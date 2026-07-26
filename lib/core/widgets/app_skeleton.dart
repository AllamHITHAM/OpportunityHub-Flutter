import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_radius.dart';
import '../theme/app_spacing.dart';

/// A single pulsing placeholder block, shown while real content is loading.
///
/// Uses a plain [AnimationController] (no shimmer package) that gently
/// pulses the block's opacity. The animation is tied to this widget's own
/// lifecycle via [SingleTickerProviderStateMixin] and is disposed — which
/// stops it — as soon as the widget is removed from the tree.
class AppSkeleton extends StatefulWidget {
  const AppSkeleton({
    super.key,
    this.width,
    this.height = 16,
    this.borderRadius,
  });

  final double? width;
  final double height;
  final BorderRadius? borderRadius;

  @override
  State<AppSkeleton> createState() => _AppSkeletonState();
}

class _AppSkeletonState extends State<AppSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _opacity = Tween<double>(
      begin: 0.5,
      end: 1,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    // Disposing the controller stops its ticker immediately, so the
    // animation never keeps running after this widget is gone.
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _opacity,
      // Passing the block as `child` means only the Opacity node rebuilds
      // on each tick, not the block itself — cheap to animate.
      child: Container(
        width: widget.width,
        height: widget.height,
        decoration: BoxDecoration(
          color: AppColors.surfaceVariant,
          borderRadius: widget.borderRadius ?? AppRadius.smallRadius,
        ),
      ),
      builder: (context, child) {
        return Opacity(opacity: _opacity.value, child: child);
      },
    );
  }
}

/// A ready-made skeleton shaped like a typical list-item card: a small
/// circular block (standing in for an avatar) plus two lines of text
/// placeholders. Not tied to any specific feature's data shape.
class AppCardSkeleton extends StatelessWidget {
  const AppCardSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.cardPadding),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: AppRadius.largeRadius,
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          const AppSkeleton(
            width: 40,
            height: 40,
            borderRadius: AppRadius.pillRadius,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const AppSkeleton(height: 14),
                const SizedBox(height: AppSpacing.xs),
                const AppSkeleton(width: 120, height: 12),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A vertical list of [count] [AppCardSkeleton]s, spaced like a typical
/// list of cards. A convenient placeholder for any loading list screen.
class AppSkeletonList extends StatelessWidget {
  const AppSkeletonList({super.key, this.count = 3});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var i = 0; i < count; i++) ...[
          const AppCardSkeleton(),
          if (i != count - 1) const SizedBox(height: AppSpacing.sm),
        ],
      ],
    );
  }
}
