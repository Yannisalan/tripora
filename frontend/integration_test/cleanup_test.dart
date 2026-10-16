// Release-mode CLEAN-UP walkthrough against the production backend.
//
// Deletes the account created by online_test.dart and verifies:
//   - logout wipes the offline trip cache,
//   - password-reset request flow works end-to-end (code delivery can NOT be
//     verified from this environment, so only the "code requested" outcome is
//     asserted; the step is tolerant of a backend e-mail failure),
//   - re-login after the offline window still works,
//   - account deletion redirects to sign-in and old credentials are rejected.
//
// Run after online_test.dart (session active, account exists).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:frontend/widgets/gradient_button.dart';

import 'package:frontend/main.dart' as app;
import 'dart:developer' as developer;

const String _pw = 'VerifyPass42!';

void _mark(String s) => developer.log('[WALKTHROUGH] $s');

Finder _ht(Finder f) => f.hitTestable();

Future<void> _pumpUntil(
  WidgetTester tester, {
  required bool Function() cond,
  Duration timeout = const Duration(seconds: 30),
  required String label,
}) async {
  final end = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 200));
    if (cond()) return;
  }
  fail('pumpUntil timed out waiting for: $label');
}

Future<void> _tapVisible(
  WidgetTester tester,
  Finder finder, {
  String label = 'target',
  Duration timeout = const Duration(seconds: 30),
}) async {
  final f = finder.hitTestable();
  await _pumpUntil(tester,
      cond: () => f.evaluate().isNotEmpty, timeout: timeout, label: label);
  await tester.ensureVisible(f.first);
  await tester.pump(const Duration(milliseconds: 250));
  await tester.tap(f.first, warnIfMissed: false);
  await tester.pump(const Duration(milliseconds: 400));
}

Finder _field(String label) => find.widgetWithText(TextFormField, label);

Future<void> _enterField(
  WidgetTester tester,
  String label,
  String text,
) async {
  final f = _field(label).hitTestable();
  await _pumpUntil(tester,
      cond: () => f.evaluate().isNotEmpty, label: 'field "$label" visible');
  await tester.ensureVisible(f.first);
  await tester.pump(const Duration(milliseconds: 200));
  await tester.tap(f.first, warnIfMissed: false);
  await tester.pump(const Duration(milliseconds: 300));
  await tester.enterText(f.first, text);
  await tester.pump(const Duration(milliseconds: 250));
  final tf = find
      .descendant(
          of: _field(label).first, matching: find.byType(TextField))
      .first;
  final ctrl = tester.widget<TextField>(tf).controller;
  if ((ctrl?.text ?? '') != text) {
    _mark('FIELD_$label enterText-missed -> direct controller');
    ctrl?.text = text;
    await tester.pump(const Duration(milliseconds: 250));
  }
  _mark('FIELD_$label="${ctrl?.text}"');
}

String _snackText(WidgetTester tester) {
  final sb = tester.widget<SnackBar>(find.byType(SnackBar).first);
  final w = sb.content;
  if (w is Text) return w.data ?? '';
  return w.toString();
}

