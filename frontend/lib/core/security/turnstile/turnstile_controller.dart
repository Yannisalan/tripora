import 'dart:async';

import 'package:flutter/foundation.dart';

import 'turnstile_event.dart';

enum TurnstileStatus {
  /// Loading the backend config or the widget.
  loading,

  /// Bot protection is off on the backend: nothing to solve.
  disabled,

  /// Waiting for the person to complete the challenge.
  waiting,

  /// A token is available for the next request.
  verified,

  /// The token expired before use; the challenge must be solved again.
  expired,

  /// The widget reported an error.
  error,

  /// Verification cannot run here (config failed, or no WebView support).
  unavailable,
}

/// State shared between a protected form and its [TurnstileField].
///
/// Tokens are single use: call [reset] after every request that sent one,
/// whatever the outcome.
class TurnstileController extends ChangeNotifier {
  TurnstileController({required this.action});

  /// Must match the backend action (`register` or `forgot_password`).
  final String action;

  /// Turnstile tokens are valid for 300 seconds. When the widget cannot tell
  /// us (the Android page is closed after solving), expire a little earlier.
  static const Duration tokenLifetime = Duration(seconds: 280);

  TurnstileStatus _status = TurnstileStatus.loading;
  String? _token;
  int _generation = 0;
  Timer? _expiry;

  /// Reads the web honeypot input; set by the web widget only.
  String Function()? honeypotReader;

  TurnstileStatus get status => _status;
  String? get token => _token;

  /// Bumped by [reset]; the platform widget re-renders when it changes.
  int get generation => _generation;

  /// True when the form may be submitted.
  bool get readyToSubmit =>
      _status == TurnstileStatus.disabled ||
      (_status == TurnstileStatus.verified && _token != null);

  /// Honeypot value to send (`website`). Empty unless a bot filled the hidden
  /// web input. Native apps always send an empty value.
  String get honeypotValue {
    try {
      return honeypotReader?.call() ?? '';
    } catch (_) {
      return '';
    }
  }

  void markDisabled() => _set(TurnstileStatus.disabled, null);
  void markWaiting() => _set(TurnstileStatus.waiting, null);
  void markUnavailable() => _set(TurnstileStatus.unavailable, null);

  void handle(TurnstileEvent event) {
    switch (event.type) {
      case TurnstileEventType.ready:
        if (_status == TurnstileStatus.loading) {
          _set(TurnstileStatus.waiting, null);
        }
      case TurnstileEventType.token:
        _set(TurnstileStatus.verified, event.token);
      case TurnstileEventType.expired:
        _set(TurnstileStatus.expired, null);
      case TurnstileEventType.error:
        _set(TurnstileStatus.error, null);
    }
  }

  /// Discards the current token and asks the widget for a fresh challenge.
  void reset() {
    if (_status == TurnstileStatus.disabled ||
        _status == TurnstileStatus.unavailable) {
      return;
    }
    _generation++;
    _set(TurnstileStatus.waiting, null);
  }

  void _set(TurnstileStatus status, String? token) {
    _expiry?.cancel();
    _expiry = null;
    _status = status;
    _token = token;
    if (status == TurnstileStatus.verified) {
      _expiry = Timer(tokenLifetime, () => _set(TurnstileStatus.expired, null));
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _expiry?.cancel();
    super.dispose();
  }
}
