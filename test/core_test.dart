import 'package:flutter_test/flutter_test.dart';
import 'package:localis/core/format.dart';
import 'package:localis/data/chat_message.dart';
import 'package:localis/data/chat_store.dart';
import 'package:localis/data/chat_window.dart';
import 'package:localis/data/model_spec.dart';
import 'package:localis/services/device_capability.dart';
import 'package:localis/services/cloud_engine.dart';
import 'package:localis/services/engine_service.dart';
import 'package:localis/ui/screens/settings_screen.dart' show contextOptions;

void main() {
  group('formatBytes', () {
    test('переводит байты в десятичные единицы с запятой', () {
      // Считаем в 1000, а не в 1024: так же, как Android показывает память.
      expect(formatBytes(396705472), '396,71 МБ');
      expect(formatBytes(1107409472), '1,11 ГБ');
      expect(formatBytes(2104932768), '2,1 ГБ');
      expect(formatBytes(0), '0 Б');
    });

    test('убирает хвостовые нули', () {
      expect(formatBytes(2000), '2 КБ');
      expect(formatBytes(2500000), '2,5 МБ');
    });

    test('у байт нет дробной части', () {
      expect(formatBytes(512), '512 Б');
      expect(formatBytes(512), isNot(contains(',')));
    });
  });

  group('plural', () {
    test('склоняет по-русски', () {
      expect(plural(1, 'модель', 'модели', 'моделей'), 'модель');
      expect(plural(3, 'модель', 'модели', 'моделей'), 'модели');
      expect(plural(5, 'модель', 'модели', 'моделей'), 'моделей');
      expect(plural(11, 'модель', 'модели', 'моделей'), 'моделей');
      expect(plural(21, 'модель', 'модели', 'моделей'), 'модель');
    });
  });

  group('ChatStore.titleFrom', () {
    test('короткий текст остаётся как есть', () {
      expect(ChatStore.titleFrom('Что такое фотосинтез?'), 'Что такое фотосинтез?');
    });

    test('длинный текст режется по границе слова', () {
      final title = ChatStore.titleFrom(
        'Объясни, пожалуйста, подробно, как устроен процесс фотосинтеза в растениях',
      );
      expect(title.length, lessThanOrEqualTo(39));
      expect(title, endsWith('…'));
      // Не должно остаться обрезанного слова с висящим пробелом.
      expect(title.substring(0, title.length - 1), isNot(endsWith(' ')));
    });

    test('схлопывает лишние пробелы и переносы', () {
      expect(ChatStore.titleFrom('  привет\n\n   мир  '), 'привет мир');
    });
  });

  group('ChatSession', () {
    test('переживает круг через JSON', () {
      final session = ChatSession(
        id: 'abc',
        title: 'Тест',
        updatedAt: DateTime.fromMillisecondsSinceEpoch(1700000000000),
        modelId: 'qwen3-1.7b-q4km',
        messages: [
          ChatMessage(role: Role.user, text: 'вопрос', createdAt: DateTime(2024, 1, 2)),
          ChatMessage(role: Role.assistant, text: 'ответ', tokensPerSecond: 12.5),
        ],
      );

      final restored = ChatSession.fromJson(session.toJson());

      expect(restored.id, session.id);
      expect(restored.title, session.title);
      expect(restored.modelId, session.modelId);
      expect(restored.messages.length, 2);
      expect(restored.messages.first.role, Role.user);
      expect(restored.messages.last.text, 'ответ');
      expect(restored.messages.last.tokensPerSecond, 12.5);
    });

    test('битая разметка роли не роняет разбор', () {
      final m = ChatMessage.fromJson({'role': 'неизвестно', 'text': 'x'});
      expect(m.role, Role.user);
    });
  });

  group('ModelCatalog', () {
    test('подбирает модель по свободной памяти', () {
      // 2 ГБ свободно — помещается 1.7B, но не 3B.
      expect(
        ModelCatalog.recommend(2 * 1024 * 1024 * 1024).id,
        ModelCatalog.qwen25_1_5b.id,
      );
      // 4 ГБ свободно — помещается и 3B, и 4B.
      expect(
        ModelCatalog.recommend(4 * 1024 * 1024 * 1024).id,
        ModelCatalog.qwen3_4bInstruct.id,
      );
      // 3,5 ГБ свободно — помещается 3B, но не 4B.
      expect(
        ModelCatalog.recommend(3758096384).id,
        ModelCatalog.qwen25_3b.id,
      );
      // Много памяти — максимум каталога.
      expect(
        ModelCatalog.recommend(12 * 1024 * 1024 * 1024).id,
        ModelCatalog.qwen3_4bInstruct.id,
      );
    });

    test('самая лёгкая модель запускается даже на 1 ГБ свободной памяти', () {
      // Регрессия из v0.1.0: порог для 0.6B стоял на 2 ГБ, и телефон
      // с 1,6 ГБ свободной памяти не мог выбрать вообще ни одну модель —
      // приложение становилось полностью нерабочим.
      const free = 1 * 1024 * 1024 * 1024;
      expect(ModelCatalog.recommend(free).id, ModelCatalog.qwen25_0_5b.id);
      expect(ModelCatalog.fitFor(ModelCatalog.qwen25_0_5b, free), ModelFit.comfortable);
    });

    test('порог памяти держится около размера файла, а не вдвое больше', () {
      // Регрессия из v0.1.0: для модели 3B (2,1 ГБ) требовалось 4 ГБ
      // свободной памяти. С mmap веса не копируются в память целиком,
      // поэтому порог обязан быть около размера файла плюс небольшая
      // надбавка на движок. Формула зафиксирована: файл × 1,45 + 300 МБ.
      const weightFactor = 1.45;
      const overhead = 320 * 1024 * 1024;

      for (final m in ModelCatalog.all) {
        expect(
          m.minFreeRamBytes,
          lessThanOrEqualTo((m.bytes * weightFactor).round() + overhead),
          reason: '${m.id}: порог памяти завышен',
        );
        expect(
          m.minFreeRamBytes,
          greaterThan(m.bytes),
          reason: '${m.id}: с запасом на движок порог должен быть больше файла',
        );
        expect(
          m.hardFloorRamBytes,
          lessThan(m.minFreeRamBytes),
          reason: '${m.id}: физический предел должен быть ниже комфортного порога',
        );
      }
    });

    test('модель впритык помечается как tight, а не блокируется', () {
      // 1,5 ГБ свободно — ровно тот телефон, на котором всё было
      // заблокировано в v0.1.0.
      const free = 1610612736; // 1,5 ГиБ
      final spec = ModelCatalog.qwen25_3b;
      final fit = ModelCatalog.fitFor(spec, free);
      expect(fit, ModelFit.tight, reason: 'выбор нельзя закрывать полностью');
      expect(fit.canRun, isTrue);
    });

    test('при заведомо недостаточной памяти модель помечается невозможной', () {
      expect(
        ModelCatalog.fitFor(ModelCatalog.qwen3_4bInstruct, 64 * 1024 * 1024),
        ModelFit.impossible,
      );
    });

    test('при неизвестном объёме памяти модель не блокируется', () {
      expect(ModelCatalog.fitFor(ModelCatalog.qwen25_0_5b, 0), ModelFit.unknown);
      expect(ModelCatalog.fitFor(ModelCatalog.qwen25_0_5b, 0).canRun, isTrue);
    });

    test('самая лёгкая модель нажимается даже когда памяти совсем нет', () {
      // Иначе на слабом телефоне получается экран, где нельзя нажать
      // ни на одну карточку: тупик без единого действия.
      expect(ModelCatalog.isSelectable(ModelCatalog.qwen25_0_5b, 64 * 1024 * 1024), isTrue);
      expect(ModelCatalog.isSelectable(ModelCatalog.qwen3_4bInstruct, 64 * 1024 * 1024), isFalse);
      expect(ModelCatalog.isSelectable(ModelCatalog.qwen25_1_5b, 8 * 1024 * 1024 * 1024), isTrue);
    });

    test('контекст ужимается под память, а не приводит к отказу', () {
      // Телефон из первого отчёта: 3,8 ГБ всего, 1,6 ГБ свободно.
      const free = 1717986918;

      // Лёгкая модель при такой памяти получает запрошенный контекст целиком.
      expect(
        ModelCatalog.fitContext(ModelCatalog.qwen25_0_5b, free, 4096),
        4096,
      );

      // Тяжёлая модель запускается с уменьшенным контекстом вместо отказа.
      final shrunk = ModelCatalog.fitContext(ModelCatalog.qwen3_4bInstruct, free, 4096);
      expect(shrunk, lessThan(4096));
      expect(shrunk, greaterThanOrEqualTo(ModelCatalog.minContext));
    });

    test('контекст не опускается ниже минимума ни при какой памяти', () {
      for (final m in ModelCatalog.all) {
        expect(
          ModelCatalog.fitContext(m, 1, 4096),
          ModelCatalog.minContext,
          reason: m.id,
        );
      }
    });

    test('контекст всегда кратен шагу и не больше запрошенного', () {
      const free = 1400000000;
      for (final m in ModelCatalog.all) {
        for (final requested in [1024, 2048, 4096, 8192]) {
          final c = ModelCatalog.fitContext(m, free, requested);
          expect(c, lessThanOrEqualTo(requested), reason: m.id);
          expect(c % 256, 0, reason: '${m.id}: контекст должен быть кратен 256');
          expect(c, greaterThanOrEqualTo(ModelCatalog.minContext), reason: m.id);
        }
      }
    });

    test('при неизвестной памяти контекст остаётся как запрошено', () {
      expect(ModelCatalog.fitContext(ModelCatalog.qwen25_0_5b, 0, 8192), 8192);
    });

    test('размер KV-кэша на токен у всех моделей положителен', () {
      for (final m in ModelCatalog.all) {
        expect(m.kvBytesPerToken, greaterThan(0), reason: m.id);
      }
    });

    test('явный выбор пользователя важнее рекомендации', () {
      final picked = ModelCatalog.recommend(
        12 * 1024 * 1024 * 1024,
        userPinned: ModelCatalog.qwen25_0_5b.id,
      );
      expect(picked.id, ModelCatalog.qwen25_0_5b.id);
    });

    test('при совсем малой памяти не падает, а берёт лёгкую', () {
      expect(ModelCatalog.recommend(512 * 1024 * 1024).id, ModelCatalog.qwen25_0_5b.id);
    });

    test('неизвестный id возвращает модель по умолчанию, а не бросает', () {
      expect(ModelCatalog.byId('такой-модели-нет').id, ModelCatalog.fallback.id);
    });

    test('у каждой модели уникальный id и корректный формат ссылки', () {
      final ids = ModelCatalog.all.map((m) => m.id).toSet();
      expect(ids.length, ModelCatalog.all.length, reason: 'id должны быть уникальны');

      for (final m in ModelCatalog.all) {
        expect(m.url, startsWith('https://huggingface.co/'), reason: m.id);
        expect(m.url, endsWith(m.fileName), reason: '${m.id}: имя файла должно быть в ссылке');
        expect(m.bytes, greaterThan(0), reason: m.id);
        expect(m.minFreeRamBytes, greaterThan(m.bytes), reason: '${m.id}: память должна быть больше файла');
        expect(m.speedHint, isNotEmpty, reason: m.id);
      }
    });
  });

  group('ChatWindow', () {
    List<ChatMessage> dialogue(int pairs, {int len = 200}) => [
      for (var i = 0; i < pairs; i++) ...[
        ChatMessage(role: Role.user, text: 'вопрос $i ' * (len ~/ 9)),
        ChatMessage(role: Role.assistant, text: 'ответ $i ' * (len ~/ 7)),
      ],
    ];

    test('пустая история остаётся пустой', () {
      expect(ChatWindow.trim(history: const [], contextTokens: 4096, reserveTokens: 512), isEmpty);
    });

    test('короткая история проходит целиком', () {
      final h = dialogue(2);
      expect(
        ChatWindow.trim(history: h, contextTokens: 4096, reserveTokens: 512),
        hasLength(h.length),
      );
    });

    test('длинная история укорачивается с конца под контекст', () {
      final h = dialogue(60);
      final trimmed = ChatWindow.trim(
        history: h,
        contextTokens: 1024,
        reserveTokens: 512,
      );

      expect(trimmed, isNotEmpty);
      expect(trimmed.length, lessThan(h.length));
      // Последнее сообщение — это текущий вопрос, он обязан уцелеть.
      expect(trimmed.last.text, h.last.text);
      // Начинаться должно с реплики человека, а не с ответа модели.
      expect(trimmed.first.isUser, isTrue);
    });

    test('при совсем крошечном контексте остаётся хотя бы текущий вопрос', () {
      final h = dialogue(5);
      final trimmed = ChatWindow.trim(
        history: h,
        contextTokens: 64,
        reserveTokens: 512,
      );
      expect(trimmed, hasLength(1));
      expect(trimmed.single.text, h.last.text);
    });

    test('вычисленный размер не превышает бюджет контекста', () {
      final h = dialogue(40);
      const context = 2048;
      const reserve = 400;
      final trimmed = ChatWindow.trim(
        history: h,
        contextTokens: context,
        reserveTokens: reserve,
      );

      final budgetChars = (context - reserve - ChatWindow.promptReserve) * ChatWindow.charsPerToken;
      final used = trimmed.fold<int>(0, (s, m) => s + m.text.length + 8);
      expect(used, lessThanOrEqualTo(budgetChars));
    });
  });

  group('buildSystemPrompt', () {
    test('пустые части не оставляют лишних переносов', () {
      final prompt = buildSystemPrompt(
        personaPrompt: '',
        customPrompt: '',
        thinkMode: false,
        spec: null,
      );
      expect(prompt.trim(), isEmpty);
    });

    test('режим размышления добавляет отдельную инструкцию', () {
      final prompt = buildSystemPrompt(
        personaPrompt: 'Ты репетитор.',
        customPrompt: '',
        thinkMode: true,
        spec: ModelCatalog.qwen25_1_5b,
      );
      expect(prompt, contains('Ты репетитор.'));
      expect(prompt, contains('разбери задачу'));
      expect(prompt, contains('без интернета'));
    });
  });

  group('GenerationStats', () {
    test('показывает токены, если их посчитали точно', () {
      const stats = GenerationStats(
        reason: FinishReason.completed,
        elapsed: Duration(seconds: 2),
        characters: 40,
        tokens: 20,
        tokensAreExact: true,
      );
      expect(stats.tokensPerSecond, 10.0);
      expect(stats.label, '10,0 ток/с');
    });

    test('откатывается на символы, если токены неизвестны', () {
      const stats = GenerationStats(
        reason: FinishReason.completed,
        elapsed: Duration(seconds: 2),
        characters: 40,
        tokens: null,
        tokensAreExact: false,
      );
      expect(stats.tokensPerSecond, isNull);
      expect(stats.label, '20 симв./с');
    });

    test('нулевое время не даёт деления на ноль', () {
      const stats = GenerationStats(
        reason: FinishReason.completed,
        elapsed: Duration.zero,
        characters: 10,
        tokens: 5,
        tokensAreExact: true,
      );
      expect(stats.tokensPerSecond, isNull);
    });
  });

  group('chatTemplateFor', () {
    test('для всех моделей каталога подходит ChatML', () {
      // Qwen2.5 и Qwen3 общаются через ChatML. Если в каталог попадёт
      // модель другого семейства, тест сразу об этом напомнит.
      for (final spec in ModelCatalog.all) {
        expect(chatTemplateFor(spec), 'chatml', reason: spec.id);
      }
    });
  });

  group('buildChatMlPrompt', () {
    // Регрессия: плагин llama_flutter_android собирает «chatml» как обычный
    // текст без специальных токенов. Qwen без них не понимает, где кончается
    // реплика, и не знает, когда остановиться: приложение «думает» минутами,
    // а вместо ответа рисует пустой серый прямоугольник во весь экран.
    test('каждая реплика обрамлена специальными токенами', () {
      final p = buildChatMlPrompt(
        systemPrompt: 'Ты помощник.',
        history: [
          ChatMessage(role: Role.user, text: 'Привет'),
          ChatMessage(role: Role.assistant, text: 'Здравствуйте!'),
          ChatMessage(role: Role.user, text: 'Что такое фотосинтез?'),
        ],
      );

      expect(p, startsWith('<|im_start|>\nsystem\nТы помощник.\n<|im_end|>\n'));
      expect(p, contains('<|im_start|>\nuser\nПривет\n<|im_end|>'));
      expect(
        p,
        contains('<|im_start|>\nassistant\nЗдравствуйте!\n<|im_end|>'),
      );
      expect(p, contains('<|im_start|>\nuser\nЧто такое фотосинтез?\n<|im_end|>'));
    });

    test('промпт заканчивается началом хода модели', () {
      final p = buildChatMlPrompt(systemPrompt: '', history: const []);
      expect(p, '<|im_start|>\nassistant\n');
    });

    test('без системной подсказки лишний блок не добавляется', () {
      final p = buildChatMlPrompt(
        systemPrompt: '   ',
        history: [ChatMessage(role: Role.user, text: 'Привет')],
      );
      expect(p, isNot(contains('system')));
      expect(p, '<|im_start|>\nuser\nПривет\n<|im_end|>\n<|im_start|>\nassistant\n');
    });

    test('пустые реплики пропускаются', () {
      final p = buildChatMlPrompt(
        systemPrompt: '',
        history: [
          ChatMessage(role: Role.user, text: '   '),
          ChatMessage(role: Role.user, text: 'Привет'),
        ],
      );
      expect('<|im_start|>'.allMatches(p).length, 2);
    });

    test('специальные токены в ответе вырезаются', () {
      expect(
        sanitizeModelOutput('Ответ<|im_end|>\n\nещё'),
        'Ответ\n\nещё',
      );
      expect(sanitizeModelOutput('<think>размышление</think>Итог'), 'Итог');
      expect(sanitizeModelOutput('Обычный ответ'), 'Обычный ответ');
    });

    test('название модели не содержит подсказок на уголки в скобках', () {
      // Специальные токены вырезаются регуляркой, поэтому важно, чтобы
      // обычный текст под них не попадал.
      expect(
        sanitizeModelOutput('Сравни: a <|b|> и c'),
        'Сравни: a  и c',
      );
    });
  });

  group('CloudModel', () {
    test('в каталоге только реально существующие модели', () {
      // Имена взяты из официальной документации Gemini, страница обновлена
      // 9 октября 2026. Модели-предпросмотра и синонимы вида flash-latest
      // намеренно нет: они молча меняют качество ответов.
      expect(
        CloudModel.values.map((m) => m.id).toList(),
        [
          'gemini-3.8-flash',
          'gemini-3.6-flash',
          'gemini-3.5-flash-lite',
        ],
      );
    });

    test('неизвестный идентификатор не ломает приложение', () {
      expect(CloudModel.byId('такой-модели-нет'), CloudModel.flash36);
      expect(CloudModel.byId('gemini-3.6-flash'), CloudModel.flash36);
    });
  });

  group('CloudEngine разбор потока', () {
    test('достаёт текст из кучка потока', () {
      const chunk =
          '{"candidates":[{"content":{"parts":[{"text":"Привет"}],'
          '"role":"model"}}],"usageMetadata":{"totalTokenCount":5}}';
      expect(CloudEngine.decodeChunk(chunk), 'Привет');
    });

    test('склеивает несколько частей в одном кучке', () {
      const chunk =
          '{"candidates":[{"content":{"parts":['
          '{"text":"При"},{"text":"вет"}]}}]}';
      expect(CloudEngine.decodeChunk(chunk), 'Привет');
    });

    test('кучки без текста игнорируются, а не роняют разбор', () {
      expect(CloudEngine.decodeChunk('{"usageMetadata":{}}'), isNull);
      expect(CloudEngine.decodeChunk('{"candidates":[]}'), isNull);
      expect(CloudEngine.decodeChunk('не json вовсе'), isNull);
    });
  });

  group('CloudEngine объяснение ошибок', () {
    test('неверный ключ объясняется по-человечески', () {
      const body = '{"error":{"message":"API key not valid."}}';
      final text = CloudEngine.explain(400, body);
      expect(text, contains('Ключ не принят'));
      expect(text, contains('без пробелов'));
    });

    test('отклонённый ключ и лимит различаются', () {
      expect(CloudEngine.explain(403, '{}'), contains('Ключ отклонён'));
      expect(CloudEngine.explain(429, '{}'), contains('Лимит запросов'));
      expect(CloudEngine.explain(503, '{}'), contains('временно недоступен'));
    });
  });

  group('contextOptions', () {
    // Регрессия: верхняя граница ползунка зависела от свободной памяти,
    // поэтому сетка делений каждый раз получалась другой, и бегунок
    // «прыгал» при открытии экрана настроек, а подпись показывала
    // другое число. Список значений это исключает.
    test('содержит только те размеры, что помещаются в память', () {
      expect(contextOptions(1024), [1024]);
      expect(contextOptions(2048), [1024, 2048]);
      expect(contextOptions(4096), [1024, 2048, 4096]);
      expect(contextOptions(8192), [1024, 2048, 4096, 8192]);
    });

    test('все значения кратны 1024 и не превышают потолок', () {
      for (final ceiling in [1024, 2048, 4096, 8192]) {
        for (final v in contextOptions(ceiling)) {
          expect(v % 1024, 0, reason: '$v должен быть кратен 1024');
          expect(v, lessThanOrEqualTo(ceiling));
        }
      }
    });
  });

  group('resolveGpuLayers', () {
    const noGpu = DeviceCapability(
      cores: 8,
      freeRamBytes: 8 * 1024 * 1024 * 1024,
      totalRamBytes: 8 * 1024 * 1024 * 1024,
      vulkanSupported: false,
      gpuName: '',
      recommendedGpuLayers: 32,
    );

    test('без Vulkan работаем только на процессоре', () {
      expect(resolveGpuLayers(noGpu, ModelCatalog.qwen25_1_5b), 0);
    });

    test('при нехватке памяти GPU-слои не даём', () {
      const tight = DeviceCapability(
        cores: 8,
        freeRamBytes: 512 * 1024 * 1024,
        totalRamBytes: 4 * 1024 * 1024 * 1024,
        vulkanSupported: true,
        gpuName: 'Adreno',
        recommendedGpuLayers: 32,
      );
      // Модель 1.7B требует 3 ГБ, свободно 0,5 — вылет гарантирован.
      expect(resolveGpuLayers(tight, ModelCatalog.qwen25_1_5b), 0);
    });

    test('GPU-слои не включаются никогда', () {
      // Регрессия. На телефоне с Adreno 610 и Vulkan модель загружалась
      // за 697 мс, но генерация не выдавала ни одного токена за 45 секунд.
      // Причина — включение GPU-слоёв: в версии 0.2.0 порог памяти был
      // 2 ГБ при 1,6 ГБ свободных, GPU не включался, и генерация шла.
      // В 0.4.0 порог снизился, условие выполнилось — вывод пропал совсем.
      //
      // Для маленьких моделей выигрыш от GPU на телефоне часто нулевой,
      // а цена — нестабильность драйверов Vulkan вплоть до полного отказа.
      const roomy = DeviceCapability(
        cores: 8,
        freeRamBytes: 8 * 1024 * 1024 * 1024,
        totalRamBytes: 12 * 1024 * 1024 * 1024,
        vulkanSupported: true,
        gpuName: 'Adreno 740',
        recommendedGpuLayers: 16,
      );
      expect(resolveGpuLayers(roomy, ModelCatalog.qwen25_1_5b), 0);

      // Даже на флагмане с большим запасом памяти — тоже ноль.
      const flagship = DeviceCapability(
        cores: 12,
        freeRamBytes: 10 * 1024 * 1024 * 1024,
        totalRamBytes: 16 * 1024 * 1024 * 1024,
        vulkanSupported: true,
        gpuName: 'Adreno 840',
        recommendedGpuLayers: 32,
      );
      expect(resolveGpuLayers(flagship, ModelCatalog.qwen25_3b), 0);
    });
  });
}
