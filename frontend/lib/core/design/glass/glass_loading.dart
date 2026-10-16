import 'package:flutter/material.dart';

import 'glass_tokens.dart';

/// ---------------------------------------------------------------------
/// Glass loading primitives
///
/// A shimmering skeleton block that respects reduced-motion settings, plus
/// a small helper that lays out a stack of them.
/// ---------------------------------------------------------------------

class GlassSkeleton extends StatefulWidget {
  const GlassSkeleton({
    super.key,
    this.width = double.infinity,
    required this.height,
    this.radius = GlassRadius.sm,
  });

  final double width;
  final double height;
  final double radius;

  @override
  State<GlassSkeleton> createState() => _GlassSkeletonState();
}

class _GlassSkeletonState extends State<GlassSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );

  @override
  void initState() {
    super.initState();
    _controller.repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final glass = context.glass;

    final base = (glass.isDark ? Colors.white : Colors.black)
        .withValues(alpha: glass.isDark ? 0.06 : 0.05);
    final sheen = (glass.isDark ? Colors.white : Colors.black)
        .withValues(alpha: glass.isDark ? 0.14 : 0.09);

    final radius = BorderRadius.circular(widget.radius);

    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
      return _block(base, radius);
    }

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return ShaderMask(
          blendMode: BlendMode.srcATop,
          shaderCallback: (bounds) {
            return LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: [base, sheen, base],
              stops: const [0.1, 0.5, 0.9],
              transform: _SlidingGradientTransform(
                percent: _controller.value,
              ),
            ).createShader(bounds);
          },
          child: _block(sheen, radius),
        );
      },
    );
  }

  Widget _block(Color color, BorderRadius radius) {
    return Container(
      width: widget.width,
      height: widget.height,
      decoration: BoxDecoration(color: color, borderRadius: radius),
    );
  }
}

/// A ready-made stack of skeletons for list/card placeholders.
class GlassSkeletonList extends StatelessWidget {
  const GlassSkeletonList({
    super.key,
    this.itemCount = 4,
    this.itemHeight = 84,
    this.spacing = 12,
    this.padding = const EdgeInsets.all(16),
  });

  final int itemCount;
  final double itemHeight;
  final double spacing;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: Column(
        children: [
          for (var i = 0; i < itemCount; i++) ...[
            GlassSkeleton(height: itemHeight, radius: GlassRadius.md),
            if (i != itemCount - 1) SizedBox(height: spacing),
          ],
        ],
      ),
    );
  }
}

class _SlidingGradientTransform extends GradientTransform {
  const _SlidingGradientTransform({required this.percent});

  final double percent;

  @override
  Matrix4? transform(Rect bounds, {TextDirection? textDirection}) {
    final dx = bounds.width * (percent * 2 - 1);
    return Matrix4.translationValues(dx, 0, 0);
  }
}
