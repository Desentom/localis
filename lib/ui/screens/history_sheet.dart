import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../data/chat_message.dart';
import '../../data/model_spec.dart';
import '../../state/app_controller.dart';
import '../widgets/aurora_background.dart';

/// История диалогов. Всё локально, без аккаунта и без сети.
class HistorySheet extends StatelessWidget {
  const HistorySheet({required this.controller, super.key});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final sessions = controller.history();
    final currentId = controller.session.id;

    return DraggableScrollableSheet(
      initialChildSize: 0.72,
      minChildSize: 0.4,
      maxChildSize: 0.94,
      builder: (context, scrollController) => Container(
        decoration: const BoxDecoration(
          color: AppColors.bgElevated,
          borderRadius: AppRadius.sheet,
          border: Border(top: BorderSide(color: Color(0x1FFFFFFF))),
        ),
        child: Column(
          children: [
            const SizedBox(height: 12),
            Container(
              width: 38,
              height: 4,
              decoration: BoxDecoration(
                color: const Color(0x33FFFFFF),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
              child: Row(
                children: [
                  const Text(
                    'История',
                    style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(width: 10),
                  if (sessions.isNotEmpty)
                    Pill(
                      label: '${sessions.length}',
                      color: AppColors.textFaint,
                      dense: true,
                    ),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: () {
                      controller.startNewSession();
                      Navigator.of(context).pop();
                    },
                    icon: const Icon(Icons.add_rounded, size: 18),
                    label: const Text('Новый'),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: sessions.isEmpty
                  ? const _EmptyHistory()
                  : ListView.builder(
                      controller: scrollController,
                      padding: const EdgeInsets.fromLTRB(12, 10, 12, 24),
                      itemCount: sessions.length,
                      itemBuilder: (context, i) => _SessionTile(
                        session: sessions[i],
                        selected: sessions[i].id == currentId,
                        onTap: () async {
                          await controller.openSession(sessions[i]);
                          if (context.mounted) Navigator.of(context).pop();
                        },
                        onDelete: () {
                          controller.chatStore.delete(sessions[i].id);
                          if (sessions[i].id == currentId) controller.startNewSession();
                          Navigator.of(context).pop();
                          // Переоткрываем лист, чтобы список обновился.
                          Future.delayed(const Duration(milliseconds: 220), () {
                            if (context.mounted) {
                              showModalBottomSheet<void>(
                                context: context,
                                backgroundColor: Colors.transparent,
                                builder: (_) => HistorySheet(controller: controller),
                              );
                            }
                          });
                        },
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SessionTile extends StatelessWidget {
  const _SessionTile({
    required this.session,
    required this.selected,
    required this.onTap,
    required this.onDelete,
  });

  final ChatSession session;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final preview = session.messages.length > 1
        ? session.messages.last.text
        : (session.messages.isEmpty ? '' : session.messages.first.text);
    final model = session.modelId == null ? null : ModelCatalog.byId(session.modelId!);

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Material(
        color: selected ? const Color(0x18FFFFFF) : Colors.transparent,
        borderRadius: AppRadius.chip,
        child: InkWell(
          onTap: onTap,
          onLongPress: onDelete,
          borderRadius: AppRadius.chip,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        session.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        preview,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12.3,
                          color: AppColors.textFaint,
                        ),
                      ),
                      if (model != null) ...[
                        const SizedBox(height: 6),
                        Pill(
                          label: '${model.title} · ${_ago(session.updatedAt)}',
                          color: AppColors.textFaint,
                          dense: true,
                        ),
                      ],
                    ],
                  ),
                ),
                IconButton(
                  onPressed: onDelete,
                  icon: const Icon(Icons.delete_outline_rounded, size: 18),
                  color: AppColors.textFaint,
                  visualDensity: VisualDensity.compact,
                  tooltip: 'Удалить',
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static String _ago(DateTime t) {
    final diff = DateTime.now().difference(t);
    if (diff.inMinutes < 1) return 'сейчас';
    if (diff.inHours < 1) return '${diff.inMinutes} мин';
    if (diff.inDays < 1) return '${diff.inHours} ч';
    if (diff.inDays < 7) return '${diff.inDays} дн';
    return '${t.day}.${t.month}';
  }
}

class _EmptyHistory extends StatelessWidget {
  const _EmptyHistory();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(30),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.forum_outlined, size: 44, color: AppColors.textFaint),
            const SizedBox(height: 14),
            const Text(
              'Пока пусто',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 7),
            const Text(
              'Диалоги сохраняются на этом телефоне и никуда не отправляются.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textSecondary, fontSize: 13, height: 1.45),
            ),
          ],
        ),
      ),
    );
  }
}
