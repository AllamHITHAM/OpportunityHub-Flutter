import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/date_formatter.dart';
import '../../../core/widgets/app_widgets.dart';
import '../../../models/user_model.dart';
import '../../../providers/admin_users_provider.dart';
import '../../../providers/auth_provider.dart';

/// Display labels for [UserModel.role] — kept local to this screen, not
/// the model, matching this app's convention of keeping display concerns
/// out of models (see `application_display.dart`/`opportunity_display.dart`
/// for the same pattern elsewhere).
const _roleLabels = {
  'student': 'Student',
  'organization': 'Organization',
  'admin': 'Admin',
};

const _statusLabels = {
  'active': 'Active',
  'suspended': 'Suspended',
  'pending': 'Pending',
};

AppStatusType _statusChipType(String status) {
  switch (status) {
    case 'active':
      return AppStatusType.success;
    case 'suspended':
      return AppStatusType.error;
    case 'pending':
      return AppStatusType.warning;
    default:
      return AppStatusType.neutral;
  }
}

/// Lists every platform user and lets an admin suspend/reactivate them.
/// Role changes and user deletion are intentionally not supported here —
/// the backend has no such endpoints.
class AdminUsersScreen extends StatefulWidget {
  const AdminUsersScreen({super.key});

  @override
  State<AdminUsersScreen> createState() => _AdminUsersScreenState();
}

class _AdminUsersScreenState extends State<AdminUsersScreen> {
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void initState() {
    super.initState();
    // Deferred to the post-frame callback — see
    // StudentOpportunitiesScreen.initState for why calling this directly
    // here would violate Flutter's build-phase constraints.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<AdminUsersProvider>().load();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  /// Client-side only — name/email/role, case-insensitive. No backend
  /// query params, per this phase's scope.
  List<UserModel> _filtered(List<UserModel> users) {
    final query = _query.trim().toLowerCase();
    if (query.isEmpty) return users;
    return users.where((user) {
      return user.name.toLowerCase().contains(query) ||
          user.email.toLowerCase().contains(query) ||
          user.role.toLowerCase().contains(query);
    }).toList();
  }

  Future<void> _handleStatusChange({
    required AdminUsersProvider provider,
    required UserModel user,
    required String newStatus,
  }) async {
    final isSuspend = newStatus == 'suspended';
    final confirmed = await showAppConfirmationDialog(
      context,
      title: isSuspend ? 'Suspend User' : 'Reactivate User',
      message: isSuspend
          ? 'Are you sure you want to suspend this user?'
          : 'Are you sure you want to reactivate this user?',
      confirmLabel: isSuspend ? 'Suspend' : 'Reactivate',
      type: isSuspend
          ? AppConfirmationType.danger
          : AppConfirmationType.neutral,
    );
    if (!confirmed || !mounted) return;

    final success = await provider.updateStatus(
      userId: user.id,
      status: newStatus,
    );
    if (!mounted) return;

    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isSuspend
                ? 'User suspended successfully'
                : 'User reactivated successfully',
          ),
        ),
      );
    } else if (provider.actionErrorMessage != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(provider.actionErrorMessage!)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AdminUsersProvider>();
    final authProvider = context.watch<AuthProvider>();

    return Scaffold(
      appBar: AppBar(title: const Text('Manage Users')),
      body: SafeArea(child: _buildBody(provider, authProvider)),
    );
  }

  Widget _buildBody(AdminUsersProvider provider, AuthProvider authProvider) {
    if (provider.isLoading && provider.users.isEmpty) {
      return const AppSkeletonList();
    }

    if (provider.errorMessage != null && provider.users.isEmpty) {
      return AppErrorView(
        message: provider.errorMessage!,
        onRetry: () => provider.load(forceRefresh: true),
      );
    }

    if (provider.users.isEmpty) {
      return const AppEmptyView(
        title: 'No Users Yet',
        message: 'There are no users on the platform yet.',
        icon: Icons.people_outline_rounded,
      );
    }

    final filtered = _filtered(provider.users);
    final selfId = authProvider.user?.id;

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
            hint: 'Search by name, email, or role',
            onChanged: (value) => setState(() => _query = value),
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
                        message: 'No users match your search.',
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
                      final user = filtered[index];
                      final isSelf = selfId != null && user.id == selfId;
                      return _UserCard(
                        user: user,
                        isSelf: isSelf,
                        isBusy: provider.isBusy(user.id),
                        onSuspend: () => _handleStatusChange(
                          provider: provider,
                          user: user,
                          newStatus: 'suspended',
                        ),
                        onReactivate: () => _handleStatusChange(
                          provider: provider,
                          user: user,
                          newStatus: 'active',
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

class _UserCard extends StatelessWidget {
  const _UserCard({
    required this.user,
    required this.isSelf,
    required this.isBusy,
    required this.onSuspend,
    required this.onReactivate,
  });

  final UserModel user;
  final bool isSelf;
  final bool isBusy;
  final VoidCallback onSuspend;
  final VoidCallback onReactivate;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final joined = user.createdAt;
    final name = user.name.trim().isEmpty ? 'Unnamed user' : user.name;

    return AppCard(
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
                    Text(name, style: textTheme.titleMedium),
                    const SizedBox(height: AppSpacing.xxs),
                    Text(user.email, style: textTheme.bodySmall),
                  ],
                ),
              ),
              if (isSelf) ...[
                const SizedBox(width: AppSpacing.xs),
                const StatusChip(
                  label: 'You',
                  type: AppStatusType.info,
                  compact: true,
                ),
              ],
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xxs,
            children: [
              StatusChip(
                label: _roleLabels[user.role] ?? user.role,
                type: AppStatusType.primary,
                compact: true,
              ),
              StatusChip(
                label: _statusLabels[user.status] ?? user.status,
                type: _statusChipType(user.status),
                compact: true,
              ),
            ],
          ),
          if (joined != null) ...[
            const SizedBox(height: AppSpacing.xxs),
            Text(
              'Joined ${formatDate(joined)}',
              style: textTheme.bodySmall?.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ],
          if (!isSelf && user.status == 'active') ...[
            const SizedBox(height: AppSpacing.sm),
            DangerButton(
              key: Key('suspend-action-${user.id}'),
              label: 'Suspend',
              isLoading: isBusy,
              onPressed: isBusy ? null : onSuspend,
            ),
          ],
          if (!isSelf && user.status == 'suspended') ...[
            const SizedBox(height: AppSpacing.sm),
            PrimaryButton(
              key: Key('reactivate-action-${user.id}'),
              label: 'Reactivate',
              isLoading: isBusy,
              onPressed: isBusy ? null : onReactivate,
            ),
          ],
        ],
      ),
    );
  }
}
