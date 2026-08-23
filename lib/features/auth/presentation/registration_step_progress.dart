import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_motion.dart';
import '../../../core/theme/app_spacing.dart';

/// A small "Step X of N" progress indicator shown at the top of each
/// student-registration step.
///
/// Purely visual — this two-step flow doesn't have its own wizard/page
/// controller, so [progress]/[stepText]/[label] are just passed in by
/// whichever screen is showing it. Kept local to the auth feature rather
/// than promoted to a global shared widget, since nothing else uses it yet.
///
/// UI Phase 1.5: replaced the plain linear bar with two connected step
/// dots (there are exactly two real steps in every flow this is used in —
/// see `_totalSteps` — never more, never fewer) that animate into their
/// completed/active state on mount, since each step is its own screen
/// (or, for Company registration, its own local-state page) rather than
/// one continuous widget whose `progress` value changes live.
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

  static const int _totalSteps = 2;

  int get _currentStep => progress >= 1.0 ? 2 : 1;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final currentStep = _currentStep;

    return Column(
      children: [
        Row(
          children: [
            for (var step = 1; step <= _totalSteps; step++) ...[
              _StepDot(
                stepNumber: step,
                isCompleted: step < currentStep,
                isActive: step == currentStep,
              ),
              if (step != _totalSteps)
                Expanded(
                  child: _StepConnector(isFilled: step < currentStep),
                ),
            ],
          ],
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

class _StepDot extends StatelessWidget {
  const _StepDot({
    required this.stepNumber,
    required this.isCompleted,
    required this.isActive,
  });

  final int stepNumber;
  final bool isCompleted;
  final bool isActive;

  static const double _size = 26;

  @override
  Widget build(BuildContext context) {
    final filled = isCompleted || isActive;

    // Each mount is effectively this step's own "entrance" (see the class
    // doc comment) -- an active/completed dot pops in from slightly
    // smaller rather than appearing at full size immediately.
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: filled ? 0.6 : 1.0, end: 1.0),
      duration: AppMotion.reduced(context, AppMotion.slow),
      curve: AppMotion.entrance,
      builder: (context, scale, child) {
        return Transform.scale(scale: scale, child: child);
      },
      child: AnimatedContainer(
        duration: AppMotion.reduced(context, AppMotion.normal),
        curve: AppMotion.standard,
        width: _size,
        height: _size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: filled ? AppColors.primary : AppColors.surfaceVariant,
          border: Border.all(
            color: filled ? AppColors.primary : AppColors.border,
            width: isActive ? 2 : 1,
          ),
        ),
        child: AnimatedSwitcher(
          duration: AppMotion.reduced(context, AppMotion.fast),
          transitionBuilder: (child, animation) => ScaleTransition(
            scale: animation,
            child: FadeTransition(opacity: animation, child: child),
          ),
          child: isCompleted
              ? Icon(
                  Icons.check_rounded,
                  key: const ValueKey('done'),
                  size: 16,
                  color: AppColors.onPrimary,
                )
              : Text(
                  '$stepNumber',
                  key: ValueKey('num-$stepNumber'),
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: filled ? AppColors.onPrimary : AppColors.textMuted,
                  ),
                ),
        ),
      ),
    );
  }
}

class _StepConnector extends StatelessWidget {
  const _StepConnector({required this.isFilled});

  final bool isFilled;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxs),
      child: TweenAnimationBuilder<double>(
        tween: Tween<double>(begin: 0, end: isFilled ? 1 : 0),
        duration: AppMotion.reduced(context, AppMotion.slow),
        curve: AppMotion.entrance,
        builder: (context, fillFraction, _) {
          return SizedBox(
            height: 3,
            child: Stack(
              children: [
                Container(color: AppColors.border),
                FractionallySizedBox(
                  widthFactor: fillFraction,
                  alignment: Alignment.centerLeft,
                  child: Container(color: AppColors.primary),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
