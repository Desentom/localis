import 'package:flutter/material.dart';

import 'core/theme.dart';
import 'state/app_controller.dart';
import 'ui/screens/chat_screen.dart';
import 'ui/screens/model_setup_screen.dart';
import 'ui/screens/splash_screen.dart';
import 'ui/widgets/aurora_background.dart';

/// Корневой виджет. Один экран на каждую стадию — никаких «почти готовых»
/// состояний, в которых интерфейс мигает и ломается.
class LocalisApp extends StatelessWidget {
  const LocalisApp({required this.controller, super.key});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Localis',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      // Тёмная тема всегда: мы рисуем собственный фон, и системная
      // светлая тема сломала бы переходы.
      themeMode: ThemeMode.dark,
      darkTheme: buildAppTheme(),
      home: AuroraBackground(
        child: AnimatedBuilder(
          animation: controller,
          builder: (context, _) => switch (controller.phase) {
            AppPhase.starting => const SplashScreen(),
            AppPhase.needsModel ||
            AppPhase.downloading ||
            AppPhase.loadingModel => ModelSetupScreen(controller: controller),
            AppPhase.ready => ChatScreen(controller: controller),
            AppPhase.failed => FailedScreen(controller: controller),
          },
        ),
      ),
    );
  }
}

/// Экран непоправимой ошибки запуска. Всегда с кнопкой «попробовать снова»:
/// человек не должен остаться в тупике.
class FailedScreen extends StatelessWidget {
  const FailedScreen({required this.controller, super.key});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error_outline_rounded, size: 52, color: AppColors.warning),
                const SizedBox(height: 18),
                const Text(
                  'Что-то пошло не так',
                  style: TextStyle(fontSize: 21, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 10),
                Text(
                  controller.error ?? 'Неизвестная ошибка',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppColors.textSecondary, height: 1.45),
                ),
                const SizedBox(height: 26),
                SizedBox(
                  width: 200,
                  child: FilledButton(
                    onPressed: controller.bootstrap,
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF141414),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: const Text('Попробовать снова'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
