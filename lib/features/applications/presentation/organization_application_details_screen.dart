import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/date_formatter.dart';
import '../../../core/widgets/app_widgets.dart';
import '../../../models/application_model.dart';
import '../../../providers/organization_applications_provider.dart';
import '../../opportunities/presentation/opportunity_display.dart';
import 'application_display.dart';

/// The three Phase 3D status actions available for a given application
/// status. Deliberately does not include interview/accepted actions —
/// applications already at `interview_scheduled`/`accepted` are read-only
/// in this phase, and `rejected`/`withdrawn` expose no forward actions.
enum _StatusAction { markReviewed, shortlist, reject }

List<_StatusAction> _actionsFor(String status) {
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
      return [_StatusAction.reject];
    default:
      // rejected, withdrawn, interview_scheduled, accepted — no Phase 3D
      // actions; this phase never downgrades or exposes further controls
      // for any of them.
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
    final isBusy = provider.isUpdating(widget.application.id);
    final actions = _actionsFor(widget.application.status);

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
