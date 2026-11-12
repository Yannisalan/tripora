// Browser-only: flutter test --platform chrome test/turnstile_web_test.dart
@TestOn('browser')
library;

import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/core/security/turnstile/turnstile_config.dart';
import 'package:frontend/core/security/turnstile/turnstile_field.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:web/web.dart' as web;

/// Stand-in for Cloudflare's `window.turnstile` (no network). Records calls.
class FakeTurnstile {
  FakeTurnstile() {
    final api = JSObject();
    api['render'] = ((web.HTMLElement container, JSObject options) {
      if (failNextRender) {
        failNextRender = false;
        throw StateError('widget failed to load');
      }
      renders.add(options);
      container.append(web.HTMLDivElement()..className = 'fake-turnstile');
      return 'widget-1'.toJS;
    }).toJS;
    api['reset'] = ((JSString id) => resets.add(id.toDart)).toJS;
    api['remove'] = ((JSString id) => removes.add(id.toDart)).toJS;
    globalContext['turnstile'] = api;
  }

  /// Simulates Cloudflare's widget failing to load (blocked script, network).
  bool failNextRender = false;
  final renders = <JSObject>[];
  final resets = <String>[];
  final removes = <String>[];

  JSObject get options => renders.single;

  void fire(String name, [JSAny? arg]) =>
      (options[name] as JSFunction).callAsFunction(null, arg);

  static void uninstall() => globalContext.delete('turnstile'.toJS);
}

/// Stand-in for the web engine's platform-view creation.
///
/// Widget tests don't hand frames to the engine, so the engine never creates
/// `HtmlElementView` elements (Flutter's own HtmlElementView tests use the
/// same technique). This registry runs the app's real view factory when the
/// framework sends `platform_views.create` and attaches the element to the
/// page, as the engine does, so the real DOM can be inspected.
class EnginePlatformViews implements ui_web.PlatformViewRegistry {
  EnginePlatformViews() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform_views, _onCall);
    ui_web.debugOverridePlatformViewRegistry(this);
  }

  final _factories = <String, Function>{};
  final _views = <int, web.HTMLElement>{};

  @override
  bool registerViewFactory(String viewType, Function viewFactory,
      {bool isVisible = true}) {
    if (_factories.containsKey(viewType)) return false;
    _factories[viewType] = viewFactory;
    return true;
  }

  @override
  Object getViewById(int viewId) => _views[viewId]!;

  Future<Object?> _onCall(MethodCall call) async {
    switch (call.method) {
      case 'create':
        final args = call.arguments as Map<Object?, Object?>;
        final id = args['id']! as int;
        final factory = _factories[args['viewType']! as String];
        if (factory == null) {
          throw PlatformException(code: 'error', message: 'unregistered view');
        }
        final element = Function.apply(factory, [id]) as web.HTMLElement;
        web.document.body!.append(element);
        _views[id] = element;
      case 'dispose':
        _views.remove(call.arguments as int)?.remove();
    }
    return null;
  }

  void uninstall() {
    for (final element in _views.values) {
      element.remove();
    }
    _views.clear();
    ui_web.debugOverridePlatformViewRegistry(null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform_views, null);
  }
}

MockClient _config() => MockClient((request) async => http.Response(
      jsonEncode({
        'success': true,
        'enabled': true,
        'siteKey': '1x00000000000000000000AA',
        'challengePath': '/api/turnstile/challenge',
      }),
      200,
      headers: {'content-type': 'application/json'},
    ));

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  late FakeTurnstile fake;
  late EnginePlatformViews views;

  setUp(() {
    TurnstileConfigService.debugReset();
    fake = FakeTurnstile();
    views = EnginePlatformViews();
  });

  tearDown(() {
    views.uninstall();
    FakeTurnstile.uninstall();
  });

  Future<TurnstileController> pump(WidgetTester tester) async {
    final controller = TurnstileController(action: 'register');
    await http.runWithClient(() async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SizedBox(width: 360, child: TurnstileField(controller: controller)),
        ),
      ));
      await _settle(tester);
    }, _config);
    return controller;
  }

  testWidgets('renders the official widget with the public key and action',
      (tester) async {
    final c = await pump(tester);
    expect(fake.renders, hasLength(1));
    expect((fake.options['sitekey'] as JSString).toDart, '1x00000000000000000000AA');
    expect((fake.options['action'] as JSString).toDart, 'register');
    expect((fake.options['size'] as JSString).toDart, 'flexible');
    expect(c.status, TurnstileStatus.waiting);
    expect(c.readyToSubmit, isFalse);
    c.dispose();
  });

  testWidgets('callback stores the token; expiry and errors clear it',
      (tester) async {
    final c = await pump(tester);

    fake.fire('callback', 'tok-1'.toJS);
    expect(c.token, 'tok-1');
    expect(c.readyToSubmit, isTrue);

    // Widget-reported expiry: token dropped and a fresh challenge requested.
    fake.fire('expired-callback');
    await tester.pump();
    expect(c.token, isNull);
    expect(fake.resets, ['widget-1']);

    fake.fire('callback', 'tok-2'.toJS);
    final handled = (fake.options['error-callback'] as JSFunction)
        .callAsFunction(null, '110200'.toJS);
    expect((handled as JSBoolean).toDart, isTrue);
    expect(c.token, isNull);
    expect(c.status, TurnstileStatus.error);
    c.dispose();
  });

  testWidgets('reset after a submit re-arms the widget', (tester) async {
    final c = await pump(tester);
    fake.fire('callback', 'tok'.toJS);
    c.reset();
    await tester.pump();
    expect(fake.resets, ['widget-1']);
    expect(c.readyToSubmit, isFalse);
    c.dispose();
  });

  testWidgets('honeypot is a real, hidden, non-focusable DOM input',
      (tester) async {
    final c = await pump(tester);
    final input = web.document.querySelector('input[name="website"]');
    expect(input, isNotNull);
    final field = input! as web.HTMLInputElement;
    expect(field.type, 'text');
    expect(field.tabIndex, -1);
    expect(field.getAttribute('autocomplete'), 'off');
    final wrapper = field.closest('.tp-website');
    expect(wrapper, isNotNull);
    expect(wrapper!.getAttribute('aria-hidden'), 'true');

    expect(c.honeypotValue, '');
    field.value = 'http://spam.example';
    expect(c.honeypotValue, 'http://spam.example');
    c.dispose();
  });

  testWidgets('a widget that cannot load explains it and offers a retry',
      (tester) async {
    fake.failNextRender = true;
    final c = await pump(tester);
    expect(c.status, TurnstileStatus.unavailable);
    expect(c.readyToSubmit, isFalse);
    final error = find.byKey(const Key('turnstile-web-unavailable'));
    expect(error, findsOneWidget);
    expect(fake.renders, isEmpty);

    await http.runWithClient(() async {
      await tester.tap(find.descendant(of: error, matching: find.byType(TextButton)));
      await _settle(tester);
    }, _config);

    expect(fake.renders, hasLength(1));
    expect(c.status, TurnstileStatus.waiting);
    expect(find.byKey(const Key('turnstile-web-unavailable')), findsNothing);
    c.dispose();
  });

  testWidgets('disposing removes the widget', (tester) async {
    final c = await pump(tester);
    await tester.pumpWidget(const SizedBox());
    expect(fake.removes, ['widget-1']);
    expect(c.honeypotValue, '');
    c.dispose();
  });
}
