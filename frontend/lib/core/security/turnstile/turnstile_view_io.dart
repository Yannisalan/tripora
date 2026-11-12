import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../config/app_config.dart';
import '../../l10n/app_localizations.dart';
import 'turnstile_challenge_page.dart';
import 'turnstile_challenge_policy.dart';
import 'turnstile_config.dart';
import 'turnstile_controller.dart';
import 'turnstile_event.dart';

/// Opens the challenge and returns the token, or null if none was produced.
typedef TurnstileChallengeLauncher = Future<String?> Function(
  BuildContext context,
  Uri challengeUri,
);

/// Test hooks for the native view (WebViews do not run in `flutter test`).
class TurnstileNativeOverrides {
  TurnstileNativeOverrides._();

  static TurnstileChallengeLauncher? launcher;
  static bool? supported;

  static void reset() {
    launcher = null;
    supported = null;
  }
}

bool get _platformSupported =>
    TurnstileNativeOverrides.supported ??
    (defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.macOS);

Future<String?> _openChallengePage(BuildContext context, Uri uri) {
  return Navigator.of(context).push<String>(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => TurnstileChallengePage(challengeUri: uri),
    ),
  );
}

/// Native apps (Android) have no HTML form, so there is no honeypot here:
/// the `website` field is always sent empty and Turnstile plus the backend's
/// checks and rate limits do the work.
Widget buildTurnstileView({
  required TurnstileController controller,
  required TurnstileConfig config,
}) {
  return _NativeTurnstileView(controller: controller, config: config);
}

class _NativeTurnstileView extends StatefulWidget {
  const _NativeTurnstileView({required this.controller, required this.config});

  final TurnstileController controller;
  final TurnstileConfig config;

  @override
  State<_NativeTurnstileView> createState() => _NativeTurnstileViewState();
}

class _NativeTurnstileViewState extends State<_NativeTurnstileView> {
  bool _opening = false;

  @override
  void initState() {
    super.initState();
    widget.controller.honeypotReader = null;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_platformSupported) {
        widget.controller.markWaiting();
      } else {
        widget.controller.markUnavailable();
      }
    });
  }

  Future<void> _verify() async {
    if (_opening) return;
    setState(() => _opening = true);
    final uri = buildChallengeUri(
      apiBaseUrl: AppConfig.apiBaseUrl,
      challengePath: widget.config.challengePath,
      action: widget.controller.action,
      dark: Theme.of(context).brightness == Brightness.dark,
    );
    final launcher = TurnstileNativeOverrides.launcher ?? _openChallengePage;
    String? token;
    try {
      token = await launcher(context, uri);
    } catch (_) {
      token = null;
    }
    if (!mounted) return;
    setState(() => _opening = false);
    final event = TurnstileEvent.tokenEvent(token);
    if (event != null) widget.controller.handle(event);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final status = widget.controller.status;
        if (status == TurnstileStatus.unavailable) {
          return Text(
            context.tr('turnstile.unsupported'),
            key: const Key('turnstile-unsupported'),
            style: TextStyle(color: scheme.error),
          );
        }
        final verified = status == TurnstileStatus.verified;
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: scheme.outlineVariant),
          ),
          child: Row(
            children: [
              Icon(
                verified ? Icons.verified_user : Icons.shield_outlined,
                color: verified ? Colors.green : scheme.primary,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  verified
                      ? context.tr('turnstile.verified')
                      : status == TurnstileStatus.expired
                          ? context.tr('turnstile.expired')
                          : context.tr('turnstile.verify'),
                ),
              ),
              if (!verified)
                TextButton(
                  key: const Key('turnstile-verify'),
                  onPressed: _opening ? null : _verify,
                  child: _opening
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(
                          status == TurnstileStatus.expired ||
                                  status == TurnstileStatus.error
                              ? context.tr('turnstile.verifyAgain')
                              : context.tr('turnstile.start'),
                        ),
                ),
            ],
          ),
        );
      },
    );
  }
}
