import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_motion.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/date_formatter.dart';
import '../../../core/widgets/app_widgets.dart';
import '../../../models/opportunity_model.dart';
import '../../../models/organization_post_model.dart';
import '../../../models/organization_profile_model.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/organization_profile_provider.dart';
import '../../../providers/organization_public_profile_provider.dart';
import '../../../routes/app_routes.dart';
import '../../opportunities/presentation/opportunity_display.dart';
import 'edit_post_sheet.dart';

const _maxContentWidth = 900.0;
const _twoColumnBreakpoint = 700.0;

const _organizationTypeLabels = {
  'company': 'Company',
  'university': 'University',
  'ngo': 'NGO',
  'training_center': 'Training Center',
  'government': 'Government',
  'other': 'Other',
};

String _organizationTypeLabel(String type) =>
    _organizationTypeLabels[type] ?? type;

/// A tiny wrapper that resolves the signed-in organization's own ID (from
/// [OrganizationProfileProvider], already loaded before this route is
/// reachable at all — see `AppRouter`'s profile-completion gating) and
/// renders [CompanyProfileScreen] for it. This is what
/// [AppRoutes.organizationProfile] actually routes to.
class OrganizationOwnProfileScreen extends StatelessWidget {
  const OrganizationOwnProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final ownId = context.watch<OrganizationProfileProvider>().profile?.id;

    if (ownId == null) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Company Profile'),
          actions: const [ThemeToggleSurface()],
        ),
        body: const SafeArea(
          child: AppEmptyView(
            icon: Icons.apartment_outlined,
            title: 'Company Profile Not Available',
            message: 'We could not load your company profile right now.',
          ),
        ),
      );
    }

    return CompanyProfileScreen(organizationId: ownId);
  }
}

/// The shared Company Profile screen (Organization Public Profile phase)
/// — one real screen for both the Organization owner viewing/managing
/// their own profile and a Student (or anyone else) viewing it publicly.
/// [_isOwner] is computed by comparing [organizationId] to the
/// signed-in organization's own ID, never trusted from navigation
/// context — owner-only controls (Edit Profile, Create/Edit/Delete
/// Update) only ever render when that's genuinely true, and the backend
/// independently enforces the same ownership on every mutation regardless
/// of what this screen shows.
class CompanyProfileScreen extends StatefulWidget {
  const CompanyProfileScreen({super.key, required this.organizationId});

  final int organizationId;

  @override
  State<CompanyProfileScreen> createState() => _CompanyProfileScreenState();
}

class _CompanyProfileScreenState extends State<CompanyProfileScreen> {
  // Captured once (not re-read fresh inside dispose()) -- calling
  // `context.read()` inside `dispose()` can throw
  // "Looking up a deactivated widget's ancestor is unsafe" if the
  // provider's own ancestor element was already torn down first during a
  // whole-tree teardown (e.g. between tests, or `pumpWidget` replacing
  // the tree). Holding the reference from `didChangeDependencies()`
  // sidesteps that entirely.
  late OrganizationPublicProfileProvider _publicProfileProvider;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<OrganizationPublicProfileProvider>().load(
        widget.organizationId,
      );
      // Closed Opportunities are owner-only real data -- there is no way
      // to scope `GET /organization/opportunities` to an arbitrary
      // organization, so this is only ever requested when the viewer has
      // already been confirmed to be the owner (never for a public/
      // Student visit, and never for a *different* signed-in
      // organization viewing someone else's profile).
      if (_isOwner) {
        context.read<OrganizationPublicProfileProvider>()
            .loadClosedOpportunitiesForOwner();
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _publicProfileProvider = context.read<OrganizationPublicProfileProvider>();
  }

  @override
  void dispose() {
    // Never leaves stale data behind for the next Company Profile screen
    // opened (possibly for a different organization).
    _publicProfileProvider.reset();
    super.dispose();
  }

  bool get _isOwner {
    final authRole = context.read<AuthProvider>().user?.role;
    final ownId = context.read<OrganizationProfileProvider>().profile?.id;
    return authRole == 'organization' && ownId == widget.organizationId;
  }

