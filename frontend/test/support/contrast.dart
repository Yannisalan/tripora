import 'dart:math' as math;

import 'package:flutter/painting.dart';

/// WCAG 2.x relative luminance of an opaque color.
double relativeLuminance(Color c) {
  double channel(double v) =>
      v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * channel(c.r) + 0.7152 * channel(c.g) + 0.0722 * channel(c.b);
}

/// WCAG contrast ratio. A translucent [foreground] is first composited over
/// [background]; [background] must be opaque.
double contrastRatio(Color foreground, Color background) {
  final fg = foreground.a < 1
      ? Color.alphaBlend(foreground, background)
      : foreground;
  final l1 = relativeLuminance(fg);
  final l2 = relativeLuminance(background);
  final hi = math.max(l1, l2);
  final lo = math.min(l1, l2);
  return (hi + 0.05) / (lo + 0.05);
}

String hex(Color c) =>
    '#${c.toARGB32().toRadixString(16).padLeft(8, '0').toUpperCase()}';
