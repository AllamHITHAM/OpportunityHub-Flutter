import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_radius.dart';
import 'app_button_content.dart';

/// A destructive-action button (e.g. delete, reject, confirm logout).
///
/// Built on [OutlinedButton] with explicit error-color styling applied
/// directly, since the app's shared button themes intentionally don't
/// define a "danger" variant. Loading layout is shared with
/// [PrimaryButton]/[SecondaryButton] via `AppButtonContent`.
class DangerButton extends StatelessWidget {
  const DangerButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.isLoading = false,
    this.icon,
    this.width,
    this.height,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool isLoading;
  final IconData? icon;
  final double? width;
  final double? height;

  /// Matches the accessible minimum button height set in `AppTheme`.
  static const double _defaultHeight = 48;

  @override
  Widget build(BuildContext context) {
    return ButtonInteractionSurface(
      child: SizedBox(
        width: width,
        height: height ?? _defaultHeight,
        child: OutlinedButton(
          onPressed: isLoading ? () {} : onPressed,
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.error,
            disabledForegroundColor: AppColors.disabledText,
            side: BorderSide(color: AppColors.error),
            shape: const RoundedRectangleBorder(
              borderRadius: AppRadius.mediumRadius,
            ),
          ),
          child: AppButtonContent(
            label: label,
            icon: icon,
            isLoading: isLoading,
            spinnerColor: AppColors.error,
          ),
        ),
      ),
    );
  }
}
