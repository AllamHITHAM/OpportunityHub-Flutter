import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_motion.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/date_formatter.dart';
import '../../../core/widgets/app_widgets.dart';
import '../../../models/application_model.dart';
import '../../../models/assessment_model.dart';
import '../../../models/match_analysis_model.dart';
import '../../../models/offer_model.dart';
import '../../../models/quiz_model.dart';
import '../../../providers/organization_applications_provider.dart';
import '../../../providers/organization_assessment_provider.dart';
import '../../../providers/organization_match_analysis_provider.dart';
import '../../../providers/organization_offer_provider.dart';
import '../../../routes/app_routes.dart';
import '../../assessments/presentation/assessment_display.dart';
import '../../assessments/presentation/assessment_info_tile.dart';
import '../../assessments/presentation/choose_assessment_type_sheet.dart';
import '../../assessments/presentation/complete_interview_sheet.dart';
import '../../assessments/presentation/meeting_link_cta.dart';
import '../../offers/presentation/offer_display.dart';
import '../../offers/presentation/send_offer_sheet.dart';
import '../../opportunities/presentation/opportunity_display.dart';
import 'application_display.dart';

/// UI Phase O6: below this width, the main content and sidebar stack into
/// one column instead of sitting side by side.
const _sidebarBreakpoint = 900.0;

/// A centered, intentional desktop width — matches the same "don't stretch
/// a page edge-to-edge" treatment already applied to the Dashboard,
/// Opportunities list, Opportunity Details, and Quiz Results. Wider than
/// those single-column pages since this one has a real two-column layout
/// to fill.
const _maxContentWidth = 1200.0;

/// The status actions available for a given application status/assessment
/// combination. `chooseAssessment` (Phase 4B-1) only ever appears for
/// `shortlisted` applications that don't already have an assessment —
/// `interview_scheduled`/`accepted` remain read-only for status actions
/// (a read-only Assessment section covers `interview_scheduled` instead),
/// and `rejected`/`withdrawn` expose no forward actions.
///
/// `completeInterview` (Phase Final-QA-2.1) only ever appears for
/// `in_assessment` applications whose Assessment is `type == 'interview'`,
/// still not `completed`, and actually has an `Interview` record —
/// otherwise there is nothing to complete (never shown for `type ==
/// 'quiz'`, which reaches `completed` on its own via the student's quiz
/// submission, never an organization action). This is the step that moves
/// `Assessment.status` to `completed`, which is what makes `sendOffer`
/// below actually reachable — previously nothing in this app could ever
/// call `PUT /organization/interviews/{interview}/complete`, so `sendOffer`
/// was correct but unreachable in practice.
///
/// `sendOffer` (Phase 6C-2) only ever appears for `in_assessment`
/// applications whose Assessment is `completed` and which don't already
/// have an Offer — `Assessment.result` is deliberately never checked (see
/// `_StatusActionsSection`/docs/BUSINESS_RULES.md on the backend: the
/// organization retains final hiring authority regardless of
/// passed/failed/waiting/no result). `reject` remains available at
/// `in_assessment`, at any Assessment state, matching the backend's own
/// unrestricted rejection rule — but (Phase 6C-4) never once an Offer
/// exists: the backend now hard-blocks the generic status endpoint the
/// moment an Offer exists (`Organization\ApplicationController::
/// updateStatus()`, since v1 has no Offer cancel/rescind workflow), so
/// `reject` is hidden the same way `sendOffer` already was — via the real
/// Offer data (`hasOffer`), never `application.status` alone, since that
/// can be transiently stale (see `_OfferSection`). Once an Offer has
/// actually been sent (`offer_sent`), no status action is offered at all;
/// the organization waits for the student's response.
enum _StatusAction {
  markReviewed,
  shortlist,
  reject,
  chooseAssessment,
  completeInterview,
  sendOffer,
}

List<_StatusAction> _actionsFor(
  String status, {
  required bool hasAssessment,
  required bool canCompleteInterview,
  required bool assessmentCompleted,
  required bool quizDecisionPending,
  required bool hasOffer,
}) {
  switch (status) {
    case 'pending':
      return [
        _StatusAction.markReviewed,
        _StatusAction.shortlist,
        _StatusAction.reject,
      ];
    case 'reviewed':
      return [_StatusAction.shortlist, _StatusAction.reject];
    case 'shortlisted':
      return [
        if (!hasAssessment) _StatusAction.chooseAssessment,
        _StatusAction.reject,
      ];
    case 'in_assessment':
      return [
        if (canCompleteInterview) _StatusAction.completeInterview,
        // Phase 10A.4A: a completed Quiz's own "Next Step" decision panel
        // (`_QuizAssessmentSummaryCard`) owns Send Offer/Advance to
        // Interview/Reject entirely while its result is still unreleased
        // — none of the three appear as generic actions here in that
        // state, so a decision can never bypass the release-timing/
        // Student-visibility rules by going through this section instead.
        if (hasAssessment &&
            assessmentCompleted &&
            !hasOffer &&
            !quizDecisionPending)
          _StatusAction.sendOffer,
        // Phase 6C-4: the backend now hard-blocks the generic status
        // endpoint once an Offer exists (see
        // Organization\ApplicationController::updateStatus()), so Reject
        // must never be offered once `hasOffer` is true either — even
        // while `application.status` hasn't yet caught up from
        // `in_assessment` to `offer_sent`. Matches Send Offer's own
        // `!hasOffer` guard just above. Also suppressed while a Quiz
        // decision is pending, for the same reason Send Offer is above.
        if (!hasOffer && !quizDecisionPending) _StatusAction.reject,
      ];
    default:
      // offer_sent, rejected, withdrawn, interview_scheduled, accepted —
      // no status actions; this phase never downgrades or exposes further
      // controls for any of them. interview_scheduled instead gets a
      // read-only Assessment section (see _AssessmentSection); offer_sent
      // (and beyond) gets a read-only Offer section (see _OfferSection).
      return [];
  }
}

/// Organization-side application details. Reached by ID alone (a route
/// parameter, never GoRouter `extra`), so a direct URL visit or a browser
/// refresh renders correctly instead of crashing.
///
/// UI Phase O6: purely a presentation polish over the exact same real
/// data/actions — a theme toggle, a centered desktop width with a real
/// main/sidebar split, a compact (not full-width) actions area, and
/// clearer, denser Assessment/Match Analysis/Applicant/CV/Opportunity
/// cards. No status rule, Assessment/Quiz/Interview/Offer/Match Analysis
/// logic, or navigation target changed.
class OrganizationApplicationDetailsScreen extends StatefulWidget {
  const OrganizationApplicationDetailsScreen({
    super.key,
    required this.applicationId,
  });

  final int applicationId;

  @override
  State<OrganizationApplicationDetailsScreen> createState() =>
      _OrganizationApplicationDetailsScreenState();
}

