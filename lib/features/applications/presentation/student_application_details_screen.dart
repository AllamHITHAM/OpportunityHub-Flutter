import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_motion.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_shadows.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/date_formatter.dart';
import '../../../core/widgets/app_widgets.dart';
import '../../../models/application_model.dart';
import '../../../models/assessment_model.dart';
import '../../../models/interview_model.dart';
import '../../../models/offer_model.dart';
import '../../../models/quiz_model.dart';
import '../../../providers/student_applications_provider.dart';
import '../../../providers/student_assessment_provider.dart';
import '../../../providers/student_offer_provider.dart';
import '../../../routes/app_routes.dart';
import '../../assessments/presentation/assessment_display.dart';
import '../../assessments/presentation/assessment_info_tile.dart';
import '../../assessments/presentation/meeting_link_cta.dart';
import '../../offers/presentation/offer_display.dart';
import '../../opportunities/presentation/opportunity_display.dart';
import 'application_display.dart';

const _desktopBreakpoint = 900.0;
const _tabletBreakpoint = 600.0;

enum _ScreenTier { mobile, tablet, desktop }

_ScreenTier _tierFor(double width) {
  if (width >= _desktopBreakpoint) return _ScreenTier.desktop;
  if (width >= _tabletBreakpoint) return _ScreenTier.tablet;
  return _ScreenTier.mobile;
}

/// Read-only application details for students, rebuilt into a premium
/// application-tracking view (UI Phase 4) — a real progress rail (current
/// stage only, never a fabricated history), a truthful "What's Next" panel,
/// and a desktop two-column layout. Reached by ID alone (a route parameter,
/// never GoRouter `extra`) — since no single-application GET endpoint
/// exists on the backend, a cached copy from the already-loaded list is
/// used when available, otherwise the full list is loaded once and this ID
/// is resolved from it.
///
/// The Assessment section (see `_StudentAssessmentSection`) and Offer
/// response section (see `_StudentOfferSection`) below are unchanged from
/// the prior phase's data/business-rule wiring — only their outer
/// presentation context changed. No applicant-review/shortlist UI belongs
/// here.
class StudentApplicationDetailsScreen extends StatefulWidget {
  const StudentApplicationDetailsScreen({
    super.key,
    required this.applicationId,
  });

  final int applicationId;

  @override
  State<StudentApplicationDetailsScreen> createState() =>
      _StudentApplicationDetailsScreenState();
}

class _StudentApplicationDetailsScreenState
    extends State<StudentApplicationDetailsScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _entranceController;

  @override
  void initState() {
    super.initState();
    // Deferred to the post-frame callback — see
    // StudentOpportunitiesScreen.initState for why calling this directly
    // here would violate Flutter's build-phase constraints.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<StudentApplicationsProvider>().loadApplicationDetails(
        widget.applicationId,
      );
      // Independent of the application load above — the Assessment
      // section has its own section-level loading/error state and must
      // never block the rest of this screen (see
      // `_StudentAssessmentSection`).
      context.read<StudentAssessmentProvider>().loadForApplication(
        widget.applicationId,
      );
      // Likewise independent — the Offer section has its own
      // section-level loading/error state (see `_StudentOfferSection`).
      context.read<StudentOfferProvider>().loadForApplication(
        widget.applicationId,
      );
    });

    final reducedMotion = SchedulerBinding
        .instance
        .platformDispatcher
        .accessibilityFeatures
        .disableAnimations;
    _entranceController = AnimationController(
      vsync: this,
      duration: reducedMotion
          ? const Duration(milliseconds: 1)
          : const Duration(milliseconds: 650),
    )..forward();
  }

  @override
  void dispose() {
    _entranceController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<StudentApplicationsProvider>();
    final application = provider.selectedApplication;
    final isThisOne = application?.id == widget.applicationId;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Application Details'),
        actions: const [
          ThemeToggleButton(),
          SizedBox(width: AppSpacing.xs),
        ],
      ),
      body: SafeArea(child: _buildBody(provider, application, isThisOne)),
    );
  }

  Widget _buildBody(
    StudentApplicationsProvider provider,
    ApplicationModel? application,
    bool isThisOne,
  ) {
    if (provider.isLoadingDetails && !isThisOne) {
      return const _DetailsSkeleton();
    }

    if (provider.detailsErrorMessage != null && !isThisOne) {
      return AppErrorView(
        message: provider.detailsErrorMessage!,
        onRetry: () => provider.loadApplicationDetails(
          widget.applicationId,
          forceRefresh: true,
        ),
      );
    }

    if (application == null || !isThisOne) {
      return const _DetailsSkeleton();
    }

    final tier = _tierFor(MediaQuery.sizeOf(context).width);

    return _DetailsContent(
      application: application,
      refreshErrorMessage: provider.detailsErrorMessage,
      onRetryRefresh: () => provider.loadApplicationDetails(
        widget.applicationId,
        forceRefresh: true,
      ),
      tier: tier,
      entranceController: _entranceController,
    );
  }
}

class _DetailsContent extends StatelessWidget {
  const _DetailsContent({
    required this.application,
    required this.refreshErrorMessage,
    required this.onRetryRefresh,
    required this.tier,
    required this.entranceController,
  });

  final ApplicationModel application;
  final String? refreshErrorMessage;
  final VoidCallback onRetryRefresh;
  final _ScreenTier tier;
  final AnimationController entranceController;

