import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_motion.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/app_widgets.dart';
import '../../../models/match_breakdown_model.dart';
import '../../../models/recommended_candidate_model.dart';
import '../../../providers/opportunity_recommendations_provider.dart';
import '../../../routes/app_routes.dart';
import '../../opportunities/presentation/opportunity_display.dart';
import 'invite_to_apply_sheet.dart';
import 'organization_candidate_profile_screen.dart';

/// UI Phase O8.1: below this width, candidates render as stacked cards
/// with full-width actions; at or above it, a compact structured
/// comparison row — matching the same technique already used by Quiz
/// Results.
const _tableBreakpoint = 900.0;
const _maxContentWidth = 1120.0;

const _invitationStatusLabels = {
  'pending': 'Pending',
  'accepted': 'Accepted',
  'declined': 'Declined',
};

String _relationshipLabel(RecommendedCandidateModel candidate) {
  if (candidate.alreadyApplied) return 'Applied';
  final status = candidate.invitationStatus;
  if (status != null) return _invitationStatusLabels[status] ?? status;
  return 'Not Invited';
}

AppStatusType _relationshipChipType(RecommendedCandidateModel candidate) {
  if (candidate.alreadyApplied) return AppStatusType.success;
  switch (candidate.invitationStatus) {
    case 'accepted':
      return AppStatusType.success;
    case 'declined':
      return AppStatusType.neutral;
    case 'pending':
      return AppStatusType.info;
    default:
      return AppStatusType.neutral;
  }
}

/// Real, eligible candidates ranked for one specific Opportunity (Phase
/// O8.1) — the platform proactively recommending who to recruit, instead
/// of the Organization manually browsing every Student profile. Backed by
/// `GET /organization/opportunities/{opportunity}/recommended-candidates`,
/// which computes each score live via the same formula a real Application
/// would later be scored with (`MatchingService::scoreCandidate()`) and
/// never inserts a throwaway Application row to do it. Eligibility is
/// already enforced server-side, so every candidate shown here is a real,
/// eligible one — ordered highest match first.
///
/// This is the one real Invite context: since the Opportunity is already
/// known, "Invite to Apply" never shows a second "choose an Opportunity"
/// step the way the old Talent Directory-wide flow used to.
class OrganizationRecommendedCandidatesScreen extends StatefulWidget {
  const OrganizationRecommendedCandidatesScreen({
    super.key,
    required this.opportunityId,
    this.opportunityTitle,
  });

  final int opportunityId;

  /// Optional — only available via in-app navigation (e.g. from
  /// Opportunity Details, via GoRouter `extra`). A direct URL visit has no
  /// `extra` to rely on, so this screen renders correctly without it.
  final String? opportunityTitle;

  @override
  State<OrganizationRecommendedCandidatesScreen> createState() =>
      _OrganizationRecommendedCandidatesScreenState();
}

