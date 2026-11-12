import 'dart:convert';

/// What the Turnstile widget reported.
enum TurnstileEventType { ready, token, expired, error }

/// A message from the Turnstile widget: from the web widget's callbacks, or
/// from the Android challenge page through the `TriporaTurnstile` JavaScript
/// channel. Anything that is not a well-formed message is ignored (returns
/// null), because the channel is reachable by any script on that page.
class TurnstileEvent {
  const TurnstileEvent._(this.type, {this.token, this.code});

  const TurnstileEvent.ready() : this._(TurnstileEventType.ready);
  const TurnstileEvent.expired() : this._(TurnstileEventType.expired);
  const TurnstileEvent.error([String? code])
      : this._(TurnstileEventType.error, code: code);

  /// Cloudflare documents a 2048-character maximum.
  static const int maxTokenLength = 2048;

  final TurnstileEventType type;
  final String? token;
  final String? code;

  static TurnstileEvent? tokenEvent(String? token) {
    if (!isPlausibleToken(token)) return null;
    return TurnstileEvent._(TurnstileEventType.token, token: token);
  }

  /// Tokens are opaque; only reject what can never be one. The backend
  /// verifies every token with Cloudflare anyway.
  static bool isPlausibleToken(String? token) =>
      token != null &&
      token.isNotEmpty &&
      token.length <= maxTokenLength &&
      !RegExp(r'\s').hasMatch(token);

  static TurnstileEvent? parse(String raw) {
    if (raw.length > maxTokenLength + 256) return null;
    final Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } catch (_) {
      return null;
    }
    if (decoded is! Map) return null;
    switch (decoded['type']) {
      case 'ready':
        return const TurnstileEvent.ready();
      case 'expired':
        return const TurnstileEvent.expired();
      case 'error':
        final code = decoded['code'];
        return TurnstileEvent.error(
          code is String && code.length <= 64 ? code : null,
        );
      case 'token':
        final token = decoded['token'];
        return token is String ? tokenEvent(token) : null;
      default:
        return null;
    }
  }
}
