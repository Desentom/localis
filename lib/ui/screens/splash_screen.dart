import 'package:flutter/material.dart';

import '../../core/theme.dart';

/// Стартовый экран. Пока идёт проба устройства и чтение настроек —
/// показываем, что происходит, и сколько ядер нашли. Это честнее
/// вечного спиннера: человек понимает, что приложение не зависло.
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const _Logo(),
            const SizedBox(height: 26),
            const SizedBox(
              width: 26,
              height: 26,
              child: CircularProgressIndicator(
                strokeWidth: 2.4,
                valueColor: AlwaysStoppedAnimation(Colors.white),
              ),
            ),
            const SizedBox(height: 18),
            Text(
              'Готовим телефон к работе',
              style: TextStyle(
                fontSize: 14,
                color: AppColors.textSecondary.withValues(alpha: 0.9),
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Проверяем процессор и память',
              style: TextStyle(fontSize: 12, color: AppColors.textFaint),
            ),
          ],
        ),
      ),
    );
  }
}

class _Logo extends StatelessWidget {
  const _Logo();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 74,
          height: 74,
          decoration: BoxDecoration(
            gradient: AppColors.accent,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: Colors.white.withValues(alpha: 0.18),
                blurRadius: 30,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: const Icon(Icons.memory_rounded, size: 38, color: Colors.black),
        ),
        const SizedBox(height: 18),
        const Text(
          'Localis',
          style: TextStyle(fontSize: 25, fontWeight: FontWeight.w800, letterSpacing: -0.5),
        ),
        const SizedBox(height: 6),
        Text(
          'нейросеть, которая живёт на телефоне',
          style: TextStyle(
            fontSize: 12.5,
            color: AppColors.textFaint.withValues(alpha: 0.95),
          ),
        ),
      ],
    );
  }
}

/// Баннер «мы считаем локально». Показываем его на старте и в шапке чата —
/// это главное отличие от облачных конкурентов, и оно должно быть видно.
class OfflineBadge extends StatelessWidget {
  const OfflineBadge({super.key, this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.wifi_off_rounded,
          size: compact ? 13 : 15,
          color: Colors.white.withValues(alpha: 0.9),
        ),
        SizedBox(width: compact ? 5 : 7),
        Text(
          compact ? 'Без сети' : 'Полностью на вашем телефоне · без сети',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.9),
            fontSize: compact ? 11 : 12.5,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.2,
          ),
        ),
      ],
    );
  }
}
