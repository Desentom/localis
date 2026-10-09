import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../data/model_spec.dart';
import '../../services/device_capability.dart';
import '../../services/engine_service.dart';
import '../../services/model_downloader.dart';
import '../../state/app_controller.dart';
import '../widgets/aurora_background.dart';
import 'splash_screen.dart';

/// Экран выбора и скачивания модели.
///
/// Это главный экран конверсии. Его задача — честно объяснить, что человек
/// получит, ДО того как потратит два гигабайтра трафика. Расхождение между
/// ожиданием и реальностью здесь — основной источник плохих отзывов.
class ModelSetupScreen extends StatelessWidget {
  const ModelSetupScreen({required this.controller, super.key});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: switch (controller.phase) {
          AppPhase.downloading => _DownloadView(controller: controller),
          AppPhase.loadingModel => _LoadingView(controller: controller),
          _ => _PickerView(controller: controller),
        },
      ),
    );
  }
}

// --- Выбор модели -----------------------------------------------------------

class _PickerView extends StatelessWidget {
  const _PickerView({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final cap = controller.capability;
    final recommended = controller.recommendedModel;

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 40),
      children: [
        const OfflineBadge(),
        const SizedBox(height: 16),
        Text(
          'Выберите модель',
          style: Theme.of(context).textTheme.headlineMedium,
        ),
        const SizedBox(height: 8),
        const Text(
          'Она скачивается один раз и остаётся на телефоне. '
          'После этого интернет не нужен никогда — вопросы, ответы и '
          'домашняя работа идут внутри самого устройства.',
          style: TextStyle(color: AppColors.textSecondary, height: 1.5),
        ),
        const SizedBox(height: 22),

        if (cap != null) _DeviceCard(capability: cap),
        if (cap != null) const SizedBox(height: 20),

        ...ModelCatalog.all.map(
          (spec) => Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _ModelCard(
              spec: spec,
              installed: controller.installed.containsKey(spec.id),
              active: controller.activeModel?.id == spec.id,
              recommended: spec.id == recommended.id,
              insufficientRam:
                  cap != null &&
                  cap.freeRamBytes > 0 &&
                  cap.freeRamBytes < spec.minFreeRamBytes,
              freeRam: cap?.freeRamBytes ?? 0,
              onTap: () => _confirm(context, spec),
            ),
          ),
        ),

        const SizedBox(height: 10),
        const _HonestyNote(),
      ],
    );
  }

  Future<void> _confirm(BuildContext context, ModelSpec spec) async {
    final messenger = ScaffoldMessenger.of(context);
    final install = controller.installed.containsKey(spec.id);

    if (!install) {
      final ok = await showModalBottomSheet<bool>(
        context: context,
        backgroundColor: Colors.transparent,
        builder: (ctx) => _ConfirmSheet(spec: spec),
      );
      if (ok != true || !context.mounted) return;
    }

    try {
      await controller.selectModel(spec);
    } on Object catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Не удалось: $e')));
    }
  }
}

class _DeviceCard extends StatelessWidget {
  const _DeviceCard({required this.capability});

  final DeviceCapability capability;

  @override
  Widget build(BuildContext context) {
    final freeRam = capability.freeRamBytes;
    return GlassCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.memory_rounded, size: 17, color: AppColors.cyan),
              const SizedBox(width: 8),
              const Text(
                'Ваш телефон',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
              ),
              const Spacer(),
              Pill(
                label: capability.vulkanSupported ? 'GPU есть' : 'только CPU',
                icon: capability.vulkanSupported
                    ? Icons.bolt_rounded
                    : Icons.developer_board_rounded,
                color: capability.vulkanSupported ? AppColors.mint : AppColors.textFaint,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            '${capability.cores} ядра · '
            '${capability.totalRamBytes > 0 ? formatBytes(capability.totalRamBytes, decimals: 1) : '?'} оперативной памяти',
            style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
          ),
          if (freeRam > 0) ...[
            const SizedBox(height: 4),
            Text(
              'Свободно ${formatBytes(freeRam, decimals: 1)} — закрыйте пару приложений, если нужно больше',
              style: const TextStyle(color: AppColors.textFaint, fontSize: 12),
            ),
          ],
          if (capability.gpuProbeFailed) ...[
            const SizedBox(height: 6),
            const Text(
              'Не удалось определить видеоускорение — модель всё равно запустится, но медленнее.',
              style: TextStyle(color: AppColors.textFaint, fontSize: 11.5),
            ),
          ],
        ],
      ),
    );
  }
}

