import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../core/format.dart';
import '../data/chat_message.dart';
import '../data/chat_store.dart';
import '../data/chat_window.dart';
import '../data/model_spec.dart';
import '../data/personas.dart';
import '../data/settings_store.dart';
import '../services/auth_service.dart';
import '../services/cloud_engine.dart';
import '../services/device_capability.dart';
import '../services/engine_service.dart';
import '../services/model_downloader.dart';

/// Стадия приложения. Один экран на каждую — никаких «полуготовых»
/// состояний, в которых интерфейс мигает и ломается.
enum AppPhase {
  starting,
  needsModel,
  downloading,
  loadingModel,
  ready,
  failed,
}

/// Единая точка состояния. Экраны только читают и вызывают методы.
class AppController extends ChangeNotifier {
  AppController({
    required this.settingsStore,
    required this.chatStore,
    required this.downloader,
    required this.engine,
    required this.auth,
  });

  final SettingsStore settingsStore;
  final ChatStore chatStore;
  final ModelDownloader downloader;
  final EngineService engine;
  final AuthService auth;

  /// Облачный движок. Создаётся лениво: он нужен только в облачном
  /// режиме, а держать открытый HTTP-клиент без надобности незачем.
  CloudEngine? _cloud;
  CloudEngine get cloud => _cloud ??= CloudEngine();

  AppPhase _phase = AppPhase.starting;
  AppPhase get phase => _phase;

  AppSettings _settings = const AppSettings();
  AppSettings get settings => _settings;

  DeviceCapability? _capability;
  DeviceCapability? get capability => _capability;

  Map<String, int> _installed = const {};
  Map<String, int> get installed => _installed;

  ModelSpec? _activeModel;
  ModelSpec? get activeModel => _activeModel;

  LoadOutcome? _loadOutcome;
  LoadOutcome? get loadOutcome => _loadOutcome;

  DownloadState _download = const DownloadIdle();
  DownloadState get download => _download;

  ChatSession _session = ChatSession(
    id: '',
    title: 'Новый диалог',
    messages: const [],
    updatedAt: DateTime(2000),
  );
  ChatSession get session => _session;

  /// Живой текст, который модель дописывает прямо сейчас.
  String _streaming = '';
  String get streaming => _streaming;
  bool get isGenerating => _streaming.isNotEmpty || _pendingGeneration;

  bool _pendingGeneration = false;

  /// Как часто интерфейс перерисовывается во время ответа.
  ///
  /// 12 раз в секунду — чаще глаз не различает, а на слабом телефоне
  /// каждая лишняя перерисовка стоит кадра. Смысл троттлинга не в
  /// экономии, а в том, чтобы GPU успевал: не успевает — Android
  /// показывает неотрисованные тайлы, и человек видит светлый
  /// прямоугольник на месте текста.
  static const _paintIntervalMs = 1000 ~/ 12;

  /// Человек нажал «стоп». Отличаем это от поломки, чтобы не пугать
  /// сообщением об ошибке то, что он и так остановил сам.
  bool _stopped = false;

  double? _liveTokensPerSecond;
  double? get liveTokensPerSecond => _liveTokensPerSecond;

  String? _error;
  String? get error => _error;

  /// Что модель выдала в последний раз, дословно.
  ///
  /// Хранится отдельно от истории диалога и не очищается: пока ответ не
  /// удалось отобразить, это единственный способ понять, что именно
  /// вернул движок — пустая строка, мусор из переносов или нормальный
  /// текст. Показывается в отчёте о диагностике.
  String _lastRawOutput = '';
  String get lastRawOutput => _lastRawOutput;

  /// Промпт, который ушёл в движок, — тоже целиком. Берётся из движка:
  /// там он записывается в момент отправки.
  String get lastPrompt => lastPromptSent ?? '';

  int _loadStage = 0;
  int get loadStage => _loadStage;

  AccountState get account => auth.state;
  Persona get persona => Personas.byId(_settings.personaId);

  /// Модель, которую мы бы порекомендовали этому телефону.
  ModelSpec get recommendedModel {
    final ram = _capability?.freeRamBytes ?? 0;
    if (ram <= 0) return ModelCatalog.fallback;
    return ModelCatalog.recommend(ram, userPinned: _settings.modelId);
  }

