import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:frontend/core/auth/login_gate.dart';
import 'package:frontend/routes/app_routes.dart';
import 'package:frontend/screens/main_shell.dart';

void main() {
  setUp(() {
    LoginGate.clear();
    MainShell.currentIndex.value = 0;
  });

  test('isProtected flags only guarded routes', () {
    expect(LoginGate.isProtected(AppRoutes.planner), isTrue);
    expect(LoginGate.isProtected(AppRoutes.trips), isTrue);
    expect(LoginGate.isProtected(AppRoutes.profile), isTrue);
    expect(LoginGate.isProtected(AppRoutes.itinerary), isTrue);

    expect(LoginGate.isProtected(AppRoutes.home), isFalse);
    expect(LoginGate.isProtected(AppRoutes.explore), isFalse);
    expect(LoginGate.isProtected(AppRoutes.login), isFalse);
    expect(LoginGate.isProtected(null), isFalse);
  });

  testWidgets(
    'guest is sent to Login and continues to the requested route after login',
    (tester) async {
      SharedPreferences.setMockInitialValues({}); // no token -> guest

      await tester.pumpWidget(_harness(onLogin: LoginGate.apply));

      expect(find.text('HOME'), findsOneWidget);

      // Tapping "Plan" as a guest must not open the Planner directly.
      await tester.tap(find.text('OPEN_PLANNER'));
      await tester.pumpAndSettle();

      expect(find.text('LOGIN'), findsOneWidget);
      expect(find.text('PLANNER'), findsNothing);

      // After signing in, the user continues to the Planner.
      await tester.tap(find.text('CONTINUE'));
      await tester.pumpAndSettle();

      expect(find.text('PLANNER'), findsOneWidget);
    },
  );

  testWidgets(
    'signed-in user opens the requested route without seeing Login',
    (tester) async {
      SharedPreferences.setMockInitialValues({'access_token': 'test-token'});

      await tester.pumpWidget(_harness(onLogin: LoginGate.apply));

      await tester.tap(find.text('OPEN_PLANNER'));
      await tester.pumpAndSettle();

      expect(find.text('PLANNER'), findsOneWidget);
      expect(find.text('LOGIN'), findsNothing);
    },
  );

  testWidgets(
    'guest guarding a tab is returned to that tab after login',
    (tester) async {
      SharedPreferences.setMockInitialValues({}); // no token -> guest

      await tester.pumpWidget(
        _harness(
          onLogin: LoginGate.apply,
          onGuardTab: (context) =>
              LoginGate.openTab(context, tabIndex: LoginGate.profileTab),
        ),
      );

      await tester.tap(find.text('OPEN_PROFILE_TAB'));
      await tester.pumpAndSettle();

      expect(find.text('LOGIN'), findsOneWidget);

      await tester.tap(find.text('CONTINUE'));
      await tester.pumpAndSettle();

      // Shell is shown and the Profile tab is selected.
      expect(find.text('HOME'), findsOneWidget);
      expect(MainShell.currentIndex.value, LoginGate.profileTab);
    },
  );
}

/// Minimal app that mirrors the real route names so we can exercise the gate
/// without building the real screens (which hit the network).
Widget _harness({
  required void Function(BuildContext) onLogin,
  void Function(BuildContext)? onGuardTab,
}) {
  return MaterialApp(
    initialRoute: AppRoutes.home,
    routes: {
      AppRoutes.home: (_) => Scaffold(
            body: Builder(
              builder: (context) => Column(
                children: [
                  const Text('HOME'),
                  TextButton(
                    onPressed: () => LoginGate.open(
                      context,
                      route: AppRoutes.planner,
                    ),
                    child: const Text('OPEN_PLANNER'),
                  ),
                  if (onGuardTab != null)
                    TextButton(
                      onPressed: () => onGuardTab(context),
                      child: const Text('OPEN_PROFILE_TAB'),
                    ),
                ],
              ),
            ),
          ),
      AppRoutes.login: (_) => Scaffold(
            body: Builder(
              builder: (context) => Column(
                children: [
                  const Text('LOGIN'),
                  TextButton(
                    onPressed: () => onLogin(context),
                    child: const Text('CONTINUE'),
                  ),
                ],
              ),
            ),
          ),
      AppRoutes.planner: (_) => const Scaffold(body: Text('PLANNER')),
    },
  );
}