class _OrganizationRecommendedCandidatesScreenState
    extends State<OrganizationRecommendedCandidatesScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<OpportunityRecommendationsProvider>().loadForOpportunity(
        widget.opportunityId,
      );
    });
  }

  void _viewProfile(RecommendedCandidateModel candidate) {
    context.push(
      AppRoutes.organizationCandidateProfile(candidate.id),
      extra: CandidateProfileView.fromRecommended(
        candidate,
        opportunityId: widget.opportunityId,
        opportunityTitle: widget.opportunityTitle,
      ),
    );
  }

  void _viewApplication(int applicationId) {
    context.push(AppRoutes.organizationApplicationDetails(applicationId));
  }

  Future<void> _invite(RecommendedCandidateModel candidate) async {
    final sent = await showInviteToApplySheet(
      context,
      candidate: candidate,
      opportunityId: widget.opportunityId,
      opportunityTitle: widget.opportunityTitle ?? 'this opportunity',
    );
    if (!mounted) return;
    if (sent) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Invitation sent')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<OpportunityRecommendationsProvider>();

    return Scaffold(
      appBar: AppBar(
        title: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Recommended Candidates'),
            if (widget.opportunityTitle != null)
              Text(
                widget.opportunityTitle!,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: AppColors.textSecondary),
              ),
          ],
        ),
        actions: const [ThemeToggleSurface()],
      ),
      body: SafeArea(child: _buildBody(provider)),
    );
  }

  Widget _buildBody(OpportunityRecommendationsProvider provider) {
    final isThisOne = provider.loadedOpportunityId == widget.opportunityId;

    if (provider.isLoading && !(isThisOne && provider.candidates.isNotEmpty)) {
      return const AppSkeletonList();
    }

    if (provider.errorMessage != null &&
        !(isThisOne && provider.candidates.isNotEmpty)) {
      return AppErrorView(
        message: provider.errorMessage!,
        onRetry: () => provider.loadForOpportunity(
          widget.opportunityId,
          forceRefresh: true,
        ),
      );
    }

    if (!isThisOne || provider.candidates.isEmpty) {
      return const AppEmptyView(
        icon: Icons.recommend_outlined,
        title: 'No Recommended Candidates',
        message:
            'No eligible student profiles are available for this '
            'opportunity yet.',
      );
    }

    final candidates = provider.candidates;

    return RefreshIndicator(
      onRefresh: () =>
          provider.loadForOpportunity(widget.opportunityId, forceRefresh: true),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final isWide = width >= _tableBreakpoint;

          return SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.symmetric(
              horizontal: width >= _tableBreakpoint
                  ? AppSpacing.xl
                  : AppSpacing.screenHorizontal,
              vertical: AppSpacing.md,
            ),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: _maxContentWidth),
                child: _Entrance(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _MatchingExplanation(
                        workMode: provider.workMode,
                        locationName: provider.locationName,
                        opportunityType: provider.opportunityType,
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        '${candidates.length} eligible '
                        'candidate${candidates.length == 1 ? '' : 's'}',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppColors.textSecondary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      if (isWide) ...[
                        const _CandidateHeaderRow(),
                        const SizedBox(height: AppSpacing.xxs),
                      ],
                      for (var i = 0; i < candidates.length; i++) ...[
                        if (i > 0) const SizedBox(height: AppSpacing.sm),
                        isWide
                            ? _CandidateTableRow(
                                candidate: candidates[i],
                                opportunityLocationName: provider.locationName,
                                justInvited:
                                    provider.lastInvitedCandidateId ==
                                    candidates[i].id,
                                onViewProfile: () =>
                                    _viewProfile(candidates[i]),
                                onViewApplication: _viewApplication,
                                onInvite: () => _invite(candidates[i]),
                              )
                            : _CandidateCard(
                                candidate: candidates[i],
                                opportunityLocationName: provider.locationName,
                                justInvited:
                                    provider.lastInvitedCandidateId ==
                                    candidates[i].id,
                                onViewProfile: () =>
                                    _viewProfile(candidates[i]),
                                onViewApplication: _viewApplication,
                                onInvite: () => _invite(candidates[i]),
                              ),
                      ],
                      const SizedBox(height: AppSpacing.xl),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// A truthful, professional explanation of what this list actually is
/// (Phase O8.2, extended by "Candidate Opportunity Preferences + Final
/// Recommendation Match Formula") -- so the Organization understands
/// these are not random profiles, but real candidates already filtered
/// against the Opportunity's configured eligibility (the Student's own
/// Interested In preference matching this Opportunity's real Type,
/// Eligible Majors, and location where Work Mode requires it) and then
/// ranked by match. Every line here is dynamic, real copy over the actual
/// Opportunity Type/work mode -- never a hardcoded assumption like "these
/// are all employees" (see this app's own truthful-copy convention).
class _MatchingExplanation extends StatelessWidget {
  const _MatchingExplanation({
    required this.workMode,
    required this.locationName,
    required this.opportunityType,
  });

  final String? workMode;
  final String? locationName;
  final String? opportunityType;

  /// Location is only ever truthfully described as "considered" when it
  /// was actually part of the filter -- Work Mode is Remote (never
  /// consulted), or the Opportunity has no canonical location set (nothing
  /// to compare against, so nobody was filtered on it either) both mean
  /// "not considered", not just "not shown".
  bool get _locationWasConsidered =>
      workMode != 'remote' && locationName != null;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final typeLabel = opportunityType == null
        ? null
        : (opportunityTypeLabels[opportunityType] ?? opportunityType);

    final String rankedBy;
    if (_locationWasConsidered) {
      rankedBy =
          'Candidates are ranked by Major, Required Skills, and '
          'work-location compatibility.';
    } else if (workMode == 'remote') {
      rankedBy =
          'Candidates are ranked by Major and Required Skills '
          'compatibility. Location is not considered because this '
          'opportunity is Remote.';
    } else {
      // On-site/Hybrid, but this Opportunity has no canonical location
      // configured -- location genuinely was not part of the filter, but
      // never truthfully attributable to being Remote.
      rankedBy =
          'Candidates are ranked by Major and Required Skills '
          'compatibility. Location is not considered because this '
          'opportunity has no fixed location set.';
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (typeLabel != null) ...[
          Row(
            children: [
              Text(
                'Opportunity Type',
                style: textTheme.labelSmall?.copyWith(
                  color: AppColors.textMuted,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.4,
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              StatusChip(
                label: typeLabel,
                type: AppStatusType.info,
                compact: true,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'These candidates are interested in $typeLabel opportunities '
            'and meet this opportunity\'s eligibility requirements.',
            style: textTheme.bodySmall?.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: AppSpacing.xxs),
        ],
        Text(
          rankedBy,
          style: textTheme.bodySmall?.copyWith(color: AppColors.textMuted),
        ),
      ],
    );
  }
}

class _Entrance extends StatelessWidget {
  const _Entrance({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final duration = AppMotion.reduced(context, AppMotion.slow);

    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: duration,
      curve: AppMotion.entrance,
      builder: (context, t, child) => Opacity(
        opacity: t,
        child: Transform.translate(
          offset: Offset(0, (1 - t) * 8),
          child: child,
        ),
      ),
      child: child,
    );
  }
}

const _candidateFlex = 3;
const _matchFlex = 2;
const _skillsFlex = 3;
const _stateFlex = 2;
const _actionWidth = 160.0;

class _CandidateHeaderRow extends StatelessWidget {
  const _CandidateHeaderRow();

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodySmall?.copyWith(
      color: AppColors.textSecondary,
      fontWeight: FontWeight.w600,
    );

    Widget label(String text, int flex) => Expanded(
      flex: flex,
      child: Text(text, style: style),
    );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      child: Row(
        children: [
          label('Candidate', _candidateFlex),
          label('Match', _matchFlex),
          label('Skills', _skillsFlex),
          label('Relationship', _stateFlex),
          const SizedBox(width: _actionWidth),
        ],
      ),
    );
  }
}

Color _matchScoreColor(double score) {
  if (score >= 75) return AppColors.success;
  if (score >= 50) return AppColors.warning;
  return AppColors.textPrimary;
}

/// A compact, structured comparison row for desktop/tablet.
class _CandidateTableRow extends StatelessWidget {
  const _CandidateTableRow({
    required this.candidate,
    required this.opportunityLocationName,
    required this.justInvited,
    required this.onViewProfile,
    required this.onViewApplication,
    required this.onInvite,
  });

  final RecommendedCandidateModel candidate;
  final String? opportunityLocationName;
  final bool justInvited;
  final VoidCallback onViewProfile;
  final ValueChanged<int> onViewApplication;
  final VoidCallback onInvite;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final subtitleParts = [
      if (candidate.major != null) candidate.major!,
      if (candidate.university != null) candidate.university!,
    ];

    return AppCard(
      borderColor: AppColors.secondaryLight,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: _candidateFlex,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      candidate.name,
                      style: textTheme.titleSmall,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (subtitleParts.isNotEmpty)
                      Text(
                        subtitleParts.join(' · '),
                        style: textTheme.bodySmall?.copyWith(
                          color: AppColors.textSecondary,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
              Expanded(
                flex: _matchFlex,
                child: Text(
                  '${candidate.matchScore.toStringAsFixed(0)}%',
                  style: textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: _matchScoreColor(candidate.matchScore),
                  ),
                ),
              ),
              Expanded(
                flex: _skillsFlex,
                child: _SkillsSummary(candidate: candidate),
              ),
              Expanded(
                flex: _stateFlex,
                child: StatusChip(
                  label: _relationshipLabel(candidate),
                  type: _relationshipChipType(candidate),
                  compact: true,
                ),
              ),
              SizedBox(
                width: _actionWidth,
                child: _CandidateActions(
                  candidate: candidate,
                  justInvited: justInvited,
                  compact: true,
                  onViewProfile: onViewProfile,
                  onViewApplication: onViewApplication,
                  onInvite: onInvite,
                ),
              ),
            ],
          ),
          if (candidate.matchBreakdown != null) ...[
            const SizedBox(height: AppSpacing.xxs),
            _WhyMatchExpansion(
              candidate: candidate,
              opportunityLocationName: opportunityLocationName,
            ),
          ],
        ],
      ),
    );
  }
}

