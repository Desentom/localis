import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Монохромная тема.
///
/// В основе решения лежит не вкус, а техника: на телефоне с 3–4 ГБ
/// оперативной памяти каждый сэкранды градиентного фона — это лишняя
/// перерисовка GPU. Здесь нет ни одного цветного пикселя: иерархия
/// строится на весе шрифта, рамках и значках, а не на оттенке.
abstract final class AppColors {
  /// Чистый чёрный. Экономит память композитора и отключает
  /// перерисовку фона на OLED-экранах.
  static const bg = Color(0xFF000000);
  static const surface = Color(0xFF0A0A0A);
  static const elevated = Color(0xFF121212);

  /// Заметка, диалог, карточка поверх [elevated]. Историческое имя
  /// оставлено, чтобы не трогать все места использования.
  static const bgElevated = elevated;

  /// Белый — единственный акцент приложения.
  static const textPrimary = Color(0xFFFFFFFF);
  static const textSecondary = Color(0xFFA6A6A6);
  static const textFaint = Color(0xFF6E6E6E);

  static const danger = Color(0xFFFFFFFF);
  static const warning = Color(0xFFFFFFFF);

  static const accent = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFFFFFFF), Color(0xFFCFCFCF)],
  );

  static const cardBorder = BorderSide(color: Color(0x1FFFFFFF));
}

/// Фон карточек и панелей: полупрозрачный белый слоем на чёрном.
abstract final class AppSurfaces {
  static const card = Color(0xFF0A0A0A);
  static const cardRaised = Color(0xFF141414);
  static const border = Color(0xFF232323);
  static const borderStrong = Color(0xFF3A3A3A);
}

abstract final class AppRadius {
  static const card = BorderRadius.all(Radius.circular(22));
  static const bubble = BorderRadius.all(Radius.circular(20));
  static const chip = BorderRadius.all(Radius.circular(14));
  static const sheet = BorderRadius.vertical(top: Radius.circular(28));
}

ThemeData buildAppTheme() {
  const scheme = ColorScheme.dark(
    primary: Colors.white,
    onPrimary: Colors.black,
    secondary: Color(0xFFA6A6A6),
    onSecondary: Colors.black,
    surface: AppColors.surface,
    onSurface: AppColors.textPrimary,
    error: Colors.white,
    onError: Colors.black,
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
      backgroundColor: AppColors.elevated,
      behavior: SnackBarBehavior.floating,
      shape: const RoundedRectangleBorder(borderRadius: AppRadius.chip),
      contentTextStyle: const TextStyle(color: AppColors.textPrimary),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
    ),
    sliderTheme: SliderThemeData(
      activeTrackColor: Colors.white,
      inactiveTrackColor: const Color(0x22FFFFFF),
      thumbColor: Colors.white,
      overlayColor: const Color(0x14FFFFFF),
      overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
      trackHeight: 3,
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: Colors.white,
      linearTrackColor: Color(0x22FFFFFF),
      circularTrackColor: Color(0x22FFFFFF),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? Colors.white : const Color(0xFF8A8A8A),
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? const Color(0xFF5A5A5A) : const Color(0xFF1C1C1C),
      ),
      trackOutlineColor: WidgetStateProperty.all(AppSurfaces.border),
    ),
  );
}
