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
    required this.hardFloorRamBytes,
    required this.kvBytesPerToken,
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

  /// Размер файла в байтах.
  final int bytes;

  final String url;
  final String fileName;

  /// Сколько свободной оперативной памяти нужно, чтобы модель работала
  /// без вылета.
  ///
  /// Важно: это НЕ равно размеру файла и НЕ равно размеру файла плюс
  /// размер файла. llama.cpp открывает веса через mmap — они не копируются
  /// в память, а подгружаются страницами по мере надобности, и ядро может
  /// вытеснить неиспользуемые обратно в хранилище. Поэтому рабочий набор
  /// заметно меньше размера модели.
  ///
  /// Формула: файл × 1,45 (запас на страницы графа и метаданные) +
  /// 300 МБ (движок и вычислительные буферы).
  final int minFreeRamBytes;

  /// Ниже этого объёма модель не запустится в принципе: не хватит памяти
  /// даже на постраничную загрузку весов.
  final int hardFloorRamBytes;

  /// Сколько памяти занимает KV-кэш на ОДИН токен контекста.
  ///
  /// Зависит не от размения весов, а от числа слоёв и числа голов
  /// внимания (KV), поэтому у моделей разного размера отношение разное.
  /// Считается как `2 (ключ и значение) × слои × kv-головы × head_dim × 2 байта`
  /// при f16. Отсюда же — ограничение контекста на телефоне: контекст
  /// растёт линейно, и именно он чаще всего доводит модель до нехватки
  /// памяти, а не сами веса.
  final int kvBytesPerToken;

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
  /// Накладные расходы помимо весов модели: движок, вычислительные буферы,
  /// KV-кэш диалога.
  static const _overheadBytes = 300 * 1024 * 1024;

  /// Коэффициент запаса к файлу модели. Больше единицы, потому что не весь
  /// файл живёт в памяти одновременно, но и не 1.0 — страницы графа,
  /// метаданные и холодные страницы, которые система не успела вытеснить,
  /// реально занимают место.
  static const _weightFactor = 1.45;

  /// Нижняя граница: столько нужно, чтобы процесс вообще стартовал.
  /// Часть весов будет подгружена с диска по мере надобности.
  static const _floorFactor = 0.55;
  static const _floorOverheadBytes = 160 * 1024 * 1024;

  static ModelSpec _spec({
    required String id,
    required String title,
    required String params,
    required ModelTier tier,
    required int bytes,
    required String url,
    required String fileName,
    required int kvBytesPerToken,
    required String speedHint,
    required String summary,
  }) {
    // minFree — комфортный запас, hardFloor — физический предел.
    // Разница между ними и есть зона, где модель запустится, но может
    // вытеснить другие приложения в подкачку.
    final need = (bytes * _weightFactor).round() + _overheadBytes;
    return ModelSpec(
      id: id,
      title: title,
      params: params,
      tier: tier,
      bytes: bytes,
      url: url,
      fileName: fileName,
      minFreeRamBytes: need,
      hardFloorRamBytes:
          (bytes * _floorFactor).round() + _floorOverheadBytes,
      kvBytesPerToken: kvBytesPerToken,
      speedHint: speedHint,
      summary: summary,
    );
  }

  static final qwen25_0_5b = _spec(
    id: 'qwen2.5-0.5b-instruct-q4km',
    title: 'Qwen2.5 0.5B',
    params: '0.5B',
    tier: ModelTier.light,
    bytes: 491400032,
    url:
        'https://huggingface.co/Qwen/Qwen2.5-0.5B-Instruct-GGUF/resolve/main/qwen2.5-0.5b-instruct-q4_k_m.gguf',
    fileName: 'qwen2.5-0.5b-instruct-q4_k_m.gguf',
    // 24 слоя, 2 KV-головы, head_dim 64: 2 × 24 × 2 × 64 × 2 = 12 288 Б
    kvBytesPerToken: 12288,
    speedHint: '25–40 ток/с',
    summary:
        'Самая лёгкая. Быстрые короткие ответы, простая арифметика, '
        'переводы, определения. Длинные тексты и рассуждения — нет.',
  );

  static final qwen25_1_5b = _spec(
    id: 'qwen2.5-1.5b-instruct-q4km',
    title: 'Qwen2.5 1.5B',
    params: '1.5B',
    tier: ModelTier.balanced,
    bytes: 1117320736,
    url:
        'https://huggingface.co/Qwen/Qwen2.5-1.5B-Instruct-GGUF/resolve/main/qwen2.5-1.5b-instruct-q4_k_m.gguf',
    fileName: 'qwen2.5-1.5b-instruct-q4_k_m.gguf',
    // 28 слоёв, 2 KV-головы, head_dim 128: 2 × 28 × 2 × 128 × 2 = 28 672 Б
    kvBytesPerToken: 28672,
    speedHint: '8–18 ток/с',
    summary:
        'Рекомендуемая по умолчанию. Русский понимает заметно лучше мелких '
        'моделей, тянет объяснения, конспекты, короткие эссе и код.',
  );

  static final qwen25_3b = _spec(
    id: 'qwen2.5-3b-instruct-q4km',
    title: 'Qwen2.5 3B',
    params: '3B',
    tier: ModelTier.quality,
    bytes: 2104932768,
    url:
        'https://huggingface.co/Qwen/Qwen2.5-3B-Instruct-GGUF/resolve/main/qwen2.5-3b-instruct-q4_k_m.gguf',
    fileName: 'qwen2.5-3b-instruct-q4_k_m.gguf',
    // 36 слоёв, 2 KV-головы, head_dim 128: 2 × 36 × 2 × 128 × 2 = 36 864 Б
    kvBytesPerToken: 36864,
    speedHint: '4–9 ток/с',
    summary:
        'Самая связная речь из доступных. Тянет объяснения по шагам и '
        'тексты с фактами, но требует заметно больше памяти и времени.',
  );

  static final qwen3_4bInstruct = _spec(
    id: 'qwen3-4b-instruct-2507-q4km',
    title: 'Qwen3 4B Instruct',
    params: '4B',
    tier: ModelTier.strong,
    bytes: 2497281120,
    url:
        'https://huggingface.co/unsloth/Qwen3-4B-Instruct-2507-GGUF/resolve/main/Qwen3-4B-Instruct-2507-Q4_K_M.gguf',
    fileName: 'Qwen3-4B-Instruct-2507-Q4_K_M.gguf',
    // 36 слоёв, 8 KV-голов, head_dim 128: 2 × 36 × 8 × 128 × 2 = 147 456 Б
    kvBytesPerToken: 147456,
    speedHint: '2–6 ток/с',
    summary:
        'Максимум, что осмысленно тащить на телефон. Реально комфортно '
        'только на флагманах с 8+ ГБ памяти — на средних будет медленно.',
  );

  /// Порядок важен: от лёгкой к тяжёлой.
  static final List<ModelSpec> all = [
    qwen25_0_5b,
    qwen25_1_5b,
    qwen25_3b,
    qwen3_4bInstruct,
  ];

  static ModelSpec byId(String id) {
    for (final m in all) {
      if (m.id == id) return m;
    }
    return fallback;
  }

  /// Модель по умолчанию.
  static ModelSpec get fallback => qwen25_1_5b;

  /// Насколько модель подходит телефону с заданным объёмом свободной
  /// памяти. Три уровня, а не два: раньше модель либо подходила, либо
  /// блокировалась, и среднего случая не было — из-за этого телефон с
  /// 1,6 ГБ свободной памяти не мог выбрать вообще ничего.
  static ModelFit fitFor(ModelSpec spec, int freeRamBytes) {
    if (freeRamBytes <= 0) return ModelFit.unknown;
    if (freeRamBytes >= spec.minFreeRamBytes) return ModelFit.comfortable;
    if (freeRamBytes >= spec.hardFloorRamBytes) return ModelFit.tight;
    return ModelFit.impossible;
  }

  /// Можно ли нажать на карточку модели.
  ///
  /// Самая лёгкая модель нажимается всегда, даже когда памяти не хватает и
  /// [fitFor] вернул [ModelFit.impossible]. Иначе на телефоне с очень малой
  /// свободной памятью человек не мог выбрать вообще ничего — приложение
  /// превращалось в пустой экран без единого действия. Лучше попробовать и
  /// получить понятную ошибку с предложением более лёгкой модели, чем
  /// получить тупик.
  static bool isSelectable(ModelSpec spec, int freeRamBytes) =>
      spec.id == all.first.id || fitFor(spec, freeRamBytes).canRun;

  /// Лучшая модель для этого телефона. Если совсем ничего не подходит —
  /// всё равно берём самую лёгкую: запрещать выбор бесполезно, человек
  /// вправе рискнуть, а мы обязаны предупредить.
  static ModelSpec recommend(int freeRamBytes, {String? userPinned}) {
    if (userPinned != null) return byId(userPinned);
    if (freeRamBytes <= 0) return fallback;

    ModelSpec? best;
    for (final m in all) {
      if (freeRamBytes >= m.minFreeRamBytes) best = m;
    }
    return best ?? all.first;
  }

  /// Ниже этого контекста диалог работает, но модель быстро забывает начало
  /// разговора. Ниже не опускаемся ни при какой памяти.
  static const minContext = 1024;

  /// Шаг округления контекста. Модель просит размер кратным этому числу,
  /// и промежуточные значения всё равно не дают выигрыша.
  static const _contextStep = 256;

  /// Какой контекст реально можно дать модели на этом телефоне.
  ///
  /// Это то, что делает приложение работоспособным на слабом железе вместо
  /// того, чтобы упираться лбом в «нужно 4 ГБ оперативной памяти».
  /// Жёсткий порог по памяти — плохое решение: пользователю нечем
  /// ответить, он закрывает приложение. Лучше ужать контекст — пусть
  /// модель хуже помнит начало диалога, зато отвечает.
  ///
  /// Считаем так: из свободной памяти вычитаем то, что нужно модели
  /// помимо контекста (постранично подгруженные веса плюс движок),
  /// остаток делим на стоимость одного токена контекста.
  static int fitContext(ModelSpec spec, int freeRamBytes, int requested) {
    if (freeRamBytes <= 0) return requested;

    final fixedUse = (spec.bytes * _floorFactor).round() + _overheadBytes;
    final spare = freeRamBytes - fixedUse;
    if (spare <= 0) return minContext;

    final affordable = (spare ~/ spec.kvBytesPerToken) ~/ _contextStep * _contextStep;
    if (affordable >= requested) return requested;
    return affordable < minContext ? minContext : affordable;
  }

  static String tierLabel(ModelTier tier) => switch (tier) {
    ModelTier.light => 'Лёгкая',
    ModelTier.balanced => 'Базовая',
    ModelTier.quality => 'Качественная',
    ModelTier.strong => 'Максимум',
  };
}

/// Насколько модель подходит телефону по свободной памяти.
enum ModelFit {
  /// Запас более чем достаточный.
  comfortable,

  /// Запустится, но может вытеснить другие приложения в подкачку.
  tight,

  /// Не хватит памяти даже на постраничную загрузку весов.
  impossible,

  /// Данные о памяти недоступны — судить не по чему.
  unknown;

  bool get canRun => this != ModelFit.impossible;
}