  Future<void> _refresh() {
    final provider = context.read<OrganizationPublicProfileProvider>();
    return Future.wait([
      provider.load(widget.organizationId, forceRefresh: true),
      if (_isOwner) provider.loadClosedOpportunitiesForOwner(forceRefresh: true),
    ]);
  }

  Future<void> _editProfile() async {
    await context.push(AppRoutes.organizationProfileEdit);
    if (!mounted) return;
    // The Edit Profile screen (text fields, and the Company Logo) writes
    // directly to `OrganizationProfileProvider.profile` -- a separate
    // state object from this screen's own
    // `OrganizationPublicProfileProvider`, so a real save there would
    // otherwise never be reflected here until a manual pull-to-refresh.
    // Always refreshing on return (whether the edit was saved or
    // cancelled) is a single harmless GET either way, and guarantees
    // this screen never shows stale data after a real edit.
    _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<OrganizationPublicProfileProvider>();
    final isOwner = _isOwner;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Company Profile'),
        actions: const [ThemeToggleSurface()],
      ),
      body: SafeArea(child: _buildBody(provider, isOwner)),
    );
  }

  Widget _buildBody(OrganizationPublicProfileProvider provider, bool isOwner) {
    if (provider.profile == null && provider.isLoadingProfile) {
      return const AppSkeletonList();
    }

    if (provider.profile == null && provider.profileErrorMessage != null) {
      return AppErrorView(
        message: provider.profileErrorMessage!,
        onRetry: _refresh,
      );
    }

    final profile = provider.profile;
    if (profile == null) {
      return const AppEmptyView(
        icon: Icons.apartment_outlined,
        title: 'Company Not Found',
        message: 'This company profile is no longer available.',
      );
    }

    return RefreshIndicator(
      onRefresh: _refresh,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          return SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.symmetric(
              horizontal: width >= _twoColumnBreakpoint
                  ? AppSpacing.xl
                  : AppSpacing.screenHorizontal,
              vertical: AppSpacing.md,
            ),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: _maxContentWidth),
                child: _Entrance(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _HeroSection(
                        profile: profile,
                        isOwner: isOwner,
                        onEditProfile: _editProfile,
                      ),
                      const SizedBox(height: AppSpacing.md),
                      _AboutSection(profile: profile, isOwner: isOwner),
                      const SizedBox(height: AppSpacing.md),
                      _CompanyDetailsSection(profile: profile, width: width),
                      const SizedBox(height: AppSpacing.md),
                      _OpenOpportunitiesSection(
                        opportunities: provider.openOpportunities,
                        isLoading: provider.isLoadingOpportunities,
                        errorMessage: provider.opportunitiesErrorMessage,
                        isOwner: isOwner,
                        onRetry: () => provider.load(
                          widget.organizationId,
                          forceRefresh: true,
                        ),
                        width: width,
                      ),
                      if (isOwner) ...[
                        const SizedBox(height: AppSpacing.md),
                        const _ClosedOpportunitiesSection(),
                      ],
                      const SizedBox(height: AppSpacing.md),
                      _UpdatesSection(
                        organizationId: widget.organizationId,
                        posts: provider.posts,
                        isLoading: provider.isLoadingPosts,
                        errorMessage: provider.postsErrorMessage,
                        isOwner: isOwner,
                      ),
                      const SizedBox(height: AppSpacing.xl),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _Entrance extends StatelessWidget {
  const _Entrance({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final duration = AppMotion.reduced(context, AppMotion.slow);

    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: duration,
      curve: AppMotion.entrance,
      builder: (context, t, child) => Opacity(
        opacity: t,
        child: Transform.translate(
          offset: Offset(0, (1 - t) * 8),
          child: child,
        ),
      ),
      child: child,
    );
  }
}

class _HeroSection extends StatelessWidget {
  const _HeroSection({
    required this.profile,
    required this.isOwner,
    required this.onEditProfile,
  });

  final OrganizationProfileModel profile;
  final bool isOwner;
  final VoidCallback onEditProfile;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final subtitleParts = [
      _organizationTypeLabel(profile.organizationType),
      if (profile.location != null) profile.location!.canonicalName,
    ];

    return AppCard(
      borderColor: AppColors.secondaryLight,
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              AppAvatar(
                imageUrl: profile.logoUrl,
                name: profile.organizationName,
                size: 64,
                fallbackIcon: Icons.apartment_outlined,
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      profile.organizationName,
                      style: textTheme.headlineSmall,
                    ),
                    const SizedBox(height: AppSpacing.xxs),
                    Text(
                      subtitleParts.join(' • '),
                      style: textTheme.bodyMedium?.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                    if (profile.website != null &&
                        profile.website!.trim().isNotEmpty) ...[
                      const SizedBox(height: AppSpacing.xxs),
                      Row(
                        children: [
                          Icon(
                            Icons.link_outlined,
                            size: 14,
                            color: AppColors.info,
                          ),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              profile.website!,
                              overflow: TextOverflow.ellipsis,
                              style: textTheme.bodySmall?.copyWith(
                                color: AppColors.info,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          if (isOwner) ...[
            const SizedBox(height: AppSpacing.md),
            PrimaryButton(
              label: 'Edit Profile',
              icon: Icons.edit_outlined,
              onPressed: onEditProfile,
            ),
          ],
        ],
      ),
    );
  }
}

class _AboutSection extends StatelessWidget {
  const _AboutSection({required this.profile, required this.isOwner});

  final OrganizationProfileModel profile;
  final bool isOwner;

  @override
  Widget build(BuildContext context) {
    final description = profile.description?.trim();
    final hasDescription = description != null && description.isNotEmpty;

    return AppCard(
      borderColor: AppColors.secondaryLight,
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SectionHeader(title: 'About'),
          const SizedBox(height: AppSpacing.xs),
          if (hasDescription)
            Text(description, style: Theme.of(context).textTheme.bodyMedium)
          else
            Text(
              isOwner
                  ? 'Add a company description so candidates can learn more '
                        'about you — edit your profile to add one.'
                  : 'This organization hasn\'t added a description yet.',
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: AppColors.textSecondary),
            ),
        ],
      ),
    );
  }
}

class _CompanyDetailsSection extends StatelessWidget {
  const _CompanyDetailsSection({required this.profile, required this.width});

  final OrganizationProfileModel profile;
  final double width;

  @override
  Widget build(BuildContext context) {
    final fields = [
      DetailField('Type', _organizationTypeLabel(profile.organizationType)),
      DetailField(
        'Industry',
        profile.industry?.trim().isNotEmpty == true
            ? profile.industry!
            : 'Not specified',
      ),
      DetailField(
        'Location',
        profile.location?.canonicalName ?? 'Not specified',
      ),
      DetailField(
        'Phone',
        profile.phone?.trim().isNotEmpty == true
            ? profile.phone!
            : 'Not specified',
      ),
    ];

    return AppCard(
      borderColor: AppColors.secondaryLight,
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SectionHeader(title: 'Company Details'),
          const SizedBox(height: AppSpacing.xs),
          DetailGrid(
            fields: fields,
            width: width,
            twoColumnBreakpoint: _twoColumnBreakpoint,
          ),
        ],
      ),
    );
  }
}