class _OrganizationApplicationDetailsScreenState
    extends State<OrganizationApplicationDetailsScreen> {
  @override
  void initState() {
    super.initState();
    // Deferred to the post-frame callback — see
    // StudentOpportunitiesScreen.initState for why calling this directly
    // here would violate Flutter's build-phase constraints.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<OrganizationApplicationsProvider>().loadApplicationDetails(
        widget.applicationId,
      );
      // Assessment loading is independent of the application details
      // fetch above and must never block the rest of this screen — see
      // _AssessmentSection, which renders its own section-level
      // loading/error state.
      context.read<OrganizationAssessmentProvider>().loadForApplication(
        widget.applicationId,
      );
      // Offer loading is likewise independent and section-level only —
      // see _OfferSection.
      context.read<OrganizationOfferProvider>().loadForApplication(
        widget.applicationId,
      );
      // Match analysis loading is likewise independent and section-level
      // only — see _MatchAnalysisSection. The page itself must never block
      // on this (Phase 8A-3).
      context.read<OrganizationMatchAnalysisProvider>().loadForApplication(
        widget.applicationId,
      );
    });
  }

  /// Downloads the CV via the secure, ownership-checked backend endpoint
  /// and confirms success — v1 stops at fetching the bytes rather than
  /// attempting OS-level PDF viewing, which would need platform
  /// file-opening dependencies beyond this phase's scope (mirrors
  /// StudentCvScreen's own "View CV" action).
  Future<void> _viewCv(
    OrganizationApplicationsProvider provider,
    int applicationId,
  ) async {
    final bytes = await provider.downloadCv(applicationId);
    if (!mounted) return;

    if (bytes != null) {
      final kb = (bytes.length / 1024).toStringAsFixed(0);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('CV downloaded ($kb KB)')));
    } else if (provider.cvDownloadErrorMessage != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(provider.cvDownloadErrorMessage!)));
    }
  }

  @override
  Widget build(BuildContext context) {
    // Establishes a real Theme dependency for this whole build — see
    // AppCard's own UI Phase O4.1 fix for why this is what makes
    // AppColors-styled content here refresh immediately on a theme toggle.
    Theme.of(context);

    final provider = context.watch<OrganizationApplicationsProvider>();
    final application = provider.selectedApplication;
    final isThisOne = application?.id == widget.applicationId;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Application Details'),
        actions: const [ThemeToggleSurface()],
      ),
      body: SafeArea(child: _buildBody(provider, application, isThisOne)),
    );
  }

  Widget _buildBody(
    OrganizationApplicationsProvider provider,
    ApplicationModel? application,
    bool isThisOne,
  ) {
    if (provider.isLoadingDetails && !isThisOne) {
      return const AppLoading();
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
      return const AppLoading();
    }

    final applicant = application.applicant;
    final opportunity = application.opportunity;
    final cv = application.cv;
    final coverLetter = application.coverLetter;
    final applicantName = cleanDisplayText(applicant?.name);
    final applicantBio = cleanDisplayText(applicant?.bio);

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= _sidebarBreakpoint;

        final mainColumn = <Widget>[
          _AssessmentSection(application: application),
          _OfferSection(application: application),
          _MatchAnalysisSection(applicationId: application.id),
          const SizedBox(height: AppSpacing.md),
          _ApplicantCard(applicant: applicant, bio: applicantBio),
          if (applicant != null && applicant.skills.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            _SkillsCard(applicant: applicant),
          ],
          if (coverLetter != null && coverLetter.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            _CoverLetterCard(coverLetter: coverLetter),
          ],
        ];

        final sidebarColumn = <Widget>[
          _ApplicationSummaryCard(application: application),
          const SizedBox(height: AppSpacing.md),
          _CvCard(
            cv: cv,
            isDownloading: provider.isDownloadingCv(application.id),
            onView: () => _viewCv(provider, application.id),
          ),
          if (opportunity != null) ...[
            const SizedBox(height: AppSpacing.md),
            _OpportunityCard(opportunity: opportunity),
          ],
        ];

        return SingleChildScrollView(
          padding: EdgeInsets.symmetric(
            horizontal: isWide ? AppSpacing.xl : AppSpacing.screenHorizontal,
            vertical: AppSpacing.md,
          ),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: _maxContentWidth),
              child: _DetailsEntrance(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _CandidateHeaderCard(
                      application: application,
                      applicantName: applicantName,
                    ),
                    const SizedBox(height: AppSpacing.md),
                    _CompactActionsBar(application: application),
                    const SizedBox(height: AppSpacing.md),
                    if (isWide)
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            flex: 2,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: mainColumn,
                            ),
                          ),
                          const SizedBox(width: AppSpacing.md),
                          SizedBox(
                            width: 340,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: sidebarColumn,
                            ),
                          ),
                        ],
                      )
                    else
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [...mainColumn, ...sidebarColumn],
                      ),
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

/// A subtle, one-time fade/slide entrance for the whole page — respects
/// reduced motion via [AppMotion.reduced]. Mirrors the identical pattern
/// already used on Opportunity Details and Create/Edit Opportunity.
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

/// A [DetailGrid] that measures its own real available width via
/// [LayoutBuilder] instead of a caller-guessed literal — this card sits
/// inside a main/sidebar column whose actual width varies with the page's
/// own responsive layout, so a hardcoded `width` would make the two-column
/// decision independently of the real space available (and did, briefly:
/// a fixed literal here caused a genuine narrow-viewport overflow, since
/// [DetailGrid] would then attempt two columns even at 320px wide).
class _ResponsiveDetailGrid extends StatelessWidget {
  const _ResponsiveDetailGrid({
    required this.fields,
    this.twoColumnBreakpoint = 420,
  });

  final List<DetailField> fields;
  final double twoColumnBreakpoint;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => DetailGrid(
        fields: fields,
        width: constraints.maxWidth,
        twoColumnBreakpoint: twoColumnBreakpoint,
      ),
    );
  }
}

/// The candidate identity area — name, avatar fallback, application
/// status, the real opportunity they applied to, and applied date. Major/
/// university appear here too when real (a quick "who is this" summary
/// without needing to scroll to the Applicant card).
class _CandidateHeaderCard extends StatelessWidget {
  const _CandidateHeaderCard({
    required this.application,
    required this.applicantName,
  });

  final ApplicationModel application;
  final String? applicantName;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final applicant = application.applicant;
    final opportunity = application.opportunity;
    final university = cleanDisplayText(applicant?.university);
    final major = cleanDisplayText(applicant?.major);
    final subtitleParts = [
      if (opportunity != null) 'Applying for ${opportunity.title}',
      if (application.appliedAt != null)
        'Applied ${formatDate(application.appliedAt!)}',
    ];

