import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _tile({required IconData icon}) {
  return Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: Colors.black12),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Icon(icon, size: 15, color: Colors.grey),
            const SizedBox(width: 6),
            const Expanded(
              child: Text('label', style: TextStyle(fontSize: 9)),
            ),
          ],
        ),
        const SizedBox(height: 8),
        const Text('value', style: TextStyle(fontSize: 18)),
      ],
    ),
  );
}

void main() {
  // Reproduces the reported crash: a Row with
  // CrossAxisAlignment.stretch inside a LayoutBuilder placed in a
  // ListView (unbounded height). Before the fix this gave every card
  // an infinite min-height, surfacing as "RenderBox was not laid out".
  Widget buildStatsRowProbe() {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.only(bottom: 40),
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final isNarrow = constraints.maxWidth < 500;

            final tiles = <Widget>[
              _tile(icon: Icons.account_balance_wallet_outlined),
              _tile(icon: Icons.map_outlined),
              _tile(icon: Icons.schedule_outlined),
            ];

            if (isNarrow) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: tiles
                    .map(
                      (tile) => Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: tile,
                      ),
                    )
                    .toList(),
              );
            }

            return IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: tiles
                    .map(
                      (tile) => Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 6),
                          child: tile,
                        ),
                      ),
                    )
                    .toList(),
              ),
            );
          },
        ),
      ],
    );
  }

  for (final width in [320.0, 480.0, 560.0, 900.0, 1200.0]) {
    testWidgets('stats row lays out clean at width $width', (tester) async {
      tester.view.physicalSize = Size(width, 860);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: buildStatsRowProbe())),
      );
      await tester.pump(const Duration(milliseconds: 50));

      final exception = tester.takeException();
      expect(exception, isNull,
          reason: 'layout exception at width $width: $exception');
    });
  }

  testWidgets('stats row cards have finite non-zero size in wide branch',
      (tester) async {
    tester.view.physicalSize = const Size(900, 860);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: buildStatsRowProbe())),
    );
    await tester.pump(const Duration(milliseconds: 50));

    final cards = tester.renderObjectList<RenderBox>(find.byType(Container));
    expect(cards, isNotEmpty);
    for (final box in cards) {
      expect(box.size.height, greaterThan(0),
          reason: 'card was not laid out: ${box.toString()}');
      expect(box.size.height.isFinite, isTrue);
      expect(box.size.width.isFinite, isTrue);
    }
  });
}