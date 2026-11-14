import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../design/glass/glass_tokens.dart';

/// ---------------------------------------------------------------------
/// Tripora 2.0 design system
///
/// Light + dark semantic theme. Dark mode uses the Tripora 2.0 deep navy
/// surfaces; both modes use the crimson brand accent ([TriporaBrand]).
/// ---------------------------------------------------------------------

/// Tripora 2.0 brand palette (Phase 4 brief), the single source for the
/// crimson accent and the navy surfaces.
///
/// [crimson] is the exact brand colour. It is used where WCAG asks for 3:1
/// (icons, indicators, dots, active borders, the brand mark, large text).
/// Normal-size TEXT needs 4.5:1, which #F01D54 does not reach on white
/// (4.19:1), under white text (4.19:1) or on the navy cards (#111729,
/// 4.25:1). Two same-hue variants (HSL lightness changed only) cover that:
///
/// - [crimsonDeep]  #D20E41 (L 0.527 -> 0.439): white text on it 5.41:1,
///   on white / the light page gradient 5.41 / 4.63:1. Filled-button
///   background in both modes and the light-mode accent text colour.
/// - [crimsonBright] #F56A8E (L 0.527 -> 0.689): 5.22:1 on #22263A,
///   6.22:1 on #111729, 6.77:1 on #080D1B. Dark-mode accent text colour.
class TriporaBrand {
  TriporaBrand._();

  static const Color crimson = Color(0xFFF01D54);
  static const Color crimsonDeep = Color(0xFFD20E41);
  static const Color crimsonBright = Color(0xFFF56A8E);

  static const Color navy = Color(0xFF080D1B);
  static const Color midnight = Color(0xFF111729);
  static const Color slate = Color(0xFF22263A);
  static const Color softWhite = Color(0xFFE8E9F0);
  static const Color mutedGrey = Color(0xFF9296A8);

  /// Accent for TEXT in the current mode (4.5:1 on that mode's surfaces).
  static Color accentText(bool isDark) => isDark ? crimsonBright : crimsonDeep;
}

class AppColors {
  AppColors._();

  // ------------------------------------------------------------
  // Brand
  // ------------------------------------------------------------

  // Tripora 2.0: the light-mode accent is the AA crimson variant (white
  // text on it 5.41:1; it on white 5.41:1). Was indigo #1E1B4B.
  static const Color primary = TriporaBrand.crimsonDeep;
  static const Color primaryDark = Color(0xFFA80B34);

  static const Color secondary = Color(0xFF3B82F6);
  static const Color tertiary = Color(0xFFF59E0B);

  static const Color success = Color(0xFF10B981);
  static const Color warning = Color(0xFFF59E0B);
  static const Color error = Color(0xFFBA1A1A);
  static const Color info = Color(0xFF3B82F6);

  // ------------------------------------------------------------
  // Liquid Glass accents (from the redesign brief). Additive only -
  // no existing token is renamed.
  // ------------------------------------------------------------

  static const Color glassSky = GlassAccents.sky;
  static const Color glassIndigo = GlassAccents.indigo;
  static const Color glassNight = GlassAccents.night;

  // ------------------------------------------------------------
  // Light surfaces
  // ------------------------------------------------------------

  static const Color background = Color(0xFFF8FAFC);
  static const Color surface = Color(0xFFFFFFFF);

  static const Color textPrimary = Color(0xFF191C1E);
  static const Color textSecondary = Color(0xFF47464F);
  // Same slate hue as the original #64748B with HSL lightness 0.469 ->
  // 0.439, so muted text reaches WCAG AA 4.5:1 on the ambient page
  // gradient (#E7EDFF) and light glass, not only on white.
  static const Color textMuted = Color(0xFF5E6D82);

  static const Color border = Color(0xFFE2E8F0);
  static const Color borderStrong = Color(0xFFCBD5E1);

  // Text-field outline. The field fill (white) is indistinguishable from
  // the white/near-white surfaces it sits on, so the outline is the only
  // visible boundary and must reach 3:1 (WCAG 2.2 SC 1.4.11). This is the
  // theme's existing ColorScheme.outline value: 3.7-4.5:1 on #FFFFFF,
  // #F8FAFC, #F1F5F9 and the page gradient top #E7EDFF. Decorative
  // dividers keep [border].
  static const Color inputBorder = Color(0xFF787680);

  static const Color surfaceInfo = Color(0xFFEFF6FF);
  static const Color surfaceSecondary = Color(0xFFF1F5F9);
  static const Color surfaceAccent = Color(0xFFFFF7ED);

