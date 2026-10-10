import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'chat_message.dart';

/// Настройки пользователя. Всё локально, ничего никуда не отправляется.
class AppSettings {
  const AppSettings({
    this.modelId,
    this.personaId = 'default',
    this.customSystemPrompt = '',
    this.temperature = 0.7,
    this.topP = 0.9,
    this.topK = 40,
    this.repeatPenalty = 1.1,
    this.maxTokens = 1024,
    this.contextSize = 4096,
    this.threads = 0,
    this.thinkMode = false,
    this.onboardingSeen = false,
    this.cloudMode = true,
    this.geminiKey = '',
    this.cloudModelId = 'gemini-3.5-flash-lite',
  });

  /// null = подбирать автоматически по телефону.
  final String? modelId;

  /// Пресет поведения: короткие ответы, объяснения, школьный помощник и т.п.
  final String personaId;
  final String customSystemPrompt;

  final double temperature;
  final double topP;
  final int topK;
  final double repeatPenalty;
  final int maxTokens;
  final int contextSize;

  /// 0 = определить автоматически по числу ядер.
  final int threads;

  /// Режим «подумать» у Qwen3. Заметно медленнее, но меньше ошибок.
  final bool thinkMode;

  final bool onboardingSeen;

  /// Отвечать через облако, а не через локальную модель.
  ///
  /// Включено по умолчанию. Локальный движок на телефоне не прошёл
  /// проверку: на восьми попытках модель либо выдавала пустоту, либо не
  /// отвечала вовсе. Облако работает предсказуемо, и именно на нём
  /// сейчас проверяется интерфейс — после этого локальный режим можно
  /// будет чинить.
  final bool cloudMode;

  /// Ключ Gemini. Вводится человеком, хранится только на телефоне и
  /// уходит ровно в одно место — на серверы Google.
  final String geminiKey;

  final String cloudModelId;

  /// Число потоков вычислений. 0 = «определи по телефону» — фактическое
  /// количество ядер знает DeviceCapability, а не эта настройка.
  int get resolvedThreads => threads > 0 ? threads : 4;

  AppSettings copyWith({
    String? modelId,
    bool clearModelId = false,
    String? personaId,
    String? customSystemPrompt,
    double? temperature,
    double? topP,
    int? topK,
    double? repeatPenalty,
    int? maxTokens,
    int? contextSize,
    int? threads,
    bool? thinkMode,
    bool? onboardingSeen,
    bool? cloudMode,
    String? geminiKey,
    String? cloudModelId,
  }) => AppSettings(
    modelId: clearModelId ? null : (modelId ?? this.modelId),
    personaId: personaId ?? this.personaId,
    customSystemPrompt: customSystemPrompt ?? this.customSystemPrompt,
    temperature: temperature ?? this.temperature,
    topP: topP ?? this.topP,
    topK: topK ?? this.topK,
    repeatPenalty: repeatPenalty ?? this.repeatPenalty,
    maxTokens: maxTokens ?? this.maxTokens,
    contextSize: contextSize ?? this.contextSize,
    threads: threads ?? this.threads,
    thinkMode: thinkMode ?? this.thinkMode,
    onboardingSeen: onboardingSeen ?? this.onboardingSeen,
    cloudMode: cloudMode ?? this.cloudMode,
    geminiKey: geminiKey ?? this.geminiKey,
    cloudModelId: cloudModelId ?? this.cloudModelId,
  );

  Map<String, dynamic> toJson() => {
    if (modelId != null) 'modelId': modelId,
    'personaId': personaId,
    'customSystemPrompt': customSystemPrompt,
    'temperature': temperature,
    'topP': topP,
    'topK': topK,
    'repeatPenalty': repeatPenalty,
    'maxTokens': maxTokens,
    'contextSize': contextSize,
    'threads': threads,
    'thinkMode': thinkMode,
    'onboardingSeen': onboardingSeen,
    'cloudMode': cloudMode,
    'geminiKey': geminiKey,
    'cloudModelId': cloudModelId,
  };

  static AppSettings fromJson(Map<String, dynamic> j) => AppSettings(
    modelId: j['modelId'] as String?,
    personaId: j['personaId'] as String? ?? 'default',
    customSystemPrompt: j['customSystemPrompt'] as String? ?? '',
    temperature: (j['temperature'] as num?)?.toDouble() ?? 0.7,
    topP: (j['topP'] as num?)?.toDouble() ?? 0.9,
    topK: (j['topK'] as num?)?.toInt() ?? 40,
    repeatPenalty: (j['repeatPenalty'] as num?)?.toDouble() ?? 1.1,
    maxTokens: (j['maxTokens'] as num?)?.toInt() ?? 1024,
    contextSize: (j['contextSize'] as num?)?.toInt() ?? 4096,
    threads: (j['threads'] as num?)?.toInt() ?? 0,
    thinkMode: j['thinkMode'] as bool? ?? false,
    onboardingSeen: j['onboardingSeen'] as bool? ?? false,
    cloudMode: j['cloudMode'] as bool? ?? true,
    geminiKey: j['geminiKey'] as String? ?? '',
    cloudModelId: j['cloudModelId'] as String? ?? 'gemini-3.5-flash-lite',
  );

  Map<String, dynamic> toCache() => toJson();

  static AppSettings fromCache(String raw) =>
      fromJson(jsonDecode(raw) as Map<String, dynamic>);
}

class SettingsStore {
  SettingsStore(this._prefs);

  final SharedPreferences _prefs;

  static const _key = 'localis.settings.v1';

  static Future<SettingsStore> open() async =>
      SettingsStore(await SharedPreferences.getInstance());

  AppSettings load() {
    final raw = _prefs.getString(_key);
    if (raw == null) return const AppSettings();
    try {
      return AppSettings.fromCache(raw);
    } on FormatException {
      // Битые настройки не должны ронять приложение при старте.
      return const AppSettings();
    }
  }

  Future<void> save(AppSettings s) async {
    final encoded = jsonEncode(s.toJson());
    final ok = await _prefs.setString(_key, encoded);
    if (!ok) {
      throw StateError('Не удалось записать настройки в SharedPreferences');
    }
  }

  /// Последняя выбранная модель — чтобы после перезапуска не грузить заново
  /// ту, которую человек закрыл вручную.
  void rememberChatState(ChatSession session) {
    _prefs.setString('localis.lastSessionId', session.id);
  }

  String? lastSessionId() => _prefs.getString('localis.lastSessionId');

  /// Не отправляем краш-репорты по умолчанию, пока человек не согласился.
  bool get crashReportsEnabled =>
      _prefs.getBool('localis.crashReports') ?? false;

  Future<void> setCrashReportsEnabled(bool value) =>
      _prefs.setBool('localis.crashReports', value);
}
