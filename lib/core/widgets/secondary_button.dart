import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import 'app_button_content.dart';

/// A secondary, outlined action button (e.g. "Cancel", "View details").
///
/// Visual styling comes entirely from the app's `OutlinedButtonThemeData`.
/// Sizing and loading behavior match `PrimaryButton`.
class SecondaryButton extends StatelessWidget {
  const SecondaryButton({
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
    return SizedBox(
      width: width,
      height: height ?? _defaultHeight,
      child: OutlinedButton(
        onPressed: isLoading ? () {} : onPressed,
        child: AppButtonContent(
          label: label,
          icon: icon,
          isLoading: isLoading,
          spinnerColor: AppColors.primary,
        ),
      ),
    );
  }
}
