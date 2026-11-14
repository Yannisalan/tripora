// Responsive probe for overlays: dialogs, bottom sheets, the activities
// side panel, date pickers and menus, opened through the real UI, at phone,
// landscape and desktop sizes, in long-text languages, at 1.3x text and with
// the on-screen keyboard open. Fails on any layout error and on overlays
// that leave the window or hide their primary action behind the keyboard.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:frontend/core/auth/auth_guard.dart';
import 'package:frontend/core/auth/token_store.dart';
import 'package:frontend/core/design/glass/glass_nav.dart';
import 'package:frontend/core/preferences/app_preferences.dart';
import 'package:frontend/screens/expenses/expense_tracker_screen.dart';
import 'package:frontend/screens/main_shell.dart';
import 'package:frontend/screens/planner/planner_screen.dart';
import 'package:frontend/screens/trip_details.dart';
import 'package:frontend/widgets/gradient_button.dart';

import 'support/probe_harness.dart';

const _phone = Size(320, 568);
const _phoneTall = Size(390, 844);
const _landscape = Size(844, 390);
const _tablet = Size(768, 1024);
const _desktop = Size(1920, 1080);

Future<void> _push(WidgetTester tester, WidgetBuilder builder) async {
  AuthGuard.navigatorKey.currentState!.push(
    MaterialPageRoute<void>(builder: builder),
  );
  await settle(tester);
  await tester.pump(const Duration(milliseconds: 400));
}

Future<void> _popAll(WidgetTester tester) async {
  AuthGuard.navigatorKey.currentState!.popUntil((r) => r.isFirst);
  await settle(tester);
  await tester.pump(const Duration(milliseconds: 400));
}

/// [finder]'s rect lies inside the window, above an open keyboard.
void _expectOnScreen(WidgetTester tester, Finder finder, String what) {
  final rect = tester.getRect(finder);
  final view = tester.view;
  final size = view.physicalSize / view.devicePixelRatio;
  final keyboard = view.viewInsets.bottom / view.devicePixelRatio;
  expect(
    rect.left >= -0.5 && rect.right <= size.width + 0.5,
    isTrue,
    reason: '$what horizontally off-screen: $rect in $size',
  );
  expect(
    rect.top >= -0.5 && rect.bottom <= size.height - keyboard + 0.5,
    isTrue,
    reason:
        '$what vertically off-screen/under keyboard: $rect, '
        'window $size, keyboard $keyboard',
  );
}

Future<void> _withKeyboard(WidgetTester tester, Size size) async {
  tester.view.viewInsets = FakeViewPadding(bottom: size.height * 0.42);
  await settle(tester);
}

