import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import 'danger_button.dart';
import 'primary_button.dart';

/// Semantic type of an [AppConfirmationDialog], controlling its icon color
/// and which button style is used for the confirm action.
enum AppConfirmationType { neutral, success, warning, danger }

const double _actionButtonWidth = 130;

/// A reusable Yes/No confirmation dialog.
///
/// Suitable for actions like "Delete CV", "Reject Candidate", "Shortlist
/// Candidate", "Close Opportunity", or "Sign Out" — all feature-specific
/// text is supplied by the caller, never hardcoded here.
///
/// Prefer [showAppConfirmationDialog] over constructing this directly; it
/// wraps `showDialog` and normalizes the result to a non-null [bool].
class AppConfirmationDialog extends StatelessWidget {
  const AppConfirmationDialog({
    super.key,
    required this.title,
    required this.message,
    this.confirmLabel = 'Confirm',
    this.cancelLabel = 'Cancel',
    this.type = AppConfirmationType.neutral,
    this.icon,
  });

  final String title;
  final String message;
  final String confirmLabel;
  final String cancelLabel;
  final AppConfirmationType type;
  final IconData? icon;

  IconData get _defaultIcon {
    switch (type) {
      case AppConfirmationType.neutral:
        return Icons.help_outline_rounded;
      case AppConfirmationType.success:
        return Icons.check_circle_outline_rounded;
      case AppConfirmationType.warning:
        return Icons.warning_amber_rounded;
      case AppConfirmationType.danger:
        return Icons.error_outline_rounded;
    }
  }

  Color get _iconColor {
    switch (type) {
      case AppConfirmationType.neutral:
        return AppColors.primary;
      case AppConfirmationType.success:
        return AppColors.success;
      case AppConfirmationType.warning:
        return AppColors.warning;
      case AppConfirmationType.danger:
        return AppColors.error;
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return AlertDialog(
      icon: Icon(icon ?? _defaultIcon, color: _iconColor, size: 32),
      title: Text(
        title,
        textAlign: TextAlign.center,
        style: textTheme.titleLarge,
      ),
      content: Text(
        message,
        textAlign: TextAlign.center,
        style: textTheme.bodyMedium?.copyWith(color: AppColors.textSecondary),
      ),
      actionsAlignment: MainAxisAlignment.center,
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(cancelLabel),
        ),
        const SizedBox(width: AppSpacing.xs),
        if (type == AppConfirmationType.danger)
          DangerButton(
            label: confirmLabel,
            width: _actionButtonWidth,
            onPressed: () => Navigator.of(context).pop(true),
          )
        else
          PrimaryButton(
            label: confirmLabel,
            width: _actionButtonWidth,
            onPressed: () => Navigator.of(context).pop(true),
          ),
      ],
    );
  }
}

/// Shows an [AppConfirmationDialog] and returns `true` only if the user
/// tapped confirm. Cancelling, or dismissing the dialog (tapping the
/// barrier, when [barrierDismissible] is true), both resolve to `false`.
Future<bool> showAppConfirmationDialog(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'Confirm',
  String cancelLabel = 'Cancel',
  AppConfirmationType type = AppConfirmationType.neutral,
  IconData? icon,
  bool barrierDismissible = true,
}) async {
  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: barrierDismissible,
    builder: (context) => AppConfirmationDialog(
      title: title,
      message: message,
      confirmLabel: confirmLabel,
      cancelLabel: cancelLabel,
      type: type,
      icon: icon,
    ),
  );
  return result ?? false;
}
