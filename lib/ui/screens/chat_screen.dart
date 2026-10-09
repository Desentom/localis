import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme.dart';
import '../../data/chat_message.dart';
import '../../data/personas.dart';
import '../../state/app_controller.dart';
import '../widgets/aurora_background.dart';
import '../widgets/message_bubble.dart';
import 'history_sheet.dart';
import 'settings_screen.dart';
import 'splash_screen.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({required this.controller, super.key});

  final AppController controller;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final _focus = FocusNode();
  bool _showChips = true;

  AppController get c => widget.controller;

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _scrollToEnd({bool animated = true}) {
    if (!_scroll.hasClients) return;
    final target = _scroll.position.maxScrollExtent;
    if (animated) {
      _scroll.animateTo(
        target,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    } else {
      _scroll.jumpTo(target);
    }
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty || c.isGenerating) return;
    _input.clear();
    setState(() => _showChips = false);
    unawaited(HapticFeedback.lightImpact());
    await c.send(text);
    if (mounted) _scrollToEnd();
  }

  void _useChip(String text) {
    _input.text = text;
    _input.selection = TextSelection.collapsed(offset: text.length);
    setState(() => _showChips = false);
    _send();
  }

  @override
  Widget build(BuildContext context) {
    final messages = c.session.messages;
    final streaming = c.streaming;
    final generating = c.isGenerating;

    return Scaffold(
      backgroundColor: Colors.transparent,
      resizeToAvoidBottomInset: true,
      appBar: _TopBar(
        controller: c,
        onHistory: () => _openHistory(context),
        onSettings: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => SettingsScreen(controller: c),
          ),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: messages.isEmpty && streaming.isEmpty
                ? _EmptyState(
                    persona: c.persona,
                    onChip: _useChip,
                    modelTitle: c.activeModel?.title ?? '',
                  )
                : ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                    // +1 — либо живой стрим, либо пустая строка, если ждём
                    // первый токен: она удерживает экран внизу.
                    itemCount: messages.length + 1,
                    itemBuilder: (context, index) {
                      if (index < messages.length) {
                        final m = messages[index];
                        return _Swipeable(
                          onCopy: () {
                            Clipboard.setData(ClipboardData(text: m.text));
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Скопировано'),
                                duration: Duration(seconds: 1),
                              ),
                            );
                          },
                          child: MessageBubble(message: m),
                        );
                      }
                      if (streaming.isEmpty && !generating) return const SizedBox.shrink();
                      return MessageBubble(
                        message: ChatMessage(role: Role.assistant, text: streaming),
                        streaming: true,
                      );
                    },
                  ),
          ),

          if (c.error != null) _ErrorBar(message: c.error!, onClose: c.clearError),

          if (_showChips && !generating) _PersonaBar(controller: c, onPick: _useChip),

          _Composer(
            controller: _input,
            focusNode: _focus,
            generating: generating,
            onSend: _send,
            onStop: c.stopGeneration,
          ),
        ],
      ),
    );
  }

  Future<void> _openHistory(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => HistorySheet(controller: c),
    );
    if (mounted) setState(() {});
  }
}

class _TopBar extends StatelessWidget implements PreferredSizeWidget {
  const _TopBar({
    required this.controller,
    required this.onHistory,
    required this.onSettings,
  });

  final AppController controller;
  final VoidCallback onHistory;
  final VoidCallback onSettings;

  @override
  Size get preferredSize => const Size.fromHeight(58);

  @override
  Widget build(BuildContext context) {
    final model = controller.activeModel;
    final busy = controller.isGenerating;

    return AppBar(
      toolbarHeight: 58,
      titleSpacing: 16,
      title: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              gradient: AppColors.accent,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.memory_rounded, size: 18, color: Colors.black),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  model?.title ?? 'Модель не выбрана',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    height: 1.1,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                const OfflineBadge(compact: true),
              ],
            ),
          ),
        ],
      ),
      actions: [
        if (busy)
          const Padding(
            padding: EdgeInsets.only(right: 6),
            child: Center(
              child: SizedBox(
                width: 15,
                height: 15,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          ),
        IconButton(
          onPressed: onHistory,
          icon: const Icon(Icons.history_rounded, size: 21),
          tooltip: 'История',
        ),
        IconButton(
          onPressed: onSettings,
          icon: const Icon(Icons.tune_rounded, size: 21),
          tooltip: 'Настройки',
        ),
        const SizedBox(width: 4),
      ],
    );
  }
}

/// Пустой чат: сразу показываем, что делать, вместо пустого экрана.
class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.persona,
    required this.onChip,
    required this.modelTitle,
  });

  final Persona persona;
  final ValueChanged<String> onChip;
  final String modelTitle;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 30, 20, 20),
      children: [
        Center(
          child: Container(
            width: 62,
            height: 62,
            decoration: BoxDecoration(
              gradient: AppColors.accent,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.white.withValues(alpha: 0.16),
                  blurRadius: 26,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: const Icon(Icons.memory_rounded, size: 31, color: Colors.black),
          ),
        ),
        const SizedBox(height: 18),
        const Text(
          'Спросите что угодно',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: -0.4),
        ),
        const SizedBox(height: 8),
        Text(
          'Режим: ${persona.emoji} ${persona.title}. Интернет не нужен — '
          'всё считается на телефоне.',
          textAlign: TextAlign.center,
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 13.5, height: 1.45),
        ),
        const SizedBox(height: 24),
        ...persona.starterChips.map(
          (chip) => Padding(
            padding: const EdgeInsets.only(bottom: 9),
            child: _SuggestionTile(text: chip, onTap: () => onChip(chip)),
          ),
        ),
      ],
    );
  }
}

