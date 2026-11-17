// Phase 2 responsiveness and fluidity fixes (R1-R10, F1-F5), against the
// in-memory fake backend.
import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:frontend/core/auth/auth_guard.dart';
import 'package:frontend/core/auth/token_store.dart';
import 'package:frontend/core/preferences/app_preferences.dart';
import 'package:frontend/core/theme/app_theme.dart';
import 'package:frontend/screens/main_shell.dart';
import 'package:frontend/screens/planner/planner_screen.dart';
import 'package:frontend/screens/trip_details.dart';
import 'package:frontend/services/auth_service.dart';
import 'package:frontend/services/trip_service.dart';
import 'package:frontend/widgets/adaptive_grid.dart';
import 'package:frontend/widgets/destination_image.dart';

import 'support/probe_harness.dart';

/// Fake backend that counts requests per "METHOD /path" and can delay
/// responses (so concurrent callers really overlap).
class CountingBackend {
  CountingBackend({this.delay = Duration.zero, this.failTrips = false});

  final Duration delay;
  bool failTrips;
  final Map<String, int> counts = {};
  final http.Client _inner = fakeBackend();

  int of(String key) => counts[key] ?? 0;

  http.Client client() => MockClient((request) async {
    final key = '${request.method} ${request.url.path}';
    counts[key] = (counts[key] ?? 0) + 1;
    if (delay > Duration.zero) await Future<void>.delayed(delay);
    if (failTrips && key == 'GET /api/trips') {
      return http.Response('{"success":false,"message":"boom"}', 500);
    }
    // Forward a fresh copy: a request can only be finalized once.
    final copy = http.Request(request.method, request.url)
      ..headers.addAll(request.headers);
    copy.bodyBytes = request.bodyBytes;
    return http.Response.fromStream(await _inner.send(copy));
  });
}

int daysToSampleTrip() =>
    DateTime(2027, 3, 10).difference(DateUtils.dateOnly(DateTime.now())).inDays;

