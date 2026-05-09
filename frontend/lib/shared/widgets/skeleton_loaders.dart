import 'package:flutter/material.dart';

/// Shimmer effect for skeleton loaders
class Shimmer extends StatefulWidget {
  final Widget child;
  final Color baseColor;
  final Color highlightColor;

  const Shimmer({
    super.key,
    required this.child,
    this.baseColor = const Color(0xFFE0E0E0),
    this.highlightColor = const Color(0xFFF5F5F5),
  });

  @override
  State<Shimmer> createState() => _ShimmerState();
}

class _ShimmerState extends State<Shimmer> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat();

    _animation = Tween<double>(
      begin: -1.0,
      end: 2.0,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeInOut,
    ));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return ShaderMask(
          shaderCallback: (bounds) {
            return LinearGradient(
              colors: [
                widget.baseColor,
                widget.highlightColor,
                widget.baseColor,
              ],
              stops: const [0.0, 0.5, 1.0],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              transform: _SlidingGradientTransform(_animation.value),
            ).createShader(bounds);
          },
          blendMode: BlendMode.srcATop,
          child: widget.child,
        );
      },
      child: widget.child,
    );
  }
}

class _SlidingGradientTransform extends GradientTransform {
  final double percent;

  const _SlidingGradientTransform(this.percent);

  @override
  Matrix4? transform(Rect bounds, {TextDirection? textDirection}) {
    return Matrix4.translationValues(bounds.width * percent, 0, 0);
  }
}

/// Base skeleton widget
class Skeleton extends StatelessWidget {
  final double width;
  final double height;
  final double borderRadius;

  const Skeleton({
    super.key,
    required this.width,
    required this.height,
    this.borderRadius = 4.0,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(borderRadius),
      ),
    );
  }
}

/// Skeleton for scan result card
class ScanResultSkeleton extends StatelessWidget {
  const ScanResultSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                const Skeleton(width: 60, height: 24, borderRadius: 12),
                const Spacer(),
                const Skeleton(width: 80, height: 20),
              ],
            ),
            const SizedBox(height: 24),
            // Invoice number
            const Skeleton(width: 120, height: 14),
            const SizedBox(height: 8),
            const Skeleton(width: double.infinity, height: 32),
            const SizedBox(height: 16),
            // Vendor
            const Skeleton(width: 80, height: 14),
            const SizedBox(height: 8),
            const Skeleton(width: double.infinity, height: 24),
            const SizedBox(height: 16),
            // Amount row
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: const [
                      Skeleton(width: 60, height: 14),
                      SizedBox(height: 8),
                      Skeleton(width: 100, height: 28),
                    ],
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: const [
                      Skeleton(width: 60, height: 14),
                      SizedBox(height: 8),
                      Skeleton(width: 100, height: 28),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            // Risk score bar
            const Skeleton(width: double.infinity, height: 16, borderRadius: 8),
            const SizedBox(height: 8),
            const Skeleton(width: 200, height: 14),
            const SizedBox(height: 24),
            // Action buttons
            Row(
              children: const [
                Expanded(child: Skeleton(width: double.infinity, height: 48)),
                SizedBox(width: 12),
                Expanded(child: Skeleton(width: double.infinity, height: 48)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Skeleton for analytics chart
class AnalyticsChartSkeleton extends StatelessWidget {
  const AnalyticsChartSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Skeleton(width: 150, height: 20),
            const SizedBox(height: 24),
            // Chart area
            const Skeleton(width: double.infinity, height: 200),
            const SizedBox(height: 16),
            // Legend
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: const [
                Skeleton(width: 80, height: 20),
                Skeleton(width: 80, height: 20),
                Skeleton(width: 80, height: 20),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Skeleton for history list item
class HistoryItemSkeleton extends StatelessWidget {
  const HistoryItemSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            // Icon placeholder
            const Skeleton(width: 48, height: 48, borderRadius: 8),
            const SizedBox(width: 12),
            // Content
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Skeleton(width: 120, height: 16),
                  SizedBox(height: 8),
                  Skeleton(width: 80, height: 14),
                ],
              ),
            ),
            // Status badge
            const Skeleton(width: 60, height: 24, borderRadius: 12),
          ],
        ),
      ),
    );
  }
}

/// Shimmer wrapper for any widget
class ShimmerLoading extends StatelessWidget {
  final Widget child;
  final bool isLoading;

  const ShimmerLoading({
    super.key,
    required this.child,
    this.isLoading = true,
  });

  @override
  Widget build(BuildContext context) {
    if (!isLoading) return child;

    return Shimmer(
      child: child,
    );
  }
}

/// Skeleton for summary cards
class SummaryCardSkeleton extends StatelessWidget {
  const SummaryCardSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: const [
            Skeleton(width: 32, height: 32, borderRadius: 8),
            SizedBox(height: 8),
            Skeleton(width: 80, height: 12),
            SizedBox(height: 4),
            Skeleton(width: 60, height: 24),
          ],
        ),
      ),
    );
  }
}