  @override
  Widget build(BuildContext context) {
    final isDesktop = tier == _ScreenTier.desktop;
    final coverLetter = application.coverLetter;
    final horizontalPadding = tier == _ScreenTier.mobile
        ? AppSpacing.screenHorizontal
        : AppSpacing.xl;

    final mainSections = <Widget>[
      if (refreshErrorMessage != null) ...[
        AppErrorView(
          compact: true,
          message: refreshErrorMessage!,
          onRetry: onRetryRefresh,
        ),
        const SizedBox(height: AppSpacing.md),
      ],
      ApplicationProgressRail(status: application.status),
      const SizedBox(height: AppSpacing.md),
      if (coverLetter != null && coverLetter.isNotEmpty) ...[
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SectionHeader(title: 'Cover Letter'),
              Text(coverLetter, style: Theme.of(context).textTheme.bodyMedium),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
      ],
      _StudentAssessmentSection(application: application),
      _StudentOfferSection(application: application),
    ];

    final sideSections = <Widget>[
      _SummaryPanel(application: application),
      const SizedBox(height: AppSpacing.md),
      _WhatsNextPanel(application: application),
    ];

    if (!isDesktop) {
      return SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _BackToApplicationsBar(),
            _ApplicationHero(
              application: application,
              isWide: false,
              entranceController: entranceController,
            ),
            _Stagger(
              controller: entranceController,
              index: 1,
              count: 2,
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  horizontalPadding,
                  AppSpacing.md,
                  horizontalPadding,
                  AppSpacing.xxl,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ...sideSections,
                    const SizedBox(height: AppSpacing.md),
                    ...mainSections,
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _BackToApplicationsBar(),
        Expanded(
          child: SizedBox.expand(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  flex: 7,
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _ApplicationHero(
                          application: application,
                          isWide: true,
                          entranceController: entranceController,
                        ),
                        _Stagger(
                          controller: entranceController,
                          index: 1,
                          count: 2,
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(
                              AppSpacing.xl,
                              AppSpacing.lg,
                              AppSpacing.lg,
                              AppSpacing.xxl,
                            ),
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 780),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: mainSections,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                SizedBox(
                  width: 340,
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.md,
                      AppSpacing.lg,
                      AppSpacing.xl,
                      AppSpacing.xxl,
                    ),
                    child: _Stagger(
                      controller: entranceController,
                      index: 1,
                      count: 2,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: sideSections,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Fades and slides a section in as part of the staged entrance. Mirrors
/// the private `_Stagger` already used elsewhere in this app's Student
/// screens (kept feature-local rather than shared).
class _Stagger extends StatelessWidget {
  const _Stagger({
    required this.controller,
    required this.index,
    required this.count,
    required this.child,
  });

  final AnimationController controller;
  final int index;
  final int count;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final start = count <= 1 ? 0.0 : index / count;
    final end = count <= 1 ? 1.0 : ((index + 1.4) / count).clamp(start, 1.0);
    final curved = CurvedAnimation(
      parent: controller,
      curve: Interval(start, end, curve: AppMotion.entrance),
    );

    return FadeTransition(
      opacity: curved,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.03),
          end: Offset.zero,
        ).animate(curved),
        child: child,
      ),
    );
  }
}

/// A real, working "Back to My Applications" affordance — falls back to a
/// direct navigation (rather than assuming a pop always succeeds) when this
/// screen was reached via a direct URL with no back-stack. Mirrors
/// `StudentOpportunityDetailsScreen`'s own `_BackToDiscoverBar`.
class _BackToApplicationsBar extends StatefulWidget {
  const _BackToApplicationsBar();

  @override
  State<_BackToApplicationsBar> createState() => _BackToApplicationsBarState();
}

class _BackToApplicationsBarState extends State<_BackToApplicationsBar> {
  bool _hovered = false;

  void _goBack(BuildContext context) {
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).maybePop();
    } else {
      context.go(AppRoutes.studentApplications);
    }
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: InkWell(
        onTap: () => _goBack(context),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.screenHorizontal,
            vertical: AppSpacing.sm,
          ),
          child: Row(
            children: [
              AnimatedSlide(
                duration: AppMotion.reduced(context, AppMotion.fast),
                offset: _hovered ? const Offset(-0.15, 0) : Offset.zero,
                child: Icon(
                  Icons.arrow_back,
                  size: 18,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(width: AppSpacing.xxs),
              Flexible(
                child: Text(
                  'Back to My Applications',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The application-details hero — real opportunity title, organization,
/// opportunity type, current status, and applied date. Same gradient
/// identity as the Profile/Opportunity-Details heroes.
class _ApplicationHero extends StatelessWidget {
  const _ApplicationHero({
    required this.application,
    required this.isWide,
    required this.entranceController,
  });

  final ApplicationModel application;
  final bool isWide;
  final AnimationController entranceController;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final opportunity = application.opportunity;
    final organizationName = opportunity?.organizationProfile?.organizationName;
    final horizontalPadding = isWide
        ? AppSpacing.xl
        : AppSpacing.screenHorizontal;
    // UI Phase 4.3: title given more presence — still the strongest text
    // in the hero — without growing the hero's own vertical footprint.
    final titleSize = isWide ? 38.0 : 26.0;

    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.primary, AppColors.primaryDark],
        ),
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          horizontalPadding,
          AppSpacing.md,
          horizontalPadding,
          AppSpacing.lg,
        ),
        child: _Stagger(
          controller: entranceController,
          index: 0,
          count: 2,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  shape: BoxShape.circle,
                  boxShadow: AppShadows.card,
                ),
                child: AppAvatar(
                  name: organizationName,
                  size: isWide ? 64 : 52,
                  fallbackIcon: Icons.apartment_outlined,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      opportunity?.title ?? 'Opportunity',
                      style: textTheme.displaySmall?.copyWith(
                        fontSize: titleSize,
                        fontWeight: FontWeight.w800,
                        height: 1.15,
                        color: Colors.white,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (organizationName != null) ...[
                      const SizedBox(height: AppSpacing.xxs),
                      Text(
                        organizationName,
                        style: textTheme.titleSmall?.copyWith(
                          color: Colors.white.withValues(alpha: 0.9),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    const SizedBox(height: AppSpacing.sm),
                    Wrap(
                      spacing: AppSpacing.sm,
                      runSpacing: AppSpacing.xxs,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        AnimatedSwitcher(
                          duration: AppMotion.reduced(
                            context,
                            AppMotion.normal,
                          ),
                          transitionBuilder: (child, animation) =>
                              FadeTransition(opacity: animation, child: child),
                          child: StatusChip(
                            key: ValueKey(application.status),
                            label:
                                applicationStatusLabels[application.status] ??
                                application.status,
                            type: applicationStatusChipType(application.status),
                          ),
                        ),
                        if (opportunity != null)
                          _HeroMetaChip(
                            label:
                                opportunityTypeLabels[opportunity
                                    .opportunityType] ??
                                opportunity.opportunityType,
                          ),
                        if (application.appliedAt != null)
                          _HeroMetaChip(
                            icon: Icons.event_outlined,
                            label:
                                'Applied ${formatDate(application.appliedAt!)}',
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HeroMetaChip extends StatelessWidget {
  const _HeroMetaChip({this.icon, required this.label});

  final IconData? icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: 6,
      ),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.14),
        borderRadius: AppRadius.pillRadius,
        border: Border.all(color: Colors.white.withValues(alpha: 0.28)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: Colors.white),
            const SizedBox(width: 4),
          ],
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The strongest visual component on this screen: a CURRENT-STAGE
/// visualization (never a fabricated event history) of where this real
/// application sits among [ApplicationPipelineStage.values]. The database
/// only stores `application.status`, not a status-change log, so this is
/// deliberately a "you are here" rail, not a timeline with dates — see
/// this phase's own scope notes on why no per-stage timestamp is ever
/// shown here. Terminal outcomes get a distinct end-cap (folded into
/// [_CurrentStatusCallout]) rather than being squeezed into the five-stage
/// rail as if they were just another stage.
///
/// Owns its own one-shot [AnimationController] (UI Phase 4.2) — separate
/// from the page-level entrance controller — so the rail's own staged
/// stage-by-stage reveal and current-stage settle-pulse play as their own
/// visual moment, matching this phase's "rail draws in, stages reveal
/// sequentially, current stage settles" requirement, without coupling this
/// widget's animation timing to the rest of the page.
class ApplicationProgressRail extends StatefulWidget {
  const ApplicationProgressRail({super.key, required this.status});

  final String status;

  @override
  State<ApplicationProgressRail> createState() =>
      _ApplicationProgressRailState();
}

class _ApplicationProgressRailState extends State<ApplicationProgressRail>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    final reducedMotion = SchedulerBinding
        .instance
        .platformDispatcher
        .accessibilityFeatures
        .disableAnimations;
    _controller = AnimationController(
      vsync: this,
      duration: reducedMotion
          ? const Duration(milliseconds: 1)
          : const Duration(milliseconds: 1100),
    )..forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isTerminal = isTerminalApplicationStatus(widget.status);
    final currentStage = pipelineStageForStatus(widget.status);
    final currentIndex = currentStage == null
        ? -1
        : ApplicationPipelineStage.values.indexOf(currentStage);
    final stageCount = ApplicationPipelineStage.values.length;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SectionHeader(title: 'Application Progress'),
          const SizedBox(height: AppSpacing.sm),
          _CurrentStatusCallout(status: widget.status, controller: _controller),
          if (!isTerminal) ...[
            const SizedBox(height: AppSpacing.lg),
            LayoutBuilder(
              builder: (context, constraints) {
                // This is the INNER width available after the card's own
                // padding — noticeably smaller than the device viewport.
                // 300 keeps this app's own default ~420px-wide mobile
                // surface (inner width ~356px after padding) on the
                // horizontal rail, which five small dots comfortably fit,
                // while a genuinely narrow phone (~320-375px outer, ~250-
                // 300px inner) gets the compact vertical stepper this
                // phase calls for.
                final compact = constraints.maxWidth < 300;
                return compact
                    ? _VerticalStepper(
                        currentIndex: currentIndex,
                        controller: _controller,
                        stageCount: stageCount,
                      )
                    : _HorizontalRail(
                        currentIndex: currentIndex,
                        controller: _controller,
                        stageCount: stageCount,
                      );
              },
            ),
          ],
        ],
      ),
    );
  }
}

/// A prominent, immediately-scannable current-status callout — icon,
/// strong colored label, and one truthful supporting sentence. Distinct
/// from the rail below: this answers "what is my status right now",
/// while the rail answers "where does that sit among the stages before
/// it". Also the terminal-outcome branch (accepted/rejected/withdrawn),
/// folded in here rather than duplicated in a second widget, since a
/// terminal outcome *is* the current (and final) status.
class _CurrentStatusCallout extends StatelessWidget {
  const _CurrentStatusCallout({required this.status, required this.controller});

  final String status;
  final AnimationController controller;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final isTerminal = isTerminalApplicationStatus(status);
    final currentStage = pipelineStageForStatus(status);

    final IconData icon;
    final Color color;
    final String label;
    final String supporting;

    if (isTerminal) {
      (icon, color, label, supporting) = switch (status) {
        'accepted' => (
          Icons.check_circle_rounded,
          AppColors.success,
          'Accepted',
          'This application was successful.',
        ),
        'withdrawn' => (
          Icons.undo_rounded,
          AppColors.textMuted,
          'Withdrawn',
          'You withdrew this application.',
        ),
        _ => (
          Icons.cancel_rounded,
          AppColors.error,
          'Not Successful',
          'This application did not proceed further.',
        ),
      };
    } else {
      icon = currentStage != null
          ? applicationPipelineStageIcons[currentStage]!
          : Icons.hourglass_top_rounded;
      color = switch (applicationStatusChipType(status)) {
        AppStatusType.success => AppColors.success,
        AppStatusType.warning => AppColors.warning,
        AppStatusType.error => AppColors.error,
        _ => AppColors.primary,
      };
      label = applicationStatusLabels[status] ?? status;
      supporting = 'This is the current stage of your application.';
    }

    final curved = CurvedAnimation(
      parent: controller,
      curve: const Interval(0, 0.45, curve: AppMotion.entrance),
    );

    return FadeTransition(
      opacity: curved,
      child: ScaleTransition(
        scale: Tween<double>(begin: 0.92, end: 1).animate(curved),
        alignment: Alignment.centerLeft,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 44,
              height: 44,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: color.withValues(alpha: 0.14),
                border: Border.all(color: color.withValues(alpha: 0.4)),
              ),
              child: Icon(icon, size: 22, color: color),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    style: textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: color,
                    ),
                  ),
                  Text(
                    supporting,
                    style: textTheme.bodySmall?.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The desktop/tablet horizontal rail — dots (each with its own visible
/// stage label underneath, UI Phase 4.3) reveal left-to-right in sequence,
/// the current stage settles with a small one-shot scale overshoot at the
/// end of its own reveal (never a permanent pulse).
class _HorizontalRail extends StatelessWidget {
  const _HorizontalRail({
    required this.currentIndex,
    required this.controller,
    required this.stageCount,
  });

  final int currentIndex;
  final AnimationController controller;
  final int stageCount;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < stageCount; i++) ...[
          if (i > 0)
            // Given real flex share (not a cramped fixed slot) so the
            // connector reads as a full line joining the stages rather
            // than a short dash.
            Expanded(
              flex: 2,
              child: Padding(
                // Centers roughly on the dot regardless of stage (current
                // dots are slightly larger) rather than on the taller
                // dot+label column as a whole.
                padding: const EdgeInsets.only(top: 19),
                child: _RailConnector(
                  filled: i <= currentIndex && currentIndex >= 0,
                  controller: controller,
                  index: i,
                  stageCount: stageCount,
                ),
              ),
            ),
          Expanded(
            flex: 3,
            child: Semantics(
              label: _stageSemanticLabel(
                ApplicationPipelineStage.values[i],
                isCurrent: i == currentIndex,
                isCompleted: currentIndex >= 0 && i < currentIndex,
              ),
              child: Column(
                children: [
                  _RailStageDot(
                    stage: ApplicationPipelineStage.values[i],
                    isCurrent: i == currentIndex,
                    isCompleted: currentIndex >= 0 && i < currentIndex,
                    controller: controller,
                    index: i,
                    stageCount: stageCount,
                  ),
                  const SizedBox(height: AppSpacing.xxs),
                  _RailStageLabel(
                    stage: ApplicationPipelineStage.values[i],
                    isCurrent: i == currentIndex,
                    controller: controller,
                    index: i,
                    stageCount: stageCount,
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// A screen-reader-friendly description of one stage's real state — "no
/// color-only status" applies to accessibility too, not just sighted
/// users.
String _stageSemanticLabel(
  ApplicationPipelineStage stage, {
  required bool isCurrent,
  required bool isCompleted,
}) {
  final name = applicationPipelineStageLabels[stage]!;
  final state = isCurrent
      ? 'current stage'
      : isCompleted
      ? 'completed'
      : 'upcoming';
  return '$name, $state';
}

/// The visible stage-name label under each desktop/tablet rail dot —
/// reveals in sync with its own dot (same shared-controller Interval).
/// Never the *only* way a stage is communicated (see [_RailStageDot]'s own
/// color/icon/completed-check treatment) — this is what makes each stage
/// "immediately understandable" rather than relying on an icon alone.
class _RailStageLabel extends StatelessWidget {
  const _RailStageLabel({
    required this.stage,
    required this.isCurrent,
    required this.controller,
    required this.index,
    required this.stageCount,
  });

  final ApplicationPipelineStage stage;
  final bool isCurrent;
  final AnimationController controller;
  final int index;
  final int stageCount;

  @override
  Widget build(BuildContext context) {
    final start = 0.45 + (index / stageCount) * 0.4;
    final end = (start + 0.35).clamp(start, 1.0);
    final reveal = CurvedAnimation(
      parent: controller,
      curve: Interval(start, end, curve: AppMotion.entrance),
    );

    return FadeTransition(
      opacity: reveal,
      child: Text(
        applicationPipelineStageLabels[stage]!,
        textAlign: TextAlign.center,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          fontWeight: isCurrent ? FontWeight.w800 : FontWeight.w600,
          color: isCurrent ? AppColors.textPrimary : AppColors.textSecondary,
        ),
      ),
    );
  }
}

/// The mobile-appropriate compact vertical stepper — a horizontal rail
/// squeezed into ~375px reads as cramped, illegible dots, so narrow
/// widths get a stacked stage list instead (icon + label per row, a
/// vertical connecting line between them).
class _VerticalStepper extends StatelessWidget {
  const _VerticalStepper({
    required this.currentIndex,
    required this.controller,
    required this.stageCount,
  });

  final int currentIndex;
  final AnimationController controller;
  final int stageCount;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < stageCount; i++)
          Semantics(
            label: _stageSemanticLabel(
              ApplicationPipelineStage.values[i],
              isCurrent: i == currentIndex,
              isCompleted: currentIndex >= 0 && i < currentIndex,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Column(
                  children: [
                    _RailStageDot(
                      stage: ApplicationPipelineStage.values[i],
                      isCurrent: i == currentIndex,
                      isCompleted: currentIndex >= 0 && i < currentIndex,
                      controller: controller,
                      index: i,
                      stageCount: stageCount,
                      compact: true,
                    ),
                    if (i < stageCount - 1)
                      SizedBox(
                        width: 2,
                        height: 28,
                        child: _RailConnector(
                          filled: i < currentIndex && currentIndex >= 0,
                          controller: controller,
                          index: i,
                          stageCount: stageCount,
                          vertical: true,
                        ),
                      ),
                  ],
                ),
                const SizedBox(width: AppSpacing.sm),
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    applicationPipelineStageLabels[ApplicationPipelineStage
                        .values[i]]!,
                    style: textTheme.bodyMedium?.copyWith(
                      fontWeight: i == currentIndex
                          ? FontWeight.w700
                          : FontWeight.w500,
                      color: i == currentIndex
                          ? AppColors.textPrimary
                          : AppColors.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _RailStageDot extends StatelessWidget {
  const _RailStageDot({
    required this.stage,
    required this.isCurrent,
    required this.isCompleted,
    required this.controller,
    required this.index,
    required this.stageCount,
    this.compact = false,
  });

  final ApplicationPipelineStage stage;
  final bool isCurrent;
  final bool isCompleted;
  final AnimationController controller;
  final int index;
  final int stageCount;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final (background, foreground, border) = isCurrent
        ? (AppColors.primary, Colors.white, AppColors.primary)
        : isCompleted
        ? (AppColors.primaryContainer, AppColors.primaryDark, AppColors.primary)
        : (AppColors.surface, AppColors.textMuted, AppColors.border);

    // Staggers each dot's own reveal across the rail's shared entrance
    // window, then — for the current stage only — lets its scale overshoot
    // slightly past 1.0 before settling, a one-shot "settle" cue rather
    // than a looping pulse.
    final start = 0.45 + (index / stageCount) * 0.4;
    final end = (start + 0.35).clamp(start, 1.0);
    final reveal = CurvedAnimation(
      parent: controller,
      curve: Interval(start, end, curve: AppMotion.entrance),
    );
    final scale = isCurrent
        ? TweenSequence<double>([
            TweenSequenceItem(tween: Tween(begin: 0.5, end: 1.15), weight: 70),
            TweenSequenceItem(tween: Tween(begin: 1.15, end: 1.0), weight: 30),
          ]).animate(reveal)
        : Tween<double>(begin: 0.5, end: 1.0).animate(reveal);

    final size = compact
        ? (isCurrent ? 36.0 : 30.0)
        : (isCurrent ? 40.0 : 32.0);

    return FadeTransition(
      opacity: reveal,
      child: ScaleTransition(
        scale: scale,
        child: Tooltip(
          message: applicationPipelineStageLabels[stage]!,
          child: AnimatedContainer(
            duration: AppMotion.reduced(context, AppMotion.normal),
            curve: AppMotion.standard,
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: background,
              border: Border.all(color: border, width: isCurrent ? 2 : 1),
              boxShadow: isCurrent ? AppShadows.card : const [],
            ),
            child: Icon(
              isCompleted ? Icons.check : applicationPipelineStageIcons[stage],
              size: isCurrent ? 20 : 16,
              color: foreground,
            ),
          ),
        ),
      ),
    );
  }
}

class _RailConnector extends StatelessWidget {
  const _RailConnector({
    required this.filled,
    required this.controller,
    required this.index,
    required this.stageCount,
    this.vertical = false,
  });

  final bool filled;
  final AnimationController controller;
  final int index;
  final int stageCount;
  final bool vertical;

  @override
  Widget build(BuildContext context) {
    final start = 0.45 + (index / stageCount) * 0.4;
    final reveal = CurvedAnimation(
      parent: controller,
      curve: Interval(
        start,
        (start + 0.3).clamp(start, 1.0),
        curve: AppMotion.standard,
      ),
    );

    return FadeTransition(
      opacity: reveal,
      child: AnimatedContainer(
        duration: AppMotion.reduced(context, AppMotion.normal),
        width: vertical ? 2 : null,
        height: vertical ? null : 3,
        margin: vertical
            ? const EdgeInsets.symmetric(vertical: 2)
            : const EdgeInsets.symmetric(horizontal: 2),
        decoration: BoxDecoration(
          color: filled ? AppColors.primary : AppColors.border,
          borderRadius: BorderRadius.circular(vertical ? 1 : 1.5),
        ),
      ),
    );
  }
}

/// The compact real-data summary — folded into the normal content flow on
/// mobile/tablet, a sticky side card on desktop. Never overloaded: exactly
/// the fields section 23 of this phase asks for, plus one real quick
/// action ("View Opportunity" — the only navigation this panel offers that
/// isn't already reachable elsewhere on this same page; a Quiz action
/// deliberately isn't duplicated here since `_StudentQuizDetails`'s own
/// "Open Quiz" button already covers it in the main content, and this
/// phase's own "do not overload the panel" guidance argues against a
/// second identical action).
class _SummaryPanel extends StatelessWidget {
  const _SummaryPanel({required this.application});

  final ApplicationModel application;

  @override
  Widget build(BuildContext context) {
    final opportunity = application.opportunity;
    final organizationName = opportunity?.organizationProfile?.organizationName;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SectionHeader(title: 'Summary'),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Status',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
              StatusChip(
                compact: true,
                label:
                    applicationStatusLabels[application.status] ??
                    application.status,
                type: applicationStatusChipType(application.status),
              ),
            ],
          ),
          OpportunityDetailRow(
            label: 'Applied',
            value: application.appliedAt != null
                ? formatDate(application.appliedAt!)
                : 'Not specified',
          ),
          if (opportunity != null)
            OpportunityDetailRow(
              label: 'Opportunity',
              value: opportunity.title,
            ),
          if (organizationName != null)
            OpportunityDetailRow(
              label: 'Organization',
              value: organizationName,
            ),
          OpportunityDetailRow(label: 'CV', value: application.cv.title),
          const SizedBox(height: AppSpacing.sm),
          if (opportunity != null)
            SecondaryButton(
              label: 'View Opportunity',
              icon: Icons.open_in_new_rounded,
              onPressed: () => context.push(
                AppRoutes.studentOpportunityDetails(application.opportunityId),
              ),
            ),
        ],
      ),
    );
  }
}

/// A truthful "What's Next?" panel — copy derived purely from
/// `application.status`, never promising a recruiter action or response
/// time this app cannot back up.
class _WhatsNextPanel extends StatelessWidget {
  const _WhatsNextPanel({required this.application});

  final ApplicationModel application;

  String get _message => switch (application.status) {
    'pending' =>
      'Your application has been submitted and is waiting to be reviewed.',
    'reviewed' => 'Your application is currently under review.',
    'shortlisted' =>
      'You have been shortlisted. Watch for an assessment or interview.',
    'in_assessment' => 'Complete your assessment to continue.',
    'interview_scheduled' =>
      'An interview has been scheduled for this application.',
    'offer_sent' => 'You have received an offer. Review it below.',
    'accepted' => 'You accepted this offer. Congratulations!',
    'rejected' => 'This application is no longer active.',
    'withdrawn' => 'You withdrew this application.',
    _ => 'Check back for updates on this application.',
  };

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.primaryContainer.withValues(alpha: 0.5),
        borderRadius: AppRadius.largeRadius,
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.arrow_forward_rounded,
            color: AppColors.primaryDark,
            size: 20,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  "What's Next?",
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                Text(_message, style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailsSkeleton extends StatelessWidget {
  const _DetailsSkeleton();

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.screenHorizontal),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const AppSkeleton(height: 120, borderRadius: AppRadius.largeRadius),
          const SizedBox(height: AppSpacing.lg),
          const AppSkeleton(height: 100, borderRadius: AppRadius.largeRadius),
          const SizedBox(height: AppSpacing.md),
          const AppCardSkeleton(),
        ],
      ),
    );
  }
}

/// The Assessment section for a student's own application — entirely
/// read-only, and only ever rendered when there's something meaningful to
/// show. Kept feature-local to this file (not `assessment_display.dart`,
/// which only holds shared display-label maps, and not
/// `application_display.dart`, which is for `application.status` labels
/// only) — mirrors `organization_application_details_screen.dart`'s own
/// `_AssessmentSection`/`_AssessmentDetailsCard` pattern, minus every
/// organization-only action and internal field.
///
/// Real assessment data always wins over a stale `application.status`: if
/// [StudentAssessmentProvider] has an assessment for this application, it's
/// shown regardless of status (an application can, in practice, sit at
/// `shortlisted` in the UI for a moment after an assessment already exists
/// elsewhere). Only `interview_scheduled` treats a *missing* assessment as
/// something worth calling out — every other status either can't have one
/// yet (`pending`/`reviewed`), hasn't necessarily reached that stage
/// (`shortlisted`), or has already moved past it with nothing on record
/// (`accepted`/`rejected`/`withdrawn`) — none of those are errors.
///
/// **Phase 10A.3**: renders the full Assessment history, one card per
/// entry, oldest first — a completed Quiz stage and a later Interview
/// stage are both shown, sequentially, never one replacing the other. A
/// student must never be left thinking a completed Quiz "disappeared"
/// once the organization advances them to an Interview; each stage keeps
/// its own card, its own status, and (for a Quiz) its own hidden/released
/// result exactly as Phase 10A.2 already governs.
class _StudentAssessmentSection extends StatelessWidget {
  const _StudentAssessmentSection({required this.application});

  final ApplicationModel application;

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<StudentAssessmentProvider>();

    if (provider.hasAssessmentFor(application.id)) {
      final assessments = provider.assessments;
      return Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final assessment in assessments) ...[
              _StudentAssessmentDetailsCard(
                assessment: assessment,
                applicationId: application.id,
              ),
              if (assessment != assessments.last)
                const SizedBox(height: AppSpacing.sm),
            ],
          ],
        ),
      );
    }

    if (application.status != 'interview_scheduled') {
      return const SizedBox.shrink();
    }

    final isLoadingThis =
        provider.isLoading && provider.loadedApplicationId == application.id;
    if (isLoadingThis) {
      return const Padding(
        padding: EdgeInsets.only(bottom: AppSpacing.md),
        child: AppLoading(compact: true),
      );
    }

    final error = provider.loadedApplicationId == application.id
        ? provider.errorMessage
        : null;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: AppErrorView(
        compact: true,
        title: 'Assessment Not Found',
        message:
            error ??
            'This application is marked Interview Scheduled, but no '
                'assessment details are available yet.',
        onRetry: () => context
            .read<StudentAssessmentProvider>()
            .loadForApplication(application.id, forceRefresh: true),
      ),
    );
  }
}

/// The read-only fields of an existing [AssessmentModel] the student is
/// allowed to see — a premium appointment-style summary (UI Phase 4.3),
/// not a plain label/value table. Branches on [AssessmentModel.type] so a
/// future type only needs a new branch here, not a redesign of this
/// section; an unrecognized type falls back to the original generic
/// Type/Status rows rather than guessing at a presentation for it.
class _StudentAssessmentDetailsCard extends StatelessWidget {
  const _StudentAssessmentDetailsCard({
    required this.assessment,
    required this.applicationId,
  });

