import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/date_formatter.dart';
import '../../../core/widgets/app_widgets.dart';
import '../../../models/opportunity_model.dart';
import '../../../providers/organization_opportunities_provider.dart';
import '../../../routes/app_routes.dart';
import 'opportunity_display.dart';

/// Organization-side opportunity details. Reached by ID alone (a route
/// parameter, never GoRouter `extra`), so a direct URL visit or a browser
/// refresh renders correctly instead of crashing.
///
/// No applicant list, quiz, or interview controls belong here yet — this
/// phase covers opportunity management only.
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

    return Scaffold(
      appBar: AppBar(
        title: const Text('Opportunity Details'),
        actions: isThisOne && opportunity != null
            ? [
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
                  onPressed: isDeleting
                      ? null
                      : () => _confirmDelete(opportunity),
                  icon: const Icon(Icons.delete_outline),
                  tooltip: 'Delete',
                ),
              ]
            : null,
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

    final textTheme = Theme.of(context).textTheme;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.screenHorizontal),
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
              StatusChip(
                label:
                    opportunityTypeLabels[opportunity.opportunityType] ??
                    opportunity.opportunityType,
                type: AppStatusType.primary,
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
          const SizedBox(height: AppSpacing.lg),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SectionHeader(title: 'Description'),
                Text(opportunity.description, style: textTheme.bodyMedium),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SectionHeader(title: 'Details'),
                _DetailRow(
                  label: 'Location',
                  value: opportunity.location ?? 'Not specified',
                ),
                _DetailRow(
                  label: 'Field of Study',
                  value: opportunity.fieldOfStudy ?? 'Not specified',
                ),
                _DetailRow(
                  label: 'Education Level',
                  value:
                      educationLevelLabels[opportunity.educationLevel] ??
                      'Not specified',
                ),
                _DetailRow(
                  label: 'Salary Range',
                  value: _formatSalaryRange(opportunity),
                ),
                _DetailRow(
                  label: 'Application Deadline',
                  value: opportunity.applicationDeadline != null
                      ? formatDate(opportunity.applicationDeadline!)
                      : 'Not specified',
                ),
                _DetailRow(
                  label: 'Positions Available',
                  value: '${opportunity.positionsAvailable}',
                ),
                if (opportunity.createdAt != null)
                  _DetailRow(
                    label: 'Posted',
                    value: formatDate(opportunity.createdAt!),
                  ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
        ],
      ),
    );
  }

  String _formatSalaryRange(OpportunityModel opportunity) {
    final min = opportunity.salaryMin;
    final max = opportunity.salaryMax;
    if (min == null && max == null) return 'Not specified';
    if (min != null && max != null) {
      return '${min.toStringAsFixed(0)} - ${max.toStringAsFixed(0)}';
    }
    return (min ?? max)!.toStringAsFixed(0);
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String value;

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
              label,
              style: textTheme.bodyMedium?.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }
}
