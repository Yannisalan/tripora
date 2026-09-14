import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/auth/auth_guard.dart';
import '../core/config/app_config.dart';
import '../models/trip_document_model.dart';

/// Client for the Trip Vault API.
///
/// Every method here requires a logged-in user: the JWT access token is
/// attached like every other authenticated service, and a 401 routes the
/// user back to login through ``AuthGuard``.
class DocumentService {
  static const String baseUrl = AppConfig.apiBaseUrl;

  // ============================================================
  // HELPERS
  // ============================================================

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

  /// Headers for binary/multipart endpoints — no Content-Type here so
  /// ``MultipartRequest`` can set its own boundary.
  Future<Map<String, String>> _authHeaders() async {
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

  Future<void> _checkUnauthorized(http.Response response) async {
    if (response.statusCode == 401) {
      await AuthGuard.handleUnauthorized();
      throw Exception('Your session has expired. Please log in again.');
    }
  }

  dynamic _apiError(
    http.BaseResponse response,
    dynamic decoded,
    String fallback,
  ) {
    if (decoded is Map) {
      return Exception(
        decoded['message']?.toString() ?? fallback,
      );
    }

    return Exception(fallback);
  }

  // ============================================================
  // LIST DOCUMENTS
  // GET /api/trips/<tripId>/documents
  // ============================================================

  Future<List<TripDocumentModel>> getDocuments(int tripId) async {
    final headers = await _authHeaders();

    final response = await http.get(
      Uri.parse('$baseUrl/api/trips/$tripId/documents'),
      headers: headers,
    );

    _debugLog('====================================');
    _debugLog('GET /api/trips/$tripId/documents');
    _debugLog('STATUS: ${response.statusCode}');
    _debugLog('====================================');

    final decoded = _decodeResponse(response);

    await _checkUnauthorized(response);

    if (response.statusCode == 404) {
      throw Exception('Trip not found.');
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw _apiError(response, decoded, 'Failed to fetch documents.');
    }

    if (decoded is! Map<String, dynamic> || decoded['success'] != true) {
      throw Exception('Failed to fetch documents.');
    }

    final documents = decoded['documents'];

    if (documents is! List) {
      throw Exception('Backend response does not contain a documents list.');
    }

    final parsed = documents.whereType<Map>().map((item) {
      return TripDocumentModel.fromJson(
        Map<String, dynamic>.from(item),
      );
    }).toList();

    return parsed;
  }

  // ============================================================
  // UPLOAD DOCUMENT
  // POST /api/trips/<tripId>/documents
  // ============================================================

  Future<TripDocumentModel> uploadDocument({
    required int tripId,
    required String name,
    required String documentType,
    required String fileName,
    required Uint8List bytes,
    required String mimeType,
  }) async {
    final headers = await _authHeaders();

    final request = http.MultipartRequest(
      'POST',
      Uri.parse('$baseUrl/api/trips/$tripId/documents'),
    );

    request.headers.addAll(headers);

    request.fields['name'] = name;
    request.fields['documentType'] = documentType;

    request.files.add(
      http.MultipartFile.fromBytes(
        'file',
        bytes,
        filename: fileName,
        contentType: MediaType.parse(mimeType),
      ),
    );

    final streamed = await request.send();
    final response = await http.Response.fromStream(streamed);

    _debugLog('====================================');
    _debugLog('POST /api/trips/$tripId/documents');
    _debugLog('STATUS: ${response.statusCode}');
    _debugLog('BODY:');
    _debugLog(response.body);
    _debugLog('====================================');

    final decoded = _decodeResponse(response);

    await _checkUnauthorized(response);

    if (response.statusCode == 404) {
      throw Exception('Trip not found.');
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw _apiError(response, decoded, 'Failed to upload document.');
    }

    if (decoded is! Map<String, dynamic> || decoded['success'] != true) {
      throw Exception('Failed to upload document.');
    }

    final document = decoded['document'];

    if (document is! Map) {
      throw Exception('Backend response does not contain a valid document.');
    }

    return TripDocumentModel.fromJson(
      Map<String, dynamic>.from(document),
    );
  }

  // ============================================================
  // DOWNLOAD DOCUMENT BYTES
  // GET /api/documents/<documentId>
  // ============================================================

  Future<Uint8List> getDocumentBytes(int documentId) async {
    final headers = await _authHeaders();

    final response = await http.get(
      Uri.parse('$baseUrl/api/documents/$documentId'),
      headers: headers,
    );

    _debugLog('====================================');
    _debugLog('GET /api/documents/$documentId');
    _debugLog('STATUS: ${response.statusCode}');
    _debugLog('BYTES: ${response.bodyBytes.length}');
    _debugLog('====================================');

    await _checkUnauthorized(response);

    if (response.statusCode == 404) {
      throw Exception('Document not found.');
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      final decoded = _decodeResponse(response);

      throw _apiError(response, decoded, 'Failed to access document.');
    }

    return response.bodyBytes;
  }

  // ============================================================
  // DELETE DOCUMENT
  // DELETE /api/documents/<documentId>
  // ============================================================

  Future<void> deleteDocument(int documentId) async {
    final headers = await _authHeaders();

    final response = await http.delete(
      Uri.parse('$baseUrl/api/documents/$documentId'),
      headers: headers,
    );

    _debugLog('====================================');
    _debugLog('DELETE /api/documents/$documentId');
    _debugLog('STATUS: ${response.statusCode}');
    _debugLog('====================================');

    final decoded = _decodeResponse(response);

    await _checkUnauthorized(response);

    if (response.statusCode == 404) {
      throw Exception('Document not found.');
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw _apiError(response, decoded, 'Failed to delete document.');
    }

    if (decoded is! Map<String, dynamic> || decoded['success'] != true) {
      throw Exception('Failed to delete document.');
    }
  }
}