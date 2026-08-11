import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_colors.dart';
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
import '../../offers/presentation/offer_display.dart';
import '../../opportunities/presentation/opportunity_display.dart';
import 'application_display.dart';

/// Read-only application details for students. Reached by ID alone (a
/// route parameter, never GoRouter `extra`) — since no single-application
/// GET endpoint exists on the backend, a cached copy from the already-
/// loaded list is used when available, otherwise the full list is loaded
/// once and this ID is resolved from it. No applicant-review/shortlist UI
/// belongs here. A read-only Assessment section (see
/// `_StudentAssessmentSection`) and the Offer response section (see
/// `_StudentOfferSection`, Phase 6C-3) are the two exceptions — the
/// student's own view of, and one-time response to, records an
/// organization already created, not applicant-review actions this screen
/// exposes.
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
      // Likewise independent — the Offer section has its own
      // section-level loading/error state (see `_StudentOfferSection`).
      context.read<StudentOfferProvider>().loadForApplication(
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
          if (provider.detailsErrorMessage != null) ...[
            const SizedBox(height: AppSpacing.sm),
            AppErrorView(
              compact: true,
              message: provider.detailsErrorMessage!,
              onRetry: () => provider.loadApplicationDetails(
                widget.applicationId,
                forceRefresh: true,
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
          _StudentOfferSection(application: application),
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
        child: _StudentAssessmentDetailsCard(
          assessment: provider.assessment!,
          applicationId: application.id,
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
  const _StudentAssessmentDetailsCard({
    required this.assessment,
    required this.applicationId,
  });

  final AssessmentModel assessment;
  final int applicationId;

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
            _StudentQuizDetails(
              assessment: assessment,
              applicationId: applicationId,
            ),
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: AppSpacing.xs),
        OpportunityDetailRow(label: 'Quiz Title', value: quiz.title),
        OpportunityDetailRow(
          label: 'Passing Score',
          value: '${quiz.passingScore}%',
        ),
        OpportunityDetailRow(
          label: 'Time Limit',
          value: quiz.timeLimitMinutes != null
              ? '${quiz.timeLimitMinutes} minutes'
              : 'No time limit',
        ),
        OpportunityDetailRow(
          label: 'Questions',
          value: '${quiz.questions.length}',
        ),
        const SizedBox(height: AppSpacing.sm),
        PrimaryButton(label: 'Open Quiz', onPressed: () => _openQuiz(context)),
      ],
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