/// A tappable "Title (count) [chevron]" header, shared by the Open and
/// Closed Opportunities accordion sections (Company Profile Polish
/// phase) -- the whole row is the tap target, and the chevron rotates
/// smoothly (`AppMotion`) rather than swapping icons.
class _AccordionHeader extends StatelessWidget {
  const _AccordionHeader({
    required this.title,
    required this.count,
    required this.expanded,
    required this.onTap,
  });

  final String title;
  final int count;
  final bool expanded;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return InkWell(
      onTap: onTap,
      borderRadius: AppRadius.smallRadius,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
        child: Row(
          children: [
            Expanded(
              child: Text('$title ($count)', style: textTheme.titleLarge),
            ),
            AnimatedRotation(
              turns: expanded ? 0.5 : 0,
              duration: AppMotion.reduced(context, AppMotion.fast),
              curve: AppMotion.standard,
              child: const Icon(Icons.expand_more_rounded),
            ),
          ],
        ),
      ),
    );
  }
}

/// Open Opportunities (Company Profile Polish phase) -- a collapsible
/// accordion (default expanded, per spec) whose own body additionally
/// shows at most [_initialVisibleCount] rows with a "View all N" / "Show
/// less" toggle once there are more, so a large Organization's profile
/// never renders dozens of cards permanently and pushes Updates &
/// Achievements far below the fold. No fake pagination -- the backend
/// endpoint this reuses (`GET /opportunities?organization_id=X`) is not
/// paginated at this call site (a generous `perPage: 50` is requested up
/// front), so "View all" only ever reveals real, already-loaded rows.
class _OpenOpportunitiesSection extends StatefulWidget {
  const _OpenOpportunitiesSection({
    required this.opportunities,
    required this.isLoading,
    required this.errorMessage,
    required this.isOwner,
    required this.onRetry,
    required this.width,
  });

