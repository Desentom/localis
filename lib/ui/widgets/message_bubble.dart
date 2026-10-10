import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../data/chat_message.dart';

/// Пузырь сообщения.
///
/// Ответ модели показывается без тяжёлого markdown-движка: пока текст
/// дописывается токен за токеном, полноценный парсер пересчитывает всё
/// дерево на каждом кадре и интерфейс дёргается. Здесь только то, что
/// реально встречается в ответах: жирный, списки, нумерация, код и
/// переносы строк — всё считается за один проход.
class MessageBubble extends StatelessWidget {
  const MessageBubble({
    required this.message,
    super.key,
    this.streaming = false,
  });

  final ChatMessage message;
  final bool streaming;

  @override
  Widget build(BuildContext context) {
    final isUser = message.isUser;

    // Пустой или состоящий из одних пробелов ответ никогда не рисуется.
    // Раньше такой текст превращался в светлый прямоугольник во весь
    // экран, и человек не мог понять, что произошло. Теперь вместо
    // этого — короткое объяснение.
    final blank = message.text.trim().isEmpty;
    if (blank && !streaming) {
      return const Padding(
        padding: EdgeInsets.only(bottom: 14),
        child: _EmptyNotice(),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        mainAxisAlignment: isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isUser) ...[
            const _Avatar(),
            const SizedBox(width: 9),
          ],
          Flexible(
            child: Container(
              constraints: const BoxConstraints(maxWidth: 340),
              padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 11),
              decoration: BoxDecoration(
                // Никаких светлых заливок: обе реплики тёмные, различаются
                // оттенком и рамкой. Инверсия «белым по белому» из прошлой
                // версии выглядела как дыра в оформлении.
                color: isUser
                    ? AppSurfaces.bubbleUser
                    : AppSurfaces.bubbleModel,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(20),
                  topRight: const Radius.circular(20),
                  bottomLeft: Radius.circular(isUser ? 20 : 6),
                  bottomRight: Radius.circular(isUser ? 6 : 20),
                ),
                border: Border.all(
                  color: isUser
                      ? AppSurfaces.borderStrong
                      : AppSurfaces.border,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Ответ ограничен по высоте. Без этого предельного размера
                  // модель, которая не поняла формат диалога, заливала экран
                  // серым прямоугольником на пол-экрана: текст состоял из
                  // сотен переносов, и разобрать его было нечем. Теперь
                  // такой текст просто прокручивается внутри пузыря.
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: MediaQuery.sizeOf(context).height * 0.45,
                    ),
                    child: SingleChildScrollView(
                      child: Text.rich(
                        _render(message.text),
                        style: TextStyle(
                          // Текст в обоих пузырях белый: заливки тёмные, различаются оттенком
                          // и рамкой. Инверсии в приложении больше нет.
                          color: AppColors.textPrimary,
                          fontSize: 15,
                          height: 1.45,
                        ),
                      ),
                    ),
                  ),
                  if (streaming) const _Caret(),
                  if (!streaming && !isUser && message.tokensPerSecond != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 7),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.bolt_rounded,
                            size: 12,
                            color: AppColors.textFaint,
                          ),
                          const SizedBox(width: 3),
                          Text(
                            '${message.tokensPerSecond!.toStringAsFixed(1).replaceAll('.', ',')} ток/с · у вас на телефоне',
                            style: const TextStyle(
                              fontSize: 10.5,
                              color: AppColors.textFaint,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyNotice extends StatelessWidget {
  const _EmptyNotice();

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _Avatar(),
        const SizedBox(width: 9),
        Flexible(
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppSurfaces.bubbleModel,
              borderRadius: AppRadius.bubble,
              border: Border.all(color: AppSurfaces.border),
            ),
            child: const Text(
              'Модель не вернула ни одного слова. Обычно это значит, что '
              'сервис не понял формат диалога или ответ был отфильтрован.',
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12.5,
                height: 1.45,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: AppColors.focus, width: 1.5),
      ),
      child: const Icon(Icons.memory_rounded, size: 16, color: Colors.white),
    );
  }
}

/// Мигающий курсор в конце дописываемого текста.
class _Caret extends StatefulWidget {
  const _Caret();

