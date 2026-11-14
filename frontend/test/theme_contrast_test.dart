// WCAG AA contrast of the theme tokens, in both modes. Pure color math on
// the real ThemeData objects the app uses - no widgets pumped.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:frontend/core/design/glass/glass_tokens.dart';
import 'package:frontend/core/theme/app_theme.dart';

import 'support/contrast.dart';

void main() {
  for (final mode in const ['light', 'dark']) {
    final theme = mode == 'light' ? AppTheme.lightTheme : AppTheme.darkTheme;
    final c = theme.extension<TriporaColors>()!;
    final status = theme.extension<AppStatusColors>()!;
    final glass = theme.extension<GlassTheme>()!;
    final scheme = theme.colorScheme;

    // The page backdrop and the two glass fills content actually sits on.
    final backdrops = <String, Color>{
      'background': c.backgroundColor,
      'surface': c.surface,
      'glass card': Color.alphaBlend(glass.tint, c.backgroundColor),
      'glass bar/sheet': Color.alphaBlend(glass.tintStrong, c.backgroundColor),
    };

    group('$mode theme tokens (WCAG AA)', () {
      // Normal-size text: 4.5:1.
      final text = <String, Color>{
        'textPrimary': c.textPrimary,
        'textSecondary': c.textSecondary,
        'textMuted': c.textMuted,
        'heading (onSurface)': scheme.onSurface,
        'error text': scheme.error,
      };
      for (final t in text.entries) {
        for (final b in backdrops.entries) {
          test('${t.key} on ${b.key} >= 4.5', () {
            final ratio = contrastRatio(t.value, b.value);
            expect(
              ratio,
              greaterThanOrEqualTo(4.5),
              reason:
                  '${t.key} ${hex(t.value)} on ${b.key} ${hex(b.value)} '
                  '= ${ratio.toStringAsFixed(2)}',
            );
          });
        }
      }

      // Accent used for links, active nav items, focused borders, icons:
      // UI components 3:1 (and the nav label text it colours: 4.5:1 on the
      // bar).
      for (final b in backdrops.entries) {
        test('primary (accent/active) on ${b.key} >= 3', () {
          final ratio = contrastRatio(scheme.primary, b.value);
          expect(
            ratio,
            greaterThanOrEqualTo(3.0),
            reason:
                'primary ${hex(scheme.primary)} on ${hex(b.value)} '
                '= ${ratio.toStringAsFixed(2)}',
          );
        });
      }
      test('active nav label (primary) on bar >= 4.5', () {
        final bar = backdrops['glass bar/sheet']!;
        final ratio = contrastRatio(scheme.primary, bar);
        expect(
          ratio,
          greaterThanOrEqualTo(4.5),
          reason: ratio.toStringAsFixed(2),
        );
      });

      // Text on filled buttons and chips.
      test('onPrimary on primary >= 4.5', () {
        final ratio = contrastRatio(scheme.onPrimary, scheme.primary);
        expect(
          ratio,
          greaterThanOrEqualTo(4.5),
          reason: ratio.toStringAsFixed(2),
        );
      });

      // Semantic status colours used as text/icons on surfaces: 3:1 (they
      // are icons and bold labels; body copy uses textPrimary).
      final statuses = <String, Color>{
        'success': status.success,
        'warning': status.warning,
        'error': status.error,
        'info': status.info,
      };
      for (final s in statuses.entries) {
        test('status ${s.key} on surface >= 3', () {
          final ratio = contrastRatio(s.value, c.surface);
          expect(
            ratio,
            greaterThanOrEqualTo(3.0),
            reason:
                '${hex(s.value)} on ${hex(c.surface)} '
                '= ${ratio.toStringAsFixed(2)}',
          );
        });
      }

      // Input borders and dividers that delimit controls: 3:1 for the
      // strong border (input outline); hairline dividers are decorative.
      // Text-field outline: the field fill matches the surfaces around it,
      // so the outline is the boundary and needs 3:1 (WCAG SC 1.4.11)
      // against both the fill inside and every surface outside it.
      final enabled =
          theme.inputDecorationTheme.enabledBorder!.borderSide.color;
      final adjacent = <String, Color>{
        ...backdrops,
        'surfaceSecondary': c.surfaceSecondary,
        'input fill': theme.inputDecorationTheme.fillColor!,
        if (mode == 'light') 'page gradient top': const Color(0xFFE7EDFF),
      };
      for (final b in adjacent.entries) {
        test('input outline on ${b.key} >= 3 (SC 1.4.11)', () {
          final ratio = contrastRatio(enabled, b.value);
          expect(
            ratio,
            greaterThanOrEqualTo(3.0),
            reason:
                '${hex(enabled)} on ${hex(b.value)} '
                '= ${ratio.toStringAsFixed(2)}',
          );
        });
      }

      // App bar back arrow / icons take the app bar foreground.
      test('app bar foreground on background >= 3', () {
        final fg = theme.appBarTheme.foregroundColor ?? scheme.onSurface;
        final ratio = contrastRatio(fg, c.backgroundColor);
        expect(
          ratio,
          greaterThanOrEqualTo(3.0),
          reason: '${hex(fg)} = ${ratio.toStringAsFixed(2)}',
        );
      });
    });
  }
}
