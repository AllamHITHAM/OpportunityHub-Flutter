import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';

/// A loading indicator, centered by default, with an optional message.
///
/// Use [compact] for a small inline spinner suitable for a card or list
/// item, rather than a full page/section.
class AppLoading extends StatelessWidget {
  const AppLoading({
    super.key,
    this.message,
    this.compact = false,
    this.padding,
  });

  final String? message;
  final bool compact;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final spinnerSize = compact ? 20.0 : 36.0;
    final spinner = SizedBox(
      width: spinnerSize,
      height: spinnerSize,
      child: CircularProgressIndicator(
        strokeWidth: compact ? 2.5 : 3,
        color: AppColors.primary,
      ),
    );

    final content = message == null
        ? spinner
        : Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              spinner,
              SizedBox(height: compact ? AppSpacing.xs : AppSpacing.sm),
              Text(
                message!,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          );

    return Center(
      child: Padding(
        padding: padding ?? const EdgeInsets.all(AppSpacing.md),
        child: content,
      ),
    );
  }
}
