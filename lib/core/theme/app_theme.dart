import 'package:flutter/material.dart';

/// Dark Tech palette. Dark is the product default; light is optional.
class AppColors {
  static const background = Color(0xFF0F172A);
  static const canvas = Color(0xFF1B1F23);
  static const surface = Color(0xFF1E293B);
  static const surfaceAlt = Color(0xFF252C32);
  static const elevated = Color(0xFF2B343C);
  static const border = Color(0xFF334155);
  static const text = Color(0xFFE8E9EA);
  static const textSecondary = Color(0xFF9BA0A6);
  static const primary = Color(0xFF2563EB);
  static const accent = Color(0xFF06B6D4);
  static const success = Color(0xFF10B981);
  static const warning = Color(0xFFF59E0B);
  static const error = Color(0xFFEF4444);

  static const lightBackground = Color(0xFFF4F2EE);
  static const lightSurface = Color(0xFFFFFFFF);
  static const lightBorder = Color(0xFFE0DFDC);
  static const lightText = Color(0xFF191919);
  static const lightTextSecondary = Color(0xFF666666);
}

class AppMotion {
  static const fast = Duration(milliseconds: 160);
  static const standard = Duration(milliseconds: 200);
}

class AppTheme {
  static const arabicFamily = 'IBMPlexSansArabic';
  static const latinFamily = 'Inter';

  /// Arabic glyphs are not in Inter. Every UI style falls back here.
  static const arabicFallback = <String>[arabicFamily];

  static ThemeData light() => _build(Brightness.light);
  static ThemeData dark() => _build(Brightness.dark);

  /// Latin from Inter, Arabic from IBM Plex. IBM Plex stops at weight 700.
  static TextStyle text({
    Color? color,
    double? fontSize,
    FontWeight? fontWeight,
    double? height,
    double? letterSpacing,
  }) {
    return TextStyle(
      fontFamily: latinFamily,
      fontFamilyFallback: arabicFallback,
      color: color,
      fontSize: fontSize,
      fontWeight: arabicWeight(fontWeight),
      height: height,
      letterSpacing: letterSpacing,
    );
  }

  static FontWeight? arabicWeight(FontWeight? weight) {
    if (weight == null || weight.value <= FontWeight.w700.value) {
      return weight;
    }
    return FontWeight.w700;
  }

  static ThemeData _build(Brightness brightness) {
    final isLight = brightness == Brightness.light;
    final scheme =
        ColorScheme.fromSeed(
          seedColor: AppColors.primary,
          brightness: brightness,
        ).copyWith(
          primary: AppColors.primary,
          onPrimary: Colors.white,
          secondary: AppColors.accent,
          onSecondary: isLight ? Colors.white : AppColors.background,
          error: AppColors.error,
          onError: Colors.white,
          surface: isLight ? AppColors.lightSurface : AppColors.surface,
          onSurface: isLight ? AppColors.lightText : AppColors.text,
          onSurfaceVariant: isLight
              ? AppColors.lightTextSecondary
              : AppColors.textSecondary,
          outline: isLight ? AppColors.lightBorder : AppColors.border,
          surfaceTint: Colors.transparent,
        );
    final background = isLight
        ? AppColors.lightBackground
        : AppColors.background;
    final elevated = isLight ? AppColors.lightSurface : AppColors.elevated;
    final radius = const BorderRadius.all(Radius.circular(8));
    final hairline = BorderSide(color: scheme.outline);
    final buttonLabel = AppTheme.text(
      fontSize: 14,
      fontWeight: FontWeight.w600,
      height: 1.2,
    );
    final pill = FilledButton.styleFrom(
      minimumSize: const Size(44, 44),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      shape: const StadiumBorder(),
      textStyle: buttonLabel,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: background,
      canvasColor: isLight ? AppColors.lightBackground : AppColors.canvas,
      fontFamily: latinFamily,
      fontFamilyFallback: arabicFallback,
      splashFactory: InkSparkle.splashFactory,
      iconTheme: IconThemeData(color: scheme.onSurface),
      dividerTheme: DividerThemeData(
        color: scheme.outline,
        thickness: 1,
        space: 1,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isLight ? AppColors.lightSurface : AppColors.surfaceAlt,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
        hintStyle: AppTheme.text(color: scheme.onSurfaceVariant),
        border: OutlineInputBorder(borderRadius: radius, borderSide: hairline),
        enabledBorder: OutlineInputBorder(
          borderRadius: radius,
          borderSide: hairline,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: radius,
          borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 1,
        shadowColor: const Color(0x140F172A),
        surfaceTintColor: Colors.transparent,
        color: scheme.surface,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: radius, side: hairline),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: elevated,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: elevated,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: isLight ? AppColors.background : AppColors.elevated,
        contentTextStyle: AppTheme.text(
          color: isLight ? AppColors.text : AppColors.text,
        ),
        shape: RoundedRectangleBorder(borderRadius: radius),
      ),
      filledButtonTheme: FilledButtonThemeData(style: pill),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(44, 44),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          shape: const StadiumBorder(),
          side: hairline,
          foregroundColor: scheme.onSurface,
          textStyle: buttonLabel,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: const Size(44, 44),
          textStyle: buttonLabel,
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(minimumSize: const Size(44, 44)),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: isLight
            ? AppColors.lightSurface
            : AppColors.surfaceAlt,
        selectedColor: AppColors.primary,
        disabledColor: scheme.surface,
        labelStyle: AppTheme.text(
          color: scheme.onSurface,
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
        secondaryLabelStyle: AppTheme.text(
          color: Colors.white,
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
        side: hairline,
        shape: const StadiumBorder(),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        elevation: 2,
        extendedPadding: EdgeInsets.symmetric(horizontal: 20),
        shape: StadiumBorder(),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: isLight ? AppColors.lightSurface : AppColors.canvas,
        indicatorColor: AppColors.primary.withValues(alpha: 0.16),
        height: 64,
        labelTextStyle: WidgetStatePropertyAll(
          AppTheme.text(fontSize: 12, fontWeight: FontWeight.w500),
        ),
      ),
      appBarTheme: AppBarTheme(
        centerTitle: false,
        backgroundColor: background,
        foregroundColor: scheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: AppTheme.text(
          color: scheme.onSurface,
          fontSize: 20,
          fontWeight: FontWeight.w700,
          height: 1.25,
        ),
        toolbarTextStyle: AppTheme.text(
          color: scheme.onSurface,
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
      ),
      textTheme: _text(scheme),
    );
  }

  static TextTheme _text(ColorScheme scheme) {
    TextStyle style(double size, FontWeight weight, {double height = 1.35}) {
      return AppTheme.text(
        fontSize: size,
        fontWeight: weight,
        height: height,
        color: scheme.onSurface,
      );
    }

    return TextTheme(
      headlineMedium: style(28, FontWeight.w700, height: 1.2),
      titleLarge: style(20, FontWeight.w700, height: 1.25),
      titleMedium: style(16, FontWeight.w600),
      titleSmall: style(14, FontWeight.w600),
      bodyLarge: style(16, FontWeight.w400),
      bodyMedium: style(14, FontWeight.w400),
      bodySmall: style(
        12,
        FontWeight.w400,
      ).copyWith(color: scheme.onSurfaceVariant),
      labelLarge: style(14, FontWeight.w600),
    );
  }
}
