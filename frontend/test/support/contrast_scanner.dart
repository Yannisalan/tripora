// Walks every visible text and icon on screen and measures its contrast
// against the background it is actually painted on: the nearest ancestor
// fills (ColoredBox, DecoratedBox colour/gradient, Material), composited
// translucent-over-opaque down to the theme backdrop, with ancestor opacity
// applied to the foreground.
//
// Not measurable automatically, so skipped and counted separately:
//  - text over photography (an image painted underneath in a Stack); its
//    scrims are checked by eye in the report,
//  - disabled controls (WCAG 1.4.3 exempts inactive components),
//  - invisible content (fully transparent or zero-size).
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'contrast.dart';

class ContrastIssue {
  ContrastIssue(
    this.text,
    this.ratio,
    this.required,
    this.fg,
    this.bg,
    this.chain,
  );
  final String text;
  final double ratio;
  final double required;
  final Color fg;
  final Color bg;
  final String chain;

  @override
  String toString() =>
      '"$text" ${ratio.toStringAsFixed(2)} < $required '
      '(fg ${hex(fg)} on ${hex(bg)}) via $chain';
}

class ContrastReport {
  final List<ContrastIssue> issues = [];
  int checked = 0;
  int overPhoto = 0;
  int disabled = 0;
}

bool _isIconFont(TextStyle? s) {
  final f = s?.fontFamily ?? '';
  return f.contains('MaterialIcons') || f.contains('CupertinoIcons');
}

/// Colour of [g] at [point] inside [rect]. Linear gradients are evaluated
/// at the exact position (a glass panel is lighter at its top-left than at
/// its bottom-right); other gradient kinds return every stop (worst case).
List<Color> _gradientAt(Gradient g, Rect rect, Offset point) {
  double t;
  if (g is RadialGradient) {
    // Same geometry Flutter uses: radius is a fraction of the shortest side.
    final c = (g.center as Alignment).withinRect(rect);
    final r = g.radius * rect.shortestSide;
    t = r == 0 ? 1.0 : ((point - c).distance / r).clamp(0.0, 1.0);
  } else if (g is LinearGradient) {
    final b = (g.begin as Alignment).withinRect(rect);
    final e = (g.end as Alignment).withinRect(rect);
    final d = e - b;
    final len2 = d.dx * d.dx + d.dy * d.dy;
    t = len2 == 0
        ? 0.0
        : (((point.dx - b.dx) * d.dx + (point.dy - b.dy) * d.dy) / len2)
            .clamp(0.0, 1.0);
  } else {
    return g.colors;
  }
  final colors = g.colors;
  final stops =
      g.stops ??
      [for (var i = 0; i < colors.length; i++) i / (colors.length - 1)];
  if (t <= stops.first) return [colors.first];
  for (var i = 1; i < stops.length; i++) {
    if (t <= stops[i]) {
      final span = stops[i] - stops[i - 1];
      final local = span == 0 ? 0.0 : (t - stops[i - 1]) / span;
      return [Color.lerp(colors[i - 1], colors[i], local)!];
    }
  }
  t = 1;
  return [colors.last];
}

/// Colours a decoration paints under [point] (global), or null when it
/// paints none. `photo` is set when it paints an image.
List<Color>? _decorationColors(
  Decoration d,
  RenderObject? box,
  Offset point,
  void Function() photo,
) {
  Gradient? gradient;
  Color? color;
  if (d is BoxDecoration) {
    if (d.image != null) photo();
    gradient = d.gradient;
    color = d.color;
  } else if (d is ShapeDecoration) {
    if (d.image != null) photo();
    gradient = d.gradient;
    color = d.color;
  }
  if (gradient != null) {
    if (box is RenderBox && box.hasSize) {
      final local = box.globalToLocal(point);
      return _gradientAt(gradient, Offset.zero & box.size, local);
    }
    return gradient.colors;
  }
  if (color != null) return [color];
  return null;
}

bool _subtreePaintsImage(RenderObject root) {
  var found = false;
  void visit(RenderObject o) {
    if (found) return;
    if (o is RenderImage) {
      found = true;
      return;
    }
    if (o is RenderDecoratedBox) {
      final d = o.decoration;
      if (d is BoxDecoration && d.image != null) {
        found = true;
        return;
      }
    }
    o.visitChildren(visit);
  }

  visit(root);
  return found;
}