    return AppCard(
      borderColor: AppColors.secondaryLight,
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppAvatar(name: applicantName, size: 56),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        applicantName ?? 'Unnamed applicant',
                        style: textTheme.headlineSmall,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    // Flexible (not a bare child) so a long status label
                    // can shrink via StatusChip's own internal ellipsis
                    // instead of forcing this Row to overflow on a narrow
                    // viewport with an avatar already claiming width.
                    Flexible(
                      child: StatusChip(
                        label:
                            applicationStatusLabels[application.status] ??
                            application.status,
                        type: applicationStatusChipType(application.status),
                      ),
                    ),
                  ],
                ),
                if (subtitleParts.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.xxs),
                  Text(
                    subtitleParts.join(' · '),
                    style: textTheme.bodySmall?.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
                if (university != null || major != null) ...[
                  const SizedBox(height: AppSpacing.xxs),
                  Text(
                    [?major, ?university].join(' · '),
                    style: textTheme.bodySmall?.copyWith(
                      color: AppColors.textMuted,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Mark Reviewed / Shortlist / Reject — exactly the actions valid for the
/// application's current status, per [_actionsFor]. Renders nothing when
/// no Phase 3D action applies (rejected, withdrawn, interview_scheduled,
/// accepted).
///
/// UI Phase O6: a compact [Wrap] of naturally-sized buttons rather than a
/// full-width stacked [Column] — every handler/label/navigation target is
/// unchanged, only the container.
class _CompactActionsBar extends StatefulWidget {
  const _CompactActionsBar({required this.application});

  final ApplicationModel application;

  @override
  State<_CompactActionsBar> createState() => _CompactActionsBarState();
}

class _CompactActionsBarState extends State<_CompactActionsBar> {
  /// Which action is currently in flight, if any — so only the button the
  /// organization actually tapped shows a spinner, while all of them stay
  /// disabled together via `provider.isUpdating`.
  _StatusAction? _pendingAction;

  Future<void> _run(
    OrganizationApplicationsProvider provider,
    _StatusAction action,
    Future<bool> Function() call,
  ) async {
    setState(() => _pendingAction = action);
    final success = await call();
    if (!mounted) return;
    setState(() => _pendingAction = null);

    if (!success && provider.actionErrorMessage != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(provider.actionErrorMessage!)));
    }
  }

  Future<void> _confirmReject(OrganizationApplicationsProvider provider) async {
    final confirmed = await showAppConfirmationDialog(
      context,
      title: 'Reject Application',
      message: 'Reject this application?',
      confirmLabel: 'Reject',
      type: AppConfirmationType.danger,
    );
    if (!confirmed || !mounted) return;

    await _run(
      provider,
      _StatusAction.reject,
      () => provider.reject(widget.application.id),
    );
  }

  /// Opens [CompleteInterviewSheet] for the currently-loaded Interview.
  /// Unlike [_openSendOfferSheet], no explicit
  /// `OrganizationApplicationsProvider` refresh is needed afterward —
  /// completing an interview never changes `Application.status` (it stays
  /// `in_assessment`), only `Assessment`/`Interview` state, which
  /// `OrganizationAssessmentProvider.completeInterview()` already updates
  /// in place and this widget already watches via `context.watch` in
  /// `build()`, so Send Offer becomes visible automatically on the very
  /// next frame.
  Future<void> _openCompleteInterviewSheet(BuildContext context) async {
    final interviewId = context
        .read<OrganizationAssessmentProvider>()
        .latestAssessment
        ?.interview
        ?.id;
    if (interviewId == null) return;

    final completed = await showCompleteInterviewSheet(
      context,
      applicationId: widget.application.id,
      interviewId: interviewId,
    );
    if (!completed || !context.mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Interview completed successfully')),
    );
  }

  /// Opens [SendOfferSheet] and, only on a successful send, refreshes the
  /// real Application from the backend so this screen picks up
  /// `status = offer_sent` — the send response itself carries only the
  /// Offer, never a nested Application (see `OfferRepository`'s own doc
  /// comment), so a targeted refresh is the least-coupled way to stay in
  /// sync, the same bridging pattern `_QuizAssessmentSummaryCard._openEditor`
  /// already uses for Quiz publishing.
  Future<void> _openSendOfferSheet(BuildContext context) async {
    final sent = await showSendOfferSheet(
      context,
      applicationId: widget.application.id,
    );
    if (!sent || !context.mounted) return;

    context.read<OrganizationApplicationsProvider>().loadApplicationDetails(
      widget.application.id,
      forceRefresh: true,
    );
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Offer sent successfully')));
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<OrganizationApplicationsProvider>();
    final assessmentProvider = context.watch<OrganizationAssessmentProvider>();
    final offerProvider = context.watch<OrganizationOfferProvider>();
    final isBusy = provider.isUpdating(widget.application.id);
    final hasAssessment = assessmentProvider.hasAssessmentFor(
      widget.application.id,
    );
    // Phase 10A.3: every action below is gated on the *current* (latest)
    // Assessment, never an arbitrary one from history — a completed Quiz
    // followed by a new Interview correctly stops offering "Advance to
    // Interview" the instant the Interview becomes the latest Assessment,
    // exactly matching `OfferService::assertEligibleForOffer()`'s own
    // latest-Assessment eligibility rule on the backend.
    final assessment = assessmentProvider.latestAssessment;
    final assessmentCompleted =
        hasAssessment && assessment?.status == 'completed';
    final canCompleteInterview =
        hasAssessment &&
        !assessmentCompleted &&
        assessment?.type == 'interview' &&
        assessment?.interview != null;
    final hasOffer = offerProvider.hasOfferFor(widget.application.id);
    // Phase 10A.4A: a completed Quiz's own "Next Step" decision panel
    // (`_QuizAssessmentSummaryCard`) takes over Send Offer/Advance to
    // Interview/Reject entirely until its result is released — see
    // `_actionsFor()`'s own doc comment.
    final quizDecisionPending =
        assessmentCompleted &&
        assessment?.type == 'quiz' &&
        assessment?.resultReleasedAt == null;
    final actions = _actionsFor(
      widget.application.status,
      hasAssessment: hasAssessment,
      canCompleteInterview: canCompleteInterview,
      assessmentCompleted: assessmentCompleted,
      quizDecisionPending: quizDecisionPending,
      hasOffer: hasOffer,
    );

    if (actions.isEmpty) {
      return const SizedBox.shrink();
    }

    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: [
        if (actions.contains(_StatusAction.markReviewed))
          SecondaryButton(
            label: 'Mark Reviewed',
            isLoading: _pendingAction == _StatusAction.markReviewed,
            onPressed: isBusy
                ? null
                : () => _run(
                    provider,
                    _StatusAction.markReviewed,
                    () => provider.markReviewed(widget.application.id),
                  ),
          ),
        if (actions.contains(_StatusAction.shortlist))
          PrimaryButton(
            label: 'Shortlist',
            isLoading: _pendingAction == _StatusAction.shortlist,
            onPressed: isBusy
                ? null
                : () => _run(
                    provider,
                    _StatusAction.shortlist,
                    () => provider.shortlist(widget.application.id),
                  ),
          ),
        if (actions.contains(_StatusAction.chooseAssessment))
          PrimaryButton(
            label: 'Choose Assessment',
            onPressed: () => showChooseAssessmentTypeSheet(
              context,
              applicationId: widget.application.id,
              recruitmentProcess:
                  widget.application.opportunity?.recruitmentProcess ??
                  'none',
            ),
          ),
        if (actions.contains(_StatusAction.completeInterview))
          PrimaryButton(
            label: 'Complete Interview',
            onPressed: () => _openCompleteInterviewSheet(context),
          ),
        if (actions.contains(_StatusAction.sendOffer))
          PrimaryButton(
            label: 'Send Offer',
            onPressed: () => _openSendOfferSheet(context),
          ),
        if (actions.contains(_StatusAction.reject))
          DangerButton(
            label: 'Reject',
            isLoading: _pendingAction == _StatusAction.reject,
            onPressed: isBusy ? null : () => _confirmReject(provider),
          ),
      ],
    );
  }
}

/// Read-only Assessment display for an application that has one, plus the
/// controlled "backend says an assessment is active but no assessment
/// record exists" recovery state. Renders nothing for every other
/// status/assessment combination — in particular, a shortlisted
/// application with no assessment yet shows nothing here; the "Choose
/// Assessment" action in [_CompactActionsBar] is the only affordance for
/// that case, so this section never duplicates it with an empty card.
///
/// **Phase 10A.3**: renders the full Assessment *history*, not just one —
/// a completed Quiz followed by a real "Advance to Interview" Assessment
/// both get their own card, oldest first (matching the backend's own
/// ordering), so the completed Quiz never appears to vanish once a follow-
/// up Interview exists (see docs/BUSINESS_RULES.md section 7a's "Student
/// Application Details" note — the Organization side follows the same
/// principle). Each card branches on its own [AssessmentModel.type] (never
/// on `application.status` alone, which only ever says *an* assessment is
/// active, not which kind, and says nothing about earlier finalized ones)
/// — Interview keeps its existing read-only card; Quiz (Phase 6B-2) gets
/// its own summary card with score/result/release/Manage-Quiz actions
/// (Phase 10A.2/10A.3). A small "Assessment History" label only appears
/// once there's genuinely more than one card to distinguish from a single
/// current Assessment — the common case's visual is otherwise unchanged
/// from before this phase.
class _AssessmentSection extends StatelessWidget {
  const _AssessmentSection({required this.application});

  final ApplicationModel application;

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<OrganizationAssessmentProvider>();
    final applicationId = application.id;
    final isThisOne = provider.loadedApplicationId == applicationId;

    // Only show a loading spinner when there's nothing already loaded for
    // this exact application to keep showing in the meantime — a
    // force-refresh of an already-displayed assessment shouldn't cause it
    // to disappear and flash a spinner in its place.
    if (provider.isLoading &&
        !(isThisOne && provider.assessments.isNotEmpty)) {
      return const AppLoading(compact: true);
    }

    if (isThisOne && provider.assessments.isNotEmpty) {
      final assessments = provider.assessments;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (assessments.length > 1) ...[
            const SectionHeader(title: 'Assessment History'),
            const SizedBox(height: AppSpacing.xs),
          ],
          for (var i = 0; i < assessments.length; i++) ...[
            assessments[i].type == 'quiz'
                ? _QuizAssessmentSummaryCard(
                    assessment: assessments[i],
                    applicationId: applicationId,
                    // Phase 10A.4A: a later Assessment already following
                    // this Quiz that isn't the one it staged itself means
                    // the older, direct "Advance to Interview"/"Send
                    // Offer" flow already acted on it -- never show the
                    // Next Step panel again once that's happened.
                    supersededByUnrelatedFollowUp:
                        i + 1 < assessments.length &&
                        assessments[i + 1].id !=
                            assessments[i].nextActionAssessment?.id,
                  )
                : _AssessmentDetailsCard(assessment: assessments[i]),
            if (assessments[i] != assessments.last)
              const SizedBox(height: AppSpacing.sm),
          ],
        ],
      );
    }

    if (isThisOne && provider.errorMessage != null) {
      return AppErrorView(
        compact: true,
        message: provider.errorMessage!,
        onRetry: () =>
            provider.loadForApplication(applicationId, forceRefresh: true),
      );
    }

    if (application.status == 'in_assessment' ||
        application.status == 'interview_scheduled') {
      // A genuine backend inconsistency (the application says an
      // assessment is active, but no assessment record backs it up) — a
      // controlled warning with retry, deliberately not another creation
      // button, since automatically offering to create a second assessment
      // here would risk exactly the duplicate this phase must prevent.
      final label =
          applicationStatusLabels[application.status] ?? application.status;
      return AppErrorView(
        compact: true,
        icon: Icons.warning_amber_rounded,
        title: 'Assessment Not Found',
        message:
            'This application is marked $label, but no assessment '
            'record could be found.',
        onRetry: () =>
            provider.loadForApplication(applicationId, forceRefresh: true),
      );
    }

    return const SizedBox.shrink();
  }
}