  static const Color overlay = Color(0x66000000);

  // ------------------------------------------------------------
  // Legacy gradients
  // ------------------------------------------------------------

  // Tripora 2.0 crimson brand gradient (was indigo -> blue). Every stop
  // is at or darker than crimsonDeep, so white text on any point of it is
  // >= 5.4:1.
  static const Color gradientStart = Color(0xFF7A0A28);
  static const Color gradientMid = Color(0xFFA80B34);
  static const Color gradientEnd = TriporaBrand.crimsonDeep;

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
      gradientMid,
      primary,
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

  // Tripora 2.0: the dark-mode accent is the AA crimson variant that
  // reads as text on every navy surface (>= 5.2:1). Was lavender #C4C1FB.
  static const Color primary = TriporaBrand.crimsonBright;
  static const Color primaryDark = Color(0xFFFFB3C6);

  static const Color secondary = Color(0xFF8DB4FF);
  static const Color tertiary = Color(0xFFFFB95F);

  static const Color success = Color(0xFF4ADE80);
  static const Color warning = Color(0xFFFFB95F);
  static const Color error = Color(0xFFFFB4AB);
  static const Color info = Color(0xFF8DB4FF);

  // ------------------------------------------------------------
  // Dark surface hierarchy
  // ------------------------------------------------------------

  // Tripora 2.0 navy hierarchy (brief: #080D1B / #111729 / #22263A).
  // Main application background.
  static const Color background = TriporaBrand.navy;

  // Cards / primary surfaces.
  static const Color surface = TriporaBrand.midnight;

  // Slightly elevated cards: midpoint of midnight and slate.
  static const Color surfaceElevated = Color(0xFF1A1F32);

  // Highest elevation surfaces.
  static const Color surfaceHighest = TriporaBrand.slate;

  // ------------------------------------------------------------
  // Dark typography
  // ------------------------------------------------------------

  // Brief soft white #E8E9F0 (16.0:1 on navy).
  static const Color textPrimary = TriporaBrand.softWhite;
  // Between soft white and muted grey, same cool hue: 8.8:1 on #22263A.
  static const Color textSecondary = Color(0xFFC3C6D4);
  // Brief muted grey #9296A8, unchanged: 5.08:1 on slate #22263A (the
  // lightest navy surface) and >= 4.92:1 directly under the navy glass top
  // highlight (GlassTheme.dark.highlight is kept at 5% white for this).
  static const Color textMuted = TriporaBrand.mutedGrey;

  // ------------------------------------------------------------
  // Dark borders
  // ------------------------------------------------------------

  static const Color border = Color(0xFF242A3F);
  static const Color borderStrong = Color(0xFF363D57);

  // Text-field outline (see AppColors.inputBorder). borderStrong's hue
  // with HSL lightness 0.286 -> 0.526: >= 3:1 on every dark surface and
  // glass body an input sits on (#0D0D14 4.7:1 ... #333339 3.0:1).
  static const Color inputBorder = Color(0xFF7B7B92);

  // ------------------------------------------------------------
  // Dark tinted surfaces
  // ------------------------------------------------------------

  static const Color surfaceInfo = Color(0xFF17243B);
  static const Color surfaceSecondary = Color(0xFF161C2F);
  static const Color surfaceAccent = Color(0xFF302516);

  static const Color overlay = Color(0xB3000000);

  // ------------------------------------------------------------
  // Dark gradients
  // ------------------------------------------------------------

  // Tripora 2.0: navy -> deep crimson (was indigo -> blue / lavender).
  static const Color gradientStart = TriporaBrand.midnight;
  static const Color gradientMid = Color(0xFF7A0A28);
  static const Color gradientEnd = TriporaBrand.crimsonDeep;

  static const Color gradientStrongStart = Color(0xFFA80B34);
  static const Color gradientStrongEnd = TriporaBrand.crimsonDeep;

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

