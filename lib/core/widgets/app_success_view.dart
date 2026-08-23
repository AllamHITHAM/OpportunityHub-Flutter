import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import 'primary_button.dart';
import 'secondary_button.dart';

/// Shown after a successful action — e.g. "Application submitted",
/// "Interview scheduled", "Organization updated", or "Password changed".
class AppSuccessView extends StatelessWidget {
  const AppSuccessView({
    super.key,
    required this.title,
    this.message,
    this.primaryActionLabel,
    this.onPrimaryAction,
    this.secondaryActionLabel,
    this.onSecondaryAction,
    this.icon = Icons.check_circle_outline_rounded,
    this.compact = false,
  });

  final String title;
  final String? message;
  final String? primaryActionLabel;
  final VoidCallback? onPrimaryAction;
  final String? secondaryActionLabel;
  final VoidCallback? onSecondaryAction;
  final IconData icon;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final iconSize = compact ? 32.0 : 44.0;
    final iconBoxSize = compact ? 56.0 : 72.0;

    return Center(
      child: Padding(
        padding: EdgeInsets.all(compact ? AppSpacing.md : AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: iconBoxSize,
              height: iconBoxSize,
              decoration: BoxDecoration(
                color: AppColors.successBackground,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: iconSize, color: AppColors.success),
            ),
            SizedBox(height: compact ? AppSpacing.sm : AppSpacing.md),
            Text(
              title,
              textAlign: TextAlign.center,
              style: textTheme.titleMedium,
            ),
            if (message != null) ...[
              const SizedBox(height: AppSpacing.xxs),
              Text(
                message!,
                textAlign: TextAlign.center,
                style: textTheme.bodyMedium?.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
            ],
            if (primaryActionLabel != null || secondaryActionLabel != null) ...[
              SizedBox(height: compact ? AppSpacing.sm : AppSpacing.md),
              if (primaryActionLabel != null)
                PrimaryButton(
                  label: primaryActionLabel!,
                  onPressed: onPrimaryAction,
                ),
              if (primaryActionLabel != null && secondaryActionLabel != null)
                const SizedBox(height: AppSpacing.xs),
              if (secondaryActionLabel != null)
                SecondaryButton(
                  label: secondaryActionLabel!,
                  onPressed: onSecondaryAction,
                ),
            ],
          ],
        ),
      ),
    );
  }
}