/// Quiz-type Assessment summary — the shared Assessment-level fields plus a
/// compact Quiz summary (title/status/question count) and a single Manage
/// Quiz (draft) / View Quiz (published) action that opens
/// [OrganizationQuizEditorScreen]. On return, force-refreshes the
/// Assessment so a status/quiz change made in the editor (e.g. publishing)
/// is reflected immediately — `OrganizationQuizProvider` and
/// `OrganizationAssessmentProvider` are deliberately separate providers
/// (see `OrganizationQuizProvider`'s own doc comment), so this refresh is
/// how this screen picks up what changed on the other one.
class _QuizAssessmentSummaryCard extends StatefulWidget {
  const _QuizAssessmentSummaryCard({
    required this.assessment,
    required this.applicationId,
    required this.supersededByUnrelatedFollowUp,
  });

  final AssessmentModel assessment;
  final int applicationId;

  /// True when a *different*, real Assessment already follows this Quiz in
  /// history that isn't the one [AssessmentModel.nextActionAssessment]
  /// itself staged — i.e. the pre-10A.4A direct "Advance to Interview"/
  /// "Send Offer" flow already acted on this Quiz. The Next Step panel must
  /// never reappear in that case, even if this Quiz's own [nextAction]
  /// fields are still null (they always are for that older flow).
  final bool supersededByUnrelatedFollowUp;

  @override
  State<_QuizAssessmentSummaryCard> createState() =>
      _QuizAssessmentSummaryCardState();
}

const _nextActionLabels = {
  'interview': 'Interview',
  'offer': 'Offer',
  'reject': 'Reject',
};