/// True when an image is painted underneath [target] inside a Stack.
bool _overPhoto(RenderObject target) {
  RenderObject child = target;
  var parent = target.parent;
  while (parent != null) {
    // Only a plain Stack paints earlier children underneath later ones
    // (an IndexedStack paints just one child).
    if (parent is RenderStack && parent is! RenderIndexedStack) {
      var reached = false;
      var image = false;
      parent.visitChildren((c) {
        if (reached || image) return;
        if (identical(c, child)) {
          reached = true;
        } else if (_subtreePaintsImage(c)) {
          image = true;
        }
      });
      if (image) return true;
    }
    if (parent is RenderDecoratedBox) {
      final d = parent.decoration;
      if (d is BoxDecoration && d.image != null) return true;
    }
    child = parent;
    parent = parent.parent;
  }
  return false;
}

/// True when an [Image] widget (loaded, loading or showing its error
/// fallback) is painted underneath [e] inside a Stack - i.e. the text sits
/// on photography. Network photos do not load in widget tests, so this
/// looks at widgets, not pixels.
bool _overImageWidget(Element e) {
  var result = false;
  Element child = e;
  e.visitAncestorElements((a) {
    if (a.widget is Stack && a.widget is! IndexedStack) {
      var reached = false;
      a.visitChildren((c) {
        if (reached || result) return;
        if (identical(c, child)) {
          reached = true;
          return;
        }
        void search(Element x) {
          if (result) return;
          if (x.widget is Image) {
            result = true;
            return;
          }
          x.visitChildren(search);
        }

        search(c);
      });
      if (result) return false;
    }
    child = a;
    return true;
  });
  return result;
}

bool _disabled(Element e) {
  var disabled = false;
  e.visitAncestorElements((a) {
    final w = a.widget;
    if (w is ButtonStyleButton && !w.enabled) disabled = true;
    if (w is IconButton && w.onPressed == null) disabled = true;
    if (w is TextField && w.enabled == false) disabled = true;
    if (w is IgnorePointer && w.ignoring) disabled = disabled;
    return !disabled;
  });
  return disabled;
}

