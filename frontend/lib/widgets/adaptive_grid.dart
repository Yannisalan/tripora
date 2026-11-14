import 'package:flutter/material.dart';

/// A non-scrolling grid for small card sets inside a scrolling page.
///
/// Drop-in replacement for `GridView.count(shrinkWrap: true,
/// physics: NeverScrollableScrollPhysics(), childAspectRatio: r, ...)`.
///
/// `childAspectRatio` there fixes every cell's height, so a longer
/// translation or a larger text scale overflows the card. Here the ratio is
/// a *minimum*: each cell keeps the original proportions when its content
/// fits, and a row grows to its tallest card when it does not. All cards in
/// a row share that height, so the grid still reads as a grid.
class AdaptiveGrid extends StatelessWidget {
  const AdaptiveGrid({
    super.key,
    required this.columns,
    required this.children,
    this.spacing = 12,
    this.runSpacing = 12,
    this.minChildAspectRatio,
  }) : assert(columns > 0);

  final int columns;
  final List<Widget> children;

  /// Horizontal gap between cells.
  final double spacing;

  /// Vertical gap between rows.
  final double runSpacing;

  /// width / height of a cell when its content fits. Null means cells are
  /// exactly as tall as their content.
  final double? minChildAspectRatio;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final cellWidth =
            (constraints.maxWidth - spacing * (columns - 1)) / columns;
        final minHeight = minChildAspectRatio == null
            ? 0.0
            : cellWidth / minChildAspectRatio!;

        final rows = <Widget>[];
        for (var start = 0; start < children.length; start += columns) {
          if (rows.isNotEmpty) rows.add(SizedBox(height: runSpacing));
          rows.add(
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var c = 0; c < columns; c++) ...[
                    if (c > 0) SizedBox(width: spacing),
                    SizedBox(
                      width: cellWidth,
                      child: start + c < children.length
                          ? ConstrainedBox(
                              constraints:
                                  BoxConstraints(minHeight: minHeight),
                              child: children[start + c],
                            )
                          : null,
                    ),
                  ],
                ],
              ),
            ),
          );
        }

        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: rows,
        );
      },
    );
  }
}
