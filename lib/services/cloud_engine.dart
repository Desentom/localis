import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:http/http.dart' as http;

import '../data/chat_message.dart' as app;

/// Ошибка облачного сервиса с понятным человеку текстом.
///
/// Сырые ответы Google не показываем: там коды и служебные тексты,
/// человеку от них ничего.
class CloudError implements Exception {
  CloudError(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Модели Gemini, доступные в приложении.
///
/// Список сверен с официальной документацией Google (страница обновлена
/// 9 октября 2026) — идентификаторы проверены по ней, а не по памяти.
/// Заглушка `flash-latest` намеренно не используется: она молча
/// подменяется на новую версию, а значит ответы и качество меняются без
/// предупреждения.
///
/// Порядок объявления — это порядок показа в настройках. Первым идёт
/// Flash-Lite: на бесплатном ключе лимиты маленькие, и самая дешёвая и
/// быстрая модель расходует их медленнее всего.
enum CloudModel {
  flashLite('gemini-3.5-flash-lite', 'Gemini 3.5 Flash-Lite', 'Самая экономная — меньше всего тратит бесплатный лимит'),
  flash36('gemini-3.6-flash', 'Gemini 3.6 Flash', 'Быстро и универсально'),
  flash38('gemini-3.8-flash', 'Gemini 3.8 Flash', 'Самое сильное в линейке Flash'),
  flashLite31('gemini-3.1-flash-lite', 'Gemini 3.1 Flash-Lite', 'Уровень фронтир, очень дёшево');

  const CloudModel(this.id, this.title, this.note);

  final String id;
  final String title;
  final String note;

  /// Модель по умолчанию. Совпадает с первой в списке.
  static const CloudModel fallback = flashLite;

  static CloudModel byId(String id) =>
      CloudModel.values.firstWhere((m) => m.id == id, orElse: () => fallback);
}

/// Клиент Gemini API.
///
/// Ключ не хранится в приложении: его вводит сам человек и он лежит
/// только на телефоне. Вшивать ключ в сборку нельзя — его тогда сможет
/// достать кто угодно, распаковав APK, и тратить чужую квоту.
class CloudEngine {
  CloudEngine({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  /// Отдельный клиент для текущего запроса. Отдельный — потому что
  /// остановить генерацию можно только разорвав соединение: у потока
  /// ответа нет «стоп», есть закрытый сокет.
  http.Client? _active;

  static const _base = 'https://generativelanguage.googleapis.com/v1beta/models';

  /// Сколько ждать первых байт ответа.
  static const _connectTimeout = Duration(seconds: 30);

  /// Сколько ждать следующий кусок, когда ответ уже пошёл.
  ///
  /// Без этого проверки зависает только ожидание заголовков, а дальше
  /// поток может молчать вечно: приложение выглядит «думает», кнопка
  /// «стоп» нажимается, а ответа нет. Сто секунд — дольше любой
  /// задержки между кусками на живом ответе, но короче вечного ожидания.
  static const _stallTimeout = Duration(seconds: 100);

  /// Оборвать текущий запрос, если он идёт.
  ///
  /// Вызывается кнопкой «стоп». Закрытие клиента разрывает соединение,
  /// и поток отдаёт ошибку, которую [_stream] превращает в обычное
  /// «остановлено», а не в сообщение о сбое.
  void cancel() {
    _active?.close();
    _active = null;
  }

  /// Потоковый ответ. Отдаёт куски текста, последним — [CloudDone].
  ///
  /// События повторяют форму локального движка, чтобы интерфейсу было
  /// всё равно, откуда пришёл ответ.
  Stream<CloudEvent> streamAnswer({
    required CloudModel model,
    required String apiKey,
    required String systemPrompt,
    required List<app.ChatMessage> history,
    required int maxTokens,
    double temperature = 0.7,
  }) async* {
    if (apiKey.trim().isEmpty) {
      throw CloudError(
        'Не задан ключ Gemini. Откройте «Настройки → Откуда ответ» '
        'и вставьте ключ из Google AI Studio.',
      );
    }

    final uri = Uri.parse('$_base/${model.id}:streamGenerateContent?alt=sse');

    final contents = <Map<String, dynamic>>[
      for (final m in history)
        if (m.text.trim().isNotEmpty)
          {
            'role': m.isUser ? 'user' : 'model',
            'parts': [
              {'text': m.text.trim()},
            ],
          },
    ];
    if (contents.isEmpty) {
      throw CloudError('Пустой вопрос — нечего отправлять.');
    }

    final body = <String, dynamic>{
      'contents': contents,
      if (systemPrompt.trim().isNotEmpty)
        'systemInstruction': {
          'parts': [
            {'text': systemPrompt.trim()},
          ],
        },
      'generationConfig': {
        'maxOutputTokens': maxTokens,
        'temperature': temperature,
      },
    };

    final client = _active = http.Client();
    final request = http.Request('POST', uri)
      ..headers['content-type'] = 'application/json'
      ..headers['x-goog-api-key'] = apiKey.trim()
      ..body = jsonEncode(body);

    http.StreamedResponse response;
    try {
      response = await client.send(request).timeout(_connectTimeout);
    } on TimeoutException {
      _release();
      throw CloudError(
        'Сервер не отвечает дольше 30 секунд. Проверьте интернет.',
      );
    } on http.ClientException catch (e) {
      _release();
      throw CloudError('Связь с сервером прервана: ${e.message}');
    }

    if (response.statusCode != 200) {
      final text = await response.stream.bytesToString();
      _release();
      throw CloudError(_explain(response.statusCode, text));
    }

    final started = DateTime.now();
    var chars = 0;
    var pieces = 0;

    try {
      await for (final line in response.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .timeout(
            _stallTimeout,
            onTimeout: (sink) {
              sink.addError(
                CloudError(
                  'Ответ остановился на ${_stallTimeout.inSeconds} секунд. '
                  'Сервис, скорее всего, перегружен — попробуйте ещё раз.',
                ),
              );
              sink.close();
            },
          )) {
        if (!line.startsWith('data:')) continue;
        final payload = line.substring(5).trim();
        if (payload.isEmpty || payload == '[DONE]') continue;

        final decoded = _decodeChunk(payload);
        if (decoded == null || decoded.isEmpty) continue;

        chars += decoded.length;
        pieces++;
        yield CloudText(decoded);
      }
    } on CloudError {
      _release();
      rethrow;
    } on http.ClientException {
      // Соединение закрыли мы сами — это кнопка «стоп», а не поломка.
      _release();
      throw CloudError('Остановлено.');
    } on Object catch (e) {
      _release();
      throw CloudError('Ответ прерван: $e');
    }
    _release();

    if (pieces == 0) {
      throw CloudError(
        'Сервис вернул пустой ответ. Обычно это означает, что вопрос '
        'заблокирован фильтром безопасности — попробуйте переформулировать.',
      );
    }

    yield CloudDone(CloudStats(DateTime.now().difference(started), chars, pieces));
  }

  void _release() {
    _active?.close();
    _active = null;
  }

  /// Проверка ключа: один короткий запрос к карточке модели.
  ///
  /// Нужна, чтобы человек узнал, что ключ неверен, сразу после ввода, а
  /// не после того, как потратит время на вопрос и увидит ошибку.
  /// Возвращает текст ошибки или null, если всё в порядке.
  Future<String?> checkKey({
    required CloudModel model,
    required String apiKey,
  }) async {
    if (apiKey.trim().isEmpty) return 'Ключ не введён.';

    final uri = Uri.parse('$_base/${model.id}');
    final http.Response response;
    try {
      response = await _client
          .get(uri, headers: {'x-goog-api-key': apiKey.trim()})
          .timeout(const Duration(seconds: 15));
    } on TimeoutException {
      return 'Сервер не отвечает дольше 15 секунд. Проверьте интернет.';
    } on http.ClientException catch (e) {
      return 'Связь с сервером прервана: ${e.message}';
    }

    if (response.statusCode == 200) return null;
    return _explain(response.statusCode, response.body);
  }

  /// Достаёт текст из одного куска потока. Возвращает null, если в
  /// куске нет текста: там же бывают метаданные и usage.
  @visibleForTesting
  static String? decodeChunk(String payload) => _decodeChunk(payload);

  @visibleForTesting
  static String explain(int status, String body) => _explain(status, body);

  static String? _decodeChunk(String payload) {
    try {
      final json = jsonDecode(payload);
      if (json is! Map) return null;
      final candidates = json['candidates'];
      if (candidates is! List || candidates.isEmpty) return null;
      final first = candidates.first;
      if (first is! Map) return null;
      final content = first['content'];
      if (content is! Map) return null;
      final parts = content['parts'];
      if (parts is! List) return null;

      final buf = StringBuffer();
      for (final p in parts) {
        if (p is Map && p['text'] is String) buf.write(p['text']);
      }
      final text = buf.toString();
      return text.isEmpty ? null : text;
    } on FormatException {
      return null;
    }
  }

  /// Превращает код ответа в текст, который можно показать человеку.
  static String _explain(int status, String body) {
    var detail = '';
    try {
      final json = jsonDecode(body);
      if (json is Map && json['error'] is Map) {
        final message = (json['error'] as Map)['message'];
        if (message is String) detail = message;
      }
    } on FormatException {
      // Тело не JSON — покажем обрезанный текст, он полезнее пустоты.
      detail = body.length > 200 ? '${body.substring(0, 200)}…' : body;
    }

    return switch (status) {
      400 =>
        'Ключ не принят сервером. Проверьте, что он скопирован целиком, '
            'без пробелов. ${_trim(detail)}',
      401 || 403 =>
        'Ключ отклонён. Чаще всего он недействителен или для этого ключа '
            'не включён Gemini API. ${_trim(detail)}',
      404 =>
        'Модель недоступна для этого ключа. ${_trim(detail)}',
      429 =>
        'Лимит запросов исчерпан. У бесплатного ключа он небольшой — '
            'подождите немного.',
      >= 500 => 'Сервис Google временно недоступен. Попробуйте позже.',
      _ => 'Ошибка сети: код $status. ${_trim(detail)}',
    };
  }

  static String _trim(String s) => s.trim().isEmpty ? '' : 'Подробности: ${s.trim()}';

  void close() {
    _release();
    _client.close();
  }
}

/// События облачного движка.
sealed class CloudEvent {
  const CloudEvent();
}

class CloudText extends CloudEvent {
  const CloudText(this.text);
  final String text;
}

class CloudDone extends CloudEvent {
  const CloudDone(this.stats);
  final CloudStats stats;
}

class CloudStats {
  const CloudStats(this.elapsed, this.characters, this.pieces);

  final Duration elapsed;
  final int characters;

  /// Сколько кусков пришло. Для облака это честная мера объёма работы:
  /// токены Google не отдаёт, а куски приходят пачками.
  final int pieces;

  double get charsPerSecond {
    final s = elapsed.inMilliseconds / 1000;
    return s <= 0 ? 0 : characters / s;
  }

  String get label {
    final cps = charsPerSecond;
    return '${cps.toStringAsFixed(0)} симв./с';
  }
}