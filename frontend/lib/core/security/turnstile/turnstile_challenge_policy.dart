/// Rules for the native (Android/iOS) Turnstile challenge WebView.
///
/// The WebView only ever shows the backend's own challenge page
/// (`/api/turnstile/challenge`), which loads Cloudflare's widget in an iframe.
/// That page's Content-Security-Policy limits scripts, frames and connections
/// to the page itself and `https://challenges.cloudflare.com`; this file
/// limits *top-level* navigation to the challenge page.
library;

const String turnstileChannelName = 'TriporaTurnstile';

/// Absolute URL of the challenge page for [action].
Uri buildChallengeUri({
  required String apiBaseUrl,
  required String challengePath,
  required String action,
  required bool dark,
}) {
  final base = Uri.parse(apiBaseUrl);
  return base.replace(
    path: challengePath,
    queryParameters: {'action': action, 'theme': dark ? 'dark' : 'light'},
    fragment: null,
  );
}

/// Main-frame navigation is allowed only to the challenge page itself (same
/// scheme, host, port and path). Links, redirects and pop-ups to anywhere
/// else are blocked. Plain HTTP is accepted only when the API itself is
/// configured with HTTP (local development).
bool isAllowedMainFrameNavigation(Uri challenge, String url) {
  final Uri target;
  try {
    target = Uri.parse(url);
  } catch (_) {
    return false;
  }
  return target.scheme == challenge.scheme &&
      (target.scheme == 'https' || target.scheme == 'http') &&
      target.host == challenge.host &&
      target.port == challenge.port &&
      target.path == challenge.path &&
      target.userInfo.isEmpty;
}