/// A compact stacked card for mobile/narrow tablet.
class _CandidateCard extends StatelessWidget {
  const _CandidateCard({
    required this.candidate,
    required this.opportunityLocationName,
    required this.justInvited,
    required this.onViewProfile,
    required this.onViewApplication,
    required this.onInvite,
  });

  final RecommendedCandidateModel candidate;
  final String? opportunityLocationName;
  final bool justInvited;
  final VoidCallback onViewProfile;
  final ValueChanged<int> onViewApplication;
  final VoidCallback onInvite;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return AppCard(
      borderColor: AppColors.secondaryLight,
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  candidate.name,
                  style: textTheme.titleMedium,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              Text(
                '${candidate.matchScore.toStringAsFixed(0)}% Match',
                style: textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: _matchScoreColor(candidate.matchScore),
                ),
              ),
            ],
          ),
          if (candidate.major != null) ...[
            const SizedBox(height: AppSpacing.xxs),
            Text(
              candidate.major!,
              style: textTheme.bodyMedium?.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ],
          if (candidate.university != null) ...[
            const SizedBox(height: AppSpacing.xxs),
            Text(
              candidate.university!,
              style: textTheme.bodyMedium?.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ],
          if (candidate.skills.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            _SkillsSummary(candidate: candidate),
          ],
          if (candidate.matchBreakdown != null) ...[
            const SizedBox(height: AppSpacing.sm),
            _WhyMatchExpansion(
              candidate: candidate,
              opportunityLocationName: opportunityLocationName,
            ),
          ],
          const SizedBox(height: AppSpacing.sm),
          StatusChip(
            label: _relationshipLabel(candidate),
            type: _relationshipChipType(candidate),
            compact: true,
          ),
          const SizedBox(height: AppSpacing.sm),
          const Divider(height: 1),
          const SizedBox(height: AppSpacing.sm),
          _CandidateActions(
            candidate: candidate,
            justInvited: justInvited,
            compact: false,
            onViewProfile: onViewProfile,
            onViewApplication: onViewApplication,
            onInvite: onInvite,
          ),
        ],
      ),
    );
  }
}

