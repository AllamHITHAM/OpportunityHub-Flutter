import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_motion.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/date_formatter.dart';
import '../../../core/widgets/app_widgets.dart';
import '../../../models/opportunity_model.dart';
import '../../../models/quiz_model.dart';
import '../../../providers/organization_opportunities_provider.dart';
import '../../../providers/organization_quiz_provider.dart';
import '../../../routes/app_routes.dart';
import '../../assessments/presentation/assessment_display.dart';
import 'opportunity_display.dart';

/// A centered, intentional desktop width — matches the same "don't stretch
/// a detail page edge-to-edge" fix already applied to the Dashboard,
/// Opportunities list, and Create/Edit Opportunity.
const _maxContentWidth = 960.0;

/// Below this width, the Details card's fields stack into a single column
/// instead of a two-column grid; matches the tablet baseline used
/// elsewhere in this app.
const _twoColumnBreakpoint = 600.0;

/// Organization-side opportunity details. Reached by ID alone (a route
/// parameter, never GoRouter `extra`), so a direct URL visit or a browser
/// refresh renders correctly instead of crashing.
///
/// No applicant list or interview controls belong here yet — Phase
/// 10A.4B added only the shared Quiz template's own summary/actions when
/// [OpportunityModel.recruitmentProcess] is `quiz`.
///
/// **UI Phase O4**: purely a presentation polish — every real field,
/// action, and navigation target below is unchanged. What changed is
/// layout/visual weight only: a centered max-width container, a real theme
/// toggle, stronger card separation, a two-column Details grid, and a
/// clearer Recruitment Process/Quiz management card with View Results
/// given the stronger of the two action buttons.
class OrganizationOpportunityDetailsScreen extends StatefulWidget {
  const OrganizationOpportunityDetailsScreen({
    super.key,
    required this.opportunityId,
  });

  final int opportunityId;

  @override
  State<OrganizationOpportunityDetailsScreen> createState() =>
      _OrganizationOpportunityDetailsScreenState();
}