  bool get isCloud => _settings.cloudMode;
  CloudModel get cloudModel => CloudModel.byId(_settings.cloudModelId);
  String get geminiKey => _settings.geminiKey;
  bool get hasApiKey => _settings.geminiKey.trim().isNotEmpty;

  /// Что показать в шапке приложения.
  String get engineTitle => isCloud
      ? hasApiKey
            ? cloudModel.title
            : 'Нужен ключ Gemini'
      : (_activeModel?.title ?? 'Модель не выбрана');

  String get engineSubtitle =>
      isCloud ? 'Через интернет' : 'Полностью на вашем телефоне · без сети';

  /// Контекст, который реально выдан движку: запрошенный, если памяти
  /// хватило, и ужатый под память — если нет.
  int get effectiveContextSize =>
      _loadOutcome?.contextSize ?? _settings.contextSize;

  /// Запуск приложения. Никогда не бросает — на любой сбой переходим
  /// в [AppPhase.failed] с понятным текстом.
  Future<void> bootstrap() async {
    _phase = AppPhase.starting;
    _error = null;
    notifyListeners();

    try {
      _settings = settingsStore.load();

      // Проба устройства нужна для рекомендации модели, но её провал
      // не должен мешать: покажем экран выбора без подсказок.
      _capability = await DeviceCapability.probe();

      await auth.initialize();

      // Старые версии каталога могли оставить на диске файлы, которых
      // в новом каталоге уже нет. Пока держим эту уборку здесь: один
      // запуск — и место освобождено навсегда.
      try {
        await downloader.purgeUnknown();
      } on Object {
        // Не смогли почистить — не повод мешать работать.
      }

      await _refreshInstalled();

      // В облачном режиме локальная модель не нужна вообще: ни памяти,
      // ни файла, ни экрана выбора. Это и есть смысл перехода — проверить
      // интерфейс и сам диалог, убрав из уравнения локальный движок.
      if (isCloud) {
        _activeModel = null;
        _loadOutcome = null;
        _phase = AppPhase.ready;
        notifyListeners();
        return;
      }

      final pinned = _settings.modelId;
      final candidate = pinned != null
          ? ModelCatalog.byId(pinned)
          : recommendedModel;

      if (_installed.containsKey(candidate.id)) {
        await _loadModel(candidate);
      } else if (_installed.isNotEmpty) {
        // Модель была, но пользователь сменил выбор — грузим любую доступную.
        final anyId = _installed.keys.first;
        await _loadModel(ModelCatalog.byId(anyId));
      } else {
        _phase = AppPhase.needsModel;
      }
    } on Object catch (e) {
      _phase = AppPhase.failed;
      _error = 'Не удалось запустить приложение: $e';
    }
    notifyListeners();
  }

  Future<void> _refreshInstalled() async {
    _installed = await downloader.installedModels();
    notifyListeners();
  }

  Future<void> _loadModel(ModelSpec spec) async {
    _activeModel = spec;
    _phase = AppPhase.loadingModel;
    _loadStage = 0;
    _error = null;
    notifyListeners();

    try {
      final path = await downloader.targetPath(spec);
      final cap = _capability;
      // Памяти может не хватить на запрошенный контекст диалога. Не
      // отказываем в запуске — ужимаем контекст до того, что телефон
      // действительно потянет. Лучше модель, которая помнит меньше, чем
      // сообщение «не хватает памяти».
      final context = ModelCatalog.fitContext(
        spec,
        cap?.freeRamBytes ?? 0,
        _settings.contextSize,
      );
      _loadOutcome = await engine.loadFromPath(
        spec,
        path,
        contextSize: context,
        requestedContext: _settings.contextSize,
        threads: cap?.cores ?? 4,
        gpuLayers: resolveGpuLayers(
          cap ?? const DeviceCapability(
            cores: 4,
            freeRamBytes: 0,
            totalRamBytes: 0,
            vulkanSupported: false,
            gpuName: '',
            recommendedGpuLayers: 0,
          ),
          spec,
        ),
        onStage: (stage) {
          _loadStage = stage;
          notifyListeners();
        },
      );
      _phase = AppPhase.ready;
    } on Object catch (e) {
      _phase = AppPhase.failed;
      // Самая частая причина падения на телефоне — не хватило памяти.
      final message = _explainLoadFailure(e);
      _error = message;
    }
    notifyListeners();
  }