void main() {
  setUp(() {
    TokenStore.debugForceSecureStorage = false;
    TokenStore.instance.resetForTesting();
  });
  tearDown(() async {
    TokenStore.debugForceSecureStorage = null;
    TokenStore.instance.resetForTesting();
    MainShell.currentIndex.value = 0;
    await AppPreferences.instance.setLanguage('en');
  });

  // -------------------------------------------------------------------
  // F1 - one countdown everywhere
  // -------------------------------------------------------------------

  testWidgets('F1: Home, My Trips and Trip details show the same countdown', (
    tester,
  ) async {
    addTearDown(tester.view.reset);
    await http.runWithClient(() async {
      await pumpShell(tester, const Size(1440, 900));
      final n = daysToSampleTrip();

      expect(find.text('$n days to departure'), findsOneWidget);

      MainShell.currentIndex.value = 3;
      await settle(tester);
      expect(find.text('Starts in $n days'), findsWidgets);

      AuthGuard.navigatorKey.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) => TripDetailsScreen(trip: sampleTrip()),
        ),
      );
      await settle(tester);
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.text('Starts in $n days'), findsWidgets);
    }, fakeBackend);
  });

  // -------------------------------------------------------------------
  // F2 - in-flight request sharing
  // -------------------------------------------------------------------

  testWidgets('F2: app start-up loads trips and the account once each', (
    tester,
  ) async {
    addTearDown(tester.view.reset);
    final backend = CountingBackend(delay: const Duration(milliseconds: 50));
    await http.runWithClient(() async {
      await pumpShell(tester, const Size(1440, 900));
      await settle(tester);
    }, backend.client);
    expect(backend.of('GET /api/trips'), 1, reason: '${backend.counts}');
    expect(backend.of('GET /api/auth/me'), 1, reason: '${backend.counts}');
  });

  group('F2: sharing is only for concurrent calls', () {
    setUp(() async {
      TestWidgetsFlutterBinding.ensureInitialized();
      SharedPreferences.setMockInitialValues({});
      await TokenStore.instance.saveSession(
        accessToken: 'test-token',
        refreshToken: 'test-refresh',
      );
    });

    test('trips: concurrent share one request, independent copies; '
        'a later call (refresh) fetches again', () async {
      final backend = CountingBackend(delay: const Duration(milliseconds: 30));
      await http.runWithClient(() async {
        final a = TripService().getTrips();
        final b = TripService().getTrips();
        final results = await Future.wait([a, b]);
        expect(backend.of('GET /api/trips'), 1);
        expect(identical(results[0], results[1]), isFalse);
        results[0].clear();
        expect(results[1], isNotEmpty);

        await TripService().getTrips();
        expect(backend.of('GET /api/trips'), 2);
      }, backend.client);
    });

    test('trips: a failed request is not cached', () async {
      final backend = CountingBackend(
        delay: const Duration(milliseconds: 20),
        failTrips: true,
      );
      await http.runWithClient(() async {
        final a = TripService().getTrips();
        final b = TripService().getTrips();
        await expectLater(a, throwsA(anything));
        await expectLater(b, throwsA(anything));
        expect(backend.of('GET /api/trips'), 1);

        backend.failTrips = false;
        expect(await TripService().getTrips(), isNotEmpty);
        expect(backend.of('GET /api/trips'), 2);
      }, backend.client);
    });

    test(
      'account: concurrent share one request; later calls refetch',
      () async {
        final backend = CountingBackend(
          delay: const Duration(milliseconds: 30),
        );
        await http.runWithClient(() async {
          final results = await Future.wait([
            AuthService().getCurrentUser(),
            AuthService().getCurrentUser(),
          ]);
          expect(backend.of('GET /api/auth/me'), 1);
          (results[0]['user'] as Map)['name'] = 'changed';
          expect((results[1]['user'] as Map)['name'], isNot('changed'));

          await AuthService().getCurrentUser();
          expect(backend.of('GET /api/auth/me'), 2);
        }, backend.client);
      },
    );
  });

  // -------------------------------------------------------------------
  // F3 - pages are not rebuilt on tab switches
  // -------------------------------------------------------------------

  testWidgets('F3: tab switches reuse the page widgets; a language change '
      'rebuilds them; tab state survives', (tester) async {
    addTearDown(tester.view.reset);
    await http.runWithClient(() async {
      await pumpShell(tester, const Size(1440, 900));
      List<Widget> pages() =>
          tester.widget<IndexedStack>(find.byType(IndexedStack).first).children;

      final before = pages();
      for (final tab in [1, 3, 0, 4, 2]) {
        MainShell.currentIndex.value = tab;
        await settle(tester);
      }
      final after = pages();
      for (var i = 0; i < before.length; i++) {
        expect(identical(before[i], after[i]), isTrue, reason: 'page $i');
      }

      await AppPreferences.instance.setLanguage('fr');
      await settle(tester);
      expect(identical(pages().first, before.first), isFalse);
      expect(find.text('Accueil'), findsWidgets); // French nav label
      expect(MainShell.currentIndex.value, 2); // still on the same tab
    }, fakeBackend);
  });

  // -------------------------------------------------------------------
  // F4 - destination images
  // -------------------------------------------------------------------

  testWidgets('F4: placeholder while loading, calm error state on failure', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme,
        home: const Center(
          child: SizedBox(
            width: 300,
            height: 200,
            child: DestinationImage(
              url: 'https://example.invalid/missing.jpg',
              placeholder: ColoredBox(key: Key('ph'), color: Colors.black),
            ),
          ),
        ),
      ),
    );
    // Loading: the placeholder is on screen, the photo is still invisible.
    expect(find.byKey(const Key('ph')), findsOneWidget);

    // Network images fail in widget tests (HTTP 400): the error state is
    // the placeholder plus an icon, never an exception.
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 300)),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('ph')), findsOneWidget);
    expect(find.byIcon(Icons.image_not_supported_outlined), findsOneWidget);
  });

  // -------------------------------------------------------------------
  // F5 - page transitions
  // -------------------------------------------------------------------

  test('F5: one restrained transition; iOS/macOS keep swipe-back', () {
    for (final theme in [AppTheme.lightTheme, AppTheme.darkTheme]) {
      final b = theme.pageTransitionsTheme.builders;
      for (final p in [
        TargetPlatform.android,
        TargetPlatform.linux,
        TargetPlatform.windows,
        TargetPlatform.fuchsia,
      ]) {
        expect(b[p], isA<FadeForwardsPageTransitionsBuilder>(), reason: '$p');
      }
      expect(b[TargetPlatform.iOS], isA<CupertinoPageTransitionsBuilder>());
      expect(b[TargetPlatform.macOS], isA<CupertinoPageTransitionsBuilder>());
    }
  });

  // -------------------------------------------------------------------
  // R2, R4, R5, R8, R10 - layout
  // -------------------------------------------------------------------

  testWidgets('R2: hero actions sit below the title, grouped on the left', (
    tester,
  ) async {
    addTearDown(tester.view.reset);
    await http.runWithClient(() async {
      // Every width: title, description and actions form one left-aligned
      // block (wide heroes no longer push the actions to the far right).
      for (final width in const [700.0, 1024.0, 1280.0, 1920.0]) {
        await pumpShell(tester, Size(width, 1000));
        final title = tester.getRect(find.text('Rio de Janeiro, Brazil').first);
        final action = tester.getRect(
          find
              .ancestor(
                of: find.text('Open trip'),
                matching: find.byWidgetPredicate((w) => w is FilledButton),
              )
              .first,
        );
        expect(action.top, greaterThan(title.bottom), reason: '$width');
        expect(
          action.left,
          moreOrLessEquals(title.left, epsilon: 1),
          reason: '$width',
        );
      }
    }, fakeBackend);
  });

  testWidgets('R4: My Trips is one column below 768 px of content, two above', (
    tester,
  ) async {
    addTearDown(tester.view.reset);
    await http.runWithClient(() async {
      // 768-839 px windows: the 72 px rail leaves under 768 px of content,
      // so the list stays one column until the cards have room.
      for (final (width, columns) in const [
        (600.0, 1),
        (768.0, 1),
        (840.0, 2),
      ]) {
        await pumpShell(tester, Size(width, 1400));
        MainShell.currentIndex.value = 3;
        await settle(tester);
        final a = tester.getTopLeft(find.text('Rio de Janeiro, Brazil').last);
        final b = tester.getTopLeft(
          find.text('Saint-Jean-de-Luz, Pyrénées-Atlantiques, France').last,
        );
        if (columns == 1) {
          expect(a.dx, b.dx, reason: '$width: same column');
        } else {
          expect(a.dx, isNot(b.dx), reason: '$width: side by side');
        }
      }
    }, fakeBackend);
  });

  testWidgets('R5: Flights date toggle drops its icons below 380 px', (
    tester,
  ) async {
    addTearDown(tester.view.reset);
    await http.runWithClient(() async {
      for (final (width, icons) in const [(360.0, false), (430.0, true)]) {
        await pumpShell(tester, Size(width, 900));
        MainShell.currentIndex.value = 2;
        await settle(tester);
        final toggle = find.byType(SegmentedButton<String>);
        expect(toggle, findsOneWidget);
        expect(
          find.descendant(
            of: toggle,
            // The unselected segment (the selected one shows a tick).
            matching: find.byIcon(Icons.date_range_outlined),
          ),
          icons ? findsOneWidget : findsNothing,
          reason: '$width',
        );
      }
    }, fakeBackend);
  });

  testWidgets('R8: Planner traveler tiles are capped on desktop', (
    tester,
  ) async {
    addTearDown(tester.view.reset);
    await http.runWithClient(() async {
      await pumpShell(tester, const Size(1440, 900));
      AuthGuard.navigatorKey.currentState!.push(
        MaterialPageRoute<void>(builder: (_) => const PlannerScreen()),
      );
      await settle(tester);
      await tester.pump(const Duration(milliseconds: 600));
      final grid = find.ancestor(
        of: find.text('Solo'),
        matching: find.byType(AdaptiveGrid),
      );
      // Two rows of two tiles, 12 px apart, each at most ~150 px tall
      // (a row may still grow when its content needs more).
      expect(tester.getSize(grid).height, lessThanOrEqualTo(2 * 170 + 12));
    }, fakeBackend);
  });

  testWidgets('R10: Trip details header uses the navy brand panel', (
    tester,
  ) async {
    addTearDown(tester.view.reset);
    await http.runWithClient(() async {
      await pumpShell(tester, const Size(1280, 900));
      AuthGuard.navigatorKey.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) => TripDetailsScreen(trip: sampleTrip()),
        ),
      );
      await settle(tester);
      await tester.pump(const Duration(milliseconds: 600));
      bool panel(Widget w, Color c) =>
          w is Container &&
          w.decoration is BoxDecoration &&
          (w.decoration! as BoxDecoration).color == c;
      expect(
        find.byWidgetPredicate((w) => panel(w, TriporaBrand.midnight)),
        findsWidgets,
      );
      expect(
        find.byWidgetPredicate((w) => panel(w, const Color(0xFF070235))),
        findsNothing,
      );
    }, fakeBackend);
  });

  // -------------------------------------------------------------------
  // R6, R7, R9 - touch targets
  // -------------------------------------------------------------------

  testWidgets('R6/R7/R9: 48 px touch targets on the audited screens', (
    tester,
  ) async {
    addTearDown(tester.view.reset);
    final handle = tester.ensureSemantics();
    await http.runWithClient(() async {
      for (final width in const [320.0, 390.0, 768.0, 1440.0]) {
        await pumpShell(tester, Size(width, 900));
        for (final tab in [0, 1, 4]) {
          MainShell.currentIndex.value = tab;
          await settle(tester);
          await expectLater(
            tester,
            meetsGuideline(androidTapTargetGuideline),
            reason: 'tab $tab @$width',
          );
        }
        MainShell.currentIndex.value = 0;
        for (final screen in ['planner', 'register']) {
          AuthGuard.navigatorKey.currentState!.push(
            MaterialPageRoute<void>(builder: probeScreens[screen]!),
          );
          await settle(tester);
          await tester.pump(const Duration(milliseconds: 600));
          await expectLater(
            tester,
            meetsGuideline(androidTapTargetGuideline),
            reason: '$screen @$width',
          );
          AuthGuard.navigatorKey.currentState!.pop();
          await settle(tester);
          await tester.pump(const Duration(milliseconds: 600));
        }
      }
    }, fakeBackend);
    handle.dispose();
  });

  testWidgets('R6: phone Profile appearance selector spans the card', (
    tester,
  ) async {
    addTearDown(tester.view.reset);
    await http.runWithClient(() async {
      await pumpShell(tester, const Size(320, 900));
      MainShell.currentIndex.value = 4;
      await settle(tester);
      final selector = find.byType(SegmentedButton<ThemeMode>);
      await tester.ensureVisible(selector);
      await settle(tester);
      // Not scaled down (no FittedBox) and almost the full content width.
      expect(
        find.ancestor(of: selector, matching: find.byType(FittedBox)),
        findsNothing,
      );
      expect(tester.getSize(selector).width, greaterThan(320 - 2 * 16 - 40));
    }, fakeBackend);
  });
}
