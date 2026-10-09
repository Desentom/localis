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

  double? _liveTokensPerSecond;
  double? get liveTokensPerSecond => _liveTokensPerSecond;

  String? _error;
  String? get error => _error;

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

      await _refreshInstalled();

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
    final model = _activeModel;
    if (model == null || _pendingGeneration) return false;

    appendUserMessage(text);
    _streaming = '';
    _pendingGeneration = true;
    _liveTokensPerSecond = null;
    notifyListeners();

    final systemPrompt = buildSystemPrompt(
      personaPrompt: persona.prompt,
      customPrompt: _settings.customSystemPrompt,
      thinkMode: _settings.thinkMode,
      spec: model,
    );

    final buffer = StringBuffer();
    final startedAt = DateTime.now();
    GenerationStats? finalStats;

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
        }
        notifyListeners();
      }

      final finalText = buffer.toString().trim();
      final tps = finalStats?.tokensPerSecond;

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
      }
      notifyListeners();
      return true;
    } on Object catch (e) {
      // Частичный ответ не выбрасываем — человек не должен терять написанное.
      final partial = buffer.toString().trim();
      _streaming = '';
      _pendingGeneration = false;
      _liveTokensPerSecond = null;

      if (partial.isNotEmpty) {
        _session = ChatSession(
          id: _session.id,
          title: _session.title,
          messages: [
            ..._session.messages,
            ChatMessage(
              role: Role.assistant,
              text: partial,
              createdAt: DateTime.now(),
            ),
          ],
          updatedAt: DateTime.now(),
          modelId: model.id,
        );
        chatStore.save(_session);
      }
      _error = 'Ошибка генерации: $e';
      notifyListeners();
      return false;
    }
  }

  Future<void> stopGeneration() async {
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
    super.dispose();
  }
}
