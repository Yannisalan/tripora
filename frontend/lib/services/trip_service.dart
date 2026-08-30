import 'dart:convert';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../core/config/app_config.dart';
import '../models/trip_model.dart';

class TripService {
  static const String baseUrl = AppConfig.apiBaseUrl;

  void _debugLog(String message) {
    assert(() {
      debugPrint(message);
      return true;
    }());
  }

  // ============================================================
  // GET AUTH TOKEN
  // ============================================================

  Future<String?> _getToken() async {
    final prefs = await SharedPreferences.getInstance();

    return prefs.getString('access_token');
  }

  Future<void> _clearToken() async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.remove('access_token');
  }

  // ============================================================
  // AUTHORIZATION HEADERS
  // ============================================================

  Future<Map<String, String>> _headers() async {
    final token = await _getToken();

    if (token == null || token.isEmpty) {
      throw Exception('You are not logged in.');
    }

    return {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      'Authorization': 'Bearer $token',
    };
  }

  // ============================================================
  // DECODE RESPONSE
  // ============================================================

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
  // GENERATE TRIP
  // POST /api/trips/generate
  // ============================================================

  Future<Map<String, dynamic>> generateTrip(TripModel trip) async {
    final headers = await _headers();

    final response = await http.post(
      Uri.parse('$baseUrl/api/trips/generate'),
      headers: headers,
      body: jsonEncode(trip.toJson()),
    );

    final decoded = _decodeResponse(response);

    _debugLog('====================================');
    _debugLog('POST /api/trips/generate');
    _debugLog('STATUS: ${response.statusCode}');
    _debugLog('BODY:');
    _debugLog(response.body);
    _debugLog('====================================');

    // ----------------------------------------------------------
    // UNAUTHORIZED
    // ----------------------------------------------------------

    if (response.statusCode == 401) {
      await _clearToken();
      throw Exception('Your session has expired. Please log in again.');
    }

    // ----------------------------------------------------------
    // SERVER ERROR
    // ----------------------------------------------------------

    if (response.statusCode < 200 || response.statusCode >= 300) {
      if (decoded is Map) {
        throw Exception(
          decoded['message']?.toString() ?? 'Failed to generate trip.',
        );
      }

      throw Exception('Failed to generate trip.');
    }

    return decoded;
  }

  // ============================================================
  // UPDATE USER TRIP
  // PATCH /api/trips/<tripId>
  // ============================================================

  Future<TripModel> updateTrip({
    required int tripId,
    required TripModel trip,
  }) async {
    final headers = await _headers();

    final response = await http.patch(
      Uri.parse('$baseUrl/api/trips/$tripId'),
      headers: headers,
      body: jsonEncode(trip.toJson()),
    );

    final decoded = _decodeResponse(response);

    _debugLog('====================================');
    _debugLog('PATCH /api/trips/$tripId');
    _debugLog('STATUS: ${response.statusCode}');
    _debugLog('BODY:');
    _debugLog(response.body);
    _debugLog('====================================');

    if (response.statusCode == 401) {
      await _clearToken();
      throw Exception('Your session has expired. Please log in again.');
    }

    if (response.statusCode == 404) {
      throw Exception('Trip not found.');
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      if (decoded is Map) {
        throw Exception(
          decoded['message']?.toString() ?? 'Failed to update trip.',
        );
      }

      throw Exception('Failed to update trip.');
    }

    if (decoded is! Map<String, dynamic> || decoded['success'] != true) {
      throw Exception('Failed to update trip.');
    }

    final updatedTrip = decoded['trip'];

    if (updatedTrip is! Map) {
      throw Exception('Backend response does not contain a valid trip.');
    }

    return TripModel.fromJson(Map<String, dynamic>.from(updatedTrip));
  }

  // ============================================================
  // REGENERATE USER TRIP ITINERARY
  // POST /api/trips/<tripId>/regenerate
  // ============================================================

  Future<TripModel> regenerateItinerary(int tripId) async {
    final headers = await _headers();

    final response = await http.post(
      Uri.parse('$baseUrl/api/trips/$tripId/regenerate'),
      headers: headers,
    );

    final decoded = _decodeResponse(response);

    _debugLog('====================================');
    _debugLog('POST /api/trips/$tripId/regenerate');
    _debugLog('STATUS: ${response.statusCode}');
    _debugLog('BODY:');
    _debugLog(response.body);
    _debugLog('====================================');

    if (response.statusCode == 401) {
      await _clearToken();
      throw Exception('Your session has expired. Please log in again.');
    }

    if (response.statusCode == 404) {
      throw Exception('Trip not found.');
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      if (decoded is Map) {
        throw Exception(
          decoded['message']?.toString() ?? 'Failed to regenerate itinerary.',
        );
      }

      throw Exception('Failed to regenerate itinerary.');
    }

    if (decoded is! Map<String, dynamic> || decoded['success'] != true) {
      throw Exception('Failed to regenerate itinerary.');
    }

    final updatedTrip = decoded['trip'];

    if (updatedTrip is! Map) {
      throw Exception('Backend response does not contain a valid trip.');
    }

    return TripModel.fromJson(Map<String, dynamic>.from(updatedTrip));
  }

  // ============================================================
  // GET ALL USER TRIPS
  // GET /api/trips
  // ============================================================

  Future<List<TripModel>> getTrips() async {
    final headers = await _headers();

    final response = await http.get(
      Uri.parse('$baseUrl/api/trips'),
      headers: headers,
    );

    _debugLog('====================================');
    _debugLog('GET /api/trips');
    _debugLog('STATUS: ${response.statusCode}');
    _debugLog('BODY:');
    _debugLog(response.body);
    _debugLog('====================================');

    final decoded = _decodeResponse(response);

    // ----------------------------------------------------------
    // UNAUTHORIZED
    // ----------------------------------------------------------

    if (response.statusCode == 401) {
      await _clearToken();
      throw Exception('Your session has expired. Please log in again.');
    }

    // ----------------------------------------------------------
    // SERVER ERROR
    // ----------------------------------------------------------

    if (response.statusCode < 200 || response.statusCode >= 300) {
      if (decoded is Map) {
        throw Exception(
          decoded['message']?.toString() ?? 'Failed to fetch trips.',
        );
      }

      throw Exception('Failed to fetch trips.');
    }

    // ----------------------------------------------------------
    // VALIDATE RESPONSE
    // ----------------------------------------------------------

    if (decoded is! Map<String, dynamic>) {
      throw Exception('Invalid response from Tripora backend.');
    }

    if (decoded['success'] != true) {
      throw Exception(
        decoded['message']?.toString() ?? 'Failed to fetch trips.',
      );
    }

    final trips = decoded['trips'];

    if (trips is! List) {
      throw Exception('Backend response does not contain a valid trips list.');
    }

    // ----------------------------------------------------------
    // CONVERT TRIPS
    // ----------------------------------------------------------

    final parsedTrips = trips.map((trip) {
      if (trip is! Map) {
        throw Exception('Invalid trip data received from backend.');
      }

      final tripMap = Map<String, dynamic>.from(trip);

      _debugLog('------------------------------------');
      _debugLog('TRIP ID: ${tripMap['id']}');
      _debugLog('DESTINATION: ${tripMap['destination']}');
      _debugLog(
        'ITINERARY TYPE: '
        '${tripMap['itinerary']?.runtimeType}',
      );
      _debugLog(
        'ITINERARY LENGTH: '
        '${tripMap['itinerary'] is List ? (tripMap['itinerary'] as List).length : 0}',
      );
      _debugLog('ITINERARY: ${tripMap['itinerary']}');
      _debugLog('------------------------------------');

      return TripModel.fromJson(tripMap);
    }).toList();

    return parsedTrips;
  }

  // ============================================================
  // GET SINGLE USER TRIP
  // GET /api/trips/<tripId>
  // ============================================================

  Future<TripModel> getTrip(int tripId) async {
    final headers = await _headers();

    final response = await http.get(
      Uri.parse('$baseUrl/api/trips/$tripId'),
      headers: headers,
    );

    _debugLog('====================================');
    _debugLog('GET /api/trips/$tripId');
    _debugLog('STATUS: ${response.statusCode}');
    _debugLog('BODY:');
    _debugLog(response.body);
    _debugLog('====================================');

    final decoded = _decodeResponse(response);

    // ----------------------------------------------------------
    // UNAUTHORIZED
    // ----------------------------------------------------------

    if (response.statusCode == 401) {
      await _clearToken();
      throw Exception('Your session has expired. Please log in again.');
    }

    // ----------------------------------------------------------
    // NOT FOUND
    // ----------------------------------------------------------

    if (response.statusCode == 404) {
      throw Exception('Trip not found.');
    }

    // ----------------------------------------------------------
    // SERVER ERROR
    // ----------------------------------------------------------

    if (response.statusCode < 200 || response.statusCode >= 300) {
      if (decoded is Map) {
        throw Exception(
          decoded['message']?.toString() ?? 'Failed to fetch trip.',
        );
      }

      throw Exception('Failed to fetch trip.');
    }

    // ----------------------------------------------------------
    // VALIDATE RESPONSE
    // ----------------------------------------------------------

    if (decoded is! Map<String, dynamic>) {
      throw Exception('Invalid response from Tripora backend.');
    }

    if (decoded['success'] != true) {
      throw Exception(
        decoded['message']?.toString() ?? 'Failed to fetch trip.',
      );
    }

    // ----------------------------------------------------------
    // GET TRIP
    // ----------------------------------------------------------

    final trip = decoded['trip'];

    if (trip is! Map) {
      throw Exception('Backend response does not contain a valid trip.');
    }

    final tripMap = Map<String, dynamic>.from(trip);

    _debugLog('====================================');
    _debugLog('SINGLE TRIP');
    _debugLog('TRIP ID: ${tripMap['id']}');
    _debugLog('DESTINATION: ${tripMap['destination']}');
    _debugLog(
      'ITINERARY TYPE: '
      '${tripMap['itinerary']?.runtimeType}',
    );
    _debugLog(
      'ITINERARY LENGTH: '
      '${tripMap['itinerary'] is List ? (tripMap['itinerary'] as List).length : 0}',
    );
    _debugLog('====================================');

    return TripModel.fromJson(tripMap);
  }

  // ============================================================
  // DELETE USER TRIP
  // DELETE /api/trips/<tripId>
  // ============================================================

  Future<void> deleteTrip(int tripId) async {
    final headers = await _headers();

    final response = await http.delete(
      Uri.parse('$baseUrl/api/trips/$tripId'),
      headers: headers,
    );

    final decoded = _decodeResponse(response);

    _debugLog('====================================');
    _debugLog('DELETE /api/trips/$tripId');
    _debugLog('STATUS: ${response.statusCode}');
    _debugLog('BODY:');
    _debugLog(response.body);
    _debugLog('====================================');

    // ----------------------------------------------------------
    // UNAUTHORIZED
    // ----------------------------------------------------------

    if (response.statusCode == 401) {
      await _clearToken();
      throw Exception('Your session has expired. Please log in again.');
    }

    // ----------------------------------------------------------
    // NOT FOUND
    // ----------------------------------------------------------

    if (response.statusCode == 404) {
      throw Exception('Trip not found.');
    }

    // ----------------------------------------------------------
    // SERVER ERROR
    // ----------------------------------------------------------

    if (response.statusCode < 200 || response.statusCode >= 300) {
      if (decoded is Map) {
        throw Exception(
          decoded['message']?.toString() ?? 'Failed to delete trip.',
        );
      }

      throw Exception('Failed to delete trip.');
    }

    // ----------------------------------------------------------
    // VALIDATE RESPONSE
    // ----------------------------------------------------------

    if (decoded is! Map<String, dynamic>) {
      throw Exception('Invalid response from Tripora backend.');
    }

    if (decoded['success'] != true) {
      throw Exception(
        decoded['message']?.toString() ?? 'Failed to delete trip.',
      );
    }
  }
}