class _QuizAssessmentSummaryCardState
    extends State<_QuizAssessmentSummaryCard> {
  Future<void> _openEditor(BuildContext context) async {
    await context.push(AppRoutes.organizationQuizEditor(widget.assessment.id));
    if (!context.mounted) return;
    context.read<OrganizationAssessmentProvider>().loadForApplication(
      widget.applicationId,
      forceRefresh: true,
    );
  }

  /// Manually releases the real, already-graded Quiz result — and, as of
  /// Phase 10A.4A, the Organization's real next-step decision — to the
  /// candidate. Only ever offered when [AssessmentModel.resultReleasedAt]
  /// is still `null`, i.e. the candidate genuinely hasn't seen it yet. The
  /// backend rejects this with a clear message if no decision is ready
  /// yet (never releasable here anyway — see [_openNextStepDecisionPanel] —
  /// but the button only ever appears once [AssessmentModel.nextAction] is
  /// already set, so that rejection should never actually be reachable
  /// through this UI). Releasing sends the Student the one coherent
  /// communication for whichever decision was made — never a separate
  /// generic "quiz result" message.
  Future<void> _confirmRelease(BuildContext context) async {
    final nextAction = widget.assessment.nextAction;
    final actionLabel = _nextActionLabels[nextAction] ?? 'next step';
    final confirmed = await showAppConfirmationDialog(
      context,
      title: 'Release Result',
      message:
          "Release this candidate's real quiz result and $actionLabel "
          'decision now? They\'ll be notified immediately by email and '
          'in-app notification.',
      confirmLabel: 'Release',
    );
    if (!confirmed || !context.mounted) return;

    final provider = context.read<OrganizationAssessmentProvider>();
    final success = await provider.releaseQuizResult(
      applicationId: widget.applicationId,
      assessmentId: widget.assessment.id,
    );
    if (!context.mounted) return;

    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Result released to the candidate')),
      );
    } else if (provider.actionErrorMessage != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(provider.actionErrorMessage!)));
    }
  }

  /// Opens the real Schedule Interview screen in "next-action" mode
  /// (Phase 10A.4A) — see `ScheduleInterviewScreen.nextActionOriginAssessmentId`.
  Future<void> _openAdvanceToInterview(BuildContext context) async {
    await context.push(
      AppRoutes.organizationScheduleInterview(widget.applicationId),
      extra: widget.assessment.id,
    );
  }

  Future<void> _openProceedToOffer(BuildContext context) async {
    await showSendOfferSheet(
      context,
      applicationId: widget.applicationId,
      nextActionOriginAssessmentId: widget.assessment.id,
    );
  }

  Future<void> _confirmRejectDecision(BuildContext context) async {
    final confirmed = await showAppConfirmationDialog(
      context,
      title: 'Reject',
      message:
          'Prepare a rejection as the next step for this candidate? They '
          "are not notified yet — the rejection only takes effect once "
          "this assessment's result is released.",
      confirmLabel: 'Prepare Rejection',
      type: AppConfirmationType.danger,
    );
    if (!confirmed || !context.mounted) return;

    final provider = context.read<OrganizationAssessmentProvider>();
    final success = await provider.setNextActionReject(
      applicationId: widget.applicationId,
      assessmentId: widget.assessment.id,
    );
    if (!context.mounted) return;

    if (!success && provider.actionErrorMessage != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(provider.actionErrorMessage!)));
    }
  }

  /// The Phase 10A.4A "Next Step" panel — only ever rendered for a
  /// completed, still-unreleased Quiz Assessment (see [build]). Shows
  /// "Decision Required" with the three real actions when no decision has
  /// been made yet, or the selected decision's own readiness/release-
  /// timing state once one has.
  Widget _buildNextStepSection(BuildContext context) {
    final assessment = widget.assessment;
    final quiz = assessment.quiz;
    final nextAction = assessment.nextAction;
    final isSettingNextAction = context
        .select<OrganizationAssessmentProvider, bool>(
          (provider) => provider.isSettingNextAction(assessment.id),
        );
    final isReleasing = context.select<OrganizationAssessmentProvider, bool>(
      (provider) => provider.isReleasingResult(assessment.id),
    );
    final isBusy = isSettingNextAction || isReleasing;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: AppSpacing.sm),
        const Divider(),
        const SizedBox(height: AppSpacing.sm),
        const SectionHeader(title: 'Next Step'),
        const SizedBox(height: AppSpacing.xs),
        if (nextAction == null) ...[
          const StatusChip(
            label: 'Decision Required',
            type: AppStatusType.warning,
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'The candidate is waiting — choose what happens next.',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: AppColors.textSecondary),
          ),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              PrimaryButton(
                label: 'Advance to Interview',
                isLoading: isSettingNextAction,
                onPressed: isBusy
                    ? null
                    : () => _openAdvanceToInterview(context),
              ),
              SecondaryButton(
                label: 'Proceed to Offer',
                onPressed: isBusy ? null : () => _openProceedToOffer(context),
              ),
              DangerButton(
                label: 'Reject',
                isLoading: isSettingNextAction,
                onPressed: isBusy
                    ? null
                    : () => _confirmRejectDecision(context),
              ),
            ],
          ),
        ] else ...[
          _ResponsiveDetailGrid(
            twoColumnBreakpoint: 420,
            fields: [
              DetailField(
                'Next Step',
                _nextActionLabels[nextAction] ?? nextAction,
              ),
              if (nextAction == 'interview' &&
                  assessment.nextActionAssessment?.interview != null)
                DetailField(
                  'Interview Scheduled',
                  formatDate(
                    assessment.nextActionAssessment!.interview!.scheduledAt ??
                        DateTime.now(),
                  ),
                ),
              DetailField('Result Release', _releaseTimingLabel(quiz)),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          PrimaryButton(
            label: 'Release Result',
            isLoading: isReleasing,
            onPressed: isBusy ? null : () => _confirmRelease(context),
          ),
        ],
      ],
    );
  }

  String _releaseTimingLabel(QuizModel? quiz) {
    switch (quiz?.resultReleaseMode) {
      case 'scheduled':
        final releaseAt = quiz?.resultReleaseAt;
        if (releaseAt == null) return 'Scheduled';
        return releaseAt.isAfter(DateTime.now())
            ? 'Scheduled for ${formatDate(releaseAt)}'
            : 'Scheduled time passed — release when ready';
      case 'immediate':
        return 'Releases as soon as ready';
      case 'manual':
      default:
        return 'Manual — release when ready';
    }
  }

  @override
  Widget build(BuildContext context) {
    final assessment = widget.assessment;
    final quiz = assessment.quiz;
    final isDraft = quiz?.status == 'draft';
    final attempt = quiz != null && quiz.attempts.isNotEmpty
        ? quiz.attempts.first
        : null;
    // Phase 10A.4A: the decision-and-release panel only ever applies to a
    // completed, still-unreleased Quiz — once released, the real next
    // step has already happened (a new Interview Assessment, a real
    // Offer, or the Application being rejected), so nothing further is
    // shown here.
    final showNextStepSection =
        assessment.status == 'completed' &&
        assessment.resultReleasedAt == null &&
        !widget.supersededByUnrelatedFollowUp;

    return AppCard(
      borderColor: AppColors.secondaryLight,
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionHeader(
            title: 'Assessment',
            trailing: StatusChip(
              label:
                  assessmentTypeLabels[assessment.type] ?? assessment.type,
              type: AppStatusType.primary,
              compact: true,
            ),
          ),
          _ResponsiveDetailGrid(
            twoColumnBreakpoint: 420,
            fields: [
              DetailField(
                'Status',
                assessmentStatusLabels[assessment.status] ??
                    assessment.status,
              ),
              if (quiz != null) ...[
                DetailField('Quiz Title', quiz.title),
                DetailField(
                  'Quiz Status',
                  quizStatusLabels[quiz.status] ?? quiz.status,
                ),
                // Phase 10A.4B addendum (section 12) — this candidate's
                // own frozen schedule, only ever set for a shared-quiz
                // Assessment.
                if (assessment.quizTimingStatus != null)
                  DetailField(
                    'Candidate Schedule',
                    quizTimingStatusLabels[assessment.quizTimingStatus] ??
                        assessment.quizTimingStatus!,
                  ),
                if (assessment.availableAt != null)
                  DetailField(
                    'Available From',
                    formatDateTime(assessment.availableAt!),
                  ),
                if (assessment.dueAt != null)
                  DetailField(
                    'Submission Deadline',
                    formatDateTime(assessment.dueAt!),
                  ),
                DetailField('Questions', '${quiz.questions.length}'),
              ],
            ],
          ),
          if (quiz != null) ...[
            if (attempt?.score != null) ...[
              const SizedBox(height: AppSpacing.sm),
              const Divider(),
              const SizedBox(height: AppSpacing.sm),
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Text(
                    '${attempt!.score}',
                    style: Theme.of(context).textTheme.displaySmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: assessment.result == 'passed'
                          ? AppColors.success
                          : assessment.result == 'failed'
                          ? AppColors.error
                          : AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  if (assessment.result != null)
                    Flexible(
                      child: StatusChip(
                        label:
                            assessmentResultLabels[assessment.result] ??
                            assessment.result!,
                        type: assessment.result == 'passed'
                            ? AppStatusType.success
                            : AppStatusType.error,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              _ResponsiveDetailGrid(
                twoColumnBreakpoint: 420,
                fields: [
                  DetailField('Passing Score', '${quiz.passingScore}'),
                  DetailField(
                    'Result Released to Candidate',
                    assessment.resultReleasedAt != null
                        ? 'Yes, on ${formatDate(assessment.resultReleasedAt!)}'
                        : 'Not yet',
                  ),
                ],
              ),
            ],
            const SizedBox(height: AppSpacing.sm),
            SecondaryButton(
              label: isDraft ? 'Manage Quiz' : 'View Quiz',
              onPressed: () => _openEditor(context),
            ),
            if (showNextStepSection) _buildNextStepSection(context),
          ],
        ],
      ),
    );
  }
}

