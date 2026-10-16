import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:frontend/main.dart';

void main() {
  testWidgets('Tripora home page loads', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({'access_token': 'test-token'});

    await tester.pumpWidget(const TriporaApp());

    // Splash sequence: 1100ms delay + 400ms exit fade, then the pushed
    // home route needs a frame to build and its transition to finish.
    await tester.pump(const Duration(milliseconds: 1500));
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('Tripora'), findsOneWidget);
    expect(
      find.text('Where will the next journey take you?'),
      findsOneWidget,
    );
    expect(find.text('Start planning'), findsOneWidget);
  });
}