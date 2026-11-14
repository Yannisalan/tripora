import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../core/theme/app_theme.dart';

/// Tripora brand: the TRIPORA wordmark alone, used by the desktop sidebar
/// and the compact Home app bar (owner decision: no mark, version badge or
/// subtitle). Manrope extra-bold, the app's existing brand typeface.
class TriporaWordmark extends StatelessWidget {
  const TriporaWordmark({super.key});

  @override
  Widget build(BuildContext context) {
    return Text(
      'TRIPORA',
      maxLines: 1,
      overflow: TextOverflow.fade,
      softWrap: false,
      style: GoogleFonts.manrope(
        fontSize: 21,
        fontWeight: FontWeight.w800,
        letterSpacing: 4.2,
        height: 1.1,
        color: context.headingColor,
      ),
    );
  }
}
