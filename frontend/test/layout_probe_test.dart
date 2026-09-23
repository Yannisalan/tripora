import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:frontend/main.dart';
import 'package:frontend/screens/main_shell.dart';

void main() {
  const widths = <double>[320, 360, 400, 480, 560, 720, 900, 1200];

  for (final width in widths) {
    testWidgets('shell renders clean at width $width', (tester) async {
      tester.view.physicalSize = Size(width, 860);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      SharedPreferences.setMockInitialValues({'access_token': 'test-token'});

      await tester.pumpWidget(const TriporaApp());
      await tester.pump(const Duration(milliseconds: 1500));
      await tester.pump(const Duration(milliseconds: 50));

      for (final tab in [0, 1, 2, 3, 4]) {
        MainShell.currentIndex.value = tab;
        await tester.pump(const Duration(milliseconds: 50));
      }
      MainShell.currentIndex.value = 0;

      final exception = tester.takeException();
      expect(exception, isNull,
          reason: 'layout exception at width $width: $exception');
    });
  }

  testWidgets('shell stays clean across window resizes', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    SharedPreferences.setMockInitialValues({'access_token': 'test-token'});

    await tester.pumpWidget(const TriporaApp());
    await tester.pump(const Duration(milliseconds: 1500));

    for (var i = 0; i < 5; i++) {
      MainShell.currentIndex.value = i % 5;
      tester.view.physicalSize =
          Size(900.0 - i * 100.0, 900.0);
      await tester.pump(const Duration(milliseconds: 50));
    }

    final exception = tester.takeException();
    expect(exception, isNull, reason: 'resize exception: $exception');
  });

  testWidgets('shell stays clean at large text scale', (tester) async {
    tester.view.physicalSize = const Size(400, 860);
    tester.view.devicePixelRatio = 1.0;
    tester.platformDispatcher.textScaleFactorTestValue = 1.3;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    addTearDown(tester.view.reset);

    SharedPreferences.setMockInitialValues({'access_token': 'test-token'});

    await tester.pumpWidget(const TriporaApp());
    await tester.pump(const Duration(milliseconds: 1500));
    await tester.pump(const Duration(milliseconds: 50));

    final exception = tester.takeException();
    expect(exception, isNull, reason: 'text-scale exception: $exception');
  });

  testWidgets('flights tab: dropdown toggle under resize stays clean',
      (tester) async {
    tester.view.physicalSize = const Size(420, 860);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    SharedPreferences.setMockInitialValues({'access_token': 'test-token'});

    await tester.pumpWidget(const TriporaApp());
    await tester.pump(const Duration(milliseconds: 1500));

    MainShell.currentIndex.value = 2;
    await tester.pump(const Duration(milliseconds: 100));

    for (var i = 0; i < 4; i++) {
      final cabin = tester.widgetList<DropdownButtonFormField<String>>(
        find.byType(DropdownButtonFormField<String>),
      );
      if (cabin.isNotEmpty) {
        await tester.tap(find.byType(DropdownButtonFormField<String>).last);
        await tester.pump(const Duration(milliseconds: 150));
      }

      tester.view.physicalSize = Size(700.0 - i * 90.0, 860.0);
      await tester.pump(const Duration(milliseconds: 100));
      tester.view.physicalSize = Size(460.0 + i * 70.0, 860.0);
      await tester.pump(const Duration(milliseconds: 100));
    }

    final exception = tester.takeException();
    expect(exception, isNull, reason: 'dropdown/resize exception: $exception');
  });

  testWidgets('flights tab: date picker + segment toggle under resize stays '
      'clean', (tester) async {
    tester.view.physicalSize = const Size(380, 860);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    SharedPreferences.setMockInitialValues({'access_token': 'test-token'});

    await tester.pumpWidget(const TriporaApp());
    await tester.pump(const Duration(milliseconds: 1500));

    MainShell.currentIndex.value = 2;
    await tester.pump(const Duration(milliseconds: 100));

    final segment = find.text('Whole month');
    if (segment.evaluate().isNotEmpty) {
      await tester.tap(segment);
      await tester.pump(const Duration(milliseconds: 300));
    }

    tester.view.physicalSize = const Size(360, 860);
    await tester.pump(const Duration(milliseconds: 100));

    final departFields =
        find.byType(TextFormField).evaluate().toList();
    final depart = departFields.length >= 3
        ? find.byWidget(departFields[2].widget)
        : find.text('Depart date or month');
    if (depart.evaluate().isNotEmpty) {
      await tester.tap(depart);
      await tester.pump(const Duration(milliseconds: 300));
      final cancel = find.text('CANCEL');
      if (cancel.evaluate().isNotEmpty) {
        await tester.tap(cancel);
        await tester.pump(const Duration(milliseconds: 300));
      }
    }

    final exception = tester.takeException();
    expect(exception, isNull, reason: 'picker/segment exception: $exception');
  });

  testWidgets('flights tab: rapid desktop-style window resizes stay clean',
      (tester) async {
    tester.view.physicalSize = const Size(1000, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    SharedPreferences.setMockInitialValues({'access_token': 'test-token'});

    await tester.pumpWidget(const TriporaApp());
    await tester.pump(const Duration(milliseconds: 1500));

    MainShell.currentIndex.value = 2;
    await tester.pump(const Duration(milliseconds: 100));

    for (var i = 0; i < 8; i++) {
      final w = 340.0 + (i * 130) % 600;
      tester.view.physicalSize = Size(w, 800.0);
      await tester.pump(const Duration(milliseconds: 16));
    }

    final exception = tester.takeException();
    expect(exception, isNull, reason: 'rapid resize exception: $exception');
  });

  testWidgets('high churn: tabs + resize + text scale stay clean',
      (tester) async {
    tester.view.physicalSize = const Size(1000, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    SharedPreferences.setMockInitialValues({'access_token': 'test-token'});

    await tester.pumpWidget(const TriporaApp());
    await tester.pump(const Duration(milliseconds: 1500));

    for (var i = 0; i < 20; i++) {
      MainShell.currentIndex.value = i % 5;
      tester.view.physicalSize = Size(300.0 + (i * 47) % 500, 800.0);
      tester.platformDispatcher.textScaleFactorTestValue =
          1.0 + (i % 4) * 0.1;
      await tester.pump(const Duration(milliseconds: 16));
      final pending = tester.takeException();
      if (pending case final e?) {
        final w = tester.view.physicalSize;
        throw StateError('exception at i=$i width=$w: $e');
      }
    }
  });

  testWidgets('isolate: 317px width, scale 1.3, explore tab', (tester) async {
    tester.view.physicalSize = const Size(317, 800);
    tester.view.devicePixelRatio = 1.0;
    tester.platformDispatcher.textScaleFactorTestValue = 1.3;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    SharedPreferences.setMockInitialValues({'access_token': 'test-token'});

    await tester.pumpWidget(const TriporaApp());
    await tester.pump(const Duration(milliseconds: 1500));
    MainShell.currentIndex.value = 1;
    await tester.pump(const Duration(milliseconds: 16));

    final exception = tester.takeException();
    expect(exception, isNull, reason: 'isolate exception: $exception');
  });
}