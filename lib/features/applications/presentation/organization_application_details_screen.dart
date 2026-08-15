import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/date_formatter.dart';
import '../../../core/widgets/app_widgets.dart';
import '../../../models/application_model.dart';
import '../../../models/assessment_model.dart';
import '../../../models/match_analysis_model.dart';
import '../../../models/offer_model.dart';
import '../../../providers/organization_applications_provider.dart';
import '../../../providers/organization_assessment_provider.dart';
import '../../../providers/organization_match_analysis_provider.dart';
import '../../../providers/organization_offer_provider.dart';
import '../../../routes/app_routes.dart';
import '../../assessments/presentation/assessment_display.dart';
import '../../assessments/presentation/choose_assessment_type_sheet.dart';
import '../../offers/presentation/offer_display.dart';
import '../../offers/presentation/send_offer_sheet.dart';
import '../../opportunities/presentation/opportunity_display.dart';
import 'application_display.dart';

/// The status actions available for a given application status/assessment
/// combination. `chooseAssessment` (Phase 4B-1) only ever appears for
/// `shortlisted` applications that don't already have an assessment —
/// `interview_scheduled`/`accepted` remain read-only for status actions
/// (a read-only Assessment section covers `interview_scheduled` instead),
/// and `rejected`/`withdrawn` expose no forward actions.
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
  sendOffer,
}

List<_StatusAction> _actionsFor(
  String status, {
  required bool hasAssessment,
  required bool assessmentCompleted,
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
        if (hasAssessment && assessmentCompleted && !hasOffer)
          _StatusAction.sendOffer,
        // Phase 6C-4: the backend now hard-blocks the generic status
        // endpoint once an Offer exists (see
        // Organization\ApplicationController::updateStatus()), so Reject
        // must never be offered once `hasOffer` is true either — even
        // while `application.status` hasn't yet caught up from
        // `in_assessment` to `offer_sent`. Matches Send Offer's own
        // `!hasOffer` guard just above.
        if (!hasOffer) _StatusAction.reject,
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

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<OrganizationApplicationsProvider>();
    final application = provider.selectedApplication;
    final isThisOne = application?.id == widget.applicationId;

    return Scaffold(
      appBar: AppBar(title: const Text('Application Details')),
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

    final textTheme = Theme.of(context).textTheme;
    final applicant = application.applicant;
    final opportunity = application.opportunity;
    final cv = application.cv;
    final coverLetter = application.coverLetter;
    final applicantName = cleanDisplayText(applicant?.name);
    final applicantBio = cleanDisplayText(applicant?.bio);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.screenHorizontal),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  applicantName ?? 'Unnamed applicant',
                  style: textTheme.headlineSmall,
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              StatusChip(
                label:
                    applicationStatusLabels[application.status] ??
                    application.status,
                type: applicationStatusChipType(application.status),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          _StatusActionsSection(application: application),
          _AssessmentSection(application: application),
          _OfferSection(application: application),
          _MatchAnalysisSection(applicationId: application.id),
          const SizedBox(height: AppSpacing.lg),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SectionHeader(title: 'Applicant'),
                OpportunityDetailRow(
                  label: 'Email',
                  value: cleanDisplayText(applicant?.email) ?? 'Not specified',
                ),
                OpportunityDetailRow(
                  label: 'Phone',
                  value: cleanDisplayText(applicant?.phone) ?? 'Not specified',
                ),
                OpportunityDetailRow(
                  label: 'University',
                  value:
                      cleanDisplayText(applicant?.university) ??
                      'Not specified',
                ),
                OpportunityDetailRow(
                  label: 'Major',
                  value: cleanDisplayText(applicant?.major) ?? 'Not specified',
                ),
                OpportunityDetailRow(
                  label: 'Graduation Year',
                  value:
                      applicant?.graduationYear?.toString() ?? 'Not specified',
                ),
                if (applicantBio != null) ...[
                  const SizedBox(height: AppSpacing.xs),
                  Text(applicantBio, style: textTheme.bodyMedium),
                ],
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SectionHeader(title: 'Application'),
                OpportunityDetailRow(
                  label: 'Applied',
                  value: application.appliedAt != null
                      ? formatDate(application.appliedAt!)
                      : 'Not specified',
                ),
                if (application.reviewedAt != null)
                  OpportunityDetailRow(
                    label: 'Reviewed',
                    value: formatDate(application.reviewedAt!),
                  ),
                if (application.matchScore != null)
                  OpportunityDetailRow(
                    label: 'Match Score',
                    value: '${application.matchScore!.toStringAsFixed(0)}%',
                  ),
              ],
            ),
          ),
          if (coverLetter != null && coverLetter.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SectionHeader(title: 'Cover Letter'),
                  Text(coverLetter, style: textTheme.bodyMedium),
                ],
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SectionHeader(title: 'CV'),
                OpportunityDetailRow(label: 'Title', value: cv.title),
                OpportunityDetailRow(label: 'File Path', value: cv.filePath),
                const SizedBox(height: AppSpacing.xs),
                Wrap(
                  spacing: AppSpacing.xs,
                  runSpacing: AppSpacing.xxs,
                  children: [
                    StatusChip(label: 'Version ${cv.version}', compact: true),
                    if (cv.isDefault)
                      const StatusChip(
                        label: 'Default',
                        type: AppStatusType.success,
                        compact: true,
                      ),
                    if (cv.createdByAi)
                      const StatusChip(
                        label: 'AI Generated',
                        type: AppStatusType.info,
                        compact: true,
                      ),
                  ],
                ),
              ],
            ),
          ),
          if (opportunity != null) ...[
            const SizedBox(height: AppSpacing.md),
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SectionHeader(title: 'Opportunity'),
                  OpportunityDetailRow(
                    label: 'Title',
                    value: opportunity.title,
                  ),
                  OpportunityDetailRow(
                    label: 'Type',
                    value:
                        opportunityTypeLabels[opportunity.opportunityType] ??
                        opportunity.opportunityType,
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.xl),
        ],
      ),
    );
  }
}

