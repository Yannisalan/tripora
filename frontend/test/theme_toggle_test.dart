// Sidebar cleanup + direct Light/Dark switching.
//
// - One tap always flips the theme ON SCREEN (also when the stored setting
//   is System), for guests and signed-in users, at desktop and mobile widths.
// - The whole app follows; the choice persists across a restart.
// - Navigation state, typed input and loaded data survive a switch.
// - The sidebar shows only the TRIPORA wordmark (no Active Aura selector,
//   mark, version badge or subtitle).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:frontend/core/auth/token_store.dart';
import 'package:frontend/core/design/glass/glass_nav.dart';
import 'package:frontend/core/preferences/active_aura.dart';
import 'package:frontend/core/preferences/app_preferences.dart';
import 'package:frontend/main.dart';
import 'package:frontend/screens/main_shell.dart';
import 'package:frontend/widgets/active_aura_selector.dart';
import 'package:frontend/widgets/theme_toggle.dart';
import 'package:frontend/widgets/tripora_brand.dart';
import 'package:frontend/data/destinations.dart';
import 'package:frontend/screens/home/home_hero.dart';

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

  Future<void> run(Future<void> Function() body) =>
      http.runWithClient(body, fakeBackend);

  /// Brightness of the theme actually applied to the app content.
  Brightness onScreen(WidgetTester tester) =>
      Theme.of(tester.element(find.byType(MainShell))).brightness;

  Future<void> pumpGuest(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    MainShell.currentIndex.value = 0;
    await tester.pumpWidget(const TriporaApp());
    await tester.pump(const Duration(milliseconds: 1500));
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await settle(tester);
  }

  /// Taps whichever toggle the layout shows (sidebar row or app-bar button).
  Future<void> tapToggle(WidgetTester tester) async {
    final row = find.byType(ThemeToggleRow);
    await tester.tap(
      row.evaluate().isNotEmpty ? row : find.byType(ThemeToggleButton),
    );
    await settle(tester);
    await tester.pump(const Duration(milliseconds: 400)); // theme animation
  }

  /// Simulates an app restart: the app is torn down, storage keeps what
  /// was written, and startup reads it back (as main() does).
  Future<void> restart(WidgetTester tester, Size size, bool signedIn) async {
    final prefs = await SharedPreferences.getInstance();
    final stored = {for (final k in prefs.getKeys()) k: prefs.get(k)!};
    await tester.pumpWidget(const SizedBox());
    // Scramble the in-memory value so only storage can restore it.
    await AppPreferences.instance.setThemeMode(ThemeMode.system);
    SharedPreferences.setMockInitialValues(stored.cast<String, Object>());
    await AppPreferences.instance.load();
    if (signedIn) {
      await TokenStore.instance.saveSession(
        accessToken: 'test-token',
        refreshToken: 'test-refresh',
      );
    }
    await pumpGuest(tester, size);
  }

  for (final signedIn in [false, true]) {
    final who = signedIn ? 'signed-in user' : 'guest';
    for (final size in const [Size(1440, 900), Size(390, 844)]) {
      final where = size.width >= 1024 ? 'desktop' : 'mobile';

      testWidgets('$who, $where: Light -> Dark -> Light, persists', (
        tester,
      ) async {
        addTearDown(tester.view.reset);
        await run(() async {
          SharedPreferences.setMockInitialValues({});
          await AppPreferences.instance.setThemeMode(ThemeMode.light);
          if (signedIn) {
            await pumpShell(tester, size, themeMode: null);
          } else {
            await pumpGuest(tester, size);
          }
          expect(onScreen(tester), Brightness.light);

          await tapToggle(tester);
          expect(onScreen(tester), Brightness.dark);
          expect(AppPreferences.instance.themeMode, ThemeMode.dark);
          var prefs = await SharedPreferences.getInstance();
          expect(prefs.getString('preferred_theme_mode'), 'dark');

          await restart(tester, size, signedIn);
          expect(onScreen(tester), Brightness.dark, reason: 'after restart');

          await tapToggle(tester);
          expect(onScreen(tester), Brightness.light);
          prefs = await SharedPreferences.getInstance();
          expect(prefs.getString('preferred_theme_mode'), 'light');

          await restart(tester, size, signedIn);
          expect(onScreen(tester), Brightness.light, reason: 'after restart');
          expect(tester.takeException(), isNull);
        });
      });
    }
  }

  for (final os in Brightness.values) {
    testWidgets('System setting with an OS in $os: one tap changes it', (
      tester,
    ) async {
      addTearDown(tester.view.reset);
      tester.platformDispatcher.platformBrightnessTestValue = os;
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
      await run(() async {
        await pumpShell(tester, const Size(1440, 900));
        await AppPreferences.instance.setThemeMode(ThemeMode.system);
        await settle(tester);
        expect(onScreen(tester), os);
        // The control shows the theme it switches TO (from the theme on
        // screen), never a "System" state.
        final icon = os == Brightness.dark
            ? Icons.light_mode_outlined
            : Icons.dark_mode_outlined;
        expect(
          find.descendant(
            of: find.byType(ThemeToggleButton),
            matching: find.byIcon(icon),
          ),
          findsOneWidget,
        );
        expect(find.text('System'), findsNothing);

        await tapToggle(tester);
        expect(onScreen(tester), isNot(os));
      });
    });
  }

  testWidgets('switching keeps the tab, typed input and loaded data', (
    tester,
  ) async {
    addTearDown(tester.view.reset);
    await run(() async {
      await pumpShell(tester, const Size(1440, 900));

      // Loaded trips (My Trips) and typed search text (Explore).
      MainShell.currentIndex.value = 3;
      await settle(tester);
      expect(find.text('Rio de Janeiro, Brazil'), findsWidgets);
      MainShell.currentIndex.value = 1;
      await settle(tester);
      final search = find.byWidgetPredicate(
        (w) =>
            w is TextField &&
            (w.decoration?.hintText ?? '').startsWith('Search destinations'),
      );
      await tester.enterText(search, 'Lisbon');
      await settle(tester);

      final before = onScreen(tester);
      await tapToggle(tester);
      expect(onScreen(tester), isNot(before));

      expect(MainShell.currentIndex.value, 1);
      expect(tester.widget<TextField>(search).controller!.text, 'Lisbon');
      MainShell.currentIndex.value = 3;
      await settle(tester);
      expect(find.text('Rio de Janeiro, Brazil'), findsWidgets);
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('sidebar shows only the TRIPORA wordmark', (tester) async {
    addTearDown(tester.view.reset);
    await run(() async {
      await pumpShell(tester, const Size(1280, 800));
      final side = find.byType(GlassSideNav);
      Finder inSide(Finder f) => find.descendant(of: side, matching: f);

      expect(inSide(find.text('TRIPORA')), findsOneWidget);
      expect(inSide(find.byType(ActiveAuraSelector)), findsNothing);
      expect(inSide(find.text('T')), findsNothing); // the old mark
      expect(inSide(find.text('2.0')), findsNothing);
      expect(inSide(find.text('AI travel companion')), findsNothing);
      expect(inSide(find.textContaining('ACTIVE AURA')), findsNothing);
      // Theme control and the rest of the sidebar are still there.
      expect(inSide(find.byType(ThemeToggleButton)), findsOneWidget);
      expect(inSide(find.text('Plan a Trip')), findsOneWidget);
    });
  });

  testWidgets('mobile Home app bar shows only the TRIPORA wordmark', (
    tester,
  ) async {
    addTearDown(tester.view.reset);
    await run(() async {
      for (final size in const [
        Size(390, 844),
        Size(320, 640),
        Size(767, 1024),
      ]) {
        await pumpShell(tester, size);
        final bar = find.byType(AppBar).first;
        Finder inBar(Finder f) => find.descendant(of: bar, matching: f);
        expect(inBar(find.byType(TriporaWordmark)), findsOneWidget);
        expect(inBar(find.text('TRIPORA')), findsOneWidget);
        expect(inBar(find.text('T')), findsNothing);
        expect(inBar(find.text('2.0')), findsNothing);
        expect(inBar(find.text('Tripora')), findsNothing);
        expect(inBar(find.byType(ThemeToggleButton)), findsOneWidget);
        expect(tester.takeException(), isNull, reason: '$size');
      }
    });
  });

  testWidgets('Active Aura: selector above the hero on mobile only', (
    tester,
  ) async {
    addTearDown(tester.view.reset);
    await run(() async {
      // Desktop: nowhere on screen (not in the sidebar, not on Home).
      await pumpShell(tester, const Size(1440, 900));
      expect(find.byType(ActiveAuraSelector), findsNothing);

      // Mobile: above the hero, and choosing from it still works.
      await pumpShell(tester, const Size(390, 844));
      final selector = find.byType(ActiveAuraSelector);
      expect(selector, findsOneWidget);
      expect(
        tester.getTopLeft(selector).dy,
        lessThan(tester.getTopLeft(find.byType(HomeHero)).dy),
      );
      await tester.tap(selector);
      await settle(tester);
      final venice = destinations.firstWhere((d) => d.city == 'Venice');
      await tester.tap(find.text(venice.fullName).last);
      await settle(tester);
      expect(ActiveAura.instance.destination?.city, 'Venice');
      expect(
        find.descendant(of: selector, matching: find.text('Venice, Italy')),
        findsOneWidget,
      );
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('active_aura_city'), 'Venice');
    });
  });
}
