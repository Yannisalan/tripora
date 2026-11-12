import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../config/app_config.dart';

/// Bot-protection settings published by the backend (`GET /api/turnstile/config`).
///
/// Only the PUBLIC site key ever reaches the app. The secret stays on the
/// server, which verifies every token.
class TurnstileConfig {
  const TurnstileConfig({
    required this.enabled,
    required this.siteKey,
    required this.challengePath,
  });

  const TurnstileConfig.disabled()
      : enabled = false,
        siteKey = null,
        challengePath = defaultChallengePath;

  static const String defaultChallengePath = '/api/turnstile/challenge';

  final bool enabled;
  final String? siteKey;
  final String challengePath;

  /// Enabled but missing a site key: the widget cannot render.
  bool get usable => !enabled || (siteKey != null && siteKey!.isNotEmpty);

  factory TurnstileConfig.fromJson(Map<String, dynamic> json) {
    final enabled = json['enabled'] == true;
    final key = json['siteKey'];
    final path = json['challengePath'];
    return TurnstileConfig(
      enabled: enabled,
      siteKey: key is String && key.trim().isNotEmpty ? key.trim() : null,
      // Only a same-origin absolute path is accepted.
      challengePath: path is String && path.startsWith('/api/turnstile/')
          ? path
          : defaultChallengePath,
    );
  }
}

class TurnstileConfigService {
  TurnstileConfigService._();

  static Future<TurnstileConfig>? _cached;

  /// Loads once per app run; a failed load is retried on the next call.
  static Future<TurnstileConfig> load({String? baseUrl}) {
    final cached = _cached;
    if (cached != null) return cached;
    final future = _fetch(baseUrl ?? AppConfig.apiBaseUrl);
    _cached = future;
    future.catchError((Object _) {
      _cached = null;
      return const TurnstileConfig.disabled();
    });
    return future;
  }

  static Future<TurnstileConfig> _fetch(String baseUrl) async {
    final response = await http
        .get(
          Uri.parse('$baseUrl/api/turnstile/config'),
          headers: const {'Accept': 'application/json'},
        )
        .timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) {
      throw Exception('Turnstile config unavailable (${response.statusCode}).');
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Turnstile config is not an object.');
    }
    return TurnstileConfig.fromJson(decoded);
  }

  /// Tests only.
  static void debugReset() => _cached = null;
}
