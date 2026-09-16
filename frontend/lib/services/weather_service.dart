import 'dart:convert';

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

    final response = await http.get(
      Uri.parse('$baseUrl/api/trips/$tripId/weather'),
      headers: {
        'Authorization': 'Bearer $token',
        'Accept': 'application/json',
      },
    );

    if (response.statusCode == 401) {
      throw Exception('Session expired. Please sign in again.');
    }

    if (response.statusCode == 404) {
      throw Exception('Trip not found.');
    }

    if (response.statusCode != 200) {
      throw Exception('Weather service is temporarily unavailable.');
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
