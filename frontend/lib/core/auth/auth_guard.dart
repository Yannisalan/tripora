import 'package:flutter/material.dart';

import '../../services/trip_service.dart';
import 'token_store.dart';

/// Global auth guard.
///
/// Services like [TripService] have no [BuildContext] of their own, so
/// they can't call `Navigator.of(context)` when a request comes back
/// unauthorized. This class holds a [GlobalKey] attached to the app's
/// [MaterialApp] so ANY part of the app — widget or plain Dart class —
/// can force a logout and redirect to the login screen.
class AuthGuard {
  AuthGuard._();

  /// Attach this to `MaterialApp(navigatorKey: AuthGuard.navigatorKey, ...)`
  /// in main.dart. Once attached, `navigatorKey.currentState` gives access
  /// to the app's root Navigator from anywhere.
  static final GlobalKey<NavigatorState> navigatorKey =
  GlobalKey<NavigatorState>();

  static bool _isHandlingUnauthorized = false;
  static bool _isHandlingUnverified = false;

  /// Route of the "verify your email" screen.
  static const String verifyEmailRoute = '/verify-email';

  /// Sends the user to the verification screen when the backend answers
  /// `403 {"error": "email_unverified"}`. The session is kept: the user is
  /// signed in, only the features that need a verified address are locked.
  static Future<void> handleEmailUnverified() async {
    if (_isHandlingUnverified) {
      return;
    }
    _isHandlingUnverified = true;
    try {
      final navigator = navigatorKey.currentState;
      if (navigator == null) {
        return;
      }
      navigator.pushNamedAndRemoveUntil(verifyEmailRoute, (route) => false);
    } finally {
      Future.delayed(const Duration(seconds: 2), () {
        _isHandlingUnverified = false;
      });
    }
  }

  /// Clears the stored token and force-navigates to `/login`, wiping the
  /// existing navigation stack so the user can never go "back" into a
  /// screen that belongs to a dead session.
  ///
  /// Safe to call from multiple places at once (e.g. several requests
  /// in flight all returning 401 around the same time) — only the first
  /// call actually triggers the redirect; the rest are ignored.
  static Future<void> handleUnauthorized({
    String message = 'Your session has expired. Please log in again.',
  }) async {
    if (_isHandlingUnauthorized) {
      return;
    }

    _isHandlingUnauthorized = true;

    try {
      // Drop the whole session — access *and* refresh token — so a dead
      // session cannot be silently renewed later.
      await TokenStore.instance.clear();

      // The old session's trips must not survive the forced logout.
      await TripService.clearOfflineCache();

      final navigator = navigatorKey.currentState;

      if (navigator == null) {
        // App isn't mounted yet (e.g. this fired during startup) —
        // nothing to navigate away from.
        return;
      }

      navigator.pushNamedAndRemoveUntil('/login', (route) => false);

      final context = navigatorKey.currentContext;

      if (context != null && context.mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: Text(message),
              behavior: SnackBarBehavior.floating,
            ),
          );
      }
    } finally {
      // Reset shortly after, so a later genuine session expiry (a new
      // login followed by another expiry) can trigger this again.
      Future.delayed(const Duration(seconds: 2), () {
        _isHandlingUnauthorized = false;
      });
    }
  }
}