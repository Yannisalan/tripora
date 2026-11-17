import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:frontend/core/auth/token_store.dart';
import 'package:frontend/core/l10n/app_localizations.dart';
import 'package:frontend/services/trip_service.dart';

import 'support/probe_harness.dart';

/// Every AI-backed trip call must turn the backend's HTTP 503 `ai_busy`
/// into [AiBusyException], so the UI shows the localized
/// `planner.aiBusy` message instead of the backend's English text.
void main() {
  const busyBody =
      '{"error":"ai_busy","message":"The AI is busy right now, please try again in a minute."}';

  http.Client busyBackend() => MockClient(
        (request) async => http.Response(
          busyBody,
          503,
          headers: {'content-type': 'application/json'},
        ),
      );

  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    TokenStore.debugForceSecureStorage = false;
    TokenStore.instance.resetForTesting();
    await TokenStore.instance.saveSession(
      accessToken: 'test-token',
      refreshToken: 'test-refresh',
    );
  });

  tearDown(() {
    TokenStore.debugForceSecureStorage = null;
  });

  test('regenerateItinerary throws AiBusyException on 503 ai_busy', () async {
    await http.runWithClient(() async {
      await expectLater(
        TripService().regenerateItinerary(1),
        throwsA(isA<AiBusyException>()),
      );
    }, busyBackend);
  });

  test('swapActivity throws AiBusyException on 503 ai_busy', () async {
    await http.runWithClient(() async {
      await expectLater(
        TripService().swapActivity(tripId: 1, day: 1, time: 'Morning'),
        throwsA(isA<AiBusyException>()),
      );
    }, busyBackend);
  });

  test('updateTrip (date edit rebuilds itinerary) throws AiBusyException',
      () async {
    await http.runWithClient(() async {
      await expectLater(
        TripService().updateTrip(tripId: 1, trip: sampleTrip()),
        throwsA(isA<AiBusyException>()),
      );
    }, busyBackend);
  });

  test('a non-busy 503 keeps the backend message (no false AI-busy)',
      () async {
    await http.runWithClient(() async {
      await expectLater(
        TripService().regenerateItinerary(1),
        throwsA(
          predicate(
            (e) => e is! AiBusyException && '$e'.contains('Maintenance'),
          ),
        ),
      );
    }, () => MockClient(
          (request) async => http.Response(
            '{"success":false,"message":"Maintenance"}',
            503,
            headers: {'content-type': 'application/json'},
          ),
        ));
  });

  test('planner.aiBusy is translated in all six languages', () {
    final english = AppLocalizations.resolve('planner.aiBusy', 'en');
    expect(english, contains('busy'));
    for (final code in ['es', 'fr', 'de', 'it', 'pt']) {
      final text = AppLocalizations.resolve('planner.aiBusy', code);
      expect(text, isNotEmpty, reason: code);
      expect(text, isNot(english), reason: '$code falls back to English');
    }
  });
}
