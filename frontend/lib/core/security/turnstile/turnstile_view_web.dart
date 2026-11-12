import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;

import 'turnstile_config.dart';
import 'turnstile_controller.dart';
import 'turnstile_event.dart';

/// Cloudflare's official widget script, explicit-render mode. Allowed by the
/// CSP in `frontend/vercel.json` (script-src and frame-src).
const String _scriptUrl =
    'https://challenges.cloudflare.com/turnstile/v0/api.js?render=explicit';

Future<void>? _scriptLoad;

JSObject? get _turnstileApi {
  final api = globalContext['turnstile'];
  return api.isA<JSObject>() ? api as JSObject : null;
}

Future<void> _ensureScript() {
  if (_turnstileApi != null) return Future.value();
  final pending = _scriptLoad;
  if (pending != null) return pending;

  final completer = Completer<void>();
  final script = web.HTMLScriptElement()
    ..src = _scriptUrl
    ..async = true
    ..defer = true;
  script.addEventListener(
    'load',
    ((web.Event _) {
      if (!completer.isCompleted) completer.complete();
    }).toJS,
  );
  script.addEventListener(
    'error',
    ((web.Event _) {
      if (!completer.isCompleted) {
        completer.completeError(StateError('Turnstile script failed to load'));
      }
    }).toJS,
  );
  web.document.head!.append(script);

  final future = completer.future.timeout(const Duration(seconds: 20));
  _scriptLoad = future;
  future.catchError((Object _) {
    // Allow a later retry to add the script again.
    _scriptLoad = null;
    script.remove();
  });
  return future;
}

Widget buildTurnstileView({
  required TurnstileController controller,
  required TurnstileConfig config,
}) {
  return _WebTurnstileView(controller: controller, siteKey: config.siteKey!);
}

class _WebTurnstileView extends StatefulWidget {
  const _WebTurnstileView({required this.controller, required this.siteKey});

  final TurnstileController controller;
  final String siteKey;

  @override
  State<_WebTurnstileView> createState() => _WebTurnstileViewState();
}

class _WebTurnstileViewState extends State<_WebTurnstileView> {
  static int _nextId = 0;

  late final String _viewType = 'tripora-turnstile-${_nextId++}';
  late final web.HTMLDivElement _root;
  late final web.HTMLDivElement _widgetHost;
  late final web.HTMLInputElement _honeypot;

  bool _viewCreated = false;
  bool _scriptReady = false;
  String? _widgetId;
  late int _renderedGeneration;

  @override
  void initState() {
    super.initState();
    _renderedGeneration = widget.controller.generation;

    _root = web.HTMLDivElement()
      ..style.width = '100%'
      ..style.height = '100%'
      ..style.position = 'relative';
    _widgetHost = web.HTMLDivElement();
    _root.append(_widgetHost);

    // Honeypot: a real DOM input that form-filling bots find, hidden by the
    // static `.tp-website` rule in web/index.html (not by script), out of the
    // tab order, hidden from assistive technology, autofill off.
    final wrapper = web.HTMLDivElement()
      ..className = 'tp-website'
      ..setAttribute('aria-hidden', 'true');
    final label = web.HTMLLabelElement()
      ..textContent = 'Website (leave this field empty)';
    _honeypot = web.HTMLInputElement()
      ..type = 'text'
      ..name = 'website'
      ..autocomplete = 'off'
      ..tabIndex = -1;
    label.append(_honeypot);
    wrapper.append(label);
    _root.append(wrapper);

    ui_web.platformViewRegistry.registerViewFactory(
      _viewType,
      (int viewId) => _root,
    );

    widget.controller.honeypotReader = () => _honeypot.value;
    widget.controller.addListener(_onControllerChanged);

    _loadScript();
  }

  Future<void> _loadScript() async {
    try {
      await _ensureScript();
    } catch (_) {
      if (mounted) widget.controller.markUnavailable();
      return;
    }
    if (!mounted) return;
    _scriptReady = true;
    _renderWhenReady();
  }

  void _onPlatformViewCreated(int _) {
    _viewCreated = true;
    _renderWhenReady();
  }

  void _renderWhenReady() {
    if (!_scriptReady || !_viewCreated || _widgetId != null) return;
    // The element is attached to the page on the next frame.
    WidgetsBinding.instance.addPostFrameCallback((_) => _render());
  }

  void _render() {
    final api = _turnstileApi;
    if (!mounted || api == null || _widgetId != null) return;
    final controller = widget.controller;
    final dark = Theme.of(context).brightness == Brightness.dark;

    final options = JSObject()
      ..['sitekey'] = widget.siteKey.toJS
      ..['action'] = controller.action.toJS
      ..['theme'] = (dark ? 'dark' : 'light').toJS
      ..['size'] = 'flexible'.toJS
      ..['callback'] = ((JSString token) {
        controller.handle(
          TurnstileEvent.tokenEvent(token.toDart) ??
              const TurnstileEvent.error('bad-token'),
        );
      }).toJS
      ..['expired-callback'] =
          (() => controller.handle(const TurnstileEvent.expired())).toJS
      ..['timeout-callback'] =
          (() => controller.handle(const TurnstileEvent.expired())).toJS
      ..['error-callback'] = ((JSAny? code) {
        controller.handle(const TurnstileEvent.error());
        return true.toJS; // handled: keep the error out of the console
      }).toJS;

    try {
      final id = api.callMethod<JSAny?>('render'.toJS, _widgetHost, options);
      _widgetId = id.isA<JSString>() ? (id as JSString).toDart : null;
      controller.markWaiting();
    } catch (_) {
      controller.markUnavailable();
    }
  }

  void _onControllerChanged() {
    final controller = widget.controller;
    // Our own expiry timer fired: get a fresh token instead of waiting for
    // the user to notice.
    if (controller.status == TurnstileStatus.expired) {
      controller.reset();
      return;
    }
    if (controller.generation != _renderedGeneration) {
      _renderedGeneration = controller.generation;
      final api = _turnstileApi;
      final id = _widgetId;
      if (api != null && id != null) {
        try {
          api.callMethod<JSAny?>('reset'.toJS, id.toJS);
        } catch (_) {}
      }
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    widget.controller.honeypotReader = null;
    final api = _turnstileApi;
    final id = _widgetId;
    if (api != null && id != null) {
      try {
        api.callMethod<JSAny?>('remove'.toJS, id.toJS);
      } catch (_) {}
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Turnstile's widget is 65 px tall; "flexible" fills the form width.
    return SizedBox(
      height: 72,
      child: HtmlElementView(
        viewType: _viewType,
        onPlatformViewCreated: _onPlatformViewCreated,
      ),
    );
  }
}