  String _explainLoadFailure(Object e) {
    final text = e.toString().toLowerCase();
    if (text.contains('alloc') || text.contains('memory') || text.contains('bad_alloc')) {
      final lighter = _lighterAlternative(_activeModel);
      return lighter == null
          ? 'Не хватило оперативной памяти. Закройте несколько приложений и попробуйте снова.'
          : 'Не хватило оперативной памяти для ${_activeModel?.title}. '
                'Попробуйте модель полегче: ${lighter.title} (${formatBytes(lighter.bytes)}).';
    }
    if (text.contains('file') || text.contains('open')) {
      return 'Файл модели не найден или повреждён. Скачайте его заново.';
    }
    return 'Не удалось запустить модель: $e';
  }

  ModelSpec? _lighterAlternative(ModelSpec? current) {
    if (current == null) return null;
    final idx = ModelCatalog.all.indexOf(current);
    if (idx <= 0) return null;
    return ModelCatalog.all[idx - 1];
  }

  /// Скачать выбранную модель и сразу загрузить её в память.
  Future<void> downloadAndLoad(ModelSpec spec) async {
    _phase = AppPhase.downloading;
    _download = const DownloadIdle();
    _error = null;
    notifyListeners();

    try {
      await downloader.download(
        spec,
        onState: (state) {
          _download = state;
          notifyListeners();
        },
      );
      await _refreshInstalled();
      await _persistSettings(spec);
      await _loadModel(spec);
    } on Object catch (e) {
      _phase = AppPhase.needsModel;
      if (_error == null) {
        final text = e.toString();
        final state = _download;
        _error = state is DownloadFailed ? state.message : 'Скачивание не удалось: $text';
      }
    }
    notifyListeners();
  }

  Future<void> _persistSettings(ModelSpec spec) async {
    _settings = _settings.copyWith(modelId: spec.id);
    await settingsStore.save(_settings);
  }

  /// Сменить модель: скачать, если её ещё нет, и перезагрузить движок.
  Future<void> selectModel(ModelSpec spec) async {
    if (_installed.containsKey(spec.id)) {
      await _persistSettings(spec);
      await _loadModel(spec);
    } else {
      await downloadAndLoad(spec);
    }
  }

  Future<void> deleteModel(ModelSpec spec) async {
    await downloader.deleteModel(spec);
    if (_activeModel?.id == spec.id) {
      await engine.unload();
      _activeModel = null;
      _phase = AppPhase.needsModel;
    }
    await _refreshInstalled();
    notifyListeners();
  }

  // --- Чат ---------------------------------------------------------------

  List<ChatSession> history() => chatStore.listAll();

  Future<void> openSession(ChatSession s) async {
    _session = s;
    notifyListeners();
  }

  void startNewSession() {
    _session = ChatSession(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      title: 'Новый диалог',
      messages: const [],
      updatedAt: DateTime.now(),
    );
    notifyListeners();
  }

  void appendUserMessage(String text) {
    final clean = text.trim();
    if (clean.isEmpty) return;
    final message = ChatMessage(role: Role.user, text: clean, createdAt: DateTime.now());
    _session = ChatSession(
      id: _session.id.isEmpty
          ? DateTime.now().microsecondsSinceEpoch.toString()
          : _session.id,
      title: _session.messages.isEmpty ? ChatStore.titleFrom(clean) : _session.title,
      messages: [..._session.messages, message],
      updatedAt: DateTime.now(),
      modelId: _activeModel?.id,
    );
    notifyListeners();
  }

