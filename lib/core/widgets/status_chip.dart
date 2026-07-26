import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_radius.dart';
import '../theme/app_spacing.dart';

/// Semantic status categories a [StatusChip] can represent.
///
/// Intentionally generic — it has no idea what "Shortlisted" or "Draft"
/// means. Callers map their own status strings to one of these types and
/// provide the label text.
enum AppStatusType { neutral, info, success, warning, error, primary }

class _StatusColors {
  const _StatusColors(this.background, this.foreground);

  final Color background;
  final Color foreground;
}

const Map<AppStatusType, _StatusColors> _statusColors = {
  AppStatusType.neutral: _StatusColors(
    AppColors.surfaceVariant,
    AppColors.textSecondary,
  ),
  AppStatusType.info: _StatusColors(AppColors.infoBackground, AppColors.info),
  AppStatusType.success: _StatusColors(
    AppColors.successBackground,
    AppColors.success,
  ),
  AppStatusType.warning: _StatusColors(
    AppColors.warningBackground,
    AppColors.warning,
  ),
  AppStatusType.error: _StatusColors(
    AppColors.errorBackground,
    AppColors.error,
  ),
  AppStatusType.primary: _StatusColors(
    AppColors.primaryContainer,
    AppColors.primaryDark,
  ),
};

/// A small, rounded label communicating a status — e.g. "Submitted",
/// "Under Review", "Shortlisted", "Interview", "Offer", "Rejected",
/// "Published", "Draft", "Closed". The label text and which [AppStatusType]
/// it maps to is entirely up to the caller.
class StatusChip extends StatelessWidget {
  const StatusChip({
    super.key,
    required this.label,
    this.type = AppStatusType.neutral,
    this.icon,
    this.compact = false,
  });

  final String label;
  final AppStatusType type;
  final IconData? icon;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final colors = _statusColors[type]!;

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? AppSpacing.xs : AppSpacing.sm,
        vertical: compact ? 2 : AppSpacing.xxs,
      ),
      decoration: BoxDecoration(
        color: colors.background,
        borderRadius: AppRadius.pillRadius,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: compact ? 12 : 14, color: colors.foreground),
            SizedBox(width: compact ? 4 : AppSpacing.xxs),
          ],
          Text(
            label,
            style: TextStyle(
              fontSize: compact ? 11 : 12,
              fontWeight: FontWeight.w600,
              color: colors.foreground,
            ),
          ),
        ],
      ),
    );
  }
}
