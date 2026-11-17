import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:frontend/main.dart';

void main() {
  testWidgets('Tripora home page loads', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({'access_token': 'test-token'});
    // Phone window: Home shows its own app bar with the wordmark (from
    // 768 px the rail / sidebar replaces it).
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const TriporaApp());

    // Splash sequence: 1100ms delay + 400ms exit fade, then the pushed
    // home route needs a frame to build and its transition to finish.
    await tester.pump(const Duration(milliseconds: 1500));
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    // Tripora 2.0 Home: brand, discovery hero (no trips in this test, so
    // no countdown), the AI command bar and the accent aura cards.
    expect(find.text('TRIPORA'), findsOneWidget);
    expect(find.text('Plan this trip'), findsOneWidget);
    expect(find.text('DESTINATION-DRIVEN ACCENT AURAS'), findsOneWidget);
    expect(find.textContaining('days to departure'), findsNothing);
  });
}