import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_spacing.dart';

/// A small "Step X of N" progress indicator shown at the top of each
/// student-registration step.
///
/// Purely visual — this two-step flow doesn't have its own wizard/page
/// controller, so [progress]/[stepText]/[label] are just passed in by
/// whichever screen is showing it. Kept local to the auth feature rather
/// than promoted to a global shared widget, since nothing else uses it yet.
class RegistrationStepProgress extends StatelessWidget {
  const RegistrationStepProgress({
    super.key,
    required this.progress,
    required this.stepText,
    required this.label,
  });

  final double progress;
  final String stepText;
  final String label;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Column(
      children: [
        ClipRRect(
          borderRadius: AppRadius.pillRadius,
          child: LinearProgressIndicator(value: progress, minHeight: 6),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          stepText,
          style: textTheme.labelLarge?.copyWith(color: AppColors.primary),
        ),
        Text(
          label,
          style: textTheme.bodySmall?.copyWith(color: AppColors.textSecondary),
        ),
      ],
    );
  }
}
