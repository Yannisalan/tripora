import 'package:flutter/material.dart';

/// Semantic brand palette (light).
///
/// Accent values are chosen to meet WCAG AA contrast (>= 4.5:1) when used as
/// filled status surfaces with white foreground, and >= 3:1 for large/UI.
class AppColors {
  AppColors._();

  static const Color primary = Color(0xFF2563EB);
  static const Color primaryDark = Color(0xFF1D4ED8);
  static const Color secondary = Color(0xFF0F766E);
  static const Color tertiary = Color(0xFFC2410C);
  static const Color success = Color(0xFF15803D);
  static const Color warning = Color(0xFFB45309);
  static const Color error = Color(0xFFB91C1C);
  static const Color info = Color(0xFF1D4ED8);

  // Vibrant brand gradient endpoints for a premium, modern travel look.
  // Darker endpoints improve contrast for white label text on the gradient.
  static const Color gradientStart = Color(0xFF1D4ED8);
  static const Color gradientMid = Color(0xFF6D28D9);
  static const Color gradientEnd = Color(0xFF0E7490);

  // Deeper gradient for buttons / primary actions (white text AA-compliant).
  static const Color gradientStrongStart = Color(0xFF1E40AF);
  static const Color gradientStrongEnd = Color(0xFF5B21B6);

  static const Color background = Color(0xFFF8FAFC);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color textPrimary = Color(0xFF0F172A);
  static const Color textSecondary = Color(0xFF334155);
  static const Color textMuted = Color(0xFF64748B);
  static const Color border = Color(0xFFE2E8F0);
  static const Color overlay = Color(0x66000000);

  // Light surface tints used for info/feature cards.
  static const Color surfaceInfo = Color(0xFFEFF6FF);
  static const Color surfaceSecondary = Color(0xFFF5F3FF);
  static const Color surfaceAccent = Color(0xFFECFEFF);

  // Convenient reusable brand gradients.
  static const LinearGradient brandGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      gradientStart,
      gradientMid,
      gradientEnd,
    ],
  );

  static const LinearGradient brandStrongGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      gradientStrongStart,
      gradientStrongEnd,
    ],
  );
}

/// Semantic palette used in dark theme.
class AppColorsDark {
  AppColorsDark._();

  static const Color primary = Color(0xFF93C5FD);
  static const Color primaryDark = Color(0xFFBFDBFE);
  static const Color secondary = Color(0xFF5EEAD4);
  static const Color tertiary = Color(0xFFFDBA74);
  static const Color success = Color(0xFF4ADE80);
  static const Color warning = Color(0xFFFCD34D);
  static const Color error = Color(0xFFFCA5A5);
  static const Color info = Color(0xFF93C5FD);

  static const Color background = Color(0xFF0B1120);
  static const Color surface = Color(0xFF141C2E);
  static const Color surfaceElevated = Color(0xFF1E293B);
  static const Color textPrimary = Color(0xFFF1F5F9);
  static const Color textSecondary = Color(0xFFCBD5E1);
  static const Color textMuted = Color(0xFF94A3B8);
  static const Color border = Color(0xFF334155);
  static const Color overlay = Color(0x99000000);

  static const Color surfaceInfo = Color(0xFF1E2A4D);
  static const Color surfaceSecondary = Color(0xFF2A2350);
  static const Color surfaceAccent = Color(0xFF103240);

  static const Color gradientStart = Color(0xFF1D4ED8);
  static const Color gradientMid = Color(0xFF6D28D9);
  static const Color gradientEnd = Color(0xFF0E7490);
  static const Color gradientStrongStart = Color(0xFF3B82F6);
  static const Color gradientStrongEnd = Color(0xFF8B5CF6);

  static const LinearGradient brandGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      gradientStart,
      gradientMid,
      gradientEnd,
    ],
  );

  static const LinearGradient brandStrongGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      gradientStrongStart,
      gradientStrongEnd,
    ],
  );
}

class AppStatusColors extends ThemeExtension<AppStatusColors> {
  const AppStatusColors({
    required this.success,
    required this.warning,
    required this.error,
    required this.info,
  });

  final Color success;
  final Color warning;
  final Color error;
  final Color info;