/// The read-only fields of an existing [AssessmentModel] — Interview
/// detail is shown only when [AssessmentModel.interview] is present
/// (always true for `type == 'interview'` once created, per this phase's
/// backend contract).
class _AssessmentDetailsCard extends StatelessWidget {
  const _AssessmentDetailsCard({required this.assessment});

  final AssessmentModel assessment;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final interview = assessment.interview;
    final notes = cleanDisplayText(interview?.notes);
    final interviewerName = cleanDisplayText(interview?.interviewerName);
    final interviewerEmail = cleanDisplayText(interview?.interviewerEmail);
    final isOnline = interview?.interviewType == 'online';
    final meetingLink = isOnline
        ? cleanDisplayText(interview?.meetingLink)
        : null;
    final validMeetingUri = meetingLink != null
        ? validHttpUri(meetingLink)
        : null;

    final infoTiles = <Widget>[
      if (interview?.scheduledAt != null) ...[
        AssessmentInfoTile(
          icon: Icons.calendar_today_outlined,
          label: 'Date',
          value: formatDate(interview!.scheduledAt!),
        ),
        AssessmentInfoTile(
          icon: Icons.access_time_rounded,
          label: 'Time',
          value: formatTime(interview.scheduledAt!),
        ),
      ],
      if (interview?.durationMinutes != null)
        AssessmentInfoTile(
          icon: Icons.timer_outlined,
          label: 'Duration',
          value: '${interview!.durationMinutes} minutes',
        ),
    ];

    return AppCard(
      borderColor: AppColors.secondaryLight,
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionHeader(
            title: 'Assessment',
            trailing: StatusChip(
              label:
                  assessmentTypeLabels[assessment.type] ?? assessment.type,
              type: AppStatusType.primary,
              compact: true,
            ),
          ),
          _ResponsiveDetailGrid(
            twoColumnBreakpoint: 420,
            fields: [
              DetailField(
                'Status',
                assessmentStatusLabels[assessment.status] ??
                    assessment.status,
              ),
              if (assessment.result != null)
                DetailField(
                  'Result',
                  assessmentResultLabels[assessment.result] ??
                      assessment.result!,
                ),
              if (interview != null)
                DetailField(
                  'Interview Type',
                  interviewTypeLabels[interview.interviewType] ??
                      interview.interviewType,
                ),
            ],
          ),
          if (interview != null) ...[
            if (infoTiles.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.sm),
              AssessmentTileGrid(tiles: infoTiles),
            ],
            const SizedBox(height: AppSpacing.sm),
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
            if (interviewerName != null || interviewerEmail != null) ...[
              const SizedBox(height: AppSpacing.sm),
              _ResponsiveDetailGrid(
                twoColumnBreakpoint: 420,
                fields: [
                  if (interviewerName != null)
                    DetailField('Interviewer Name', interviewerName),
                  if (interviewerEmail != null)
                    DetailField('Interviewer Email', interviewerEmail),
                ],
              ),
            ],
            if (interview.decision != null) ...[
              const SizedBox(height: AppSpacing.sm),
              _ResponsiveDetailGrid(
                twoColumnBreakpoint: 420,
                fields: [
                  DetailField(
                    'Interview Status',
                    interviewStatusLabels[interview.status] ??
                        interview.status,
                  ),
                  DetailField(
                    'Decision',
                    interviewDecisionLabels[interview.decision] ??
                        interview.decision!,
                  ),
                ],
              ),
            ] else
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.sm),
                child: _ResponsiveDetailGrid(
                  twoColumnBreakpoint: 420,
                  fields: [
                    DetailField(
                      'Interview Status',
                      interviewStatusLabels[interview.status] ??
                          interview.status,
                    ),
                  ],
                ),
              ),
            if (notes != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(notes, style: textTheme.bodyMedium),
            ],
          ],
        ],
      ),
    );
  }
}

/// Read-only Offer display for an application, plus the controlled
/// "backend says an Offer was sent but no Offer record exists" recovery
/// state — the same posture `_AssessmentSection` already takes for its own
/// analogous inconsistency. Renders nothing for every other status/Offer
/// combination.
///
/// The actual Offer, once loaded, is always shown as-is regardless of
/// `application.status` — a stale/lagging Application status must never
/// hide real Offer data the organization already has (see
/// `OrganizationOfferProvider`'s own doc comment on why this section never
/// infers an Offer's existence from `application.status` alone).
class _OfferSection extends StatelessWidget {
  const _OfferSection({required this.application});

  final ApplicationModel application;

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<OrganizationOfferProvider>();
    final applicationId = application.id;
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
        child: _OfferSummaryCard(offer: provider.offer!),
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

