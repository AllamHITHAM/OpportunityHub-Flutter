import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_motion.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/app_widgets.dart';
import '../../../providers/admin_dashboard_provider.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/notification_provider.dart';
import '../../../routes/app_routes.dart';
import '../../auth/presentation/email_verification_banner.dart';
import '../../notifications/presentation/notification_bell_action.dart';

/// Real, responsive breakpoints for the metric grid, and the centered
/// desktop content width (Admin Dashboard Final UI Polish) — deliberately
/// the exact same values `OrganizationHomeScreen` already established,
/// not a new, competing set of breakpoints for this one screen.
const _wideBreakpoint = 1200.0;
const _desktopBreakpoint = 900.0;
const _tabletBreakpoint = 600.0;
const _maxContentWidth = 900.0;

/// The Admin dashboard — platform-wide statistics, plus navigation entries
/// to Manage Users, Manage Organizations, Manage Skills, and Education
/// Verifications. Every number here is a real backend count from
/// `GET /api/admin/dashboard` — this phase is visual/responsive polish
/// only, never a new statistic or a changed query (see
/// `AdminDashboardStatsModel`/`DashboardController` — both untouched).
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
      // Independent of the dashboard load above — see StudentHomeScreen's
      // own initState doc comment on why this fires once per Home-screen
      // entry rather than being polled.
      context.read<NotificationProvider>().load();
    });
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AdminDashboardProvider>();
    final authProvider = context.watch<AuthProvider>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Admin Dashboard'),
        actions: const [ThemeToggleButton(), NotificationBellAction()],
      ),
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
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;

          return SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.symmetric(
              horizontal: width >= _desktopBreakpoint
                  ? AppSpacing.xl
                  : AppSpacing.screenHorizontal,
              vertical: AppSpacing.md,
            ),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: _maxContentWidth),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _AdminIdentityCard(authProvider: authProvider),
                    const SizedBox(height: AppSpacing.md),
                    const EmailVerificationBanner(),
                    if (provider.errorMessage != null) ...[
                      const SizedBox(height: AppSpacing.sm),
                      AppErrorView(
                        compact: true,
                        title: 'Refresh Failed',
                        message: provider.errorMessage!,
                        onRetry: () => provider.load(forceRefresh: true),
                      ),
                    ],
                    const SizedBox(height: AppSpacing.lg),
                    _MetricGroup(
                      title: 'Overview',
                      width: width,
                      metrics: [
                        _Metric(
                          icon: Icons.groups_outlined,
                          label: 'Total Users',
                          value: stats.totalUsers,
                        ),
                        _Metric(
                          icon: Icons.person_outline_rounded,
                          label: 'Students',
                          value: stats.totalStudents,
                        ),
                        _Metric(
                          icon: Icons.business_outlined,
                          label: 'Organizations',
                          value: stats.totalOrganizations,
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    _MetricGroup(
                      title: 'Organizations',
                      width: width,
                      metrics: [
                        _Metric(
                          icon: Icons.hourglass_top_outlined,
                          label: 'Pending',
                          value: stats.pendingOrganizations,
                          type: AppStatusType.warning,
                          // Admin Dashboard Final UI Polish: real-data-driven
                          // emphasis only -- never a fabricated alert. A
                          // genuinely nonzero Pending count (real backend
                          // data already on screen either way) gets a
                          // slightly stronger border, nothing invented.
                          emphasized: stats.pendingOrganizations > 0,
                        ),
                        _Metric(
                          icon: Icons.check_circle_outline,
                          label: 'Approved',
                          value: stats.approvedOrganizations,
                          type: AppStatusType.success,
                        ),
                        _Metric(
                          icon: Icons.cancel_outlined,
                          label: 'Rejected',
                          value: stats.rejectedOrganizations,
                          type: AppStatusType.error,
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    _MetricGroup(
                      title: 'Opportunities',
                      width: width,
                      metrics: [
                        _Metric(
                          icon: Icons.work_outline_rounded,
                          label: 'Total',
                          value: stats.totalOpportunities,
                        ),
                        _Metric(
                          icon: Icons.check_circle_outline,
                          label: 'Open',
                          value: stats.openOpportunities,
                          type: AppStatusType.success,
                        ),
                        _Metric(
                          icon: Icons.archive_outlined,
                          label: 'Closed',
                          value: stats.closedOpportunities,
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    _MetricGroup(
                      title: 'Recruitment',
                      width: width,
                      metrics: [
                        _Metric(
                          icon: Icons.description_outlined,
                          label: 'Applications',
                          value: stats.totalApplications,
                        ),
                        _Metric(
                          icon: Icons.groups_2_outlined,
                          label: 'Interviews',
                          value: stats.totalInterviews,
                        ),
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
                    _ManageEntry(
                      icon: Icons.psychology_outlined,
                      label: 'Manage Skills',
                      onTap: () => context.push(AppRoutes.adminSkills),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    _ManageEntry(
                      icon: Icons.school_outlined,
                      label: 'Education Verifications',
                      onTap: () =>
                          context.push(AppRoutes.adminEducationVerifications),
                    ),
                    const SizedBox(height: AppSpacing.xl),
                    Center(
                      child: TextButton.icon(
                        onPressed: () => authProvider.logout(),
                        icon: Icon(
                          Icons.logout_rounded,
                          size: 18,
                          color: AppColors.textSecondary,
                        ),
                        label: Text(
                          'Logout',
                          style: TextStyle(color: AppColors.textSecondary),
                        ),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// The Admin identity card — avatar/initials, name, email, and the "Admin"
/// role badge, unchanged in substance from before this polish (no new
/// profile feature, no Admin Profile screen). A subtle one-time entrance
/// (respecting reduced motion), mirroring `OrganizationHomeScreen`'s own
/// `_DashboardHeader` — the same restrained motion already standard
/// elsewhere in this app, not a new animation invented for this screen.
class _AdminIdentityCard extends StatelessWidget {
  const _AdminIdentityCard({required this.authProvider});

  final AuthProvider authProvider;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final user = authProvider.user;
    final reducedMotion = AppMotion.reduced(context, AppMotion.slow);

    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: reducedMotion,
      curve: AppMotion.entrance,
      builder: (context, t, child) => Opacity(
        opacity: t,
        child: Transform.translate(
          offset: Offset(0, (1 - t) * 8),
          child: child,
        ),
      ),
      child: AppCard(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            AppAvatar(name: user?.name, size: 48),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    user?.name ?? '',
                    style: textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: AppSpacing.xxs),
                  Text(
                    user?.email ?? '',
                    style: textTheme.bodySmall?.copyWith(
                      color: AppColors.textSecondary,
                    ),
                    // A long Admin email must wrap safely on a narrow
                    // phone, never overflow -- see spec's own mobile
                    // requirement. Two lines is enough room for any
                    // realistic address without pushing the badge below.
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.xs),
            const StatusChip(label: 'Admin', type: AppStatusType.primary),
          ],
        ),
      ),
    );
  }
}

/// One real dashboard statistic — a plain icon/label/value tuple, not tied
/// to any backend field name beyond what [AdminDashboardStatsModel]
/// already provides. Kept private to this screen: these are display
/// labels, not something a model or a shared file should know about.
/// Mirrors `OrganizationHomeScreen`'s own `_Metric` exactly, for one
/// consistent metric-tile look across every dashboard in this app.
class _Metric {
  const _Metric({
    required this.icon,
    required this.label,
    required this.value,
    this.type = AppStatusType.neutral,
    this.emphasized = false,
  });

  final IconData icon;
  final String label;
  final int value;
  final AppStatusType type;

  /// Real-data-driven only (e.g. a nonzero Pending count) -- never set from
  /// an invented condition. Renders a stronger accent border; the number
  /// and label are always present regardless, so status is never conveyed
  /// by color/emphasis alone.
  final bool emphasized;
}

/// A titled group of [_MetricTile]s, laid out in a width-aware wrapping
/// grid so it never overflows at narrow widths and uses the extra space on
/// wide (desktop/web) viewports instead of leaving it empty. Identical
/// breakpoint logic to `OrganizationHomeScreen`'s own `_MetricGroup`.
class _MetricGroup extends StatelessWidget {
  const _MetricGroup({
    required this.title,
    required this.width,
    required this.metrics,
  });

  final String title;
  final double width;
  final List<_Metric> metrics;

  int get _columns {
    if (width >= _wideBreakpoint) return 4;
    if (width >= _desktopBreakpoint) return 3;
    if (width >= _tabletBreakpoint) return 2;
    return 2;
  }

  @override
  Widget build(BuildContext context) {
    final columns = _columns;
    const spacing = AppSpacing.sm;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(title: title),
        const SizedBox(height: AppSpacing.xs),
        LayoutBuilder(
          builder: (context, constraints) {
            final tileWidth =
                (constraints.maxWidth - spacing * (columns - 1)) / columns;

            return Wrap(
              spacing: spacing,
              runSpacing: spacing,
              children: [
                for (final metric in metrics)
                  SizedBox(
                    width: tileWidth,
                    child: _MetricTile(metric: metric),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _MetricTile extends StatelessWidget {
  const _MetricTile({required this.metric});

  final _Metric metric;

  Color get _accent {
    switch (metric.type) {
      case AppStatusType.success:
        return AppColors.success;
      case AppStatusType.warning:
        return AppColors.warning;
      case AppStatusType.error:
        return AppColors.error;
      case AppStatusType.info:
        return AppColors.info;
      case AppStatusType.primary:
        return AppColors.primary;
      case AppStatusType.neutral:
        return AppColors.textSecondary;
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return AppCard(
      borderColor: metric.emphasized ? _accent : null,
      child: Semantics(
        // Screen-reader-friendly: announces as one coherent statistic
        // ("Pending, 3") rather than two disconnected text nodes.
        label: '${metric.label}, ${metric.value}',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(metric.icon, size: 18, color: _accent),
            const SizedBox(height: AppSpacing.xs),
            Text(
              '${metric.value}',
              style: textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: AppSpacing.xxs),
            Text(
              metric.label,
              style: textTheme.bodySmall?.copyWith(
                color: AppColors.textSecondary,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

/// A navigation entry for a management area. With [onTap] omitted, this
/// renders as a disabled "Coming Soon" placeholder for an area not
/// implemented yet — deliberately has no `onTap` at all in that case, so
/// it can never navigate to a route that doesn't exist yet. With [onTap]
/// provided, it renders as a normal enabled, tappable entry instead. Every
/// current entry (Users, Organizations, Skills) is enabled; this still
/// exists for whatever future management area comes next.
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
      // Admin Dashboard Final UI Polish: a subtle Web hover lift + mobile
      // press-scale on top of the tap ripple `onTap` already provides --
      // the same opt-in `AppCard` already offers `_QuickActionCard` on the
      // Organization dashboard. Routes/business logic are untouched.
      interactive: true,
      child: Row(
        children: [
          SizedBox(width: 24, child: Icon(icon, color: color)),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              label,
              style: textTheme.titleSmall?.copyWith(color: color),
            ),
          ),
          if (enabled)
            Icon(Icons.chevron_right_rounded, color: AppColors.textSecondary)
          else
            const StatusChip(label: 'Coming Soon', compact: true),
        ],
      ),
    );
  }
}
