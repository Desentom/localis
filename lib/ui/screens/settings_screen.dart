import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../core/version.dart';
import '../../data/model_spec.dart';
import '../../data/personas.dart';
import '../../services/auth_service.dart';
import '../../state/app_controller.dart';
import '../widgets/aurora_background.dart';
import 'splash_screen.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({required this.controller, super.key});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final contextCeiling = _contextCeiling(controller);

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('Настройки', style: TextStyle(fontWeight: FontWeight.w700)),
        leading: IconButton(
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(Icons.arrow_back_rounded),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
        children: [
          _StatusCard(controller: controller),
          const SizedBox(height: 22),

          const _Section('Модель'),
          const SizedBox(height: 8),
          _ModelSwitcher(controller: controller),
          const SizedBox(height: 22),

          const _Section('Режим ответа'),
          const SizedBox(height: 8),
          _PersonaSwitcher(controller: controller),
          const SizedBox(height: 10),
          _ThinkModeTile(controller: controller),
          const SizedBox(height: 22),

          const _Section('Точность и скорость'),
          const SizedBox(height: 4),
          // Значения по умолчанию обязаны попадать точно на сетку делений,
          // иначе ползунок «прыгает» при первом открытии экрана.
          _Slider(
            title: 'Свобода ответа',
            hint: 'Ниже — факты и повторение. Выше — живой текст, но иногда '
                'с выдумками.',
            value: controller.settings.temperature,
            min: 0,
            max: 1.2,
            steps: 11,
            format: (v) => v.toStringAsFixed(1).replaceAll('.', ','),
            onChanged: (v) => controller.updateSettings(
              controller.settings.copyWith(temperature: v),
            ),
          ),
          _Slider(
            title: 'Длина ответа',
            hint: 'Больше — ответ длиннее и медленнее.',
            value: controller.settings.maxTokens.toDouble(),
            min: 128,
            max: 2048,
            steps: 29,
            format: (v) => 'до ${v.round()} токенов',
            onChanged: (v) => controller.updateSettings(
              controller.settings.copyWith(maxTokens: v.round()),
            ),
          ),
          _Picker(
            title: 'Размер контекста',
            hint: contextHint(contextCeiling),
            options: contextOptions(contextCeiling),
            selected: controller.settings.contextSize,
            onChanged: (v) => controller.updateSettings(
              controller.settings.copyWith(contextSize: v),
            ),
          ),
          const SizedBox(height: 22),

          const _Section('Аккаунт'),
          const SizedBox(height: 8),
          _AccountCard(controller: controller),
          const SizedBox(height: 8),
          const _GuestNote(),
          const SizedBox(height: 22),

          const _Section('Данные'),
          const SizedBox(height: 8),
          _StorageCard(controller: controller),
          const SizedBox(height: 22),

          const _Section('О приложении'),
          const SizedBox(height: 8),
          const _AboutCard(),
          const SizedBox(height: 8),
          _DiagnosticsCard(controller: controller),
        ],
      ),
    );
  }
}

