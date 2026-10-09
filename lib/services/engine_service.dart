import 'dart:async';

import 'package:llama_flutter_android/llama_flutter_android.dart' as llama;

import '../data/chat_message.dart' as app;
import '../data/model_spec.dart';
import 'device_capability.dart';

/// Как закончилась генерация.
enum FinishReason { completed, stopped, error }

class GenerationStats {
  const GenerationStats({
    required this.reason,
    required this.elapsed,
    required this.characters,
    required this.tokens,
    required this.tokensAreExact,
  });

  final FinishReason reason;
  final Duration elapsed;
  final int characters;

  /// null — посчитать не удалось, показывать символы вместо токенов.
  final int? tokens;

  /// true — число токенов снято с контекста движка, false — эвристика.
  final bool tokensAreExact;

  /// Токенов в секунду, если известны. Иначе null.
  double? get tokensPerSecond {
    final t = tokens;
    if (t == null) return null;
    final s = elapsed.inMilliseconds / 1000;
    if (s <= 0) return null;
    return t / s;
  }

  /// Запасная метрика — скорость в символах. Считается чем угодно,
  /// в отличие от токенов, и потому никогда не пропадёт.
  double get charsPerSecond {
    final s = elapsed.inMilliseconds / 1000;
    if (s <= 0) return 0;
    return characters / s;
  }

  /// Что показать пользователю в одну строку.
  String get label {
    final tps = tokensPerSecond;
    if (tps != null) {
      final prefix = tokensAreExact ? '' : '≈';
      return '$prefix${tps.toStringAsFixed(1).replaceAll('.', ',')} ток/с';
    }
    return '${charsPerSecond.toStringAsFixed(0)} симв./с';
  }
}

/// Событие генерации: кусок текста либо финальная статистика.
sealed class GenEvent {
  const GenEvent();
}

class GenText extends GenEvent {
  const GenText(this.text);
  final String text;
}

class GenDone extends GenEvent {
  const GenDone(this.stats);
  final GenerationStats stats;
}

class LoadOutcome {
  const LoadOutcome({
    required this.spec,
    required this.loadedIn,
    required this.gpuLayers,
  });

  final ModelSpec spec;
  final Duration loadedIn;
  final int gpuLayers;

  bool get usedGpu => gpuLayers > 0;
}

/// Обёртка над нативным движком.
///
/// Сюда намеренно спущены ВСЕ вызовы плагина. При обновлении llama.cpp
/// сигнатуры едут здесь — правится один файл, а не весь проект.
class EngineService {
  EngineService({llama.LlamaController? controller})
    : _controller = controller ?? llama.LlamaController();

  final llama.LlamaController _controller;

  ModelSpec? _loaded;
  bool _stopRequested = false;

  ModelSpec? get loadedModel => _loaded;
  bool get isReady => _loaded != null;

  /// Стадии загрузки — показываются текстом под индикатором.
  static const loadStages = <String>[
    'Читаем файл модели с диска',
    'Инициализируем вычислительный граф',
    'Готовим контекст диалога',
  ];

  /// Загрузка модели.
  ///
  /// Важная деталь: плагин бросает `StateError('Model already loaded')`, если
  /// модель уже в памяти. Поэтому перед повторной загрузкой модель обязательно
  /// выгружается — иначе смена модели в настройках падала бы с ошибкой.
  Future<LoadOutcome> loadFromPath(
    ModelSpec spec,
    String path, {
    required int contextSize,
    required int threads,
    required int gpuLayers,
    void Function(int stage)? onStage,
  }) async {
    onStage?.call(0);

    if (await _controller.isModelLoaded()) {
      onStage?.call(0);
      await _controller.stop();
      await _controller.dispose();
      onStage?.call(1);
    }

    final started = DateTime.now();
    await _controller.loadModel(
      modelPath: path,
      threads: threads,
      contextSize: contextSize,
      gpuLayers: gpuLayers,
    );

    onStage?.call(1);
    await _controller.clearContext();
    onStage?.call(2);

    final outcome = LoadOutcome(
      spec: spec,
      loadedIn: DateTime.now().difference(started),
      gpuLayers: gpuLayers,
    );
    _loaded = spec;
    return outcome;
  }

