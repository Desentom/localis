import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Тёмная тема приложения. Основная идея — «стекло» поверх живой градиентной
/// подложки: пользователь сразу видит, что интерфейс локальный и лёгкий.
abstract final class AppColors {
  static const bg = Color(0xFF07080D);
  static const bgElevated = Color(0xFF0E1018);

  static const violet = Color(0xFF7C5CFF);
  static const cyan = Color(0xFF22D3EE);
  static const mint = Color(0xFF34E5A3);

  static const textPrimary = Color(0xFFF2F4F8);
  static const textSecondary = Color(0xFF9AA3B5);
  static const textFaint = Color(0xFF5E6678);

  static const danger = Color(0xFFFF6B6B);
  static const warning = Color(0xFFFFB84D);

  /// Градиент фирменного акцента.
  static const accent = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [violet, cyan],
  );

  static const cardBorder = BorderSide(color: Color(0x1AFFFFFF));
}

abstract final class AppRadius {
  static const card = BorderRadius.all(Radius.circular(22));
  static const bubble = BorderRadius.all(Radius.circular(20));
  static const chip = BorderRadius.all(Radius.circular(14));
  static const sheet = BorderRadius.vertical(top: Radius.circular(28));
}

ThemeData buildAppTheme() {
  const scheme = ColorScheme.dark(
    primary: AppColors.violet,
    onPrimary: Colors.white,
    secondary: AppColors.cyan,
    onSecondary: Color(0xFF04252B),
    surface: AppColors.bgElevated,
    onSurface: AppColors.textPrimary,
    error: AppColors.danger,
    onError: Colors.white,
  );

  final base = ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    brightness: Brightness.dark,
    scaffoldBackgroundColor: AppColors.bg,
    fontFamily: 'Roboto',
    splashFactory: InkSparkle.splashFactory,
  );

  return base.copyWith(
    textTheme: base.textTheme
        .apply(
          bodyColor: AppColors.textPrimary,
          displayColor: AppColors.textPrimary,
        )
        .copyWith(
          headlineMedium: const TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.6,
          ),
          titleLarge: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700),
          titleMedium: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          bodyLarge: const TextStyle(fontSize: 15.5, height: 1.45),
          bodyMedium: const TextStyle(
            fontSize: 14,
            height: 1.45,
            color: AppColors.textSecondary,
          ),
          labelLarge: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          labelSmall: const TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.3,
          ),
        ),
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      centerTitle: false,
      systemOverlayStyle: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
      ),
    ),
    dividerTheme: const DividerThemeData(
      color: Color(0x14FFFFFF),
      thickness: 1,
      space: 1,
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: const Color(0xFF1A1D28),
      behavior: SnackBarBehavior.floating,
      shape: const RoundedRectangleBorder(borderRadius: AppRadius.chip),
      contentTextStyle: const TextStyle(color: AppColors.textPrimary),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
    ),
    sliderTheme: SliderThemeData(
      activeTrackColor: AppColors.violet,
      inactiveTrackColor: const Color(0x22FFFFFF),
      thumbColor: Colors.white,
      overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
      trackHeight: 4,
    ),
  );
}