    if (application.status == 'offer_sent') {
      // A genuine backend inconsistency (the application says an Offer was
      // sent, but no Offer record backs it up) — a controlled warning with
      // retry, never a fake/fabricated Offer card.
      return Padding(
        padding: const EdgeInsets.only(top: AppSpacing.md),
        child: AppErrorView(
          compact: true,
          icon: Icons.warning_amber_rounded,
          title: 'Offer Not Found',
          message:
              'This application is marked Offer Sent, but no offer '
              'record could be found.',
          onRetry: () =>
              provider.loadForApplication(applicationId, forceRefresh: true),
        ),
      );
    }

    return const SizedBox.shrink();
  }
}

/// The read-only fields of an existing [OfferModel]. No organization
/// action appears here in v1 for any [OfferModel.status] — sent, accepted,
/// or declined are all equally read-only; there is no edit/cancel/resend.
class _OfferSummaryCard extends StatelessWidget {
  const _OfferSummaryCard({required this.offer});

  final OfferModel offer;

  @override
  Widget build(BuildContext context) {
    final title = cleanDisplayText(offer.title);
    final message = cleanDisplayText(offer.message);
    final salary = formatSalary(
      amount: offer.salaryAmount,
      currency: offer.salaryCurrency,
      period: offer.salaryPeriod,
    );

    return AppCard(
      borderColor: AppColors.secondaryLight,
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionHeader(
            title: 'Offer',
            trailing: StatusChip(
              label: offerStatusLabels[offer.status] ?? offer.status,
              type: offerStatusChipType(offer.status),
            ),
          ),
          _ResponsiveDetailGrid(
            twoColumnBreakpoint: 420,
            fields: [
              if (title != null) DetailField('Title', title),
              if (salary != null) DetailField('Salary', salary),
              if (offer.startDate != null)
                DetailField('Start Date', formatDate(offer.startDate!)),
              if (offer.sentAt != null)
                DetailField('Sent At', formatDate(offer.sentAt!)),
              if (offer.respondedAt != null)
                DetailField('Responded At', formatDate(offer.respondedAt!)),
            ],
          ),
          if (message != null) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(message, style: Theme.of(context).textTheme.bodyMedium),
          ],
        ],
      ),
    );
  }
}

/// Match analysis (Phase 8A-3) — a compact, deterministic breakdown card
/// plus the Recalculate action. Always rendered (never omitted based on
/// application status the way `_AssessmentSection`/`_OfferSection` are),
/// since Recalculate must stay reachable "regardless of whether a score
/// already exists" for any application this organization owns.
///
/// Loading is entirely independent of the rest of the page — mirrors
/// `_AssessmentSection`/`_OfferSection`'s own section-level
/// loading/error/empty states, never blocking the surrounding
/// Application/Assessment/Offer content.
class _MatchAnalysisSection extends StatelessWidget {
  const _MatchAnalysisSection({required this.applicationId});

  final int applicationId;

  Future<void> _recalculate(BuildContext context) async {
    final provider = context.read<OrganizationMatchAnalysisProvider>();
    final success = await provider.recalculate(applicationId);
    if (!context.mounted) return;

    if (success) {
      // The analysis provider never carries a full ApplicationModel (see
      // its own doc comment) -- a targeted, force-refreshed details fetch
      // is the safest way to pick up the newly-persisted match_score
      // without fabricating one, the same bridging pattern
      // _CompactActionsBar._openSendOfferSheet already uses for Offer.
      context.read<OrganizationApplicationsProvider>().loadApplicationDetails(
        applicationId,
        forceRefresh: true,
      );
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Match recalculated')));
    } else if (provider.actionErrorMessage != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(provider.actionErrorMessage!)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<OrganizationMatchAnalysisProvider>();
    final isThisOne = provider.loadedApplicationId == applicationId;
    final textTheme = Theme.of(context).textTheme;
    final isError =
        isThisOne &&
        provider.errorMessage != null &&
        !(provider.isLoading || provider.analysis != null);

    Widget body;
    if (provider.isLoading && !(isThisOne && provider.analysis != null)) {
      body = const Padding(
        padding: EdgeInsets.symmetric(vertical: AppSpacing.sm),
        child: AppLoading(compact: true),
      );
    } else if (isThisOne && provider.analysis != null) {
      body = _MatchAnalysisBreakdown(analysis: provider.analysis!);
    } else if (isError) {
      // Deliberately not the full AppErrorView here (icon + title +
      // message + retry) — UI Phase O6: that made this card's error state
      // "much too tall". A compact one-line message + inline retry button
      // says the same thing without the icon/padding overhead; the
      // Recalculate action below still covers "generate a fresh one".
      body = Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
        child: Row(
          children: [
            Expanded(
              child: Text(
                provider.errorMessage!,
                style: textTheme.bodyMedium?.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            SecondaryButton(
              label: 'Try Again',
              height: 36,
              onPressed: () => context
                  .read<OrganizationMatchAnalysisProvider>()
                  .loadForApplication(applicationId, forceRefresh: true),
            ),
          ],
        ),
      );
    } else {
      // Genuinely never calculated yet (backend 404) -- a lightweight,
      // non-error empty state; Recalculate below is how the organization
      // generates a real one.
      body = Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
        child: Text(
          'Match not calculated yet.',
          style: textTheme.bodyMedium?.copyWith(color: AppColors.textSecondary),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.md),
      child: AppCard(
        borderColor: AppColors.secondaryLight,
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SectionHeader(title: 'Match Analysis'),
            body,
            const SizedBox(height: AppSpacing.sm),
            SecondaryButton(
              label: 'Recalculate Match',
              isLoading: provider.isRecalculating,
              onPressed: provider.isRecalculating
                  ? null
                  : () => _recalculate(context),
            ),
          ],
        ),
      ),
    );
  }
}

/// The read-only breakdown of an existing [MatchAnalysisModel] — Overall
/// Match plus the three v1.1 factors (Skills, Field/Major, Experience;
/// deliberately no Education/Location/Work Mode row, matching the
/// backend's actual formula). Strengths, weaknesses, and recommendation
/// are shown only when the backend actually returned something meaningful
/// for them. No charts — plain compact rows, per this phase's own scope.
class _MatchAnalysisBreakdown extends StatelessWidget {
  const _MatchAnalysisBreakdown({required this.analysis});

