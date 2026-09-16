import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../core/config/app_config.dart';

/// Fetches the weather forecast for a trip from the Tripora backend
/// (``GET /api/trips/<id>/weather``) with a lightweight 30-minute in-memory
/// cache keyed by trip id.
class WeatherService {
  WeatherService._();

  static const String baseUrl = AppConfig.apiBaseUrl;
  static const Duration ttl = Duration(minutes: 30);

  /// Max time to wait for the backend. The Render free tier spins down
  /// after inactivity, so a cold start can take tens of seconds; without
  /// a timeout the request can hang for a very long time and surface as a
  /// silent "unavailable" once the browser finally gives up.
  static const Duration requestTimeout = Duration(seconds: 25);

  static final Map<int, _CacheEntry> _cache = {};

  // ----------------------------------------------------------
  // AUTH
  // ----------------------------------------------------------

  static Future<String?> _getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('access_token');
  }

  // ----------------------------------------------------------
  // PUBLIC API
  // ----------------------------------------------------------

  /// Returns the parsed weather payload for [tripId].
  /// Serves from cache when fresh; otherwise calls the backend.
  static Future<Map<String, dynamic>> fetchWeather(
    int tripId, {
    bool force = false,
  }) async {
    final now = DateTime.now();

    if (!force) {
      final cached = _cache[tripId];
      if (cached != null && now.difference(cached.fetchedAt) < ttl) {
        return cached.data;
      }
    }

    final token = await _getToken();
    if (token == null || token.isEmpty) {
      throw Exception('You are not logged in.');
    }

    final uri = Uri.parse('$baseUrl/api/trips/$tripId/weather');

    final http.Response response;
    try {
      response = await http
          .get(uri, headers: {
            'Authorization': 'Bearer $token',
            'Accept': 'application/json',
          })
          .timeout(requestTimeout);
    } on TimeoutException {
      debugPrint(
        'WEATHER FETCH ERROR: timeout after '
        '${requestTimeout.inSeconds}s for $uri',
      );
      throw Exception(
        'Weather request timed out. The server may be starting up — '
        'please try again.',
      );
    } catch (error) {
      debugPrint('WEATHER FETCH ERROR: network failure for $uri: $error');
      throw Exception(
        'Could not reach the weather service. Check your connection and '
        'try again.',
      );
    }

    if (response.statusCode == 401) {
      debugPrint('WEATHER FETCH ERROR: 401 unauthorized for $uri');
      throw Exception('Session expired. Please sign in again.');
    }

    if (response.statusCode == 404) {
      debugPrint('WEATHER FETCH ERROR: 404 trip not found for $uri');
      throw Exception('Trip not found.');
    }

    if (response.statusCode != 200) {
      debugPrint(
        'WEATHER FETCH ERROR: HTTP ${response.statusCode} for $uri '
        'body=${response.body.length > 500 ? response.body.substring(0, 500) : response.body}',
      );
      throw Exception(
        'Weather service is temporarily unavailable '
        '(HTTP ${response.statusCode}).',
      );
    }

    final decoded = _decode(response.body);

    _cache[tripId] = _CacheEntry(data: decoded, fetchedAt: now);

    return decoded;
  }

  // ----------------------------------------------------------
  // HELPERS
  // ----------------------------------------------------------

  static Map<String, dynamic> _decode(String body) {
    if (body.trim().isEmpty) {
      throw Exception('Empty response from weather service.');
    }
    final decoded = jsonDecode(body);
    if (decoded is Map<String, dynamic>) return decoded;
    return Map<String, dynamic>.from(decoded as Map);
  }
}

class _CacheEntry {
  final Map<String, dynamic> data;
  final DateTime fetchedAt;
  _CacheEntry({required this.data, required this.fetchedAt});
}