Future<void> _noKeyboard(WidgetTester tester) async {
  tester.view.resetViewInsets();
  await settle(tester);
}

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

  for (final lang in const ['en', 'de', 'fr', 'pt']) {
    for (final scale in const [1.0, 1.3]) {
      if (scale == 1.3 && (lang == 'fr' || lang == 'pt')) continue;

      testWidgets(
        'AI consent dialog fits and blocks navigation ($lang, ${scale}x)',
        (tester) async {
          addTearDown(tester.view.reset);
          tester.platformDispatcher.textScaleFactorTestValue = scale;
          addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

          final found = await collectErrors(tester, (errors) async {
            await pumpShell(tester, _phoneTall);
            await AppPreferences.instance.setLanguage(lang);
            await settle(tester);

            for (final size in const [
              _phone,
              _phoneTall,
              _landscape,
              _tablet,
              _desktop,
            ]) {
              tester.view.physicalSize = size;
              await settle(tester);

              bool? result;
              final nav = AuthGuard.navigatorKey.currentContext!;
              showDialog<bool>(
                context: nav,
                barrierDismissible: false,
                builder: buildAiConsentDialog,
              ).then((v) => result = v);
              await settle(tester);
              drainErrors(tester, errors, '$lang consent @$size');

              final dialog = find.byType(AlertDialog);
              expect(dialog, findsOneWidget);
              _expectOnScreen(tester, dialog, 'consent dialog @$size');
              final width = tester.getSize(dialog).width;
              if (size.width >= 1024) {
                expect(
                  width,
                  greaterThanOrEqualTo(280),
                  reason: 'desktop dialog too narrow: $width',
                );
              }

              // Both actions reachable without scrolling.
              final actions = find.descendant(
                of: dialog,
                matching: find.byWidgetPredicate(
                  (w) => w is TextButton || w is FilledButton,
                ),
              );
              expect(actions, findsNWidgets(2));
              for (final e in actions.evaluate()) {
                _expectOnScreen(
                  tester,
                  find.byWidget(e.widget),
                  'consent action @$size',
                );
              }

              // The modal barrier blocks the navigation underneath.
              final before = MainShell.currentIndex.value;
              await tester.tapAt(const Offset(4, 4));
              await settle(tester);
              expect(
                find.byType(AlertDialog),
                findsOneWidget,
                reason: 'consent must not dismiss on barrier tap',
              );
              expect(MainShell.currentIndex.value, before);

              await tester.tap(
                find.descendant(
                  of: dialog,
                  matching: find.byType(FilledButton),
                ),
              );
              await settle(tester);
              expect(result, isTrue);
              drainErrors(tester, errors, '$lang consent @$size');
            }
            await AppPreferences.instance.setLanguage('en');
            await settle(tester);
          });
          expect(found, isEmpty, reason: found.toSet().join('\n'));
        },
      );

      testWidgets('expense sheets usable with keyboard ($lang, ${scale}x)', (
        tester,
      ) async {
        addTearDown(tester.view.reset);
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

        final found = await collectErrors(tester, (errors) async {
          await pumpShell(tester, _phoneTall);
          await AppPreferences.instance.setLanguage(lang);
          await settle(tester);

          for (final size in const [
            _phone,
            _phoneTall,
            _landscape,
            _tablet,
            _desktop,
          ]) {
            tester.view.physicalSize = size;
            await _push(
              tester,
              (_) => ExpenseTrackerScreen(trip: sampleTrip()),
            );

            for (final open in [
              () => tester.tap(find.byType(FloatingActionButton)),
              () => tester.tap(find.byIcon(Icons.savings_outlined).first),
            ]) {
              await open();
              await settle(tester);
              await tester.pump(const Duration(milliseconds: 400));
              final sheet = find.byType(BottomSheet);
              expect(sheet, findsOneWidget, reason: 'sheet @$size');

              await _withKeyboard(tester, size);
              drainErrors(tester, errors, '$lang expense sheet+kbd @$size');

              final save = find
                  .descendant(of: sheet, matching: find.byType(GradientButton))
                  .last;
              await tester.ensureVisible(save);
              await settle(tester);
              _expectOnScreen(tester, save, 'sheet save button @$size');

              await _noKeyboard(tester);
              AuthGuard.navigatorKey.currentState!.pop();
              await settle(tester);
              await tester.pump(const Duration(milliseconds: 400));
              drainErrors(tester, errors, '$lang expense sheet @$size');
            }
            await _popAll(tester);
          }
          await AppPreferences.instance.setLanguage('en');
          await settle(tester);
        });
        expect(found, isEmpty, reason: found.toSet().join('\n'));
      });

      testWidgets(
        'trip details: edit sheet + activities panel ($lang, ${scale}x)',
        (tester) async {
          addTearDown(tester.view.reset);
          tester.platformDispatcher.textScaleFactorTestValue = scale;
          addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

          final found = await collectErrors(tester, (errors) async {
            await pumpShell(tester, _phoneTall);
            await AppPreferences.instance.setLanguage(lang);
            await settle(tester);

            for (final size in const [
              _phone,
              _phoneTall,
              _landscape,
              _tablet,
              _desktop,
            ]) {
              tester.view.physicalSize = size;
              await _push(tester, (_) => TripDetailsScreen(trip: sampleTrip()));

              // Edit-trip sheet, with the keyboard open.
              await tester.tap(find.byIcon(Icons.edit_outlined).first);
              await settle(tester);
              await tester.pump(const Duration(milliseconds: 400));
              expect(
                find.byType(BottomSheet),
                findsOneWidget,
                reason: 'edit-trip sheet did not open @$size',
              );
              await _withKeyboard(tester, size);
              drainErrors(tester, errors, '$lang edit sheet+kbd @$size');
              await _noKeyboard(tester);
              AuthGuard.navigatorKey.currentState!.pop();
              await settle(tester);
              await tester.pump(const Duration(milliseconds: 400));

              // All activities: side panel on desktop, bottom sheet otherwise.
              // The deck sits further down a lazily built list: step the
              // page's main scroll position until it is built.
              final tile = find.byIcon(Icons.local_activity_outlined);
              final position = tester
                  .state<ScrollableState>(
                    find
                        .descendant(
                          of: find.byType(TripDetailsScreen),
                          matching: find.byType(Scrollable),
                        )
                        .first,
                  )
                  .position;
              for (var i = 0; i < 40 && tile.evaluate().isEmpty; i++) {
                position.jumpTo(
                  (position.pixels + 250).clamp(0, position.maxScrollExtent),
                );
                await tester.pump();
              }
              expect(tile, findsWidgets, reason: 'activities tile @$size');
              await tester.ensureVisible(tile.first);
              await settle(tester);
              await tester.tap(tile.first);
              await settle(tester);
              await tester.pump(const Duration(milliseconds: 400));
              drainErrors(tester, errors, '$lang activities @$size');

              final close = find.byIcon(Icons.close).last;
              _expectOnScreen(tester, close, 'activities close @$size');
              if (size.width >= 1024) {
                expect(
                  find.byType(DraggableScrollableSheet),
                  findsNothing,
                  reason: 'desktop should use the side panel',
                );
                expect(
                  tester.getRect(close).right,
                  greaterThan(size.width - 80),
                  reason: 'side panel is docked on the right',
                );
              } else {
                expect(
                  find.byType(DraggableScrollableSheet),
                  findsOneWidget,
                  reason: 'phones/tablets keep the bottom sheet',
                );
              }
              await tester.tap(close);
              await settle(tester);
              await tester.pump(const Duration(milliseconds: 400));
              await _popAll(tester);
              drainErrors(tester, errors, '$lang trip details @$size');
            }
            await AppPreferences.instance.setLanguage('en');
            await settle(tester);
          });
          expect(found, isEmpty, reason: found.toSet().join('\n'));
        },
      );

      testWidgets(
        'trips delete dialog, account dialog, date picker ($lang, ${scale}x)',
        (tester) async {
          addTearDown(tester.view.reset);
          tester.platformDispatcher.textScaleFactorTestValue = scale;
          addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

          final found = await collectErrors(tester, (errors) async {
            await pumpShell(tester, _phoneTall);
            await AppPreferences.instance.setLanguage(lang);
            await settle(tester);

            for (final size in const [_phone, _landscape, _tablet, _desktop]) {
              tester.view.physicalSize = size;
              await settle(tester);

              // My Trips -> card menu -> delete confirmation.
              MainShell.currentIndex.value = 3;
              await settle(tester);
              final menu = find.byType(PopupMenuButton<String>).first;
              await tester.ensureVisible(menu);
              await settle(tester);
              await tester.tap(menu);
              await settle(tester);
              await tester.pump(const Duration(milliseconds: 400));
              await tester.tap(find.byType(PopupMenuItem<String>).last);
              await settle(tester);
              await tester.pump(const Duration(milliseconds: 400));
              final del = find.byType(AlertDialog);
              expect(del, findsOneWidget, reason: 'delete dialog @$size');
              _expectOnScreen(tester, del, 'delete dialog @$size');
              drainErrors(tester, errors, '$lang trips delete @$size');
              await tester.tap(
                find
                    .descendant(of: del, matching: find.byType(TextButton))
                    .first,
              );
              await settle(tester);

              // Profile -> delete account (password field + keyboard).
              MainShell.currentIndex.value = 4;
              await settle(tester);
              final delAccount = find.byIcon(Icons.delete_outline).last;
              await tester.ensureVisible(delAccount);
              await settle(tester);
              await tester.tap(delAccount);
              await settle(tester);
              await tester.pump(const Duration(milliseconds: 400));
              expect(
                find.byType(AlertDialog),
                findsOneWidget,
                reason: 'account dialog @$size',
              );
              await _withKeyboard(tester, size);
              drainErrors(tester, errors, '$lang account dialog+kbd @$size');
              await _noKeyboard(tester);
              AuthGuard.navigatorKey.currentState!.pop();
              await settle(tester);

              // Flights -> departure date picker.
              MainShell.currentIndex.value = 2;
              await settle(tester);
              final date = find.byIcon(Icons.calendar_today_outlined).first;
              await tester.ensureVisible(date);
              await settle(tester);
              await tester.tap(date);
              await settle(tester);
              await tester.pump(const Duration(milliseconds: 400));
              final picker = find.byType(DatePickerDialog);
              expect(picker, findsOneWidget, reason: 'date picker @$size');
              _expectOnScreen(tester, picker, 'date picker @$size');
              drainErrors(tester, errors, '$lang date picker @$size');
              AuthGuard.navigatorKey.currentState!.pop();
              await settle(tester);
              MainShell.currentIndex.value = 0;
              await settle(tester);
            }
            await AppPreferences.instance.setLanguage('en');
            await settle(tester);
          });
          expect(found, isEmpty, reason: found.toSet().join('\n'));
        },
      );
    }
  }

  testWidgets('only one navigation is ever on screen while overlays open', (
    tester,
  ) async {
    addTearDown(tester.view.reset);
    await pumpShell(tester, _desktop);
    expect(find.byType(GlassSideNav), findsOneWidget);
    expect(find.byType(GlassBottomNav), findsNothing);
    showDialog<bool>(
      context: AuthGuard.navigatorKey.currentContext!,
      barrierDismissible: false,
      builder: buildAiConsentDialog,
    );
    await settle(tester);
    tester.view.physicalSize = _phoneTall;
    await settle(tester);
    expect(find.byType(GlassBottomNav), findsOneWidget);
    expect(find.byType(GlassSideNav), findsNothing);
    expect(
      find.byType(AlertDialog),
      findsOneWidget,
      reason: 'resizing must not drop an open dialog',
    );
    expect(tester.takeException(), isNull);
  });
}
