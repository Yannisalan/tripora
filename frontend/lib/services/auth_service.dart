import 'dart:convert';

import 'package:http/http.dart' as http;

import '../core/auth/token_store.dart';
import '../core/config/app_config.dart';
import 'trip_service.dart';

/// Outcome of a silent session refresh.
enum RefreshResult {
  /// A new access token was issued and stored.
  refreshed,

  /// The refresh token is gone, expired or revoked — the session is dead.
  invalid,

  /// The server or network could not be reached. The session is untouched
  /// and should be retried later.
  transient,
}

class AuthService {
  static const String baseUrl = AppConfig.apiBaseUrl;

  /// Refresh 60 seconds early so a token never expires in-flight.
  static const Duration _expirySkew = Duration(seconds: 60);

  /// Single in-flight refresh shared by every [AuthService] instance.
  ///
  /// Refreshing is single-use: the backend rotates the refresh token and
  /// revokes the old one, so two parallel refreshes would look like token
  /// replay and kill the whole session family. Keeping this static means a
  /// burst of 401s across different services still renews exactly once.
  static Future<RefreshResult>? _sharedRefresh;

  // ============================================================
  // REGISTER
  // ============================================================

  /// [turnstileToken] and [honeypot] come from the form's TurnstileController
  /// (see lib/core/security/turnstile). The token is single use.
  Future<Map<String, dynamic>> register({
    required String name,
    required String email,
    required String password,
    String? turnstileToken,
    String honeypot = '',
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
        ..._botProtectionFields(turnstileToken, honeypot),
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
    // SAVE SESSION (ACCESS + REFRESH)
    // ----------------------------------------------------------

    await _storeSession(decoded, token.toString());

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

    await _storeSession(decoded, token.toString());

    return decoded;
  }

  // ============================================================
  // GOOGLE LOGIN (DEDICATED ENDPOINT, TOKEN VERIFIED SERVER-SIDE)
  // ============================================================

  Future<Map<String, dynamic>> googleLogin({
    required String idToken,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/auth/google'),
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
      body: jsonEncode({'idToken': idToken}),
    );

    final decoded = _decodeResponse(response);

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        decoded['message']?.toString() ?? 'Google sign-in failed.',
      );
    }

    if (decoded['success'] != true) {
      throw Exception(
        decoded['message']?.toString() ?? 'Google sign-in failed.',
      );
    }

    final token = decoded['accessToken'];

    if (token == null || token.toString().trim().isEmpty) {
      throw Exception('Sign-in succeeded but no access token was returned.');
    }

    await _storeSession(decoded, token.toString());

