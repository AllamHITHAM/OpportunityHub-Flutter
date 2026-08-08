import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/app_widgets.dart';
import '../../../providers/admin_dashboard_provider.dart';
import '../../../providers/auth_provider.dart';
import '../../../routes/app_routes.dart';

/// The Admin dashboard — platform-wide statistics, plus a navigation entry
/// to Manage Users (implemented) and (disabled, "Coming Soon") entries for
/// the Organizations/Skills management areas that later phases will
/// implement.
class AdminHomeScreen extends StatefulWidget {
  const AdminHomeScreen({super.key});

  @override
  State<AdminHomeScreen> createState() => _AdminHomeScreenState();
}

class _AdminHomeScreenState extends State<AdminHomeScreen> {
  @override
  void initState() {
    super.initState();
    // Deferred to the post-frame callback — see
    // StudentOpportunitiesScreen.initState for why calling this directly
    // here would violate Flutter's build-phase constraints.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<AdminDashboardProvider>().load();
    });
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AdminDashboardProvider>();
    final authProvider = context.watch<AuthProvider>();

    return Scaffold(
      appBar: AppBar(title: const Text('Admin Dashboard')),
      body: SafeArea(child: _buildBody(provider, authProvider)),
    );
  }

  Widget _buildBody(
    AdminDashboardProvider provider,
    AuthProvider authProvider,
  ) {
    final stats = provider.stats;

    if (provider.isLoading && stats == null) {
      return const AppLoading();
    }

    if (provider.errorMessage != null && stats == null) {
      return AppErrorView(
        message: provider.errorMessage!,
        onRetry: () => provider.load(forceRefresh: true),
      );
    }

    if (stats == null) {
      // Neither loading, nor an error, nor stats -- the load hasn't been
      // kicked off yet (e.g. the very first frame, before the post-frame
      // callback runs). Rendering the same loading state here (rather
      // than an empty screen) keeps this branch from ever being a visible
      // flash of nothing.
      return const AppLoading();
    }

    return RefreshIndicator(
      onRefresh: () => provider.load(forceRefresh: true),
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(AppSpacing.screenHorizontal),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _AdminIdentityCard(authProvider: authProvider),
            if (provider.errorMessage != null) ...[
              const SizedBox(height: AppSpacing.md),
              AppErrorView(
                compact: true,
                title: 'Refresh Failed',
                message: provider.errorMessage!,
                onRetry: () => provider.load(forceRefresh: true),
              ),
            ],
            const SizedBox(height: AppSpacing.lg),
            _StatSection(
              title: 'Overview',
              items: [
                _StatItem('Total Users', stats.totalUsers),
                _StatItem('Students', stats.totalStudents),
                _StatItem('Organizations', stats.totalOrganizations),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            _StatSection(
              title: 'Organizations',
              items: [
                _StatItem('Pending', stats.pendingOrganizations),
                _StatItem('Approved', stats.approvedOrganizations),
                _StatItem('Rejected', stats.rejectedOrganizations),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            _StatSection(
              title: 'Opportunities',
              items: [
                _StatItem('Total', stats.totalOpportunities),
                _StatItem('Open', stats.openOpportunities),
                _StatItem('Closed', stats.closedOpportunities),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            _StatSection(
              title: 'Recruitment',
              items: [
                _StatItem('Applications', stats.totalApplications),
                _StatItem('Interviews', stats.totalInterviews),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            const SectionHeader(title: 'Manage'),
            const SizedBox(height: AppSpacing.xs),
            _ManageEntry(
              icon: Icons.people_outline_rounded,
              label: 'Manage Users',
              onTap: () => context.push(AppRoutes.adminUsers),
            ),
            const SizedBox(height: AppSpacing.sm),
            _ManageEntry(
              icon: Icons.business_outlined,
              label: 'Manage Organizations',
              onTap: () => context.push(AppRoutes.adminOrganizations),
            ),
            const SizedBox(height: AppSpacing.sm),
            const _ManageEntry(
              icon: Icons.psychology_outlined,
              label: 'Manage Skills',
            ),
            const SizedBox(height: AppSpacing.lg),
            SecondaryButton(
              label: 'Logout',
              onPressed: () => authProvider.logout(),
            ),
            const SizedBox(height: AppSpacing.xl),
          ],
        ),
      ),
    );
  }
}

class _AdminIdentityCard extends StatelessWidget {
  const _AdminIdentityCard({required this.authProvider});

  final AuthProvider authProvider;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final user = authProvider.user;

    return AppCard(
      child: Row(
        children: [
          AppAvatar(name: user?.name, size: 44),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(user?.name ?? '', style: textTheme.titleMedium),
                Text(user?.email ?? '', style: textTheme.bodySmall),
              ],
            ),
          ),
          const StatusChip(label: 'Admin', type: AppStatusType.primary),
        ],
      ),
    );
  }
}

/// A single dashboard statistic — a plain label/value pair, not tied to any
/// backend field name. Kept private to this screen: these are display
/// labels, not something a model or a shared file should know about.
class _StatItem {
  const _StatItem(this.label, this.value);

  final String label;
  final int value;
}

/// A titled group of [_StatTile]s, laid out in a width-aware wrapping grid
/// so it never overflows at narrow widths and uses the extra space on wide
/// (e.g. web) viewports instead of leaving it empty.
class _StatSection extends StatelessWidget {
  const _StatSection({required this.title, required this.items});

  final String title;
  final List<_StatItem> items;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(title: title),
        const SizedBox(height: AppSpacing.xs),
        LayoutBuilder(
          builder: (context, constraints) {
            final columns = constraints.maxWidth >= 700
                ? 4
                : (constraints.maxWidth >= 420 ? 3 : 2);
            const spacing = AppSpacing.sm;
            final tileWidth =
                (constraints.maxWidth - spacing * (columns - 1)) / columns;

            return Wrap(
              spacing: spacing,
              runSpacing: spacing,
              children: [
                for (final item in items)
                  SizedBox(
                    width: tileWidth,
                    child: _StatTile(item: item),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({required this.item});

  final _StatItem item;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('${item.value}', style: textTheme.headlineSmall),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            item.label,
            style: textTheme.bodySmall,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

/// A navigation entry for a management area. With [onTap] omitted, this
/// renders as a disabled "Coming Soon" placeholder for an area not
/// implemented yet (Organizations, Skills — later phases) — deliberately
/// has no `onTap` at all in that case, so it can never navigate to a route
/// that doesn't exist yet. With [onTap] provided (Users, this phase), it
/// renders as a normal enabled, tappable entry instead.
class _ManageEntry extends StatelessWidget {
  const _ManageEntry({required this.icon, required this.label, this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final enabled = onTap != null;
    final color = enabled ? null : Theme.of(context).disabledColor;

    return AppCard(
      onTap: onTap,
      child: Row(
        children: [
          Icon(icon, color: color),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              label,
              style: textTheme.titleSmall?.copyWith(color: color),
            ),
          ),
          if (enabled)
            const Icon(Icons.chevron_right_rounded)
          else
            const StatusChip(label: 'Coming Soon', compact: true),
        ],
      ),
    );
  }
}