class _OrganizationOpportunityDetailsScreenState
    extends State<OrganizationOpportunityDetailsScreen> {
  bool _quizLoadTriggered = false;

  /// Phase 10A.4B: the Opportunity itself loads via
  /// `OrganizationOpportunitiesProvider`, so `recruitmentProcess` isn't
  /// known until that resolves — this schedules the shared Quiz template's
  /// own load (a separate provider) exactly once, the first time a `quiz`
  /// Opportunity is actually rendered, rather than guessing eagerly in
  /// `initState()` before the Opportunity itself has loaded.
  void _maybeLoadQuizTemplate(OpportunityModel opportunity) {
    if (opportunity.recruitmentProcess != 'quiz' || _quizLoadTriggered) {
      return;
    }
    _quizLoadTriggered = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<OrganizationQuizProvider>().loadQuizForOpportunity(
        opportunity.id,
      );
    });
  }

  @override
  void initState() {
    super.initState();
    // Deferred to the post-frame callback — see
    // OrganizationOpportunitiesScreen.initState for why calling this
    // directly here would violate Flutter's build-phase constraints.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<OrganizationOpportunitiesProvider>().loadOpportunityDetails(
        widget.opportunityId,
      );
    });
  }

  Future<void> _confirmDelete(OpportunityModel opportunity) async {
    final provider = context.read<OrganizationOpportunitiesProvider>();

    final confirmed = await showAppConfirmationDialog(
      context,
      title: 'Delete Opportunity',
      message:
          'Are you sure you want to delete "${opportunity.title}"? '
          'This cannot be undone.',
      confirmLabel: 'Delete',
      type: AppConfirmationType.danger,
    );
    if (!confirmed) return;

    final success = await provider.deleteOpportunity(opportunity.id);
    if (!mounted) return;

    if (success) {
      context.go(AppRoutes.organizationOpportunities);
    } else if (provider.deleteErrorMessage != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(provider.deleteErrorMessage!)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<OrganizationOpportunitiesProvider>();
    final opportunity = provider.selectedOpportunity;
    final isThisOne = opportunity?.id == widget.opportunityId;
    final isDeleting = provider.isDeleting(widget.opportunityId);
    final hasLoaded = isThisOne && opportunity != null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Opportunity Details'),
        actions: [
          const ThemeToggleSurface(),
          if (hasLoaded) ...[
            IconButton(
              onPressed: isDeleting
                  ? null
                  : () => context.push(
                      AppRoutes.organizationApplicants(opportunity.id),
                      extra: opportunity.title,
                    ),
              icon: const Icon(Icons.people_outline),
              tooltip: 'View Applicants',
            ),
            IconButton(
              onPressed: isDeleting
                  ? null
                  : () => context.push(
                      AppRoutes.organizationOpportunityRecommendedCandidates(
                        opportunity.id,
                      ),
                      extra: opportunity.title,
                    ),
              icon: const Icon(Icons.recommend_outlined),
              tooltip: 'Recommended Candidates',
            ),
            IconButton(
              onPressed: isDeleting
                  ? null
                  : () => context.push(
                      AppRoutes.organizationOpportunityEdit(opportunity.id),
                    ),
              icon: const Icon(Icons.edit_outlined),
              tooltip: 'Edit',
            ),
            IconButton(
              onPressed: isDeleting ? null : () => _confirmDelete(opportunity),
              icon: const Icon(Icons.delete_outline),
              tooltip: 'Delete',
              color: AppColors.error,
            ),
            const SizedBox(width: AppSpacing.xxs),
          ],
        ],
      ),
      body: SafeArea(child: _buildBody(provider, opportunity, isThisOne)),
    );
  }

  Widget _buildBody(
    OrganizationOpportunitiesProvider provider,
    OpportunityModel? opportunity,
    bool isThisOne,
  ) {
    if (provider.isLoadingDetails && !isThisOne) {
      return const AppLoading();
    }

    if (provider.detailsErrorMessage != null && !isThisOne) {
      return AppErrorView(
        message: provider.detailsErrorMessage!,
        onRetry: () => provider.loadOpportunityDetails(
          widget.opportunityId,
          forceRefresh: true,
        ),
      );
    }

    if (opportunity == null || !isThisOne) {
      return const AppLoading();
    }

    _maybeLoadQuizTemplate(opportunity);

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;

        return SingleChildScrollView(
          padding: EdgeInsets.symmetric(
            horizontal: width >= _twoColumnBreakpoint
                ? AppSpacing.xl
                : AppSpacing.screenHorizontal,
            vertical: AppSpacing.md,
          ),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: _maxContentWidth),
              child: _DetailsEntrance(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _IdentityCard(opportunity: opportunity),
                    const SizedBox(height: AppSpacing.lg),
                    _DescriptionCard(opportunity: opportunity),
                    const SizedBox(height: AppSpacing.lg),
                    _DetailsCard(opportunity: opportunity, width: width),
                    const SizedBox(height: AppSpacing.lg),
                    _RequirementsCard(opportunity: opportunity),
                    if (opportunity.recruitmentProcess != 'none') ...[
                      const SizedBox(height: AppSpacing.lg),
                      _AssessmentSection(
                        opportunity: opportunity,
                        width: width,
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
    );
  }
}

/// The opportunity identity area — title, status, and the real
/// type/employment-type/work-mode/experience-level chips — now grouped in
/// its own card so it reads as intentional, not a loose header floating
/// above the rest of the page.
class _IdentityCard extends StatelessWidget {
  const _IdentityCard({required this.opportunity});

  final OpportunityModel opportunity;

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
                child: Text(opportunity.title, style: textTheme.headlineSmall),
              ),
              const SizedBox(width: AppSpacing.xs),
              StatusChip(
                label: statusLabels[opportunity.status] ?? opportunity.status,
                type: statusChipType(opportunity.status),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xxs,
            children: [
              // Opportunity Type Clarity (Candidate Opportunity
              // Preferences + Final Recommendation Match Formula):
              // `info`, not `primary` -- `AppStatusType.primary`'s
              // dark-theme foreground/background pair are both the same
              // dark navy blue, making this chip barely visible in Dark
              // mode (the exact same contrast defect already fixed on
              // the Eligible Major chip below). `info` has a genuinely
              // contrast-safe pair in both themes, and Opportunity Type
              // is the one chip in this row that most needs to read
              // clearly at a glance.
              StatusChip(
                label:
                    opportunityTypeLabels[opportunity.opportunityType] ??
                    opportunity.opportunityType,
                type: AppStatusType.info,
              ),
              StatusChip(
                label:
                    employmentTypeLabels[opportunity.employmentType] ??
                    opportunity.employmentType,
              ),
              StatusChip(
                label:
                    workModeLabels[opportunity.workMode] ??
                    opportunity.workMode,
              ),
              StatusChip(
                label:
                    experienceLevelLabels[opportunity.experienceLevel] ??
                    opportunity.experienceLevel,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DescriptionCard extends StatelessWidget {
  const _DescriptionCard({required this.opportunity});

  final OpportunityModel opportunity;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return AppCard(
      borderColor: AppColors.secondaryLight,
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SectionHeader(title: 'Description'),
          const SizedBox(height: AppSpacing.xs),
          Text(
            opportunity.description,
            style: textTheme.bodyMedium?.copyWith(height: 1.5),
          ),
        ],
      ),
    );
  }
}

class _DetailsCard extends StatelessWidget {
  const _DetailsCard({required this.opportunity, required this.width});

  final OpportunityModel opportunity;
  final double width;

  @override
  Widget build(BuildContext context) {
    final details = [
      DetailField('Location', opportunity.location ?? 'Not specified'),
      // Opportunity Academic Matching Cleanup: Field of Study (legacy,
      // free-text) is deliberately not shown here any more -- Eligible
      // Majors (in the Requirements card below) is the sole authoritative
      // academic requirement.
      DetailField(
        'Education Level',
        educationLevelLabels[opportunity.educationLevel] ?? 'Not specified',
      ),
      DetailField('Salary Range', formatSalaryRange(opportunity)),
      DetailField(
        'Application Deadline',
        opportunity.applicationDeadline != null
            ? formatDate(opportunity.applicationDeadline!)
            : 'Not specified',
      ),
      DetailField('Positions Available', '${opportunity.positionsAvailable}'),
      if (opportunity.createdAt != null)
        DetailField('Posted', formatDate(opportunity.createdAt!)),
    ];

    return AppCard(
      borderColor: AppColors.secondaryLight,
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SectionHeader(title: 'Details'),
          const SizedBox(height: AppSpacing.xs),
          DetailGrid(fields: details, width: width),
        ],
      ),
    );
  }
}