  @override
  State<_Caret> createState() => _CaretState();
}

class _CaretState extends State<_Caret> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) => Container(
        width: 7,
        height: 15,
        margin: const EdgeInsets.only(left: 3, top: 3),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.4 + 0.6 * _c.value),
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }
}

/// Разбор ответа модели в [TextSpan]. Поддерживается ровно то, что нужно.
///
/// Текст в обоих пузырях белый, поэтому цвет маркеров больше не зависит
/// от того, чья это реплика.
TextSpan _render(String raw) {
  final span = TextSpan(style: const TextStyle());
  if (raw.isEmpty) return span;

  // Оба пузыря тёмные, поэтому маркер всегда светлее основного текста.
  const marker = Colors.white;

  final blocks = raw.split('\n');
  for (var i = 0; i < blocks.length; i++) {
    final line = blocks[i].trimRight();
    if (line.isEmpty) {
      span.children!.add(TextSpan(text: '\n', style: const TextStyle(height: 0.9)));
      continue;
    }

    if (i > 0) {
      span.children!.add(const TextSpan(text: '\n'));
    }

    final trimmed = line.trimLeft();

    // Блок кода — всё до конца или до трёх обратных кавычек.
    if (trimmed.startsWith('```')) {
      final code = <String>[];
      var j = i + 1;
      for (; j < blocks.length && !blocks[j].trim().startsWith('```'); j++) {
        code.add(blocks[j]);
      }
      span.children!.add(_codeSpan(code.join('\n')));
      // Пропускаем закрывающий ``` — он уже учтён в цикле выше.
      i = j;
      continue;
    }

    if (trimmed.startsWith('- ') || trimmed.startsWith('• ') || trimmed.startsWith('* ')) {
      span.children!.addAll([
        TextSpan(text: '•  ', style: TextStyle(color: marker)),
        ..._inline(trimmed.substring(2)),
      ]);
      continue;
    }

    final numbered = RegExp(r'^(\d+)[.)]\s+').firstMatch(trimmed);
    if (numbered != null) {
      span.children!.addAll([
        TextSpan(
          text: '${numbered.group(1)}.  ',
          style: TextStyle(color: marker, fontWeight: FontWeight.w700),
        ),
        ..._inline(trimmed.substring(numbered.end)),
      ]);
      continue;
    }

    // Заголовки из двух хешей — часто так оформляют выводы.
    if (trimmed.startsWith('## ')) {
      span.children!.addAll([
        const TextSpan(text: '\n'),
        TextSpan(
          text: trimmed.substring(3),
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15.5),
        ),
      ]);
      continue;
    }

    span.children!.addAll(_inline(trimmed));
  }
  return span;
}

TextSpan _codeSpan(String code) => TextSpan(
  children: [
    const TextSpan(text: '\n'),
    WidgetSpan(
      alignment: PlaceholderAlignment.middle,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(11),
        decoration: BoxDecoration(
          color: const Color(0xFF000000),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          code,
          style: TextStyle(
            fontFamily: 'monospace',
            fontSize: 12.5,
            height: 1.45,
            color: const Color(0xFFCFCFCF),
          ),
        ),
      ),
    ),
    const TextSpan(text: '\n'),
  ],
);

/// Жирный `**текст**` и моноширинный `текст` внутри строки.
List<TextSpan> _inline(String line) {
  const codeColor = Color(0xFFCFCFCF);

  final parts = <TextSpan>[];
  final pattern = RegExp(r'(\*\*.+?\*\*|`[^`]+`)');
  var index = 0;
  for (final m in pattern.allMatches(line)) {
    if (m.start > index) {
      parts.add(TextSpan(text: line.substring(index, m.start)));
    }
    final token = m.group(0)!;
    if (token.startsWith('**')) {
      parts.add(
        TextSpan(
          text: token.substring(2, token.length - 2),
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
      );
    } else {
      parts.add(
        TextSpan(
          text: token.substring(1, token.length - 1),
          style: TextStyle(
            fontFamily: 'monospace',
            fontSize: 13,
            color: codeColor,
          ),
        ),
      );
    }
    index = m.end;
  }
  if (index < line.length) parts.add(TextSpan(text: line.substring(index)));
  return parts;
}