  /// Отправить сообщение и принять потоковый ответ.
  ///
  /// Возвращает true, если ответ получен полностью.
  Future<bool> send(String text) async {
    if (_pendingGeneration) return false;

    // В облачном режиме локальная модель не нужна — и не должна быть
    // обязательной. Поэтому проверка «модель выбрана» есть только у
    // локального пути.
    if (!isCloud && _activeModel == null) return false;

    appendUserMessage(text);
    _streaming = '';
    _pendingGeneration = true;
    _liveTokensPerSecond = null;
    notifyListeners();

    if (isCloud) {
      return _askCloud(text);
    }
    return _askLocal(text);
  }

  /// Путь через Gemini.
  Future<bool> _askCloud(String question) async {
    final buffer = StringBuffer();
    final startedAt = DateTime.now();
    String? failure;
    _lastRawOutput = '';
    _stopped = false;

    final systemPrompt = buildSystemPrompt(
      personaPrompt: persona.prompt,
      customPrompt: _settings.customSystemPrompt,
      thinkMode: _settings.thinkMode,
      spec: null,
    );

    // Перерисовка на каждом куске — главная причина «серых тайлов» на
    // слабом телефоне. Google шлёт куски часто, и каждый вызов
    // notifyListeners() перестраивает весь список сообщений. Раньше на
    // слабом GPU растеризация не успевала, и Android показывал
    // неотрисованные прямоугольники. Поэтому интерфейс обновляется не
    // чаще 12 раз в секунду — глаз эту разницу не видит, а кадров
    // тратится в четыре раза меньше.
    var lastPaint = DateTime.fromMillisecondsSinceEpoch(0);

    try {
      final stream = cloud.streamAnswer(
        model: cloudModel,
        apiKey: geminiKey,
        systemPrompt: systemPrompt,
        history: _session.messages,
        maxTokens: _settings.maxTokens,
        temperature: _settings.temperature,
      );

      await for (final event in stream) {
        switch (event) {
          case CloudText(:final text):
            buffer.write(text);
            _streaming = buffer.toString();
            final seconds =
                DateTime.now().difference(startedAt).inMilliseconds / 1000;
            if (seconds > 0.2) _liveTokensPerSecond = buffer.length / seconds;
          case CloudDone(:final stats):
            _cloudStats = stats;
        }
        final now = DateTime.now();
        if (now.difference(lastPaint).inMilliseconds >= _paintIntervalMs) {
          lastPaint = now;
          notifyListeners();
        }
      }

      final text = buffer.toString().trim();
      _lastRawOutput = buffer.toString();
      _streaming = '';
      _pendingGeneration = false;
      _liveTokensPerSecond = null;

      if (text.isNotEmpty) {
        _appendAssistant(text, _cloudStats?.charsPerSecond ?? 0);
      } else if (_stopped) {
        // Человек нажал «стоп» — это не ошибка, показывать нечего.
        _error = null;
      } else {
        failure ??= 'Сервис вернул пустой ответ.';
      }
      _error = failure;
      notifyListeners();
      return failure == null;
    } on CloudError catch (e) {
      _lastRawOutput = buffer.toString();
      _streaming = '';
      _pendingGeneration = false;
      _liveTokensPerSecond = null;
      // «Остановлено» — это следствие нажатия «стоп», а не поломка.
      _error = _stopped ? null : e.message;
      notifyListeners();
      return false;
    } on Object catch (e) {
      _streaming = '';
      _pendingGeneration = false;
      _liveTokensPerSecond = null;
      _error = _stopped ? null : 'Ошибка сети: $e';
      notifyListeners();
      return false;
    }
  }

  CloudStats? _cloudStats;

  /// Облачный клиент доступен и контроллеру, и экрану настроек: там
  /// ключ проверяется до первого вопроса.
  CloudEngine get cloudClient => cloud;

  void _appendAssistant(String text, double charsPerSecond) {
    _session = ChatSession(
      id: _session.id,
      title: _session.title,
      messages: [
        ..._session.messages,
        ChatMessage(
          role: Role.assistant,
          text: text,
          createdAt: DateTime.now(),
          tokensPerSecond: charsPerSecond,
        ),
      ],
      updatedAt: DateTime.now(),
      modelId: cloudModel.id,
    );
    chatStore.save(_session);
    settingsStore.rememberChatState(_session);
  }

