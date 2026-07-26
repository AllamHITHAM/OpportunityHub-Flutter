import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_radius.dart';
import '../theme/app_shadows.dart';
import '../theme/app_spacing.dart';

/// The shadow strength for [AppCard].
enum AppCardElevation { none, card, elevated }

/// A reusable container/card wrapper matching the app's design system.
///
/// Uses [Material]+[InkWell] (not a bare [GestureDetector]) when [onTap]
/// is provided, so taps get a proper ripple clipped to the card's rounded
/// corners.
class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.padding,
    this.margin,
    this.onTap,
    this.backgroundColor,
    this.borderColor,
    this.borderRadius,
    this.elevation = AppCardElevation.card,
  });

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final VoidCallback? onTap;
  final Color? backgroundColor;
  final Color? borderColor;
  final BorderRadius? borderRadius;
  final AppCardElevation elevation;

  List<BoxShadow> get _shadow {
    switch (elevation) {
      case AppCardElevation.none:
        return const [];
      case AppCardElevation.card:
        return AppShadows.card;
      case AppCardElevation.elevated:
        return AppShadows.elevated;
    }
  }

  @override
  Widget build(BuildContext context) {
    final radius = borderRadius ?? AppRadius.largeRadius;

    return Container(
      margin: margin,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: backgroundColor ?? AppColors.card,
        borderRadius: radius,
        border: Border.all(color: borderColor ?? AppColors.border),
        boxShadow: _shadow,
      ),
      child: Material(
        color: AppColors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: radius,
          child: Padding(
            padding: padding ?? const EdgeInsets.all(AppSpacing.cardPadding),
            child: child,
          ),
        ),
      ),
    );
  }
}