class _SuggestionTile extends StatelessWidget {
  const _SuggestionTile({required this.text, required this.onTap});

  final String text;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      onTap: onTap,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      borderRadius: AppRadius.chip,
      child: Row(
        children: [
          const Icon(Icons.arrow_outward_rounded, size: 15, color: Colors.white),
          const SizedBox(width: 11),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontSize: 13.5, height: 1.35),
            ),
          ),
        ],
      ),
    );
  }
}

/// Быстрые пресеты под полем ввода — то, что человек чаще всего хочет.
class _PersonaBar extends StatelessWidget {
  const _PersonaBar({required this.controller, required this.onPick});

  final AppController controller;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    final persona = controller.persona;
    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        itemCount: Personas.all.length,
        separatorBuilder: (_, __) => const SizedBox(width: 7),
        itemBuilder: (context, i) {
          final p = Personas.all[i];
          final selected = p.id == persona.id;
          return GestureDetector(
            onTap: () {
              HapticFeedback.selectionClick();
              controller.updateSettings(controller.settings.copyWith(personaId: p.id));
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: selected ? Colors.white.withValues(alpha: 0.22) : const Color(0x10FFFFFF),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: selected ? Colors.white : const Color(0x14FFFFFF),
                ),
              ),
              child: Text(
                '${p.emoji} ${p.title}',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: selected ? Colors.white : AppColors.textSecondary,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _Composer extends StatefulWidget {
  const _Composer({
    required this.controller,
    required this.focusNode,
    required this.generating,
    required this.onSend,
    required this.onStop,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool generating;
  final VoidCallback onSend;
  final VoidCallback onStop;

  @override
  State<_Composer> createState() => _ComposerState();
}

class _ComposerState extends State<_Composer> {
  bool _hasText = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    final has = widget.controller.text.trim().isNotEmpty;
    if (has != _hasText) setState(() => _hasText = has);
  }

  @override
  Widget build(BuildContext context) {
    final insets = MediaQuery.viewInsetsOf(context).bottom;

    return Container(
      padding: EdgeInsets.fromLTRB(14, 10, 14, 10 + (insets > 0 ? 0 : 0)),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Color(0x12FFFFFF))),
      ),
      child: SafeArea(
        top: false,
        bottom: insets == 0,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Container(
                constraints: const BoxConstraints(maxHeight: 140),
                decoration: BoxDecoration(
                  color: const Color(0x14FFFFFF),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0x1AFFFFFF)),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 3),
                child: TextField(
                  controller: widget.controller,
                  focusNode: widget.focusNode,
                  minLines: 1,
                  maxLines: 5,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => widget.onSend(),
                  keyboardType: TextInputType.multiline,
                  style: const TextStyle(fontSize: 15, height: 1.4),
                  cursorColor: Colors.white,
                  decoration: InputDecoration(
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(vertical: 12),
                    hintText: 'Спросите что-нибудь…',
                    hintStyle: const TextStyle(color: AppColors.textFaint, fontSize: 15),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 9),
            _SendButton(
              active: widget.generating || _hasText,
              generating: widget.generating,
              onTap: widget.generating ? widget.onStop : widget.onSend,
            ),
          ],
        ),
      ),
    );
  }
}

class _SendButton extends StatelessWidget {
  const _SendButton({
    required this.active,
    required this.generating,
    required this.onTap,
  });

  final bool active;
  final bool generating;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: active
          ? () {
              HapticFeedback.mediumImpact();
              onTap();
            }
          : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          gradient: active ? AppColors.accent : null,
          color: active ? null : const Color(0x14FFFFFF),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Icon(
          generating ? Icons.stop_rounded : Icons.arrow_upward_rounded,
          color: active ? Colors.black : AppColors.textFaint,
          size: 22,
        ),
      ),
    );
  }
}

class _ErrorBar extends StatelessWidget {
  const _ErrorBar({required this.message, required this.onClose});

  final String message;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(14, 0, 14, 8),
      padding: const EdgeInsets.fromLTRB(13, 10, 6, 10),
      decoration: BoxDecoration(
        color: AppColors.danger.withValues(alpha: 0.13),
        borderRadius: AppRadius.chip,
        border: Border.all(color: AppColors.danger.withValues(alpha: 0.32)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline_rounded, size: 17, color: AppColors.danger),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(color: AppColors.textPrimary, fontSize: 12.5, height: 1.35),
            ),
          ),
          IconButton(
            onPressed: onClose,
            icon: const Icon(Icons.close_rounded, size: 17),
            color: AppColors.textSecondary,
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }
}

/// Свайп по сообщению справа — копирование. Дешевле, чем иконка в каждом
/// пузыре, и не загромождает интерфейс.
class _Swipeable extends StatefulWidget {
  const _Swipeable({required this.child, required this.onCopy});

  final Widget child;
  final VoidCallback onCopy;

  @override
  State<_Swipeable> createState() => _SwipeableState();
}

class _SwipeableState extends State<_Swipeable> {
  double _dx = 0;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onHorizontalDragUpdate: (d) => setState(() => _dx = (_dx + d.delta.dx).clamp(-90.0, 0.0)),
      onHorizontalDragEnd: (_) {
        if (_dx < -55) {
          widget.onCopy();
        }
        setState(() => _dx = 0);
      },
      child: Transform.translate(
        offset: Offset(_dx, 0),
        child: Stack(
          children: [
            Positioned(
              right: 12,
              top: 0,
              bottom: 0,
              child: Center(
                child: Icon(
                  Icons.copy_rounded,
                  size: 17,
                  color: AppColors.textFaint.withValues(alpha: (-_dx / 90).clamp(0.0, 1.0)),
                ),
              ),
            ),
            widget.child,
          ],
        ),
      ),
    );
  }
}
