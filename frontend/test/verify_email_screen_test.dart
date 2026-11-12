import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/core/theme/app_theme.dart';
import 'package:frontend/screens/auth/verify_email_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  Future<void> pump(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1200));
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: const VerifyEmailScreen(email: 'traveler@example.com'),
      ),
    );
    await tester.pump();
  }

  testWidgets('shows the address, code field and a resend cooldown',
      (tester) async {
    await pump(tester);

    expect(find.textContaining('traveler@example.com'), findsOneWidget);
    expect(find.byKey(const Key('verifyEmailCode')), findsOneWidget);
    // Resend is locked during the initial 60 s cooldown.
    expect(find.textContaining('60'), findsWidgets);

    // Drain the cooldown timer so the test ends cleanly.
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('rejects a code that is not 6 digits without calling the API',
      (tester) async {
    await pump(tester);

    await tester.enterText(find.byKey(const Key('verifyEmailCode')), '12a3');
    await tester.tap(find.text('Verify email'));
    await tester.pump();

    expect(find.text('Enter the 6-digit code.'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
