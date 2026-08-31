import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../core/config/app_config.dart';

/// Client for the token-gated Tripora admin / analytics API.
///
/// The admin endpoints live under `/api/admin/*` and are protected by a single
/// shared admin token (``ADMIN_API_TOKEN``), which is distinct from a normal
/// user JWT. The token is stored locally so the admin dashboard can re-load.
class AdminService {
  static const String baseUrl = AppConfig.apiBaseUrl;

  static const String _adminTokenKey = 'admin_token';

  // ============================================================
  // TOKEN STORAGE
  // ============================================================

  Future<String?> getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_adminTokenKey);
  }

  Future<void> saveToken(String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_adminTokenKey, token.trim());
  }

  Future<void> clearToken() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_adminTokenKey);
  }

  // ============================================================
  // LOGIN STATUS
  // ============================================================

  /// Returns true when the supplied token is valid for the admin API.
  Future<bool> checkToken({required String token}) async {
    final response = await http.get(
      Uri.parse('$baseUrl/api/admin/login-status'),
      headers: _headers(token),
    );

    if (response.statusCode != 200) {
      return false;
    }

    try {
      final decoded = jsonDecode(response.body);
      return decoded['authenticated'] == true;
    } catch (_) {
      return false;
    }
  }

  // ============================================================
  // STATS
  // ============================================================

  Future<Map<String, dynamic>> fetchStats() async {
    final response = await http.get(
      Uri.parse('$baseUrl/api/admin/stats'),
      headers: await _adminHeaders(),
    );

    return _decode(response, context: 'analytics');
  }

  // ============================================================
  // USERS
  // ============================================================

  Future<Map<String, dynamic>> fetchUsers({int limit = 100, int offset = 0}) async {
    final uri = Uri.parse('$baseUrl/api/admin/users').replace(
      queryParameters: {'limit': '$limit', 'offset': '$offset'},
    );
    final response = await http.get(uri, headers: await _adminHeaders());
    return _decode(response, context: 'users');
  }

  // ============================================================
  // TRIPS
  // ============================================================

  Future<Map<String, dynamic>> fetchTrips({int limit = 100, int offset = 0}) async {
    final uri = Uri.parse('$baseUrl/api/admin/trips').replace(
      queryParameters: {'limit': '$limit', 'offset': '$offset'},
    );
    final response = await http.get(uri, headers: await _adminHeaders());
    return _decode(response, context: 'trips');
  }

  // ============================================================
  // ACTIVITY LOG
  // ============================================================

  Future<Map<String, dynamic>> fetchLogs({
    String? type,
    int limit = 200,
    int offset = 0,
  }) async {
    final params = <String, String>{
      'limit': '$limit',
      'offset': '$offset',
    };
    if (type != null) params['type'] = type;
    final uri = Uri.parse('$baseUrl/api/admin/logs').replace(
      queryParameters: params,
    );
    final response = await http.get(uri, headers: await _adminHeaders());
    return _decode(response, context: 'activity log');
  }

  // ============================================================
  // HTTP HELPERS
  // ============================================================

  Map<String, String> _headers(String token) {
    return {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      'Authorization': 'Bearer $token',
    };
  }

  Future<Map<String, String>> _adminHeaders() async {
    final token = await getToken();
    if (token == null || token.trim().isEmpty) {
      throw Exception('Admin token is not set.');
    }
    return _headers(token);
  }

  Map<String, dynamic> _decode(http.Response response, {required String context}) {
    if (response.body.trim().isEmpty) {
      throw Exception('Tripora backend returned an empty response.');
    }

    Map<String, dynamic> decoded;
    try {
      final raw = jsonDecode(response.body);
      decoded = raw is Map<String, dynamic>
          ? raw
          : Map<String, dynamic>.from(raw as Map);
    } catch (_) {
      throw Exception('Invalid response from Tripora backend.');
    }

    if (response.statusCode == 401) {
      throw AdminAuthException('Your admin session is invalid.');
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        decoded['message']?.toString() ?? 'Failed to load $context.',
      );
    }

    if (decoded['success'] != true) {
      throw Exception(decoded['message']?.toString() ?? 'Failed to load $context.');
    }

    return decoded;
  }
}

/// Raised when the admin token is rejected (401) by the backend.
class AdminAuthException implements Exception {
  const AdminAuthException(this.message);

  final String message;

  @override
  String toString() => message;
}