/// Recommendation Accuracy Patch, section 12 -- the exact real
/// requirements Recommended Candidates is evaluated against, so an
/// Organization never has to guess. [OpportunityModel.eligibleMajors] and
/// [OpportunityModel.fieldOfStudy] are deliberately shown as two separate
/// fields (never merged): eligible majors is the real, authoritative
/// eligibility gate (`OpportunityEligibilityService::isStudentEligible()`);
/// field of study is descriptive metadata only, never consulted for
/// eligibility -- see that service's own doc comment on the backend.
/// Required Skills come from the canonical Skill Catalog
/// (`opportunity.opportunitySkills`), the same real ranking input
/// `MatchingService` scores candidates against; preferred (non-required)
/// skills are shown too, but visually secondary.
class _RequirementsCard extends StatelessWidget {
  const _RequirementsCard({required this.opportunity});

  final OpportunityModel opportunity;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final requiredSkills = opportunity.opportunitySkills
        .where((s) => s.isRequired)
        .toList();
    final preferredSkills = opportunity.opportunitySkills
        .where((s) => !s.isRequired)
        .toList();

    return AppCard(
      borderColor: AppColors.secondaryLight,
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SectionHeader(title: 'Requirements'),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'These are the exact eligible majors and required skills '
            'Recommended Candidates evaluates every candidate against.',
            style: textTheme.bodySmall?.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text('ELIGIBLE MAJORS', style: _labelStyle(context)),
          const SizedBox(height: AppSpacing.xxs),
          if (opportunity.eligibleMajors.isEmpty)
            Text(
              'Open to all majors',
              style: textTheme.bodyMedium?.copyWith(
                color: AppColors.textSecondary,
              ),
            )
          else
            Wrap(
              spacing: AppSpacing.xs,
              runSpacing: AppSpacing.xxs,
              children: [
                for (final major in opportunity.eligibleMajors)
                  // Opportunity Academic Matching Cleanup: `info`, not
                  // `primary` -- `AppStatusType.primary`'s dark-theme
                  // foreground/background pair are both the same dark
                  // navy blue, so text on it is nearly unreadable in
                  // Dark mode. `info` already has a genuinely
                  // contrast-safe pair in both themes (a bright blue
                  // foreground against a distinctly lighter/darker
                  // background) and is what the Student-facing Eligible
                  // Majors chips already use -- see
                  // `_EligibleMajorsSection` on
                  // `student_opportunity_details_screen.dart`.
                  StatusChip(label: major, type: AppStatusType.info),
              ],
            ),
          const SizedBox(height: AppSpacing.sm),
          Text('REQUIRED SKILLS', style: _labelStyle(context)),
          const SizedBox(height: AppSpacing.xxs),
          if (requiredSkills.isEmpty)
            Text(
              'No required skills configured',
              style: textTheme.bodyMedium?.copyWith(
                color: AppColors.textSecondary,
              ),
            )
          else
            Wrap(
              spacing: AppSpacing.xs,
              runSpacing: AppSpacing.xxs,
              children: [
                for (final opportunitySkill in requiredSkills)
                  StatusChip(
                    label: opportunitySkill.skill.name,
                    type: AppStatusType.info,
                  ),
              ],
            ),
          if (preferredSkills.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            Text('PREFERRED SKILLS', style: _labelStyle(context)),
            const SizedBox(height: AppSpacing.xxs),
            Wrap(
              spacing: AppSpacing.xs,
              runSpacing: AppSpacing.xxs,
              children: [
                for (final opportunitySkill in preferredSkills)
                  StatusChip(
                    label: opportunitySkill.skill.name,
                    type: AppStatusType.neutral,
                  ),
              ],
            ),
          ],
          if (opportunity.workMode == 'remote') ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              'This opportunity is Remote — candidate location is not '
              'used to restrict Recommended Candidates.',
              style: textTheme.bodySmall?.copyWith(color: AppColors.textMuted),
            ),
          ],
        ],
      ),
    );
  }

  TextStyle? _labelStyle(BuildContext context) =>
      Theme.of(context).textTheme.labelSmall?.copyWith(
        color: AppColors.textSecondary,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.5,
      );
}