  static const AppStatusColors light = AppStatusColors(
    success: AppColors.success,
    warning: AppColors.warning,
    error: AppColors.error,
    info: AppColors.info,
  );

  static const AppStatusColors dark = AppStatusColors(
    success: AppColorsDark.success,
    warning: AppColorsDark.warning,
    error: AppColorsDark.error,
    info: AppColorsDark.info,
  );

  @override
  AppStatusColors copyWith({
    Color? success,
    Color? warning,
    Color? error,
    Color? info,
  }) {
    return AppStatusColors(
      success: success ?? this.success,
      warning: warning ?? this.warning,
      error: error ?? this.error,
      info: info ?? this.info,
    );
  }

  @override
  AppStatusColors lerp(ThemeExtension<AppStatusColors>? other, double t) {
    if (other is! AppStatusColors) {
      return this;
    }

    return AppStatusColors(
      success: Color.lerp(success, other.success, t) ?? success,
      warning: Color.lerp(warning, other.warning, t) ?? warning,
      error: Color.lerp(error, other.error, t) ?? error,
      info: Color.lerp(info, other.info, t) ?? info,
    );
  }
}

/// Semantic accessor so widgets can resolve palette colors from context
/// (adapts to light/dark automatically).
extension TriporaColorsX on BuildContext {
  AppStatusColors get appStatus =>
      Theme.of(this).extension<AppStatusColors>() ?? AppStatusColors.light;

  TriporaColors get triporaColors =>
      Theme.of(this).extension<TriporaColors>() ?? TriporaColors.light;

  bool get isDark => Theme.of(this).brightness == Brightness.dark;
}

class AppTheme {
  AppTheme._();

  static const Radius _radius = Radius.circular(16);
  static const BorderRadius _radiusAll = BorderRadius.all(_radius);

  static final ThemeData lightTheme = _buildLight();
  static final ThemeData darkTheme = _buildDark();

  static ThemeData _buildLight() {
    final scheme = ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      primary: AppColors.primary,
      secondary: AppColors.secondary,
      tertiary: AppColors.tertiary,
      error: AppColors.error,
      surface: AppColors.surface,
      brightness: Brightness.light,
    ).copyWith(
      surfaceContainerLowest: AppColors.surface,
      surfaceContainerLow: const Color(0xFFF1F5F9),
      surfaceContainer: const Color(0xFFEFF6FF),
    );

    return _base(scheme, TriporaColors.light);
  }

  static ThemeData _buildDark() {
    final scheme = ColorScheme.fromSeed(
      seedColor: AppColorsDark.primary,
      primary: AppColorsDark.primary,
      secondary: AppColorsDark.secondary,
      tertiary: AppColorsDark.tertiary,
      error: AppColorsDark.error,
      surface: AppColorsDark.surface,
      brightness: Brightness.dark,
    ).copyWith(
      surfaceContainerLowest: AppColorsDark.surface,
      surfaceContainerLow: AppColorsDark.surfaceElevated,
      surfaceContainer: AppColorsDark.surfaceElevated,
      surfaceContainerHighest: const Color(0xFF1E293B),
    );

    return _base(scheme, TriporaColors.dark);
  }

  static ThemeData _base(
    ColorScheme scheme,
    TriporaColors bg,
  ) {
    return ThemeData(
      useMaterial3: true,
      fontFamily: 'Arial',
      colorScheme: scheme,
      brightness: scheme.brightness,
      scaffoldBackgroundColor: bg.backgroundColor,
      canvasColor: bg.backgroundColor,
      appBarTheme: const AppBarTheme(
        elevation: 0,
        centerTitle: false,
      ).copyWith(
        backgroundColor: bg.backgroundColor,
        foregroundColor: bg.textPrimary,
        surfaceTintColor: Colors.transparent,
      ),
      cardTheme: CardThemeData(
        color: bg.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shadowColor: const Color(0x140F172A),
        shape: RoundedRectangleBorder(
          borderRadius: _radiusAll,
          side: BorderSide(color: bg.border),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: scheme.primary,
          foregroundColor: scheme.onPrimary,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: scheme.primary,
          foregroundColor: scheme.onPrimary,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: scheme.primary,
          side: BorderSide(color: scheme.primary, width: 1.4),
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 15),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: bg.surface,
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
        hintStyle: TextStyle(color: bg.textMuted),
        prefixIconColor: scheme.primary,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: bg.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: bg.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: scheme.primary, width: 1.6),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: bg.surface,
        selectedColor: scheme.primary,
        side: BorderSide(color: bg.border),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        labelStyle: const TextStyle(fontWeight: FontWeight.w600),
      ),
      dividerTheme: DividerThemeData(
        color: bg.border,
        thickness: 1,
      ),
      snackBarTheme: const SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: Color(0xFF1F2937),
        contentTextStyle: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
      ),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: scheme.primary,
      ),
      extensions: <ThemeExtension<dynamic>>[bg.appStatus],
    );
  }
}

