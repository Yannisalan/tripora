import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/widgets/google_g_logo.dart';

void main() {
  group('parseGoogleGPath', () {
    test('parses absolute M/C/Z commands', () {
      final path = parseGoogleGPath('M10 10 C10 0 20 0 20 10 Z');
      final bounds = path.getBounds();
      expect(bounds.left, closeTo(10, 0.001));
      expect(bounds.top, closeTo(0, 0.001));
      expect(bounds.right, closeTo(20, 0.001));
      expect(bounds.bottom, closeTo(10, 0.001));
    });

    test('mixes lower-case relative commands with implicit repetition', () {
      final path = parseGoogleGPath(
        'M24 9.5c3.54 0 6.71 1.22 9.21 3.6l6.85-6.85'
        'C35.9 2.38 30.47 0 24 0',
      );
      final bounds = path.getBounds();
      expect(bounds.left, closeTo(24, 0.001));
      expect(bounds.top, closeTo(0, 0.001));
      expect(bounds.right, closeTo(40.06, 0.001));
      expect(bounds.bottom, closeTo(13.1, 0.001));
    });

    test('parses H/h and V/v', () {
      final path = parseGoogleGPath('M46.98 24.55H24v9.02h12.94');
      final bounds = path.getBounds();
      expect(bounds.left, closeTo(24, 0.001));
      expect(bounds.top, closeTo(24.55, 0.001));
      expect(bounds.right, closeTo(46.98, 0.001));
      expect(bounds.bottom, closeTo(33.57, 0.001));
    });

    test('parses the s (smooth cubic) command', () {
      final path = parseGoogleGPath('M10 10c0 5 5 5 5 0s5-5 5 0');
      expect(path.getBounds().width, greaterThan(0));
    });

    for (final segment in _segments) {
      test('official segment "${segment.label}" parses and fits the 48x48 box',
          () {
        final bounds = parseGoogleGPath(segment.d).getBounds();
        expect(bounds.left, greaterThanOrEqualTo(-0.001));
        expect(bounds.top, greaterThanOrEqualTo(-0.001));
        expect(bounds.right, lessThanOrEqualTo(48.001));
        expect(bounds.bottom, lessThanOrEqualTo(48.001));
        expect(bounds.width, greaterThan(0));
        expect(bounds.height, greaterThan(0));
      });
    }

    test('red sector reaches the left boundary region', () {
      final bounds = parseGoogleGPath(_red).getBounds();
      expect(bounds.left, closeTo(2.56, 0.2));
      expect(bounds.top, closeTo(0, 0.2));
    });
  });
}

class _Segment {
  final String label;
  final String d;

  const _Segment(this.label, this.d);
}

const List<_Segment> _segments = [
  _Segment('blue', 'M46.98 24.55c0-1.57-.15-3.09-.38-4.55H24v9.02h12.94'
      'c-.58 2.96-2.26 5.48-4.78 7.18l7.73 6c4.51-4.18 7.09-10.36 7.09-17.65z'),
  _Segment('green', 'M24 48c6.48 0 11.93-2.13 15.89-5.81l-7.73-6'
      'c-2.15 1.45-4.92 2.3-8.16 2.3-6.26 0-11.57-4.22-13.47-9.91l-7.98 6.19'
      'C6.51 42.62 14.62 48 24 48z'),
  _Segment('yellow', 'M10.53 28.59c-.48-1.45-.76-2.99-.76-4.59s.27-3.14'
      '.76-4.59l-7.98-6.19C.92 16.46 0 20.12 0 24c0 3.88.92 7.54 2.56 10.78'
      'l7.97-6.19z'),
  _Segment('red', 'M24 9.5c3.54 0 6.71 1.22 9.21 3.6l6.85-6.85'
      'C35.9 2.38 30.47 0 24 0 14.62 0 6.51 5.38 2.56 13.22l7.98 6.19'
      'C12.43 13.72 17.74 9.5 24 9.5z'),
];

const String _red = 'M24 9.5c3.54 0 6.71 1.22 9.21 3.6l6.85-6.85'
    'C35.9 2.38 30.47 0 24 0 14.62 0 6.51 5.38 2.56 13.22l7.98 6.19'
    'C12.43 13.72 17.74 9.5 24 9.5z';