    return decoded;
  }

  // ============================================================
  // FORGOT PASSWORD
  // ============================================================

  /// Requests a one-time password reset code for [email].
  ///
  /// The backend always responds with the same generic success message, so
  /// this API cannot be used to probe whether an account exists.
  Future<Map<String, dynamic>> forgotPassword({
    required String email,
    String? turnstileToken,
    String honeypot = '',
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/auth/forgot-password'),
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
      body: jsonEncode({
        'email': email.trim(),
        ..._botProtectionFields(turnstileToken, honeypot),
      }),
    );

    final decoded = _decodeResponse(response);

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        decoded['message']?.toString() ?? 'Could not send a reset code.',
      );
    }

    if (decoded['success'] != true) {
      throw Exception(
        decoded['message']?.toString() ?? 'Could not send a reset code.',
      );
    }

    return decoded;
  }

  /// Verifies the emailed one-time reset [code] for [email].
  ///
  /// Returns the one-time ``resetToken`` that is then passed to
  /// [resetPassword]. The token expires quickly and can only be used once.
  Future<String> verifyResetCode({
    required String email,
    required String code,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/auth/forgot-password/verify'),
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
      body: jsonEncode({
        'email': email.trim(),
        'code': code.trim(),
      }),
    );

    final decoded = _decodeResponse(response);

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        decoded['message']?.toString() ?? 'That code is invalid or expired.',
      );
    }

    if (decoded['success'] != true || decoded['resetToken'] == null) {
      throw Exception(
        decoded['message']?.toString() ?? 'That code is invalid or expired.',
      );
    }

    return decoded['resetToken'].toString();
  }

  /// Completes the reset using the one-time [resetToken] and a new
  /// [password] (at least 8 characters).
  Future<void> resetPassword({
    required String resetToken,
    required String password,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/auth/reset-password'),
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
      body: jsonEncode({'resetToken': resetToken, 'password': password}),
    );

    final decoded = _decodeResponse(response);

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        decoded['message']?.toString() ?? 'Could not reset your password.',
      );
    }

    if (decoded['success'] != true) {
      throw Exception(
        decoded['message']?.toString() ?? 'Could not reset your password.',
      );
    }
  }

  // ============================================================
  // SESSION STORAGE
  // ============================================================

  Future<void> _storeSession(
    Map<String, dynamic> decoded,
    String accessToken,
  ) async {
    final refresh = decoded['refreshToken']?.toString();

    await TokenStore.instance.saveSession(
      accessToken: accessToken,
      refreshToken: refresh,
    );
  }

  /// Persists an access token on its own. Prefer [_storeSession] so the
  /// refresh token is stored too.
  Future<void> saveToken(String token) async {
    await TokenStore.instance.saveSession(accessToken: token);
  }

  Future<String?> getToken() async {
    return TokenStore.instance.readAccessToken();
  }

  Future<String?> getRefreshToken() async {
    return TokenStore.instance.readRefreshToken();
  }

  /// True when a session is stored locally. This is only a local check —
  /// use [ensureFreshSession] / [refreshSession] to know it is still valid.
  Future<bool> isLoggedIn() async {
    return TokenStore.instance.hasSession();
  }

  /// Cheap, offline check used at startup to decide the initial UI state.
  Future<bool> hasStoredSession() async {
    return TokenStore.instance.hasSession();
  }

  // ============================================================
  // SESSION REFRESH
  // ============================================================

  /// Exchanges the stored refresh token for a fresh pair of tokens.
  ///
  /// Concurrent callers share a single in-flight request so a burst of
  /// expired 401s only refreshes once.
  Future<RefreshResult> refreshSession() {
    return _sharedRefresh ??= _performRefresh().whenComplete(() {
      _sharedRefresh = null;
    });
  }

  /// Called once at startup and never awaited by the UI: renews an expired
  /// access token in the background. A transient failure leaves the session
  /// intact so the user is not logged out by a flaky network.
  ///
  /// Returns true when the session is usable.
  Future<bool> ensureFreshSession() async {
    final access = await TokenStore.instance.readAccessToken();

    if (access != null && access.trim().isNotEmpty && !_isExpired(access)) {
      return true;
    }

    final refresh = await TokenStore.instance.readRefreshToken();

    if (refresh == null || refresh.trim().isEmpty) {
      return false;
    }

    final result = await refreshSession();

    return result == RefreshResult.refreshed;
  }

  Future<RefreshResult> _performRefresh() async {
    final refresh = await TokenStore.instance.readRefreshToken();

    if (refresh == null || refresh.trim().isEmpty) {
      return RefreshResult.invalid;
    }

    http.Response response;

    try {
      response = await http
          .post(
            Uri.parse('$baseUrl/api/auth/refresh'),
            headers: {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
            body: jsonEncode({'refreshToken': refresh}),
          )
          .timeout(const Duration(seconds: 15));
    } catch (_) {
      return RefreshResult.transient;
    }

    // 400/401 mean the stored refresh token is unusable (missing, expired,
    // revoked or already rotated) — the session is dead.
    if (response.statusCode == 400 || response.statusCode == 401) {
      await TokenStore.instance.clear();
      return RefreshResult.invalid;
    }

    // Any other non-2xx (e.g. 5xx) is treated as transient.
    if (response.statusCode < 200 || response.statusCode >= 300) {
      return RefreshResult.transient;
    }

    Map<String, dynamic> decoded;

    try {
      decoded = _decodeResponse(response);
    } catch (_) {
      return RefreshResult.transient;
    }

    final access = decoded['accessToken']?.toString();

    if (decoded['success'] != true ||
        access == null ||
        access.trim().isEmpty) {
      return RefreshResult.transient;
    }

    await TokenStore.instance.saveSession(
      accessToken: access,
      refreshToken: decoded['refreshToken']?.toString(),
    );

    return RefreshResult.refreshed;
  }

  // ============================================================
  // AUTHORIZATION HEADERS
  // ============================================================

  Future<Map<String, String>> getAuthHeaders() async {
    var token = await TokenStore.instance.readAccessToken();

    // If the access token is missing or about to expire, renew it first so
    // the request does not fail with a 401.
    if (token == null || token.trim().isEmpty || _isExpired(token)) {
      final refresh = await TokenStore.instance.readRefreshToken();

      if (refresh != null && refresh.trim().isNotEmpty) {
        final result = await refreshSession();

        if (result == RefreshResult.refreshed) {
          token = await TokenStore.instance.readAccessToken();
        }
      }
    }

    if (token == null || token.trim().isEmpty) {
      throw Exception('You are not logged in.');
    }

    return {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      'Authorization': 'Bearer $token',
    };
  }

  // ============================================================
  // JWT EXPIRY (LOCAL, UNVERIFIED)
  // ============================================================

  /// True when [token] is at or past `exp` (with a small safety margin).
  ///
  /// The signature is NOT verified here — this only decides whether a refresh
  /// is worth attempting. A token that cannot be parsed is treated as
  /// not-expired so the server stays the source of truth.
  bool _isExpired(String token) {
    final expiry = _decodeExpiry(token);

    if (expiry == null) {
      return false;
    }

    return DateTime.now().add(_expirySkew).isAfter(expiry);
  }

  DateTime? _decodeExpiry(String token) {
    final parts = token.split('.');

    if (parts.length != 3) {
      return null;
    }

    try {
      final normalized = base64Url.normalize(parts[1]);
      final payload = jsonDecode(utf8.decode(base64Url.decode(normalized)));

      if (payload is! Map) {
        return null;
      }

      final exp = payload['exp'];

      if (exp is! int) {
        return null;
      }

      return DateTime.fromMillisecondsSinceEpoch(exp * 1000);
    } catch (_) {
      return null;
    }
  }

  // ============================================================
  // GET CURRENT USER
  // ============================================================

  /// The account request currently in flight, shared by concurrent callers
  /// (the Profile tab and the sidebar card both ask at start-up). Cleared
  /// on completion, so later calls always fetch fresh data.
  static Future<Map<String, dynamic>>? _currentUserInFlight;

  Future<Map<String, dynamic>> getCurrentUser() {
    final pending = _currentUserInFlight;
    if (pending != null) return pending.then(_copyUserResponse);

    final request = _getCurrentUserUnshared();
    _currentUserInFlight = request;
    request.then<void>((_) {}, onError: (_) {}).whenComplete(() {
      if (identical(_currentUserInFlight, request)) {
        _currentUserInFlight = null;
      }
    });
    return request.then(_copyUserResponse);
  }

  /// Independent copy per caller (the nested user map included).
  static Map<String, dynamic> _copyUserResponse(Map<String, dynamic> r) {
    final copy = Map<String, dynamic>.of(r);
    final user = copy['user'];
    if (user is Map) copy['user'] = Map<String, dynamic>.from(user);
    return copy;
  }

  Future<Map<String, dynamic>> _getCurrentUserUnshared() async {
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
    }
    // The backend requires the current password to change the password OR
    // the login email (the account-recovery channel), so send it whenever
    // the user entered it.
    if (currentPassword != null && currentPassword.isNotEmpty) {
      body['currentPassword'] = currentPassword;
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
    final refresh = await TokenStore.instance.readRefreshToken();

    // Best-effort server-side revoke of this device's refresh token. Never
    // let a slow or offline network block sign-out.
    if (refresh != null && refresh.trim().isNotEmpty) {
      try {
        await http
            .post(
              Uri.parse('$baseUrl/api/auth/logout'),
              headers: {
                'Content-Type': 'application/json',
                'Accept': 'application/json',
              },
              body: jsonEncode({'refreshToken': refresh}),
            )
            .timeout(const Duration(seconds: 5));
      } catch (_) {
        // Ignored on purpose — the local session is cleared regardless.
      }
    }

    await TokenStore.instance.clear();

    // Never leave another user's offline trip data behind after signing out.
    await TripService.clearOfflineCache();
  }

  // ============================================================
  // DELETE CURRENT USER (ACCOUNT DELETION)
  // ============================================================

  /// Permanently deletes the account.
  ///
  /// The backend re-authenticates the user: pass [currentPassword] for
  /// email/password accounts, or a FRESH provider [idToken] (plus [nonce]
  /// for Apple) for social-only accounts. A valid session alone is refused.
  Future<void> deleteAccount({
    String? currentPassword,
    String? idToken,
    String? nonce,
  }) async {
    final headers = await getAuthHeaders();

    final response = await http.delete(
      Uri.parse('$baseUrl/api/auth/account'),
      headers: headers,
      body: jsonEncode({
        if (currentPassword != null && currentPassword.isNotEmpty)
          'currentPassword': currentPassword,
        if (idToken != null && idToken.isNotEmpty) 'idToken': idToken,
        if (nonce != null && nonce.isNotEmpty) 'nonce': nonce,
      }),
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
    await TokenStore.instance.clear();

    // The account (and its trips) no longer exist server-side, so the
    // locally cached copies must not survive either.
    await TripService.clearOfflineCache();
  }

  // ============================================================
  // EMAIL VERIFICATION
  // ============================================================

  /// Submits the 6-digit code from the verification email.
  ///
  /// Returns the updated user map. Throws [EmailVerificationException] with
  /// a machine-readable [EmailVerificationException.code] on failure.
  Future<Map<String, dynamic>> verifyEmail(String code) async {
    final headers = await getAuthHeaders();

    final response = await http.post(
      Uri.parse('$baseUrl/api/auth/verify-email'),
      headers: headers,
      body: jsonEncode({'code': code.trim()}),
    );

    final decoded = _decodeResponse(response);

    if (response.statusCode == 200 && decoded['success'] == true) {
      final user = decoded['user'];
      return user is Map<String, dynamic>
          ? user
          : <String, dynamic>{'emailVerified': true};
    }

    throw EmailVerificationException(
      code: decoded['error']?.toString() ??
          (response.statusCode == 401 ? 'unauthorized' : 'invalid_code'),
      message: decoded['message']?.toString() ?? 'Verification failed.',
    );
  }

  /// Asks the backend to email a new verification code.
  ///
  /// Returns the number of seconds to wait before another resend is allowed
  /// (0 when the request succeeded and no wait is known).
  Future<int> resendVerificationEmail() async {
    final headers = await getAuthHeaders();

    final response = await http.post(
      Uri.parse('$baseUrl/api/auth/verify-email/resend'),
      headers: headers,
    );

    final decoded = _decodeResponse(response);

    if (response.statusCode == 200) {
      return 0;
    }

    if (response.statusCode == 429) {
      final retry = int.tryParse(
            decoded['retryAfter']?.toString() ??
                response.headers['retry-after'] ??
                '',
          ) ??
          60;
      throw EmailVerificationException(
        code: 'resend_cooldown',
        message: decoded['message']?.toString() ?? 'Please wait.',
        retryAfterSeconds: retry,
      );
    }

    throw EmailVerificationException(
      code: decoded['error']?.toString() ?? 'resend_failed',
      message: decoded['message']?.toString() ??
          'Could not send a new code right now.',
    );
  }

  // ============================================================
  // BOT PROTECTION FIELDS
  // ============================================================

  /// `turnstileToken` (omitted when protection is off) and the `website`
  /// honeypot (empty for people). Checked by backend/services/bot_protection.py.
  static Map<String, String> _botProtectionFields(
    String? turnstileToken,
    String honeypot,
  ) {
    return {
      if (turnstileToken != null && turnstileToken.isNotEmpty)
        'turnstileToken': turnstileToken,
      'website': honeypot,
    };
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

/// Failure from the email-verification endpoints.
class EmailVerificationException implements Exception {
  /// Backend error code, e.g. `code_expired`, `resend_cooldown`,
  /// `invalid_code`, `unauthorized`.
  final String code;
  final String message;
  final int? retryAfterSeconds;

  const EmailVerificationException({
    required this.code,
    required this.message,
    this.retryAfterSeconds,
  });

  @override
  String toString() => message;
}
