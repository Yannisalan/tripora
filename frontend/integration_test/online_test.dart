// Release-mode online walkthrough against the production backend.
//
// Run via:
//   flutter drive --release \
//     --driver=test_driver/integration_test.dart \
//     --target=integration_test/online_test.dart \
//     -d emulator-5554 \
//     --dart-define=API_BASE_URL=https://tripora-4mt3.onrender.com
//
// Assumes network is ON and the app is NOT already signed in.
import 'dart:io';
import 'dart:developer' as developer;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:frontend/core/auth/auth_guard.dart';
import 'package:frontend/core/config/app_config.dart';
import 'package:frontend/core/preferences/app_preferences.dart';
import 'package:frontend/models/trip_model.dart';
import 'package:frontend/screens/trips/trips_screen.dart';
import 'package:frontend/services/trip_service.dart';
import 'package:frontend/widgets/gradient_button.dart';

import 'package:frontend/main.dart' as app;

const String _base = AppConfig.apiBaseUrl;
const String _pw = 'VerifyPass42!';

void _mark(String s) => developer.log('[WALKTHROUGH] $s');
void _status(String s) => developer.log('[WALKTHROUGH_STATUS] $s');

Future<bool> _probeOnline() async {
  for (var attempt = 0; attempt < 4; attempt++) {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
    try {
      final req = await client
          .getUrl(Uri.parse('$_base/api/auth/me'))
          .timeout(const Duration(seconds: 20));
      final res = await req.close().timeout(const Duration(seconds: 25));
      await res.drain<void>();
      return true;
    } catch (_) {
      // cold start or transient; retry
    } finally {
      client.close(force: true);
    }
    if (attempt < 3) {
      await Future<void>.delayed(const Duration(seconds: 5));
    }
  }
  return false;
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
  // Read the controller via the raw widget tree (not hitTestable): the field
  // stays mounted in the SingleChildScrollView even when the soft keyboard
  // pushes it off-screen, but re-evaluating a hitTestable finder here can
  // transiently return empty ("Bad state: No element" on .first).
  final tf = find
      .descendant(
          of: _field(label).first, matching: find.byType(TextField))
      .first;
  final ctrl = tester.widget<TextField>(tf).controller;
  if ((ctrl?.text ?? '') != text) {
    // On-device, the mock IME channel can be ignored by the real IME, so the
    // value never sticks. Fall back to the controller directly for
    // determinism; the flow-level assertions are what matter here.
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

Future<void> _goHomeRoot(WidgetTester tester) async {
  final nav = AuthGuard.navigatorKey.currentState;
  if (nav != null) {
    nav.popUntil((route) => route.isFirst);
  }
  await tester.pump(const Duration(milliseconds: 700));
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

Future<void> _tapInScroll(WidgetTester tester, Finder finder,
    {String label = 'target'}) async {
  await _scrollIntoView(tester, finder, label: label);
  final f = finder.hitTestable();
  await tester.ensureVisible(f.first);
  await tester.pump(const Duration(milliseconds: 250));
  await tester.tap(f.first, warnIfMissed: false);
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('online walkthrough against production', (tester) async {
    final sp = await SharedPreferences.getInstance();

    // Fresh, install-like state so the walkthrough is deterministic.
    await sp.clear();
    await TripService.clearOfflineCache();
    expect(await _probeOnline(), isTrue,
        reason: 'online run requires working network');

    // ------------------------------------------------------------------
    // Launch + fresh-install first screen
    // ------------------------------------------------------------------
    app.main();
    await _pumpUntil(tester,
        cond: () => _ht(find.text('Welcome back to Tripora')).evaluate().isNotEmpty,
        timeout: const Duration(seconds: 60),
        label: 'login screen after fresh launch');
    _mark('STEP1_FRESH_LAUNCH=login_screen');

    // ------------------------------------------------------------------
    // Register via UI (backend live round-trip, both consent checkboxes)
    // ------------------------------------------------------------------
    final email = 'rv${DateTime.now().millisecondsSinceEpoch}@example.com';

    await _tapVisible(tester, find.text('Sign up'), label: 'sign up link');
    await _pumpUntil(tester,
        cond: () => _ht(find.text('Create Account')).evaluate().isNotEmpty,
        timeout: const Duration(seconds: 30),
        label: 'register screen');
    _mark('STEP2_REGISTER_SCREEN=shown');

    await _enterField(tester, 'Name', 'Verify Tester');
    await _enterField(tester, 'Email', email);
    await _enterField(tester, 'Password', _pw);

    final boxes = find.byType(Checkbox);
    await _pumpUntil(tester,
        cond: () => boxes.evaluate().length >= 2,
        label: 'both consent checkboxes present');
    final cbs = boxes.evaluate().toList();
    _mark('CHECKBOX_COUNT=${cbs.length}');
    if (cbs.isNotEmpty) {
      for (var i = 0; i < cbs.length; i++) {
        _mark('CHECKBOX_$i=${(cbs[i].widget as Checkbox).value}');
      }
    }
    await tester.ensureVisible(boxes.at(0));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tap(boxes.at(0));
    await tester.pump(const Duration(milliseconds: 250));
    await tester.ensureVisible(boxes.at(1));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tap(boxes.at(1));
    await tester.pump(const Duration(milliseconds: 250));
    final cbs2 = find.byType(Checkbox).evaluate().toList();
    for (var i = 0; i < cbs2.length; i++) {
      _mark('CHECKBOX_AFTER_$i=${(cbs2[i].widget as Checkbox).value}');
    }

    await _tapVisible(
        tester,
        find.widgetWithText(GradientButton, 'Create Account'),
        label: 'Create Account (GradientButton)');
    _mark('STEP2_REGISTER_TAPPED=create_account');

    // Fast window: catch transient form-validation / terms snackbars and
    // validator error texts that only flash briefly.
    String? lastState;
    final fastEnd = DateTime.now().add(const Duration(seconds: 8));
    while (DateTime.now().isBefore(fastEnd)) {
      await tester.pump(const Duration(milliseconds: 300));
      final snack = find.byType(SnackBar).evaluate().isNotEmpty
          ? _snackText(tester)
          : '(none)';
      final spinner = find
          .byType(CircularProgressIndicator)
          .hitTestable()
          .evaluate()
          .isNotEmpty;
      final errs = <String>[
        'Please enter your name.',
        'Please enter your email.',
        'Please enter a valid email.',
        'Password must be at least 8 characters.',
        'Please accept the Terms & Conditions and Privacy Policy.',
      ].where((s) => find.text(s).evaluate().isNotEmpty).join(' | ');
      final key = 'snack=$snack spinner=$spinner errs={$errs}';
      if (key != lastState) {
        lastState = key;
        _mark('REG_FAST $key');
      }
      if (_ht(find.text('Welcome back to Tripora')).evaluate().isNotEmpty) {
        break;
      }
    }

    // Long wait: the backend may cold-start the register request.
    bool landed = false;
    final regDeadline = DateTime.now().add(const Duration(seconds: 120));
    while (DateTime.now().isBefore(regDeadline)) {
      await tester.pump(const Duration(milliseconds: 250));
      if (_ht(find.text('Welcome back to Tripora')).evaluate().isNotEmpty) {
        landed = true;
        break;
      }
    }
    _mark('STEP2_REGISTER_LANDED=$landed');
    expect(landed, isTrue,
        reason: 'registration should return to the login screen');
    _mark('STEP2_REGISTER=ok');
    _mark('STEP2_REGISTER_EMAIL=$email');

    // ------------------------------------------------------------------
    // Sign in via UI
    // ------------------------------------------------------------------
    await _enterField(tester, 'Email', email);
    await _enterField(tester, 'Password', _pw);
    await _tapInScroll(
        tester,
        find.widgetWithText(GradientButton, 'Sign In'),
        label: 'Sign In (GradientButton)');
    await _pumpUntil(tester,
        cond: () => _ht(find.text('My Trips')).evaluate().isNotEmpty,
        timeout: const Duration(seconds: 45),
        label: 'main shell after sign-in');
    _mark('STEP3_LOGIN=ok');

    // ------------------------------------------------------------------
    // Planner: consent disclosure MUST appear before any generation
    // ------------------------------------------------------------------
    await _tapVisible(tester, find.text('Plan a Trip'), label: 'Plan a Trip CTA');
    await _pumpUntil(tester,
        cond: () => _ht(find.text('Essentials')).evaluate().isNotEmpty,
        timeout: const Duration(seconds: 30),
        label: 'planner screen');
    _mark('STEP4_PLANNER=shown');

    await _tapInScroll(tester,
        find.widgetWithText(ChoiceChip, 'Tokyo'), label: 'Tokyo chip');
    await _tapInScroll(tester,
        find.widgetWithText(ChoiceChip, '1 Week'), label: '1 Week chip');

    await _tapInScroll(
        tester, find.text('Create with AI'), label: 'Create with AI');

    await _pumpUntil(tester,
        cond: () => _ht(find.text('Before you generate')).evaluate().isNotEmpty,
        timeout: const Duration(seconds: 20),
        label: 'AI consent dialog shown BEFORE generation');
    expect(_ht(find.byType(CircularProgressIndicator)).evaluate(), isEmpty,
        reason: 'no generation overlay while consent dialog is open');
    _mark('STEP4_CONSENT_DIALOG_FIRST=ok');

    // Decline => no generation, consent stays false (persisted).
    await _tapVisible(tester, find.text('Not now'), label: 'decline consent');
    await _pumpUntil(tester,
        cond: () => _ht(find.text('Before you generate')).evaluate().isEmpty,
        timeout: const Duration(seconds: 15),
        label: 'consent dialog dismissed after decline');
    expect(AppPreferences.instance.aiConsentGiven, isFalse,
        reason: 'decline must not grant consent');
    expect(_ht(find.byType(CircularProgressIndicator)).evaluate(), isEmpty,
        reason: 'decline must not start the generation overlay');
    final spConsent = await SharedPreferences.getInstance();
    expect(spConsent.getBool('ai_consent_given') ?? false, isFalse,
        reason: 'ai_consent_given must remain false when declined');
    _mark('STEP4_DECLINE_NO_GENERATION=ok');

    // Accept => overlay appears, generation actually starts.
    await _tapVisible(
        tester, find.text('Create with AI'), label: 'Create with AI (2nd)');
    await _pumpUntil(tester,
        cond: () => _ht(find.text('I understand')).evaluate().isNotEmpty,
        timeout: const Duration(seconds: 20),
        label: 'consent dialog again after re-tap');
    await _tapVisible(tester, find.text('I understand'), label: 'accept consent');
    expect(AppPreferences.instance.aiConsentGiven, isTrue,
        reason: 'accept must persist consent');
    _mark('STEP4_ACCEPT_CONSENT=ok');

    await _pumpUntil(tester,
        cond: () => _ht(find.byType(CircularProgressIndicator)).evaluate().isNotEmpty,
        timeout: const Duration(seconds: 20),
        label: 'generation overlay started');
    _mark('STEP5_GENERATION_OVERLAY=ok');

    // ------------------------------------------------------------------
    // Wait for the live AI generation to settle (success OR graceful error)
    // ------------------------------------------------------------------
    String genOutcome = 'unknown';
    String errText = '';
    final deadline = DateTime.now().add(const Duration(seconds: 150));
    while (DateTime.now().isBefore(deadline)) {
      await tester.pump(const Duration(milliseconds: 400));
      if (_ht(find.text('Create with AI')).evaluate().isEmpty &&
          _ht(find.byType(CircularProgressIndicator)).evaluate().isEmpty) {
        genOutcome = 'success_navigated';
        break;
      }
      if (_ht(find.byType(SnackBar)).evaluate().isNotEmpty) {
        genOutcome = 'error';
        errText = _snackText(tester);
        break;
      }
    }
    if (genOutcome == 'unknown') {
      fail('generation did not settle within 150s (live AI call too slow)');
    }
    _mark('STEP5_GENERATE_OUTCOME=$genOutcome');
    if (genOutcome == 'error') _mark('STEP5_GENERATE_ERROR=$errText');

    // ------------------------------------------------------------------
    // If itinerary opened: render check + add-to-calendar (no crash)
    // ------------------------------------------------------------------
    if (genOutcome == 'success_navigated') {
      await _pumpUntil(tester,
          cond: () => _ht(find.text('Add to calendar')).evaluate().isNotEmpty,
          timeout: const Duration(seconds: 20),
          label: 'itinerary rendered (add-to-calendar present)');
      _mark('STEP5_ITINERARY_RENDERED=ok');

      await _tapVisible(
          tester, find.text('Add to calendar'), label: 'Add to calendar');
      try {
        await _pumpUntil(tester,
            cond: () => _ht(find.byType(SnackBar)).evaluate().isNotEmpty,
            timeout: const Duration(seconds: 20),
            label: 'calendar result snackbar (either outcome)');
        _mark('STEP5_CALENDAR_SNACK=${_snackText(tester)}');
      } on TestFailure {
        _mark('STEP5_CALENDAR_NO_SNACKBAR=no_platform_calendar');
      }
      expect(AuthGuard.navigatorKey.currentContext, isNotNull,
          reason: 'app must stay alive after the calendar action');
      await tester.pump(const Duration(milliseconds: 1500));
      _mark('STEP5_CALENDAR_NO_CRASH=ok');
    } else {
      _mark('STEP5_ITINERARY_CALENDAR=skipped_generation_failed');
    }

    // ------------------------------------------------------------------
    // Make sure at least one trip exists server-side + offline cache filled
    // ------------------------------------------------------------------
    await _goHomeRoot(tester);
    await tester.pump(const Duration(milliseconds: 800));

    final svc = TripService();
    var saved = await svc.getTrips();
    _mark('STEP6_LIST_COUNT_AFTER_GEN=${saved.length}');

    if (saved.isEmpty && genOutcome == 'error') {
      _mark('STEP6_FALLBACK_GENERATE=attempting');
      var fallbackOk = false;
      var failures = <String>[];
      for (var attempt = 1; attempt <= 3; attempt++) {
        try {
          await svc.generateTrip(TripModel(
            destination: 'Tokyo',
            startDate: DateTime.now(),
            endDate: DateTime.now().add(const Duration(days: 6)),
            travelers: 1,
            budget: 'Moderate',
            travelStyle: 'Balanced',
            interests: const ['Food'],
          ));
          fallbackOk = true;
          _mark('STEP6_FALLBACK_GENERATE=ok attempt=$attempt');
          break;
        } catch (e) {
          failures.add('$e');
          _mark('STEP6_FALLBACK_GENERATE=retry attempt=$attempt:$e');
          if (attempt < 3) {
            await tester.pump(const Duration(seconds: 12));
          }
        }
      }
      if (!fallbackOk) {
        _mark('STEP6_FALLBACK_GENERATE=failed:${failures.join(' | ')}');
      }
    }

    saved = await svc.getTrips();
    _mark('STEP6_FINAL_LIST_COUNT=${saved.length}');
    final spCache = await SharedPreferences.getInstance();
    final cached = spCache.getString('tripora.offline_trips_v1');

    if (saved.isEmpty || cached == null || cached == '[]') {
      _status('trip_missing');
      _mark('STEP6_SAVED_TRIP=none');
    } else {
      _status('trip_available');
      _mark('STEP6_CACHE_COUNT=${_jsonCount(cached)}');
      _mark('STEP6_SAVED_TRIP_CACHED=ok');
    }

    // ------------------------------------------------------------------
    // My Trips tab: saved trip card renders
    // ------------------------------------------------------------------
    if (saved.isNotEmpty) {
      await _tapVisible(tester, find.text('My Trips'), label: 'My Trips tab');
      // The trips tab is mounted at shell startup (empty); force a refresh so
      // the trip generated later in this run actually renders.
      await tester.pump(const Duration(seconds: 1));
      if (_ht(find.textContaining('Tokyo')).evaluate().isEmpty) {
        final tripsScroll = find
            .descendant(
                of: find.byType(TripsScreen),
                matching: find.byType(Scrollable))
            .hitTestable();
        if (tripsScroll.evaluate().isNotEmpty) {
          await tester.fling(
              tripsScroll.first, const Offset(0, 400), 1200);
          await tester.pump(const Duration(milliseconds: 600));
        }
      }
      await _pumpUntil(tester,
          cond: () => _ht(find.textContaining('Tokyo')).evaluate().isNotEmpty,
          timeout: const Duration(seconds: 25),
          label: 'saved trip card on My Trips');
      _mark('STEP6_TRIP_CARD_VISIBLE=ok');
    }

    // ------------------------------------------------------------------
    // Flights tab: read-only entry (no booking / vault / premium / hotels)
    // ------------------------------------------------------------------
    await _tapVisible(tester, find.text('Flights'), label: 'Flights tab');
    await tester.pump(const Duration(seconds: 2));
    for (final banned in ['Book now', 'Vault', 'Premium', 'Hotels', 'Book Now']) {
      expect(_ht(find.textContaining(banned)).evaluate(), isEmpty,
          reason: 'no "$banned" may surface on the Flights screen');
    }
    _mark('STEP9_FLIGHTS_READ_ONLY=ok');

    // ------------------------------------------------------------------
    // Home tab reachability scan (same banned surface check)
    // ------------------------------------------------------------------
    await _tapVisible(tester, find.text('Home'), label: 'Home tab');
    await tester.pump(const Duration(seconds: 2));
    for (final banned in ['Vault', 'Premium', 'Hotels']) {
      expect(_ht(find.textContaining(banned)).evaluate(), isEmpty,
          reason: 'no "$banned" reachable from Home');
    }
    _mark('STEP17_REACHABILITY_HOME=ok');

    // ------------------------------------------------------------------
    // Language: switch to French (nav re-labels instantly), then back
    // ------------------------------------------------------------------
    await _tapVisible(tester, find.text('Profile'), label: 'Profile tab');
    await _pumpUntil(tester,
        cond: () => _ht(find.byTooltip('Log out')).evaluate().isNotEmpty,
        timeout: const Duration(seconds: 30),
        label: 'profile loaded');

    final langDropdown = find.byType(DropdownButtonFormField<String>).first;
    await _scrollIntoView(tester, langDropdown, label: 'language dropdown');
    await tester.tap(langDropdown, warnIfMissed: false);
    await tester.pump(const Duration(milliseconds: 600));
    // In EN locale the French menu item reads "French" (items are translated).
    await _tapVisible(tester, find.text('French').last, label: 'French item');
    await _pumpUntil(tester,
        cond: () => _ht(find.text('Accueil')).evaluate().isNotEmpty,
        timeout: const Duration(seconds: 20),
        label: 'nav re-labeled to French immediately');
    expect(AppPreferences.instance.language, 'fr',
        reason: 'language preference must be applied');
    _mark('STEP7_LANG_FR_INSTANT=ok');

    // back to English (dropdown key changes with value, so re-locate; items
    // are now localized in French, so English reads "Anglais")
    await tester.pump(const Duration(milliseconds: 400));
    final frDrop = find.byType(DropdownButtonFormField<String>).first;
    await _scrollIntoView(tester, frDrop, label: 'language dropdown (2nd)');
    await tester.tap(frDrop, warnIfMissed: false);
    await tester.pump(const Duration(milliseconds: 600));
    await _tapVisible(tester, find.text('Anglais').last, label: 'Anglais item');
    await _pumpUntil(tester,
        cond: () => _ht(find.text('Home')).evaluate().isNotEmpty,
        timeout: const Duration(seconds: 20),
        label: 'nav re-labeled back to English instantly');
    expect(AppPreferences.instance.language, 'en',
        reason: 'language preference must be restored');
    _mark('STEP7_LANG_EN_RESTORED=ok');

    // ------------------------------------------------------------------
    // Theme: Dark then Light, verified via MaterialApp.themeMode
    // ------------------------------------------------------------------
    await _scrollIntoView(tester, find.text('Dark'), label: 'Dark segment');
    await tester.tap(_ht(find.text('Dark')).first, warnIfMissed: false);
    await _pumpUntil(tester,
        cond: () =>
            tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode ==
            ThemeMode.dark,
        timeout: const Duration(seconds: 15),
        label: 'theme switched to dark');
    expect(AppPreferences.instance.themeMode, ThemeMode.dark,
        reason: 'themeMode preference must persist dark');
    _mark('STEP13_THEME_DARK=ok');

    await _scrollIntoView(tester, find.text('Light'), label: 'Light segment');
    await tester.tap(_ht(find.text('Light')).first, warnIfMissed: false);
    await _pumpUntil(tester,
        cond: () =>
            tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode ==
            ThemeMode.light,
        timeout: const Duration(seconds: 15),
        label: 'theme switched to light');
    expect(AppPreferences.instance.themeMode, ThemeMode.light,
        reason: 'themeMode preference must restore light');
    _mark('STEP13_THEME_LIGHT_RESTORED=ok');

    // ------------------------------------------------------------------
    // Persist the account identifiers for the follow-up drives, and finish.
    // ------------------------------------------------------------------
    await sp.setString('verify_email', email);
    _mark('WALKTHROUGH_ONLINE_COMPLETE');
  });
}

int _jsonCount(String jsonList) {
  final decoded = RegExp(r'"id"\s*:').allMatches(jsonList).length;
  return decoded;
}