import 'package:flutter_test/flutter_test.dart';
import 'package:localis/core/format.dart';
import 'package:localis/data/chat_message.dart';
import 'package:localis/data/chat_store.dart';
import 'package:localis/data/model_spec.dart';
import 'package:localis/services/device_capability.dart';
import 'package:localis/services/engine_service.dart';

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
      // Мало памяти — только самая лёгкая.
      expect(
        ModelCatalog.recommend(2 * 1024 * 1024 * 1024).id,
        ModelCatalog.qwen3_0_6b.id,
      );
      // 4 ГБ свободно — помещается 3B.
      expect(
        ModelCatalog.recommend(4 * 1024 * 1024 * 1024).id,
        ModelCatalog.qwen25_3b.id,
      );
      // Много памяти — максимум каталога.
      expect(
        ModelCatalog.recommend(12 * 1024 * 1024 * 1024).id,
        ModelCatalog.qwen3_4b.id,
      );
    });

    test('явный выбор пользователя важнее рекомендации', () {
      final picked = ModelCatalog.recommend(
        12 * 1024 * 1024 * 1024,
        userPinned: ModelCatalog.qwen3_0_6b.id,
      );
      expect(picked.id, ModelCatalog.qwen3_0_6b.id);
    });

    test('при совсем малой памяти не падает, а берёт лёгкую', () {
      expect(ModelCatalog.recommend(512 * 1024 * 1024).id, ModelCatalog.qwen3_0_6b.id);
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
        spec: ModelCatalog.qwen3_1_7b,
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
      expect(resolveGpuLayers(noGpu, ModelCatalog.qwen3_1_7b), 0);
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
      expect(resolveGpuLayers(tight, ModelCatalog.qwen3_1_7b), 0);
    });

    test('с запасом памяти берём рекомендацию плагина', () {
      const roomy = DeviceCapability(
        cores: 8,
        freeRamBytes: 8 * 1024 * 1024 * 1024,
        totalRamBytes: 12 * 1024 * 1024 * 1024,
        vulkanSupported: true,
        gpuName: 'Adreno 740',
        recommendedGpuLayers: 16,
      );
      expect(resolveGpuLayers(roomy, ModelCatalog.qwen3_1_7b), 16);
    });
  });
}