class _ModelCard extends StatelessWidget {
  const _ModelCard({
    required this.spec,
    required this.installed,
    required this.active,
    required this.recommended,
    required this.insufficientRam,
    required this.freeRam,
    required this.onTap,
  });

  final ModelSpec spec;
  final bool installed;
  final bool active;
  final bool recommended;
  final bool insufficientRam;
  final int freeRam;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final blocked = insufficientRam && !installed;

    return GlassCard(
      onTap: blocked ? null : onTap,
      borderColor: recommended && !active
          ? AppColors.violet.withValues(alpha: 0.55)
          : const Color(0x1FFFFFFF),
      padding: const EdgeInsets.all(15),
      child: Opacity(
        opacity: blocked ? 0.55 : 1.0,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  spec.title,
                  style: const TextStyle(fontSize: 16.5, fontWeight: FontWeight.w700),
                ),
                const SizedBox(width: 7),
                Pill(
                  label: ModelCatalog.tierLabel(spec.tier),
                  color: AppColors.textFaint,
                  dense: true,
                ),
                const Spacer(),
                if (active)
                  const Pill(
                    label: 'Загружена',
                    icon: Icons.check_circle_rounded,
                    color: AppColors.mint,
                    dense: true,
                  )
                else if (installed)
                  const Pill(
                    label: 'Скачана',
                    icon: Icons.download_done_rounded,
                    color: AppColors.textSecondary,
                    dense: true,
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                _MetaChip(
                  icon: Icons.save_alt_rounded,
                  label: formatBytes(spec.bytes),
                ),
                const SizedBox(width: 8),
                _MetaChip(icon: Icons.speed_rounded, label: spec.speedHint),
                const SizedBox(width: 8),
                _MetaChip(
                  icon: Icons.sd_storage_rounded,
                  label: 'нужно ${formatBytes(spec.minFreeRamBytes, decimals: 0)} ОЗУ',
                ),
              ],
            ),
            const SizedBox(height: 11),
            Text(
              spec.summary,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12.8,
                height: 1.45,
              ),
            ),
            if (recommended && !active) ...[
              const SizedBox(height: 11),
              const Row(
                children: [
                  Icon(Icons.star_rounded, size: 15, color: AppColors.violet),
                  SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Подходит для этого телефона',
                      style: TextStyle(
                        color: AppColors.violet,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ],
            if (blocked) ...[
              const SizedBox(height: 11),
              Row(
                children: [
                  const Icon(Icons.warning_amber_rounded, size: 15, color: AppColors.warning),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Свободно только ${formatBytes(freeRam, decimals: 1)} — '
                      'модель будет вылетать. Сначала освободите память.',
                      style: const TextStyle(color: AppColors.warning, fontSize: 12),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _MetaChip extends StatelessWidget {
  const _MetaChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: AppColors.textFaint),
        const SizedBox(width: 4),
        Text(
          label,
          style: const TextStyle(
            color: AppColors.textFaint,
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

/// Блок про ожидания. Честная рамка перед скачиванием — дешевле, чем отзыв.
class _HonestyNote extends StatelessWidget {
  const _HonestyNote();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: 0.07),
        borderRadius: AppRadius.card,
        border: Border.all(color: AppColors.warning.withValues(alpha: 0.22)),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline_rounded, size: 16, color: AppColors.warning),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'Честно о границах. Модель на телефоне — это не облачный '
              'сервис: она не знает новостей и не откроет сайт. Зато отвечает '
              'мгновенно, ничего не отправляет наружу и работает в метро, '
              'самолёте и в деревне.',
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12.3,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// --- Подтверждение скачивания ----------------------------------------------

class _ConfirmSheet extends StatelessWidget {
  const _ConfirmSheet({required this.spec});

  final ModelSpec spec;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.bgElevated,
        borderRadius: AppRadius.sheet,
        border: Border(top: BorderSide(color: Color(0x1FFFFFFF))),
      ),
      padding: const EdgeInsets.fromLTRB(22, 12, 22, 28),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 38,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0x33FFFFFF),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text('Скачать ${spec.title}?', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(
              '${formatBytes(spec.bytes)} трафика. Скачивание можно прервать — '
              'продолжится с того же места.',
              style: const TextStyle(color: AppColors.textSecondary, height: 1.45),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                _MetaChip(icon: Icons.speed_rounded, label: spec.speedHint),
                const SizedBox(width: 10),
                _MetaChip(icon: Icons.alternate_email_rounded, label: 'платно 0 ₽'),
              ],
            ),
            const SizedBox(height: 22),
            GradientButton(
              label: 'Скачать ${formatBytes(spec.bytes)}',
              icon: Icons.download_rounded,
              onPressed: () => Navigator.of(context).pop(true),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
                child: const Text('Отмена', style: TextStyle(color: AppColors.textSecondary)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// --- Загрузка ---------------------------------------------------------------

class _DownloadView extends StatelessWidget {
  const _DownloadView({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final state = controller.download;

    final (double progress, int received, int total, double speed) = switch (state) {
      DownloadRunning(:final received, :final total, :final bytesPerSecond) => (
        total > 0 ? received / total : 0,
        received,
        total,
        bytesPerSecond,
      ),
      DownloadVerifying() => (1.0, 1, 1, 0),
      _ => (0.0, 0, 0, 0),
    };

    final verifying = state is DownloadVerifying;
    final spec = controller.activeModel;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.memory_rounded, size: 54, color: AppColors.cyan),
            const SizedBox(height: 22),
            Text(
              verifying ? 'Проверяем файл' : 'Скачиваем модель',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              verifying
                  ? 'Сверяем контрольную сумму — это защита от битой загрузки'
                  : '${spec?.title ?? ''} · это нужно сделать один раз',
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.textSecondary, height: 1.45),
            ),
            const SizedBox(height: 26),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                value: progress == 0 ? null : progress,
                minHeight: 9,
                backgroundColor: const Color(0x1FFFFFFF),
                valueColor: const AlwaysStoppedAnimation(AppColors.cyan),
              ),
            ),
            const SizedBox(height: 14),
            Text(
              '${formatBytes(received)} из ${formatBytes(total)}'
              '${speed > 0 ? '  ·  ${formatBytes(speed, decimals: 1)}/с' : ''}',
              style: const TextStyle(color: AppColors.textFaint, fontSize: 13),
            ),
            if (controller.error != null) ...[
              const SizedBox(height: 16),
              Text(
                controller.error!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.danger, fontSize: 13, height: 1.4),
              ),
            ],
            const SizedBox(height: 24),
            const Text(
              'Не выключайте экран — экран блокировки может остановить загрузку',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textFaint, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}

// --- Загрузка модели в память -----------------------------------------------

class _LoadingView extends StatelessWidget {
  const _LoadingView({required this.controller});

  final AppController controller;

  static const _stageIcons = [Icons.storage_rounded, Icons.memory_rounded, Icons.forum_rounded];

  @override
  Widget build(BuildContext context) {
    final stage = controller.loadStage.clamp(0, EngineService.loadStages.length - 1);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(
              width: 42,
              height: 42,
              child: CircularProgressIndicator(
                strokeWidth: 3,
                valueColor: AlwaysStoppedAnimation(AppColors.violet),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Запускаем модель',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 20),
            ...List.generate(EngineService.loadStages.length, (i) {
              final done = i < stage;
              final active = i == stage;
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(
                  children: [
                    Icon(
                      done ? Icons.check_circle_rounded : _stageIcons[i.clamp(0, 2)],
                      size: 18,
                      color: done
                          ? AppColors.mint
                          : active
                          ? AppColors.violet
                          : AppColors.textFaint,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        EngineService.loadStages[i],
                        style: TextStyle(
                          fontSize: 13.5,
                          color: done || active
                              ? AppColors.textPrimary
                              : AppColors.textFaint,
                        ),
                      ),
                    ),
                    if (active)
                      const SizedBox(
                        width: 13,
                        height: 13,
                        child: CircularProgressIndicator(strokeWidth: 1.8),
                      ),
                  ],
                ),
              );
            }),
            if (controller.error != null) ...[
              const SizedBox(height: 18),
              Text(
                controller.error!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.danger, fontSize: 13, height: 1.4),
              ),
              const SizedBox(height: 18),
              TextButton.icon(
                onPressed: controller.bootstrap,
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('Перезапустить'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