/// "Why X%?" — a collapsed-by-default expandable breakdown (Recommendation
/// Accuracy Patch) built entirely from [RecommendedCandidateModel.matchBreakdown],
/// itself built entirely from real, already-computed backend matching
/// inputs. Never a fabricated or AI-generated explanation, and never
/// expanded by default so a candidate row/card never grows taller than
/// necessary until the Organization actually asks.
class _WhyMatchExpansion extends StatefulWidget {
  const _WhyMatchExpansion({
    required this.candidate,
    required this.opportunityLocationName,
  });

  final RecommendedCandidateModel candidate;
  final String? opportunityLocationName;

  @override
  State<_WhyMatchExpansion> createState() => _WhyMatchExpansionState();
}

class _WhyMatchExpansionState extends State<_WhyMatchExpansion> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final breakdown = widget.candidate.matchBreakdown!;
    final textTheme = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: () => setState(() => _expanded = !_expanded),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _expanded
                      ? 'Hide match details'
                      : 'Why ${widget.candidate.matchScore.toStringAsFixed(0)}%?',
                  style: textTheme.bodySmall?.copyWith(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Icon(
                  _expanded
                      ? Icons.keyboard_arrow_up
                      : Icons.keyboard_arrow_down,
                  size: 16,
                  color: AppColors.primary,
                ),
              ],
            ),
          ),
        ),
        if (_expanded)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.xxs),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final section in _factorSections(breakdown))
                  _WhyMatchFactorSection(section: section),
              ],
            ),
          ),
      ],
    );
  }

  /// Final Recommendation Match Formula: exactly three factor sections --
  /// Major, Skills, and Location -- each showing the real points this
  /// factor contributed out of its real weight (e.g. "25 / 25"), already
  /// computed backend-side and never recalculated here. There is no
  /// Experience section any more (removed from the formula entirely).
  List<_FactorSection> _factorSections(MatchBreakdownModel breakdown) {
    return [
      _FactorSection(
        title: 'Major',
        pointsLabel: _pointsLabel(
          breakdown.majorContribution,
          breakdown.majorWeight,
        ),
        lines: [_academicMatchLine(breakdown)],
      ),
      _FactorSection(
        title: 'Skills',
        pointsLabel: _pointsLabel(
          breakdown.skillsContribution,
          breakdown.skillsWeight,
        ),
        lines: _skillsLines(breakdown),
      ),
      _FactorSection(
        title: 'Location',
        pointsLabel: _locationPointsLabel(breakdown),
        lines: [_locationLine(breakdown)],
      ),
    ];
  }

  /// The exact points contributed out of the exact weight this factor was
  /// scored against for this candidate -- e.g. "25 / 25" or "30 / 60".
  /// "Not applicable" only when the factor was genuinely unscoreable
  /// (e.g. the Opportunity has no Eligible Majors configured).
  String _pointsLabel(double? contribution, int? weight) {
    if (contribution == null || weight == null) return 'Not applicable';
    return '${_formatPoints(contribution)} / $weight';
  }

  /// Location has a third real state Major/Skills don't: "not considered
  /// at all" for a Remote Opportunity -- deliberately distinct copy from
  /// "not applicable" (which would wrongly imply the factor was attempted
  /// and failed, rather than never entering the formula in the first
  /// place). Never a phantom "0 / 15" for Remote.
  String _locationPointsLabel(MatchBreakdownModel breakdown) {
    if (breakdown.locationEligibility == 'not_considered') {
      return 'Not considered';
    }
    return _pointsLabel(breakdown.locationContribution, breakdown.locationWeight);
  }

  /// Whole numbers render without a decimal point (matching the
  /// spec's own "25 / 25" examples); a genuinely fractional contribution
  /// keeps one decimal place rather than rounding it away -- since this
  /// is the same value summed (by the backend) into the displayed total,
  /// rounding it independently here could make the breakdown's numbers
  /// fail to add up to that total.
  String _formatPoints(double value) {
    if (value == value.roundToDouble()) return value.toStringAsFixed(0);
    return value.toStringAsFixed(1);
  }

  List<_BreakdownLine> _skillsLines(MatchBreakdownModel breakdown) {
    if (breakdown.requiredSkillsTotal == 0) {
      return const [
        _BreakdownLine(
          text: 'This opportunity has no required skills configured',
          kind: _BreakdownLineKind.neutral,
        ),
      ];
    }

    final lines = <_BreakdownLine>[
      _BreakdownLine(
        text:
            '${breakdown.requiredSkillsMatched} of '
            '${breakdown.requiredSkillsTotal} required skills matched',
        kind: breakdown.requiredSkillsMatched == breakdown.requiredSkillsTotal
            ? _BreakdownLineKind.positive
            : _BreakdownLineKind.neutral,
      ),
    ];
    for (final matched in breakdown.matchedRequiredSkills) {
      lines.add(
        _BreakdownLine(text: matched, kind: _BreakdownLineKind.positive),
      );
    }
    for (final missing in breakdown.missingRequiredSkills) {
      lines.add(
        _BreakdownLine(
          text: 'Missing: $missing',
          kind: _BreakdownLineKind.negative,
        ),
      );
    }
    return lines;
  }

  _BreakdownLine _academicMatchLine(MatchBreakdownModel breakdown) {
    switch (breakdown.academicMatch) {
      case 'matched':
        return const _BreakdownLine(
          text: 'Major matches an eligible major',
          kind: _BreakdownLineKind.positive,
        );
      case 'not_matched':
        // Defensive/rare on Recommended Candidates -- every listed
        // candidate already passed the identical isStudentEligible() gate
        // that this factor also scores, so this branch is reachable only
        // for a stale Application Match Analysis recalculated after the
        // Student's major changed post-submission, never here in
        // practice. Kept for a truthful label if it ever is reached.
        return const _BreakdownLine(
          text: 'Major does not match an eligible major',
          kind: _BreakdownLineKind.negative,
        );
      case 'not_applicable':
      default:
        return const _BreakdownLine(
          text: 'This opportunity has no eligible majors configured',
          kind: _BreakdownLineKind.neutral,
        );
    }
  }

  _BreakdownLine _locationLine(MatchBreakdownModel breakdown) {
    switch (breakdown.locationEligibility) {
      case 'matched':
        final locationName = widget.opportunityLocationName;
        return _BreakdownLine(
          text: locationName != null
              ? 'Available to work in $locationName'
              : 'Available work location matched',
          kind: _BreakdownLineKind.positive,
        );
      case 'unrestricted':
        return const _BreakdownLine(
          text: 'This opportunity has no fixed location requirement',
          kind: _BreakdownLineKind.neutral,
        );
      case 'not_considered':
      default:
        return const _BreakdownLine(
          text: 'This opportunity is Remote',
          kind: _BreakdownLineKind.neutral,
        );
    }
  }
}

