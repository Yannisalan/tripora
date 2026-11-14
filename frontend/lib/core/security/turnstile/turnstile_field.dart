import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import 'turnstile_config.dart';
import 'turnstile_controller.dart';
import 'turnstile_view.dart';

export 'turnstile_controller.dart';

/// Bot-protection block for a protected form (sign-up, password reset).
///
/// Loads the backend's Turnstile config. When protection is off it renders
/// nothing and the controller reports [TurnstileStatus.disabled]; otherwise
/// it shows the platform's challenge (web widget or Android WebView) and
/// keeps the controller's token up to date.
class TurnstileField extends StatefulWidget {
  const TurnstileField({super.key, required this.controller});

  final TurnstileController controller;

  @override
  State<TurnstileField> createState() => _TurnstileFieldState();
}

class _TurnstileFieldState extends State<TurnstileField> {
  TurnstileConfig? _config;
  bool _failed = false;
  // Bumped on every load so a retry builds a fresh platform view (the config
  // is cached, so the view would otherwise be kept and never re-rendered).
  int _attempt = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _failed = false;
      _config = null;
      _attempt++;
    });
    try {
      final config = await TurnstileConfigService.load();
      if (!mounted) return;
      if (!config.enabled) {
        widget.controller.markDisabled();
      } else if (!config.usable) {
        widget.controller.markUnavailable();
        setState(() => _failed = true);
        return;
      }
      setState(() => _config = config);
    } catch (_) {
      if (!mounted) return;
      widget.controller.markUnavailable();
      setState(() => _failed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final config = _config;
    final errorColor = Theme.of(context).colorScheme.error;

    if (_failed) {
      return Row(
        key: const Key('turnstile-config-error'),
        children: [
          Expanded(
            child: Text(
              context.tr('turnstile.loadError'),
              style: TextStyle(color: errorColor),
            ),
          ),
          Flexible(
            child: TextButton(
              onPressed: _load,
              child: Text(context.tr('turnstile.retry')),
            ),
          ),
        ],
      );
    }

    if (config == null) {
      return Row(
        key: const Key('turnstile-loading'),
        children: [
          const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 12),
          Expanded(child: Text(context.tr('turnstile.loading'))),
        ],
      );
    }

    if (!config.enabled) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        KeyedSubtree(
          key: ValueKey<int>(_attempt),
          child: buildTurnstileView(controller: widget.controller, config: config),
        ),
        ListenableBuilder(
          listenable: widget.controller,
          builder: (context, _) {
            final status = widget.controller.status;
            // Web: Cloudflare's script was blocked or the widget failed to
            // render. Submitting stays blocked (fail closed); explain it and
            // offer a retry that rebuilds the widget. Native views show their
            // own message for this state.
            if (kIsWeb && status == TurnstileStatus.unavailable) {
              return Row(
                key: const Key('turnstile-web-unavailable'),
                children: [
                  Expanded(
                    child: Text(
                      context.tr('turnstile.loadError'),
                      style: TextStyle(color: errorColor),
                    ),
                  ),
                  TextButton(
                    onPressed: _load,
                    child: Text(context.tr('turnstile.retry')),
                  ),
                ],
              );
            }
            if (status != TurnstileStatus.error) {
              return const SizedBox.shrink();
            }
            return Row(
              children: [
                Expanded(
                  child: Text(
                    context.tr('turnstile.loadError'),
                    style: TextStyle(color: errorColor),
                  ),
                ),
                TextButton(
                  onPressed: widget.controller.reset,
                  child: Text(context.tr('turnstile.retry')),
                ),
              ],
            );
          },
        ),
      ],
    );
  }
}
