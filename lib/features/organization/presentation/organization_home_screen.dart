import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_motion.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/app_widgets.dart';
import '../../../models/organization_dashboard_stats_model.dart';
import '../../../models/organization_profile_model.dart';
import '../../../models/user_model.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/notification_provider.dart';
import '../../../providers/organization_dashboard_provider.dart';
import '../../../providers/organization_profile_provider.dart';
import '../../../routes/app_routes.dart';
import '../../auth/presentation/email_verification_banner.dart';
import '../../messaging/presentation/messages_bell_action.dart';
import '../../notifications/presentation/notification_bell_action.dart';

/// User-facing labels for `OrganizationProfileModel.organizationType` — must
/// match `RegisterOrganizationRequest`'s
/// `in:company,university,ngo,training_center,government,other` rule.
/// Mirrors the identical private map already defined in
/// `organization_registration_screen.dart` — kept local to each screen
/// rather than shared, the established convention in this codebase for a
/// small display-only label map (see also the Admin organization screens).
const _organizationTypeLabels = {
  'company': 'Company',
  'university': 'University',
  'ngo': 'NGO',
  'training_center': 'Training Center',
  'government': 'Government',
  'other': 'Other',
};

/// Real, responsive breakpoints for the metric/quick-action grids —
/// mirrors the four bands used elsewhere in this app (e.g.
/// `StudentHomeScreen`'s discovery grid).
const _wideBreakpoint = 1200.0;
const _desktopBreakpoint = 900.0;
const _tabletBreakpoint = 600.0;
const _maxContentWidth = 1040.0;

/// The Organization dashboard — a real recruitment dashboard built entirely
/// from `GET /api/organization/dashboard`'s existing statistics
/// ([OrganizationDashboardProvider]) plus the organization's own profile
/// ([OrganizationProfileProvider], for the header's name/context) and
/// account ([AuthProvider], for the avatar/verification state). No
/// fabricated metric, list, or field — every number shown here is a real
/// backend count; see [OrganizationDashboardStatsModel]'s own doc comment.
///
/// Deliberately shows no "Recent Applications"/"Recent Opportunities" list
/// — the dashboard endpoint returns only counts, never list data, so
/// building one here would mean inventing an endpoint call this screen has
/// no real data to back. See docs/API.md for the exact response shape this
/// screen renders.
class OrganizationHomeScreen extends StatefulWidget {
  const OrganizationHomeScreen({super.key});

  @override
  State<OrganizationHomeScreen> createState() => _OrganizationHomeScreenState();
}