  final List<OpportunityModel> opportunities;
  final bool isLoading;
  final String? errorMessage;
  final bool isOwner;
  final VoidCallback onRetry;
  final double width;

  @override
  State<_OpenOpportunitiesSection> createState() =>
      _OpenOpportunitiesSectionState();
}

const _initialVisibleCount = 4;

class _OpenOpportunitiesSectionState extends State<_OpenOpportunitiesSection> {
  bool _sectionExpanded = true;
  bool _showAll = false;

  @override
  Widget build(BuildContext context) {
    final opportunities = widget.opportunities;
    final hasMore = opportunities.length > _initialVisibleCount;
    final visible = (!_showAll && hasMore)
        ? opportunities.take(_initialVisibleCount).toList()
        : opportunities;

    return AppCard(
      borderColor: AppColors.secondaryLight,
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _AccordionHeader(
            title: 'Open Opportunities',
            count: opportunities.length,
            expanded: _sectionExpanded,
            onTap: () => setState(() => _sectionExpanded = !_sectionExpanded),
          ),
          AnimatedSize(
            duration: AppMotion.reduced(context, AppMotion.normal),
            curve: AppMotion.standard,
            alignment: Alignment.topCenter,
            child: !_sectionExpanded
                ? const SizedBox(width: double.infinity)
                : Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.xs),
                    child: _buildBody(context, visible, hasMore),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody(
    BuildContext context,
    List<OpportunityModel> visible,
    bool hasMore,
  ) {
    if (widget.isLoading && widget.opportunities.isEmpty) {
      return const AppLoading(compact: true);
    }
    if (widget.errorMessage != null && widget.opportunities.isEmpty) {
      return AppErrorView(
        message: widget.errorMessage!,
        compact: true,
        onRetry: widget.onRetry,
      );
    }
    if (widget.opportunities.isEmpty) {
      return Text(
        'No open opportunities right now.',
        style: Theme.of(
          context,
        ).textTheme.bodyMedium?.copyWith(color: AppColors.textSecondary),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < visible.length; i++) ...[
          if (i > 0) const SizedBox(height: AppSpacing.sm),
          _OpenOpportunityTile(opportunity: visible[i], isOwner: widget.isOwner),
        ],
        if (hasMore) ...[
          const SizedBox(height: AppSpacing.sm),
          Center(
            child: TextButton(
              onPressed: () => setState(() => _showAll = !_showAll),
              child: Text(
                _showAll
                    ? 'Show less'
                    : 'View all ${widget.opportunities.length}',
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _OpenOpportunityTile extends StatelessWidget {
  const _OpenOpportunityTile({
    required this.opportunity,
    required this.isOwner,
  });

  final OpportunityModel opportunity;
  final bool isOwner;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return AppCard(
      borderColor: AppColors.border,
      padding: const EdgeInsets.all(AppSpacing.md),
      interactive: true,
      onTap: () => context.push(
        isOwner
            ? AppRoutes.organizationOpportunityDetails(opportunity.id)
            : AppRoutes.studentOpportunityDetails(opportunity.id),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  opportunity.title,
                  style: textTheme.titleSmall,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: AppSpacing.xxs),
                Wrap(
                  spacing: AppSpacing.xs,
                  runSpacing: AppSpacing.xxs,
                  children: [
                    StatusChip(
                      label:
                          opportunityTypeLabels[opportunity.opportunityType] ??
                          opportunity.opportunityType,
                      type: AppStatusType.info,
                      compact: true,
                    ),
                    StatusChip(
                      label: opportunity.workMode,
                      type: AppStatusType.neutral,
                      compact: true,
                    ),
                  ],
                ),
              ],
            ),
          ),
          Icon(Icons.chevron_right_rounded, color: AppColors.textMuted),
        ],
      ),
    );
  }
}

const _closedDatePresetLabels = {
  'all': 'All',
  'last_30_days': '30 Days',
  'last_3_months': '3 Months',
  'last_6_months': '6 Months',
  'this_year': 'This Year',
  'older': 'Older',
};

const _closedSortLabels = {'newest': 'Newest first', 'oldest': 'Oldest first'};

/// Closed Opportunities (Company Profile Polish phase; Closed
/// Opportunities Scalability Polish for the date filtering/sorting/
/// pagination below) -- owner-only, collapsed by default so it never
/// clutters the profile (spec section 4). Backend-paginated ("Load
/// More"), never an unbounded historical list rendered/loaded all at
/// once. Each row shows the real `can_delete` state truthfully: a
/// genuinely safe-to-delete closed Opportunity gets a working "Delete
/// Permanently" action; one with real recruitment history gets a plain
/// explanatory message instead of a dead/hidden button pretending the
/// action doesn't exist. The backend independently re-enforces both the
/// `closed` status and the no-history rule on every request regardless
/// of what this screen shows.
class _ClosedOpportunitiesSection extends StatefulWidget {
  const _ClosedOpportunitiesSection();

  @override
  State<_ClosedOpportunitiesSection> createState() =>
      _ClosedOpportunitiesSectionState();
}

class _ClosedOpportunitiesSectionState
    extends State<_ClosedOpportunitiesSection> {
  bool _expanded = false;

  /// True once the user has tapped "Custom" -- reveals the From/To
  /// pickers even before either date has actually been chosen yet
  /// (`provider.closedFromDate`/`closedToDate` both still `null` at that
  /// point). Once a filter is genuinely applied, [_CustomDateRangeRow]
  /// stays visible purely because the provider's own state says so, so
  /// this flag only matters for that brief in-between moment.
  bool _showCustomRangePickers = false;

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<OrganizationPublicProfileProvider>();

    return AppCard(
      borderColor: AppColors.secondaryLight,
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _AccordionHeader(
            title: 'Closed Opportunities',
            count: provider.totalClosedOpportunities,
            expanded: _expanded,
            onTap: () => setState(() => _expanded = !_expanded),
          ),
          AnimatedSize(
            duration: AppMotion.reduced(context, AppMotion.normal),
            curve: AppMotion.standard,
            alignment: Alignment.topCenter,
            child: !_expanded
                ? const SizedBox(width: double.infinity)
                : Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.xs),
                    child: _buildExpandedBody(context, provider),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildExpandedBody(
    BuildContext context,
    OrganizationPublicProfileProvider provider,
  ) {
    final isCustomActive =
        provider.closedFromDate != null || provider.closedToDate != null;
    final isFiltered = provider.closedDatePreset != 'all' || isCustomActive;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ClosedOpportunitiesFilterBar(
          activePreset: provider.closedDatePreset,
          isCustomActive: isCustomActive || _showCustomRangePickers,
          sort: provider.closedSort,
          onPresetSelected: (preset) {
            setState(() => _showCustomRangePickers = false);
            provider.applyClosedOpportunitiesDatePreset(preset);
          },
          onCustomSelected: () =>
              setState(() => _showCustomRangePickers = true),
          onSortChanged: provider.applyClosedOpportunitiesSort,
        ),
        if (isCustomActive || _showCustomRangePickers) ...[
          const SizedBox(height: AppSpacing.xs),
          _CustomDateRangeRow(
            from: provider.closedFromDate,
            to: provider.closedToDate,
            onChanged: (from, to) => provider
                .applyClosedOpportunitiesDateRange(from: from, to: to),
          ),
        ],
        const SizedBox(height: AppSpacing.sm),
        if (isFiltered &&
            !provider.isLoadingClosedOpportunities &&
            provider.closedOpportunities.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.xs),
            child: Text(
              'Showing ${provider.closedOpportunities.length} of '
              '${provider.closedOpportunitiesFilteredTotal}',
              style: Theme.of(
                context,
              ).textTheme.labelSmall?.copyWith(color: AppColors.textMuted),
            ),
          ),
        _buildListBody(context, provider),
      ],
    );
  }

  Widget _buildListBody(
    BuildContext context,
    OrganizationPublicProfileProvider provider,
  ) {
    if (provider.isLoadingClosedOpportunities &&
        provider.closedOpportunities.isEmpty) {
      return const AppLoading(compact: true);
    }
    if (provider.closedOpportunitiesErrorMessage != null &&
        provider.closedOpportunities.isEmpty) {
      return AppErrorView(
        message: provider.closedOpportunitiesErrorMessage!,
        compact: true,
        onRetry: () =>
            provider.loadClosedOpportunitiesForOwner(forceRefresh: true),
      );
    }
    if (provider.closedOpportunities.isEmpty) {
      return Text(
        provider.totalClosedOpportunities == 0
            ? 'No closed opportunities yet.'
            : 'No closed opportunities in this period.',
        style: Theme.of(
          context,
        ).textTheme.bodyMedium?.copyWith(color: AppColors.textSecondary),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < provider.closedOpportunities.length; i++) ...[
          if (i > 0) const SizedBox(height: AppSpacing.sm),
          _ClosedOpportunityTile(opportunity: provider.closedOpportunities[i]),
        ],
        if (provider.hasMoreClosedOpportunities) ...[
          const SizedBox(height: AppSpacing.sm),
          Center(
            child: provider.isLoadingMoreClosedOpportunities
                ? const AppLoading(compact: true)
                : SecondaryButton(
                    label: 'Load More',
                    onPressed: provider.loadMoreClosedOpportunities,
                  ),
          ),
        ],
        if (provider.loadMoreClosedOpportunitiesErrorMessage != null) ...[
          const SizedBox(height: AppSpacing.xs),
          Text(
            provider.loadMoreClosedOpportunitiesErrorMessage!,
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.labelSmall?.copyWith(color: AppColors.error),
          ),
        ],
      ],
    );
  }
}

