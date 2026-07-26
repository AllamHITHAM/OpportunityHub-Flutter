import 'package:flutter/material.dart';

import '../theme/app_spacing.dart';

/// Shared label/icon/spinner layout used by [PrimaryButton], [SecondaryButton],
/// and [DangerButton].
///
/// Not part of the public design-system API on its own — it exists only so
/// the three buttons don't each repeat the same loading-state layout.
class AppButtonContent extends StatelessWidget {
  const AppButtonContent({
    super.key,
    required this.label,
    required this.isLoading,
    required this.spinnerColor,
    this.icon,
  });

  final String label;
  final bool isLoading;
  final Color spinnerColor;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final labelChild = icon == null
        ? Text(label)
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18),
              const SizedBox(width: AppSpacing.xs),
              Text(label),
            ],
          );

    return Stack(
      alignment: Alignment.center,
      children: [
        // Keeping the label in the tree (just invisible) while loading
        // means the button keeps its natural size instead of shrinking
        // down to fit the spinner alone.
        Opacity(opacity: isLoading ? 0 : 1, child: labelChild),
        if (isLoading)
          SizedBox(
            height: 20,
            width: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2.5,
              color: spinnerColor,
            ),
          ),
      ],
    );
  }
}