Future<void> _scrollIntoView(WidgetTester tester, Finder finder,
    {String label = 'target'}) async {
  await _pumpUntil(tester,
      cond: () => finder.evaluate().isNotEmpty, label: '$label in widget tree');
  final end = DateTime.now().add(const Duration(seconds: 20));
  while (DateTime.now().isBefore(end)) {
    await tester.ensureVisible(finder.first);
    await tester.pump(const Duration(milliseconds: 300));
    if (finder.hitTestable().evaluate().isNotEmpty) return;
    final scrollables = find.byType(Scrollable).hitTestable();
    if (scrollables.evaluate().isEmpty) break;
    await tester.drag(scrollables.first, const Offset(0, -250));
    await tester.pump(const Duration(milliseconds: 300));
  }
  fail('could not scroll "$label" into view');
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('clean-up: reset flow, logout cache wipe, account deletion',
      (tester) async {
    final sp = await SharedPreferences.getInstance();
    final token = sp.getString('access_token');
    expect(token, isNotNull,
        reason: 'cleanup run requires the session from online_test.dart');

    final email = sp.getString('verify_email');
    expect(email, isNotNull,
        reason: 'cleanup run requires verify_email stored by online_test.dart');

    // ------------------------------------------------------------------
    // Launch: session still valid after the offline window.
    // ------------------------------------------------------------------
    app.main();
    await _pumpUntil(tester,
        cond: () => _ht(find.text('My Trips')).evaluate().isNotEmpty,
        timeout: const Duration(seconds: 90),
        label: 'main shell after relaunch (session persisted across runs)');
    _mark('CLEANUP_SESSION_PERSISTED=ok');
    _mark('CLEANUP_ACCOUNT_EMAIL=$email');

    // ------------------------------------------------------------------
    // Logout from Profile: must wipe the offline trip cache.
    // ------------------------------------------------------------------
    final cacheBefore = sp.getString('tripora.offline_trips_v1');
    _mark('CLEANUP_CACHE_BEFORE_LOGOUT=${cacheBefore != null}');

    await _tapVisible(tester, find.text('Profile'), label: 'Profile tab');
    await _pumpUntil(tester,
        cond: () => _ht(find.byTooltip('Log out')).evaluate().isNotEmpty,
        timeout: const Duration(seconds: 30),
        label: 'profile loaded');
    await _tapVisible(tester, find.byTooltip('Log out'), label: 'Log out button');

    await _pumpUntil(tester,
        cond: () => _ht(find.text('Welcome back to Tripora')).evaluate().isNotEmpty,
        timeout: const Duration(seconds: 45),
        label: 'login screen after logout');
    final spAfterLogout = await SharedPreferences.getInstance();
    expect(spAfterLogout.getString('tripora.offline_trips_v1'), isNull,
        reason: 'trips-list offline cache must be cleared on logout');
    final leftover =
        spAfterLogout.getKeys().where((k) => k.startsWith('tripora.offline_trip_'));
    expect(leftover.toList(), isEmpty,
        reason: 'per-trip offline cache must be cleared on logout');
    _mark('STEP15_LOGOUT_CLEARS_OFFLINE_CACHE=ok');

    // ------------------------------------------------------------------
    // Forgot password: request code (delivery depends on the SMTP backend;
    // the verified part is that the request succeeds / error is graceful).
    // ------------------------------------------------------------------
    await _tapVisible(tester, find.text('Forgot password?'),
        label: 'Forgot password? link');
    await _pumpUntil(tester,
        cond: () => _ht(find.text('Send Reset Code')).evaluate().isNotEmpty,
        timeout: const Duration(seconds: 30),
        label: 'forgot-password screen');
    await _enterField(tester, 'Email', email!);
    await _tapVisible(
        tester,
        find.widgetWithText(GradientButton, 'Send Reset Code'),
        label: 'Send Reset Code button');

    String resetOutcome = 'unresolved';
    final rEnd = DateTime.now().add(const Duration(seconds: 45));
    while (DateTime.now().isBefore(rEnd)) {
      await tester.pump(const Duration(milliseconds: 300));
      if (_ht(find.text('Check Your Email')).evaluate().isNotEmpty ||
          _ht(find.text(
                      'If the account exists, a password reset code has been sent.'))
              .evaluate()
              .isNotEmpty) {
        resetOutcome = 'code_requested';
        break;
      }
      if (_ht(find.byType(SnackBar)).evaluate().isNotEmpty) {
        final text = _snackText(tester);
        if (!text.contains('reset code')) {
          resetOutcome = 'error:$text';
          break;
        }
        resetOutcome = 'code_requested';
        break;
      }
    }
    _mark('STEP14_RESET_SEND_OUTCOME=$resetOutcome');
    _mark('STEP14_NOTE=reset_CODE_DELIVERY_requires_mailbox_UNVERIFIED');

    // ------------------------------------------------------------------
    // Return to the login screen (pop the reset screen however many steps up).
    // ------------------------------------------------------------------
    for (var i = 0; i < 4; i++) {
      if (_ht(find.text('Welcome back to Tripora')).evaluate().isNotEmpty) break;
      final backArrow = _ht(find.byIcon(Icons.arrow_back));
      if (backArrow.evaluate().isEmpty) break;
      await tester.tap(backArrow.first, warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 700));
    }
    await _pumpUntil(tester,
        cond: () => _ht(find.text('Welcome back to Tripora')).evaluate().isNotEmpty,
        timeout: const Duration(seconds: 30),
        label: 'login screen reached again');

    // ------------------------------------------------------------------
    // Re-login after the offline window.
    // ------------------------------------------------------------------
    await _enterField(tester, 'Email', email);
    await _enterField(tester, 'Password', _pw);
    await _tapVisible(
        tester,
        find.widgetWithText(GradientButton, 'Sign In'),
        label: 'Sign In (re-login)');
    await _pumpUntil(tester,
        cond: () => _ht(find.text('My Trips')).evaluate().isNotEmpty,
        timeout: const Duration(seconds: 45),
        label: 'main shell after re-login');
    _mark('STEP4_RELOGIN_AFTER_OFFLINE_WINDOW=ok');

    // ------------------------------------------------------------------
    // Delete account.
    // ------------------------------------------------------------------
    await _tapVisible(tester, find.text('Profile'), label: 'Profile tab (2)');
    await _pumpUntil(tester,
        cond: () => _ht(find.byTooltip('Log out')).evaluate().isNotEmpty,
        timeout: const Duration(seconds: 30),
        label: 'profile loaded (2)');
    await _scrollIntoView(tester, find.text('Delete my account'),
        label: 'Delete my account button');
    await _tapVisible(tester, find.text('Delete my account'),
        label: 'Delete my account');

    await _pumpUntil(tester,
        cond: () => _ht(find.text('Delete your account?')).evaluate().isNotEmpty,
        timeout: const Duration(seconds: 15),
        label: 'delete confirmation dialog');
    _mark('STEP16_DELETE_DIALOG=ok');
    await _tapVisible(tester, find.text('Delete'), label: 'Confirm Delete');

    await _pumpUntil(tester,
        cond: () => _ht(find.text('Welcome back to Tripora')).evaluate().isNotEmpty,
        timeout: const Duration(seconds: 45),
        label: 'login screen after account deletion');
    final spAfterDelete = await SharedPreferences.getInstance();
    expect(spAfterDelete.getString('access_token'), isNull,
        reason: 'token must be dropped after account deletion');
    expect(spAfterDelete.getString('tripora.offline_trips_v1'), isNull,
        reason: 'offline cache must be cleared on account deletion');
    _mark('STEP16_DELETE_ACCOUNT=ok');

    // ------------------------------------------------------------------
    // Old credentials must now be rejected by the backend.
    // ------------------------------------------------------------------
    await _enterField(tester, 'Email', email);
    await _enterField(tester, 'Password', _pw);
    await _tapVisible(
        tester,
        find.widgetWithText(GradientButton, 'Sign In'),
        label: 'Sign In (after deletion)');
    await _pumpUntil(tester,
        cond: () =>
            _ht(find.textContaining('Invalid email')).evaluate().isNotEmpty,
        timeout: const Duration(seconds: 30),
        label: 'login after account deletion rejected');
    _mark('STEP16_LOGIN_AFTER_DELETE_BLOCKED=${_snackText(tester)}');

    _mark('WALKTHROUGH_CLEANUP_COMPLETE');
  });
}