/// The date-preset chip row + custom-range toggle + sort dropdown --
/// deliberately one compact, horizontally-scrollable row on any width
/// (mirrors `organization_opportunities_screen.dart`'s own status-chip
/// row) rather than a full analytics-style filter panel.
class _ClosedOpportunitiesFilterBar extends StatelessWidget {
  const _ClosedOpportunitiesFilterBar({
    required this.activePreset,
    required this.isCustomActive,
    required this.sort,
    required this.onPresetSelected,
    required this.onCustomSelected,
    required this.onSortChanged,
  });

  final String activePreset;
  final bool isCustomActive;
  final String sort;
  final ValueChanged<String> onPresetSelected;
  final VoidCallback onCustomSelected;
  final ValueChanged<String> onSortChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final entry in _closedDatePresetLabels.entries) ...[
                _FilterChoiceChip(
                  label: entry.value,
                  selected: !isCustomActive && activePreset == entry.key,
                  onSelected: () => onPresetSelected(entry.key),
                ),
                const SizedBox(width: AppSpacing.xs),
              ],
              _FilterChoiceChip(
                label: 'Custom',
                selected: isCustomActive,
                onSelected: onCustomSelected,
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Sort:',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: AppColors.textSecondary),
            ),
            const SizedBox(width: AppSpacing.xxs),
            DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: sort,
                isDense: true,
                borderRadius: BorderRadius.circular(12),
                items: [
                  for (final entry in _closedSortLabels.entries)
                    DropdownMenuItem(value: entry.key, child: Text(entry.value)),
                ],
                onChanged: (value) {
                  if (value != null) onSortChanged(value);
                },
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _FilterChoiceChip extends StatelessWidget {
  const _FilterChoiceChip({
    required this.label,
    required this.selected,
    required this.onSelected,
  });

  final String label;
  final bool selected;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onSelected(),
      selectedColor: AppColors.primaryContainer,
      backgroundColor: AppColors.surface,
      side: BorderSide(color: selected ? AppColors.primary : AppColors.border),
      labelStyle: TextStyle(
        color: selected ? AppColors.primaryDark : AppColors.textSecondary,
        fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
      ),
    );
  }
}

