import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// ---------------------------------------------------------------------
/// Nocturne Voyage design tokens
///
/// Ported from the "Nocturne Voyage" design system: editorial-minimal
/// travel UI built on Midnight Indigo, Aerosphere Blue and Sunset Amber,
/// with Noto Serif display type over Manrope body/label type.
/// ---------------------------------------------------------------------

/// Semantic brand palette (light).
class AppColors {
  AppColors._();

  // Brand accents — see "Palette Roles & Distribution" in the design spec.
  static const Color primary = Color(0xFF1E1B4B); // Midnight Indigo
  static const Color primaryDark = Color(0xFF14123A);
  static const Color secondary = Color(0xFF3B82F6); // Aerosphere Blue
  static const Color tertiary = Color(0xFFF59E0B); // Sunset Amber
  static const Color success = Color(0xFF10B981); // Highland Emerald
  static const Color warning = Color(0xFFF59E0B);
  static const Color error = Color(0xFFBA1A1A);
  static const Color info = Color(0xFF3B82F6);

  // Kept for any screens still referencing a brand gradient, but the
  // Nocturne Voyage system favors flat, solid accents over gradients —
  // prefer `primary` / `secondary` directly for new components.
  static const Color gradientStart = Color(0xFF1E1B4B);
  static const Color gradientMid = Color(0xFF3B5BDB);
  static const Color gradientEnd = Color(0xFF3B82F6);

  static const Color gradientStrongStart = Color(0xFF1E1B4B);
  static const Color gradientStrongEnd = Color(0xFF3B82F6);

  // Neutral canvas — "Crisp Porcelain & Pure White".
  static const Color background = Color(0xFFF8FAFC);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color textPrimary = Color(0xFF191C1E); // on-surface
  static const Color textSecondary = Color(0xFF47464F); // on-surface-variant
  static const Color textMuted = Color(0xFF64748B); // muted slate icons
  static const Color border = Color(0xFFE2E8F0);
  static const Color borderStrong = Color(0xFFCBD5E1);
  static const Color overlay = Color(0x66000000);

  // Light surface tints for info/feature cards.
  static const Color surfaceInfo = Color(0xFFEFF6FF);
  static const Color surfaceSecondary = Color(0xFFF1F5F9);
  static const Color surfaceAccent = Color(0xFFFFF7ED);

  static const LinearGradient brandGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [gradientStart, gradientMid, gradientEnd],
  );

  static const LinearGradient brandStrongGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [gradientStrongStart, gradientStrongEnd],
  );
}

/// Semantic palette used in dark theme. The spec itself is light-first
/// ("porcelain" canvas), so the dark variant inverts the surface
/// stratification while keeping the same brand accents, lifted in
/// value so they stay AA-legible on a near-black indigo canvas.
class AppColorsDark {
  AppColorsDark._();

  static const Color primary = Color(0xFFC4C1FB); // inverse-primary
  static const Color primaryDark = Color(0xFFE3DFFF);
  static const Color secondary = Color(0xFFADC6FF);
  static const Color tertiary = Color(0xFFFFB95F);
  static const Color success = Color(0xFF4ADE80);
  static const Color warning = Color(0xFFFFB95F);
  static const Color error = Color(0xFFFFB4AB);
  static const Color info = Color(0xFFADC6FF);

  static const Color background = Color(0xFF121218);
  static const Color surface = Color(0xFF1B1B23);
  static const Color surfaceElevated = Color(0xFF23232E);
  static const Color textPrimary = Color(0xFFEFF1F3); // inverse-on-surface
  static const Color textSecondary = Color(0xFFC8C5D0); // outline-variant
  static const Color textMuted = Color(0xFF9490A0);
  static const Color border = Color(0xFF3A3944);
  static const Color borderStrong = Color(0xFF4C4B57);
  static const Color overlay = Color(0x99000000);

  static const Color surfaceInfo = Color(0xFF1B2A4D);
  static const Color surfaceSecondary = Color(0xFF232338);
  static const Color surfaceAccent = Color(0xFF332616);

  static const Color gradientStart = Color(0xFF1E1B4B);
  static const Color gradientMid = Color(0xFF444173);
  static const Color gradientEnd = Color(0xFFADC6FF);
  static const Color gradientStrongStart = Color(0xFF444173);
  static const Color gradientStrongEnd = Color(0xFFC4C1FB);

  static const LinearGradient brandGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [gradientStart, gradientMid, gradientEnd],
  );

  static const LinearGradient brandStrongGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [gradientStrongStart, gradientStrongEnd],
  );
}

