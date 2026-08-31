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

/// List of trip cards skeleton loader (for the My Trips screen).
class TripsScreenShimmer extends StatelessWidget {
  const TripsScreenShimmer({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      itemCount: 4,
      itemBuilder: (context, index) => const Padding(
        padding: EdgeInsets.only(bottom: 12),
        child: TripCardShimmer(),
      ),
    );
  }
}

/// Profile screen skeleton loader (avatar block + form fields).
class ProfileScreenShimmer extends StatelessWidget {
  const ProfileScreenShimmer({super.key});

  @override
  Widget build(BuildContext context) {
    return const SingleChildScrollView(
      padding: EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Card(
            child: Padding(
              padding: EdgeInsets.all(20),
              child: Row(
                children: [
                  ShimmerLoader(width: 64, height: 64, borderRadius: BorderRadius.all(Radius.circular(32))),
                  SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ShimmerLoader(width: 160, height: 20, borderRadius: BorderRadius.all(Radius.circular(4))),
                        SizedBox(height: 10),
                        ShimmerLoader(width: 120, height: 14, borderRadius: BorderRadius.all(Radius.circular(4))),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          SizedBox(height: 20),
          Card(
            child: Padding(
              padding: EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ShimmerLoader(width: double.infinity, height: 48, borderRadius: BorderRadius.all(Radius.circular(14))),
                  SizedBox(height: 12),
                  ShimmerLoader(width: double.infinity, height: 48, borderRadius: BorderRadius.all(Radius.circular(14))),
                  SizedBox(height: 12),
                  ShimmerLoader(width: double.infinity, height: 48, borderRadius: BorderRadius.all(Radius.circular(14))),
                  SizedBox(height: 12),
                  ShimmerLoader(width: double.infinity, height: 48, borderRadius: BorderRadius.all(Radius.circular(14))),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Trip details screen skeleton loader (hero + body blocks).
class TripDetailsShimmer extends StatelessWidget {
  const TripDetailsShimmer({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.only(bottom: 32),
      children: const [
        ShimmerLoader(height: 220, borderRadius: BorderRadius.zero),
        Padding(
          padding: EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ShimmerLoader(width: double.infinity, height: 28, borderRadius: BorderRadius.all(Radius.circular(6))),
              SizedBox(height: 12),
              ShimmerLoader(width: 180, height: 16, borderRadius: BorderRadius.all(Radius.circular(4))),
              SizedBox(height: 24),
              ShimmerLoader(width: double.infinity, height: 90, borderRadius: BorderRadius.all(Radius.circular(16))),
              SizedBox(height: 20),
              ShimmerLoader(width: double.infinity, height: 90, borderRadius: BorderRadius.all(Radius.circular(16))),
              SizedBox(height: 20),
              ShimmerLoader(width: double.infinity, height: 90, borderRadius: BorderRadius.all(Radius.circular(16))),
            ],
          ),
        ),
      ],
    );
  }
}

/// Premium screen skeleton loader.
class PremiumScreenShimmer extends StatelessWidget {
  const PremiumScreenShimmer({super.key});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: const [
          ShimmerLoader(height: 160, borderRadius: BorderRadius.all(Radius.circular(16))),
          SizedBox(height: 20),
          ShimmerLoader(height: 90, borderRadius: BorderRadius.all(Radius.circular(16))),
          SizedBox(height: 20),
          ShimmerLoader(height: 90, borderRadius: BorderRadius.all(Radius.circular(16))),
          SizedBox(height: 20),
          ShimmerLoader(height: 70, borderRadius: BorderRadius.all(Radius.circular(16))),
        ],
      ),
    );
  }
}
