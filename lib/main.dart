import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app.dart';
import 'data/chat_store.dart';
import 'data/settings_store.dart';
import 'services/auth_service.dart';
import 'services/engine_service.dart';
import 'services/model_downloader.dart';
import 'state/app_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Тёмная тема фиксирована: приложение должно выглядеть одинаково
  // и не «перекраиваться» при смене системной темы.
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: Color(0xFF000000),
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );

  // Записи крашей без согласия пользователя не отправляем.
  // Пока файла google-services.json нет, Firebase не инициализируется,
  // и приложение спокойно работает в гостевом режиме.
  await FirebaseBootstrap.run();

  final settingsStore = await SettingsStore.open();
  final chatStore = await ChatStore.open();

  final controller = AppController(
    settingsStore: settingsStore,
    chatStore: chatStore,
    downloader: ModelDownloader(),
    engine: EngineService(),
    auth: AuthService(),
  );

  runApp(LocalisApp(controller: controller));

  // Стартуем после первого кадра, чтобы не блокировать показ окна.
  WidgetsBinding.instance.addPostFrameCallback((_) {
    controller.bootstrap();
  });
}

/// Обёртка над инициализацией Firebase.
///
/// Важно: любая ошибка здесь НЕ должна мешать запуску. Приложение
/// полностью работоспособно без аккаунта — все вычисления на устройстве.
abstract final class FirebaseBootstrap {
  static Future<void> run() async {
    try {
      // Подключается, когда firebase_core реально нужен. Пока файла
      // google-services.json нет, этот блок остаётся выключенным,
      // чтобы `flutter run` работал «из коробки».
      //
      // await Firebase.initializeApp(
      //   options: DefaultFirebaseOptions.currentPlatform,
      // );
    } on Object {
      // Работаем как гости.
    }
  }
}
