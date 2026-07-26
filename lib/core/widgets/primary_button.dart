import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import 'app_button_content.dart';

/// The app's main call-to-action button (e.g. "Login", "Apply", "Save").
///
/// Visual styling comes entirely from the app's `ElevatedButtonThemeData` —
/// this widget only handles layout, the optional icon, and the loading
/// state.
class PrimaryButton extends StatelessWidget {
  const PrimaryButton({
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
      child: ElevatedButton(
        // A no-op (instead of null) keeps the button's normal enabled
        // appearance while loading, rather than flashing into its
        // disabled style, while still swallowing taps.
        onPressed: isLoading ? () {} : onPressed,
        child: AppButtonContent(
          label: label,
          icon: icon,
          isLoading: isLoading,
          spinnerColor: AppColors.onPrimary,
        ),
      ),
    );
  }
}