/// Shape & spacing tokens straight from the Nocturne Voyage grid
/// (8pt base rhythm, 4pt half-step for dense metadata groupings).
class AppRadius {
  AppRadius._();

  static const double sm = 4; // 0.25rem
  static const double base = 8; // 0.5rem — inputs, buttons, chips
  static const double md = 12; // 0.75rem
  static const double lg = 16; // 1rem — standard cards
  static const double xl = 24; // 1.5rem — hero containers, sheets
  static const double full = 9999; // avatars, progress pills
}

class AppSpacing {
  AppSpacing._();

  static const double xs2 = 4; // space-2xs
  static const double xs = 8; // space-xs
  static const double sm = 12; // space-sm
  static const double md = 16; // space-md
  static const double lg = 24; // space-lg
  static const double xl = 32; // space-xl
  static const double xl2 = 48; // space-2xl
  static const double xl3 = 64; // space-3xl
}

/// Elevation shadows matching the spec's crisp, low-theatrics layering
/// (hairline borders + soft ambient shadow rather than heavy Material
/// elevation). Apply via `BoxDecoration(boxShadow: ...)` on custom
/// containers; ThemeData elevation values remain 0 throughout.
class AppElevation {
  AppElevation._();

  static const List<BoxShadow> level1 = [
    BoxShadow(color: Color(0x0A1E1B4B), blurRadius: 3, offset: Offset(0, 1)),
    BoxShadow(color: Color(0x051E1B4B), blurRadius: 2, offset: Offset(0, 1)),
  ];

  static const List<BoxShadow> level2 = [
    BoxShadow(color: Color(0x0F1E1B4B), blurRadius: 15, offset: Offset(0, 10), spreadRadius: -3),
    BoxShadow(color: Color(0x081E1B4B), blurRadius: 6, offset: Offset(0, 4), spreadRadius: -4),
  ];

