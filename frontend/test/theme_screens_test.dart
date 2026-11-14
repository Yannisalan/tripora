// Every screen, in light and dark mode, at phone and desktop width: every
// visible text and icon must meet WCAG AA against the surface it is drawn
// on (see support/contrast_scanner.dart for what is measured and skipped).
// Also checks app-bar back arrows explicitly (a known dark-mode regression).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:frontend/core/auth/auth_guard.dart';
import 'package:frontend/core/auth/token_store.dart';
import 'package:frontend/core/preferences/app_preferences.dart';
import 'package:frontend/core/theme/app_theme.dart';
import 'package:frontend/main.dart';
import 'package:frontend/screens/expenses/expense_tracker_screen.dart';
import 'package:frontend/screens/main_shell.dart';
import 'package:frontend/screens/planner/planner_screen.dart';
import 'package:frontend/screens/travel/flight_search_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/contrast.dart';
import 'support/contrast_scanner.dart';
import 'support/probe_harness.dart';

const _sizes = [Size(390, 844), Size(1440, 900)];

void main() {
  setUp(() {
    TokenStore.debugForceSecureStorage = false;
    TokenStore.instance.resetForTesting();
  });
  tearDown(() {
    TokenStore.debugForceSecureStorage = null;
    TokenStore.instance.resetForTesting();
    MainShell.currentIndex.value = 0;
  });

  for (final mode in const [ThemeMode.light, ThemeMode.dark]) {
    final name = mode.name;
    final backdrop =
        (mode == ThemeMode.dark ? AppTheme.darkTheme : AppTheme.lightTheme)
            .extension<TriporaColors>()!
            .backgroundColor;

    testWidgets('all screens meet AA contrast ($name)', (tester) async {
      addTearDown(tester.view.reset);
      final issues = <String>{};
      var checked = 0, overPhoto = 0, disabled = 0, fields = 0;

      final theme = mode == ThemeMode.dark
          ? AppTheme.darkTheme
          : AppTheme.lightTheme;
      final surface = theme.extension<TriporaColors>()!.surface;

      void scan(String where) {
        final r = scanContrast(tester, backdrop: backdrop);
        checked += r.checked;
        overPhoto += r.overPhoto;
        disabled += r.disabled;
        for (final i in r.issues) {
          issues.add('$where: $i');
        }

        // Every enabled text field's effective outline (theme default or a
        // screen's own override) must be a >= 3:1 boundary (SC 1.4.11).
        for (final e in find.byType(InputDecorator).evaluate()) {
          final w = e.widget as InputDecorator;
          if (!w.decoration.enabled) continue;
          fields++;
          final d = w.decoration.applyDefaults(
            Theme.of(e).inputDecorationTheme,
          );
          final border = d.enabledBorder ?? d.border;
          if (border == null || border.borderSide.style == BorderStyle.none) {
            issues.add(
              '$where: text field without a visible outline '
              '(${w.decoration.labelText ?? w.decoration.hintText})',
            );
            continue;
          }
          final color = border.borderSide.color;
          for (final adj in [backdrop, surface]) {
            final ratio = contrastRatio(color, adj);
            if (ratio < 3.0) {
              issues.add(
                '$where: input outline ${hex(color)} on '
                '${hex(adj)} = ${ratio.toStringAsFixed(2)} '
                '(${w.decoration.labelText ?? w.decoration.hintText})',
              );
            }
          }
        }
      }

      final errors = await collectErrors(tester, (errors) async {
        await pumpShell(tester, _sizes.first, themeMode: mode);
        for (final size in _sizes) {
          tester.view.physicalSize = size;
          await settle(tester);
          for (final tab in probeTabs.entries) {
            MainShell.currentIndex.value = tab.key;
            await settle(tester);
            await tester.pump(const Duration(seconds: 1));
            scan('${tab.value} @${size.width.toInt()}');
          }
          MainShell.currentIndex.value = 0;
          for (final screen in probeScreens.entries) {
            AuthGuard.navigatorKey.currentState!.push(
              MaterialPageRoute<void>(builder: screen.value),
            );
            await settle(tester);
            await tester.pump(const Duration(seconds: 1));
            scan('${screen.key} @${size.width.toInt()}');

            // Back arrow (automatic or explicit) must be visible.
            for (final icon in const [
              Icons.arrow_back,
              Icons.arrow_back_rounded,
              Icons.arrow_back_ios_new,
              Icons.arrow_back_ios,
            ]) {
              for (final e in find.byIcon(icon).evaluate()) {
                expect(e.renderObject, isNotNull);
              }
            }

            AuthGuard.navigatorKey.currentState!.pop();
            await settle(tester);
            await tester.pump(const Duration(milliseconds: 400));
          }
        }
      });

      // ignore: avoid_print
      print(
        '[$name] checked $checked texts/icons; skipped $overPhoto over '
        'photography, $disabled disabled; $fields text-field outlines; '
        '${issues.length} issues',
      );
      expect(errors, isEmpty, reason: errors.toSet().join('\n'));
      expect(issues, isEmpty, reason: issues.join('\n'));
    });

    testWidgets('dialogs, sheets and pickers meet AA contrast ($name)', (
      tester,
    ) async {
      addTearDown(tester.view.reset);
      final issues = <String>{};
      void scan(String where) {
        for (final i in scanContrast(tester, backdrop: backdrop).issues) {
          issues.add('$where: $i');
        }
      }

      final errors = await collectErrors(tester, (errors) async {
        await pumpShell(tester, const Size(390, 844), themeMode: mode);
        final nav = AuthGuard.navigatorKey.currentState!;

        // AI consent dialog.
        showDialog<bool>(
          context: nav.context,
          barrierDismissible: false,
          builder: buildAiConsentDialog,
        );
        await settle(tester);
        scan('consent dialog');
        nav.pop();
        await settle(tester);

        // Flights date picker.
        MainShell.currentIndex.value = 2;
        await settle(tester);
        final date = find.byIcon(Icons.calendar_today_outlined).first;
        await tester.ensureVisible(date);
        await settle(tester);
        await tester.tap(date);
        await settle(tester);
        await tester.pump(const Duration(milliseconds: 400));
        expect(find.byType(DatePickerDialog), findsOneWidget);
        scan('date picker');
        nav.pop();
        await settle(tester);
        MainShell.currentIndex.value = 0;
        await settle(tester);

        // Expense sheet + budget sheet.
        nav.push(
          MaterialPageRoute<void>(
            builder: (_) => ExpenseTrackerScreen(trip: sampleTrip()),
          ),
        );
        await settle(tester);
        await tester.pump(const Duration(seconds: 1));
        await tester.tap(find.byType(FloatingActionButton));
        await settle(tester);
        await tester.pump(const Duration(milliseconds: 400));
        scan('expense sheet');
        nav.pop();
        await settle(tester);
        await tester.tap(find.byIcon(Icons.savings_outlined).first);
        await settle(tester);
        await tester.pump(const Duration(milliseconds: 400));
        scan('budget sheet');
        nav.pop();
        await settle(tester);

        // Snackbar.
        ScaffoldMessenger.of(
          tester.element(find.byType(ExpenseTrackerScreen)),
        ).showSnackBar(const SnackBar(content: Text('Expense saved')));
        await settle(tester);
        scan('snackbar');
        nav.popUntil((r) => r.isFirst);
        await settle(tester);
      });
      expect(errors, isEmpty, reason: errors.toSet().join('\n'));
      expect(issues, isEmpty, reason: issues.join('\n'));
    });
  }

  testWidgets('saved theme applies on the first frame after restart', (
    tester,
  ) async {
    for (final saved in const ['dark', 'light']) {
      SharedPreferences.setMockInitialValues({'preferred_theme_mode': saved});
      await AppPreferences.instance.load();
      expect(AppPreferences.instance.themeMode.name, saved);

      // Same as main(): preferences are loaded before runApp, so the very
      // first frame already uses the saved mode (no flash).
      await tester.pumpWidget(const TriporaApp());
      // Below MaterialApp, i.e. inside the Theme it builds.
      final context = tester.element(find.byType(Navigator).first);
      final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
      expect(app.themeMode?.name, saved);
      expect(Theme.of(context).brightness.name, saved);
      await tester.pumpWidget(const SizedBox());
    }
    SharedPreferences.setMockInitialValues({});
    await AppPreferences.instance.load();
  });

  testWidgets('switching theme keeps tab, page state and form input', (
    tester,
  ) async {
    addTearDown(tester.view.reset);
    await AppPreferences.instance.setThemeMode(ThemeMode.light);
    await pumpShell(tester, const Size(390, 844));

    MainShell.currentIndex.value = 2;
    await settle(tester);
    final field = find
        .descendant(
          of: find.byType(FlightSearchScreen),
          matching: find.byType(EditableText),
        )
        .first;
    await tester.enterText(field, 'Lisbon');
    await tester.pump();
    final before = tester.state(find.byType(FlightSearchScreen));

    for (final mode in const [
      ThemeMode.dark,
      ThemeMode.light,
      ThemeMode.dark,
    ]) {
      await AppPreferences.instance.setThemeMode(mode);
      await settle(tester);
      await tester.pump(const Duration(milliseconds: 400));
      final ctx = tester.element(find.byType(FlightSearchScreen));
      expect(
        Theme.of(ctx).brightness,
        mode == ThemeMode.dark ? Brightness.dark : Brightness.light,
      );
      expect(MainShell.currentIndex.value, 2);
      expect(
        identical(tester.state(find.byType(FlightSearchScreen)), before),
        isTrue,
        reason: 'theme switch recreated the Flights page',
      );
      expect(tester.widget<EditableText>(field).controller.text, 'Lisbon');
    }
    await AppPreferences.instance.setThemeMode(ThemeMode.system);
    expect(tester.takeException(), isNull);
  });
}
