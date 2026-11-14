import 'package:flutter/material.dart';

import '../../models/destination_model.dart';
import 'app_theme.dart';

/// ---------------------------------------------------------------------
/// Destination accent auras (Tripora 2.0)
///
/// The ONE place destination colours live. Screens never hardcode a
/// destination colour; they ask [DestinationAccents.of].
///
/// PENDING OWNER APPROVAL (Phase 4): these 22 values are proposals, not
/// brand-approved colours. Each is used only as a non-text graphic (accent
/// dot, selection ring, card glow), so it must reach WCAG 3:1 (SC 1.4.11):
///
/// - [DestinationAccent.dark]: >= 3.2:1 on #111729, #22263A and #2A2F45.
/// - [DestinationAccent.light]: the same hue with HSL lightness lowered
///   until >= 3.2:1 on #FFFFFF, #F1F5F9 and the page gradient top #E7EDFF.
///
/// A destination without an entry falls back to the brand crimson, so new
/// destination data keeps working without a colour.
/// ---------------------------------------------------------------------

@immutable
class DestinationAccent {
  const DestinationAccent({required this.dark, required this.light});

  final Color dark;
  final Color light;

  Color resolve(bool isDark) => isDark ? dark : light;
}

class DestinationAccents {
  DestinationAccents._();

  static const DestinationAccent brand = DestinationAccent(
    dark: TriporaBrand.crimson,
    light: TriporaBrand.crimsonDeep,
  );

  /// Keyed by [DestinationModel.city].
  static const Map<String, DestinationAccent> byCity = {
    'Paris': DestinationAccent(
      dark: Color(0xFF8C9EFF),
      light: Color(0xFF5E77FF),
    ),
    'London': DestinationAccent(
      dark: Color(0xFF5FA8D3),
      light: Color(0xFF3489BC),
    ),
    'Venice': DestinationAccent(
      dark: Color(0xFF2EC4B6),
      light: Color(0xFF229288),
    ),
    'Rome': DestinationAccent(
      dark: Color(0xFFE07A5F),
      light: Color(0xFFD95A39),
    ),
    'Tokyo': DestinationAccent(
      dark: Color(0xFFFF6B9A),
      light: Color(0xFFFF1962),
    ),
    'Dubai': DestinationAccent(
      dark: Color(0xFFE9B44C),
      light: Color(0xFFAB7815),
    ),
    'Bali': DestinationAccent(
      dark: Color(0xFF4CC38A),
      light: Color(0xFF319263),
    ),
    'Bangkok': DestinationAccent(
      dark: Color(0xFFF4A259),
      light: Color(0xFFCA660D),
    ),
    'Cotonou': DestinationAccent(
      dark: Color(0xFFF2C14E),
      light: Color(0xFFAA7B0C),
    ),
    'Abidjan': DestinationAccent(
      dark: Color(0xFFFF8F5A),
      light: Color(0xFFE94B00),
    ),
    'Seychelles': DestinationAccent(
      dark: Color(0xFF3DD6D0),
      light: Color(0xFF1E8F8A),
    ),
    'Cape Town': DestinationAccent(
      dark: Color(0xFF6FA8FF),
      light: Color(0xFF287DFF),
    ),
    'New York': DestinationAccent(
      dark: Color(0xFFB0B8C9),
      light: Color(0xFF7684A2),
    ),
    'San Francisco': DestinationAccent(
      dark: Color(0xFFFF7A45),
      light: Color(0xFFED4400),
    ),
    'Rio de Janeiro': DestinationAccent(
      dark: Color(0xFF5EDC7A),
      light: Color(0xFF20953A),
    ),
    'Buenos Aires': DestinationAccent(
      dark: Color(0xFF7FB3FF),
      light: Color(0xFF237CFF),
    ),
    'Cusco': DestinationAccent(
      dark: Color(0xFFD98E5B),
      light: Color(0xFFC46A2D),
    ),
    'Cartagena': DestinationAccent(
      dark: Color(0xFFFFB347),
      light: Color(0xFFBC6F00),
    ),
    'Sydney': DestinationAccent(
      dark: Color(0xFF38BDF8),
      light: Color(0xFF0789C3),
    ),
    'Queenstown': DestinationAccent(
      dark: Color(0xFF7DD3C0),
      light: Color(0xFF31907B),
    ),
    'Fiji': DestinationAccent(
      dark: Color(0xFF22D3EE),
      light: Color(0xFF0D8FA3),
    ),
    'Bora Bora': DestinationAccent(
      dark: Color(0xFF2DD4BF),
      light: Color(0xFF1E9283),
    ),
  };

  static DestinationAccent forDestination(DestinationModel? destination) =>
      destination == null ? brand : (byCity[destination.city] ?? brand);

  /// Accent colour for [destination] in the current theme mode.
  static Color of(BuildContext context, DestinationModel? destination) =>
      forDestination(
        destination,
      ).resolve(Theme.of(context).brightness == Brightness.dark);
}
