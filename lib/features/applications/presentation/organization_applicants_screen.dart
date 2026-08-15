import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/date_formatter.dart';
import '../../../core/widgets/app_widgets.dart';
import '../../../models/application_model.dart';
import '../../../providers/organization_applications_provider.dart';
import '../../../routes/app_routes.dart';
import 'application_display.dart';

/// Lists the applicants for one of the organization's own opportunities.
/// No applicant-review actions live here — tapping a card opens
/// [ApplicationModel] details, where Mark Reviewed/Shortlist/Reject
/// actions live, to avoid accidental decisions from a list row.
class OrganizationApplicantsScreen extends StatefulWidget {
  const OrganizationApplicantsScreen({
    super.key,
    required this.opportunityId,
    this.opportunityTitle,
  });

  final int opportunityId;

  /// Optional — only available when reached via in-app navigation (e.g.
  /// from Opportunity Details, via GoRouter `extra`). A direct URL visit
  /// has no `extra` to rely on, so the screen must render correctly
  /// without it; [opportunityId] alone is always sufficient to load data.
  final String? opportunityTitle;

  @override
  State<OrganizationApplicantsScreen> createState() =>
      _OrganizationApplicantsScreenState();
}

class _OrganizationApplicantsScreenState
    extends State<OrganizationApplicantsScreen> {
  @override
  void initState() {
    super.initState();
    // Deferred to the post-frame callback — see
    // StudentOpportunitiesScreen.initState for why calling this directly
    // here would violate Flutter's build-phase constraints.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context
          .read<OrganizationApplicationsProvider>()
          .loadApplicationsForOpportunity(widget.opportunityId);
    });
  }

  /// Opens Application Details and, on return, force-refreshes this list.
  /// Backend ranking depends on the stored `match_score` (Phase 8A-1), and
  /// a Recalculate on the details screen (Phase 8A-3) only updates that
  /// screen's own `selectedApplication` — never this list's `applications`
  /// array — so without this refresh, a changed score/ranking wouldn't be
  /// reflected until some unrelated action reloaded the list. Mirrors
  /// `_QuizAssessmentSummaryCard._openEditor`'s own "await the push, then
  /// force-refresh on return" pattern. The backend remains the sole
  /// ranking authority — this never introduces client-side sorting, just
  /// re-fetches the backend's own order.
  Future<void> _openDetails(int applicationId) async {
    await context.push(AppRoutes.organizationApplicationDetails(applicationId));
    if (!mounted) return;
    context
        .read<OrganizationApplicationsProvider>()
        .loadApplicationsForOpportunity(
          widget.opportunityId,
          forceRefresh: true,
        );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<OrganizationApplicationsProvider>();

    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.opportunityTitle != null
              ? 'Applicants for ${widget.opportunityTitle}'
              : 'Applicants',
        ),
      ),
      body: SafeArea(child: _buildBody(provider)),
    );
  }

  Widget _buildBody(OrganizationApplicationsProvider provider) {
    if (provider.isLoadingList && provider.applications.isEmpty) {
      return const AppSkeletonList();
    }

    if (provider.listErrorMessage != null && provider.applications.isEmpty) {
      return AppErrorView(
        message: provider.listErrorMessage!,
        onRetry: () => provider.loadApplicationsForOpportunity(
          widget.opportunityId,
          forceRefresh: true,
        ),
      );
    }

    if (provider.applications.isEmpty) {
      return const AppEmptyView(
        title: 'No Applicants Yet',
        message: 'Applications submitted to this opportunity will appear here.',
        icon: Icons.people_outline,
      );
    }

    return RefreshIndicator(
      onRefresh: () => provider.loadApplicationsForOpportunity(
        widget.opportunityId,
        forceRefresh: true,
      ),
      child: ListView.separated(
        padding: const EdgeInsets.all(AppSpacing.screenHorizontal),
        itemCount: provider.applications.length,
        separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
        itemBuilder: (context, index) {
          final application = provider.applications[index];
          return _ApplicantCard(
            application: application,
            onTap: () => _openDetails(application.id),
          );
        },
      ),
    );
  }
}

class _ApplicantCard extends StatelessWidget {
  const _ApplicantCard({required this.application, required this.onTap});

  final ApplicationModel application;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final applicant = application.applicant;
    final name = cleanDisplayText(applicant?.name);
    final email = cleanDisplayText(applicant?.email);
    final matchScore = application.matchScore;

    final studyLine = _studyLine(
      cleanDisplayText(applicant?.major),
      cleanDisplayText(applicant?.university),
    );

    return AppCard(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  name ?? 'Unnamed applicant',
                  style: textTheme.titleMedium,
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              StatusChip(
                label:
                    applicationStatusLabels[application.status] ??
                    application.status,
                type: applicationStatusChipType(application.status),
                compact: true,
              ),
            ],
          ),
          if (email != null) ...[
            const SizedBox(height: AppSpacing.xxs),
            Text(
              email,
              style: textTheme.bodyMedium?.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ],
          if (studyLine != null) ...[
            const SizedBox(height: AppSpacing.xxs),
            Text(
              studyLine,
              style: textTheme.bodySmall?.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.xxs),
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xxs,
            children: [
              if (application.appliedAt != null)
                Text(
                  'Applied ${formatDate(application.appliedAt!)}',
                  style: textTheme.bodySmall?.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              if (matchScore != null)
                StatusChip(
                  label: 'Match ${matchScore.toStringAsFixed(0)}%',
                  type: AppStatusType.primary,
                  compact: true,
                ),
            ],
          ),
        ],
      ),
    );
  }

  String? _studyLine(String? major, String? university) {
    if (major != null && university != null) return '$major, $university';
    return major ?? university;
  }
}
