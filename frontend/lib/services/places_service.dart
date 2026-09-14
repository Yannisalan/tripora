import 'dart:convert';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../core/auth/auth_guard.dart';
import '../core/config/app_config.dart';

class GeocodedPlace {
  final String name;
  final double latitude;
  final double longitude;

  const GeocodedPlace({
    required this.name,
    required this.latitude,
    required this.longitude,
  });
}

/// Talks to the `places` blueprint on the backend.
///
/// The backend resolves free-text place names through Nominatim, caches the
/// results, and proxies OSRM routing — so the app never talks to those
/// services directly.
class PlacesService {
  static const String baseUrl = AppConfig.apiBaseUrl;

  void _debugLog(String message) {
    assert(() {
      debugPrint(message);
      return true;
    }());
  }

  Future<String?> _getToken() async {
    final prefs = await SharedPreferences.getInstance();

    return prefs.getString('access_token');
  }

  Future<Map<String, String>> _headers() async {
    final token = await _getToken();

    if (token == null || token.isEmpty) {
      await AuthGuard.handleUnauthorized(
        message: 'Please log in to continue.',
      );

      throw Exception('You are not logged in.');
    }

    return {
      'Accept': 'application/json',
      'Authorization': 'Bearer $token',
    };
  }

  dynamic _decodeResponse(http.Response response) {
    if (response.body.isEmpty) {
      return null;
    }

    try {
      return jsonDecode(response.body);
    } catch (_) {
      return null;
    }
  }

  // ============================================================
  // GEOCODE
  // GET /api/places/geocode?query=...
  // ============================================================

  Future<GeocodedPlace?> geocode(String query) async {
    final headers = await _headers();

    final response = await http.get(
      Uri.parse('$baseUrl/api/places/geocode')
          .replace(queryParameters: {'query': query}),
      headers: headers,
    );

    final decoded = _decodeResponse(response);

    _debugLog('GEOCODE "$query" -> ${response.statusCode}');

    if (response.statusCode == 401) {
      await AuthGuard.handleUnauthorized();
      throw Exception('Your session has expired. Please log in again.');
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        decoded?['message']?.toString() ??
            'Could not resolve that location.',
      );
    }

    final coordinate = decoded?['coordinate'];

    if (decoded?['geocoded'] != true || coordinate is! Map) {
      return null;
    }

    final latitude = coordinate['latitude'];
    final longitude = coordinate['longitude'];

    if (latitude is! num || longitude is! num) {
      return null;
    }

    return GeocodedPlace(
      name: coordinate['name']?.toString() ?? query,
      latitude: latitude.toDouble(),
      longitude: longitude.toDouble(),
    );
  }

  // ============================================================
  // ROUTE
  // GET /api/places/route
  // ============================================================

  /// Best-effort driving route between two points.
  ///
  /// Returns a list of [latitude, longitude] pairs (empty when the upstream
  /// router is unavailable or finds nothing).
  Future<List<(double, double)>> getRoute({
    required double fromLat,
    required double fromLng,
    required double toLat,
    required double toLng,
  }) async {
    final headers = await _headers();

    final response = await http.get(
      Uri.parse('$baseUrl/api/places/route').replace(
        queryParameters: {
          'from_lat': '$fromLat',
          'from_lng': '$fromLng',
          'to_lat': '$toLat',
          'to_lng': '$toLng',
        },
      ),
      headers: headers,
    );

    final decoded = _decodeResponse(response);

    _debugLog('ROUTE -> ${response.statusCode} (routed: '
        '${decoded?['routed']})');

    if (response.statusCode == 401) {
      await AuthGuard.handleUnauthorized();
      throw Exception('Your session has expired. Please log in again.');
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      return [];
    }

    if (decoded?['routed'] != true ||
        decoded?['coordinates'] is! List) {
      return [];
    }

    final coordinates = decoded['coordinates'] as List;

    return coordinates
        .whereType<List>()
        .map(
          (point) => (
            (point[0] as num).toDouble(),
            (point[1] as num).toDouble(),
          ),
        )
        .toList();
  }
}