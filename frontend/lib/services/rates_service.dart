import 'dart:convert';

import 'package:http/http.dart' as http;

import '../core/config/app_config.dart';

/// Fetches the app-wide currency conversion table from the Tripora backend
/// (``GET /api/rates/base/USD``) and caches it in-memory with a 6-hour TTL.
///
/// The table is keyed by currency code and holds the number of local units
/// per 1 USD, so any from->to conversion is ``to / from``.
class RatesService {
  RatesService._();

  static const String baseUrl = AppConfig.apiBaseUrl;

  static Map<String, double>? _cache;
  static DateTime? _fetchedAt;

  static const Duration ttl = Duration(hours: 6);

  /// Returns the cached USD rate table, or fetches it if the cache is
  /// missing or older than [ttl]. Throws when the backend cannot be reached
  /// (callers decide how to degrade — e.g. keep showing source currency).
  static Future<Map<String, double>> fetchUsdRates({
    bool force = false,
  }) async {
    final now = DateTime.now();

    if (!force &&
        _cache != null &&
        _fetchedAt != null &&
        now.difference(_fetchedAt!) < ttl) {
      return _cache!;
    }

    final response = await http.get(
      Uri.parse('$baseUrl/api/rates/base/USD'),
      headers: const {
        'Accept': 'application/json',
      },
    );

    if (response.statusCode != 200) {
      throw Exception('Currency conversion is temporarily unavailable.');
    }

    final decoded = _decode(response.body);

    final rawRates = decoded['rates'];

    if (rawRates is! Map) {
      throw Exception('Invalid response from conversion service.');
    }

    final parsed = <String, double>{
      'USD': 1.0,
    };

    rawRates.forEach((key, value) {
      if (key is String && value is num && value > 0) {
        parsed[key] = value.toDouble();
      }
    });

    if (parsed.length < 2) {
      throw Exception('Invalid response from conversion service.');
    }

    _cache = parsed;
    _fetchedAt = now;

    return parsed;
  }

  static Map<String, dynamic> _decode(String body) {
    if (body.trim().isEmpty) {
      throw Exception('Empty response from conversion service.');
    }

    final decoded = jsonDecode(body);

    if (decoded is Map<String, dynamic>) {
      return decoded;
    }

    return Map<String, dynamic>.from(decoded as Map);
  }
}