/// One factor's expandable-breakdown section -- a bold title paired with
/// the real "points / weight" label (e.g. "Major" / "25 / 25"), followed
/// by its real detail lines. Exactly the shape the spec's own "Why X%?"
/// examples show: Major, Skills, Location, each mathematically explicit.
class _FactorSection {
  const _FactorSection({
    required this.title,
    required this.pointsLabel,
    required this.lines,
  });

  final String title;
  final String pointsLabel;
  final List<_BreakdownLine> lines;
}

class _WhyMatchFactorSection extends StatelessWidget {
  const _WhyMatchFactorSection({required this.section});

  final _FactorSection section;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                section.title,
                style: textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              Text(
                section.pointsLabel,
                style: textTheme.bodySmall?.copyWith(
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          for (final line in section.lines) _WhyMatchLine(line: line),
        ],
      ),
    );
  }
}

enum _BreakdownLineKind { positive, negative, neutral }

class _BreakdownLine {
  const _BreakdownLine({required this.text, required this.kind});

  final String text;
  final _BreakdownLineKind kind;
}

class _WhyMatchLine extends StatelessWidget {
  const _WhyMatchLine({required this.line});

  final _BreakdownLine line;

  @override
  Widget build(BuildContext context) {
    final (icon, color) = switch (line.kind) {
      _BreakdownLineKind.positive => (
        Icons.check_circle_outline,
        AppColors.success,
      ),
      _BreakdownLineKind.negative => (Icons.cancel_outlined, AppColors.error),
      _BreakdownLineKind.neutral => (Icons.info_outline, AppColors.textMuted),
    };

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xxs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Text(
              line.text,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: AppColors.textSecondary),
            ),
          ),
        ],
      ),
    );
  }
}

