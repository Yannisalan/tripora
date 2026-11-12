import 'dart:convert';

import 'package:flutter/material.dart' show MaterialPageRoute, RouteSettings;
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/core/auth/token_store.dart';
import 'package:frontend/core/security/legacy_storage_cleanup.dart';
import 'package:frontend/routes/app_routes.dart';
import 'package:frontend/services/auth_service.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

String _jwtWithExp(int expSeconds) {
  String part(Map<String, dynamic> value) =>
      base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
  return '${part({'alg': 'none'})}.${part({'sub': '1', 'exp': expSeconds})}.s';
}

int _inOneHour() =>
    DateTime.now().add(const Duration(hours: 1)).millisecondsSinceEpoch ~/
    1000;

http.Response _json(int status, Map<String, dynamic> body,
        {Map<String, String> headers = const {}}) =>
    http.Response(jsonEncode(body), status,
        headers: {'content-type': 'application/json', ...headers});

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    TokenStore.debugForceSecureStorage = null;
    TokenStore.instance.resetForTesting();
    await TokenStore.instance.saveSession(
      accessToken: _jwtWithExp(_inOneHour()),
      refreshToken: 'r1',
    );
  });

  tearDown(() {
    TokenStore.instance.resetForTesting();
  });

  group('email verification', () {
    test('verifyEmail posts the code with the session token', () async {
      late http.Request seen;
      final client = MockClient((request) async {
        seen = request;
        return _json(200, {
          'success': true,
          'user': {'emailVerified': true, 'email': 'a@example.com'},
        });
      });

      final user = await http.runWithClient(
        () => AuthService().verifyEmail(' 123456 '),
        () => client,
      );

      expect(seen.url.path, '/api/auth/verify-email');
      expect(seen.headers['Authorization'], startsWith('Bearer '));
      expect(jsonDecode(seen.body), {'code': '123456'});
      expect(user['emailVerified'], true);
    });

    test('verifyEmail surfaces code_expired', () async {
      final client = MockClient((_) async => _json(400, {
            'success': false,
            'error': 'code_expired',
            'message': 'This code has expired.',
          }));

      expect(
        () => http.runWithClient(
          () => AuthService().verifyEmail('123456'),
          () => client,
        ),
        throwsA(isA<EmailVerificationException>()
            .having((e) => e.code, 'code', 'code_expired')),
      );
    });

    test('resend cooldown reports the wait time', () async {
      final client = MockClient((_) async => _json(
            429,
            {'success': false, 'error': 'resend_cooldown', 'retryAfter': 42},
            headers: {'retry-after': '42'},
          ));

      expect(
        () => http.runWithClient(
          () => AuthService().resendVerificationEmail(),
          () => client,
        ),
        throwsA(isA<EmailVerificationException>()
            .having((e) => e.retryAfterSeconds, 'retryAfter', 42)),
      );
    });
  });

  group('account deletion', () {
    test('sends the current password and clears the session on success',
        () async {
      late http.Request seen;
      final client = MockClient((request) async {
        seen = request;
        return _json(200, {'success': true});
      });

      await http.runWithClient(
        () => AuthService().deleteAccount(currentPassword: 'pw-123456'),
        () => client,
      );

      expect(seen.method, 'DELETE');
      expect(jsonDecode(seen.body), {'currentPassword': 'pw-123456'});
      expect(await TokenStore.instance.readRefreshToken(), isNull);
    });

    test('keeps the session when the password is rejected', () async {
      final client = MockClient((_) async => _json(401, {
            'success': false,
            'error': 'reauth_failed',
            'message': 'Your password is incorrect.',
          }));

      await expectLater(
        () => http.runWithClient(
          () => AuthService().deleteAccount(currentPassword: 'wrong'),
          () => client,
        ),
        throwsA(predicate((e) => e.toString().contains('incorrect'))),
      );
      expect(await TokenStore.instance.readRefreshToken(), 'r1');
    });
  });

  group('legacy admin token cleanup (admin UI removed)', () {
    test('removes a stored admin_token and keeps other preferences',
        () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'admin_token': 'old-shared-secret',
        'language': 'fr',
      });

      await LegacyStorageCleanup.run();

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.containsKey('admin_token'), isFalse);
      expect(
        prefs.getKeys().where((k) => prefs.get(k) == 'old-shared-secret'),
        isEmpty,
      );
      expect(prefs.getString('language'), 'fr');
    });

    test('is a no-op when nothing was stored', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{'language': 'de'});

      await LegacyStorageCleanup.run();
      await LegacyStorageCleanup.run();

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getKeys(), {'language'});
    });

    test('the app exposes no admin routes; old admin links open Home', () {
      expect(
        AppRoutes.routes.keys.where((r) => r.startsWith('/admin')),
        isEmpty,
      );
      final route = AppRoutes.unknownRoute(
        const RouteSettings(name: '/admin/login'),
      );
      expect(route, isA<MaterialPageRoute<void>>());
      expect(route.settings.name, AppRoutes.home);
    });
  });
}