  // Light mode: status colors are drawn as text and icons on white/near-
  // white surfaces, where the brand swatches (#10B981, #F59E0B, #3B82F6)
  // only reach 2.5:1 / 2.2:1 / 3.7:1. These are the SAME hue and
  // saturation with HSL lightness lowered just until WCAG AA 4.5:1 on every
  // light surface text sits on: #FFFFFF, the #F8FAFC background and the
  // ambient page gradient's top (#E7EDFF) (enforced by
  // test/theme_contrast_test.dart and test/theme_screens_test.dart).
  // Translucent tints built from them (alpha 0.08-0.16 pills) keep the same
  // hue. Dark mode is unchanged.
  static const AppStatusColors light = AppStatusColors(
    success: Color(0xFF0B7A55), // AppColors.success hue, L 0.394 -> 0.259
    warning: Color(0xFF945F06), // AppColors.warning hue, L 0.502 -> 0.302
    error: AppColors.error, // already 6.5:1
    info: Color(0xFF0B61EE), // AppColors.info hue, L 0.598 -> 0.488
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
  /// Tripora semantic colors for the CURRENT brightness.
  ///
  /// Both ThemeData objects register the extension, so the fallback below
  /// should never be used. If it ever is (e.g. a widget wrapped in a bare
  /// `Theme(data: ThemeData(...))`), it now falls back to the palette that
  /// matches the current brightness instead of always returning light.
  TriporaColors get triporaColors =>
      Theme.of(this).extension<TriporaColors>() ??
      (Theme.of(this).brightness == Brightness.dark
          ? TriporaColors.dark
          : TriporaColors.light);

  AppStatusColors get appStatus =>
      Theme.of(this).extension<AppStatusColors>() ??
      (Theme.of(this).brightness == Brightness.dark
          ? AppStatusColors.dark
          : AppStatusColors.light);

  bool get isDark =>
      Theme.of(this).brightness == Brightness.dark;

  /// Serif heading color.
  ///
  /// Light mode keeps the original deep-indigo heading (0xFF070235) so light
  /// mode looks exactly as before. Dark mode uses the normal primary text
  /// color, because that indigo is nearly invisible on dark surfaces.
  /// Enabled text-field outline (>= 3:1 boundary, WCAG SC 1.4.11).
  Color get inputBorder =>
      isDark ? AppColorsDark.inputBorder : AppColors.inputBorder;

  /// Light mode uses the brand midnight navy (was deep indigo #070235).
  Color get headingColor => isDark
      ? triporaColors.textPrimary
      : TriporaBrand.midnight;

  /// Accent icons on a `colorScheme.primary` panel (trip header, chips).
  ///
  /// With the crimson primary in both modes, the old sky accent (#93C5FD)
  /// is only 3.0:1 on crimson, so both modes use onPrimary.
  Color get onPrimaryAccent => Theme.of(this).colorScheme.onPrimary;

  // ------------------------------------------------------------
  // Tripora 2.0 brand roles (Phase 4 consistency pass). Same in both
  // modes, so a filled primary action or icon tile looks identical in
  // light and dark.
  // ------------------------------------------------------------

  /// Filled primary actions, icon tiles, number badges, selected option
  /// cards: the deep AA crimson.
  Color get brandFill => TriporaBrand.crimsonDeep;

  /// Text/icons on [brandFill]: white, 5.41:1.
  Color get onBrandFill => Colors.white;

  /// Secondary text on [brandFill]: white at 94% (>= 4.8:1).
  Color get onBrandFillSubtle => Colors.white.withValues(alpha: 0.94);

  /// Large dark brand panels (e.g. the itinerary trip header): midnight
  /// navy in both modes, never a crimson slab.
  Color get brandPanel => TriporaBrand.midnight;

  /// Text on [brandPanel]: soft white, 14.7:1.
  Color get onBrandPanel => TriporaBrand.softWhite;

  /// Secondary text on [brandPanel]: 10.5:1.
  Color get onBrandPanelSubtle => AppColorsDark.textSecondary;

  /// Accent icons on [brandPanel]: bright AA crimson, 6.2:1.
  Color get brandPanelAccent => TriporaBrand.crimsonBright;

  /// Secondary text on a `colorScheme.primary` panel. White at 70% is only
  /// 3.0:1 on the light crimson, so light mode uses 94%; dark mode's navy
  /// onPrimary at 88% stays above 4.5:1 on the bright crimson.
  Color get onPrimarySubtle => Theme.of(this)
      .colorScheme
      .onPrimary
      .withValues(alpha: isDark ? 0.88 : 0.94);
}

/// ---------------------------------------------------------------------
/// App Theme
/// ---------------------------------------------------------------------

class AppTheme {
  AppTheme._();

  static final ThemeData lightTheme = _buildLight();
  static final ThemeData darkTheme = _buildDark();

  // ------------------------------------------------------------
  // System UI (status / navigation bar)
  //
  // The status bar is fully transparent so the app's own header — the
  // light AppBar / glass top bar — shows through instead of Android's
  // opaque default bar (the black gap above the header). Icon brightness
  // is inverted per theme so the clock / battery stay legible:
  //   light background -> dark icons
  //   dark  background -> light icons
  //
  // `statusBarIconBrightness` is read on Android; `statusBarBrightness`
  // is read on iOS (it is the brightness OF the bar background).
  // ------------------------------------------------------------