/// The "Custom" range's own From/To pickers -- Flutter's built-in
/// `showDatePicker` (already used elsewhere in this app, e.g. Application
/// Deadline on the Opportunity form), never a new dependency. Filters
/// strictly against `closed_at` on the backend, never `created_at`.
class _CustomDateRangeRow extends StatelessWidget {
  const _CustomDateRangeRow({
    required this.from,
    required this.to,
    required this.onChanged,
  });

  final DateTime? from;
  final DateTime? to;
  final void Function(DateTime? from, DateTime? to) onChanged;

  Future<void> _pickFrom(BuildContext context) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: from ?? now,
      firstDate: DateTime(2000),
      lastDate: now,
    );
    if (picked == null) return;
    onChanged(picked, to);
  }

  Future<void> _pickTo(BuildContext context) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: to ?? now,
      firstDate: from ?? DateTime(2000),
      lastDate: now,
    );
    if (picked == null) return;
    onChanged(from, picked);
  }

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: AppSpacing.xs,
      runSpacing: AppSpacing.xs,
      children: [
        SecondaryButton(
          label: from == null ? 'From' : formatDate(from!),
          icon: Icons.calendar_today_outlined,
          onPressed: () => _pickFrom(context),
        ),
        SecondaryButton(
          label: to == null ? 'To' : formatDate(to!),
          icon: Icons.calendar_today_outlined,
          onPressed: () => _pickTo(context),
        ),
      ],
    );
  }
}

