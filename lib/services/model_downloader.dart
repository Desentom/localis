import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../data/model_spec.dart';

/// Состояние загрузки модели.
sealed class DownloadState {
  const DownloadState();
}

class DownloadIdle extends DownloadState {
  const DownloadIdle();
}

class DownloadRunning extends DownloadState {
  const DownloadRunning({
    required this.received,
    required this.total,
    required this.bytesPerSecond,
  });

  final int received;
  final int total;
  final double bytesPerSecond;

  double get progress => total > 0 ? received / total : 0;
}

class DownloadVerifying extends DownloadState {
  const DownloadVerifying(this.path);
  final String path;
}

class DownloadDone extends DownloadState {
  const DownloadDone(this.path, this.wasResumed);
  final String path;
  final bool wasResumed;
}

class DownloadFailed extends DownloadState {
  const DownloadFailed(this.message, {this.retryable = true});
  final String message;
  final bool retryable;
}

/// Скачивает GGUF-файл модели с докачкой, проверкой целостности и
/// атомарным переименованием.
///
/// Докачка обязательна: файл весит 0.4–2.5 ГБ, обрыв связи на мобильном
/// интернете случается постоянно, и заставлять человека начинать заново
/// недопустимо.
class ModelDownloader {
  ModelDownloader({http.Client? client, this.onState})
    : _client = client ?? http.Client();

  final http.Client _client;
  final void Function(DownloadState)? onState;

  static const _maxAttempts = 5;
  static const _chunkTimeout = Duration(seconds: 60);

  Future<Directory> modelsDir() async {
    final support = await getApplicationSupportDirectory();
    final dir = Directory('${support.path}/models');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return dir;
  }

  /// Путь, который используется при загрузке модели.
  Future<String> targetPath(ModelSpec spec) async =>
      '${(await modelsDir()).path}/${spec.fileName}';

  /// Файл уже скачан целиком?
  Future<bool> isInstalled(ModelSpec spec) async {
    final file = File(await targetPath(spec));
    if (!file.existsSync()) return false;
    return await file.length() == spec.bytes;
  }

  /// Какие модели лежат на устройстве: id -> размер в байтах.
  Future<Map<String, int>> installedModels() async {
    final dir = await modelsDir();
    final result = <String, int>{};
    for (final spec in ModelCatalog.all) {
      final file = File('${dir.path}/${spec.fileName}');
      if (file.existsSync()) {
        final len = await file.length();
        if (len == spec.bytes) result[spec.id] = len;
      }
    }
    return result;
  }

  /// Сколько байт на диске занято моделями.
  Future<int> usedBytes() async {
    final dir = await modelsDir();
    var total = 0;
    await for (final e in dir.list()) {
      if (e is File) total += await e.length();
    }
    return total;
  }

  Future<void> deleteModel(ModelSpec spec) async {
    final file = File(await targetPath(spec));
    if (file.existsSync()) await file.delete();
  }

  /// Скачать модель. Бросает [DownloadFailed]-подобное исключение через
  /// [DownloadFailed]-состояние и rethrow — вызывающий сам решает, что делать.
  Future<String> download(
    ModelSpec spec, {
    void Function(DownloadState)? onState,
  }) async {
    final emit = onState ?? this.onState;
    final target = await targetPath(spec);
    final part = File('$target.part');

    var attempts = 0;
    while (attempts < _maxAttempts) {
      attempts++;
      try {
        return await _attemptDownload(spec, target, part, emit);
      } on SocketException {
        if (attempts == _maxAttempts) {
          const msg = 'Связь пропала. Проверьте интернет и попробуйте снова.';
          emit?.call(const DownloadFailed(msg));
          throw StateError(msg);
        }
        // Пауза с экспоненциальной задержкой: сеть могла «отдохнуть».
        await Future<void>.delayed(Duration(seconds: 1 << (attempts - 1)));
      } on http.ClientException {
        if (attempts == _maxAttempts) {
          const msg = 'Сервер прервал загрузку. Попробуйте позже.';
          emit?.call(const DownloadFailed(msg));
          throw StateError(msg);
        }
        await Future<void>.delayed(Duration(seconds: 1 << (attempts - 1)));
      }
      // e.toString() не выводим пользователю: там сырые исключения с URL.
    }
    throw StateError('Загрузка не удалась после $_maxAttempts попыток');
  }

