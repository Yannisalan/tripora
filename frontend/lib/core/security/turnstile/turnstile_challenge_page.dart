import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

import '../../l10n/app_localizations.dart';
import 'turnstile_challenge_policy.dart';
import 'turnstile_event.dart';

/// Full-screen WebView that shows the backend's Turnstile challenge page and
/// returns the token (or null when closed) through `Navigator.pop`.
///
/// Turnstile has no native Flutter/Android SDK; Cloudflare supports it in
/// WebViews. The page posts `{"type":"token","token":...}` to the
/// [turnstileChannelName] JavaScript channel. The token only proves a solved
/// challenge to the backend, which verifies it with Cloudflare; a forged
/// message gains nothing.
class TurnstileChallengePage extends StatefulWidget {
  const TurnstileChallengePage({super.key, required this.challengeUri});

  final Uri challengeUri;

  @override
  State<TurnstileChallengePage> createState() => _TurnstileChallengePageState();
}

class _TurnstileChallengePageState extends State<TurnstileChallengePage> {
  late final WebViewController _web;
  bool _loading = true;
  bool _failed = false;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    _web = WebViewController()
      // Turnstile needs JavaScript; DOM storage is on by default in
      // webview_flutter_android.
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..addJavaScriptChannel(
        turnstileChannelName,
        onMessageReceived: (message) => _onMessage(message.message),
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (request) {
            // Subframes (Cloudflare's iframe) are governed by the page CSP.
            if (!request.isMainFrame) return NavigationDecision.navigate;
            return isAllowedMainFrameNavigation(widget.challengeUri, request.url)
                ? NavigationDecision.navigate
                : NavigationDecision.prevent;
          },
          onPageFinished: (_) {
            if (mounted) setState(() => _loading = false);
          },
          onWebResourceError: (error) {
            if (error.isForMainFrame ?? true) {
              if (mounted) setState(() => _failed = true);
            }
          },
        ),
      );

    final platform = _web.platform;
    if (platform is AndroidWebViewController) {
      // The page needs nothing from the device.
      platform.setAllowFileAccess(false);
      platform.setAllowContentAccess(false);
    }

    _web.loadRequest(widget.challengeUri);
  }

  void _onMessage(String raw) {
    final event = TurnstileEvent.parse(raw);
    if (event == null || !mounted || _done) return;
    switch (event.type) {
      case TurnstileEventType.token:
        _done = true;
        Navigator.of(context).pop(event.token);
      case TurnstileEventType.error:
        setState(() => _failed = true);
      case TurnstileEventType.ready:
      case TurnstileEventType.expired:
        break;
    }
  }

  void _retry() {
    setState(() {
      _failed = false;
      _loading = true;
    });
    _web.loadRequest(widget.challengeUri);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('turnstile.challengeTitle'))),
      body: SafeArea(
        child: _failed
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        context.tr('turnstile.loadError'),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      FilledButton(
                        onPressed: _retry,
                        child: Text(context.tr('turnstile.retry')),
                      ),
                    ],
                  ),
                ),
              )
            : Stack(
                children: [
                  WebViewWidget(controller: _web),
                  if (_loading)
                    const Center(child: CircularProgressIndicator()),
                ],
              ),
      ),
    );
  }
}
