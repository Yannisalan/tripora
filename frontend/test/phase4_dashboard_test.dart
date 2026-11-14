// Tripora 2.0 (Phase 4) dashboard: the hero only shows real trip data,
// weather only when the backend returned a forecast, the Active Aura is a
// local preference, the AI command bar opens the real Planner (no fake AI),
// and the sidebar holds the brand, aura selector, theme switch and the
// user's real name. Runs against the in-memory fake backend.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:frontend/core/auth/auth_guard.dart';
import 'package:frontend/core/auth/token_store.dart';
import 'package:frontend/core/design/glass/glass_nav.dart';
import 'package:frontend/core/design/glass/glass_tokens.dart';
import 'package:frontend/core/preferences/active_aura.dart';
import 'package:frontend/core/preferences/app_preferences.dart';
import 'package:frontend/core/theme/app_theme.dart';
import 'package:frontend/core/theme/destination_accents.dart';
import 'package:frontend/data/destinations.dart';
import 'package:frontend/main.dart';
import 'package:frontend/screens/home/home_hero.dart';
import 'package:frontend/screens/main_shell.dart';
import 'package:frontend/screens/planner/planner_screen.dart';
import 'package:frontend/screens/trip_details.dart';
import 'package:frontend/widgets/theme_toggle.dart';

import 'support/contrast.dart';
import 'support/probe_harness.dart';