/// Carries theme-aware (semantic) colors that adapt between light and dark.
class TriporaColors extends ThemeExtension<TriporaColors> {
  const TriporaColors({
    required this.backgroundColor,
    required this.surface,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
    required this.border,
    required this.surfaceInfo,
    required this.surfaceSecondary,
    required this.surfaceAccent,
    required this.appStatus,
  });

  static const TriporaColors light = TriporaColors(
    backgroundColor: AppColors.background,
    surface: AppColors.surface,
    textPrimary: AppColors.textPrimary,
    textSecondary: AppColors.textSecondary,
    textMuted: AppColors.textMuted,
    border: AppColors.border,
    surfaceInfo: AppColors.surfaceInfo,
    surfaceSecondary: AppColors.surfaceSecondary,
    surfaceAccent: AppColors.surfaceAccent,
    appStatus: AppStatusColors.light,
  );

  static const TriporaColors dark = TriporaColors(
    backgroundColor: AppColorsDark.background,
    surface: AppColorsDark.surface,
    textPrimary: AppColorsDark.textPrimary,
    textSecondary: AppColorsDark.textSecondary,
    textMuted: AppColorsDark.textMuted,
    border: AppColorsDark.border,
    surfaceInfo: AppColorsDark.surfaceInfo,
    surfaceSecondary: AppColorsDark.surfaceSecondary,
    surfaceAccent: AppColorsDark.surfaceAccent,
    appStatus: AppStatusColors.dark,
  );

  final Color backgroundColor;
  final Color surface;
  final Color textPrimary;
  final Color textSecondary;
  final Color textMuted;
  final Color border;
  final Color surfaceInfo;
  final Color surfaceSecondary;
  final Color surfaceAccent;
  final AppStatusColors appStatus;

  @override
  TriporaColors copyWith({
    Color? backgroundColor,
    Color? surface,
    Color? textPrimary,
    Color? textSecondary,
    Color? textMuted,
    Color? border,
    Color? surfaceInfo,
    Color? surfaceSecondary,
    Color? surfaceAccent,
    AppStatusColors? appStatus,
  }) {
    return TriporaColors(
      backgroundColor: backgroundColor ?? this.backgroundColor,
      surface: surface ?? this.surface,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      textMuted: textMuted ?? this.textMuted,
      border: border ?? this.border,
      surfaceInfo: surfaceInfo ?? this.surfaceInfo,
      surfaceSecondary: surfaceSecondary ?? this.surfaceSecondary,
      surfaceAccent: surfaceAccent ?? this.surfaceAccent,
      appStatus: appStatus ?? this.appStatus,
    );
  }

  @override
  TriporaColors lerp(ThemeExtension<TriporaColors>? other, double t) {
    if (other is! TriporaColors) {
      return this;
    }
    return TriporaColors(
      backgroundColor: Color.lerp(backgroundColor, other.backgroundColor, t) ?? backgroundColor,
      surface: Color.lerp(surface, other.surface, t) ?? surface,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t) ?? textPrimary,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t) ?? textSecondary,
      textMuted: Color.lerp(textMuted, other.textMuted, t) ?? textMuted,
      border: Color.lerp(border, other.border, t) ?? border,
      surfaceInfo: Color.lerp(surfaceInfo, other.surfaceInfo, t) ?? surfaceInfo,
      surfaceSecondary: Color.lerp(surfaceSecondary, other.surfaceSecondary, t) ?? surfaceSecondary,
      surfaceAccent: Color.lerp(surfaceAccent, other.surfaceAccent, t) ?? surfaceAccent,
      appStatus: appStatus.lerp(other.appStatus, t),
    );
  }
}
