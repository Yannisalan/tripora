import 'package:flutter_test/flutter_test.dart';

import 'package:frontend/main.dart';

void main() {
  testWidgets('Tripora home page loads', (WidgetTester tester) async {
    await tester.pumpWidget(const TriporaApp());

    expect(find.text('Tripora'), findsOneWidget);
    expect(find.text('Your journey.\nPowered by AI.'), findsOneWidget);
    expect(find.text('Start Planning'), findsOneWidget);
  });
}