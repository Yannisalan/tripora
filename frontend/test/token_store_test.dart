import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/core/auth/token_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Storage behaviour for [TokenStore].
///
/// Tokens are stored in secure storage where available; in unit tests the
/// plugin is not registered so tokens are kept in memory only (no plaintext
/// SharedPreferences fallback). Legacy tokens in SharedPreferences are
/// migrated into secure storage and deleted.
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

  test('saves and reads an access + refresh session', () async {
    await store.saveSession(accessToken: 'a1', refreshToken: 'r1');

    expect(await store.readAccessToken(), 'a1');
    expect(await store.readRefreshToken(), 'r1');
    expect(await store.hasSession(), isTrue);
  });

  test('hasSession is true when only a refresh token is stored', () async {
    await store.saveSession(accessToken: '', refreshToken: 'r1');

    expect(await store.readAccessToken(), isNull);
    expect(await store.hasSession(), isTrue);
  });

  test('hasSession is false when nothing is stored', () async {
    expect(await store.hasSession(), isFalse);
  });

  test('saveSession without a refresh token keeps the existing one', () async {
    await store.saveSession(accessToken: 'a1', refreshToken: 'r1');
    await store.saveSession(accessToken: 'a2');

    expect(await store.readAccessToken(), 'a2');
    expect(await store.readRefreshToken(), 'r1');
  });

  test('clear removes both tokens', () async {
    await store.saveSession(accessToken: 'a1', refreshToken: 'r1');

    await store.clear();

    expect(await store.readAccessToken(), isNull);
    expect(await store.readRefreshToken(), isNull);
    expect(await store.hasSession(), isFalse);
  });

  test('migrates legacy access token from SharedPreferences and deletes it',
      () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(TokenStore.accessTokenKey, 'legacy-a1');

    expect(await store.readAccessToken(), 'legacy-a1');
    expect(prefs.getString(TokenStore.accessTokenKey), isNull);
  });

  test('does not fall back to SharedPreferences when secure storage fails',
      () async {
    TokenStore.debugForceSecureStorage = true;
    SharedPreferences.setMockInitialValues(<String, Object>{
      TokenStore.refreshTokenKey: 'plain-r1',
    });

    // Tokens in SharedPreferences are not read as fallback; only legacy
    // access_token is migrated. refresh_token remains in prefs but is not
    // accessible without secure storage.
    expect(await store.readRefreshToken(), isNull);
    expect(await store.hasSession(), isFalse);
  });
}
