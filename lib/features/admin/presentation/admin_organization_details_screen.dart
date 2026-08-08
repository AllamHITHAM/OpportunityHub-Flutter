import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/app_widgets.dart';
import '../../../providers/admin_dashboard_provider.dart';
import '../../../providers/admin_organizations_provider.dart';

const _typeLabels = {
  'company': 'Company',
  'university': 'University',
  'ngo': 'NGO',
  'training_center': 'Training Center',
  'government': 'Government',
  'other': 'Other',
};

const _statusLabels = {
  'pending': 'Pending',
  'approved': 'Approved',
  'rejected': 'Rejected',
};

AppStatusType _statusChipType(String status) {
  switch (status) {
    case 'approved':
      return AppStatusType.success;
    case 'rejected':
      return AppStatusType.error;
    case 'pending':
      return AppStatusType.warning;
    default:
      return AppStatusType.neutral;
  }
}

/// Shows one organization's full details and, only while it's still
/// `pending`, lets an admin approve or reject it. Approved/rejected
/// organizations are read-only here — this phase deliberately never exposes
/// a way to move an organization back to another approval state, even
/// though the backend endpoint itself would technically allow it.
class AdminOrganizationDetailsScreen extends StatefulWidget {
  const AdminOrganizationDetailsScreen({
    super.key,
    required this.organizationId,
  });

  final int organizationId;

  @override
  State<AdminOrganizationDetailsScreen> createState() =>
      _AdminOrganizationDetailsScreenState();
}

class _AdminOrganizationDetailsScreenState
    extends State<AdminOrganizationDetailsScreen> {
  // Tracks which specific action is in flight, purely for which button
  // shows its own spinner — `provider.isBusy` (organization-level, not
  // per-action) already disables *both* buttons the instant either one is
  // pressed, but only the pressed one should visibly spin.
  bool _isApproving = false;
  bool _isRejecting = false;

  @override
  void initState() {
    super.initState();
    // Deferred to the post-frame callback — see
    // StudentOpportunitiesScreen.initState for why calling this directly
    // here would violate Flutter's build-phase constraints.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<AdminOrganizationsProvider>().loadDetails(
        widget.organizationId,
      );
    });
  }

  Future<void> _handleApprove(AdminOrganizationsProvider provider) async {
    final confirmed = await showAppConfirmationDialog(
      context,
      title: 'Approve Organization',
      message: 'Are you sure you want to approve this organization?',
      confirmLabel: 'Approve',
      type: AppConfirmationType.success,
    );
    if (!confirmed || !mounted) return;

    setState(() => _isApproving = true);
    final success = await provider.approve(widget.organizationId);
    if (!mounted) return;
    setState(() => _isApproving = false);

    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Organization approved successfully')),
      );
      // Least-coupled way to keep the dashboard's pending/approved counts
      // in sync — triggered from here rather than injecting
      // AdminDashboardProvider into AdminOrganizationsProvider, since
      // returning to AdminHomeScreen via `pop` doesn't re-run its
      // initState (the route stays alive in the stack), so it wouldn't
      // otherwise pick up this change on its own.
      context.read<AdminDashboardProvider>().load(forceRefresh: true);
    } else if (provider.actionErrorMessage != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(provider.actionErrorMessage!)));
    }
  }

  Future<void> _handleReject(AdminOrganizationsProvider provider) async {
    final confirmed = await showAppConfirmationDialog(
      context,
      title: 'Reject Organization',
      message: 'Are you sure you want to reject this organization?',
      confirmLabel: 'Reject',
      type: AppConfirmationType.danger,
    );
    if (!confirmed || !mounted) return;

    setState(() => _isRejecting = true);
    final success = await provider.reject(widget.organizationId);
    if (!mounted) return;
    setState(() => _isRejecting = false);

    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Organization rejected successfully')),
      );
      context.read<AdminDashboardProvider>().load(forceRefresh: true);
    } else if (provider.actionErrorMessage != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(provider.actionErrorMessage!)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AdminOrganizationsProvider>();

    return Scaffold(
      appBar: AppBar(title: const Text('Organization Details')),
      body: SafeArea(child: _buildBody(provider)),
    );
  }

  Widget _buildBody(AdminOrganizationsProvider provider) {
    final organization = provider.selectedOrganization;
    final isForThisOrganization =
        organization != null && organization.id == widget.organizationId;

    if (provider.isLoadingDetails && !isForThisOrganization) {
      return const AppLoading();
    }

    if (provider.detailsErrorMessage != null && !isForThisOrganization) {
      return AppErrorView(
        message: provider.detailsErrorMessage!,
        onRetry: () =>
            provider.loadDetails(widget.organizationId, forceRefresh: true),
      );
    }

    if (!isForThisOrganization) {
      // Neither loading, nor an error, nor a matching organization — the
      // load hasn't been kicked off yet (e.g. the very first frame, before
      // the post-frame callback runs). Rendering the same loading state
      // here (rather than an empty screen) keeps this branch from ever
      // being a visible flash of nothing.
      return const AppLoading();
    }

    final textTheme = Theme.of(context).textTheme;
    final isBusy = provider.isBusy(organization.id);
    final isPending = organization.approvalStatus == 'pending';

    return RefreshIndicator(
      onRefresh: () =>
          provider.loadDetails(widget.organizationId, forceRefresh: true),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(AppSpacing.screenHorizontal),
        children: [
          if (provider.detailsErrorMessage != null) ...[
            AppErrorView(
              compact: true,
              title: 'Refresh Failed',
              message: provider.detailsErrorMessage!,
              onRetry: () => provider.loadDetails(
                widget.organizationId,
                forceRefresh: true,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
          ],
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  organization.organizationName,
                  style: textTheme.titleLarge,
                ),
                const SizedBox(height: AppSpacing.xs),
                Wrap(
                  spacing: AppSpacing.xs,
                  runSpacing: AppSpacing.xxs,
                  children: [
                    StatusChip(
                      label:
                          _typeLabels[organization.organizationType] ??
                          organization.organizationType,
                      type: AppStatusType.primary,
                      compact: true,
                    ),
                    StatusChip(
                      label:
                          _statusLabels[organization.approvalStatus] ??
                          organization.approvalStatus,
                      type: _statusChipType(organization.approvalStatus),
                      compact: true,
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                if (organization.user?.email != null)
                  _DetailRow(label: 'Email', value: organization.user!.email),
                if (organization.phone != null)
                  _DetailRow(label: 'Phone', value: organization.phone!),
                if (organization.website != null)
                  _DetailRow(label: 'Website', value: organization.website!),
                if (organization.industry != null)
                  _DetailRow(label: 'Industry', value: organization.industry!),
                if (organization.description != null) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Text('Description', style: textTheme.labelLarge),
                  const SizedBox(height: AppSpacing.xxs),
                  Text(
                    organization.description!,
                    style: textTheme.bodyMedium?.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (isPending) ...[
            const SizedBox(height: AppSpacing.lg),
            PrimaryButton(
              key: const Key('approve-action'),
              label: 'Approve',
              isLoading: _isApproving,
              onPressed: isBusy ? null : () => _handleApprove(provider),
            ),
            const SizedBox(height: AppSpacing.sm),
            DangerButton(
              key: const Key('reject-action'),
              label: 'Reject',
              isLoading: _isRejecting,
              onPressed: isBusy ? null : () => _handleReject(provider),
            ),
          ],
        ],
      ),
    );
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
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              label,
              style: textTheme.bodySmall?.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ),
          Expanded(child: Text(value, style: textTheme.bodyMedium)),
        ],
      ),
    );
  }
}
