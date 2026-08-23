import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_shadows.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/date_formatter.dart';
import '../../../core/widgets/app_widgets.dart';
import '../../../models/opportunity_model.dart';
import '../../../providers/student_applications_provider.dart';
import '../../applications/presentation/apply_bottom_sheet.dart';
import 'opportunity_card_palette.dart';
import 'opportunity_display.dart';

/// A rich opportunity card for the Student Explore feed — every field
/// rendered here comes straight from [OpportunityModel] (itself sourced
/// from the real, already-used `GET /api/opportunities` response); nothing
/// is fabricated (no salary, no applicant count, no match percentage). The
/// card's pastel background comes from [opportunityCardTone] — a stable
/// function of the opportunity's real ID, never implying status.
///
/// UI Phase 1.3: the top "cover" band is media-ready — `OrganizationProfile`
/// has no confirmed, app-parsed logo field yet (see this class's own audit
/// note below), so it renders a deterministic gradient (from the same
/// [opportunityCardTone]) with the organization's [AppAvatar] fallback
/// (initials, never a fabricated photo/logo) overlaid in the corner. If a
/// real cover-image/logo field is added to the API later, only this one
/// band needs to start preferring that image — the rest of the card is
/// unaffected.
///
/// Tapping the card (or "View Details") navigates to the real Opportunity
/// Details route. "Apply" (shown only when the student hasn't already
/// applied) reuses the exact same [showApplyBottomSheet] flow Details
/// itself calls — CV selection, eligibility, and submission all happen
/// there, never duplicated here.
class OpportunityCard extends StatelessWidget {
  const OpportunityCard({
    super.key,
    required this.opportunity,
    required this.onTap,
  });

  final OpportunityModel opportunity;
  final VoidCallback onTap;

  Future<void> _apply(BuildContext context) {
    return showApplyBottomSheet(
      context,
      opportunityId: opportunity.id,
      opportunityTitle: opportunity.title,
    );
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final organizationName = opportunity.organizationProfile?.organizationName;
    final deadline = opportunity.applicationDeadline;
    final eligibility = eligibilityLabel(opportunity);
    final skills = opportunity.opportunitySkills;
    final tone = opportunityCardTone(opportunity.id);
    final alreadyApplied = context.select<StudentApplicationsProvider, bool>(
      (provider) => provider.hasAppliedTo(opportunity.id),
    );

    return AppCard(
      onTap: onTap,
      interactive: true,
      backgroundColor: tone.background,
      borderColor: tone.border,
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          _CoverBand(organizationName: organizationName, tone: tone),
          Padding(
            padding: const EdgeInsets.all(AppSpacing.cardPadding),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  opportunity.title,
                  style: textTheme.titleMedium,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                if (organizationName != null) ...[
                  const SizedBox(height: AppSpacing.xxs),
                  Row(
                    children: [
                      Icon(
                        Icons.apartment_outlined,
                        size: 14,
                        color: AppColors.textMuted,
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          organizationName,
                          style: textTheme.bodySmall?.copyWith(
                            color: AppColors.textSecondary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: AppSpacing.sm),
                Wrap(
                  spacing: AppSpacing.xxs,
                  runSpacing: AppSpacing.xxs,
                  children: [
                    StatusChip(
                      compact: true,
                      type: AppStatusType.primary,
                      label:
                          opportunityTypeLabels[opportunity.opportunityType] ??
                          opportunity.opportunityType,
                    ),
                    StatusChip(
                      compact: true,
                      label:
                          employmentTypeLabels[opportunity.employmentType] ??
                          opportunity.employmentType,
                    ),
                    StatusChip(
                      compact: true,
                      label:
                          workModeLabels[opportunity.workMode] ??
                          opportunity.workMode,
                    ),
                    if (opportunity.location != null)
                      StatusChip(
                        compact: true,
                        icon: Icons.place_outlined,
                        label: opportunity.location!,
                      ),
                  ],
                ),
                if (opportunity.description.trim().isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    opportunity.description.trim(),
                    style: textTheme.bodySmall?.copyWith(
                      color: AppColors.textSecondary,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                if (eligibility != null) ...[
                  const SizedBox(height: AppSpacing.xs),
                  Row(
                    children: [
                      Icon(
                        Icons.school_outlined,
                        size: 14,
                        color: AppColors.textMuted,
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          eligibility,
                          style: textTheme.labelSmall,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
                if (skills.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.xs),
                  Wrap(
                    spacing: AppSpacing.xxs,
                    runSpacing: AppSpacing.xxs,
                    children: [
                      for (final opportunitySkill in skills.take(4))
                        StatusChip(
                          compact: true,
                          type: AppStatusType.neutral,
                          label: opportunitySkill.skill.name,
                        ),
                      if (skills.length > 4)
                        StatusChip(
                          compact: true,
                          label: '+${skills.length - 4} more',
                        ),
                    ],
                  ),
                ],
                const SizedBox(height: AppSpacing.sm),
                if (deadline != null)
                  Row(
                    children: [
                      Icon(
                        Icons.event_outlined,
                        size: 14,
                        color: AppColors.textMuted,
                      ),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          'Apply by ${formatDate(deadline)}',
                          style: textTheme.labelSmall,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                const SizedBox(height: AppSpacing.sm),
                Row(
                  children: [
                    Expanded(
                      child: SecondaryButton(
                        label: 'View Details',
                        height: 40,
                        onPressed: onTap,
                      ),
                    ),
                    if (!alreadyApplied) ...[
                      const SizedBox(width: AppSpacing.xs),
                      Expanded(
                        child: PrimaryButton(
                          label: 'Apply',
                          height: 40,
                          onPressed: () => _apply(context),
                        ),
                      ),
                    ] else ...[
                      const SizedBox(width: AppSpacing.xs),
                      Expanded(
                        child: SizedBox(
                          height: 40,
                          child: Center(
                            child: StatusChip(
                              icon: Icons.check_circle_outline,
                              type: AppStatusType.success,
                              label: 'Applied',
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The card's media-ready top band. No opportunity cover-image field
/// exists in [OpportunityModel] today (audited for UI Phase 1.3 — see
/// [OpportunityCard]'s own doc comment), so this renders a deterministic
/// gradient derived from the card's own [OpportunityCardTone] plus the
/// organization's real [AppAvatar] fallback (initials only — never a
/// fabricated logo/photo, since no confirmed logo field exists either).
class _CoverBand extends StatelessWidget {
  const _CoverBand({required this.organizationName, required this.tone});

  final String? organizationName;
  final OpportunityCardTone tone;

  static const double _height = 56;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: _height,
      child: Stack(
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [tone.background, tone.border],
                ),
              ),
            ),
          ),
          Positioned(
            right: AppSpacing.xs,
            bottom: AppSpacing.xs,
            child: Container(
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                color: AppColors.surface,
                shape: BoxShape.circle,
                boxShadow: AppShadows.card,
              ),
              child: AppAvatar(
                name: organizationName,
                size: 28,
                fallbackIcon: Icons.apartment_outlined,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
