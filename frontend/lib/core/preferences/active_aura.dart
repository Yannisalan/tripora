import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../data/destinations.dart';
import '../../models/destination_model.dart';

/// The destination the user picked as their "Active Aura" (Tripora 2.0).
///
/// Purely a local presentation preference: it picks the Home hero image,
/// the accent shown in the sidebar selector and the Planner prefill. It is
/// stored on this device only (SharedPreferences) and never sent to the
/// backend. Only destinations from the app's own destination data can be
/// selected; an unknown stored value is ignored.
class ActiveAura extends ChangeNotifier {
  ActiveAura._();

  static final ActiveAura instance = ActiveAura._();

  static const String _key = 'active_aura_city';

  String? _city;
  bool _loaded = false;

  /// The selected destination, or null when the user has not chosen one.
  DestinationModel? get destination {
    final city = _city;
    if (city == null) return null;
    for (final d in destinations) {
      if (d.city == city) return d;
    }
    return null;
  }

  /// Restores the stored selection once. Safe to call repeatedly.
  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getString(_key);
      if (stored != null && destinations.any((d) => d.city == stored)) {
        _city = stored;
        notifyListeners();
      }
    } catch (error) {
      debugPrint('ACTIVE AURA LOAD ERROR: $error');
    }
  }

  /// Selects [destination] (null clears the selection) and persists it.
  Future<void> select(DestinationModel? destination) async {
    final city = destination?.city;
    if (city == _city) return;
    _city = city;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      if (city == null) {
        await prefs.remove(_key);
      } else {
        await prefs.setString(_key, city);
      }
    } catch (error) {
      debugPrint('ACTIVE AURA SAVE ERROR: $error');
    }
  }

  @visibleForTesting
  void resetForTesting() {
    _city = null;
    _loaded = false;
  }
}