/// Skill chips beyond this count collapse into a single "+N more" chip —
/// keeps a candidate with a long skill list from making their row/card
/// much taller than everyone else's.
const _maxVisibleSkills = 3;

class _SkillsSummary extends StatelessWidget {
  const _SkillsSummary({required this.candidate});

  final RecommendedCandidateModel candidate;

  @override
  Widget build(BuildContext context) {
    if (candidate.skills.isEmpty) {
      return Text(
        'No skills listed',
        style: Theme.of(
          context,
        ).textTheme.bodySmall?.copyWith(color: AppColors.textMuted),
      );
    }

    final visible = candidate.skills.take(_maxVisibleSkills).toList();
    final hiddenCount = candidate.skills.length - visible.length;

    return Wrap(
      spacing: AppSpacing.xs,
      runSpacing: AppSpacing.xxs,
      children: [
        for (final skill in visible)
          StatusChip(label: skill.name, compact: true),
        if (hiddenCount > 0)
          StatusChip(
            label: '+$hiddenCount more',
            type: AppStatusType.neutral,
            compact: true,
          ),
      ],
    );
  }
}

/// View Profile always, plus whichever real action fits this candidate's
/// truthful relationship state: Invite to Apply (nothing yet), View
/// Application (already applied), or a disabled label showing the real
/// invitation status (already invited) — never a duplicate-inviting
/// active button where the backend would reject it.
class _CandidateActions extends StatelessWidget {
  const _CandidateActions({
    required this.candidate,
    required this.justInvited,
    required this.compact,
    required this.onViewProfile,
    required this.onViewApplication,
    required this.onInvite,
  });

  final RecommendedCandidateModel candidate;
  final bool justInvited;
  final bool compact;
  final VoidCallback onViewProfile;
  final ValueChanged<int> onViewApplication;
  final VoidCallback onInvite;

  @override
  Widget build(BuildContext context) {
    final width = compact ? null : double.infinity;
    final height = compact ? 36.0 : null;

    Widget primaryAction;
    if (candidate.alreadyApplied) {
      primaryAction = SecondaryButton(
        label: 'View Application',
        width: width,
        height: height,
        onPressed: () => onViewApplication(candidate.applicationId!),
      );
    } else if (candidate.invitationStatus != null || justInvited) {
      primaryAction = SecondaryButton(
        label: _relationshipLabel(candidate) == 'Not Invited'
            ? 'Invited'
            : _relationshipLabel(candidate),
        width: width,
        height: height,
        onPressed: null,
      );
    } else {
      primaryAction = PrimaryButton(
        label: 'Invite to Apply',
        width: width,
        height: height,
        onPressed: onInvite,
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: compact
          ? CrossAxisAlignment.stretch
          : CrossAxisAlignment.stretch,
      children: [
        SecondaryButton(
          label: 'View Profile',
          width: width,
          height: height,
          onPressed: onViewProfile,
        ),
        const SizedBox(height: AppSpacing.xs),
        primaryAction,
      ],
    );
  }
}
