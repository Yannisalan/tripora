// Login/Register on the native path (widget tests run with kIsWeb == false,
// like Android/iOS): with third-party sign-in gated off there must be no
// orphaned "or with email" divider, no Google/Apple buttons, and the email
// + password form must still be there.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:frontend/core/auth/auth_guard.dart';
import 'package:frontend/core/auth/token_store.dart';
import 'package:frontend/core/config/app_config.dart';
import 'package:frontend/screens/auth/login_screen.dart';
import 'package:frontend/screens/auth/register_screen.dart';
import 'package:frontend/screens/main_shell.dart';

import 'support/probe_harness.dart';

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

  test('third-party sign-in is still gated off', () {
    expect(AppConfig.showThirdPartyAuth, isFalse);
  });

  for (final entry in <String, Widget>{
    'login': const LoginScreen(),
    'register': const RegisterScreen(),
  }.entries) {
    testWidgets('${entry.key}: no orphaned divider, email form intact', (
      tester,
    ) async {
      addTearDown(tester.view.reset);
      await pumpShell(tester, const Size(390, 844));
      AuthGuard.navigatorKey.currentState!.push(
        MaterialPageRoute<void>(builder: (_) => entry.value),
      );
      await settle(tester);
      await tester.pump(const Duration(milliseconds: 400));

      final screen = find.byWidget(entry.value);
      expect(screen, findsOneWidget);
      expect(
        find.descendant(of: screen, matching: find.byType(Divider)),
        findsNothing,
        reason: 'divider shown with no social buttons above it',
      );
      expect(find.text('or with email'), findsNothing);
      expect(find.textContaining('Continue with Google'), findsNothing);
      expect(find.textContaining('Continue with Apple'), findsNothing);

      // Email/password flow still present.
      expect(
        find.descendant(of: screen, matching: find.byType(TextFormField)),
        findsAtLeastNWidgets(2),
      );
      expect(tester.takeException(), isNull);
    });
  }
}
