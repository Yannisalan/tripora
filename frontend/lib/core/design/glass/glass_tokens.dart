import 'package:flutter/material.dart';

/// ---------------------------------------------------------------------
/// Liquid Glass design system - tokens
///
/// Self-contained, dependency-free. Values are resolved per brightness
/// through the [GlassTheme] theme extension so light/dark transitions
/// stay smooth and every glass surface reads from one source of truth.
/// ---------------------------------------------------------------------

/// Corner radii for glass surfaces.
class GlassRadius {
  GlassRadius._();

  static const double xs = 10;
  static const double sm = 14;
  static const double md = 20;
  static const double lg = 28;
  static const double xl = 36;
  static const double pill = 999;
}

/// Blur sigmas.
class GlassBlur {
  GlassBlur._();

  static const double thin = 12;
  static const double regular = 20;
  static const double heavy = 34;
}

/// Glass accent colors from the brief, kept separate from the semantic
/// [AppColors] palette so nothing existing is renamed.
class GlassAccents {
  GlassAccents._();

  /// Deep near-black backdrop used by the ambient background.
  static const Color night = Color(0xFF080B11);

  /// Sky accent (new).
  static const Color sky = Color(0xFF38BDF8);

  /// Indigo accent (new).
  static const Color indigo = Color(0xFF818CF8);
}

/// Motion tokens shared by all glass widgets.
class GlassMotion {
  GlassMotion._();

  static const Duration fast = Duration(milliseconds: 160);
  static const Duration base = Duration(milliseconds: 240);
  static const Duration slow = Duration(milliseconds: 420);

  static const Curve standard = Curves.easeOutCubic;
  static const Curve emphasized = Curves.easeOutBack;

  /// Returns [duration] shortened to zero when the platform asks for
  /// reduced motion, so animations collapse instead of looping.
  static Duration resolve(BuildContext context, Duration duration) {
    return MediaQuery.maybeDisableAnimationsOf(context) ?? false
        ? Duration.zero
        : duration;
  }
}

/// ---------------------------------------------------------------------
/// Glass theme values
/// ---------------------------------------------------------------------

@immutable
class GlassTheme extends ThemeExtension<GlassTheme> {
  const GlassTheme({
    required this.tint,
    required this.tintStrong,
    required this.strokeTop,
    required this.strokeBottom,
    required this.highlight,
    required this.shadow,
    required this.blurThin,
    required this.blurRegular,
    required this.blurHeavy,
    required this.isDark,
  });

  /// Translucent fill for cards and chips.
  final Color tint;

  /// More opaque fill for bars and sheets.
  final Color tintStrong;

  /// Outer border gradient - top-left stop.
  final Color strokeTop;

  /// Outer border gradient - bottom-right stop.
  final Color strokeBottom;

  /// Inner top highlight (the "specular" edge).
  final Color highlight;

  /// Drop shadow color.
  final Color shadow;

  final double blurThin;
  final double blurRegular;
  final double blurHeavy;

  final bool isDark;

  // ------------------------------------------------------------
  // Dark
  // ------------------------------------------------------------

  static const GlassTheme dark = GlassTheme(
    tint: Color(0x14FFFFFF),
    tintStrong: Color(0x1FFFFFFF),
    strokeTop: Color(0x40FFFFFF),
    strokeBottom: Color(0x0DFFFFFF),
    highlight: Color(0x2EFFFFFF),
    shadow: Color(0x99000000),
    blurThin: GlassBlur.thin,
    blurRegular: GlassBlur.regular,
    blurHeavy: GlassBlur.heavy,
    isDark: true,
  );

  // ------------------------------------------------------------
  // Light
  // ------------------------------------------------------------