  Future<String> _attemptDownload(
    ModelSpec spec,
    String target,
    File part,
    void Function(DownloadState)? emit,
  ) async {
    final already = part.existsSync() ? await part.length() : 0;
    if (already > spec.bytes) {
      // Файл больше ожидаемого — версия на сервере изменилась. Начинаем заново.
      await part.delete();
    }

    final startAt = already > 0 ? already : 0;
    final request = http.Request('GET', Uri.parse(spec.url));
    if (startAt > 0) request.headers['Range'] = 'bytes=$startAt-';

    final response = await _client.send(request).timeout(_chunkTimeout);
    if (response.statusCode != 200 && response.statusCode != 206) {
      await response.stream.drain<void>();
      throw http.ClientException('HTTP ${response.statusCode}', Uri.parse(spec.url));
    }

    // Сервер проигнорировал Range и прислал файл целиком — начинаем заново,
    // иначе получим склейку из двух копий.
    final resumed = response.statusCode == 206;
    if (startAt > 0 && !resumed) await part.delete();

    final total = resumed
        ? startAt + (int.tryParse(response.headers['content-length'] ?? '') ?? spec.bytes - startAt)
        : spec.bytes;

    final sink = part.openWrite(mode: resumed ? FileMode.append : FileMode.write);
    var received = resumed ? startAt : 0;
    var lastTick = DateTime.now();
    var lastBytes = received;

    emit?.call(
      DownloadRunning(received: received, total: total, bytesPerSecond: 0),
    );

    try {
      await for (final chunk in response.stream.timeout(_chunkTimeout)) {
        sink.add(chunk);
        received += chunk.length;
        final now = DateTime.now();
        final elapsed = now.difference(lastTick).inMilliseconds;
        if (elapsed >= 400) {
          final speed = (received - lastBytes) / (elapsed / 1000);
          emit?.call(
            DownloadRunning(
              received: received,
              total: total,
              bytesPerSecond: speed.toDouble(),
            ),
          );
          lastTick = now;
          lastBytes = received;
        }
      }
    } finally {
      await sink.flush();
      await sink.close();
    }

    emit?.call(DownloadRunning(received: received, total: total, bytesPerSecond: 0));

    final finalLength = await part.length();
    if (finalLength != spec.bytes) {
      final msg =
          'Файл докачался не полностью ($finalLength из ${spec.bytes} байт).';
      emit?.call(DownloadFailed(msg));
      throw SocketException(msg);
    }

    final hash = spec.sha256;
    if (hash != null) {
      emit?.call(DownloadVerifying(target));
      final actual = await sha256OfFile(part);
      if (actual.toLowerCase() != hash.toLowerCase()) {
        await part.delete();
        const msg = 'Контрольная сумма не сошлась — файл удалён, скачайте заново.';
        emit?.call(const DownloadFailed(msg, retryable: true));
        throw StateError(msg);
      }
    }

    final out = File(target);
    if (out.existsSync()) await out.delete();
    await part.rename(target);

    emit?.call(DownloadDone(target, resumed));
    return target;
  }

  Future<String> sha256OfFile(File file) async {
    final digest = await sha256.bind(file.openRead()).first;
    return digest.toString();
  }

  void close() => _client.close();
}

/// Канал к нативной части: там один метод — сколько свободно на диске.
/// Без него нельзя честно предупредить «нужно 4 ГБ, есть 1.2 ГБ».
abstract final class DeviceStorage {
  static const _channel = MethodChannel('localis/device');

  static Future<int?> freeBytes(String path) async {
    try {
      final value = await _channel.invokeMethod<int>('freeBytes', {'path': path});
      return value;
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }
}
