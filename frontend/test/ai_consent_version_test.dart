import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:frontend/core/auth/auth_guard.dart';
import 'package:frontend/core/auth/token_store.dart';
import 'package:frontend/core/l10n/app_localizations.dart';
import 'package:frontend/core/preferences/app_preferences.dart';
import 'package:frontend/screens/planner/planner_screen.dart';
import 'package:frontend/screens/trip_details.dart';

import 'support/probe_harness.dart';

/// Versioned AI consent (`ai_consent_v2`): an acceptance of the earlier
/// disclosure never counts, every AI entry point asks first, and declining
/// sends nothing to the AI provider.
void main() {
  const v2 = AppPreferences.aiConsentKey;
  const v1 = AppPreferences.legacyAiConsentKey;
  const languages = ['en', 'es', 'fr', 'de', 'it', 'pt'];

  setUp(() => TestWidgetsFlutterBinding.ensureInitialized());

  // ------------------------------------------------------------------
  // Storage: new / existing users, acceptance, restarts
  // ------------------------------------------------------------------

  group('consent storage', () {
    test('key is versioned', () {
      expect(v2, 'ai_consent_v2');
      expect(v1, 'ai_consent_given');
    });

    test('new user: no consent', () async {
      SharedPreferences.setMockInitialValues({});
      await AppPreferences.instance.load();
      expect(AppPreferences.instance.aiConsentGiven, isFalse);
    });

    test('existing user who accepted v1 must accept again', () async {
      SharedPreferences.setMockInitialValues({v1: true});
      await AppPreferences.instance.load();
      expect(AppPreferences.instance.aiConsentGiven, isFalse);
    });

    test('accepting stores v2 and survives a restart', () async {
      SharedPreferences.setMockInitialValues({v1: true});
      await AppPreferences.instance.load();

      await AppPreferences.instance.setAiConsentGiven(true);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool(v2), isTrue);
      // The legacy value is left as it was, and still not trusted.
      expect(prefs.getBool(v1), isTrue);

      // Simulated restart: state is rebuilt from storage only.
      SharedPreferences.setMockInitialValues({v1: true, v2: true});
      await AppPreferences.instance.load();
      expect(AppPreferences.instance.aiConsentGiven, isTrue);
    });

    test('a stored v2 decline (false) stays declined after restart', () async {
      SharedPreferences.setMockInitialValues({v2: false});
      await AppPreferences.instance.load();
      expect(AppPreferences.instance.aiConsentGiven, isFalse);
    });
  });

  // ------------------------------------------------------------------
  // ensureAiConsent: dialog, accept / decline, all six languages
  // ------------------------------------------------------------------

  Future<List<bool>> pumpGate(WidgetTester tester) async {
    final results = <bool>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () async =>
                    results.add(await ensureAiConsent(context)),
                child: const Text('go'),
              ),
            ),
          ),
        ),
      ),
    );
    return results;
  }

  for (final lang in languages) {
    group('[$lang]', () {
      setUp(() async {
        // Existing user: accepted the old disclosure, language set.
        SharedPreferences.setMockInitialValues({
          v1: true,
          'preferred_language': lang,
        });
        await AppPreferences.instance.load();
        expect(AppPreferences.instance.language, lang);
      });

      testWidgets('existing user sees the new disclosure and can accept',
          (tester) async {
        final results = await pumpGate(tester);

        await tester.tap(find.text('go'));
        await tester.pumpAndSettle();

        expect(find.byType(AlertDialog), findsOneWidget);
        expect(
          find.text(AppLocalizations.resolve('planner.aiDisclosureBody', lang)),
          findsOneWidget,
        );
        await tester.tap(find.text(
          AppLocalizations.resolve('planner.aiDisclosureConfirm', lang),
        ));
        await tester.pumpAndSettle();

        expect(results, [true]);
        expect(AppPreferences.instance.aiConsentGiven, isTrue);
        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getBool(v2), isTrue);

        // Accepted: no dialog the next time.
        await tester.tap(find.text('go'));
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog), findsNothing);
        expect(results, [true, true]);
      });

      testWidgets('declining blocks AI and asks again next time',
          (tester) async {
        final results = await pumpGate(tester);

        await tester.tap(find.text('go'));
        await tester.pumpAndSettle();
        await tester.tap(find.text(
          AppLocalizations.resolve('planner.aiDisclosureDecline', lang),
        ));
        await tester.pumpAndSettle();

        expect(results, [false]);
        expect(AppPreferences.instance.aiConsentGiven, isFalse);
        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getBool(v2), isNot(true));

        await tester.tap(find.text('go'));
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog), findsOneWidget);
      });
    });
  }

  testWidgets('new user is asked; v2-accepted user is not', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await AppPreferences.instance.load();
    // The singleton keeps the last group's language; this test reads English.
    await AppPreferences.instance.setLanguage('en');
    final results = await pumpGate(tester);

    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    await tester.tap(find.text(
      AppLocalizations.resolve('planner.aiDisclosureConfirm', 'en'),
    ));
    await tester.pumpAndSettle();
    expect(results, [true]);

    SharedPreferences.setMockInitialValues({v2: true});
    await AppPreferences.instance.load();
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(results, [true, true]);
  });

  // ------------------------------------------------------------------
  // Real entry point: swapping an activity in Trip details
  // ------------------------------------------------------------------

  testWidgets('trip swap: declining sends nothing; accepting proceeds',
      (tester) async {
    addTearDown(tester.view.reset);
    // In-memory token storage, as the other shell tests use (the secure
    // storage plugin is unavailable in widget tests).
    TokenStore.debugForceSecureStorage = false;
    TokenStore.instance.resetForTesting();
    addTearDown(() => TokenStore.debugForceSecureStorage = null);
    final swapRequests = <String>[];
    final inner = fakeBackend();
    http.Client backend() => MockClient((request) async {
          if (request.url.path.endsWith('/swap-activity')) {
            swapRequests.add(request.url.path);
          }
          final copy = http.Request(request.method, request.url)
            ..headers.addAll(request.headers);
          copy.bodyBytes = request.bodyBytes;
          return http.Response.fromStream(await inner.send(copy));
        });

    await http.runWithClient(() async {
      await pumpShell(tester, const Size(1440, 900));

      // Existing user whose only acceptance is the old (v1) one: v2 not
      // accepted (the storage tests above prove v1 is ignored on load).
      await AppPreferences.instance.setLanguage('en');
      await AppPreferences.instance.setAiConsentGiven(false);
      expect(AppPreferences.instance.aiConsentGiven, isFalse);

      AuthGuard.navigatorKey.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) => TripDetailsScreen(trip: sampleTrip()),
        ),
      );
      await settle(tester);
      await tester.pump(const Duration(milliseconds: 600));

      final swap = find.byIcon(Icons.swap_horiz).first;
      await tester.ensureVisible(swap);
      await settle(tester);

      // Decline: no request reaches the backend.
      await tester.tap(swap);
      await settle(tester);
      expect(find.text(
        AppLocalizations.resolve('planner.aiDisclosureBody', 'en'),
      ), findsOneWidget);
      await tester.tap(find.text(
        AppLocalizations.resolve('planner.aiDisclosureDecline', 'en'),
      ));
      await settle(tester);
      expect(swapRequests, isEmpty);
      expect(AppPreferences.instance.aiConsentGiven, isFalse);

      // Accept: the swap request is sent.
      await tester.tap(swap);
      await settle(tester);
      await tester.tap(find.text(
        AppLocalizations.resolve('planner.aiDisclosureConfirm', 'en'),
      ));
      await settle(tester);
      await tester.pump(const Duration(milliseconds: 600));
      expect(swapRequests, hasLength(1));
      expect(AppPreferences.instance.aiConsentGiven, isTrue);
    }, backend);
  });
}
