import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../core/config/app_config.dart';

/// Talks to the premium-only live travel-search endpoints.
///
/// These endpoints are gated server-side by [require_premium]; a free user
/// gets a 403 (```PREMIUM_REQUIRED```) which the UI surfaces as the paywall.
/// All results are display-only search data -- no booking or checkout.
class DuffelService {
  static const String baseUrl = AppConfig.apiBaseUrl;

  Future<String?> _getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('access_token');
  }

  Future<Map<String, String>> _headers() async {
    final token = await _getToken();
    if (token == null || token.trim().isEmpty) {
      throw Exception('You are not logged in.');
    }
    return {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      'Authorization': 'Bearer $token',
    };
  }

  Map<String, dynamic> _decode(http.Response response) {
    if (response.body.trim().isEmpty) {
      throw Exception('Tripora backend returned an empty response.');
    }
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
      return Map<String, dynamic>.from(decoded as Map);
    } catch (_) {
      throw Exception('Invalid response from Tripora backend.');
    }
  }

  Future<Map<String, dynamic>> _post(
    String path,
    Map<String, dynamic> payload,
  ) async {
    final response = await http.post(
      Uri.parse('$baseUrl$path'),
      headers: await _headers(),
      body: jsonEncode(payload),
    );
    final decoded = _decode(response);

    if (response.statusCode < 200 || response.statusCode >= 300) {
      final code = (decoded['code'] ?? '').toString();
      final message =
          decoded['message']?.toString() ?? 'The travel search failed.';
      throw PremiumRequiredException(
        message,
        premiumRequired: code == 'PREMIUM_REQUIRED',
      );
    }

    if (decoded['results'] is! Map) {
      throw Exception('Backend returned an invalid travel search result.');
    }
    return Map<String, dynamic>.from(decoded['results'] as Map);
  }

  // ============================================================
  // FLIGHTS
  // POST /api/travel/flights/search
  // ============================================================

  Future<Map<String, dynamic>> searchFlights({
    required String origin,
    required String destination,
    required String departDate,
    String? returnDate,
    int passengers = 1,
    String cabinClass = 'economy',
  }) async {
    return _post('/api/travel/flights/search', {
      'origin': origin,
      'destination': destination,
      'departDate': departDate,
      if (returnDate != null && returnDate.isNotEmpty) 'returnDate': returnDate,
      'passengers': passengers,
      'cabinClass': cabinClass,
    });
  }

  // ============================================================
  // FLIGHT PRICES
  // POST /api/travel/flights/prices
  //
  // Open to any logged-in user (no premium gate).
  // ============================================================

  Future<Map<String, dynamic>> searchFlightPrices({
    required String origin,
    required String destination,
    required String departDate,
    String currency = 'USD',
  }) async {
    return _post('/api/travel/flights/prices', {
      'origin': origin,
      'destination': destination,
      'departDate': departDate,
      'currency': currency,
    });
  }

  // ============================================================
  // STAYS
  // POST /api/travel/stays/search
  // ============================================================

  Future<Map<String, dynamic>> searchStays({
    required String location,
    required String checkIn,
    required String checkOut,
    int guests = 2,
    int rooms = 1,
  }) async {
    return _post('/api/travel/stays/search', {
      'location': location,
      'checkIn': checkIn,
      'checkOut': checkOut,
      'guests': guests,
      'rooms': rooms,
    });
  }

  // ============================================================
  // CARS
  // POST /api/travel/cars/search
  // ============================================================

  Future<Map<String, dynamic>> searchCars({
    required String pickup,
    required String dropoff,
    required String pickupDateTime,
    required String dropoffDateTime,
    int driverAge = 30,
  }) async {
    return _post('/api/travel/cars/search', {
      'pickup': pickup,
      'dropoff': dropoff,
      'pickupDateTime': pickupDateTime,
      'dropoffDateTime': dropoffDateTime,
      'driverAge': driverAge,
    });
  }
}

/// Thrown when the backend reports a non-2xx response.
///
/// [premiumRequired] is true when the backend returned the `PREMIUM_REQUIRED`
/// code, which the UI uses to route the user to the paywall.
class PremiumRequiredException implements Exception {
  final String message;
  final bool premiumRequired;

  PremiumRequiredException(this.message, {this.premiumRequired = false});

  @override
  String toString() => message;
}
