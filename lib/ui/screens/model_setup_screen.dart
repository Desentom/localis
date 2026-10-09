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
/// Главный экран конверсии. Его задача — честно объяснить, что человек
/// получит, ДО того как потратит два гигабайта трафика.
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
    final freeRam = cap?.freeRamBytes ?? 0;

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 40),
      children: [
        const OfflineBadge(),
        const SizedBox(height: 16),
        Text('Выберите модель', style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: 8),
        const Text(
          'Она скачивается один раз и остаётся на телефоне. '
          'После этого интернет не нужен никогда.',
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
              fit: ModelCatalog.fitFor(spec, freeRam),
              freeRam: freeRam,
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
        builder: (ctx) => _ConfirmSheet(
          spec: spec,
          fit: ModelCatalog.fitFor(spec, controller.capability?.freeRamBytes ?? 0),
          freeRam: controller.capability?.freeRamBytes ?? 0,
        ),
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
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppSurfaces.card,
        borderRadius: AppRadius.card,
        border: Border.all(color: AppSurfaces.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.memory_rounded, size: 17, color: Colors.white),
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
                color: capability.vulkanSupported
                    ? AppColors.textPrimary
                    : AppColors.textFaint,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            '${capability.cores} ядра · '
            '${capability.totalRamBytes > 0 ? formatBytes(capability.totalRamBytes, decimals: 1) : '?'} оперативной памяти',
            style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
          ),
          if (capability.freeRamBytes > 0) ...[
            const SizedBox(height: 4),
            Text(
              'Свободно сейчас ${formatBytes(capability.freeRamBytes, decimals: 2)}',
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
    required this.fit,
    required this.freeRam,
    required this.onTap,
  });

  final ModelSpec spec;
  final bool installed;
  final bool active;
  final bool recommended;
  final ModelFit fit;
  final int freeRam;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // Блокируем только когда памяти не хватит физически. Раньше здесь стоял
    // запрет на любой модели, у которой не хватало комфортного запаса, —
    // из-за этого телефон с 1,6 ГБ свободной памяти не мог выбрать вообще
    // ничего, даже самую лёгкую модель. Теперь выбор открыт всегда,
    // и тупика «не нажимается ни одна карточка» не существует.
    final blocked = !ModelCatalog.isSelectable(spec, freeRam);

    return Opacity(
      opacity: blocked ? 0.5 : 1.0,
      child: Material(
        color: active ? AppSurfaces.cardRaised : AppSurfaces.card,
        borderRadius: AppRadius.card,
        child: InkWell(
          onTap: blocked ? null : onTap,
          borderRadius: AppRadius.card,
          child: Container(
            padding: const EdgeInsets.all(15),
            decoration: BoxDecoration(
              borderRadius: AppRadius.card,
              border: Border.all(
                color: active
                    ? Colors.white
                    : recommended
                    ? AppSurfaces.borderStrong
                    : AppSurfaces.border,
                width: active ? 1.5 : 1,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      spec.title,
                      style: const TextStyle(
                        fontSize: 16.5,
                        fontWeight: FontWeight.w700,
                      ),
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
                        color: Colors.white,
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
                Wrap(
                  spacing: 14,
                  runSpacing: 4,
                  children: [
                    _MetaChip(
                      icon: Icons.save_alt_rounded,
                      label: formatBytes(spec.bytes),
                    ),
                    _MetaChip(
                      icon: Icons.speed_rounded,
                      label: spec.speedHint,
                    ),
                    _MetaChip(
                      icon: Icons.memory_rounded,
                      label: 'нужно ${formatBytes(spec.minFreeRamBytes, decimals: 1)}',
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
                      Icon(Icons.star_rounded, size: 15, color: Colors.white),
                      SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'Лучший выбор для этого телефона',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
                if (fit == ModelFit.tight && !active) ...[
                  const SizedBox(height: 11),
                  _Note(
                    icon: Icons.info_outline_rounded,
                    text:
                        'Памяти впритык: свободно '
                        '${formatBytes(freeRam, decimals: 1)}, нужно около '
                        '${formatBytes(spec.minFreeRamBytes, decimals: 1)}. '
                        'Закройте пару приложений — иначе система начнёт '
                        'выгружать память в диск, и ответы замедлятся.',
                  ),
                ],
                if (fit == ModelFit.impossible) ...[
                  const SizedBox(height: 11),
                  _Note(
                    icon: Icons.block_rounded,
                    text: spec.id == ModelCatalog.all.first.id
                        ? 'Свободно ${formatBytes(freeRam, decimals: 1)} — это мало '
                              'даже для самой лёгкой модели. Закройте приложения '
                              'на телефоне и попробуйте снова. Если не поможет — '
                              'модель можно скачать, а запустить позже.'
                        : 'Свободно ${formatBytes(freeRam, decimals: 1)} — для этой '
                              'модели нужно не меньше '
                              '${formatBytes(spec.hardFloorRamBytes, decimals: 1)}. '
                              'Возьмите модель поменьше или закройте приложения.',
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Note extends StatelessWidget {
  const _Note({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFF131313),
        borderRadius: AppRadius.chip,
        border: Border.all(color: AppSurfaces.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 14, color: AppColors.textSecondary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 11.8,
                height: 1.45,
              ),
            ),
          ),
        ],
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
        color: AppSurfaces.card,
        borderRadius: AppRadius.card,
        border: Border.all(color: AppSurfaces.border),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline_rounded, size: 16, color: AppColors.textSecondary),
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
  const _ConfirmSheet({
    required this.spec,
    required this.fit,
    required this.freeRam,
  });

  final ModelSpec spec;
  final ModelFit fit;
  final int freeRam;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadius.sheet,
        border: Border(top: BorderSide(color: AppSurfaces.border)),
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
                  color: AppSurfaces.borderStrong,
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
            if (fit == ModelFit.tight) ...[
              const SizedBox(height: 14),
              const _Note(
                icon: Icons.info_outline_rounded,
                text: 'Памяти немного. Модель запустится, но при ответе '
                    'телефон может подтормаживать — это нормально.',
              ),
            ],
            const SizedBox(height: 16),
            Wrap(
              spacing: 14,
              runSpacing: 6,
              children: [
                _MetaChip(icon: Icons.speed_rounded, label: spec.speedHint),
                _MetaChip(
                  icon: Icons.memory_rounded,
                  label: 'нужно ${formatBytes(spec.minFreeRamBytes, decimals: 1)}',
                ),
                const _MetaChip(
                  icon: Icons.alternate_email_rounded,
                  label: 'бесплатно',
                ),
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
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: const Text(
                  'Отмена',
                  style: TextStyle(color: AppColors.textSecondary),
                ),
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
            const Icon(Icons.memory_rounded, size: 54, color: Colors.white),
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
                minHeight: 6,
                backgroundColor: const Color(0x22FFFFFF),
                valueColor: const AlwaysStoppedAnimation(Colors.white),
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
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 13,
                  height: 1.4,
                  fontWeight: FontWeight.w600,
                ),
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

  static const _stageIcons = [
    Icons.storage_rounded,
    Icons.memory_rounded,
    Icons.forum_rounded,
  ];

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
              width: 34,
              height: 34,
              child: CircularProgressIndicator(strokeWidth: 2.4),
            ),
            const SizedBox(height: 24),
            Text('Запускаем модель', style: Theme.of(context).textTheme.titleLarge),
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
                      color: done || active
                          ? Colors.white
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
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 13,
                  height: 1.4,
                  fontWeight: FontWeight.w600,
                ),
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
