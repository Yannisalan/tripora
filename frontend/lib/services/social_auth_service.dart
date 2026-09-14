import 'dart:convert';
import 'dart:io' show Platform;
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

import '../core/config/app_config.dart';

/// Result of a successful native social sign-in (before backend exchange).
class SocialLoginResult {
  final String provider;
  final String idToken;
  final String? nonce;

  const SocialLoginResult({
    required this.provider,
    required this.idToken,
    this.nonce,
  });
}

/// Thrown when the user dismisses the native sign-in sheet (or the OS
/// interrupts it), so callers can stay quiet instead of showing an error.
class SocialSignInCancelled implements Exception {
  const SocialSignInCancelled();
}

/// Wraps the native Google / Apple sign-in plugins and produces the
/// ID / identity token that the backend verifies.
class SocialAuthService {
  SocialAuthService._();

  static final SocialAuthService instance = SocialAuthService._();

  GoogleSignIn get _google => GoogleSignIn.instance;

  bool _googleInitialized = false;

  /// Configures the native Google sign-in plugin.
  ///
  /// `initialize` must be called exactly once per process, so this is guarded
  /// by [_googleInitialized] and never re-runs (not even after [signOutGoogle],
  /// which does not invalidate the plugin configuration).
  ///
  /// Platform client identifiers (see app_config.dart / dart-defines):
  ///  * Android  -> `serverClientId` MUST be the Google Cloud *Web* OAuth
  ///    client ID. The Credential Manager flow used by google_sign_in >= 7
  ///    ignores `clientId` on Android and only mints an ID token for an
  ///    audience it knows about: either this value or the
  ///    `default_web_client_id` from google-services.json.
  ///  * iOS      -> `clientId` is the iOS OAuth client ID.
  ///  * Web      -> `clientId` is the Web OAuth client ID.
  Future<void> _ensureGoogleInitialized() async {
    if (_googleInitialized) {
      return;
    }

    if (Platform.isAndroid) {
      final serverClientId = AppConfig.googleWebClientId.isNotEmpty
          ? AppConfig.googleWebClientId
          : null;
      await _google.initialize(serverClientId: serverClientId);
    } else {
      await _google.initialize(clientId: _googleClientId());
    }
    _googleInitialized = true;
  }

  String? _googleClientId() {
    if (kIsWeb) {
      return AppConfig.googleWebClientId.isNotEmpty
          ? AppConfig.googleWebClientId
          : null;
    }
    if (Platform.isIOS) {
      return AppConfig.googleIosClientId.isNotEmpty
          ? AppConfig.googleIosClientId
          : null;
    }
    return null;
  }

  // ============================================================
  // GOOGLE SIGN-IN
  // ============================================================

  /// Runs the native Google sign-in flow.
  ///
  /// Throws [SocialSignInCancelled] if the user dismisses or the OS cancels
  /// the sheet. Re-throws [GoogleSignInException] (e.g. a client configuration
  /// problem) and any plugin `PlatformException` for the caller to surface.
  Future<SocialLoginResult> signInWithGoogle() async {
    await _ensureGoogleInitialized();

    final GoogleSignInAccount account;
    try {
      account = await _google.authenticate();
    } on GoogleSignInException catch (error) {
      if (error.code == GoogleSignInExceptionCode.canceled ||
          error.code == GoogleSignInExceptionCode.interrupted ||
          error.code == GoogleSignInExceptionCode.uiUnavailable) {
        throw const SocialSignInCancelled();
      }
      rethrow;
    }

    final idToken = account.authentication.idToken;

    if (idToken == null || idToken.isEmpty) {
      throw Exception('Google sign-in returned no ID token.');
    }

    return SocialLoginResult(provider: 'google', idToken: idToken);
  }

  /// Ends the native Google session so the account picker appears on the next
  /// sign-in. Best-effort: a stale native session is harmless to Tripora log
  /// out, so errors are swallowed here.
  Future<void> signOutGoogle() async {
    try {
      await _google.signOut();
    } catch (_) {
      // Best-effort only.
    }
  }

  // ============================================================
  // SIGN IN WITH APPLE
  // ============================================================

  Future<SocialLoginResult> signInWithApple() async {
    final rawNonce = _generateNonce();
    final nonceHash = _sha256(rawNonce);

    final requiresWebAuth = kIsWeb || Platform.isAndroid;

    final credential = await SignInWithApple.getAppleIDCredential(
      scopes: [
        AppleIDAuthorizationScopes.email,
        AppleIDAuthorizationScopes.fullName,
      ],
      nonce: nonceHash,
      webAuthenticationOptions: requiresWebAuth
          ? WebAuthenticationOptions(
              clientId: AppConfig.appleClientId,
              redirectUri: Uri.parse(AppConfig.appleRedirectUri),
            )
          : null,
    );

    final identityToken = credential.identityToken;

    if (identityToken == null || identityToken.isEmpty) {
      throw Exception('Apple sign-in returned no identity token.');
    }

    return SocialLoginResult(
      provider: 'apple',
      idToken: identityToken,
      nonce: rawNonce,
    );
  }

  // ============================================================
  // HELPERS
  // ============================================================

  String _generateNonce([int length = 32]) {
    const charset =
        '0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._';
    final random = Random.secure();
    return List.generate(
      length,
      (_) => charset[random.nextInt(charset.length)],
    ).join();
  }

  String _sha256(String input) {
    final bytes = utf8.encode(input);
    return sha256.convert(bytes).toString();
  }
}
