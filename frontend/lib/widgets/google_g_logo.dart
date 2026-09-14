import 'package:flutter/material.dart';

/// The official Google "G" mark rendered as a [CustomPaint].
///
/// Paint geometry is the official 48x48 vector from Google's brand guide:
/// * `#4285F4` (blue)    — upper-right segment
/// * `#34A853` (green)   — lower-right segment
/// * `#FBBC05` (yellow)  — lower-left segment
/// * `#EA4335` (red)     — upper-left segment
class GoogleGLogo extends StatelessWidget {
  final double size;

  const GoogleGLogo({super.key, this.size = 22});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.square(size),
      painter: const _GoogleGLogoPainter(),
    );
  }
}

class _GoogleGLogoPainter extends CustomPainter {
  const _GoogleGLogoPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.shortestSide / 48.0;
    final paint = Paint()..style = PaintingStyle.fill;

    canvas.scale(scale);

    for (final segment in _segments) {
      paint.color = segment.color;
      canvas.drawPath(parseGoogleGPath(segment.d), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _GoogleGLogoPainter oldDelegate) => false;
}

class _Segment {
  final Color color;
  final String d;

  const _Segment(this.color, this.d);
}

/// The official multi-colour Google G paths in 48x48 coordinates.
const List<_Segment> _segments = [
  _Segment(Color(0xFF4285F4), _blue),
  _Segment(Color(0xFF34A853), _green),
  _Segment(Color(0xFFFBBC05), _yellow),
  _Segment(Color(0xFFEA4335), _red),
];

const String _blue = 'M46.98 24.55c0-1.57-.15-3.09-.38-4.55H24v9.02h12.94'
    'c-.58 2.96-2.26 5.48-4.78 7.18l7.73 6c4.51-4.18 7.09-10.36 7.09-17.65z';
const String _green = 'M24 48c6.48 0 11.93-2.13 15.89-5.81l-7.73-6'
    'c-2.15 1.45-4.92 2.3-8.16 2.3-6.26 0-11.57-4.22-13.47-9.91l-7.98 6.19'
    'C6.51 42.62 14.62 48 24 48z';
const String _yellow = 'M10.53 28.59c-.48-1.45-.76-2.99-.76-4.59s.27-3.14'
    '.76-4.59l-7.98-6.19C.92 16.46 0 20.12 0 24c0 3.88.92 7.54 2.56 10.78'
    'l7.97-6.19z';
const String _red = 'M24 9.5c3.54 0 6.71 1.22 9.21 3.6l6.85-6.85'
    'C35.9 2.38 30.47 0 24 0 14.62 0 6.51 5.38 2.56 13.22l7.98 6.19'
    'C12.43 13.72 17.74 9.5 24 9.5z';

/// Parses the SVG path data used by the Google G glyphs (M/m, L/l, H/h, V/v,
/// C/c, S/s and Z/z commands) into a [Path] in the 48x48 coordinate space;
/// the painter scales the resulting path.
Path parseGoogleGPath(String d) {
  final tokens = _tokenize(d);
  final path = Path();
  var i = 0;

  double x = 0, y = 0;
  double? lastControlX, lastControlY;
  var needMoveTo = true;
  var currentCommand = '';

  double readNumber() {
    if (i >= tokens.length) {
      throw const FormatException('Malformed SVG path: ran out of numbers.');
    }
    final value = double.tryParse(tokens[i]);
    if (value == null) {
      throw FormatException('Malformed SVG path number: ${tokens[i]}.');
    }
    i++;
    return value;
  }

  while (i < tokens.length) {
    if (_isCommand(tokens[i])) {
      currentCommand = tokens[i];
      i++;
    }

    if (currentCommand.isEmpty) break;

    final upper = currentCommand.toUpperCase();
    final relative = currentCommand != upper;

    switch (upper) {
      case 'M' || 'L':
        final nextX = readNumber();
        final nextY = readNumber();
        x = relative ? x + nextX : nextX;
        y = relative ? y + nextY : nextY;
        lastControlX = lastControlY = null;
        if (upper == 'M' && needMoveTo) {
          path.moveTo(x, y);
          needMoveTo = false;
        } else {
          path.lineTo(x, y);
        }
      case 'H':
        final nextX = readNumber();
        x = relative ? x + nextX : nextX;
        path.lineTo(x, y);
        lastControlX = lastControlY = null;
      case 'V':
        final nextY = readNumber();
        y = relative ? y + nextY : nextY;
        path.lineTo(x, y);
        lastControlX = lastControlY = null;
      case 'C':
        final points = <double>[for (var n = 0; n < 6; n++) readNumber()];

        final c1x = relative ? x + points[0] : points[0];
        final c1y = relative ? y + points[1] : points[1];
        final c2x = relative ? x + points[2] : points[2];
        final c2y = relative ? y + points[3] : points[3];
        final ex = relative ? x + points[4] : points[4];
        final ey = relative ? y + points[5] : points[5];

        path.cubicTo(c1x, c1y, c2x, c2y, ex, ey);
        lastControlX = c2x;
        lastControlY = c2y;
        x = ex;
        y = ey;
      case 'S':
        final points = <double>[for (var n = 0; n < 4; n++) readNumber()];

        // Smooth: mirror the previous control point about (x, y).
        final c1x = 2 * x - (lastControlX ?? x);
        final c1y = 2 * y - (lastControlY ?? y);
        final c2x = relative ? x + points[0] : points[0];
        final c2y = relative ? y + points[1] : points[1];
        final ex = relative ? x + points[2] : points[2];
        final ey = relative ? y + points[3] : points[3];

        path.cubicTo(c1x, c1y, c2x, c2y, ex, ey);
        lastControlX = c2x;
        lastControlY = c2y;
        x = ex;
        y = ey;
      case 'Z':
        path.close();
        needMoveTo = true;
        lastControlX = lastControlY = null;
        currentCommand = ''; // Never reuse Z: it takes no arguments.
      default:
        break;
    }
  }

  return path;
}

List<String> _tokenize(String d) {
  final out = <String>[];

  var i = 0;
  while (i < d.length) {
    final c = d[i];

    if (_isCommand(c)) {
      out.add(c);
      i++;
      continue;
    }

    if (c == '-' || c == '.' ||
        (c.compareTo('0') >= 0 && c.compareTo('9') <= 0)) {
      final start = i;
      if (d[i] == '-') {
        i++; // Consume the sign even if no digits follow (avoid stall).
      }
      var dotSeen = false;
      while (i < d.length) {
        final ch = d[i];
        if (ch == '.') {
          if (dotSeen) break; // A second '.' starts the next number.
          dotSeen = true;
          i++;
        } else if (ch.compareTo('0') >= 0 && ch.compareTo('9') <= 0) {
          i++;
        } else {
          break;
        }
      }
      final raw = d.substring(start, i);
      if (double.tryParse(raw) != null) {
        out.add(raw);
      }
      continue;
    }

    i++; // Unrecognised character (e.g. whitespace); skip.
  }

  return out;
}

bool _isCommand(String c) => 'MmLlHhVvCcSsZz'.contains(c);