import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// ---------------------------------------------------------------------
/// Tripora / Nocturne Voyage Design System
///
/// Light + dark semantic theme.
/// Dark mode uses deep indigo surfaces rather than pure black.
/// ---------------------------------------------------------------------

class AppColors {
  AppColors._();

  // ------------------------------------------------------------
  // Brand
  // ------------------------------------------------------------

  static const Color primary = Color(0xFF1E1B4B);
  static const Color primaryDark = Color(0xFF14123A);

  static const Color secondary = Color(0xFF3B82F6);
  static const Color tertiary = Color(0xFFF59E0B);

  static const Color success = Color(0xFF10B981);
  static const Color warning = Color(0xFFF59E0B);
  static const Color error = Color(0xFFBA1A1A);
  static const Color info = Color(0xFF3B82F6);

  // ------------------------------------------------------------
  // Light surfaces
  // ------------------------------------------------------------

  static const Color background = Color(0xFFF8FAFC);
  static const Color surface = Color(0xFFFFFFFF);

  static const Color textPrimary = Color(0xFF191C1E);
  static const Color textSecondary = Color(0xFF47464F);
  static const Color textMuted = Color(0xFF64748B);

  static const Color border = Color(0xFFE2E8F0);
  static const Color borderStrong = Color(0xFFCBD5E1);

  static const Color surfaceInfo = Color(0xFFEFF6FF);
  static const Color surfaceSecondary = Color(0xFFF1F5F9);
  static const Color surfaceAccent = Color(0xFFFFF7ED);

  static const Color overlay = Color(0x66000000);

  // ------------------------------------------------------------
  // Legacy gradients
  // ------------------------------------------------------------

  static const Color gradientStart = Color(0xFF1E1B4B);
  static const Color gradientMid = Color(0xFF3B5BDB);
  static const Color gradientEnd = Color(0xFF3B82F6);

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
      primary,
      secondary,
    ],
  );
}

/// ---------------------------------------------------------------------
/// Dark palette
/// ---------------------------------------------------------------------

class AppColorsDark {
  AppColorsDark._();

  // ------------------------------------------------------------
  // Brand
  // ------------------------------------------------------------

  // Bright enough to work on dark surfaces, but still feels like
  // Tripora's indigo rather than generic purple.
  static const Color primary = Color(0xFFC4C1FB);
  static const Color primaryDark = Color(0xFFE3DFFF);

  static const Color secondary = Color(0xFF8DB4FF);
  static const Color tertiary = Color(0xFFFFB95F);

  static const Color success = Color(0xFF4ADE80);
  static const Color warning = Color(0xFFFFB95F);
  static const Color error = Color(0xFFFFB4AB);
  static const Color info = Color(0xFF8DB4FF);

  // ------------------------------------------------------------
  // Dark surface hierarchy
  // ------------------------------------------------------------

  // Main application background.
  static const Color background = Color(0xFF0D0D14);

  // Cards / primary surfaces.
  static const Color surface = Color(0xFF15151E);

  // Slightly elevated cards.
  static const Color surfaceElevated = Color(0xFF1C1C28);

  // Highest elevation surfaces.
  static const Color surfaceHighest = Color(0xFF252532);

  // ------------------------------------------------------------
  // Dark typography
  // ------------------------------------------------------------

  static const Color textPrimary = Color(0xFFF1F2F4);
  static const Color textSecondary = Color(0xFFC7C5D0);
  static const Color textMuted = Color(0xFF9493A2);

  // ------------------------------------------------------------
  // Dark borders
  // ------------------------------------------------------------

  static const Color border = Color(0xFF2D2D39);
  static const Color borderStrong = Color(0xFF424250);

  // ------------------------------------------------------------
  // Dark tinted surfaces
  // ------------------------------------------------------------

  static const Color surfaceInfo = Color(0xFF17243B);
  static const Color surfaceSecondary = Color(0xFF1B1B25);
  static const Color surfaceAccent = Color(0xFF302516);

  static const Color overlay = Color(0xB3000000);

  // ------------------------------------------------------------
  // Dark gradients
  // ------------------------------------------------------------

  static const Color gradientStart = Color(0xFF1E1B4B);
  static const Color gradientMid = Color(0xFF363264);
  static const Color gradientEnd = Color(0xFF536FAF);

