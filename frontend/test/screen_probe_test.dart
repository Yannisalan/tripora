// Responsive layout probe: pumps every reachable screen at the Phase 2
// widths, in all six languages and at 1.3x text, and fails on any layout
// error (RenderFlex overflow, unbounded constraints, ...). Each failure is
// reported with the source location Flutter blames, so a regression points
// straight at the widget that broke.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:frontend/core/auth/auth_guard.dart';
import 'package:frontend/core/auth/token_store.dart';
import 'package:frontend/core/preferences/app_preferences.dart';
import 'package:frontend/screens/main_shell.dart';

import 'support/probe_harness.dart';

Future<void> probeEverything(
  WidgetTester tester,
  ProbeErrors errors, {
  required String label,
  required List<double> widths,
  double height = 900,
  bool landscape = false,
}) async {
  for (final width in widths) {
    final size = landscape ? Size(width, width * 0.46) : Size(width, height);
    tester.view.physicalSize = size;
    await settle(tester);

    for (final tab in probeTabs.entries) {
      MainShell.currentIndex.value = tab.key;
      await settle(tester);
      drainErrors(
        tester,
        errors,
        '$label ${tab.value} @${size.width.toInt()}x${size.height.toInt()}',
      );
    }
    MainShell.currentIndex.value = 0;

    for (final screen in probeScreens.entries) {
      AuthGuard.navigatorKey.currentState!.push(
        MaterialPageRoute<void>(builder: screen.value),
      );
      await settle(tester);
      await tester.pump(const Duration(milliseconds: 400));
      drainErrors(
        tester,
        errors,
        '$label ${screen.key} @${size.width.toInt()}x${size.height.toInt()}',
      );
      AuthGuard.navigatorKey.currentState!.pop();
      await settle(tester);
      await tester.pump(const Duration(milliseconds: 400));
    }
  }
}

void main() {
  setUp(() {
    TokenStore.debugForceSecureStorage = false;
    TokenStore.instance.resetForTesting();
  });
  tearDownAll(() {
    for (final e in ProbeErrors.firstDetails.entries) {
      // ignore: avoid_print
      print('##### ${e.key}\n${e.value}');
    }
  });
  tearDown(() async {
    TokenStore.debugForceSecureStorage = null;
    TokenStore.instance.resetForTesting();
    MainShell.currentIndex.value = 0;
  });

  for (final lang in probeLanguages) {
    testWidgets('all screens clean at every width ($lang)', (tester) async {
      addTearDown(tester.view.reset);
      final found = await collectErrors(tester, (errors) async {
        await pumpShell(tester, const Size(390, 844));
        await AppPreferences.instance.setLanguage(lang);
        await settle(tester);
        await probeEverything(tester, errors, label: lang, widths: probeWidths);
        await AppPreferences.instance.setLanguage('en');
        await settle(tester);
      });
      expect(found, isEmpty, reason: found.toSet().join('\n'));
    });
  }

  testWidgets('all screens clean in landscape', (tester) async {
    addTearDown(tester.view.reset);
    final found = await collectErrors(tester, (errors) async {
      await pumpShell(tester, const Size(844, 390));
      await probeEverything(
        tester,
        errors,
        label: 'landscape',
        widths: const [568, 740, 844, 932, 1180],
        landscape: true,
      );
    });
    expect(found, isEmpty, reason: found.toSet().join('\n'));
  });

  for (final lang in const ['en', 'de', 'fr', 'pt']) {
    testWidgets('all screens clean at 1.3x text ($lang)', (tester) async {
      addTearDown(tester.view.reset);
      tester.platformDispatcher.textScaleFactorTestValue = 1.3;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final found = await collectErrors(tester, (errors) async {
        await pumpShell(tester, const Size(390, 844));
        await AppPreferences.instance.setLanguage(lang);
        await settle(tester);
        await probeEverything(
          tester,
          errors,
          label: '$lang@1.3x',
          widths: const [320, 390, 768, 1024, 1440],
        );
        await AppPreferences.instance.setLanguage('en');
        await settle(tester);
      });
      expect(found, isEmpty, reason: found.toSet().join('\n'));
    });
  }
}
