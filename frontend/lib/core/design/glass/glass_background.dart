import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import 'glass_tokens.dart';

/// ---------------------------------------------------------------------
/// Ambient glass background
///
/// A deep, softly-lit backdrop the glass surfaces refract. Built from
/// blurred accent blobs over a base color - no image assets required, so
/// it renders identically on iOS, Android, Web and desktop.
/// ---------------------------------------------------------------------

class GlassBackground extends StatelessWidget {
  const GlassBackground({
    super.key,
    this.child,
    this.intensity = 1,
  });

  /// Content drawn on top of the backdrop.
  final Widget? child;

  /// Scales the accent-blob opacity. `0` yields a flat base color.
  final double intensity;

  @override
  Widget build(BuildContext context) {
    final glass = context.glass;
    final isDark = glass.isDark;
    final base = Theme.of(context).scaffoldBackgroundColor;

    // Dark mode keeps its deep night base with two soft accents. Light mode
    // swaps the flat near-white base for a cool indigo wash and adds a third
    // accent, so the backdrop carries real colour and luminance for glass to
    // refract. Blurring a uniform pale field is why light mode previously
    // read as a plain grey card instead of glass.
    final sky = GlassAccents.sky.withValues(
      alpha: (isDark ? 0.22 : 0.42) * intensity,
    );
    final indigo = GlassAccents.indigo.withValues(
      alpha: (isDark ? 0.24 : 0.34) * intensity,
    );
    final indigoSoft = GlassAccents.indigo.withValues(
      alpha: 0.30 * intensity,
    );

    return Stack(
      fit: StackFit.expand,
      children: [
        if (isDark)
          ColoredBox(color: base)
        else
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0xFFE7EDFF),
                  Color(0xFFF3F6FC),
                  Color(0xFFF8FAFC),
                ],
                stops: [0.0, 0.55, 1.0],
              ),
            ),
          ),

        if (intensity > 0) ...[
          Positioned(
            top: isDark ? -120 : -150,
            left: isDark ? -100 : -130,
            width: isDark ? 360 : 460,
            height: isDark ? 360 : 460,
            child: _Blob(color: sky),
          ),
          Positioned(
            top: isDark ? -60 : -90,
            right: isDark ? -110 : -140,
            width: isDark ? 340 : 440,
            height: isDark ? 340 : 440,
            child: _Blob(color: indigo),
          ),
          if (!isDark)
            Positioned(
              bottom: -170,
              right: -90,
              width: 430,
              height: 430,
              child: _Blob(color: indigoSoft),
            ),
        ],

        if (child != null) Positioned.fill(child: child!),
      ],
    );
  }
}

class _Blob extends StatelessWidget {
  const _Blob({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: ImageFiltered(
        imageFilter: ImageFilter.blur(sigmaX: 70, sigmaY: 70),
        child: DecoratedBox(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
              colors: [color, color.withValues(alpha: 0)],
            ),
          ),
        ),
      ),
    );
  }
}
