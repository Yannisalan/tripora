import 'dart:convert';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:http/http.dart' as http;

import '../core/config/app_config.dart';

/// Lightweight, fire-and-forget page-view/activity tracking beacon.
///
/// Reports screen visits to the backend analytics endpoint. Failures are
/// swallowed (analytics must never block or crash the UI), and page views are
/// reported at most every [pageViewThrottleMs] per route to avoid spamming the
/// backend during frequent navigation.
class ActivityService {
  static const String baseUrl = AppConfig.apiBaseUrl;

  /// Minimum gap (ms) between two page-view reports for the same route name.
  static const int pageViewThrottleMs = 1500;

  final Map<String, int> _lastReportedAt = {};

  /// Report a screen visit. Never throws.
  Future<void> trackPageView(String path) async {
    if (path.isEmpty) return;

    final now = DateTime.now().millisecondsSinceEpoch;
    final last = _lastReportedAt[path] ?? 0;
    if (now - last < pageViewThrottleMs) return;
    _lastReportedAt[path] = now;

    try {
      await http.post(
        Uri.parse('$baseUrl/api/admin/page-view'),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: jsonEncode({'path': path}),
      );
    } catch (error) {
      debugPrint('ActivityService: failed to report page view: $error');
    }
  }
}
