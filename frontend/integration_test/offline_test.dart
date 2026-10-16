// Release-mode OFFLINE walkthrough against the production backend.
//
// The host script enables airplane mode BEFORE this run, so the device must
// already be offline when the app starts. Assumes online_test.dart completed
// first (active session + cached Tokyo trip in SharedPreferences).
//
// Run via:
//   flutter drive --release \
//     --driver=test_driver/integration_test.dart \
//     --target=integration_test/offline_test.dart \
//     -d emulator-5554 \
//     --dart-define=API_BASE_URL=https://tripora-4mt3.onrender.com
import 'dart:io';
import 'dart:developer' as developer;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:frontend/core/config/app_config.dart';

import 'package:frontend/main.dart' as app;

const String _base = AppConfig.apiBaseUrl;

void _mark(String s) => developer.log('[WALKTHROUGH] $s');

Future<bool> _probeOnline() async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
  try {
    final req = await client
        .getUrl(Uri.parse('$_base/api/auth/me'))
        .timeout(const Duration(seconds: 8));
    final res = await req.close().timeout(const Duration(seconds: 8));
    await res.drain<void>();
    return true;
  } catch (_) {
    return false;
  } finally {
    client.close(force: true);
  }
}

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

String _snackText(WidgetTester tester) {
  final sb = tester.widget<SnackBar>(find.byType(SnackBar).first);
  final w = sb.content;
  if (w is Text) return w.data ?? '';
  return w.toString();
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('offline walkthrough (airplane mode)', (tester) async {
    final sp = await SharedPreferences.getInstance();
    final token = sp.getString('access_token');
    expect(token, isNotNull,
        reason: 'offline run requires the session from online_test.dart');

    // ------------------------------------------------------------------
    // Confirm the host actually cut the network BEFORE this run started.
    // ------------------------------------------------------------------
    final offlineEnd = DateTime.now().add(const Duration(seconds: 240));
    var offline = false;
    while (DateTime.now().isBefore(offlineEnd)) {
      await tester.pump(const Duration(milliseconds: 500));
      if (!(await _probeOnline())) {
        offline = true;
        break;
      }
    }
    expect(offline, isTrue,
        reason: 'device network must be OFF (airplane mode) for offline run');
    _mark('OFFLINE_DEVICE_CONFIRMED');

    // ------------------------------------------------------------------
    // Launch: session survives, main shell loads purely from local state.
    // ------------------------------------------------------------------
    app.main();
    await _pumpUntil(tester,
        cond: () => _ht(find.text('My Trips')).evaluate().isNotEmpty,
        timeout: const Duration(seconds: 90),
        label: 'main shell after offline launch (token kept user signed in)');
    _mark('OFFLINE_SESSION_RESTORED=ok');

    // ------------------------------------------------------------------
    // My Trips: offline banner + cached trip visible (read-only).
    // ------------------------------------------------------------------
    await _tapVisible(tester, find.text('My Trips'), label: 'My Trips tab');
    await _pumpUntil(tester,
        cond: () => _ht(find.textContaining("You're offline")).evaluate().isNotEmpty,
        timeout: const Duration(seconds: 30),
        label: 'offline banner on My Trips');
    _mark('OFFLINE_BANNER=ok');

    await _pumpUntil(tester,
        cond: () => _ht(find.textContaining('Tokyo')).evaluate().isNotEmpty,
        timeout: const Duration(seconds: 30),
        label: 'cached trip visible offline');
    _mark('OFFLINE_CACHED_TRIP=ok');

    // ------------------------------------------------------------------
    // Planner generate while offline: graceful error, never a hang.
    // ------------------------------------------------------------------
    await _tapVisible(tester, find.text('Home'), label: 'Home tab (offline)');
    await _tapVisible(tester, find.text('Plan a Trip'), label: 'Plan a Trip CTA (offline)');
    await _pumpUntil(tester,
        cond: () => _ht(find.text('Essentials')).evaluate().isNotEmpty,
        timeout: const Duration(seconds: 30),
        label: 'planner screen (offline)');
    await _tapVisible(
        tester, find.widgetWithText(ChoiceChip, 'Tokyo'), label: 'Tokyo chip (offline)');
    await _tapVisible(
        tester, find.widgetWithText(ChoiceChip, '1 Week'), label: '1 Week chip (offline)');

    // Consent was accepted during the online run; but if it ever got reset,
    // accept it here so generation is actually attempted.
    if (_ht(find.text('Before you generate')).evaluate().isNotEmpty) {
      await _tapVisible(tester, find.text('I understand'),
          label: 'defensive consent accept (offline)');
    }

    await _tapVisible(
        tester, find.text('Create with AI'), label: 'Create with AI (offline)');

    await _pumpUntil(tester,
        cond: () => _ht(find.byType(CircularProgressIndicator)).evaluate().isNotEmpty,
        timeout: const Duration(seconds: 20),
        label: 'generation overlay appeared (offline)');

    // A socket-connect failure must surface as a snackbar fast; the overlay
    // must then close and the planner must remain responsive.
    await _pumpUntil(tester,
        cond: () => _ht(find.byType(SnackBar)).evaluate().isNotEmpty,
        timeout: const Duration(seconds: 120),
        label: 'offline generation settled with a graceful error');
    _mark('OFFLINE_GENERATE_GRACEFUL_ERROR=${_snackText(tester)}');

    await _pumpUntil(tester,
        cond: () => _ht(find.byType(CircularProgressIndicator)).evaluate().isEmpty,
        timeout: const Duration(seconds: 20),
        label: 'offline overlay dismissed (no hang)');
    await _pumpUntil(tester,
        cond: () => _ht(find.text('Create with AI')).evaluate().isNotEmpty,
        timeout: const Duration(seconds: 10),
        label: 'planner responsive again after offline error');
    _mark('OFFLINE_NO_HANG=ok');

    _mark('WALKTHROUGH_OFFLINE_COMPLETE');
  });
}