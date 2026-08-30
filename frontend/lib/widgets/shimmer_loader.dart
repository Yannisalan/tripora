import 'package:flutter/material.dart';

/// Reusable shimmer loading skeleton that mimics content while loading
class ShimmerLoader extends StatefulWidget {
  final double width;
  final double height;
  final BorderRadius borderRadius;
  final EdgeInsets margin;

  const ShimmerLoader({
    super.key,
    this.width = double.infinity,
    this.height = 100,
    BorderRadius? borderRadius,
    this.margin = EdgeInsets.zero,
  }) : borderRadius =
           borderRadius ?? const BorderRadius.all(Radius.circular(8));

  @override
  State<ShimmerLoader> createState() => _ShimmerLoaderState();
}

class _ShimmerLoaderState extends State<ShimmerLoader>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(seconds: 1),
      vsync: this,
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Container(
          margin: widget.margin,
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            borderRadius: widget.borderRadius,
            gradient: LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              stops: [
                (_controller.value - 0.3).clamp(0, 1).toDouble(),
                _controller.value.clamp(0, 1).toDouble(),
                (_controller.value + 0.3).clamp(0, 1).toDouble(),
              ],
              colors: [
                const Color(0xFFE5E7EB),
                const Color(0xFFF3F4F6),
                const Color(0xFFE5E7EB),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Trip card skeleton loader
class TripCardShimmer extends StatelessWidget {
  final bool isCompact;

  const TripCardShimmer({super.key, this.isCompact = false});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ShimmerLoader(
              width: double.infinity,
              height: 24,
              borderRadius: const BorderRadius.all(Radius.circular(4)),
              margin: const EdgeInsets.only(bottom: 8),
            ),
            ShimmerLoader(
              width: 150,
              height: 16,
              borderRadius: const BorderRadius.all(Radius.circular(4)),
            ),
          ],
        ),
      ),
    );
  }
}

/// Destination card skeleton loader
class DestinationCardShimmer extends StatelessWidget {
  final double width;

  const DestinationCardShimmer({super.key, this.width = 300});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Card(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: ShimmerLoader(
                width: double.infinity,
                height: 200,
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
              child: ShimmerLoader(
                width: double.infinity,
                height: 18,
                borderRadius: const BorderRadius.all(Radius.circular(4)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