class _ClosedOpportunityTile extends StatelessWidget {
  const _ClosedOpportunityTile({required this.opportunity});

  final OpportunityModel opportunity;

  Future<void> _delete(BuildContext context) async {
    final confirmed = await showAppConfirmationDialog(
      context,
      title: 'Delete Opportunity?',
      message:
          'This opportunity has no recruitment history. Deleting it '
          'permanently cannot be undone.',
      confirmLabel: 'Delete Permanently',
      type: AppConfirmationType.danger,
    );
    if (!confirmed) return;
    if (!context.mounted) return;

    final provider = context.read<OrganizationPublicProfileProvider>();
    final success = await provider.deleteClosedOpportunity(opportunity.id);
    if (!context.mounted) return;

    if (!success && provider.deleteClosedOpportunityErrorMessage != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(provider.deleteClosedOpportunityErrorMessage!)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final isBusy = context.select<OrganizationPublicProfileProvider, bool>(
      (p) => p.isBusyWithClosedOpportunity(opportunity.id),
    );

    return AppCard(
      borderColor: AppColors.border,
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      opportunity.title,
                      style: textTheme.titleSmall,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: AppSpacing.xxs),
                    StatusChip(
                      label: 'Closed',
                      type: AppStatusType.neutral,
                      compact: true,
                    ),
                    const SizedBox(height: AppSpacing.xxs),
                    // Closed Opportunities Scalability Polish: the real
                    // closure timestamp -- never a fabricated date for a
                    // legacy row whose true closure time can't be proven
                    // (see the backend migration's own doc comment).
                    Text(
                      opportunity.closedAt != null
                          ? 'Closed ${formatDate(opportunity.closedAt!)}'
                          : 'Closure date unavailable',
                      style: textTheme.labelSmall?.copyWith(
                        color: AppColors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'View',
                icon: const Icon(Icons.visibility_outlined),
                onPressed: () => context.push(
                  AppRoutes.organizationOpportunityDetails(opportunity.id),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          if (opportunity.canDelete)
            isBusy
                ? const Padding(
                    padding: EdgeInsets.symmetric(vertical: AppSpacing.xs),
                    child: Center(
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  )
                : SecondaryButton(
                    label: 'Delete Permanently',
                    icon: Icons.delete_outline_rounded,
                    onPressed: () => _delete(context),
                  )
          else
            Text(
              'This opportunity has recruitment history and cannot be '
              'permanently deleted.',
              style: textTheme.bodySmall?.copyWith(color: AppColors.textMuted),
            ),
        ],
      ),
    );
  }
}

class _UpdatesSection extends StatelessWidget {
  const _UpdatesSection({
    required this.organizationId,
    required this.posts,
    required this.isLoading,
    required this.errorMessage,
    required this.isOwner,
  });

  final int organizationId;
  final List<OrganizationPostModel> posts;
  final bool isLoading;
  final String? errorMessage;
  final bool isOwner;

  Future<void> _createUpdate(BuildContext context) async {
    await showEditPostSheet(context);
  }

  @override
  Widget build(BuildContext context) {
    return AppCard(
      borderColor: AppColors.secondaryLight,
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionHeader(
            title: 'Updates & Achievements',
            trailing: isOwner
                ? TextButton.icon(
                    onPressed: () => _createUpdate(context),
                    icon: const Icon(Icons.add_rounded, size: 18),
                    label: const Text('Create Update'),
                  )
                : null,
          ),
          const SizedBox(height: AppSpacing.xs),
          if (isLoading && posts.isEmpty)
            const AppLoading(compact: true)
          else if (errorMessage != null && posts.isEmpty)
            AppErrorView(message: errorMessage!, compact: true)
          else if (posts.isEmpty)
            Text(
              isOwner
                  ? 'Share your first company update.'
                  : 'No updates published yet.',
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: AppColors.textSecondary),
            )
          else
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < posts.length; i++) ...[
                  if (i > 0) const SizedBox(height: AppSpacing.sm),
                  _PostCard(post: posts[i], isOwner: isOwner),
                ],
              ],
            ),
        ],
      ),
    );
  }
}

