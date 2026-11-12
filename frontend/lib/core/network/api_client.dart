import 'dart:convert';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:http/http.dart' as http;

import '../../services/auth_service.dart';
import '../auth/auth_guard.dart';
import '../config/app_config.dart';

/// The one HTTP client every authenticated backend call goes through.
///
/// It centralises three things that used to be copy-pasted (and subtly
/// wrong) in every service:
///
///  1. **Token attach** — every request carries
///     `Authorization: Bearer <access>`; an access token that is missing or
///     about to expire is renewed *before* the request is sent, so the
///     common "app was idle for 15 minutes" case never even reaches a 401.
///  2. **Single refresh on 401** — if the server still answers `401`, the
///     session is renewed once (shared, single-flight, see
///     [AuthService.refreshSession]) and the request is replayed **once**.
///  3. **Safe replay** — the replay only happens for idempotent methods
///     (GET / HEAD / PUT / DELETE / OPTIONS), so a retried POST or PATCH can
///     never create a duplicate trip, expense or booking.
///
/// When the session cannot be renewed the request is handed to
/// [AuthGuard] (which clears it and redirects to Login) and the original
/// `401` is returned so callers keep their existing error handling.
///
/// Network errors and timeouts are deliberately *not* caught here — they
/// propagate so services can keep distinguishing "offline" from "bad
/// response" (e.g. the trips offline cache).
class ApiClient {
  ApiClient._(this._client, [AuthService? auth])
      : _auth = auth ?? AuthService();

  /// Shared instance used by every service.
  static final ApiClient instance = ApiClient._(null);

  /// Builds a client backed by a supplied [client] and, optionally, an
  /// [auth]. Intended for tests.
  @visibleForTesting
  factory ApiClient.forTest({
    required http.Client client,
    AuthService? auth,
  }) =>
      ApiClient._(client, auth);

  static const String baseUrl = AppConfig.apiBaseUrl;

  /// Methods that are safe to replay after a mid-request token refresh.
  static const Set<String> _idempotentMethods = {
    'GET',
    'HEAD',
    'PUT',
    'DELETE',
    'OPTIONS',
  };

  final http.Client? _client;
  final AuthService _auth;

  Future<http.Response> get(Uri url) => _send('GET', url);

  Future<http.Response> post(Uri url, {Object? body}) =>
      _send('POST', url, body: body);

  Future<http.Response> put(Uri url, {Object? body}) =>
      _send('PUT', url, body: body);

  Future<http.Response> patch(Uri url, {Object? body}) =>
      _send('PATCH', url, body: body);

  Future<http.Response> delete(Uri url, {Object? body}) =>
      _send('DELETE', url, body: body);

  Future<http.Response> _send(
    String method,
    Uri url, {
    Object? body,
  }) async {
    // getAuthHeaders() renews an about-to-expire access token first, so the
    // vast majority of calls never see a 401 at all.
    var headers = await _auth.getAuthHeaders();

    final response = await _dispatch(method, url, headers, body);

    if (response.statusCode == 403 && _isEmailUnverified(response)) {
      // Signed in but the address is not verified yet: route to the
      // verification screen. The server decided this; the client never
      // stores or trusts its own "verified" flag.
      await AuthGuard.handleEmailUnverified();
      return response;
    }

    if (response.statusCode != 401) {
      return response;
    }

    // The server rejected the token anyway (revoked, clock skew, race). Try
    // to renew exactly once.
    final renewedResult = await _auth.refreshSession();

    if (renewedResult == RefreshResult.refreshed &&
        _idempotentMethods.contains(method)) {
      headers = await _auth.getAuthHeaders();
      return _dispatch(method, url, headers, body);
    }

    // Only a dead session forces a logout. A non-idempotent request that was
    // refreshed but not replayed returns its 401 so the caller can surface a
    // retryable error without dropping the session.
    if (renewedResult == RefreshResult.invalid) {
      await AuthGuard.handleUnauthorized();
    }

    return response;
  }

  static bool _isEmailUnverified(http.Response response) {
    try {
      final decoded = jsonDecode(response.body);
      return decoded is Map && decoded['error'] == 'email_unverified';
    } catch (_) {
      return false;
    }
  }

  Future<http.Response> _dispatch(
    String method,
    Uri url,
    Map<String, String> headers,
    Object? body,
  ) {
    final client = _client;
    switch (method) {
      case 'GET':
        return client == null
            ? http.get(url, headers: headers)
            : client.get(url, headers: headers);
      case 'POST':
        return client == null
            ? http.post(url, headers: headers, body: body)
            : client.post(url, headers: headers, body: body);
      case 'PUT':
        return client == null
            ? http.put(url, headers: headers, body: body)
            : client.put(url, headers: headers, body: body);
      case 'PATCH':
        return client == null
            ? http.patch(url, headers: headers, body: body)
            : client.patch(url, headers: headers, body: body);
      case 'DELETE':
        return client == null
            ? http.delete(url, headers: headers, body: body)
            : client.delete(url, headers: headers, body: body);
      default:
        throw ArgumentError('Unsupported method: $method');
    }
  }
}
