import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/date_formatter.dart';
import '../../../core/widgets/app_widgets.dart';
import '../../../models/application_model.dart';
import '../../../models/assessment_model.dart';
import '../../../models/interview_model.dart';
import '../../../providers/student_applications_provider.dart';
import '../../../providers/student_assessment_provider.dart';
import '../../assessments/presentation/assessment_display.dart';
import '../../opportunities/presentation/opportunity_display.dart';
import 'application_display.dart';

/// Read-only application details for students. Reached by ID alone (a
/// route parameter, never GoRouter `extra`) — since no single-application
/// GET endpoint exists on the backend, a cached copy from the already-
/// loaded list is used when available, otherwise the full list is loaded
/// once and this ID is resolved from it. No applicant-review/shortlist/
/// offer UI belongs here. A read-only Assessment section (see
/// `_StudentAssessmentSection`) is the one exception — it's the student's
/// own view of an assessment an organization already created, not an
/// action this screen exposes.
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
    extends State<StudentApplicationDetailsScreen> {
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
    });
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<StudentApplicationsProvider>();
    final application = provider.selectedApplication;
    final isThisOne = application?.id == widget.applicationId;

    return Scaffold(
      appBar: AppBar(title: const Text('Application Details')),
      body: SafeArea(child: _buildBody(provider, application, isThisOne)),
    );
  }

  Widget _buildBody(
    StudentApplicationsProvider provider,
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
    final organization = application.opportunity?.organizationProfile;
    final coverLetter = application.coverLetter;

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
                  application.opportunity?.title ?? 'Opportunity',
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
          if (organization != null) ...[
            const SizedBox(height: AppSpacing.xxs),
            Text(
              organization.organizationName,
              style: textTheme.titleSmall?.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.lg),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SectionHeader(title: 'Details'),
                OpportunityDetailRow(label: 'CV', value: application.cv.title),
                OpportunityDetailRow(
                  label: 'Applied',
                  value: application.appliedAt != null
                      ? formatDate(application.appliedAt!)
                      : 'Not specified',
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
          _StudentAssessmentSection(application: application),
          const SizedBox(height: AppSpacing.xl),
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
class _StudentAssessmentSection extends StatelessWidget {
  const _StudentAssessmentSection({required this.application});

  final ApplicationModel application;

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<StudentAssessmentProvider>();

    if (provider.hasAssessmentFor(application.id)) {
      return Padding(
        padding: const EdgeInsets.only(top: AppSpacing.md),
        child: _StudentAssessmentDetailsCard(assessment: provider.assessment!),
      );
    }

    if (application.status != 'interview_scheduled') {
      return const SizedBox.shrink();
    }

    final isLoadingThis =
        provider.isLoading && provider.loadedApplicationId == application.id;
    if (isLoadingThis) {
      return const Padding(
        padding: EdgeInsets.only(top: AppSpacing.md),
        child: AppLoading(compact: true),
      );
    }

    final error = provider.loadedApplicationId == application.id
        ? provider.errorMessage
        : null;

    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.md),
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
/// allowed to see. Branches on [AssessmentModel.type] so a future Quiz type
/// only needs a new branch here, not a redesign of this section.
class _StudentAssessmentDetailsCard extends StatelessWidget {
  const _StudentAssessmentDetailsCard({required this.assessment});

  final AssessmentModel assessment;

  @override
  Widget build(BuildContext context) {
    final result = assessment.result;

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
          if (result != null)
            OpportunityDetailRow(
              label: 'Result',
              value: assessmentResultLabels[result] ?? result,
            ),
          if (assessment.type == 'interview')
            _StudentInterviewDetails(interview: assessment.interview)
          else if (assessment.type == 'quiz')
            const _QuizAssessmentPlaceholder(),
          // Any other/unknown type: the Type/Status/Result rows above are
          // the entire generic summary — nothing more to render, and
          // nothing to crash on.
        ],
      ),
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
    final location = cleanDisplayText(interview.location);
    final interviewerName = cleanDisplayText(interview.interviewerName);
    final notes = cleanDisplayText(interview.notes);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
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
        if (location != null)
          OpportunityDetailRow(label: 'Location', value: location),
        if (interviewerName != null)
          OpportunityDetailRow(
            label: 'Interviewer Name',
            value: interviewerName,
          ),
        OpportunityDetailRow(
          label: 'Interview Status',
          value: interviewStatusLabels[interview.status] ?? interview.status,
        ),
        if (meetingLink != null) ...[
          const SizedBox(height: AppSpacing.xxs),
          _MeetingLinkRow(link: meetingLink),
        ],
        if (notes != null) ...[
          const SizedBox(height: AppSpacing.xs),
          Text(notes, style: Theme.of(context).textTheme.bodyMedium),
        ],
      ],
    );
  }
}

/// A label/value row for the interview meeting link specifically — the
/// value is [SelectableText] (copyable) rather than [OpportunityDetailRow]'s
/// plain [Text], since a link is only useful if the student can copy it.
/// Deliberately does not launch a browser or depend on `url_launcher` — see
/// this phase's own scope notes on meeting-link handling.
class _MeetingLinkRow extends StatelessWidget {
  const _MeetingLinkRow({required this.link});

  final String link;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              'Meeting Link',
              style: textTheme.bodyMedium?.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: SelectableText(
              link,
              textAlign: TextAlign.end,
              style: textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }
}

/// A compact placeholder for `assessment.type == 'quiz'` — Quiz itself is a
/// future phase (no questions/route/submission/score UI exists yet); this
/// only proves the section doesn't crash or misrender for that type.
class _QuizAssessmentPlaceholder extends StatelessWidget {
  const _QuizAssessmentPlaceholder();

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Quiz assessment', style: textTheme.titleSmall),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            'Quiz functionality will be available in a later phase.',
            style: textTheme.bodySmall?.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}