class _OrganizationHomeScreenState extends State<OrganizationHomeScreen> {
  @override
  void initState() {
    super.initState();
    // Deferred to the post-frame callback — see
    // StudentOpportunitiesScreen.initState for why calling this directly
    // here would violate Flutter's build-phase constraints. Each provider
    // already guards against duplicate concurrent loads on its own, so
    // revisiting this screen is always safe.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<NotificationProvider>().load();
      context.read<OrganizationDashboardProvider>().load();
      // The router's own redirect logic already calls this once per
      // sign-in before this screen is ever reachable — this is a
      // defensive, idempotent fallback (skipped once already checked) in
      // case this screen is ever reached some other way.
      final profileProvider = context.read<OrganizationProfileProvider>();
      if (!profileProvider.hasChecked) {
        profileProvider.checkProfileStatus();
      }
    });
  }

  Future<void> _onRefresh() {
    return context.read<OrganizationDashboardProvider>().load(
      forceRefresh: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = context.watch<AuthProvider>();
    final profileProvider = context.watch<OrganizationProfileProvider>();
    final dashboardProvider = context.watch<OrganizationDashboardProvider>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Dashboard'),
        actions: [
          const ThemeToggleButton(),
          const MessagesBellAction(),
          const NotificationBellAction(),
          _ProfileNavButton(user: authProvider.user),
          const SizedBox(width: AppSpacing.xs),
        ],
      ),
      body: SafeArea(
        child: _buildBody(authProvider, profileProvider, dashboardProvider),
      ),
    );
  }

  Widget _buildBody(
    AuthProvider authProvider,
    OrganizationProfileProvider profileProvider,
    OrganizationDashboardProvider dashboardProvider,
  ) {
    final stats = dashboardProvider.stats;

    if (dashboardProvider.isLoading && stats == null) {
      return const AppLoading();
    }

    if (dashboardProvider.errorMessage != null && stats == null) {
      return AppErrorView(
        message: dashboardProvider.errorMessage!,
        onRetry: () => dashboardProvider.load(forceRefresh: true),
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
      onRefresh: _onRefresh,
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
                    _DashboardHeader(
                      user: authProvider.user,
                      profile: profileProvider.profile,
                    ),
                    const SizedBox(height: AppSpacing.md),
                    const EmailVerificationBanner(),
                    if (dashboardProvider.errorMessage != null) ...[
                      const SizedBox(height: AppSpacing.sm),
                      AppErrorView(
                        compact: true,
                        title: 'Refresh Failed',
                        message: dashboardProvider.errorMessage!,
                        onRetry: () =>
                            dashboardProvider.load(forceRefresh: true),
                      ),
                    ],
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
                        _Metric(
                          icon: Icons.edit_note_outlined,
                          label: 'Draft',
                          value: stats.draftOpportunities,
                          type: AppStatusType.warning,
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    _MetricGroup(
                      title: 'Applications',
                      width: width,
                      metrics: [
                        _Metric(
                          icon: Icons.description_outlined,
                          label: 'Total',
                          value: stats.totalApplications,
                        ),
                        _Metric(
                          icon: Icons.hourglass_top_outlined,
                          label: 'Pending Review',
                          value: stats.pendingApplications,
                          type: AppStatusType.warning,
                        ),
                        _Metric(
                          icon: Icons.star_outline_rounded,
                          label: 'Shortlisted',
                          value: stats.shortlistedApplications,
                          type: AppStatusType.info,
                        ),
                        _Metric(
                          icon: Icons.local_offer_outlined,
                          label: 'Offer Sent',
                          value: stats.offerSentApplications,
                          type: AppStatusType.primary,
                        ),
                        _Metric(
                          icon: Icons.check_circle_outline,
                          label: 'Accepted',
                          value: stats.acceptedApplications,
                          type: AppStatusType.success,
                        ),
                        _Metric(
                          icon: Icons.cancel_outlined,
                          label: 'Rejected',
                          value: stats.rejectedApplications,
                          type: AppStatusType.error,
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    _MetricGroup(
                      title: 'Interviews',
                      width: width,
                      metrics: [
                        _Metric(
                          icon: Icons.groups_outlined,
                          label: 'Total',
                          value: stats.totalInterviews,
                        ),
                        _Metric(
                          icon: Icons.task_alt_outlined,
                          label: 'Completed',
                          value: stats.completedInterviews,
                          type: AppStatusType.success,
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    _QuickActions(width: width),
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

/// Organization Public Profile phase — the avatar nav button leading to
/// the organization's own Company Profile screen, mirroring
/// `StudentHomeScreen`'s own `_ProfileNavButton` exactly.
class _ProfileNavButton extends StatelessWidget {
  const _ProfileNavButton({required this.user});

  final UserModel? user;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxs),
      child: InkWell(
        onTap: () => context.push(AppRoutes.organizationProfile),
        customBorder: const CircleBorder(),
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: AppAvatar(name: user?.name, size: 32),
        ),
      ),
    );
  }
}

/// A compact welcome header — real organization/user identity, a short
/// real context line (organization type + industry, when the profile has
/// loaded), and a subtle one-time entrance (respecting reduced motion).
/// Never shows a fabricated stat or placeholder text; falls back cleanly
/// when [profile] hasn't loaded yet.
class _DashboardHeader extends StatelessWidget {
  const _DashboardHeader({required this.user, required this.profile});

  final UserModel? user;
  final OrganizationProfileModel? profile;

  String? get _displayName {
    final orgName = profile?.organizationName.trim();
    if (orgName != null && orgName.isNotEmpty) return orgName;
    final userName = user?.name.trim();
    return userName != null && userName.isNotEmpty ? userName : null;
  }

  String? get _context {
    final currentProfile = profile;
    if (currentProfile == null) return null;
    final typeLabel =
        _organizationTypeLabels[currentProfile.organizationType] ??
        currentProfile.organizationType;
    final industry = currentProfile.industry?.trim();
    if (industry != null && industry.isNotEmpty) {
      return '$typeLabel · $industry';
    }
    return typeLabel;
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final name = _displayName;
    final contextLine = _context;
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
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          OrganizationAvatar(name: name, size: 56),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  name == null ? 'Welcome' : 'Welcome, $name',
                  style: textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                if (contextLine != null)
                  Text(
                    contextLine,
                    style: textTheme.bodyMedium?.copyWith(
                      color: AppColors.textSecondary,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// One real dashboard statistic — a plain icon/label/value tuple, not tied
/// to any backend field name beyond what [OrganizationDashboardStatsModel]
/// already provides. Kept private to this screen: these are display
/// labels, not something a model or a shared file should know about.
class _Metric {
  const _Metric({
    required this.icon,
    required this.label,
    required this.value,
    this.type = AppStatusType.neutral,
  });

  final IconData icon;
  final String label;
  final int value;
  final AppStatusType type;
}

/// A titled group of [_MetricTile]s, laid out in a width-aware wrapping
/// grid so it never overflows at narrow widths and uses the extra space on
/// wide (desktop/web) viewports instead of leaving it empty — the core fix
/// for the old dashboard's mostly-empty desktop layout.
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
    );
  }
}

/// One real, existing recruitment action — creating/managing Opportunities,
/// or browsing Candidates. Every route here already exists elsewhere in
/// the app; this screen only adds a prominent entry point to them.
class _QuickAction {
  const _QuickAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
}

class _QuickActions extends StatelessWidget {
  const _QuickActions({required this.width});

  final double width;

  int get _columns {
    if (width >= _desktopBreakpoint) return 3;
    if (width >= _tabletBreakpoint) return 3;
    return 1;
  }

  @override
  Widget build(BuildContext context) {
    final actions = [
      _QuickAction(
        icon: Icons.add_circle_outline_rounded,
        label: 'Create Opportunity',
        onTap: () => context.push(AppRoutes.organizationOpportunityCreate),
      ),
      _QuickAction(
        icon: Icons.work_outline_rounded,
        label: 'Manage Opportunities',
        onTap: () => context.push(AppRoutes.organizationOpportunities),
      ),
      _QuickAction(
        icon: Icons.person_search_outlined,
        label: 'Browse Talent',
        onTap: () => context.push(AppRoutes.organizationCandidates),
      ),
    ];
    final columns = _columns;
    const spacing = AppSpacing.sm;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionHeader(title: 'Quick Actions'),
        const SizedBox(height: AppSpacing.xs),
        LayoutBuilder(
          builder: (context, constraints) {
            final tileWidth = columns == 1
                ? constraints.maxWidth
                : (constraints.maxWidth - spacing * (columns - 1)) / columns;

            return Wrap(
              spacing: spacing,
              runSpacing: spacing,
              children: [
                for (final action in actions)
                  SizedBox(
                    width: tileWidth,
                    child: _QuickActionCard(action: action),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _QuickActionCard extends StatelessWidget {
  const _QuickActionCard({required this.action});

  final _QuickAction action;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return AppCard(
      interactive: true,
      onTap: action.onTap,
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.primaryContainer,
            ),
            child: Icon(action.icon, color: AppColors.primaryDark, size: 20),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              action.label,
              style: textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Icon(Icons.chevron_right_rounded, color: AppColors.textSecondary),
        ],
      ),
    );
  }
}