  static const Color gradientStrongStart = Color(0xFF363264);
  static const Color gradientStrongEnd = Color(0xFFC4C1FB);

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

/// ---------------------------------------------------------------------
/// Radius
/// ---------------------------------------------------------------------

class AppRadius {
  AppRadius._();

  static const double sm = 4;
  static const double base = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double full = 9999;
}

/// ---------------------------------------------------------------------
/// Spacing
/// ---------------------------------------------------------------------

class AppSpacing {
  AppSpacing._();

  static const double xs2 = 4;
  static const double xs = 8;
  static const double sm = 12;
  static const double md = 16;
  static const double lg = 24;
  static const double xl = 32;
  static const double xl2 = 48;
  static const double xl3 = 64;
}

/// ---------------------------------------------------------------------
/// Elevation
/// ---------------------------------------------------------------------

class AppElevation {
  AppElevation._();

  static const List<BoxShadow> level1 = [
    BoxShadow(
      color: Color(0x18000000),
      blurRadius: 4,
      offset: Offset(0, 2),
    ),
  ];

  static const List<BoxShadow> level2 = [
    BoxShadow(
      color: Color(0x26000000),
      blurRadius: 16,
      offset: Offset(0, 8),
      spreadRadius: -3,
    ),
  ];

  static const List<BoxShadow> level3 = [
    BoxShadow(
      color: Color(0x33000000),
      blurRadius: 28,
      offset: Offset(0, 18),
      spreadRadius: -5,
    ),
  ];
}

/// ---------------------------------------------------------------------
/// Status colors
/// ---------------------------------------------------------------------

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
  AppStatusColors lerp(
    ThemeExtension<AppStatusColors>? other,
    double t,
  ) {
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

/// ---------------------------------------------------------------------
/// Theme-aware Tripora colors
/// ---------------------------------------------------------------------

class TriporaColors extends ThemeExtension<TriporaColors> {
  const TriporaColors({
    required this.backgroundColor,
    required this.surface,
    required this.surfaceElevated,
    required this.surfaceHighest,
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

  // ------------------------------------------------------------
  // Light
  // ------------------------------------------------------------

  static const TriporaColors light = TriporaColors(
    backgroundColor: AppColors.background,
    surface: AppColors.surface,
    surfaceElevated: AppColors.surface,
    surfaceHighest: AppColors.surface,
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

  // ------------------------------------------------------------
  // Dark
  // ------------------------------------------------------------

  static const TriporaColors dark = TriporaColors(
    backgroundColor: AppColorsDark.background,
    surface: AppColorsDark.surface,
    surfaceElevated: AppColorsDark.surfaceElevated,
    surfaceHighest: AppColorsDark.surfaceHighest,
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
  final Color surfaceElevated;
  final Color surfaceHighest;

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
    Color? surfaceElevated,
    Color? surfaceHighest,
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
      surfaceElevated: surfaceElevated ?? this.surfaceElevated,
      surfaceHighest: surfaceHighest ?? this.surfaceHighest,
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
  TriporaColors lerp(
    ThemeExtension<TriporaColors>? other,
    double t,
  ) {
    if (other is! TriporaColors) {
      return this;
    }

    return TriporaColors(
      backgroundColor:
          Color.lerp(backgroundColor, other.backgroundColor, t) ??
              backgroundColor,
      surface: Color.lerp(surface, other.surface, t) ?? surface,
      surfaceElevated:
          Color.lerp(surfaceElevated, other.surfaceElevated, t) ??
              surfaceElevated,
      surfaceHighest:
          Color.lerp(surfaceHighest, other.surfaceHighest, t) ??
              surfaceHighest,
      textPrimary:
          Color.lerp(textPrimary, other.textPrimary, t) ?? textPrimary,
      textSecondary:
          Color.lerp(textSecondary, other.textSecondary, t) ??
              textSecondary,
      textMuted:
          Color.lerp(textMuted, other.textMuted, t) ?? textMuted,
      border: Color.lerp(border, other.border, t) ?? border,
      borderStrong:
          Color.lerp(borderStrong, other.borderStrong, t) ??
              borderStrong,
      surfaceInfo:
          Color.lerp(surfaceInfo, other.surfaceInfo, t) ??
              surfaceInfo,
      surfaceSecondary:
          Color.lerp(surfaceSecondary, other.surfaceSecondary, t) ??
              surfaceSecondary,
      surfaceAccent:
          Color.lerp(surfaceAccent, other.surfaceAccent, t) ??
              surfaceAccent,
      appStatus: appStatus.lerp(other.appStatus, t),
      isDarkBg: t < 0.5 ? isDarkBg : other.isDarkBg,
    );
  }
}

/// ---------------------------------------------------------------------
/// BuildContext extensions
/// ---------------------------------------------------------------------

extension TriporaColorsX on BuildContext {
  TriporaColors get triporaColors =>
      Theme.of(this).extension<TriporaColors>() ??
      TriporaColors.light;

  AppStatusColors get appStatus =>
      Theme.of(this).extension<AppStatusColors>() ??
      AppStatusColors.light;

  bool get isDark =>
      Theme.of(this).brightness == Brightness.dark;
}

/// ---------------------------------------------------------------------
/// App Theme
/// ---------------------------------------------------------------------

class AppTheme {
  AppTheme._();

  static final ThemeData lightTheme = _buildLight();
  static final ThemeData darkTheme = _buildDark();

  // ------------------------------------------------------------
  // Light
  // ------------------------------------------------------------

  static ThemeData _buildLight() {
    final scheme = ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      brightness: Brightness.light,
    ).copyWith(
      primary: AppColors.primary,
      onPrimary: Colors.white,

      secondary: AppColors.secondary,
      onSecondary: Colors.white,

      tertiary: AppColors.tertiary,
      onTertiary: Colors.white,

      error: AppColors.error,

      surface: AppColors.surface,
      onSurface: AppColors.textPrimary,

      surfaceContainerLowest: Colors.white,
      surfaceContainerLow: Color(0xFFF5F7F9),
      surfaceContainer: Color(0xFFF0F2F4),
      surfaceContainerHigh: Color(0xFFE8EBEE),
      surfaceContainerHighest: Color(0xFFE1E5E8),

      outline: Color(0xFF787680),
      outlineVariant: AppColors.border,
    );

    return _base(
      scheme,
      TriporaColors.light,
    );
  }

  // ------------------------------------------------------------
  // Dark
  // ------------------------------------------------------------

  static ThemeData _buildDark() {
    final scheme = ColorScheme(
      brightness: Brightness.dark,

      // Primary
      primary: AppColorsDark.primary,
      onPrimary: Color(0xFF29264F),
      primaryContainer: Color(0xFF403C70),
      onPrimaryContainer: Color(0xFFE7E3FF),

      // Secondary
      secondary: AppColorsDark.secondary,
      onSecondary: Color(0xFF12264C),
      secondaryContainer: Color(0xFF28487D),
      onSecondaryContainer: Color(0xFFDCE7FF),

      // Tertiary
      tertiary: AppColorsDark.tertiary,
      onTertiary: Color(0xFF3D2600),
      tertiaryContainer: Color(0xFF5C3A00),
      onTertiaryContainer: Color(0xFFFFDDB1),

      // Error
      error: AppColorsDark.error,
      onError: Color(0xFF690005),
      errorContainer: Color(0xFF93000A),
      onErrorContainer: Color(0xFFFFDAD6),

      // Surfaces
      surface: AppColorsDark.surface,
      onSurface: AppColorsDark.textPrimary,

      surfaceContainerHighest: AppColorsDark.surfaceHighest,
      surfaceContainerHigh: AppColorsDark.surfaceElevated,
      surfaceContainer: AppColorsDark.surface,
      surfaceContainerLow: Color(0xFF111119),
      surfaceContainerLowest: AppColorsDark.background,

      // Borders
      outline: AppColorsDark.borderStrong,
      outlineVariant: AppColorsDark.border,

      // Other
      inverseSurface: Color(0xFFE8E8F0),
      onInverseSurface: Color(0xFF292931),
      inversePrimary: AppColors.primary,
      shadow: Colors.black,
      scrim: Colors.black,
    );

    return _base(
      scheme,
      TriporaColors.dark,
    );
  }

  // ------------------------------------------------------------
  // Shared theme
  // ------------------------------------------------------------

  static ThemeData _base(
    ColorScheme scheme,
    TriporaColors bg,
  ) {
    final baseTextTheme = TextTheme(
      displayLarge: TextStyle(
        fontSize: 40,
        fontWeight: FontWeight.w600,
        height: 48 / 40,
        letterSpacing: -0.8,
        color: bg.textPrimary,
      ),
      headlineLarge: TextStyle(
        fontSize: 28,
        fontWeight: FontWeight.w600,
        height: 36 / 28,
        letterSpacing: -0.42,
        color: bg.textPrimary,
      ),
      headlineMedium: TextStyle(
        fontSize: 22,
        fontWeight: FontWeight.w500,
        height: 30 / 22,
        letterSpacing: -0.22,
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
        letterSpacing: -0.08,
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
        letterSpacing: 0.12,
        color: bg.textMuted,
      ),
      labelLarge: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        height: 18 / 14,
        letterSpacing: 0.14,
        color: bg.textPrimary,
      ),
      labelMedium: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        height: 16 / 12,
        letterSpacing: 0.24,
        color: bg.textPrimary,
      ),
      labelSmall: TextStyle(
        fontSize: 10,
        fontWeight: FontWeight.w700,
        height: 14 / 10,
        letterSpacing: 0.5,
        color: bg.textMuted,
      ),
    );

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

      brightness: scheme.brightness,
      colorScheme: scheme,

      scaffoldBackgroundColor: bg.backgroundColor,
      canvasColor: bg.backgroundColor,

      textTheme: textTheme,

      // ----------------------------------------------------------
      // AppBar
      // ----------------------------------------------------------

      appBarTheme: AppBarTheme(
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        backgroundColor: bg.backgroundColor,
        foregroundColor: bg.textPrimary,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: textTheme.headlineSmall,
      ),

      // ----------------------------------------------------------
      // Cards
      // ----------------------------------------------------------

      cardTheme: CardThemeData(
        color: bg.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shadowColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          side: BorderSide(
            color: bg.border,
          ),
        ),
      ),

      // ----------------------------------------------------------
      // Elevated buttons
      // ----------------------------------------------------------

      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: scheme.primary,
          foregroundColor: scheme.onPrimary,
          disabledBackgroundColor: bg.border,
          disabledForegroundColor: bg.textMuted,
          elevation: 0,
          minimumSize: const Size.fromHeight(48),
          padding: const EdgeInsets.symmetric(
            horizontal: 24,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(
              AppRadius.base,
            ),
          ),
          textStyle: textTheme.labelLarge,
        ),
      ),

      // ----------------------------------------------------------
      // Filled buttons
      // ----------------------------------------------------------

      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: scheme.primary,
          foregroundColor: scheme.onPrimary,
          disabledBackgroundColor: bg.border,
          disabledForegroundColor: bg.textMuted,
          minimumSize: const Size.fromHeight(48),
          padding: const EdgeInsets.symmetric(
            horizontal: 24,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(
              AppRadius.base,
            ),
          ),
          textStyle: textTheme.labelLarge,
        ),
      ),

      // ----------------------------------------------------------
      // Outlined buttons
      // ----------------------------------------------------------

      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: scheme.primary,
          side: BorderSide(
            color: bg.borderStrong,
          ),
          minimumSize: const Size.fromHeight(48),
          padding: const EdgeInsets.symmetric(
            horizontal: 22,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(
              AppRadius.base,
            ),
          ),
          textStyle: textTheme.labelLarge,
        ),
      ),

      // ----------------------------------------------------------
      // Text buttons
      // ----------------------------------------------------------

      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: scheme.primary,
          textStyle: textTheme.labelLarge,
        ),
      ),

      // ----------------------------------------------------------
      // Inputs
      // ----------------------------------------------------------

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: bg.surface,

        constraints: const BoxConstraints(
          minHeight: 52,
        ),

        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),

        hintStyle: textTheme.bodyLarge?.copyWith(
          color: bg.textMuted,
        ),

        labelStyle: textTheme.bodyMedium?.copyWith(
          color: bg.textSecondary,
        ),

        prefixIconColor: bg.textMuted,
        suffixIconColor: bg.textMuted,

        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(
            AppRadius.base,
          ),
          borderSide: BorderSide(
            color: bg.border,
          ),
        ),

        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(
            AppRadius.base,
          ),
          borderSide: BorderSide(
            color: bg.border,
          ),
        ),

        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(
            AppRadius.base,
          ),
          borderSide: BorderSide(
            color: scheme.primary,
            width: 2,
          ),
        ),

        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(
            AppRadius.base,
          ),
          borderSide: BorderSide(
            color: scheme.error,
          ),
        ),

        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(
            AppRadius.base,
          ),
          borderSide: BorderSide(
            color: scheme.error,
            width: 2,
          ),
        ),
      ),

      // ----------------------------------------------------------
      // Chips
      // ----------------------------------------------------------

      chipTheme: ChipThemeData(
        backgroundColor: bg.surfaceSecondary,
        selectedColor: scheme.primary,
        disabledColor: bg.border,
        side: BorderSide(
          color: bg.border,
        ),
        shape: const StadiumBorder(),
        padding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 6,
        ),
        labelStyle: textTheme.labelMedium,
        secondaryLabelStyle: textTheme.labelMedium?.copyWith(
          color: scheme.onPrimary,
        ),
      ),

      // ----------------------------------------------------------
      // Checkbox
      // ----------------------------------------------------------

      checkboxTheme: CheckboxThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(
            AppRadius.sm,
          ),
        ),
        side: BorderSide(
          color: bg.borderStrong,
          width: 1.5,
        ),
        fillColor: WidgetStateProperty.resolveWith(
          (states) {
            if (states.contains(WidgetState.selected)) {
              return scheme.primary;
            }

            return Colors.transparent;
          },
        ),
        checkColor: WidgetStatePropertyAll(
          scheme.onPrimary,
        ),
      ),

      // ----------------------------------------------------------
      // Radio
      // ----------------------------------------------------------

      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (states) {
            if (states.contains(WidgetState.selected)) {
              return scheme.primary;
            }

            return bg.borderStrong;
          },
        ),
      ),

      // ----------------------------------------------------------
      // Switch
      // ----------------------------------------------------------

      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) {
            if (states.contains(WidgetState.selected)) {
              return scheme.onPrimary;
            }

            return bg.textMuted;
          },
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) {
            if (states.contains(WidgetState.selected)) {
              return scheme.primary;
            }

            return bg.surfaceHighest;
          },
        ),
        trackOutlineColor: WidgetStatePropertyAll(
          bg.borderStrong,
        ),
      ),

      // ----------------------------------------------------------
      // Divider
      // ----------------------------------------------------------

      dividerTheme: DividerThemeData(
        color: bg.border,
        thickness: 1,
        space: 1,
      ),

      // ----------------------------------------------------------
      // Dialogs
      // ----------------------------------------------------------

      dialogTheme: DialogThemeData(
        backgroundColor: bg.surfaceElevated,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(
            AppRadius.xl,
          ),
          side: BorderSide(
            color: bg.border,
          ),
        ),
        titleTextStyle: textTheme.headlineSmall,
        contentTextStyle: textTheme.bodyMedium,
      ),

      // ----------------------------------------------------------
      // Bottom sheets
      // ----------------------------------------------------------

      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: bg.surface,
        surfaceTintColor: Colors.transparent,
        modalBackgroundColor: bg.surface,
        modalBarrierColor: AppColorsDark.overlay,
        elevation: 0,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(
              AppRadius.xl,
            ),
          ),
        ),
      ),

      // ----------------------------------------------------------
      // Navigation bar
      // ----------------------------------------------------------

      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: bg.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        indicatorColor: scheme.primaryContainer,
        labelTextStyle: WidgetStatePropertyAll(
          textTheme.labelMedium,
        ),
        iconTheme: WidgetStateProperty.resolveWith(
          (states) {
            if (states.contains(WidgetState.selected)) {
              return IconThemeData(
                color: scheme.onPrimaryContainer,
              );
            }

            return IconThemeData(
              color: bg.textMuted,
            );
          },
        ),
      ),

      // ----------------------------------------------------------
      // Snackbars
      // ----------------------------------------------------------

      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: bg.isDarkBg
            ? bg.surfaceHighest
            : const Color(0xFF1F2937),
        contentTextStyle: textTheme.bodyMedium?.copyWith(
          color: Colors.white,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(
            AppRadius.md,
          ),
        ),
      ),

      // ----------------------------------------------------------
      // Selection
      // ----------------------------------------------------------

      textSelectionTheme: TextSelectionThemeData(
        cursorColor: scheme.primary,
        selectionColor: scheme.primary.withValues(
          alpha: 0.25,
        ),
        selectionHandleColor: scheme.primary,
      ),

      // ----------------------------------------------------------
      // Theme extensions
      // ----------------------------------------------------------

      extensions: <ThemeExtension<dynamic>>[
        bg,
        bg.appStatus,
      ],
    );
  }
}
