import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:frontend/main.dart';
import 'package:frontend/screens/main_shell.dart';

void main() {
  testWidgets('desktop width shows web top navigation', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    SharedPreferences.setMockInitialValues({'access_token': 'test-token'});

    await tester.pumpWidget(const TriporaApp());
    // Splash: 1100ms delay + 400ms exit fade, then the replaced route
    // needs a frame to build and its transition to finish.
    await tester.pump(const Duration(milliseconds: 1500));
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('Plan a Trip'), findsOneWidget);
    for (final label in ['Home', 'Explore', 'Flights', 'My Trips', 'Profile']) {
      expect(find.text(label), findsWidgets,
          reason: 'web nav should contain $label');
    }
  });

  testWidgets('mobile width shows bottom navigation, no top nav',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    SharedPreferences.setMockInitialValues({'access_token': 'test-token'});

    await tester.pumpWidget(const TriporaApp());
    await tester.pump(const Duration(milliseconds: 1500));
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    // On native mobile there is no web header. Home keeps its own inner
    // app bar with the Plan Trip CTA (only one), and the primary
    // navigation is the bottom bar.
    expect(find.text('Plan a Trip'), findsOneWidget);
    expect(find.byIcon(Icons.menu_rounded), findsNothing);
    for (final label in ['Home', 'Explore', 'Flights', 'My Trips', 'Profile']) {
      expect(find.text(label), findsWidgets,
          reason: 'bottom nav should contain $label');
    }
  });

  testWidgets('crossing breakpoint preserves tag selection', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    SharedPreferences.setMockInitialValues({'access_token': 'test-token'});

    await tester.pumpWidget(const TriporaApp());
    await tester.pump(const Duration(milliseconds: 1500));
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    // Select the Profile tab while wide.
    MainShell.currentIndex.value = 4;
    await tester.pump(const Duration(milliseconds: 50));

    // Shrink below the breakpoint: tabs must still work with bottom nav.
    tester.view.physicalSize = const Size(700, 900);
    await tester.pump(const Duration(milliseconds: 50));
    expect(MainShell.currentIndex.value, 4);

    MainShell.currentIndex.value = 1;
    await tester.pump(const Duration(milliseconds: 50));
    expect(MainShell.currentIndex.value, 1);

    // Grow again: navigation stays responsive, active tab state is kept.
    tester.view.physicalSize = const Size(1440, 900);
    await tester.pump(const Duration(milliseconds: 50));
    expect(MainShell.currentIndex.value, 1);
    for (final label in ['Home', 'Explore', 'Flights', 'My Trips', 'Profile']) {
      expect(find.text(label), findsWidgets,
          reason: 'navigation should still contain $label');
    }

    final exception = tester.takeException();
    expect(exception, isNull, reason: 'breakpoint exception: $exception');
  });
}