  // Light mode leans on a tinted ambient backdrop (see [GlassBackground])
  // so glass can actually refract colour. Over that backdrop the panel is a
  // translucent cool-white (never a flat opaque card), framed by a bright
  // white specular top edge and a soft cool contact edge, with a deeper
  // shadow so panels lift off the background instead of blending into it.
  static const GlassTheme light = GlassTheme(
    tint: Color(0x42F8FAFF),
    tintStrong: Color(0x7AF8FAFF),
    strokeTop: Color(0xF2FFFFFF),
    strokeBottom: Color(0x38202A3D),
    highlight: Color(0xB8FFFFFF),
    shadow: Color(0x2E1E293B),
    blurThin: 14,
    blurRegular: 22,
    blurHeavy: 34,
    isDark: false,
  );

  // ------------------------------------------------------------
  // Derived gradients
  // ------------------------------------------------------------

  /// Translucent fill gradient, slightly brighter at the top-left.
  LinearGradient fillGradient({required Color base, double boost = 0}) {
    return LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        Color.alphaBlend(tintStrong, base),
        Color.alphaBlend(tint, base),
      ],
    );
  }

  /// Outer border gradient.
  LinearGradient get borderGradient => LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [strokeTop, strokeBottom],
      );

  /// Inner top highlight sweep.
  LinearGradient get highlightGradient => LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [highlight, highlight.withValues(alpha: 0)],
      );

  /// Drop shadow stack tuned for glass elevation.
  List<BoxShadow> shadows({double lift = 1}) {
    return [
      BoxShadow(
        color: shadow,
        blurRadius: 24 * lift,
        offset: Offset(0, 10 * lift),
        spreadRadius: -4,
      ),
      BoxShadow(
        color: shadow.withValues(alpha: shadow.a * 0.5),
        blurRadius: 6 * lift,
        offset: Offset(0, 2 * lift),
      ),
    ];
  }

  @override
  GlassTheme copyWith({
    Color? tint,
    Color? tintStrong,
    Color? strokeTop,
    Color? strokeBottom,
    Color? highlight,
    Color? shadow,
    double? blurThin,
    double? blurRegular,
    double? blurHeavy,
    bool? isDark,
  }) {
    return GlassTheme(
      tint: tint ?? this.tint,
      tintStrong: tintStrong ?? this.tintStrong,
      strokeTop: strokeTop ?? this.strokeTop,
      strokeBottom: strokeBottom ?? this.strokeBottom,
      highlight: highlight ?? this.highlight,
      shadow: shadow ?? this.shadow,
      blurThin: blurThin ?? this.blurThin,
      blurRegular: blurRegular ?? this.blurRegular,
      blurHeavy: blurHeavy ?? this.blurHeavy,
      isDark: isDark ?? this.isDark,
    );
  }

  @override
  GlassTheme lerp(
    ThemeExtension<GlassTheme>? other,
    double t,
  ) {
    if (other is! GlassTheme) {
      return this;
    }

    return GlassTheme(
      tint: Color.lerp(tint, other.tint, t) ?? tint,
      tintStrong:
          Color.lerp(tintStrong, other.tintStrong, t) ?? tintStrong,
      strokeTop: Color.lerp(strokeTop, other.strokeTop, t) ?? strokeTop,
      strokeBottom: Color.lerp(strokeBottom, other.strokeBottom, t) ??
          strokeBottom,
      highlight: Color.lerp(highlight, other.highlight, t) ?? highlight,
      shadow: Color.lerp(shadow, other.shadow, t) ?? shadow,
      blurThin: lerpDouble(blurThin, other.blurThin, t),
      blurRegular: lerpDouble(blurRegular, other.blurRegular, t),
      blurHeavy: lerpDouble(blurHeavy, other.blurHeavy, t),
      isDark: t < 0.5 ? isDark : other.isDark,
    );
  }
}

double lerpDouble(double a, double b, double t) => a + (b - a) * t;

/// ---------------------------------------------------------------------
/// BuildContext access
/// ---------------------------------------------------------------------

extension GlassContextX on BuildContext {
  /// Glass tokens for the current brightness.
  ///
  /// Falls back to the palette matching the current brightness when the
  /// extension is not registered (e.g. a bare `Theme` in a test).
  GlassTheme get glass =>
      Theme.of(this).extension<GlassTheme>() ??
      (Theme.of(this).brightness == Brightness.dark
          ? GlassTheme.dark
          : GlassTheme.light);
}