class _PostCard extends StatelessWidget {
  const _PostCard({required this.post, required this.isOwner});

  final OrganizationPostModel post;
  final bool isOwner;

  Future<void> _edit(BuildContext context) async {
    await showEditPostSheet(context, post: post);
  }

  Future<void> _delete(BuildContext context) async {
    final confirmed = await showAppConfirmationDialog(
      context,
      title: 'Delete Update?',
      message:
          'This update will be permanently removed. This cannot be undone.',
      confirmLabel: 'Delete',
      type: AppConfirmationType.danger,
    );
    if (!confirmed) return;
    if (!context.mounted) return;

    final provider = context.read<OrganizationPublicProfileProvider>();
    final success = await provider.deletePost(post.id);
    if (!context.mounted) return;

    if (!success && provider.postActionErrorMessage != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(provider.postActionErrorMessage!)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final provider = context.watch<OrganizationPublicProfileProvider>();
    final isBusy = provider.isBusyWithPost(post.id);
    final title = post.title?.trim();

    return AppCard(
      borderColor: AppColors.border,
      padding: const EdgeInsets.all(AppSpacing.md),
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
                    if (title != null && title.isNotEmpty)
                      Text(title, style: textTheme.titleSmall),
                    Text(
                      formatDate(post.createdAt),
                      style: textTheme.labelSmall?.copyWith(
                        color: AppColors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              if (isOwner)
                isBusy
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : PopupMenuButton<String>(
                        icon: const Icon(Icons.more_vert_rounded),
                        onSelected: (value) {
                          if (value == 'edit') _edit(context);
                          if (value == 'delete') _delete(context);
                        },
                        itemBuilder: (context) => const [
                          PopupMenuItem(value: 'edit', child: Text('Edit')),
                          PopupMenuItem(value: 'delete', child: Text('Delete')),
                        ],
                      ),
            ],
          ),
          const SizedBox(height: AppSpacing.xxs),
          Text(post.body, style: textTheme.bodyMedium),
          if (post.imageUrl != null) ...[
            const SizedBox(height: AppSpacing.sm),
            _PostImage(url: post.imageUrl!),
          ],
        ],
      ),
    );
  }
}

/// A post's optional single image (Company Profile Polish phase) --
/// aspect-ratio constrained (never stretched, never allowed to dominate
/// the viewport on a wide desktop screen), rounded to match the design
/// system, and network-safe: a broken/unreachable image degrades to a
/// plain placeholder rather than a raw Flutter error.
class _PostImage extends StatelessWidget {
  const _PostImage({required this.url});

  final String url;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: AppRadius.mediumRadius,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 360),
        child: AspectRatio(
          aspectRatio: 16 / 9,
          child: Image.network(
            url,
            fit: BoxFit.cover,
            width: double.infinity,
            errorBuilder: (context, error, stackTrace) => Container(
              color: AppColors.surfaceVariant,
              alignment: Alignment.center,
              child: Icon(
                Icons.broken_image_outlined,
                color: AppColors.textMuted,
              ),
            ),
            loadingBuilder: (context, child, progress) {
              if (progress == null) return child;
              return Container(
                color: AppColors.surfaceVariant,
                alignment: Alignment.center,
                child: const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