  final AssessmentModel assessment;
  final int applicationId;

  @override
  Widget build(BuildContext context) {
    final result = assessment.result;
    final interview = assessment.interview;

    final (headerIcon, headerTitle) = switch (assessment.type) {
      'interview' => (
        _interviewTypeIcon(interview?.interviewType),
        interview != null
            ? '${interviewTypeLabels[interview.interviewType] ?? interview.interviewType} Interview'
            : 'Interview',
      ),
      'quiz' => (Icons.quiz_outlined, 'Quiz'),
      _ => (null, null),
    };

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SectionHeader(title: 'Assessment'),
          const SizedBox(height: AppSpacing.xs),
          if (headerIcon != null && headerTitle != null)
            _AssessmentTypeHeader(
              icon: headerIcon,
              title: headerTitle,
              statusLabel:
                  assessmentStatusLabels[assessment.status] ??
                  assessment.status,
              statusType: assessmentStatusChipType(assessment.status),
            )
          else ...[
            // Any other/unknown type: the original generic Type/Status
            // rows — nothing to guess at a richer presentation for, and
            // nothing to crash on.
            OpportunityDetailRow(
              label: 'Type',
              value: assessmentTypeLabels[assessment.type] ?? assessment.type,
            ),
            OpportunityDetailRow(
              label: 'Status',
              value:
                  assessmentStatusLabels[assessment.status] ??
                  assessment.status,
            ),
          ],
          if (result != null) ...[
            const SizedBox(height: AppSpacing.xs),
            OpportunityDetailRow(
              label: 'Result',
              value: assessmentResultLabels[result] ?? result,
            ),
          ],
          if (assessment.type == 'interview') ...[
            const SizedBox(height: AppSpacing.md),
            _StudentInterviewDetails(interview: interview),
          ] else if (assessment.type == 'quiz') ...[
            const SizedBox(height: AppSpacing.md),
            _StudentQuizDetails(
              assessment: assessment,
              applicationId: applicationId,
            ),
          ],
        ],
      ),
    );
  }
}

