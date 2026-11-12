import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/core/auth/token_store.dart';
import 'package:frontend/services/auth_service.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Builds an unsigned JWT-shaped string whose payload carries [expSeconds].
String _jwtWithExp(int expSeconds) {
  String part(Map<String, dynamic> value) =>
      base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');

  final header = part({'alg': 'none', 'typ': 'JWT'});
  final payload = part({'sub': '1', 'exp': expSeconds});

  return '$header.$payload.signature';
}

int _inSeconds(Duration offset) =>
    DateTime.now().add(offset).millisecondsSinceEpoch ~/ 1000;

void main() {
  final store = TokenStore.instance;

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    TokenStore.debugForceSecureStorage = null;
    TokenStore.instance.resetForTesting();
  });

  tearDown(() {
    TokenStore.debugForceSecureStorage = null;
    TokenStore.instance.resetForTesting();
  });

  group('getAuthHeaders', () {
    test('throws when no session is stored', () async {
      expect(
        () => AuthService().getAuthHeaders(),
        throwsA(
          predicate(
            (Object? e) => e.toString().contains('You are not logged in.'),
          ),
        ),
      );
    });

    test('returns the stored token without contacting the network', () async {
      final token = _jwtWithExp(_inSeconds(const Duration(hours: 1)));
      await TokenStore.instance.saveSession(
        accessToken: token,
        refreshToken: 'r1',
      );

      final client = MockClient((_) async => fail('no network expected'));

      final headers = await http.runWithClient(
        () => AuthService().getAuthHeaders(),
        () => client,
      );

      expect(headers['Authorization'], 'Bearer $token');
    });

    test('refreshes an expired token before returning headers', () async {
      final expired = _jwtWithExp(_inSeconds(const Duration(minutes: 5) * -1));
      await TokenStore.instance.saveSession(
        accessToken: expired,
        refreshToken: 'r1',
      );

      final client = MockClient(
        (_) async => http.Response(
          jsonEncode({
            'success': true,
            'accessToken': 'fresh-access',
            'refreshToken': 'fresh-refresh',
          }),
          200,
        ),
      );

      final headers = await http.runWithClient(
        () => AuthService().getAuthHeaders(),
        () => client,
      );

      expect(headers['Authorization'], 'Bearer fresh-access');
      expect(await store.readAccessToken(), 'fresh-access');
      expect(await store.readRefreshToken(), 'fresh-refresh');
    });
  });

  group('ensureFreshSession', () {
    test('is true for a valid access token and makes no request', () async {
      final token = _jwtWithExp(_inSeconds(const Duration(hours: 1)));
      SharedPreferences.setMockInitialValues(<String, Object>{
        TokenStore.accessTokenKey: token,
      });

      final client = MockClient((_) async => fail('no network expected'));

      final ok = await http.runWithClient(
        () => AuthService().ensureFreshSession(),
        () => client,
      );

      expect(ok, isTrue);
    });

    test('is false when nothing is stored', () async {
      expect(await AuthService().ensureFreshSession(), isFalse);
    });
  });

  group('refreshSession', () {
    test('stores the rotated tokens on success', () async {
      await TokenStore.instance.saveSession(accessToken: 'old', refreshToken: 'r1');

      final client = MockClient((request) async {
        expect(request.url.path, '/api/auth/refresh');
        expect(
          jsonDecode(request.body)['refreshToken'],
          'r1',
          reason: 'the stored refresh token must be sent',
        );
        return http.Response(
          jsonEncode({
            'success': true,
            'accessToken': 'new-access',
            'refreshToken': 'new-refresh',
          }),
          200,
        );
      });

      final result = await http.runWithClient(
        () => AuthService().refreshSession(),
        () => client,
      );

      expect(result, RefreshResult.refreshed);
      expect(await store.readAccessToken(), 'new-access');
      expect(await store.readRefreshToken(), 'new-refresh');
    });

    test('is invalid and clears the session on 401', () async {
      await TokenStore.instance.saveSession(
        accessToken: 'a1',
        refreshToken: 'r1',
      );

      final client = MockClient(
        (_) async => http.Response(jsonEncode({'success': false}), 401),
      );

      final result = await http.runWithClient(
        () => AuthService().refreshSession(),
        () => client,
      );

      expect(result, RefreshResult.invalid);
      expect(await store.readAccessToken(), isNull);
      expect(await store.readRefreshToken(), isNull);
    });

    test('is transient and keeps the session on 500', () async {
      await TokenStore.instance.saveSession(
        accessToken: 'a1',
        refreshToken: 'r1',
      );

      final client = MockClient((_) async => http.Response('oops', 500));

      final result = await http.runWithClient(
        () => AuthService().refreshSession(),
        () => client,
      );

      expect(result, RefreshResult.transient);
      expect(await store.readAccessToken(), 'a1');
      expect(await store.readRefreshToken(), 'r1');
    });

    test('is invalid without a request when no refresh token is stored',
        () async {
      final client = MockClient((_) async => fail('no network expected'));

      final result = await http.runWithClient(
        () => AuthService().refreshSession(),
        () => client,
      );

      expect(result, RefreshResult.invalid);
    });
  });
}