/// Scan every on-stage RichText in the tree.
ContrastReport scanContrast(WidgetTester tester, {required Color backdrop}) {
  final report = ContrastReport();
  final viewSize = tester.view.physicalSize / tester.view.devicePixelRatio;
  final screen = Offset.zero & viewSize;

  for (final element in find.byType(RichText).evaluate()) {
    final render = element.renderObject;
    if (render is! RenderParagraph || !render.hasSize) continue;
    if (render.size.isEmpty) continue;
    final rect = MatrixUtils.transformRect(
      render.getTransformTo(null),
      Offset.zero & render.size,
    );
    if (!rect.overlaps(screen)) continue;

    final span = render.text;
    final plain = span.toPlainText().trim();
    if (plain.isEmpty) continue;

    // First styled leaf decides colour/size (labels are single-styled).
    TextStyle? style = span.style;
    span.visitChildren((s) {
      if (s is TextSpan && s.text != null && s.text!.trim().isNotEmpty) {
        style = (span.style ?? const TextStyle()).merge(s.style);
        return false;
      }
      return true;
    });
    final color = style?.color ?? style?.foreground?.color;
    if (color == null || color.a == 0) continue;

    // Material draws inactive items (e.g. past days in a date picker) at
    // 38% opacity; WCAG 1.4.3 exempts inactive components.
    if (_disabled(element) || color.a <= 0.40) {
      report.disabled++;
      continue;
    }
    if (_overPhoto(render) || _overImageWidget(element)) {
      report.overPhoto++;
      continue;
    }

    // Foreground opacity from ancestors.
    var opacity = 1.0;
    RenderObject? p = render.parent;
    while (p != null) {
      if (p is RenderOpacity) opacity *= p.opacity;
      if (p is RenderAnimatedOpacity) opacity *= p.opacity.value;
      p = p.parent;
    }
    if (opacity < 0.05) continue;

    // Background layers, nearest first.
    final layers = <List<Color>>[];
    final chain = <String>[];
    var photo = false;
    Element pathChild = element;
    element.visitAncestorElements((a) {
      final w = a.widget;

      // Underlays: decorations painted by EARLIER children of a Stack that
      // cover this text (e.g. the glass panel's top highlight sweep).
      if (w is Stack && w is! IndexedStack) {
        var reached = false;
        a.visitChildren((sibling) {
          if (reached) return;
          if (identical(sibling, pathChild)) {
            reached = true;
            return;
          }
          void search(Element x) {
            // Ambient blobs are blurred (sigma 70, then again by the
            // glass backdrop filter); an unblurred model would overstate
            // them, so blurred subtrees are not treated as underlays.
            if (x.widget is ImageFiltered) return;
            final ro = x.renderObject;
            if (x.widget is DecoratedBox &&
                ro is RenderBox &&
                ro.hasSize &&
                (x.widget as DecoratedBox).position ==
                    DecorationPosition.background) {
              final box = MatrixUtils.transformRect(
                ro.getTransformTo(null),
                Offset.zero & ro.size,
              );
              if (box.contains(rect.center)) {
                final colors = _decorationColors(
                  (x.widget as DecoratedBox).decoration,
                  ro,
                  rect.center,
                  () {},
                );
                if (colors != null && colors.any((k) => k.a > 0)) {
                  layers.add(colors);
                  chain.add('underlay');
                }
              }
            }
            x.visitChildren(search);
          }

          search(sibling);
        });
      }
      pathChild = a;

      List<Color>? c;
      if (w is ColoredBox) {
        c = [w.color];
      } else if (w is Ink && w.decoration != null) {
        c = _decorationColors(
          w.decoration!,
          a.findRenderObject(),
          rect.center,
          () => photo = true,
        );
      } else if (w is DecoratedBox &&
          w.position == DecorationPosition.background) {
        c = _decorationColors(
          w.decoration,
          a.renderObject,
          rect.center,
          () => photo = true,
        );
      } else if (w is Material &&
          w.type != MaterialType.transparency &&
          w.color != null) {
        c = [w.color!];
      } else if (w is Material &&
          (w.type == MaterialType.canvas || w.type == MaterialType.card)) {
        final theme = Theme.of(a);
        c = [w.type == MaterialType.card ? theme.cardColor : theme.canvasColor];
      }
      if (c != null && c.any((x) => x.a > 0)) {
        layers.add(c);
        chain.add(w.runtimeType.toString());
        if (c.every((x) => x.a >= 0.999)) return false;
      }
      return !photo;
    });
    if (photo) {
      report.overPhoto++;
      continue;
    }

    // Composite each gradient stop down to the backdrop; worst case wins.
    List<Color> under = [backdrop];
    for (final layer in layers.reversed) {
      final next = <Color>[];
      for (final top in layer) {
        for (final base in under) {
          next.add(Color.alphaBlend(top, base));
        }
      }
      under = next;
    }

    final fg = color.withValues(alpha: color.a * opacity);
    final isIcon = _isIconFont(style);
    final size = (style?.fontSize ?? 14);
    final bold = (style?.fontWeight?.value ?? 400) >= 700;
    final large = size >= 24 || (bold && size >= 18.66);
    final required = isIcon || large ? 3.0 : 4.5;

    var worst = double.infinity;
    Color worstBg = under.first;
    for (final bg in under) {
      final r = contrastRatio(fg, bg);
      if (r < worst) {
        worst = r;
        worstBg = bg;
      }
    }
    report.checked++;
    if (worst < required) {
      final creator = element
          .debugGetCreatorChain(6)
          .split(' ← ')
          .where((s) => !s.startsWith('RichText') && !s.startsWith('Text'))
          .take(4)
          .join(' < ');
      report.issues.add(
        ContrastIssue(
          isIcon ? 'icon U+${plain.runes.first.toRadixString(16)}' : plain,
          worst,
          required,
          fg,
          worstBg,
          '${chain.join('/')} | $creator',
        ),
      );
    }
  }
  return report;
}