/// A real, distinct icon per interview type (UI Phase 4.3) — purely
/// presentational, never a different business rule per type.
IconData _interviewTypeIcon(String? interviewType) => switch (interviewType) {
  'online' => Icons.videocam_outlined,
  'phone' => Icons.phone_outlined,
  'onsite' => Icons.location_on_outlined,
  _ => Icons.groups_outlined,
};

/// The card's premium identity header — icon + a combined type title
/// ("Online Interview", "Phone Interview", "Quiz", ...) + the real
/// Assessment status as a chip, so status is never communicated by color
/// alone.
class _AssessmentTypeHeader extends StatelessWidget {
  const _AssessmentTypeHeader({
    required this.icon,
    required this.title,
    required this.statusLabel,
    required this.statusType,
  });

  final IconData icon;
  final String title;
  final String statusLabel;
  final AppStatusType statusType;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 48,
          height: 48,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: AppColors.primaryContainer,
          ),
          child: Icon(icon, size: 24, color: AppColors.primaryDark),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                title,
                style: textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 2),
              AnimatedSwitcher(
                duration: AppMotion.reduced(context, AppMotion.normal),
                transitionBuilder: (child, animation) =>
                    FadeTransition(opacity: animation, child: child),
                child: StatusChip(
                  key: ValueKey(statusLabel),
                  compact: true,
                  label: statusLabel,
                  type: statusType,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Interview-specific detail — student-safe fields only. Deliberately never
/// reads [InterviewModel.interviewerEmail], [InterviewModel.companyFeedback],
/// [InterviewModel.rating], or [InterviewModel.decision]: those exist on the
/// shared model for the organization side (see
/// `organization_application_details_screen.dart`) and must never reach
/// this screen, even though the model still carries them.
/// [AssessmentModel.result] (rendered by the parent card) is the
/// student-facing outcome instead of the interview's own raw decision.
class _StudentInterviewDetails extends StatelessWidget {
  const _StudentInterviewDetails({required this.interview});

  final InterviewModel? interview;

  @override
  Widget build(BuildContext context) {
    final interview = this.interview;
    if (interview == null) return const SizedBox.shrink();

    final meetingLink = cleanDisplayText(interview.meetingLink);
    final interviewerName = cleanDisplayText(interview.interviewerName);
    final notes = cleanDisplayText(interview.notes);
    final isOnline = interview.interviewType == 'online';
    final validMeetingUri = isOnline && meetingLink != null
        ? validHttpUri(meetingLink)
        : null;

    // Date/Time/Duration are genuinely optional — omitted entirely (not
    // "Not specified") when absent, per this phase's own tile guidance.
    final infoTiles = <Widget>[
      if (interview.scheduledAt != null) ...[
        AssessmentInfoTile(
          icon: Icons.calendar_today_outlined,
          label: 'Date',
          value: formatDate(interview.scheduledAt!),
        ),
        AssessmentInfoTile(
          icon: Icons.access_time_rounded,
          label: 'Time',
          value: formatTime(interview.scheduledAt!),
        ),
      ],
      if (interview.durationMinutes != null)
        AssessmentInfoTile(
          icon: Icons.timer_outlined,
          label: 'Duration',
          value: '${interview.durationMinutes} minutes',
        ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (infoTiles.isNotEmpty) ...[
          AssessmentTileGrid(tiles: infoTiles),
          const SizedBox(height: AppSpacing.sm),
        ],
        // Exactly one attendance-detail element, matching whichever field
        // this interview's real type needs (Phase Final-QA-1's own rule,
        // preserved) — a real, launchable meeting link gets a prominent
        // CTA; a missing/empty/invalid link never surfaces its raw value
        // (which may be malformed legacy data), only a graceful
        // placeholder — never fabricate a URL that isn't there.
        if (isOnline)
          validMeetingUri != null
              ? MeetingLinkCta(uri: validMeetingUri, rawLink: meetingLink!)
              : const MeetingLinkPlaceholder()
        else
          AssessmentInfoTile(
            icon: interview.interviewType == 'phone'
                ? Icons.phone_outlined
                : Icons.location_on_outlined,
            label: interviewContactDetailLabel(interview.interviewType),
            value: interviewContactDetailValue(interview) ?? 'Not specified',
          ),
        if (interviewerName != null) ...[
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              Icon(
                Icons.person_outline_rounded,
                size: 18,
                color: AppColors.textSecondary,
              ),
              const SizedBox(width: AppSpacing.xs),
              Text(
                'Interviewer',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: AppColors.textSecondary),
              ),
              const SizedBox(width: AppSpacing.sm),
              Flexible(
                child: Text(
                  interviewerName,
                  textAlign: TextAlign.end,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ],
        const SizedBox(height: AppSpacing.sm),
        Row(
          children: [
            Expanded(
              // Deliberately not "Interview Status" — the assessment-level
              // status chip already shown next to the header title above
              // can read the same ("Scheduled") for most of this
              // interview's life. This row reflects the interview's own
              // distinct backend field (InterviewModel.status, e.g.
              // completed/cancelled/rescheduled/no_show), which can diverge
              // from the assessment status — the label makes that a
              // separate fact instead of a visual duplicate.
              child: Text(
                'Attendance Status',
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            StatusChip(
              compact: true,
              label:
                  interviewStatusLabels[interview.status] ?? interview.status,
              type: switch (interview.status) {
                'completed' => AppStatusType.success,
                'cancelled' || 'no_show' => AppStatusType.neutral,
                _ => AppStatusType.info,
              },
            ),
          ],
        ),
        if (notes != null) ...[
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Notes',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: AppColors.textMuted,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 2),
          Text(notes, style: Theme.of(context).textTheme.bodyMedium),
        ],
      ],
    );
  }
}

/// Quiz-specific detail for `assessment.type == 'quiz'` — a compact quiz
/// summary (title, passing score, time limit, question count) plus a
/// single Open Quiz action while the quiz is published and not yet
/// completed, matching [_StudentInterviewDetails]'s role for interviews.
///
/// Deliberately doesn't try to distinguish "not started" from "in
/// progress" — [StudentQuizScreen] itself determines Start vs. Resume the
/// moment it's opened (see that screen's own doc comment), so a single
/// "Open Quiz" action covers both without this screen needing to know
/// which one applies, or fetching the attempt itself (there is no
/// endpoint to do that without also starting/resuming it).
///
/// Reads no answer/score/correct-answer data — [AssessmentModel.result]
/// (rendered by the parent card once non-null) is the only outcome shown
/// here; a numeric score is only ever available transiently inside
/// [StudentQuizScreen] right after the student's own submit — see that
/// screen's doc comment for why.
class _StudentQuizDetails extends StatelessWidget {
  const _StudentQuizDetails({
    required this.assessment,
    required this.applicationId,
  });

  final AssessmentModel assessment;
  final int applicationId;

  Future<void> _openQuiz(BuildContext context) async {
    await context.push(AppRoutes.studentQuiz(assessment.id));
    if (!context.mounted) return;
    context.read<StudentAssessmentProvider>().loadForApplication(
      applicationId,
      forceRefresh: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    final QuizModel? quiz = assessment.quiz;
    final textTheme = Theme.of(context).textTheme;

    if (assessment.status == 'completed') {
      return Padding(
        padding: const EdgeInsets.only(top: AppSpacing.xs),
        child: Text('Quiz completed', style: textTheme.titleSmall),
      );
    }

    if (quiz == null || quiz.status != 'published') {
      return Padding(
        padding: const EdgeInsets.only(top: AppSpacing.xs),
        child: Text(
          'Quiz details are not available yet.',
          style: textTheme.bodySmall?.copyWith(color: AppColors.textSecondary),
        ),
      );
    }

    // Phase 10A.4B addendum — this candidate's own frozen window, real and
    // truthful the moment they're advanced (never merely "the quiz was
    // published"). `null`/`null` means no gating at all (legacy quiz),
    // which falls straight through to the normal Open Quiz card below,
    // exactly matching pre-addendum behavior.
    final availableAt = assessment.availableAt;
    final dueAt = assessment.dueAt;
    final now = DateTime.now();

    if (availableAt != null && now.isBefore(availableAt)) {
      return _QuizTimingCard(
        icon: Icons.hourglass_top_outlined,
        title: 'Assessment Upcoming',
        message:
            'You have been selected for "${quiz.title}". It becomes '
            'available on ${formatDateTime(availableAt)}'
            '${dueAt != null ? ', with a deadline of ${formatDateTime(dueAt)}' : ''}.',
      );
    }

    if (dueAt != null && now.isAfter(dueAt)) {
      return _QuizTimingCard(
        icon: Icons.event_busy_outlined,
        title: 'Assessment Deadline Passed',
        message:
            'The submission deadline for "${quiz.title}" '
            '(${formatDateTime(dueAt)}) has passed.',
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AssessmentTileGrid(
          tiles: [
            AssessmentInfoTile(
              icon: Icons.quiz_outlined,
              label: 'Quiz Title',
              value: quiz.title,
            ),
            AssessmentInfoTile(
              icon: Icons.flag_outlined,
              label: 'Passing Score',
              value: '${quiz.passingScore}%',
            ),
            AssessmentInfoTile(
              icon: Icons.timer_outlined,
              label: 'Time Limit',
              value: quiz.timeLimitMinutes != null
                  ? '${quiz.timeLimitMinutes} minutes'
                  : 'No time limit',
            ),
            AssessmentInfoTile(
              icon: Icons.checklist_outlined,
              label: 'Questions',
              value: '${quiz.questions.length}',
            ),
            if (dueAt != null)
              AssessmentInfoTile(
                icon: Icons.event_outlined,
                label: 'Deadline',
                value: formatDateTime(dueAt),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        PrimaryButton(label: 'Open Quiz', onPressed: () => _openQuiz(context)),
      ],
    );
  }
}

/// Phase 10A.4B addendum — the Upcoming/Deadline Passed states of
/// [_StudentQuizDetails], both of which show real, truthful timing instead
/// of the normal quiz-summary tiles + Open Quiz action. Never offers an
/// action of its own — a Student who taps into a card in either state has
/// nothing to do yet (or nothing left to do); [StudentQuizScreen] itself
/// independently re-derives and enforces the same state if reached
/// directly (e.g. via a stale link), so this card is a truthful preview,
/// not the real gate.
class _QuizTimingCard extends StatelessWidget {
  const _QuizTimingCard({
    required this.icon,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: AppColors.textSecondary),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: textTheme.titleSmall),
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  message,
                  style: textTheme.bodySmall?.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Which student Offer response action is currently in flight, if any — so
/// only the button the student actually tapped shows a spinner, while both
/// stay disabled together via `StudentOfferProvider.isResponding`. Mirrors
/// `_StatusAction`/`_pendingAction` in
/// `organization_application_details_screen.dart`.
enum _StudentOfferAction { accept, decline }

/// The Offer section for a student's own application (Phase 6C-3) —
/// section-level loading/error state, entirely independent of the rest of
/// this screen (see `_StudentApplicationDetailsScreenState.initState`).
///
/// Real Offer data always wins over a stale `application.status`: if
/// [StudentOfferProvider] has an Offer for this application, it's shown
/// regardless of status — the same "actual data is authoritative" rule
/// `_StudentAssessmentSection` already follows for Assessments, and
/// `_OfferSection` follows on the organization side. Only
/// `application.status == 'offer_sent'` treats a *missing* Offer as a
/// controlled inconsistency worth calling out; every other status either
/// can't have one yet or has already moved past it, which is normal, not
/// an error — see [_StudentApplicationDetailsScreenState] and
/// `docs/BUSINESS_RULES.md` (backend) section 13 on the rejected-vs-
/// declined distinction this deliberately does not conflate:
/// `application.status == 'rejected'` alone never implies an Offer was
/// declined, since an early-funnel organization rejection reaches the same
/// status with no Offer at all.
class _StudentOfferSection extends StatefulWidget {
  const _StudentOfferSection({required this.application});

  final ApplicationModel application;

  @override
  State<_StudentOfferSection> createState() => _StudentOfferSectionState();
}

class _StudentOfferSectionState extends State<_StudentOfferSection> {
  _StudentOfferAction? _pendingAction;

  Future<void> _run(
    StudentOfferProvider provider,
    _StudentOfferAction action,
    Future<bool> Function() call,
  ) async {
    setState(() => _pendingAction = action);
    final success = await call();
    if (!mounted) return;
    setState(() => _pendingAction = null);

    if (success) {
      // The backend response carries only the Offer, never a nested
      // Application (see `OfferRepository`'s own doc comment) — a
      // targeted refresh is the least-coupled way to pick up the real
      // `accepted`/`rejected` Application status, the same bridging
      // pattern the organization Send Offer flow already uses.
      context.read<StudentApplicationsProvider>().loadApplicationDetails(
        widget.application.id,
        forceRefresh: true,
      );
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            action == _StudentOfferAction.accept
                ? 'Offer accepted successfully'
                : 'Offer declined successfully',
          ),
        ),
      );
    } else if (provider.actionErrorMessage != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(provider.actionErrorMessage!)));
    }
  }

  Future<void> _confirmAccept(StudentOfferProvider provider) async {
    final confirmed = await showAppConfirmationDialog(
      context,
      title: 'Accept Offer',
      message: 'Are you sure you want to accept this offer?',
      confirmLabel: 'Accept',
      type: AppConfirmationType.success,
    );
    if (!confirmed || !mounted) return;

    await _run(provider, _StudentOfferAction.accept, provider.accept);
  }

  Future<void> _confirmDecline(StudentOfferProvider provider) async {
    final confirmed = await showAppConfirmationDialog(
      context,
      title: 'Decline Offer',
      message: 'Are you sure you want to decline this offer?',
      confirmLabel: 'Decline',
      type: AppConfirmationType.danger,
    );
    if (!confirmed || !mounted) return;

    await _run(provider, _StudentOfferAction.decline, provider.decline);
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<StudentOfferProvider>();
    final applicationId = widget.application.id;
    final isThisOne = provider.loadedApplicationId == applicationId;

    // Only show a loading spinner when there's nothing already loaded for
    // this exact application to keep showing in the meantime — a
    // force-refresh of an already-displayed Offer shouldn't cause it to
    // disappear and flash a spinner in its place.
    if (provider.isLoading && !(isThisOne && provider.offer != null)) {
      return const Padding(
        padding: EdgeInsets.only(top: AppSpacing.md),
        child: AppLoading(compact: true),
      );
    }

    if (isThisOne && provider.offer != null) {
      return Padding(
        padding: const EdgeInsets.only(top: AppSpacing.md),
        child: _StudentOfferCard(
          offer: provider.offer!,
          isBusy: provider.isResponding,
          pendingAction: _pendingAction,
          onAccept: () => _confirmAccept(provider),
          onDecline: () => _confirmDecline(provider),
        ),
      );
    }

    if (isThisOne && provider.errorMessage != null) {
      return Padding(
        padding: const EdgeInsets.only(top: AppSpacing.md),
        child: AppErrorView(
          compact: true,
          message: provider.errorMessage!,
          onRetry: () =>
              provider.loadForApplication(applicationId, forceRefresh: true),
        ),
      );
    }

    if (widget.application.status == 'offer_sent') {
      // A genuine backend inconsistency (the application says an Offer was
      // sent, but no Offer record backs it up) — a controlled warning with
      // retry, never a fake/fabricated Offer card.
      return Padding(
        padding: const EdgeInsets.only(top: AppSpacing.md),
        child: AppErrorView(
          compact: true,
          icon: Icons.warning_amber_rounded,
          message: 'Offer details are currently unavailable.',
          onRetry: () =>
              provider.loadForApplication(applicationId, forceRefresh: true),
        ),
      );
    }

    return const SizedBox.shrink();
  }
}

/// The read-only Offer fields the student is allowed to see, plus the
/// Accept/Decline actions while [offer] is still awaiting a response.
/// Reuses `offer_display.dart`'s label/formatting helpers — the same ones
/// the organization-side `_OfferSummaryCard` uses — so salary/status
/// formatting is defined in exactly one place for both roles.
class _StudentOfferCard extends StatelessWidget {
  const _StudentOfferCard({
    required this.offer,
    required this.isBusy,
    required this.pendingAction,
    required this.onAccept,
    required this.onDecline,
  });

  final OfferModel offer;
  final bool isBusy;
  final _StudentOfferAction? pendingAction;
  final VoidCallback onAccept;
  final VoidCallback onDecline;

  @override
  Widget build(BuildContext context) {
    final title = cleanDisplayText(offer.title);
    final message = cleanDisplayText(offer.message);
    final salary = formatSalary(
      amount: offer.salaryAmount,
      currency: offer.salaryCurrency,
      period: offer.salaryPeriod,
    );
    // The card's own header names the terminal outcome explicitly once one
    // exists, rather than leaving the student to infer it from the status
    // chip alone — see this section's own doc comment on why
    // `Offer.status == 'declined'` (never `Application.status` alone) is
    // what may ever justify the "Offer Declined" wording appearing
    // anywhere on this screen.
    final headerTitle = switch (offer.status) {
      'accepted' => 'Offer Accepted',
      'declined' => 'Offer Declined',
      _ => 'Offer',
    };

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: SectionHeader(title: headerTitle)),
              StatusChip(
                label: offerStatusLabels[offer.status] ?? offer.status,
                type: offerStatusChipType(offer.status),
              ),
            ],
          ),
          if (title != null) OpportunityDetailRow(label: 'Title', value: title),
          if (salary != null)
            OpportunityDetailRow(label: 'Salary', value: salary),
          if (offer.startDate != null)
            OpportunityDetailRow(
              label: 'Start Date',
              value: formatDate(offer.startDate!),
            ),
          if (offer.sentAt != null)
            OpportunityDetailRow(
              label: 'Sent At',
              value: formatDate(offer.sentAt!),
            ),
          if (offer.respondedAt != null)
            OpportunityDetailRow(
              label: 'Responded At',
              value: formatDate(offer.respondedAt!),
            ),
          if (message != null) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(message, style: Theme.of(context).textTheme.bodyMedium),
          ],
          if (offer.status == 'sent') ...[
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                Expanded(
                  child: DangerButton(
                    label: 'Decline Offer',
                    isLoading: pendingAction == _StudentOfferAction.decline,
                    onPressed: isBusy ? null : onDecline,
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: PrimaryButton(
                    label: 'Accept Offer',
                    isLoading: pendingAction == _StudentOfferAction.accept,
                    onPressed: isBusy ? null : onAccept,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
