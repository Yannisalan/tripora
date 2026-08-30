import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../core/config/app_config.dart';
import '../models/subscription_model.dart';

/// Talks to the premium/subscription endpoints.
///
/// Status is server-authoritative. Real store purchases are submitted via
/// [verifyReceipt] (needs the backend store credentials configured); while
/// those are not set up yet, [activateDev] lets you exercise the whole
/// premium flow locally.
class SubscriptionService {
  static const String baseUrl = AppConfig.apiBaseUrl;

  // ============================================================
  // AUTH TOKEN
  // ============================================================

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

  // ============================================================
  // SUBSCRIPTION STATUS
  // GET /api/premium/status
  // ============================================================

  Future<SubscriptionModel> getStatus() async {
    final response = await http.get(
      Uri.parse('$baseUrl/api/premium/status'),
      headers: await _headers(),
    );
    final decoded = _decode(response);

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        decoded['message']?.toString() ?? 'Could not load subscription.',
      );
    }

    final sub = decoded['subscription'];
    if (sub is! Map) {
      throw Exception('Backend returned an invalid subscription.');
    }
    return SubscriptionModel.fromJson(Map<String, dynamic>.from(sub));
  }

  // ============================================================
  // DEV/TEST ACTIVATION
  // POST /api/premium/activate
  // ============================================================

  Future<SubscriptionModel> activateDev({int days = 3}) async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/premium/activate'),
      headers: await _headers(),
      body: jsonEncode({'days': days}),
    );
    final decoded = _decode(response);

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        decoded['message']?.toString() ?? 'Could not activate premium.',
      );
    }

    final sub = decoded['subscription'];
    if (sub is! Map) {
      throw Exception('Backend returned an invalid subscription.');
    }
    return SubscriptionModel.fromJson(Map<String, dynamic>.from(sub));
  }

  // ============================================================
  // VERIFY A REAL STORE PURCHASE
  // POST /api/premium/verify-receipt
  // ============================================================

  Future<SubscriptionModel> verifyReceipt({
    required String store, // 'appstore' | 'googleplay'
    String? receiptData,
    String? productId,
    String? purchaseToken,
  }) async {
    final body = <String, dynamic>{'store': store};
    if (receiptData != null) body['receiptData'] = receiptData;
    if (productId != null) body['productId'] = productId;
    if (purchaseToken != null) body['purchaseToken'] = purchaseToken;

    final response = await http.post(
      Uri.parse('$baseUrl/api/premium/verify-receipt'),
      headers: await _headers(),
      body: jsonEncode(body),
    );
    final decoded = _decode(response);

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        decoded['message']?.toString() ?? 'Could not verify your purchase.',
      );
    }

    final sub = decoded['subscription'];
    if (sub is! Map) {
      throw Exception('Backend returned an invalid subscription.');
    }
    return SubscriptionModel.fromJson(Map<String, dynamic>.from(sub));
  }

  // ============================================================
  // PREMIUM: FLIGHT PRICE
  // GET /api/premium/flights/price
  // ============================================================

  Future<Map<String, dynamic>> flightPrice({
    required String from,
    required String to,
    required String date,
    int passengers = 1,
  }) async {
    final uri = Uri.parse('$baseUrl/api/premium/flights/price').replace(
      queryParameters: {
        'from': from,
        'to': to,
        'date': date,
        'passengers': '$passengers',
      },
    );
    final response = await http.get(uri, headers: await _headers());
    final decoded = _decode(response);

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        decoded['message']?.toString() ?? 'Could not check flight prices.',
      );
    }
    if (decoded['price'] is! Map) {
      throw Exception('Backend returned an invalid price.');
    }
    return Map<String, dynamic>.from(decoded['price'] as Map);
  }

  // ============================================================
  // PREMIUM: WEATHER FORECAST
  // GET /api/premium/weather/forecast
  // ============================================================

  Future<Map<String, dynamic>> weatherForecast({
    required String destination,
    required String startDate,
    required String endDate,
  }) async {
    final uri = Uri.parse('$baseUrl/api/premium/weather/forecast').replace(
      queryParameters: {
        'destination': destination,
        'startDate': startDate,
        'endDate': endDate,
      },
    );
    final response = await http.get(uri, headers: await _headers());
    final decoded = _decode(response);

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        decoded['message']?.toString() ?? 'Could not load the forecast.',
      );
    }
    if (decoded['forecast'] is! Map) {
      throw Exception('Backend returned an invalid forecast.');
    }
    return Map<String, dynamic>.from(decoded['forecast'] as Map);
  }
}
