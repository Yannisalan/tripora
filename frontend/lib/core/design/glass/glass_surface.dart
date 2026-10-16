import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import 'glass_tokens.dart';

/// ---------------------------------------------------------------------
/// Glass surface
///
/// The core building block of the Liquid Glass system: a backdrop-blurred,
/// translucent panel with a gradient hairline border, an inner specular
/// highlight and a soft drop shadow.
///
/// Nothing here mutates state or depends on a package - it is pure Flutter
/// (`BackdropFilter` + gradients), so it behaves the same on every
/// platform and is safe inside widget tests.
/// ---------------------------------------------------------------------

enum GlassVariant {
  /// Floating translucent panel - cards, chips, stat tiles.
  card,

  /// Navigation bars and toolbars (slightly more opaque).
  bar,

  /// Bottom sheets and dialogs (heaviest blur + strongest fill).
  sheet,

  /// Compact pill / chip.
  pill,
}

class GlassSurface extends StatelessWidget {
  const GlassSurface({
    super.key,
    required this.child,
    this.variant = GlassVariant.card,
    this.padding = const EdgeInsets.all(16),
    this.margin,
    this.borderRadius,
    this.blur,
    this.tintStrength = 1,
    this.elevation = 1,
    this.showBorder = true,
    this.showHighlight = true,
    this.onTap,
    this.width,
    this.height,
    this.alignment,
    this.constraints,
  });

  final Widget child;
  final GlassVariant variant;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry? margin;
  final BorderRadius? borderRadius;

  /// Overrides the blur sigma for this surface only.
  final double? blur;

  /// Multiplies the fill opacity (1 = default, 0 = fully transparent).
  final double tintStrength;

  /// Multiplies shadow lift (0 = flat, 1 = default).
  final double elevation;

  final bool showBorder;
  final bool showHighlight;
  final VoidCallback? onTap;

  final double? width;
  final double? height;
  final AlignmentGeometry? alignment;
  final BoxConstraints? constraints;

  double _defaultRadius() {
    switch (variant) {
      case GlassVariant.card:
        return GlassRadius.lg;
      case GlassVariant.bar:
        return GlassRadius.xl;
      case GlassVariant.sheet:
        return GlassRadius.xl;
      case GlassVariant.pill:
        return GlassRadius.pill;
    }
  }

  double _blurSigma(GlassTheme glass) {
    if (blur != null) {
      return blur!;
    }

    switch (variant) {
      case GlassVariant.card:
        return glass.blurRegular;
      case GlassVariant.bar:
        return glass.blurThin;
      case GlassVariant.sheet:
        return glass.blurHeavy;
      case GlassVariant.pill:
        return glass.blurThin;
    }
  }

  double _baseAlpha(GlassTheme glass) {
    switch (variant) {
      case GlassVariant.card:
      case GlassVariant.pill:
        return glass.tint.a;
      case GlassVariant.bar:
      case GlassVariant.sheet:
        return glass.tintStrong.a;
    }
  }

  Widget _maybeBlur({
    required bool enabled,
    required double sigma,
    required Widget child,
  }) {
    if (!enabled) {
      return child;
    }

    return BackdropFilter(
      filter: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
      child: child,
    );
  }

  Color _baseColor(GlassTheme glass) {
    switch (variant) {
      case GlassVariant.card:
      case GlassVariant.pill:
        return glass.tint;
      case GlassVariant.bar:
      case GlassVariant.sheet:
        return glass.tintStrong;
    }
  }

  @override
  Widget build(BuildContext context) {
    final glass = context.glass;

    final radius =
        borderRadius ?? BorderRadius.circular(_defaultRadius());
    const strokeWidth = 1.1;
    final innerRadius = BorderRadius.only(
      topLeft: _deflate(radius.topLeft, strokeWidth),
      topRight: _deflate(radius.topRight, strokeWidth),
      bottomLeft: _deflate(radius.bottomLeft, strokeWidth),
      bottomRight: _deflate(radius.bottomRight, strokeWidth),
    );

    // When the platform asks for high contrast (accessibility), collapse the
    // translucency to a near-opaque surface and skip the backdrop blur: this
    // keeps text legible over any backdrop and avoids pointless blur cost.
    final highContrast = MediaQuery.maybeHighContrastOf(context) ?? false;

    final alpha = highContrast
        ? 0.94
        : (_baseAlpha(glass) * tintStrength).clamp(0.0, 1.0);
    // Use the theme tint's hue (cool white in light mode, white in dark mode)
    // so glass reads as a frosted translucent panel instead of white-on-white.
    final baseColor = highContrast
        ? Theme.of(context).colorScheme.surface
        : _baseColor(glass);
    final fill = baseColor.withValues(alpha: alpha);

    Widget body = DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: innerRadius,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            fill.withValues(alpha: (alpha * 1.3).clamp(0.0, 1.0)),
            fill,
          ],
        ),
      ),
      child: Stack(
        children: [
          if (showHighlight)
            Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: innerRadius,
                    gradient: glass.highlightGradient,
                  ),
                ),
              ),
            ),
          Padding(padding: padding, child: child),
        ],
      ),
    );

    if (onTap != null) {
      body = InkWell(
        onTap: onTap,
        borderRadius: innerRadius,
        overlayColor: WidgetStatePropertyAll(
          Theme.of(context).colorScheme.primary.withValues(alpha: 0.10),
        ),
        child: body,
      );
    }

    Widget panel = DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: radius,
        gradient: showBorder ? glass.borderGradient : null,
        border: showBorder
            ? null
            : Border.all(color: glass.strokeBottom, width: strokeWidth),
        boxShadow:
            elevation > 0 ? glass.shadows(lift: elevation) : null,
      ),
      child: Padding(
        padding: showBorder
            ? const EdgeInsets.all(strokeWidth)
            : EdgeInsets.zero,
        child: ClipRRect(
          borderRadius: innerRadius,
          child: _maybeBlur(
            enabled: !highContrast,
            sigma: _blurSigma(glass),
            child: Material(
              color: Colors.transparent,
              child: body,
            ),
          ),
        ),
      ),
    );

    if (width != null || height != null) {
      panel = SizedBox(width: width, height: height, child: panel);
    }

    if (constraints != null) {
      panel = ConstrainedBox(constraints: constraints!, child: panel);
    }

    if (alignment != null) {
      panel = Align(alignment: alignment!, child: panel);
    }

    if (margin != null) {
      panel = Padding(padding: margin!, child: panel);
    }

    return panel;
  }
}

Radius _deflate(Radius radius, double amount) {
  final r = (radius.x - amount).clamp(0.0, double.infinity);
  return Radius.circular(r);
}
