import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/core/auth/token_store.dart';
import 'package:frontend/core/network/api_client.dart';
import 'package:frontend/services/auth_service.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A stand-in for [AuthService] so the client's refresh/replay behaviour can
/// be driven deterministically without any real token or network.
class _FakeAuth extends AuthService {
  _FakeAuth({
    required this.result,
    Map<String, String>? initialHeaders,
    this.headersAfterRefresh,
  }) : headers = initialHeaders ?? const {'Authorization': 'Bearer access'};

  Map<String, String> headers;
  final Map<String, String>? headersAfterRefresh;
  RefreshResult result;
  int refreshCalls = 0;

  @override
  Future<Map<String, String>> getAuthHeaders() async => headers;

  @override
  Future<RefreshResult> refreshSession() async {
    refreshCalls++;

    if (result == RefreshResult.refreshed && headersAfterRefresh != null) {
      headers = headersAfterRefresh!;
    }

    return result;
  }
}

void main() {
  // AuthGuard.handleUnauthorized reads the root navigator key, which needs a
  // binding even when no widget tree is mounted.
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    TokenStore.debugForceSecureStorage = null;
    TokenStore.instance.resetForTesting();
  });

  tearDown(() {
    TokenStore.debugForceSecureStorage = null;
    TokenStore.instance.resetForTesting();
  });

  test('attaches the Authorization header to a successful request', () async {
    Map<String, String>? seenHeaders;
    final client = MockClient((request) async {
      seenHeaders = request.headers;
      return http.Response(jsonEncode({'ok': true}), 200);
    });
    final auth = _FakeAuth(
      result: RefreshResult.refreshed,
      initialHeaders: const {'Authorization': 'Bearer access-1'},
    );
    final api = ApiClient.forTest(client: client, auth: auth);

    final response = await api.get(Uri.parse('https://api.test/api/trips'));

    expect(response.statusCode, 200);
    expect(seenHeaders!['Authorization'], 'Bearer access-1');
    expect(auth.refreshCalls, 0);
  });

  test('refreshes once and replays an idempotent GET after a 401', () async {
    var calls = 0;
    final seenTokens = <String?>[];
    final client = MockClient((request) async {
      calls++;
      seenTokens.add(request.headers['Authorization']);
      return calls == 1
          ? http.Response('', 401)
          : http.Response(jsonEncode({'ok': true}), 200);
    });
    final auth = _FakeAuth(
      result: RefreshResult.refreshed,
      initialHeaders: const {'Authorization': 'Bearer old'},
      headersAfterRefresh: const {'Authorization': 'Bearer new'},
    );
    final api = ApiClient.forTest(client: client, auth: auth);

    final response = await api.get(Uri.parse('https://api.test/api/trips'));

    expect(response.statusCode, 200);
    expect(calls, 2, reason: 'GET must be replayed after a refresh');
    expect(seenTokens, ['Bearer old', 'Bearer new']);
    expect(auth.refreshCalls, 1, reason: 'refresh must run exactly once');
  });

  test('does not replay a POST after a 401', () async {
    var calls = 0;
    final client = MockClient((request) async {
      calls++;
      return http.Response('', 401);
    });
    final auth = _FakeAuth(
      result: RefreshResult.refreshed,
      initialHeaders: const {'Authorization': 'Bearer old'},
      headersAfterRefresh: const {'Authorization': 'Bearer new'},
    );
    final api = ApiClient.forTest(client: client, auth: auth);

    final response = await api.post(
      Uri.parse('https://api.test/api/trips'),
      body: '{}',
    );

    expect(response.statusCode, 401);
    expect(calls, 1, reason: 'a POST must never be silently re-run');
    expect(auth.refreshCalls, 1);
  });

  test('clears the session and does not replay when refresh is invalid',
      () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      TokenStore.accessTokenKey: 'old',
      TokenStore.refreshTokenKey: 'r1',
    });

    var calls = 0;
    final client = MockClient((request) async {
      calls++;
      return http.Response('', 401);
    });
    final auth = _FakeAuth(
      result: RefreshResult.invalid,
      initialHeaders: const {'Authorization': 'Bearer old'},
    );
    final api = ApiClient.forTest(client: client, auth: auth);

    final response = await api.get(Uri.parse('https://api.test/api/trips'));

    expect(response.statusCode, 401);
    expect(calls, 1);
    expect(await TokenStore.instance.readAccessToken(), isNull);
    expect(await TokenStore.instance.readRefreshToken(), isNull);
  });

  test('leaves the session intact when refresh is transient', () async {
    await TokenStore.instance.saveSession(
      accessToken: 'old',
      refreshToken: 'r1',
    );

    var calls = 0;
    final client = MockClient((request) async {
      calls++;
      return http.Response('', 401);
    });
    final auth = _FakeAuth(
      result: RefreshResult.transient,
      initialHeaders: const {'Authorization': 'Bearer old'},
    );
    final api = ApiClient.forTest(client: client, auth: auth);

    final response = await api.get(Uri.parse('https://api.test/api/trips'));

    expect(response.statusCode, 401);
    expect(calls, 1);
    expect(await TokenStore.instance.readAccessToken(), 'old');
    expect(await TokenStore.instance.readRefreshToken(), 'r1');
  });

  test('passes a non-401 error response straight through', () async {
    var calls = 0;
    final client = MockClient((request) async {
      calls++;
      return http.Response('boom', 500);
    });
    final auth = _FakeAuth(result: RefreshResult.refreshed);
    final api = ApiClient.forTest(client: client, auth: auth);

    final response = await api.get(Uri.parse('https://api.test/api/trips'));

    expect(response.statusCode, 500);
    expect(calls, 1);
    expect(auth.refreshCalls, 0, reason: 'no 401 means no refresh');
  });
}