  final MatchAnalysisModel analysis;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final recommendation = cleanDisplayText(analysis.recommendation);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Text(
                'Overall Match',
                style: textTheme.bodyMedium?.copyWith(
                  color: AppColors.textSecondary,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Text(
              formatMatchScore(analysis.overallMatchScore),
              style: textTheme.displaySmall?.copyWith(
                fontWeight: FontWeight.bold,
                color: AppColors.primary,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        _ResponsiveDetailGrid(
          twoColumnBreakpoint: 380,
          fields: [
            DetailField(
              matchFactorLabels['skills']!,
              formatMatchScore(analysis.skillsMatchScore),
            ),
            DetailField(
              matchFactorLabels['major']!,
              formatMatchScore(analysis.majorMatchScore),
            ),
            DetailField(
              matchFactorLabels['location']!,
              formatMatchScore(analysis.locationMatchScore),
            ),
          ],
        ),
        if (analysis.strengths.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.xs),
          Text('Strengths', style: textTheme.labelLarge),
          const SizedBox(height: AppSpacing.xxs),
          for (final strength in analysis.strengths)
            Text('• $strength', style: textTheme.bodySmall),
        ],
        if (analysis.weaknesses.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.xs),
          Text('Weaknesses', style: textTheme.labelLarge),
          const SizedBox(height: AppSpacing.xxs),
          for (final weakness in analysis.weaknesses)
            Text('• $weakness', style: textTheme.bodySmall),
        ],
        if (recommendation != null) ...[
          const SizedBox(height: AppSpacing.xs),
          Text(
            recommendation,
            style: textTheme.bodyMedium?.copyWith(fontStyle: FontStyle.italic),
          ),
        ],
      ],
    );
  }
}

/// Candidate contact/academic details — real fields only, a two-column
/// grid on wide layouts (UI Phase O6) instead of the old single-column
/// label/far-right-value rows.
class _ApplicantCard extends StatelessWidget {
  const _ApplicantCard({required this.applicant, required this.bio});

  final dynamic applicant;
  final String? bio;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return AppCard(
      borderColor: AppColors.secondaryLight,
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SectionHeader(title: 'Applicant'),
          _ResponsiveDetailGrid(
            twoColumnBreakpoint: 420,
            fields: [
              DetailField(
                'Email',
                cleanDisplayText(applicant?.email) ?? 'Not specified',
              ),
              DetailField(
                'Phone',
                cleanDisplayText(applicant?.phone) ?? 'Not specified',
              ),
              DetailField(
                'University',
                cleanDisplayText(applicant?.university) ?? 'Not specified',
              ),
              DetailField(
                'Major',
                cleanDisplayText(applicant?.major) ?? 'Not specified',
              ),
              DetailField(
                'Graduation Year',
                applicant?.graduationYear?.toString() ?? 'Not specified',
              ),
              DetailField(
                'Education Verification',
                educationVerificationStatusLabel(
                  applicant?.educationVerificationStatus,
                ),
              ),
            ],
          ),
          if (bio != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(bio!, style: textTheme.bodyMedium),
          ],
        ],
      ),
    );
  }
}

/// Real skill chips only, CV-supported vs. Self-declared kept
/// distinguishable exactly as before — a tighter [Wrap], never a tall
/// list.
class _SkillsCard extends StatelessWidget {
  const _SkillsCard({required this.applicant});

  final dynamic applicant;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      borderColor: AppColors.secondaryLight,
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SectionHeader(title: 'Skills'),
          const SizedBox(height: AppSpacing.xs),
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xxs,
            children: [
              for (final skill in applicant.skills)
                StatusChip(
                  label: '${skill.skillName} · ${skill.evidenceLabel}',
                  type: skill.isCvSupported
                      ? AppStatusType.info
                      : AppStatusType.neutral,
                  compact: true,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CoverLetterCard extends StatelessWidget {
  const _CoverLetterCard({required this.coverLetter});

  final String coverLetter;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      borderColor: AppColors.secondaryLight,
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SectionHeader(title: 'Cover Letter'),
          Text(coverLetter, style: Theme.of(context).textTheme.bodyMedium),
        ],
      ),
    );
  }
}

/// Sidebar summary — real Applied/Reviewed/Match Score/current status
/// only, a quick-glance complement to the header (which already shows
/// status prominently), not a duplicate of it.
class _ApplicationSummaryCard extends StatelessWidget {
  const _ApplicationSummaryCard({required this.application});

  final ApplicationModel application;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      borderColor: AppColors.secondaryLight,
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SectionHeader(title: 'Application'),
          _ResponsiveDetailGrid(
            twoColumnBreakpoint: 320,
            fields: [
              DetailField(
                'Applied',
                application.appliedAt != null
                    ? formatDate(application.appliedAt!)
                    : 'Not specified',
              ),
              if (application.reviewedAt != null)
                DetailField('Reviewed', formatDate(application.reviewedAt!)),
              if (application.matchScore != null)
                DetailField(
                  'Match Score',
                  '${application.matchScore!.toStringAsFixed(0)}%',
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// A compact CV summary card — real title/version/flags only, the
/// unchanged real "View CV" download action.
class _CvCard extends StatelessWidget {
  const _CvCard({
    required this.cv,
    required this.isDownloading,
    required this.onView,
  });

  final dynamic cv;
  final bool isDownloading;
  final VoidCallback onView;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      borderColor: AppColors.secondaryLight,
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SectionHeader(title: 'CV'),
          Text(cv.title as String, style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: AppSpacing.xs),
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xxs,
            children: [
              const StatusChip(label: 'PDF', compact: true),
              StatusChip(label: 'Version ${cv.version}', compact: true),
              if (cv.isDefault as bool)
                const StatusChip(
                  label: 'Default',
                  type: AppStatusType.success,
                  compact: true,
                ),
              if (cv.createdByAi as bool)
                const StatusChip(
                  label: 'AI Generated',
                  type: AppStatusType.info,
                  compact: true,
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          SecondaryButton(
            label: 'View CV',
            isLoading: isDownloading,
            onPressed: isDownloading ? null : onView,
          ),
        ],
      ),
    );
  }
}

/// A compact, entirely-tappable Opportunity summary card — the real
/// "View Opportunity" action for this phase, as a whole-card tap
/// (`AppCard(interactive: true, onTap: ...)`) rather than a second button,
/// so it never adds another `OutlinedButton` next to the always-present
/// View CV/Recalculate Match actions.
class _OpportunityCard extends StatelessWidget {
  const _OpportunityCard({required this.opportunity});

  final dynamic opportunity;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final recruitmentProcess = opportunity.recruitmentProcess as String?;

    return AppCard(
      borderColor: AppColors.secondaryLight,
      padding: const EdgeInsets.all(AppSpacing.lg),
      interactive: true,
      onTap: () => context.push(
        AppRoutes.organizationOpportunityDetails(opportunity.id as int),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Expanded(child: SectionHeader(title: 'Opportunity')),
              Icon(
                Icons.chevron_right_rounded,
                color: AppColors.textMuted,
              ),
            ],
          ),
          Text(opportunity.title as String, style: textTheme.titleSmall),
          const SizedBox(height: AppSpacing.xxs),
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xxs,
            children: [
              StatusChip(
                label:
                    opportunityTypeLabels[opportunity.opportunityType
                        as String] ??
                    opportunity.opportunityType as String,
                compact: true,
              ),
              if (recruitmentProcess != null && recruitmentProcess != 'none')
                StatusChip(
                  label:
                      recruitmentProcessLabels[recruitmentProcess] ??
                      recruitmentProcess,
                  type: AppStatusType.primary,
                  compact: true,
                ),
            ],
          ),
        ],
      ),
    );
  }
}