  static const List<BoxShadow> level3 = [
    BoxShadow(color: Color(0x141E1B4B), blurRadius: 25, offset: Offset(0, 20), spreadRadius: -5),
    BoxShadow(color: Color(0x081E1B4B), blurRadius: 10, offset: Offset(0, 8), spreadRadius: -6),
  ];
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
      surfaceContainerLowest: const Color(0xFFFFFFFF),
      surfaceContainerLow: const Color(0xFFF2F4F6),
      surfaceContainer: const Color(0xFFECEEF0),
      surfaceContainerHigh: const Color(0xFFE6E8EA),
      surfaceContainerHighest: const Color(0xFFE0E3E5),
      outline: const Color(0xFF787680),
      outlineVariant: const Color(0xFFC8C5D0),
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
      surfaceContainerHighest: const Color(0xFF2D3133),
      outline: const Color(0xFF938F99),
      outlineVariant: const Color(0xFF49454F),
    );

    return _base(scheme, TriporaColors.dark);
  }

  static ThemeData _base(ColorScheme scheme, TriporaColors bg) {
    // Nocturne Voyage type scale: Noto Serif on display/headline roles,
    // Manrope on body/label roles. Pulled live via google_fonts (no
    // bundled .ttf assets needed — see pubspec.yaml: add
    // `google_fonts: ^6.0.0` under dependencies). Sizes, weights,
    // line-heights and tracking still follow the original spec; only the
    // family is layered on top of the existing TextStyle definitions via
    // GoogleFonts.<family>(textStyle: ...).
    final baseTextTheme = TextTheme(
      displayLarge: TextStyle(
        fontSize: 40,
        fontWeight: FontWeight.w600,
        height: 48 / 40,
        letterSpacing: -0.02 * 40,
        color: bg.textPrimary,
      ),
      headlineLarge: TextStyle(
        fontSize: 28,
        fontWeight: FontWeight.w600,
        height: 36 / 28,
        letterSpacing: -0.015 * 28,
        color: bg.textPrimary,
      ),
      headlineMedium: TextStyle(
        fontSize: 22,
        fontWeight: FontWeight.w500,
        height: 30 / 22,
        letterSpacing: -0.01 * 22,
        color: bg.textPrimary,
      ),
      headlineSmall: TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w600,
        height: 26 / 18,
        color: bg.textPrimary,
      ),
      bodyLarge: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w400,
        height: 24 / 16,
        letterSpacing: -0.005 * 16,
        color: bg.textPrimary,
      ),
      bodyMedium: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w400,
        height: 20 / 14,
        color: bg.textSecondary,
      ),
      bodySmall: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w400,
        height: 16 / 12,
        letterSpacing: 0.01 * 12,
        color: bg.textMuted,
      ),
      labelLarge: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        height: 18 / 14,
        letterSpacing: 0.01 * 14,
        color: bg.textPrimary,
      ),
      labelMedium: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        height: 16 / 12,
        letterSpacing: 0.02 * 12,
        color: bg.textPrimary,
      ),
      labelSmall: TextStyle(
        fontSize: 10,
        fontWeight: FontWeight.w700,
        height: 14 / 10,
        letterSpacing: 0.05 * 10,
        color: bg.textMuted,
      ),
    );

    // Layer Noto Serif onto display/headline roles...
    final textTheme = baseTextTheme.copyWith(
      displayLarge: GoogleFonts.notoSerif(
        textStyle: baseTextTheme.displayLarge,
      ),
      headlineLarge: GoogleFonts.notoSerif(
        textStyle: baseTextTheme.headlineLarge,
      ),
      headlineMedium: GoogleFonts.notoSerif(
        textStyle: baseTextTheme.headlineMedium,
      ),
      headlineSmall: GoogleFonts.notoSerif(
        textStyle: baseTextTheme.headlineSmall,
      ),
      // ...and Manrope onto body/label roles.
      bodyLarge: GoogleFonts.manrope(
        textStyle: baseTextTheme.bodyLarge,
      ),
      bodyMedium: GoogleFonts.manrope(
        textStyle: baseTextTheme.bodyMedium,
      ),
      bodySmall: GoogleFonts.manrope(
        textStyle: baseTextTheme.bodySmall,
      ),
      labelLarge: GoogleFonts.manrope(
        textStyle: baseTextTheme.labelLarge,
      ),
      labelMedium: GoogleFonts.manrope(
        textStyle: baseTextTheme.labelMedium,
      ),
      labelSmall: GoogleFonts.manrope(
        textStyle: baseTextTheme.labelSmall,
      ),
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      brightness: scheme.brightness,
      scaffoldBackgroundColor: bg.backgroundColor,
      canvasColor: bg.backgroundColor,
      textTheme: textTheme,
      appBarTheme: AppBarTheme(
        elevation: 0,
        centerTitle: false,
        backgroundColor: bg.backgroundColor,
        foregroundColor: bg.textPrimary,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: textTheme.headlineSmall,
      ),
      cardTheme: CardThemeData(
        color: bg.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shadowColor: const Color(0x0A1E1B4B),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          side: BorderSide(color: bg.border),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: scheme.primary,
          foregroundColor: scheme.onPrimary,
          disabledBackgroundColor: bg.border,
          elevation: 0,
          minimumSize: const Size.fromHeight(48),
          padding: const EdgeInsets.symmetric(horizontal: 24),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.base),
          ),
          textStyle: textTheme.labelLarge,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: scheme.primary,
          foregroundColor: scheme.onPrimary,
          minimumSize: const Size.fromHeight(48),
          padding: const EdgeInsets.symmetric(horizontal: 24),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.base),
          ),
          textStyle: textTheme.labelLarge,
        ),
      ),
      // "Secondary / AI Variant" from the spec — used for AI prompt
      // triggers and dynamic flight/route highlights. Wired to
      // TextButtonTheme's tonal cousin isn't ideal, so expose it as a
      // FilledButton.tonal override via a dedicated ButtonStyle below
      // if you add an explicit AI-action button widget.
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: scheme.primary,
          side: BorderSide(color: bg.borderStrong, width: 1),
          minimumSize: const Size.fromHeight(48),
          padding: const EdgeInsets.symmetric(horizontal: 22),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.base),
          ),
          textStyle: textTheme.labelLarge,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: scheme.primary,
          textStyle: textTheme.labelLarge,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: bg.surface,
        constraints: const BoxConstraints(minHeight: 52),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        hintStyle: textTheme.bodyLarge?.copyWith(color: bg.textMuted),
        labelStyle: textTheme.bodyMedium,
        prefixIconColor: bg.textMuted,
        suffixIconColor: bg.textMuted,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.base),
          borderSide: BorderSide(color: bg.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.base),
          borderSide: BorderSide(color: bg.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.base),
          borderSide: BorderSide(color: scheme.primary, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.base),
          borderSide: BorderSide(color: scheme.error),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: bg.surfaceSecondary,
        selectedColor: scheme.primary,
        disabledColor: bg.border,
        side: BorderSide.none,
        shape: const StadiumBorder(),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        labelStyle: textTheme.labelMedium,
        secondaryLabelStyle: textTheme.labelMedium?.copyWith(color: scheme.onPrimary),
      ),
      checkboxTheme: CheckboxThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
        side: BorderSide(color: bg.borderStrong, width: 1.5),
        fillColor: WidgetStateProperty.resolveWith(
              (states) => states.contains(WidgetState.selected) ? scheme.primary : Colors.transparent,
        ),
      ),
      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith(
              (states) => states.contains(WidgetState.selected) ? scheme.primary : bg.borderStrong,
        ),
      ),
      dividerTheme: DividerThemeData(
        color: bg.border,
        thickness: 1,
        space: 1,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: bg.isDarkBg ? AppColorsDark.surfaceElevated : const Color(0xFF1F2937),
        contentTextStyle: textTheme.bodyMedium?.copyWith(color: Colors.white),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
      ),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: scheme.primary,
        selectionColor: scheme.primary.withValues(alpha: 0.2),
        selectionHandleColor: scheme.primary,
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
    required this.borderStrong,
    required this.surfaceInfo,
    required this.surfaceSecondary,
    required this.surfaceAccent,
    required this.appStatus,
    required this.isDarkBg,
  });

  static const TriporaColors light = TriporaColors(
    backgroundColor: AppColors.background,
    surface: AppColors.surface,
    textPrimary: AppColors.textPrimary,
    textSecondary: AppColors.textSecondary,
    textMuted: AppColors.textMuted,
    border: AppColors.border,
    borderStrong: AppColors.borderStrong,
    surfaceInfo: AppColors.surfaceInfo,
    surfaceSecondary: AppColors.surfaceSecondary,
    surfaceAccent: AppColors.surfaceAccent,
    appStatus: AppStatusColors.light,
    isDarkBg: false,
  );

  static const TriporaColors dark = TriporaColors(
    backgroundColor: AppColorsDark.background,
    surface: AppColorsDark.surface,
    textPrimary: AppColorsDark.textPrimary,
    textSecondary: AppColorsDark.textSecondary,
    textMuted: AppColorsDark.textMuted,
    border: AppColorsDark.border,
    borderStrong: AppColorsDark.borderStrong,
    surfaceInfo: AppColorsDark.surfaceInfo,
    surfaceSecondary: AppColorsDark.surfaceSecondary,
    surfaceAccent: AppColorsDark.surfaceAccent,
    appStatus: AppStatusColors.dark,
    isDarkBg: true,
  );

  final Color backgroundColor;
  final Color surface;
  final Color textPrimary;
  final Color textSecondary;
  final Color textMuted;
  final Color border;
  final Color borderStrong;
  final Color surfaceInfo;
  final Color surfaceSecondary;
  final Color surfaceAccent;
  final AppStatusColors appStatus;
  final bool isDarkBg;

  @override
  TriporaColors copyWith({
    Color? backgroundColor,
    Color? surface,
    Color? textPrimary,
    Color? textSecondary,
    Color? textMuted,
    Color? border,
    Color? borderStrong,
    Color? surfaceInfo,
    Color? surfaceSecondary,
    Color? surfaceAccent,
    AppStatusColors? appStatus,
    bool? isDarkBg,
  }) {
    return TriporaColors(
      backgroundColor: backgroundColor ?? this.backgroundColor,
      surface: surface ?? this.surface,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      textMuted: textMuted ?? this.textMuted,
      border: border ?? this.border,
      borderStrong: borderStrong ?? this.borderStrong,
      surfaceInfo: surfaceInfo ?? this.surfaceInfo,
      surfaceSecondary: surfaceSecondary ?? this.surfaceSecondary,
      surfaceAccent: surfaceAccent ?? this.surfaceAccent,
      appStatus: appStatus ?? this.appStatus,
      isDarkBg: isDarkBg ?? this.isDarkBg,
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
      borderStrong: Color.lerp(borderStrong, other.borderStrong, t) ?? borderStrong,
      surfaceInfo: Color.lerp(surfaceInfo, other.surfaceInfo, t) ?? surfaceInfo,
      surfaceSecondary: Color.lerp(surfaceSecondary, other.surfaceSecondary, t) ?? surfaceSecondary,
      surfaceAccent: Color.lerp(surfaceAccent, other.surfaceAccent, t) ?? surfaceAccent,
      appStatus: appStatus.lerp(other.appStatus, t),
      isDarkBg: t < 0.5 ? isDarkBg : other.isDarkBg,
    );
  }
}