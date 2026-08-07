import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/date_formatter.dart';
import '../../../core/widgets/app_widgets.dart';
import '../../../models/application_model.dart';
import '../../../models/assessment_model.dart';
import '../../../providers/organization_applications_provider.dart';
import '../../../providers/organization_assessment_provider.dart';
import '../../assessments/presentation/assessment_display.dart';
import '../../assessments/presentation/choose_assessment_type_sheet.dart';
import '../../opportunities/presentation/opportunity_display.dart';
import 'application_display.dart';

/// The status actions available for a given application status/assessment
/// combination. `chooseAssessment` (Phase 4B-1) only ever appears for
/// `shortlisted` applications that don't already have an assessment —
/// `interview_scheduled`/`accepted` remain read-only for status actions
/// (a read-only Assessment section covers `interview_scheduled` instead),
/// and `rejected`/`withdrawn` expose no forward actions.
enum _StatusAction { markReviewed, shortlist, reject, chooseAssessment }

List<_StatusAction> _actionsFor(String status, {required bool hasAssessment}) {
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
    default:
      // rejected, withdrawn, interview_scheduled, accepted — no status
      // actions; this phase never downgrades or exposes further controls
      // for any of them. interview_scheduled instead gets a read-only
      // Assessment section (see _AssessmentSection).
      return [];
  }
}

/// Organization-side application details. Reached by ID alone (a route
/// parameter, never GoRouter `extra`), so a direct URL visit or a browser
/// refresh renders correctly instead of crashing.
///
/// No interview/quiz/assessment-selection/offer UI belongs here — this
/// phase covers reviewing an application and moving it through
/// reviewed/shortlisted/rejected only.
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

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<OrganizationApplicationsProvider>();
    final assessmentProvider = context.watch<OrganizationAssessmentProvider>();
    final isBusy = provider.isUpdating(widget.application.id);
    final hasAssessment = assessmentProvider.hasAssessmentFor(
      widget.application.id,
    );
    final actions = _actionsFor(
      widget.application.status,
      hasAssessment: hasAssessment,
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
/// controlled "backend says interview_scheduled but no assessment record
/// exists" recovery state. Renders nothing for every other
/// status/assessment combination — in particular, a shortlisted
/// application with no assessment yet shows nothing here; the "Choose
/// Assessment" action in [_StatusActionsSection] is the only affordance
/// for that case, so this section never duplicates it with an empty card.
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
      return Padding(
        padding: const EdgeInsets.only(top: AppSpacing.md),
        child: _AssessmentDetailsCard(assessment: provider.assessment!),
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

    if (application.status == 'interview_scheduled') {
      // A genuine backend inconsistency (the application says an
      // interview was scheduled, but no assessment record backs it up) —
      // a controlled warning with retry, deliberately not another
      // creation button, since automatically offering to create a second
      // assessment here would risk exactly the duplicate this phase must
      // prevent.
      return Padding(
        padding: const EdgeInsets.only(top: AppSpacing.md),
        child: AppErrorView(
          compact: true,
          icon: Icons.warning_amber_rounded,
          title: 'Assessment Not Found',
          message:
              'This application is marked Interview Scheduled, but no '
              'assessment record could be found.',
          onRetry: () =>
              provider.loadForApplication(applicationId, forceRefresh: true),
        ),
      );
    }

    return const SizedBox.shrink();
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
            OpportunityDetailRow(
              label: 'Decision',
              value:
                  interviewDecisionLabels[interview.decision] ??
                  interview.decision,
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