void main() {
  setUp(() {
    TokenStore.debugForceSecureStorage = false;
    TokenStore.instance.resetForTesting();
    ActiveAura.instance.resetForTesting();
  });
  tearDown(() async {
    TokenStore.debugForceSecureStorage = null;
    TokenStore.instance.resetForTesting();
    ActiveAura.instance.resetForTesting();
    MainShell.currentIndex.value = 0;
    await AppPreferences.instance.setThemeMode(ThemeMode.system);
  });

  Future<void> run(WidgetTester tester, Future<void> Function() body) =>
      http.runWithClient(body, fakeBackend);

  testWidgets('hero shows the next real trip: countdown, dates, weather', (
    tester,
  ) async {
    addTearDown(tester.view.reset);
    await run(tester, () async {
      await pumpShell(tester, const Size(1440, 900));
      await settle(tester);

      // Fake backend: the upcoming trip starts 2027-03-10 (Rio).
      final today = DateUtils.dateOnly(DateTime.now());
      final days = DateTime(2027, 3, 10).difference(today).inDays;
      final hero = find.byType(HomeHero);
      expect(hero, findsOneWidget);
      expect(
        find.descendant(
          of: hero,
          matching: find.text('$days days to departure'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: hero,
          matching: find.text('Rio de Janeiro, Brazil'),
        ),
        findsOneWidget,
      );
      // 5 days, from the trip's own dates.
      expect(
        find.descendant(of: hero, matching: find.textContaining('• 5 DAYS')),
        findsOneWidget,
      );
      // Weather from the (fake) weather endpoint: 31.5 / 22.1.
      expect(
        find.descendant(of: hero, matching: find.text('32° / 22°')),
        findsOneWidget,
      );
      expect(find.text('Open trip'), findsOneWidget);
    });
  });

  testWidgets('without trips the hero is a discovery card: no countdown', (
    tester,
  ) async {
    addTearDown(tester.view.reset);
    // No session: trips fail to load, so nothing trip-specific may show.
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    SharedPreferences.setMockInitialValues({});
    await run(tester, () async {
      await pumpShellSignedOut(tester);
      final hero = find.byType(HomeHero);
      expect(hero, findsOneWidget);
      expect(find.textContaining('to departure'), findsNothing);
      expect(find.textContaining('°'), findsNothing);
      expect(
        find.descendant(of: hero, matching: find.text('Featured destination')),
        findsOneWidget,
      );
      expect(find.text('Plan this trip'), findsOneWidget);
      // The sidebar profile card falls back to Guest.
      expect(
        find.descendant(
          of: find.byType(GlassSideNav),
          matching: find.text('Guest'),
        ),
        findsOneWidget,
      );
    });
  });

  testWidgets('accent card selects the Active Aura and persists it', (
    tester,
  ) async {
    addTearDown(tester.view.reset);
    await run(tester, () async {
      await pumpShell(tester, const Size(1440, 900));
      await settle(tester);

      final card = find.bySemanticsLabel(RegExp(r'^Venice, Italy, '));
      await tester.ensureVisible(card);
      await settle(tester);
      await tester.tap(card);
      await settle(tester);

      expect(ActiveAura.instance.destination?.city, 'Venice');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('active_aura_city'), 'Venice');
      // Drives the AI command bar (the sidebar selector was removed).
      expect(find.text('Plan Venice'), findsOneWidget);
    });
  });

  testWidgets('AI command bar opens the real Planner, prefilled', (
    tester,
  ) async {
    addTearDown(tester.view.reset);
    await run(tester, () async {
      await pumpShell(tester, const Size(1440, 900));
      await settle(tester);

      final field = find.byWidgetPredicate(
        (w) =>
            w is TextField &&
            (w.decoration?.hintText ?? '').contains('Tripora AI'),
      );
      expect(field, findsOneWidget);
      await tester.enterText(field, 'Lisbon, Portugal');
      await tester.tap(find.text('Open Planner'));
      await settle(tester);
      await tester.pump(const Duration(milliseconds: 600));

      final planner = tester.widget<PlannerScreen>(find.byType(PlannerScreen));
      expect(planner.initialDestination, 'Lisbon, Portugal');
    });
  });

  testWidgets('sidebar: wordmark, theme toggle, real user name', (
    tester,
  ) async {
    addTearDown(tester.view.reset);
    await run(tester, () async {
      await pumpShell(tester, const Size(1280, 900));
      await settle(tester);
      final side = find.byType(GlassSideNav);

      expect(
        find.descendant(of: side, matching: find.text('TRIPORA')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: side,
          matching: find.text('Maximiliana Rodrigues-Fernandes de Albuquerque'),
        ),
        findsOneWidget,
      );

      final before = AppPreferences.instance.themeMode;
      await tester.tap(find.byType(ThemeToggleRow));
      await settle(tester);
      expect(AppPreferences.instance.themeMode, isNot(before));
    });
  });

  testWidgets('no raw {placeholder} on any tab or trip details; real '
      'days-until status', (tester) async {
    addTearDown(tester.view.reset);
    final placeholder = RegExp(r'\{\w+\}');
    List<String> leaks() => [
      for (final e in find.byType(Text).evaluate())
        if (placeholder.hasMatch((e.widget as Text).data ?? ''))
          (e.widget as Text).data!,
    ];
    await run(tester, () async {
      await pumpShell(tester, const Size(1440, 900));
      for (var tab = 0; tab < 5; tab++) {
        MainShell.currentIndex.value = tab;
        await settle(tester);
        expect(leaks(), isEmpty, reason: 'tab $tab');
      }

      // My Trips status pill: days until departure from the trip's own
      // start date, never the trip-count string.
      MainShell.currentIndex.value = 3;
      await settle(tester);
      final days = DateTime(
        2027,
        3,
        10,
      ).difference(DateUtils.dateOnly(DateTime.now())).inDays;
      expect(find.text('Starts in $days days'), findsWidgets);
      expect(find.textContaining('upcoming trip'), findsNothing);
      expect(find.text('5 days'), findsWidgets); // 10-14 March
      expect(find.text('Travelers'), findsWidgets);

      // Trip details (same placeholder bug class).
      AuthGuard.navigatorKey.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) => TripDetailsScreen(trip: sampleTrip()),
        ),
      );
      await settle(tester);
      await tester.pump(const Duration(milliseconds: 400));
      expect(leaks(), isEmpty, reason: 'trip details');
    });
  });

  group('brand crimson AA variants', () {
    test('white on crimsonDeep and crimsonDeep on white >= 4.5', () {
      expect(
        contrastRatio(Colors.white, TriporaBrand.crimsonDeep),
        greaterThan(4.5),
      );
      expect(
        contrastRatio(TriporaBrand.crimsonDeep, const Color(0xFFE7EDFF)),
        greaterThan(4.5),
      );
    });
    test('muted grey #9296A8 >= 4.5 on navy glass, under the highlight', () {
      final glass = AppTheme.darkTheme.extension<GlassTheme>()!;
      expect(AppColorsDark.textMuted, TriporaBrand.mutedGrey);
      for (final backdrop in const [
        TriporaBrand.navy,
        TriporaBrand.midnight,
        TriporaBrand.slate,
      ]) {
        for (final tint in [glass.tint, glass.tintStrong]) {
          // Top-left of the panel: fill at 1.3x alpha + full highlight.
          final fill = tint.withValues(alpha: (tint.a * 1.3).clamp(0.0, 1.0));
          final lit = Color.alphaBlend(
            glass.highlight,
            Color.alphaBlend(fill, backdrop),
          );
          expect(
            contrastRatio(TriporaBrand.mutedGrey, lit),
            greaterThanOrEqualTo(4.5),
            reason: 'on ${hex(lit)}',
          );
        }
      }
    });
    test('crimsonBright on every navy surface >= 4.5', () {
      for (final bg in const [
        TriporaBrand.navy,
        TriporaBrand.midnight,
        TriporaBrand.slate,
      ]) {
        expect(contrastRatio(TriporaBrand.crimsonBright, bg), greaterThan(4.5));
      }
    });
    // Explicit accents: every mapping keeps its 3:1 non-text contrast.
    test('explicit destination accents reach 3:1 in both modes', () {
      for (final entry in DestinationAccents.byCity.entries) {
        final a = entry.value;
        for (final bg in const [Color(0xFF111729), Color(0xFF22263A)]) {
          expect(
            contrastRatio(a.dark, bg),
            greaterThanOrEqualTo(3),
            reason: entry.key,
          );
        }
        for (final bg in const [Colors.white, Color(0xFFE7EDFF)]) {
          expect(
            contrastRatio(a.light, bg),
            greaterThanOrEqualTo(3),
            reason: entry.key,
          );
        }
      }
    });

    // The approved palette is frozen: exactly the original 22 mappings, no
    // new (arbitrary) values for the Phase 2 destinations.
    test('accent mapping is unchanged (22 approved entries)', () {
      expect(DestinationAccents.byCity.length, 22);
      for (final city in DestinationAccents.byCity.keys) {
        expect(
          destinations.any((d) => d.city == city),
          isTrue,
          reason: '$city maps to a real destination',
        );
      }
    });

    // Destinations without a mapping use the brand crimson fallback, which
    // itself meets the same safeguards (crimson 4.25+ on navy surfaces,
    // crimsonDeep 5.41 on white).
    test('unmapped destinations fall back to brand crimson', () {
      final unmapped = destinations
          .where((d) => !DestinationAccents.byCity.containsKey(d.city))
          .toList();
      expect(unmapped.map((d) => d.city).toSet(), {
        'Marrakech',
        'Nairobi',
        'Zanzibar',
        'Cairo',
        'Auckland',
        'Melbourne',
        'Lisbon',
        'Athens',
      });
      for (final d in unmapped) {
        final a = DestinationAccents.forDestination(d);
        expect(identical(a, DestinationAccents.brand), isTrue, reason: d.city);
        expect(a.dark, TriporaBrand.crimson);
        expect(a.light, TriporaBrand.crimsonDeep);
      }
      final brand = DestinationAccents.brand;
      for (final bg in const [Color(0xFF111729), Color(0xFF22263A)]) {
        expect(contrastRatio(brand.dark, bg), greaterThanOrEqualTo(3));
      }
      for (final bg in const [Colors.white, Color(0xFFE7EDFF)]) {
        expect(contrastRatio(brand.light, bg), greaterThanOrEqualTo(3));
      }
    });
  });
}

/// The shell with no stored session (guest).
Future<void> pumpShellSignedOut(WidgetTester tester) async {
  MainShell.currentIndex.value = 0;
  await tester.pumpWidget(const TriporaApp());
  await tester.pump(const Duration(milliseconds: 1500));
  await tester.pump(const Duration(milliseconds: 600));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
  await settle(tester);
}