/// Максимальный контекст, который телефон потянет для текущей модели.
///
/// Ползунок не даёт выставить больше, чем реально влезает: иначе человек
/// выставил бы 8 тысяч токенов, получил бы ужатый до 2 тысяч контекст и
/// решил бы, что приложение не работает. Ограничение объяснено подписью.
int _contextCeiling(AppController controller) {
  const top = 8192;
  final spec = controller.activeModel;
  final free = controller.capability?.freeRamBytes ?? 0;
  if (spec == null || free <= 0) return top;

  final affordable = ModelCatalog.fitContext(spec, free, top);
  // Шаг ползунка — 1024 токена, округляем вниз, чтобы ползунок не упирался.
  final rounded = (affordable ~/ 1024) * 1024;
  return rounded < 1024 ? 1024 : rounded;
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final model = controller.activeModel;
    final cap = controller.capability;
    final outcome = controller.loadOutcome;

    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.focus, width: 1.5),
                ),
                child: const Icon(Icons.memory_rounded, size: 20, color: Colors.white),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      model?.title ?? 'Модель не выбрана',
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 2),
                    const OfflineBadge(compact: true),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          const Divider(),
          const SizedBox(height: 12),
          if (cap != null)
            _Row(
              label: 'Телефон',
              value: cap.summary,
            ),
          if (outcome != null)
            _Row(
              label: 'Загрузка модели',
              value: formatDuration(outcome.loadedIn),
            ),
          if (outcome != null && outcome.contextShrunk)
            _Row(
              label: 'Контекст',
              value:
                  '${outcome.contextSize} вместо ${outcome.requestedContext} — '
                  'не хватило памяти',
            ),
          _Row(
            label: 'Режим ответа',
            value: '${controller.persona.emoji} ${controller.persona.title}',
          ),
          const SizedBox(height: 6),
          const Text(
            'Все вычисления идут на этом устройстве. Ни один вопрос '
            'не покидает телефон.',
            style: TextStyle(color: AppColors.textFaint, fontSize: 12, height: 1.45),
          ),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(
              label,
              style: const TextStyle(color: AppColors.textFaint, fontSize: 12.5),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text(
        title.toUpperCase(),
        style: const TextStyle(
          color: AppColors.textFaint,
          fontSize: 11,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.1,
        ),
      ),
    );
  }
}