  static const SystemUiOverlayStyle lightSystemUiOverlayStyle =
      SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.dark,
    statusBarBrightness: Brightness.light,
    systemNavigationBarColor: Colors.transparent,
    systemNavigationBarDividerColor: Colors.transparent,
    systemNavigationBarIconBrightness: Brightness.dark,
  );

  static const SystemUiOverlayStyle darkSystemUiOverlayStyle =
      SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    statusBarBrightness: Brightness.dark,
    systemNavigationBarColor: Colors.transparent,
    systemNavigationBarDividerColor: Colors.transparent,
    systemNavigationBarIconBrightness: Brightness.light,
  );

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
      primaryContainer: Color(0xFFFFD9E0),
      onPrimaryContainer: Color(0xFF3F0012),

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
      // Navy on the bright crimson: 6.77:1.
      onPrimary: TriporaBrand.navy,
      primaryContainer: Color(0xFF4A1226),
      onPrimaryContainer: Color(0xFFFFD9E0),

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

      // Secondary text/icon color on surfaces. Many default Material 3
      // widgets (ListTile icons, dropdowns, default IconButtons, labels)
      // read this. Without it, it silently falls back to onSurface.
      onSurfaceVariant: AppColorsDark.textSecondary,

      surfaceContainerHighest: AppColorsDark.surfaceHighest,
      surfaceContainerHigh: AppColorsDark.surfaceElevated,
      surfaceContainer: AppColorsDark.surface,
      surfaceContainerLow: Color(0xFF0D1222),
      surfaceContainerLowest: AppColorsDark.background,

      // Borders
      outline: AppColorsDark.borderStrong,
      outlineVariant: AppColorsDark.border,

      // Other
      inverseSurface: Color(0xFFE8E9F0),
      onInverseSurface: Color(0xFF22263A),
      inversePrimary: AppColors.primary,
      shadow: Colors.black,
      scrim: Colors.black,
    );

    final base = _base(
      scheme,
      TriporaColors.dark,
    );

    return _applyDarkOverrides(
      base,
      scheme,
      TriporaColors.dark,
    );
  }

  // ------------------------------------------------------------
  // Dark-only global fixes
  //
  // These themes are ONLY applied in dark mode, so light mode keeps
  // exactly the appearance it had before.
  // ------------------------------------------------------------

  static ThemeData _applyDarkOverrides(
    ThemeData base,
    ColorScheme scheme,
    TriporaColors bg,
  ) {
    final textTheme = base.textTheme;

    return base.copyWith(
      // Default icon color for any bare Icon(...) that has no explicit
      // color. Flutter's default is pure white in dark mode.
      iconTheme: IconThemeData(
        color: bg.textPrimary,
      ),

      // ListTile leading/trailing icons and title text.
      listTileTheme: ListTileThemeData(
        iconColor: bg.textSecondary,
        textColor: bg.textPrimary,
      ),

      // Drawer.
      drawerTheme: DrawerThemeData(
        backgroundColor: bg.surface,
        surfaceTintColor: Colors.transparent,
        scrimColor: AppColorsDark.overlay,
      ),

      // Overflow ("...") menus, e.g. the trip card menu.
      popupMenuTheme: PopupMenuThemeData(
        color: bg.surfaceElevated,
        surfaceTintColor: Colors.transparent,
        textStyle: textTheme.bodyMedium?.copyWith(
          color: bg.textPrimary,
        ),
      ),

      // Classic BottomNavigationBar (NavigationBar is themed in _base).
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: bg.surface,
        selectedItemColor: scheme.primary,
        unselectedItemColor: bg.textMuted,
      ),

      // DropdownMenu (not DropdownButtonFormField).
      dropdownMenuTheme: DropdownMenuThemeData(
        textStyle: textTheme.bodyLarge?.copyWith(
          color: bg.textPrimary,
        ),
        menuStyle: MenuStyle(
          backgroundColor: WidgetStatePropertyAll(
            bg.surfaceElevated,
          ),
          surfaceTintColor: const WidgetStatePropertyAll(
            Colors.transparent,
          ),
        ),
      ),
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
      //
      // iconTheme / actionsIconTheme are now explicit so the automatic
      // back arrow, drawer icon and action icons always use the
      // theme's text color (never a default or hardcoded color).
      // ----------------------------------------------------------

      appBarTheme: AppBarTheme(
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        backgroundColor: bg.backgroundColor,
        foregroundColor: bg.textPrimary,
        surfaceTintColor: Colors.transparent,
        iconTheme: IconThemeData(
          color: bg.textPrimary,
        ),
        actionsIconTheme: IconThemeData(
          color: bg.textPrimary,
        ),
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

      // Filled buttons use the deep AA crimson with white text in BOTH
      // modes (5.41:1), matching the brand fill.
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: TriporaBrand.crimsonDeep,
          foregroundColor: Colors.white,
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
          backgroundColor: TriporaBrand.crimsonDeep,
          foregroundColor: Colors.white,
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

        // Enabled outline: the field's only visible boundary, so it uses
        // the 3:1 input outline token (WCAG SC 1.4.11), not the
        // decorative divider colour.
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(
            AppRadius.base,
          ),
          borderSide: BorderSide(
            color: bg.isDarkBg
                ? AppColorsDark.inputBorder
                : AppColors.inputBorder,
          ),
        ),

        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(
            AppRadius.base,
          ),
          borderSide: BorderSide(
            color: bg.isDarkBg
                ? AppColorsDark.inputBorder
                : AppColors.inputBorder,
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
      //
      // The label color now depends on the selected state. Previously a
      // selected chip (primary background) always used the normal text
      // color, which is dark-on-dark in light mode and light-on-light in
      // dark mode whenever a screen did not override the label style.
      // ----------------------------------------------------------

      chipTheme: ChipThemeData(
        backgroundColor: bg.surfaceSecondary,
        selectedColor: scheme.primary,
        disabledColor: bg.border,
        checkmarkColor: scheme.onPrimary,
        side: BorderSide(
          color: bg.border,
        ),
        shape: const StadiumBorder(),
        padding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 6,
        ),
        labelStyle: WidgetStateTextStyle.resolveWith(
          (states) {
            final style =
                textTheme.labelMedium ?? const TextStyle();

            return style.copyWith(
              color: states.contains(WidgetState.selected)
                  ? scheme.onPrimary
                  : bg.textPrimary,
            );
          },
        ),
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

      // ----------------------------------------------------------
      // Page transitions (Phase 2, F5)
      //
      // One restrained style instead of the per-platform defaults: a short
      // fade-forward on Android, web, Windows and Linux, over the theme's
      // own background (navy in dark mode, so no black flash between
      // pages). iOS and macOS keep the native Cupertino slide because it
      // carries the edge swipe-back gesture.
      // ----------------------------------------------------------

      pageTransitionsTheme: PageTransitionsTheme(
        builders: {
          for (final platform in const [
            TargetPlatform.android,
            TargetPlatform.fuchsia,
            TargetPlatform.linux,
            TargetPlatform.windows,
          ])
            platform: FadeForwardsPageTransitionsBuilder(
              backgroundColor: bg.backgroundColor,
            ),
          TargetPlatform.iOS: const CupertinoPageTransitionsBuilder(),
          TargetPlatform.macOS: const CupertinoPageTransitionsBuilder(),
        },
      ),

      // Date picker: the month/year header defaults to 60% onSurface,
      // which is 4.2:1 on the light dialog surface (below WCAG AA). Use the
      // secondary text token instead; everything else stays Material's
      // scheme-derived default.
      datePickerTheme: DatePickerThemeData(
        subHeaderForegroundColor: bg.textSecondary,
      ),

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
      //
      // Dark mode: the background is a dark surface, so the message text
      // uses the theme text color and the action button uses the dark
      // primary. Previously the action defaulted to inversePrimary (dark
      // indigo), which is invisible on a dark snackbar.
      // Light mode is unchanged.
      // ----------------------------------------------------------

      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: bg.isDarkBg
            ? bg.surfaceHighest
            : const Color(0xFF1F2937),
        contentTextStyle: textTheme.bodyMedium?.copyWith(
          color: bg.isDarkBg ? bg.textPrimary : Colors.white,
        ),
        actionTextColor: bg.isDarkBg ? scheme.primary : null,
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
      //
      // _base() is used for BOTH light and dark, so TriporaColors and
      // AppStatusColors are registered in both ThemeData objects.
      // ----------------------------------------------------------

      extensions: <ThemeExtension<dynamic>>[
        bg,
        bg.appStatus,
        bg.isDarkBg ? GlassTheme.dark : GlassTheme.light,
      ],
    );
  }
}