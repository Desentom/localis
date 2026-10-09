/// Каталог моделей. Все URL и размеры проверены по HTTP Range-запросу
/// (сентябрь 2026). Перед релизом прогнать `tool/verify_models.ps1`,
/// он посчитает sha256 и подставит значения в поле `sha256`.
library;

/// Класс модели. Определяет и рекомендацию по телефону, и подпись в UI.
enum ModelTier {
  /// ~0.4 ГБ. Быстро, но отвечает поверхностно.
  light,

  /// ~1.1 ГБ. Рабочая лошадка: лучшее соотношение скорость/качество.
  balanced,

  /// ~2 ГБ. Заметно разумнее, но требует 4+ ГБ свободной памяти.
  quality,

  /// ~2.5 ГБ. Максимум разумного для телефона.
  strong,
}

class ModelSpec {
  const ModelSpec({
    required this.id,
    required this.title,
    required this.params,
    required this.tier,
    required this.bytes,
    required this.url,
    required this.fileName,
    required this.minFreeRamBytes,
    required this.speedHint,
    required this.summary,
    this.sha256,
  });

  /// Короткий идентификатор для настроек и имён файлов.
  final String id;

  /// Название в интерфейсе.
  final String title;

  /// Размер в параметрах, как в оригинале: «1.7B».
  final String params;

  final ModelTier tier;

  /// Точный размер файла GGUF в байтах.
  final int bytes;

  final String url;
  final String fileName;

  /// Сколько свободной оперативной памяти нужно, чтобы не вылететь.
  final int minFreeRamBytes;

  /// Честная оценка скорости для телефона среднего класса.
  /// Показывается пользователю ДО скачивания — это защита от плохих отзывов.
  final String speedHint;

  /// Пара строк о том, что модель умеет и чего не умеет.
  final String summary;

  /// null = контрольная сумма не зафиксирована. См. tool/verify_models.ps1.
  final String? sha256;

  /// Нужно ли свободное место с запасом (сама модель + временный файл).
  int get requiredFreeSpace => bytes * 2;

  bool isInstalledAs(int fileSize) => fileSize == bytes;
}

abstract final class ModelCatalog {
  static const qwen3_0_6b = ModelSpec(
    id: 'qwen3-0.6b-q4km',
    title: 'Qwen3 0.6B',
    params: '0.6B',
    tier: ModelTier.light,
    bytes: 396705472,
    url: 'https://huggingface.co/unsloth/Qwen3-0.6B-GGUF/resolve/main/Qwen3-0.6B-Q4_K_M.gguf',
    fileName: 'Qwen3-0.6B-Q4_K_M.gguf',
    minFreeRamBytes: 2 * 1024 * 1024 * 1024,
    speedHint: '20–35 ток/с',
    summary:
        'Самая лёгкая. Быстрые короткие ответы, простая арифметика, '
        'переводы, определения. Длинные тексты и рассуждения — нет.',
  );

  static const qwen3_1_7b = ModelSpec(
    id: 'qwen3-1.7b-q4km',
    title: 'Qwen3 1.7B',
    params: '1.7B',
    tier: ModelTier.balanced,
    bytes: 1107409472,
    url: 'https://huggingface.co/unsloth/Qwen3-1.7B-GGUF/resolve/main/Qwen3-1.7B-Q4_K_M.gguf',
    fileName: 'Qwen3-1.7B-Q4_K_M.gguf',
    minFreeRamBytes: 3 * 1024 * 1024 * 1024,
    speedHint: '8–18 ток/с',
    summary:
        'Рекомендуемая по умолчанию. Русский понимает заметно лучше мелких '
        'моделей, тянет объяснения, конспекты, короткие эссе и код.',
  );

  static const qwen25_3b = ModelSpec(
    id: 'qwen2.5-3b-q4km',
    title: 'Qwen2.5 3B',
    params: '3B',
    tier: ModelTier.quality,
    bytes: 2104932768,
    url: 'https://huggingface.co/Qwen/Qwen2.5-3B-Instruct-GGUF/resolve/main/qwen2.5-3b-instruct-q4_k_m.gguf',
    fileName: 'qwen2.5-3b-instruct-q4_k_m.gguf',
    minFreeRamBytes: 4 * 1024 * 1024 * 1024,
    speedHint: '4–9 ток/с',
    summary:
        'Официальная модель Qwen, самая связная речь из доступных. Есть '
        'режим «думать»: включается отдельным пресетом и отвечает медленнее, '
        'но на задачах вроде уравнений заметно меньше ошибок.',
  );

  static const qwen3_4b = ModelSpec(
    id: 'qwen3-4b-q4km',
    title: 'Qwen3 4B',
    params: '4B',
    tier: ModelTier.strong,
    bytes: 2497281312,
    url: 'https://huggingface.co/unsloth/Qwen3-4B-GGUF/resolve/main/Qwen3-4B-Q4_K_M.gguf',
    fileName: 'Qwen3-4B-Q4_K_M.gguf',
    minFreeRamBytes: 5 * 1024 * 1024 * 1024,
    speedHint: '2–6 ток/с',
    summary:
        'Максимум, что осмысленно тащить на телефон. Реально комфортно '
        'только на флагманах с 8+ ГБ памяти — на средних будет медленно.',
  );

  /// Порядок важен: от лёгкой к тяжёлой.
  static const all = <ModelSpec>[qwen3_0_6b, qwen3_1_7b, qwen25_3b, qwen3_4b];

  static ModelSpec byId(String id) =>
      all.firstWhere((m) => m.id == id, orElse: () => qwen3_1_7b);

  /// Модель по умолчанию.
  static const fallback = qwen3_1_7b;

  /// Подбор по свободной оперативной памяти. Показываем максимум того,
  /// что телефон потянет, но не прыгаем выше userPinned, если он задан.
  static ModelSpec recommend(int freeRamBytes, {String? userPinned}) {
    if (userPinned != null) return byId(userPinned);
    ModelSpec? best;
    for (final m in all) {
      if (freeRamBytes >= m.minFreeRamBytes) best = m;
    }
    return best ?? all.first;
  }

  static String tierLabel(ModelTier tier) => switch (tier) {
    ModelTier.light => 'Лёгкая',
    ModelTier.balanced => 'Базовая',
    ModelTier.quality => 'Качественная',
    ModelTier.strong => 'Максимум',
  };
}
