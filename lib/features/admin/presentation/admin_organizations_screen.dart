import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/app_widgets.dart';
import '../../../models/organization_profile_model.dart';
import '../../../providers/admin_organizations_provider.dart';
import '../../../routes/app_routes.dart';

/// Display labels for [OrganizationProfileModel.organizationType] — kept
/// local to this screen, not the model, matching this app's convention of
/// keeping display concerns out of models (see `admin_users_screen.dart`'s
/// `_roleLabels` for the same pattern).
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

/// A simple client-side approval-status filter — no backend query params,
/// per this phase's scope. `all` is the default and shows everything.
enum _ApprovalFilter { all, pending, approved, rejected }

extension on _ApprovalFilter {
  String get label => switch (this) {
    _ApprovalFilter.all => 'All',
    _ApprovalFilter.pending => 'Pending',
    _ApprovalFilter.approved => 'Approved',
    _ApprovalFilter.rejected => 'Rejected',
  };

  String? get wireValue => switch (this) {
    _ApprovalFilter.all => null,
    _ApprovalFilter.pending => 'pending',
    _ApprovalFilter.approved => 'approved',
    _ApprovalFilter.rejected => 'rejected',
  };
}

/// Lists every platform organization and lets an admin drill into one for
/// approval/rejection. Organization deletion and profile editing are
/// intentionally not supported here — the backend has no such Admin
/// endpoints.
class AdminOrganizationsScreen extends StatefulWidget {
  const AdminOrganizationsScreen({super.key});

  @override
  State<AdminOrganizationsScreen> createState() =>
      _AdminOrganizationsScreenState();
}

class _AdminOrganizationsScreenState extends State<AdminOrganizationsScreen> {
  final _searchController = TextEditingController();
  String _query = '';
  _ApprovalFilter _filter = _ApprovalFilter.all;

  @override
  void initState() {
    super.initState();
    // Deferred to the post-frame callback — see
    // StudentOpportunitiesScreen.initState for why calling this directly
    // here would violate Flutter's build-phase constraints.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<AdminOrganizationsProvider>().load();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  /// Client-side only — organization name, user email, type, and approval
  /// status, case-insensitive. No backend query params, per this phase's
  /// scope.
  List<OrganizationProfileModel> _filtered(
    List<OrganizationProfileModel> organizations,
  ) {
    var result = organizations;

    final statusFilter = _filter.wireValue;
    if (statusFilter != null) {
      result = result
          .where((organization) => organization.approvalStatus == statusFilter)
          .toList();
    }

    final query = _query.trim().toLowerCase();
    if (query.isEmpty) return result;
    return result.where((organization) {
      return organization.organizationName.toLowerCase().contains(query) ||
          (organization.user?.email.toLowerCase().contains(query) ?? false) ||
          organization.organizationType.toLowerCase().contains(query) ||
          organization.approvalStatus.toLowerCase().contains(query);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AdminOrganizationsProvider>();

    return Scaffold(
      appBar: AppBar(title: const Text('Manage Organizations')),
      body: SafeArea(child: _buildBody(provider)),
    );
  }

  Widget _buildBody(AdminOrganizationsProvider provider) {
    if (provider.isLoading && provider.organizations.isEmpty) {
      return const AppSkeletonList();
    }

    if (provider.errorMessage != null && provider.organizations.isEmpty) {
      return AppErrorView(
        message: provider.errorMessage!,
        onRetry: () => provider.load(forceRefresh: true),
      );
    }

    if (provider.organizations.isEmpty) {
      return const AppEmptyView(
        title: 'No Organizations Yet',
        message: 'There are no organizations on the platform yet.',
        icon: Icons.business_outlined,
      );
    }

    final filtered = _filtered(provider.organizations);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.screenHorizontal,
            AppSpacing.screenHorizontal,
            AppSpacing.screenHorizontal,
            0,
          ),
          child: AppSearchField(
            controller: _searchController,
            hint: 'Search by name, email, or type',
            onChanged: (value) => setState(() => _query = value),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.screenHorizontal,
            AppSpacing.sm,
            AppSpacing.screenHorizontal,
            0,
          ),
          child: Wrap(
            spacing: AppSpacing.xs,
            children: [
              for (final option in _ApprovalFilter.values)
                ChoiceChip(
                  label: Text(option.label),
                  selected: _filter == option,
                  onSelected: (_) => setState(() => _filter = option),
                ),
            ],
          ),
        ),
        if (provider.errorMessage != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.screenHorizontal,
              AppSpacing.sm,
              AppSpacing.screenHorizontal,
              0,
            ),
            child: AppErrorView(
              compact: true,
              title: 'Refresh Failed',
              message: provider.errorMessage!,
              onRetry: () => provider.load(forceRefresh: true),
            ),
          ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: () => provider.load(forceRefresh: true),
            child: filtered.isEmpty
                ? ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: const [
                      SizedBox(height: AppSpacing.xxl),
                      AppEmptyView(
                        title: 'No Matches',
                        message: 'No organizations match your search.',
                        icon: Icons.search_off_rounded,
                      ),
                    ],
                  )
                : ListView.separated(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(AppSpacing.screenHorizontal),
                    itemCount: filtered.length,
                    separatorBuilder: (_, _) =>
                        const SizedBox(height: AppSpacing.sm),
                    itemBuilder: (context, index) {
                      final organization = filtered[index];
                      return _OrganizationCard(
                        organization: organization,
                        onTap: () => context.push(
                          AppRoutes.adminOrganizationDetails(organization.id),
                        ),
                      );
                    },
                  ),
          ),
        ),
      ],
    );
  }
}

class _OrganizationCard extends StatelessWidget {
  const _OrganizationCard({required this.organization, required this.onTap});

  final OrganizationProfileModel organization;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final email = organization.user?.email;

    return AppCard(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      organization.organizationName,
                      style: textTheme.titleMedium,
                    ),
                    if (email != null) ...[
                      const SizedBox(height: AppSpacing.xxs),
                      Text(email, style: textTheme.bodySmall),
                    ],
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded),
            ],
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
        ],
      ),
    );
  }
}
