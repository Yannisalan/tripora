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

/// Wraps the native Google / Apple sign-in plugins and produces the
/// ID / identity token that the backend verifies.
class SocialAuthService {
  SocialAuthService._();

  static final SocialAuthService instance = SocialAuthService._();

  GoogleSignIn get _google => GoogleSignIn.instance;

  bool _googleInitialized = false;

  Future<void> _ensureGoogleInitialized() async {
    if (_googleInitialized) {
      return;
    }

    await _google.initialize(clientId: _googleClientId());
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
    if (Platform.isAndroid) {
      return AppConfig.googleAndroidClientId.isNotEmpty
          ? AppConfig.googleAndroidClientId
          : null;
    }
    return null;
  }

  // ============================================================
  // GOOGLE SIGN-IN
  // ============================================================

  Future<SocialLoginResult> signInWithGoogle() async {
    await _ensureGoogleInitialized();

    final account = await _google.authenticate();

    final idToken = account.authentication.idToken;

    if (idToken == null || idToken.isEmpty) {
      throw Exception('Google sign-in returned no ID token.');
    }

    return SocialLoginResult(provider: 'google', idToken: idToken);
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