  /// Путь через локальную модель на телефоне.
  Future<bool> _askLocal(String question) async {
    final model = _activeModel!;
    final startedAt = DateTime.now();
    final systemPrompt = buildSystemPrompt(
      personaPrompt: persona.prompt,
      customPrompt: _settings.customSystemPrompt,
      thinkMode: _settings.thinkMode,
      spec: model,
    );

    final buffer = StringBuffer();
    GenerationStats? finalStats;
    String? failure;
    _lastRawOutput = '';

    // Ответ не должен занимать весь контекст: место нужно ещё на вопрос
    // и историю диалога. На ужатом под память контексте запрошенная
    // длина ответа была бы просто невозможной.
    final answerTokens = min(
      _settings.maxTokens,
      max(256, (effectiveContextSize * 0.6).round()),
    );

    try {
      final stream = engine.streamAnswer(
        spec: model,
        history: ChatWindow.trim(
          history: _session.messages,
          contextTokens: effectiveContextSize,
          reserveTokens: answerTokens,
        ),
        systemPrompt: systemPrompt,
        temperature: _settings.temperature,
        topP: _settings.topP,
        topK: _settings.topK,
        repeatPenalty: _settings.repeatPenalty,
        maxTokens: answerTokens,
      );

      await for (final event in stream) {
        switch (event) {
          case GenText(:final text):
            buffer.write(text);
            _streaming = buffer.toString();
            // Во время генерации движок не отдаёт число токенов, поэтому
            // показываем скорость в символах — метрика честная в любом случае.
            final seconds = DateTime.now().difference(startedAt).inMilliseconds / 1000;
            if (seconds > 0.2) {
              _liveTokensPerSecond = buffer.length / seconds;
            }
          case GenDone(:final stats):
            finalStats = stats;
          case GenFailed(:final reason):
            failure = reason;
        }
        notifyListeners();
      }

      final finalText = buffer.toString().trim();
      final tps = finalStats?.tokensPerSecond;
      _lastRawOutput = buffer.toString();

      _streaming = '';
      _pendingGeneration = false;
      _liveTokensPerSecond = null;

      if (finalText.isNotEmpty) {
        _session = ChatSession(
          id: _session.id,
          title: _session.title,
          messages: [
            ..._session.messages,
            ChatMessage(
              role: Role.assistant,
              text: finalText,
              createdAt: DateTime.now(),
              tokensPerSecond: tps,
            ),
          ],
          updatedAt: DateTime.now(),
          modelId: model.id,
        );
        chatStore.save(_session);
        settingsStore.rememberChatState(_session);
      } else {
        // Модель ответила одними переносами и пробелами. Такой «ответ»
        // не должен попадать в историю: он превращается в пустой серый
        // прямоугольник и засоряет диалог.
        failure ??= 'Модель не выдала ни одного слова — только пробелы. '
            'Скорее всего, она не поняла формат диалога.';
      }
      _error = failure;
      notifyListeners();
      return failure == null;
    } on Object catch (e) {
      // Частичный ответ не выбрасываем — человек не должен терять написанное.
      final partial = buffer.toString().trim();
      _streaming = '';
      _pendingGeneration = false;
      _liveTokensPerSecond = null;

      if (partial.isNotEmpty) {
        _appendAssistant(partial, 0);
      }
      _error = 'Ошибка генерации: $e';
      notifyListeners();
      return false;
    }
  }

  Future<void> stopGeneration() async {
    _stopped = true;
    if (isCloud) {
      // У потока ответа нет «стоп» — соединение надо разорвать.
      cloud.cancel();
      return;
    }
    await engine.stop();
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }

  // --- Настройки ---------------------------------------------------------

  Future<void> updateSettings(AppSettings next) async {
    final needsReload =
        next.contextSize != _settings.contextSize ||
        next.threads != _settings.threads;
    _settings = next;
    await settingsStore.save(next);
    notifyListeners();

    // Контекст и число потоков задаются только при загрузке модели.
    if (needsReload && _activeModel != null) {
      await _loadModel(_activeModel!);
    }
  }

  @override
  void dispose() {
    downloader.close();
    engine.dispose();
    _cloud?.close();
    super.dispose();
  }
}