  /// Потоковая генерация ответа по диалогу.
  ///
  /// События идут в таком порядке: куски текста ([GenText]), а последним
  /// обязательно [GenDone] с метриками. Останавливать можно на любом
  /// кадре — поток просто закроется, а статистика придёт с причиной stopped.
  Stream<GenEvent> streamAnswer({
    required ModelSpec spec,
    required List<app.ChatMessage> history,
    required String systemPrompt,
    required double temperature,
    required double topP,
    required int topK,
    required double repeatPenalty,
    required int maxTokens,
  }) async* {
    _stopRequested = false;
    final started = DateTime.now();
    final before = await _contextTokens();

    var chars = 0;

    final messages = <llama.ChatMessage>[
      if (systemPrompt.trim().isNotEmpty)
        llama.ChatMessage(role: 'system', content: systemPrompt.trim()),
      ...history.map((m) => llama.ChatMessage(role: m.role.wire, content: m.text)),
    ];

    // Плагин бросает StateError, если генерация уже идёт. Мы к этому
    // готовы: интерфейс не даёт отправить второе сообщение, пока идёт первое.
    final stream = _controller.generateChat(
      messages: messages,
      template: chatTemplateFor(spec),
      maxTokens: maxTokens,
      temperature: temperature,
      topP: topP,
      topK: topK,
      repeatPenalty: repeatPenalty,
    );

    await for (final piece in stream) {
      if (piece.isEmpty) continue;
      chars += piece.length;
      yield GenText(piece);
    }

    final after = await _contextTokens();
    final exact = (after != null && before != null) ? after - before : null;
    // Эвристика: в русском тексте в среднем около трёх символов на токен.
    final heuristic = (chars / 3).round();

    yield GenDone(
      GenerationStats(
        reason: _stopRequested ? FinishReason.stopped : FinishReason.completed,
        elapsed: DateTime.now().difference(started),
        characters: chars,
        tokens: exact ?? heuristic,
        tokensAreExact: exact != null,
      ),
    );
  }

  /// Остановить генерацию. Плагин закроет поток, а статистика придёт с
  /// причиной stopped — иначе интерфейс показал бы «готово» на обрезанном
  /// ответе и человек подумал бы, что модель просто не договорила.
  Future<void> stop() async {
    _stopRequested = true;
    try {
      await _controller.stop();
    } on Object {
      // Остановка не должна бросать: пользователь уже ушёл с экрана.
    }
  }

  Future<void> unload() async {
    await stop();
    try {
      if (await _controller.isModelLoaded()) await _controller.dispose();
    } on Object {
      // Уже выгружено — ничего страшного.
    }
    _loaded = null;
  }

  void dispose() {
    try {
      _controller.dispose();
    } on Object {
      // Выгрузка при закрытии приложения не должна бросать.
    }
  }

  /// Сколько токенов занято в контексте. Метрика не должна ломать генерацию,
  /// поэтому любая ошибка молча превращается в null.
  Future<int?> _contextTokens() async {
    try {
      final info = await _controller.getContextInfo();
      return info.tokensUsed;
    } on Object {
      return null;
    }
  }
}

/// Шаблон диалога. Qwen2.5 и Qwen3 используют ChatML.
String chatTemplateFor(ModelSpec spec) => 'chatml';

/// Сборка системной подсказки из пресета и пользовательского текста.
String buildSystemPrompt({
  required String personaPrompt,
  required String customPrompt,
  required bool thinkMode,
  required ModelSpec? spec,
}) {
  final parts = <String>[
    personaPrompt.trim(),
    if (thinkMode)
      'Сначала разбери задачу про себя и не выводи ход рассуждений в ответ. '
          'Если задача многошаговая — кратко назови план, потом дай итог.',
    if (spec != null)
      'Ты работаешь на устройстве пользователя без интернета, поэтому не '
          'ссылайся на сайты, поиск и события после даты твоего обучения. '
          'Если данных не хватает — прямо скажи об этом.',
    customPrompt.trim(),
  ];
  return parts.where((p) => p.isNotEmpty).join('\n\n');
}

/// Рекомендованное число GPU-слоёв с учётом подсказки плагина.
int resolveGpuLayers(DeviceCapability cap, ModelSpec spec) {
  if (!cap.vulkanSupported) return 0;
  if (cap.freeRamBytes == 0) return 0;
  // Модель целиком в памяти GPU на телефоне — верный путь к OOM.
  if (cap.freeRamBytes < spec.minFreeRamBytes) return 0;
  return cap.recommendedGpuLayers;
}
