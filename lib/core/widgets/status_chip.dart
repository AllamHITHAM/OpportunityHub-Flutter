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

/// Resolved fresh on every call (never cached in a `const`/`final` map) so
/// it always reflects the current light/dark theme — see [AppColors]'s own
/// doc comment on why its fields are plain getters rather than constants.
_StatusColors _statusColorsFor(AppStatusType type) {
  switch (type) {
    case AppStatusType.neutral:
      return _StatusColors(AppColors.surfaceVariant, AppColors.textSecondary);
    case AppStatusType.info:
      return _StatusColors(AppColors.infoBackground, AppColors.info);
    case AppStatusType.success:
      return _StatusColors(AppColors.successBackground, AppColors.success);
    case AppStatusType.warning:
      return _StatusColors(AppColors.warningBackground, AppColors.warning);
    case AppStatusType.error:
      return _StatusColors(AppColors.errorBackground, AppColors.error);
    case AppStatusType.primary:
      return _StatusColors(AppColors.primaryContainer, AppColors.primaryDark);
  }
}

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
    final colors = _statusColorsFor(type);

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
          // Flexible+ellipsis is purely defensive: it never changes how an
          // already-short label renders (the common case everywhere this
          // is used today), but keeps a longer label from ever overflowing
          // when a narrow viewport constrains the chip's available width
          // (e.g. inside a `Wrap`).
          Flexible(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: compact ? 11 : 12,
                fontWeight: FontWeight.w600,
                color: colors.foreground,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