class _ModelSwitcher extends StatelessWidget {
  const _ModelSwitcher({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: ModelCatalog.all.map((spec) {
        final installed = controller.installed.containsKey(spec.id);
        final active = controller.activeModel?.id == spec.id;
        final loading = controller.phase == AppPhase.loadingModel;
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Material(
            color: active ? const Color(0xFF1F1F1F) : const Color(0x10FFFFFF),
            borderRadius: AppRadius.card,
            child: InkWell(
              borderRadius: AppRadius.card,
              onTap: () => controller.selectModel(spec),
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  borderRadius: AppRadius.card,
                  border: Border.all(
                    color: active ? Colors.white : const Color(0x12FFFFFF),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      active ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
                      size: 19,
                      color: active ? Colors.white : AppColors.textFaint,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  spec.title,
                                  style: const TextStyle(
                                    fontSize: 14.5,
                                    fontWeight: FontWeight.w700,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              // Метка активной модели — раньше её можно было
                              // не заметить, и выглядело так, будто выбор
                              // не сработал.
                              if (active) ...[
                                const SizedBox(width: 8),
                                const Pill(
                                  label: 'загружена',
                                  icon: Icons.check_circle_rounded,
                                  color: Colors.white,
                                  dense: true,
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 3),
                          Text(
                            '${formatBytes(spec.bytes)} · ${spec.speedHint}'
                            '${installed ? '' : ' · скачать'}'
                            '${active ? '' : ' · выбрать'}',
                            style: const TextStyle(
                              fontSize: 11.8,
                              color: AppColors.textFaint,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (loading && !active)
                      const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    if (installed)
                      IconButton(
                        onPressed: () => _confirmDelete(context, spec),
                        icon: const Icon(Icons.delete_outline_rounded, size: 18),
                        color: AppColors.textFaint,
                        visualDensity: VisualDensity.compact,
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Future<void> _confirmDelete(BuildContext context, ModelSpec spec) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.bgElevated,
        title: const Text('Удалить модель?'),
        content: Text(
          'Файл ${formatBytes(spec.bytes)} будет удалён с телефона. '
          'Скачать его заново можно будет в любой момент.',
          style: const TextStyle(color: AppColors.textSecondary, height: 1.45),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Удалить', style: TextStyle(color: AppColors.danger)),
          ),
        ],
      ),
    );
    if (ok == true) await controller.deleteModel(spec);
  }
}

class _PersonaSwitcher extends StatelessWidget {
  const _PersonaSwitcher({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: Personas.all.map((p) {
        final selected = p.id == controller.settings.personaId;
        return GestureDetector(
          onTap: () {
            HapticFeedback.selectionClick();
            controller.updateSettings(controller.settings.copyWith(personaId: p.id));
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
            decoration: BoxDecoration(
              color: selected ? Colors.white.withValues(alpha: 0.22) : const Color(0x10FFFFFF),
              borderRadius: AppRadius.chip,
              border: Border.all(
                color: selected ? Colors.white : const Color(0x14FFFFFF),
              ),
            ),
            child: Text(
              '${p.emoji}  ${p.title}',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: selected ? Colors.white : AppColors.textSecondary,
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _ThinkModeTile extends StatelessWidget {
  const _ThinkModeTile({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final on = controller.settings.thinkMode;
    return GlassCard(
      padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
      child: Row(
        children: [
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Режим «подумать»',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                ),
                SizedBox(height: 3),
                Text(
                  'Просит модель сначала спланировать ответ. Медленнее, '
                  'но на уравнениях и логике ошибок меньше.',
                  style: TextStyle(
                    color: AppColors.textFaint,
                    fontSize: 11.8,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
          Switch(
            value: on,
            onChanged: (v) => controller.updateSettings(
              controller.settings.copyWith(thinkMode: v),
            ),
            activeThumbColor: Colors.white,
            activeTrackColor: Colors.white,
          ),
        ],
      ),
    );
  }
}

class _Slider extends StatelessWidget {
  const _Slider({
    required this.title,
    required this.hint,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.steps,
    this.format,
  });

  final String title;
  final String hint;
  final double value;
  final double min;
  final double max;
  final int? steps;
  final String Function(double)? format;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    // Поле final не продвигается в null-типизацию, поэтому счётчик
    // приводим к локальной переменной.
    final divisions = steps == null ? null : steps! + 1;

    // Значение приводится к сетке делений. Flutter делает это молча,
    // и из-за этого ползунок и подпись расходились: подпись показывала
    // сохранённое число, а бегунок стоял на ближайшем делении. Отсюда
    // «шкала ездит сама». Здесь округляем явно — и рисуем, и храним
    // одно и то же число.
    final snapped = divisions == null
        ? value.clamp(min, max)
        : (min + ((value - min) / _stepSize(min, max, divisions)) *
                      ((value - min) / _stepSize(min, max, divisions)).round())
                  .clamp(min, max);

    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
              const Spacer(),
              Text(
                format?.call(snapped) ??
                    snapped.toStringAsFixed(2).replaceAll('.', ','),
                style: const TextStyle(
                  fontSize: 12.5,
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          Slider(
            value: snapped,
            min: min,
            max: max,
            // В Flutter 3.47 параметр steps переименован в divisions:
            // это количество ПРОМЕЖУТКОВ, то есть на единицу больше прежнего steps.
            divisions: divisions,
            onChanged: onChanged,
          ),
          Text(
            hint,
            style: const TextStyle(color: AppColors.textFaint, fontSize: 11.5, height: 1.4),
          ),
        ],
      ),
    );
  }

  static double _stepSize(double min, double max, int divisions) =>
      (max - min) / divisions;
}

/// Размеры контекста, которые телефон действительно потянет.
///
/// Не ползунок, а выбор из списка: у ползунка верхняя граница зависит от
/// свободной памяти, и вместе с ней ломается сетка делений — бегунок
/// уезжает, а подпись показывает другое число. Список делает все значения
/// заранее корректными.
List<int> contextOptions(int ceiling) => [for (final v in [1024, 2048, 4096, 8192]) if (v <= ceiling) v];

String contextHint(int ceiling) => ceiling < 8192
    ? 'Сейчас доступно не больше ${(ceiling / 1024).round()} тыс. токенов — '
          'столько помещается в свободную память телефона.'
    : 'Сколько диалога модель помнит. Больше — больше памяти.';

/// Переключатель из конечного списка. Для небольшого набора значений
/// честнее кнопки, чем ползунок: человек видит все варианты сразу.
class _Picker extends StatelessWidget {
  const _Picker({
    required this.title,
    required this.hint,
    required this.options,
    required this.selected,
    required this.onChanged,
  });

  final String title;
  final String hint;
  final List<int> options;
  final int selected;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final values = options.contains(selected)
        ? options
        : [selected, ...options]..sort();

    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final v in values)
                GestureDetector(
                  onTap: () => onChanged(v),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 140),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 9,
                    ),
                    decoration: BoxDecoration(
                      color: v == selected
                          ? const Color(0xFF1F1F1F)
                          : const Color(0x14FFFFFF),
                      borderRadius: AppRadius.chip,
                      border: Border.all(
                        color: v == selected
                            ? AppColors.focus
                            : const Color(0x1AFFFFFF),
                      ),
                    ),
                    child: Text(
                      '${v ~/ 1024} тыс.',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: v == selected
                            ? Colors.white
                            : AppColors.textSecondary,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            hint,
            style: const TextStyle(
              color: AppColors.textFaint,
              fontSize: 11.5,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

class _AccountCard extends StatelessWidget {
  const _AccountCard({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final state = controller.account;

    return switch (state) {
      SignedInAccount(:final displayName, :final email, :final photoUrl) => GlassCard(
        child: Row(
          children: [
            CircleAvatar(
              radius: 21,
              backgroundImage: photoUrl != null ? NetworkImage(photoUrl) : null,
              child: photoUrl == null
                  ? Text(
                      (displayName ?? '?').characters.first.toUpperCase(),
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                    )
                  : null,
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    displayName ?? 'Аккаунт Google',
                    style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700),
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (email != null)
                    Text(
                      email,
                      style: const TextStyle(color: AppColors.textFaint, fontSize: 12),
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
            TextButton(
              onPressed: () => controller.auth.signOut(),
              child: const Text('Выйти'),
            ),
          ],
        ),
      ),
      AuthFailure(:final message) => GlassCard(
        borderColor: AppColors.danger.withValues(alpha: 0.3),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              message,
              style: const TextStyle(color: AppColors.danger, fontSize: 13, height: 1.4),
            ),
            const SizedBox(height: 12),
            _SignInButton(onPressed: () => controller.auth.signInWithGoogle()),
          ],
        ),
      ),
      GuestAccount() => _SignInButton(onPressed: () => controller.auth.signInWithGoogle()),
    };
  }
}

class _SignInButton extends StatelessWidget {
  const _SignInButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 46,
      child: Material(
        color: const Color(0xFF141414),
        borderRadius: BorderRadius.circular(13),
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.focus, width: 1.5),
            borderRadius: BorderRadius.circular(13),
          ),
          child: InkWell(
            onTap: onPressed,
            borderRadius: BorderRadius.circular(13),
            child: Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Логотип Google рисуем текстом — это допустимо и не тянет
                  // зависимость с картинками. Буква белая: в приложении нет
                  // цветных пикселей, и синий «G» выбивался бы из оформления.
                  // Слово «Google» рядом всё равно читается.
                  Text(
                    'G',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(width: 11),
                  const Text(
                    'Войти через Google',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _GuestNote extends StatelessWidget {
  const _GuestNote();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.fromLTRB(4, 0, 4, 0),
      child: Text(
        'Вход не обязателен. Он понадобится только когда появится облачная '
        'синхронизация истории между устройствами.',
        style: TextStyle(color: AppColors.textFaint, fontSize: 11.8, height: 1.45),
      ),
    );
  }
}

class _StorageCard extends StatelessWidget {
  const _StorageCard({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final count = controller.installed.length;
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Row(
            label: 'Моделей на телефоне',
            value: count == 0
                ? 'нет'
                : '$count ${plural(count, 'модель', 'модели', 'моделей')}',
          ),
          const SizedBox(height: 4),
          const Text(
            'Диалоги и модели лежат только на этом устройстве. Удаление '
            'приложения стирает их безвозвратно.',
            style: TextStyle(color: AppColors.textFaint, fontSize: 11.8, height: 1.45),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () async {
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    backgroundColor: AppColors.bgElevated,
                    title: const Text('Очистить историю?'),
                    content: const Text(
                      'Все диалоги будут удалены. Модели останутся на месте.',
                      style: TextStyle(color: AppColors.textSecondary, height: 1.45),
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.of(ctx).pop(false),
                        child: const Text('Отмена'),
                      ),
                      TextButton(
                        onPressed: () => Navigator.of(ctx).pop(true),
                        child: const Text('Удалить', style: TextStyle(color: AppColors.danger)),
                      ),
                    ],
                  ),
                );
                if (ok == true) {
                  controller.chatStore.deleteAll();
                  controller.startNewSession();
                }
              },
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.textSecondary,
                side: const BorderSide(color: Color(0x1FFFFFFF)),
                padding: const EdgeInsets.symmetric(vertical: 13),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
              ),
              icon: const Icon(Icons.delete_sweep_outlined, size: 18),
              label: const Text('Очистить историю диалогов'),
            ),
          ),
        ],
      ),
    );
  }
}

class _AboutCard extends StatelessWidget {
  const _AboutCard();

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Версия видна прямо в приложении. Раньше приходилось гадать по
          // скриншоту, какая сборка запущена: в заголовке значилась модель,
          // которой в новом каталоге уже нет, и вывод делался неверный.
          const _Row(label: 'Версия', value: appVersion),
          const _Row(label: 'Движок', value: 'llama.cpp, libllama.so'),
          const _Row(label: 'Формат диалога', value: 'ChatML, вручную'),
          const _Row(label: 'Модели', value: 'Qwen 2.5 / Qwen 3 Instruct'),
          const _Row(label: 'Лицензия модели', value: 'Apache 2.0 (Qwen)'),
          const SizedBox(height: 6),
          const Text(
            'Приложение бесплатное и останется таким: токены считает телефон, '
            'поэтому себестоимость ответа равна нулю.',
            style: TextStyle(
              color: AppColors.textFaint,
              fontSize: 11.8,
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }
}

/// Экранирует текст так, чтобы его было видно целиком в одну строку.
///
/// Без этого отчёт невозможно прочитать: модель могла вернуть тысячи
/// переносов, и в буфер обмена попал бы неразличимый блок.
String _escape(String raw, {int limit = 400}) {
  final cut = raw.length > limit ? '${raw.substring(0, limit)}…' : raw;
  return cut
      .replaceAll('\\', '\\\\')
      .replaceAll('\n', '\\n')
      .replaceAll('\r', '\\r')
      .replaceAll('\t', '\\t');
}

/// Версия приложения и полная диагностика одним нажатием.
///
/// Понимание, какая сборка стоит, какая модель загружена и что с
/// контекстом, экономит больше времени, чем любые догадки о том, почему
/// модель не отвечает.
class _DiagnosticsCard extends StatelessWidget {
  const _DiagnosticsCard({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final cap = controller.capability;
    final out = controller.activeModel;

    String value() {
      final b = StringBuffer();
      b.writeln('Localis $appVersion');
      b.writeln('Модель: ${out?.title ?? 'нет'} (${out?.id ?? '—'})');
      b.writeln('Файл: ${out?.fileName ?? '—'}');
      b.writeln(
        'Контекст: ${controller.effectiveContextSize} из '
        '${controller.settings.contextSize}',
      );
      b.writeln('Ядер: ${cap?.cores ?? 0}');
      b.writeln('Свободно RAM: ${formatBytes(cap?.freeRamBytes ?? 0, decimals: 2)}');
      b.writeln('Vulkan: ${cap?.vulkanSupported ?? false ? 'да' : 'нет'}');
      b.writeln('Движок: llama_flutter_android');
      if (controller.error != null) b.writeln('Ошибка: ${controller.error}');
      b.writeln('Сообщений в диалоге: ${controller.session.messages.length}');
      b.writeln(
        'Ответ модели (${controller.lastRawOutput.length} симв.): '
        '${_escape(controller.lastRawOutput)}',
      );
      b.writeln('Промпт: ${_escape(controller.lastPrompt)}');
      return b.toString();
    }

    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Диагностика',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          const Text(
            'Нажмите, чтобы скопировать отчёт о телефоне и модели.',
            style: TextStyle(
              color: AppColors.textFaint,
              fontSize: 11.8,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 12),
          GradientButton(
            label: 'Скопировать отчёт',
            icon: Icons.copy_all_rounded,
            onPressed: () async {
              final messenger = ScaffoldMessenger.of(context);
              await Clipboard.setData(ClipboardData(text: value()));
              messenger.showSnackBar(
                const SnackBar(content: Text('Отчёт скопирован')),
              );
            },
          ),
        ],
      ),
    );
  }
}