/// Phase 10A.4B — the Recruitment Process summary, plus the shared Quiz
/// template's own status/actions when `recruitmentProcess == 'quiz'`. Never
/// forces the Organization into an Application just to manage the Quiz
/// definition (section 15).
///
/// UI Phase O4: the process value now sits as a trailing chip on the
/// section header itself (never a second "Recruitment Process" label
/// duplicated inside the card), and the Quiz sub-section reads as a real
/// management card — its own title/status row, a compact details grid
/// (Questions/Passing Score/Time Limit/Candidate Availability), and two
/// actions with a real hierarchy: View Quiz stays secondary, View Results
/// (or Configure Quiz, when no template exists yet) is the stronger,
/// primary action.
class _AssessmentSection extends StatelessWidget {
  const _AssessmentSection({required this.opportunity, required this.width});

  final OpportunityModel opportunity;
  final double width;

  @override
  Widget build(BuildContext context) {
    final quizProvider = context.watch<OrganizationQuizProvider>();
    final isQuizProcess = opportunity.recruitmentProcess == 'quiz';
    final isThisOpportunitysQuiz =
        quizProvider.loadedOpportunityId == opportunity.id;
    final quiz = isQuizProcess && isThisOpportunitysQuiz
        ? quizProvider.quiz
        : null;

    return AppCard(
      borderColor: AppColors.secondaryLight,
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionHeader(
            title: 'Recruitment Process',
            trailing: StatusChip(
              label:
                  recruitmentProcessLabels[opportunity.recruitmentProcess] ??
                  opportunity.recruitmentProcess,
              type: AppStatusType.primary,
            ),
          ),
          if (isQuizProcess) ...[
            const SizedBox(height: AppSpacing.sm),
            const Divider(),
            const SizedBox(height: AppSpacing.sm),
            _buildQuizStatus(
              context,
              quizProvider,
              isThisOpportunitysQuiz,
              quiz,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildQuizStatus(
    BuildContext context,
    OrganizationQuizProvider quizProvider,
    bool isThisOpportunitysQuiz,
    QuizModel? quiz,
  ) {
    if (quizProvider.isLoadingResults ||
        (quizProvider.isLoading && !isThisOpportunitysQuiz)) {
      return const AppLoading(compact: true);
    }

    if (isThisOpportunitysQuiz &&
        quizProvider.errorMessage != null &&
        quiz == null) {
      return AppErrorView(
        compact: true,
        message: quizProvider.errorMessage!,
        onRetry: () => quizProvider.loadQuizForOpportunity(
          opportunity.id,
          forceRefresh: true,
        ),
      );
    }

    if (quiz == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const OpportunityDetailRow(label: 'Quiz', value: 'Not configured'),
          const SizedBox(height: AppSpacing.sm),
          PrimaryButton(
            label: 'Configure Quiz',
            onPressed: () => context.push(
              AppRoutes.organizationCreateQuizForOpportunity(opportunity.id),
            ),
          ),
        ],
      );
    }

    final quizDetails = [
      DetailField('Questions', '${quiz.questions.length}'),
      DetailField('Passing Score', '${quiz.passingScore}%'),
      DetailField(
        'Time Limit',
        quiz.timeLimitMinutes != null
            ? '${quiz.timeLimitMinutes} minutes'
            : 'Not specified',
      ),
      // Phase 10A.4B addendum — real, already-returned fields; the same
      // policy summary already used on the Quiz editor screen, reused here
      // rather than duplicating the description logic.
      DetailField('Candidate Availability', describeAvailabilityPolicy(quiz)),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                quiz.title,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            const SizedBox(width: AppSpacing.xs),
            StatusChip(
              label: quizStatusLabels[quiz.status] ?? quiz.status,
              type: quizStatusChipType(quiz.status),
              compact: true,
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        DetailGrid(fields: quizDetails, width: width),
        const SizedBox(height: AppSpacing.sm),
        Row(
          children: [
            Expanded(
              child: SecondaryButton(
                label: quiz.status == 'draft' ? 'Manage Quiz' : 'View Quiz',
                onPressed: () => context.push(
                  AppRoutes.organizationOpportunityQuiz(opportunity.id),
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: PrimaryButton(
                label: 'View Results',
                onPressed: () => context.push(
                  AppRoutes.organizationOpportunityQuizResults(opportunity.id),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// A subtle, one-time fade/slide entrance for the whole details page —
/// respects reduced motion via [AppMotion.reduced]. Mirrors the identical
/// pattern already used on Create/Edit Opportunity and the Organization
/// Dashboard.
class _DetailsEntrance extends StatelessWidget {
  const _DetailsEntrance({required this.child});

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