/// Mark Reviewed / Shortlist / Reject — exactly the actions valid for the
/// application's current status, per [_actionsFor]. Renders nothing when
/// no Phase 3D action applies (rejected, withdrawn, interview_scheduled,
/// accepted).
class _StatusActionsSection extends StatefulWidget {
  const _StatusActionsSection({required this.application});

  final ApplicationModel application;

  @override
  State<_StatusActionsSection> createState() => _StatusActionsSectionState();
}

class _StatusActionsSectionState extends State<_StatusActionsSection> {
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
    final assessmentCompleted =
        hasAssessment && assessmentProvider.assessment?.status == 'completed';
    final hasOffer = offerProvider.hasOfferFor(widget.application.id);
    final actions = _actionsFor(
      widget.application.status,
      hasAssessment: hasAssessment,
      assessmentCompleted: assessmentCompleted,
      hasOffer: hasOffer,
    );

    if (actions.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (actions.contains(_StatusAction.markReviewed)) ...[
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
          const SizedBox(height: AppSpacing.sm),
        ],
        if (actions.contains(_StatusAction.shortlist)) ...[
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
          const SizedBox(height: AppSpacing.sm),
        ],
        if (actions.contains(_StatusAction.chooseAssessment)) ...[
          PrimaryButton(
            label: 'Choose Assessment',
            onPressed: () => showChooseAssessmentTypeSheet(
              context,
              applicationId: widget.application.id,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
        ],
        if (actions.contains(_StatusAction.sendOffer)) ...[
          PrimaryButton(
            label: 'Send Offer',
            onPressed: () => _openSendOfferSheet(context),
          ),
          const SizedBox(height: AppSpacing.sm),
        ],
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
/// Assessment" action in [_StatusActionsSection] is the only affordance
/// for that case, so this section never duplicates it with an empty card.
///
/// Branches on [AssessmentModel.type] (never on `application.status`
/// alone, which only says an assessment exists, not what kind) — Interview
/// keeps its existing read-only card; Quiz (Phase 6B-2) gets its own
/// summary card with a Manage/View Quiz action.
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
    if (provider.isLoading && !(isThisOne && provider.assessment != null)) {
      return const Padding(
        padding: EdgeInsets.only(top: AppSpacing.md),
        child: AppLoading(compact: true),
      );
    }

    if (isThisOne && provider.assessment != null) {
      final assessment = provider.assessment!;
      return Padding(
        padding: const EdgeInsets.only(top: AppSpacing.md),
        child: assessment.type == 'quiz'
            ? _QuizAssessmentSummaryCard(
                assessment: assessment,
                applicationId: applicationId,
              )
            : _AssessmentDetailsCard(assessment: assessment),
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

    if (application.status == 'in_assessment' ||
        application.status == 'interview_scheduled') {
      // A genuine backend inconsistency (the application says an
      // assessment is active, but no assessment record backs it up) — a
      // controlled warning with retry, deliberately not another creation
      // button, since automatically offering to create a second assessment
      // here would risk exactly the duplicate this phase must prevent.
      final label =
          applicationStatusLabels[application.status] ?? application.status;
      return Padding(
        padding: const EdgeInsets.only(top: AppSpacing.md),
        child: AppErrorView(
          compact: true,
          icon: Icons.warning_amber_rounded,
          title: 'Assessment Not Found',
          message:
              'This application is marked $label, but no assessment '
              'record could be found.',
          onRetry: () =>
              provider.loadForApplication(applicationId, forceRefresh: true),
        ),
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
class _QuizAssessmentSummaryCard extends StatelessWidget {
  const _QuizAssessmentSummaryCard({
    required this.assessment,
    required this.applicationId,
  });

  final AssessmentModel assessment;
  final int applicationId;

  Future<void> _openEditor(BuildContext context) async {
    await context.push(AppRoutes.organizationQuizEditor(assessment.id));
    if (!context.mounted) return;
    context.read<OrganizationAssessmentProvider>().loadForApplication(
      applicationId,
      forceRefresh: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    final quiz = assessment.quiz;
    final isDraft = quiz?.status == 'draft';

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SectionHeader(title: 'Assessment'),
          OpportunityDetailRow(
            label: 'Type',
            value: assessmentTypeLabels[assessment.type] ?? assessment.type,
          ),
          OpportunityDetailRow(
            label: 'Status',
            value:
                assessmentStatusLabels[assessment.status] ?? assessment.status,
          ),
          if (quiz != null) ...[
            const SizedBox(height: AppSpacing.xs),
            OpportunityDetailRow(label: 'Quiz Title', value: quiz.title),
            OpportunityDetailRow(
              label: 'Quiz Status',
              value: quizStatusLabels[quiz.status] ?? quiz.status,
            ),
            OpportunityDetailRow(
              label: 'Questions',
              value: '${quiz.questions.length}',
            ),
            const SizedBox(height: AppSpacing.sm),
            SecondaryButton(
              label: isDraft ? 'Manage Quiz' : 'View Quiz',
              onPressed: () => _openEditor(context),
            ),
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
    final interview = assessment.interview;
    final notes = cleanDisplayText(interview?.notes);

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SectionHeader(title: 'Assessment'),
          OpportunityDetailRow(
            label: 'Type',
            value: assessmentTypeLabels[assessment.type] ?? assessment.type,
          ),
          OpportunityDetailRow(
            label: 'Status',
            value:
                assessmentStatusLabels[assessment.status] ?? assessment.status,
          ),
          if (assessment.result != null)
            OpportunityDetailRow(
              label: 'Result',
              value:
                  assessmentResultLabels[assessment.result] ??
                  assessment.result!,
            ),
          if (interview != null) ...[
            const SizedBox(height: AppSpacing.xs),
            OpportunityDetailRow(
              label: 'Interview Type',
              value:
                  interviewTypeLabels[interview.interviewType] ??
                  interview.interviewType,
            ),
            OpportunityDetailRow(
              label: 'Scheduled Date',
              value: interview.scheduledAt != null
                  ? formatDate(interview.scheduledAt!)
                  : 'Not specified',
            ),
            OpportunityDetailRow(
              label: 'Scheduled Time',
              value: interview.scheduledAt != null
                  ? formatTime(interview.scheduledAt!)
                  : 'Not specified',
            ),
            if (interview.durationMinutes != null)
              OpportunityDetailRow(
                label: 'Duration',
                value: '${interview.durationMinutes} minutes',
              ),
            if (cleanDisplayText(interview.meetingLink) != null)
              OpportunityDetailRow(
                label: 'Meeting Link',
                value: cleanDisplayText(interview.meetingLink)!,
              ),
            if (cleanDisplayText(interview.location) != null)
              OpportunityDetailRow(
                label: 'Location',
                value: cleanDisplayText(interview.location)!,
              ),
            if (cleanDisplayText(interview.interviewerName) != null)
              OpportunityDetailRow(
                label: 'Interviewer Name',
                value: cleanDisplayText(interview.interviewerName)!,
              ),
            if (cleanDisplayText(interview.interviewerEmail) != null)
              OpportunityDetailRow(
                label: 'Interviewer Email',
                value: cleanDisplayText(interview.interviewerEmail)!,
              ),
            OpportunityDetailRow(
              label: 'Interview Status',
              value:
                  interviewStatusLabels[interview.status] ?? interview.status,
            ),
            if (interview.decision != null)
              OpportunityDetailRow(
                label: 'Decision',
                value:
                    interviewDecisionLabels[interview.decision] ??
                    interview.decision!,
              ),
            if (notes != null) ...[
              const SizedBox(height: AppSpacing.xs),
              Text(notes, style: Theme.of(context).textTheme.bodyMedium),
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Expanded(child: SectionHeader(title: 'Offer')),
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
      // _StatusActionsSection._openSendOfferSheet already uses for Offer.
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

    Widget body;
    if (provider.isLoading && !(isThisOne && provider.analysis != null)) {
      body = const Padding(
        padding: EdgeInsets.symmetric(vertical: AppSpacing.sm),
        child: AppLoading(compact: true),
      );
    } else if (isThisOne && provider.analysis != null) {
      body = _MatchAnalysisBreakdown(analysis: provider.analysis!);
    } else if (isThisOne && provider.errorMessage != null) {
      body = AppErrorView(
        compact: true,
        message: provider.errorMessage!,
        onRetry: () => context
            .read<OrganizationMatchAnalysisProvider>()
            .loadForApplication(applicationId, forceRefresh: true),
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
          children: [
            Text(
              'Overall Match',
              style: textTheme.bodyMedium?.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
            const Spacer(),
            Text(
              formatMatchScore(analysis.overallMatchScore),
              style: textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        OpportunityDetailRow(
          label: matchFactorLabels['skills']!,
          value: formatMatchScore(analysis.skillsMatchScore),
        ),
        OpportunityDetailRow(
          label: matchFactorLabels['field']!,
          value: formatMatchScore(analysis.fieldMatchScore),
        ),
        OpportunityDetailRow(
          label: matchFactorLabels['experience']!,
          value: formatMatchScore(analysis.experienceMatchScore),
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
