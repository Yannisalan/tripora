import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../core/config/app_config.dart';

class AuthService {
  static const String baseUrl = AppConfig.apiBaseUrl;

  static const String _tokenKey = 'access_token';

  // ============================================================
  // REGISTER
  // ============================================================

  Future<Map<String, dynamic>> register({
    required String name,
    required String email,
    required String password,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/auth/register'),
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
      body: jsonEncode({
        'name': name.trim(),
        'email': email.trim(),
        'password': password,
      }),
    );

    final decoded = _decodeResponse(response);

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(decoded['message']?.toString() ?? 'Registration failed.');
    }

    if (decoded['success'] != true) {
      throw Exception(decoded['message']?.toString() ?? 'Registration failed.');
    }

    return decoded;
  }

  // ============================================================
  // LOGIN
  // ============================================================

  Future<Map<String, dynamic>> login({
    required String email,
    required String password,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/auth/login'),
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
      body: jsonEncode({'email': email.trim(), 'password': password}),
    );

    final decoded = _decodeResponse(response);

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(decoded['message']?.toString() ?? 'Login failed.');
    }

    if (decoded['success'] != true) {
      throw Exception(decoded['message']?.toString() ?? 'Login failed.');
    }

    // ----------------------------------------------------------
    // GET JWT
    // ----------------------------------------------------------

    final token = decoded['accessToken'];

    if (token == null || token.toString().trim().isEmpty) {
      throw Exception('Login succeeded but no access token was returned.');
    }

    // ----------------------------------------------------------
    // SAVE JWT
    // ----------------------------------------------------------

    await saveToken(token.toString());

    return decoded;
  }

  // ============================================================
  // SOCIAL LOGIN (GOOGLE / APPLE)
  // ============================================================

  Future<Map<String, dynamic>> socialLogin({
    required String provider,
    required String idToken,
    String? nonce,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/auth/social'),
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
      body: jsonEncode({
        'provider': provider,
        'idToken': idToken,
        if (nonce != null && nonce.trim().isNotEmpty) 'nonce': nonce.trim(),
      }),
    );

    final decoded = _decodeResponse(response);

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        decoded['message']?.toString() ?? 'Social sign-in failed.',
      );
    }

    if (decoded['success'] != true) {
      throw Exception(
        decoded['message']?.toString() ?? 'Social sign-in failed.',
      );
    }

    final token = decoded['accessToken'];

    if (token == null || token.toString().trim().isEmpty) {
      throw Exception('Sign-in succeeded but no access token was returned.');
    }

    await saveToken(token.toString());

    return decoded;
  }

  // ============================================================
  // SAVE TOKEN
  // ============================================================

  Future<void> saveToken(String token) async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.setString(_tokenKey, token);
  }

  // ============================================================
  // GET TOKEN
  // ============================================================

  Future<String?> getToken() async {
    final prefs = await SharedPreferences.getInstance();

    return prefs.getString(_tokenKey);
  }

  // ============================================================
  // CHECK LOGIN
  // ============================================================

  Future<bool> isLoggedIn() async {
    final token = await getToken();

    return token != null && token.trim().isNotEmpty;
  }

  // ============================================================
  // AUTHORIZATION HEADERS
  // ============================================================

  Future<Map<String, String>> getAuthHeaders() async {
    final token = await getToken();

    if (token == null || token.trim().isEmpty) {
      throw Exception('User is not authenticated.');
    }

    return {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      'Authorization': 'Bearer $token',
    };
  }

  // ============================================================
  // VERIFY EMAIL
  // ============================================================

  Future<Map<String, dynamic>> verifyEmail({required String token}) async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/auth/verify-email'),
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
      body: jsonEncode({'token': token.trim()}),
    );

    final decoded = _decodeResponse(response);

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        decoded['message']?.toString() ?? 'Email verification failed.',
      );
    }

    if (decoded['success'] != true) {
      throw Exception(
        decoded['message']?.toString() ?? 'Email verification failed.',
      );
    }

    return decoded;
  }

  // ============================================================
  // RESEND VERIFICATION
  // ============================================================

  Future<Map<String, dynamic>> resendVerification({
    required String email,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/auth/resend-verification'),
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
      body: jsonEncode({'email': email.trim()}),
    );

    final decoded = _decodeResponse(response);

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        decoded['message']?.toString() ?? 'Could not resend verification.',
      );
    }

    if (decoded['success'] != true) {
      throw Exception(
        decoded['message']?.toString() ?? 'Could not resend verification.',
      );
    }

    return decoded;
  }

  // ============================================================
  // GET CURRENT USER
  // ============================================================

  Future<Map<String, dynamic>> getCurrentUser() async {
    final headers = await getAuthHeaders();

    final response = await http.get(
      Uri.parse('$baseUrl/api/auth/me'),
      headers: headers,
    );

    final decoded = _decodeResponse(response);

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        decoded['message']?.toString() ?? 'Could not load your account.',
      );
    }

    if (decoded['success'] != true || decoded['user'] is! Map) {
      throw Exception('Could not load your account.');
    }

    return decoded;
  }

  // ============================================================
  // UPDATE CURRENT USER
  // ============================================================

  Future<Map<String, dynamic>> updateCurrentUser({
    String? name,
    String? email,
    String? password,
    String? currentPassword,
    String? preferredLanguage,
    String? preferredCurrency,
  }) async {
    final headers = await getAuthHeaders();

    final body = <String, dynamic>{};

    if (name != null) body['name'] = name.trim();
    if (email != null) body['email'] = email.trim();
    if (preferredLanguage != null && preferredLanguage.trim().isNotEmpty) {
      body['preferredLanguage'] = preferredLanguage.trim();
    }
    if (preferredCurrency != null && preferredCurrency.trim().isNotEmpty) {
      body['preferredCurrency'] = preferredCurrency.trim();
    }
    if (password != null && password.trim().isNotEmpty) {
      body['password'] = password.trim();
      if (currentPassword != null) {
        body['currentPassword'] = currentPassword;
      }
    }

    final response = await http.patch(
      Uri.parse('$baseUrl/api/auth/me'),
      headers: headers,
      body: jsonEncode(body),
    );

    final decoded = _decodeResponse(response);

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        decoded['message']?.toString() ?? 'Could not update your account.',
      );
    }

    if (decoded['success'] != true || decoded['user'] is! Map) {
      throw Exception('Could not update your account.');
    }

    return decoded;
  }

  // ============================================================
  // LOGOUT
  // ============================================================

  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.remove(_tokenKey);
  }

  // ============================================================
  // DELETE CURRENT USER (ACCOUNT DELETION)
  // ============================================================

  Future<void> deleteAccount() async {
    final headers = await getAuthHeaders();

    final response = await http.delete(
      Uri.parse('$baseUrl/api/auth/account'),
      headers: headers,
    );

    final decoded = _decodeResponse(response);

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        decoded['message']?.toString() ?? 'Could not delete your account.',
      );
    }

    if (decoded['success'] != true) {
      throw Exception('Could not delete your account.');
    }

    // The account is gone; drop the local session.
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
  }

  // ============================================================
  // DECODE RESPONSE
  // ============================================================

  Map<String, dynamic> _decodeResponse(http.Response response) {
    if (response.body.trim().isEmpty) {
      throw Exception('Tripora backend returned an empty response.');
    }

    try {
      final decoded = jsonDecode(response.body);

      if (decoded is Map<String, dynamic>) {
        return decoded;
      }

      return Map<String, dynamic>.from(decoded);
    } catch (error) {
      throw Exception('Invalid response from Tripora backend.');
    }
  }
}
