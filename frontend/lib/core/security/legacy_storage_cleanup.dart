import 'package:shared_preferences/shared_preferences.dart';

/// Removes credentials that older app versions left in plain storage.
///
/// Up to the 2026-11 security hardening, the admin dashboard saved the shared
/// `ADMIN_API_TOKEN` in SharedPreferences under `admin_token` (browser
/// `localStorage` on the web). The admin UI no longer exists, so that copy is
/// a lingering secret readable by any script on the origin. This runs at
/// every app start; it is idempotent and never throws.
class LegacyStorageCleanup {
  LegacyStorageCleanup._();

  /// SharedPreferences key used by the removed admin dashboard.
  static const String legacyAdminTokenKey = 'admin_token';

  static Future<void> run() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.containsKey(legacyAdminTokenKey)) {
        await prefs.remove(legacyAdminTokenKey);
      }
    } catch (_) {
      // Storage unavailable (private mode, blocked site data): nothing to
      // remove, and app start must not fail because of it.
    }
  }
}
