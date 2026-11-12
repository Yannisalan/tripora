import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/core/security/turnstile/turnstile_challenge_policy.dart';
import 'package:frontend/core/security/turnstile/turnstile_config.dart';
import 'package:frontend/core/security/turnstile/turnstile_event.dart';
import 'package:frontend/core/security/turnstile/turnstile_field.dart';
import 'package:frontend/core/security/turnstile/turnstile_view_io.dart';
import 'package:frontend/services/auth_service.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

http.Response _json(int status, Object body) => http.Response(
      jsonEncode(body),
      status,
      headers: {'content-type': 'application/json'},
    );

MockClient _configClient(Object body, {int status = 200, List<String>? log}) {
  return MockClient((request) async {
    log?.add('${request.method} ${request.url.path}');
    if (request.url.path == '/api/turnstile/config') return _json(status, body);
    return _json(404, {});
  });
}

const _enabled = {
  'success': true,
  'enabled': true,
  'siteKey': '1x00000000000000000000AA',
  'challengePath': '/api/turnstile/challenge',
};
const _disabled = {'success': true, 'enabled': false, 'siteKey': null};

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    TurnstileConfigService.debugReset();
    TurnstileNativeOverrides.reset();
  });

  // ------------------------------------------------------------------
  group('TurnstileEvent.parse', () {
    test('accepts the four message types', () {
      expect(TurnstileEvent.parse('{"type":"ready"}')!.type,
          TurnstileEventType.ready);
      expect(TurnstileEvent.parse('{"type":"expired"}')!.type,
          TurnstileEventType.expired);
      final error = TurnstileEvent.parse('{"type":"error","code":"110200"}')!;
      expect(error.type, TurnstileEventType.error);
      expect(error.code, '110200');
      final token = TurnstileEvent.parse('{"type":"token","token":"0.abc-_X"}')!;
      expect(token.type, TurnstileEventType.token);
      expect(token.token, '0.abc-_X');
    });

    test('ignores anything malformed', () {
      for (final raw in [
        'not json',
        '[]',
        '"token"',
        '{}',
        '{"type":"navigate","url":"https://evil"}',
        '{"type":"token"}',
        '{"type":"token","token":""}',
        '{"type":"token","token":42}',
        '{"type":"token","token":"has space"}',
        jsonEncode({'type': 'token', 'token': 'x' * 2049}),
        'x' * 5000,
      ]) {
        expect(TurnstileEvent.parse(raw), isNull, reason: raw);
      }
    });

    test('drops oversized error codes', () {
      final e = TurnstileEvent.parse(jsonEncode({'type': 'error', 'code': 'c' * 65}))!;
      expect(e.code, isNull);
    });
  });

  // ------------------------------------------------------------------
  group('Android challenge policy', () {
    final challenge = buildChallengeUri(
      apiBaseUrl: 'https://tripora-4mt3.onrender.com',
      challengePath: '/api/turnstile/challenge',
      action: 'register',
      dark: true,
    );

    test('builds the backend challenge URL', () {
      expect(challenge.toString(),
          'https://tripora-4mt3.onrender.com/api/turnstile/challenge?action=register&theme=dark');
    });

    test('only the challenge page may load in the main frame', () {
      expect(isAllowedMainFrameNavigation(challenge, challenge.toString()), isTrue);
      expect(
          isAllowedMainFrameNavigation(challenge,
              'https://tripora-4mt3.onrender.com/api/turnstile/challenge?action=forgot_password&theme=light'),
          isTrue);
      for (final url in [
        'https://challenges.cloudflare.com/cdn-cgi/challenge-platform/x',
        'https://evil.example.com/api/turnstile/challenge',
        'http://tripora-4mt3.onrender.com/api/turnstile/challenge',
        'https://tripora-4mt3.onrender.com/api/auth/login',
        'https://user:pw@tripora-4mt3.onrender.com/api/turnstile/challenge',
        'https://tripora-4mt3.onrender.com:8443/api/turnstile/challenge',
        'javascript:alert(1)',
        'intent://scan#Intent;end',
        'file:///etc/passwd',
        'about:blank',
      ]) {
        expect(isAllowedMainFrameNavigation(challenge, url), isFalse, reason: url);
      }
    });

    test('the channel name matches the backend page', () {
      expect(turnstileChannelName, 'TriporaTurnstile');
    });
  });

  // ------------------------------------------------------------------
  group('web deployment config', () {
    test('honeypot is hidden by a static CSS rule, off-screen, not display:none',
        () {
      final html = File('web/index.html').readAsStringSync();
      final rule = RegExp(r'\.tp-website\s*\{([^}]*)\}').firstMatch(html);
      expect(rule, isNotNull);
      final body = rule!.group(1)!;
      expect(body, contains('position: absolute'));
      expect(body, contains('left: -10000px'));
      expect(body, isNot(contains('display: none')));
    });

    test('CSP allows Cloudflare Turnstile and nothing broader', () {
      final vercel = jsonDecode(File('vercel.json').readAsStringSync()) as Map;
      final headers = (vercel['headers'] as List)
          .expand((h) => (h as Map)['headers'] as List)
          .cast<Map>();
      final csp = headers
          .firstWhere((h) => '${h['key']}'.startsWith('Content-Security-Policy'))['value']
          as String;
      final directives = {
        for (final part in csp.split(';'))
          if (part.trim().isNotEmpty)
            part.trim().split(RegExp(r'\s+')).first:
                part.trim().split(RegExp(r'\s+')).skip(1).toList(),
      };
      expect(directives['script-src'], contains('https://challenges.cloudflare.com'));
      expect(directives['frame-src'], ['https://challenges.cloudflare.com']);
      expect(directives['script-src'], isNot(contains("'unsafe-inline'")));
      expect(directives['frame-ancestors'], ["'none'"]);
      expect(directives['object-src'], ["'none'"]);
    });
  });

  // ------------------------------------------------------------------
  group('TurnstileController', () {
    test('needs a token unless protection is disabled', () {
      final c = TurnstileController(action: 'register');
      expect(c.readyToSubmit, isFalse);
      c.markWaiting();
      expect(c.readyToSubmit, isFalse);
      c.handle(TurnstileEvent.tokenEvent('tok')!);
      expect(c.readyToSubmit, isTrue);
      expect(c.token, 'tok');
      c.dispose();

      final off = TurnstileController(action: 'register')..markDisabled();
      expect(off.readyToSubmit, isTrue);
      expect(off.token, isNull);
      off.dispose();
    });

    test('reset discards the single-use token and bumps the generation', () {
      final c = TurnstileController(action: 'register')..markWaiting();
      c.handle(TurnstileEvent.tokenEvent('tok')!);
      final before = c.generation;
      c.reset();
      expect(c.token, isNull);
      expect(c.readyToSubmit, isFalse);
      expect(c.generation, before + 1);
      c.dispose();
    });

    test('reset is a no-op when protection is disabled or unavailable', () {
      final c = TurnstileController(action: 'register')..markDisabled();
      c.reset();
      expect(c.status, TurnstileStatus.disabled);
      c.markUnavailable();
      c.reset();
      expect(c.status, TurnstileStatus.unavailable);
      c.dispose();
    });

    testWidgets('a token expires before Cloudflare\'s 300 s limit',
        (tester) async {
      // testWidgets runs on a fake clock.
      final c = TurnstileController(action: 'register')..markWaiting();
      c.handle(TurnstileEvent.tokenEvent('tok')!);
      await tester.pump(const Duration(seconds: 279));
      expect(c.status, TurnstileStatus.verified);
      await tester.pump(const Duration(seconds: 2));
      expect(c.status, TurnstileStatus.expired);
      expect(c.token, isNull);
      expect(c.readyToSubmit, isFalse);
      c.dispose();
    });

    test('expired and error events clear the token', () {
      final c = TurnstileController(action: 'register')..markWaiting();
      c.handle(TurnstileEvent.tokenEvent('tok')!);
      c.handle(const TurnstileEvent.expired());
      expect(c.token, isNull);
      c.handle(TurnstileEvent.tokenEvent('tok2')!);
      c.handle(const TurnstileEvent.error());
      expect(c.token, isNull);
      expect(c.status, TurnstileStatus.error);
      c.dispose();
    });

    test('honeypot is empty natively and never throws', () {
      final c = TurnstileController(action: 'register');
      expect(c.honeypotValue, '');
      c.honeypotReader = () => 'spam';
      expect(c.honeypotValue, 'spam');
      c.honeypotReader = () => throw StateError('detached');
      expect(c.honeypotValue, '');
      c.dispose();
    });
  });

  // ------------------------------------------------------------------
  group('TurnstileConfig', () {
    test('parses the backend payload and never trusts a foreign path', () {
      final c = TurnstileConfig.fromJson({
        'enabled': true,
        'siteKey': ' key ',
        'challengePath': 'https://evil.example.com/x',
      });
      expect(c.enabled, isTrue);
      expect(c.siteKey, 'key');
      expect(c.challengePath, TurnstileConfig.defaultChallengePath);
      expect(c.usable, isTrue);
      expect(TurnstileConfig.fromJson({'enabled': true}).usable, isFalse);
      expect(TurnstileConfig.fromJson({'enabled': 'yes'}).enabled, isFalse);
    });

    test('loads once, and retries after a failure', () async {
      final log = <String>[];
      await http.runWithClient(() async {
        final a = await TurnstileConfigService.load(baseUrl: 'https://api.test');
        final b = await TurnstileConfigService.load(baseUrl: 'https://api.test');
        expect(a.enabled, isTrue);
        expect(identical(a, b), isTrue);
      }, () => _configClient(_enabled, log: log));
      expect(log, ['GET /api/turnstile/config']);

      TurnstileConfigService.debugReset();
      await http.runWithClient(() async {
        await expectLater(
          TurnstileConfigService.load(baseUrl: 'https://api.test'),
          throwsA(anything),
        );
      }, () => _configClient({}, status: 500));
      await http.runWithClient(() async {
        final c = await TurnstileConfigService.load(baseUrl: 'https://api.test');
        expect(c.enabled, isFalse);
      }, () => _configClient(_disabled));
    });
  });

  // ------------------------------------------------------------------
  group('AuthService sends the bot-protection fields', () {
    Future<Map<String, dynamic>> capture(
        Future<void> Function(AuthService) call, int status, Map body) async {
      late Map<String, dynamic> sent;
      final client = MockClient((request) async {
        sent = jsonDecode(request.body) as Map<String, dynamic>;
        return _json(status, body);
      });
      await http.runWithClient(() => call(AuthService()), () => client);
      return sent;
    }

    test('register', () async {
      final sent = await capture(
        (s) => s.register(
          name: 'A',
          email: 'a@example.com',
          password: 'Password123!',
          turnstileToken: 'tok',
        ),
        201,
        {'success': true, 'verificationRequired': true},
      );
      expect(sent['turnstileToken'], 'tok');
      expect(sent['website'], '');
    });

    test('forgot password, protection off: no token, empty honeypot', () async {
      final sent = await capture(
        (s) => s.forgotPassword(email: 'a@example.com'),
        200,
        {'success': true, 'message': 'sent'},
      );
      expect(sent.containsKey('turnstileToken'), isFalse);
      expect(sent['website'], '');
      expect(sent['email'], 'a@example.com');
    });

    test('a challenge failure surfaces the server message', () async {
      final client = MockClient((_) async => _json(400, {
            'success': false,
            'code': 'turnstile_failed',
            'message': 'We could not verify that you are human.',
          }));
      await http.runWithClient(() async {
        await expectLater(
          AuthService().forgotPassword(email: 'a@example.com', turnstileToken: 'bad'),
          throwsA(predicate((e) => e.toString().contains('verify that you are human'))),
        );
      }, () => client);
    });
  });

  // ------------------------------------------------------------------
  group('TurnstileField on Android (native view)', () {
    Future<void> pumpField(WidgetTester tester, TurnstileController c, MockClient client) {
      return http.runWithClient(() async {
        await tester.pumpWidget(MaterialApp(
          home: Scaffold(body: Center(child: TurnstileField(controller: c))),
        ));
        await tester.pumpAndSettle();
      }, () => client);
    }

    testWidgets('disabled on the backend: renders nothing, form may submit',
        (tester) async {
      final c = TurnstileController(action: 'register');
      await pumpField(tester, c, _configClient(_disabled));
      expect(c.status, TurnstileStatus.disabled);
      expect(c.readyToSubmit, isTrue);
      expect(find.byKey(const Key('turnstile-verify')), findsNothing);
      c.dispose();
    });

    testWidgets('opens the backend challenge and stores the returned token',
        (tester) async {
      TurnstileNativeOverrides.supported = true;
      Uri? opened;
      TurnstileNativeOverrides.launcher = (context, uri) async {
        opened = uri;
        return 'token-from-webview';
      };
      final c = TurnstileController(action: 'forgot_password');
      await pumpField(tester, c, _configClient(_enabled));
      expect(c.status, TurnstileStatus.waiting);
      expect(c.readyToSubmit, isFalse);

      await tester.tap(find.byKey(const Key('turnstile-verify')));
      await tester.pumpAndSettle();

      expect(opened!.path, '/api/turnstile/challenge');
      expect(opened!.queryParameters['action'], 'forgot_password');
      expect(c.token, 'token-from-webview');
      expect(c.readyToSubmit, isTrue);
      expect(c.honeypotValue, '');
      expect(find.byKey(const Key('turnstile-verify')), findsNothing);

      c.reset(); // after a submit
      await tester.pump();
      expect(find.byKey(const Key('turnstile-verify')), findsOneWidget);
      c.dispose();
    });

    testWidgets('closing the challenge without solving keeps the form locked',
        (tester) async {
      TurnstileNativeOverrides.supported = true;
      TurnstileNativeOverrides.launcher = (context, uri) async => null;
      final c = TurnstileController(action: 'register');
      await pumpField(tester, c, _configClient(_enabled));
      await tester.tap(find.byKey(const Key('turnstile-verify')));
      await tester.pumpAndSettle();
      expect(c.readyToSubmit, isFalse);
      c.dispose();
    });

    testWidgets('a malformed token from the WebView is ignored', (tester) async {
      TurnstileNativeOverrides.supported = true;
      TurnstileNativeOverrides.launcher = (context, uri) async => 'bad token';
      final c = TurnstileController(action: 'register');
      await pumpField(tester, c, _configClient(_enabled));
      await tester.tap(find.byKey(const Key('turnstile-verify')));
      await tester.pumpAndSettle();
      expect(c.readyToSubmit, isFalse);
      c.dispose();
    });

    testWidgets('platforms without a WebView report unavailable', (tester) async {
      TurnstileNativeOverrides.supported = false;
      final c = TurnstileController(action: 'register');
      await pumpField(tester, c, _configClient(_enabled));
      expect(c.status, TurnstileStatus.unavailable);
      expect(c.readyToSubmit, isFalse);
      expect(find.byKey(const Key('turnstile-unsupported')), findsOneWidget);
      c.dispose();
    });

    testWidgets('config errors block the form and offer a retry', (tester) async {
      final c = TurnstileController(action: 'register');
      await pumpField(tester, c, _configClient({}, status: 503));
      expect(c.readyToSubmit, isFalse);
      expect(find.byKey(const Key('turnstile-config-error')), findsOneWidget);

      TurnstileNativeOverrides.supported = true;
      await http.runWithClient(() async {
        await tester.tap(find.text('Try again'));
        await tester.pumpAndSettle();
      }, () => _configClient(_enabled));
      expect(c.status, TurnstileStatus.waiting);
      c.dispose();
    });

    testWidgets('enabled without a site key is unavailable', (tester) async {
      final c = TurnstileController(action: 'register');
      await pumpField(tester, c, _configClient({'enabled': true, 'siteKey': null}));
      expect(c.status, TurnstileStatus.unavailable);
      expect(c.readyToSubmit, isFalse);
      c.dispose();
    });
  });
}
