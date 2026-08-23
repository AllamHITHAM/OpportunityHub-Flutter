import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_motion.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_shadows.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/app_widgets.dart';
import '../../../models/user_model.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/notification_provider.dart';
import '../../../providers/student_applications_provider.dart';
import '../../../providers/student_cv_provider.dart';
import '../../../providers/student_opportunities_provider.dart';
import '../../../routes/app_routes.dart';
import '../../notifications/presentation/notification_bell_action.dart';
import '../../opportunities/presentation/opportunity_card.dart';
import '../../opportunities/presentation/opportunity_display.dart';
import '../../opportunities/presentation/opportunity_filter_sheet.dart';

/// Breakpoints for the discovery grid/sidebar — matches the four bands
/// called out in UI Phase 1.2 exactly: mobile (~375–430px, 1 column, no
/// sidebar), tablet (600–899px, 2 columns, no sidebar), desktop/tablet
/// (900–1199px, persistent sidebar + 2 columns), and wide desktop
/// (>=1200px, persistent sidebar + 3 columns).
const _wideBreakpoint = 1200.0;
const _sidebarBreakpoint = 900.0;
const _tabletBreakpoint = 600.0;
const _sidebarWidth = 272.0;

/// The Student "Explore" home — a browsing/discovery-first landing page for
/// publicly available opportunities, redesigned in UI Phase 1.2 to match a
/// real job-marketplace's density: a persistent filter sidebar and a rich,
/// colored opportunity-card grid dominate wide Web, rather than a tall
/// hero or a centered narrow dashboard.
///
/// Personal/profile content (CVs, Skills, Education Verification) is not
/// shown here — those routes/providers still exist untouched and are
/// reachable from the avatar in the top bar, which now navigates to a
/// minimal [StudentProfileScreen] shell (UI Phase 1.2) rather than a popup
/// menu. This screen reads [StudentOpportunitiesProvider] (search/filter/
/// browse), [StudentApplicationsProvider] (real applications-count badge
/// and per-card "already applied" state), and [StudentCvProvider] (needed
/// so the real Apply flow has CVs ready the moment a card's Apply button
/// is used) — no new endpoint, no fabricated data.
class StudentHomeScreen extends StatefulWidget {
  const StudentHomeScreen({super.key});

  @override
  State<StudentHomeScreen> createState() => _StudentHomeScreenState();
}

class _StudentHomeScreenState extends State<StudentHomeScreen>
    with SingleTickerProviderStateMixin {
  final _searchController = TextEditingController();
  Timer? _debounce;

  late final AnimationController _greetingController;
  late final Animation<double> _greetingOpacity;
  late final Animation<Offset> _greetingSlide;

  @override
  void initState() {
    super.initState();

    final reducedMotion = SchedulerBinding
        .instance
        .platformDispatcher
        .accessibilityFeatures
        .disableAnimations;
    _greetingController = AnimationController(
      vsync: this,
      duration: reducedMotion ? const Duration(milliseconds: 1) : AppMotion.fast,
    );
    _greetingOpacity = CurvedAnimation(
      parent: _greetingController,
      curve: AppMotion.entrance,
    );
    _greetingSlide =
        Tween<Offset>(
          begin: reducedMotion ? Offset.zero : const Offset(0, -0.06),
          end: Offset.zero,
        ).animate(
          CurvedAnimation(parent: _greetingController, curve: AppMotion.entrance),
        );
    _greetingController.forward();

    _searchController.text = context.read<StudentOpportunitiesProvider>().keyword;

    // Deferred to the post-frame callback — see
    // StudentOpportunitiesScreen.initState for why calling this directly
    // here would violate Flutter's build-phase constraints. Each provider
    // already guards against duplicate concurrent loads on its own, so
    // revisiting this screen is always safe.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<NotificationProvider>().load();
      context.read<StudentOpportunitiesProvider>().loadOpportunities();
      context.read<StudentApplicationsProvider>().loadApplications();
      // Not displayed on Explore itself, but the card grid's real Apply
      // button (via ApplyBottomSheet) reads this provider's already-loaded
      // CV list — without this, tapping Apply here would incorrectly show
      // "No CV Yet" for a student who really does have one.
      context.read<StudentCvProvider>().loadCvs();
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    _greetingController.dispose();
    super.dispose();
  }

  Future<void> _onRefresh() {
    return Future.wait([
      context.read<StudentOpportunitiesProvider>().loadOpportunities(
        forceRefresh: true,
      ),
      context.read<StudentApplicationsProvider>().loadApplications(
        forceRefresh: true,
      ),
      context.read<StudentCvProvider>().loadCvs(forceRefresh: true),
    ]);
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      if (!mounted) return;
      final provider = context.read<StudentOpportunitiesProvider>();
      provider.updateKeyword(value.trim());
      provider.loadOpportunities(forceRefresh: true);
    });
  }

  Future<void> _openFilters() {
    final provider = context.read<StudentOpportunitiesProvider>();
    return showOpportunityFilterSheet(context, provider);
  }

  void _openDetails(int id) {
    context.push(AppRoutes.studentOpportunityDetails(id));
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = context.watch<AuthProvider>();
    final applicationsCount = context.watch<StudentApplicationsProvider>().applications.length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('OpportunityHub'),
        actions: [
          const ThemeToggleButton(),
          const NotificationBellAction(),
          _ProfileNavButton(user: authProvider.user),
          const SizedBox(width: AppSpacing.xs),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(52),
          child: _ExploreNavTabs(applicationsCount: applicationsCount),
        ),
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            final sidebarVisible = width >= _sidebarBreakpoint;
            final columns = width >= _wideBreakpoint
                ? 3
                : (width >= _tabletBreakpoint ? 2 : 1);

            final content = RefreshIndicator(
              onRefresh: _onRefresh,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: EdgeInsets.fromLTRB(
                  sidebarVisible ? AppSpacing.lg : AppSpacing.screenHorizontal,
                  AppSpacing.md,
                  sidebarVisible ? AppSpacing.xl : AppSpacing.screenHorizontal,
                  AppSpacing.screenVertical,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    FadeTransition(
                      opacity: _greetingOpacity,
                      child: SlideTransition(
                        position: _greetingSlide,
                        child: _CompactGreeting(
                          user: authProvider.user,
                          showVisual: sidebarVisible,
                        ),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    _ExploreSearchBar(
                      controller: _searchController,
                      onChanged: _onSearchChanged,
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    _FilterChipsRow(
                      showFiltersTrigger: !sidebarVisible,
                      onOpenFilters: _openFilters,
                    ),
                    const SizedBox(height: AppSpacing.md),
                    _OpportunitiesSection(
                      columns: columns,
                      onOpenDetails: _openDetails,
                    ),
                  ],
                ),
              ),
            );

            if (!sidebarVisible) return content;

            return Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  width: _sidebarWidth,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      border: Border(
                        right: BorderSide(color: AppColors.border),
                      ),
                    ),
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(AppSpacing.md),
                      child: _FilterSidebar(
                        key: _sidebarKey(context),
                      ),
                    ),
                  ),
                ),
                Expanded(child: content),
              ],
            );
          },
        ),
      ),
    );
  }

  /// Rebuilds the sidebar's local text-field state whenever the underlying
  /// filters change from *outside* the sidebar itself (Reset All, an
  /// active-filter chip's remove button, or the narrow-mode filter sheet)
  /// — a plain, standard Flutter technique: changing a widget's `key`
  /// forces a fresh `State`, so [_FilterSidebarState]'s controllers always
  /// re-sync from the provider rather than silently going stale.
  Key _sidebarKey(BuildContext context) {
    final provider = context.watch<StudentOpportunitiesProvider>();
    return ValueKey('${provider.location}|${provider.fieldOfStudy}');
  }
}

String _greetingForHour(int hour) {
  if (hour < 12) return 'Good morning';
  if (hour < 17) return 'Good afternoon';
  return 'Good evening';
}

/// The avatar in the top bar — Explore's real Profile entry point (UI
/// Phase 1.2). Navigates to the minimal [StudentProfileScreen] shell,
/// which is also where Logout now lives instead of a large button at the
/// bottom of this page.
class _ProfileNavButton extends StatelessWidget {
  const _ProfileNavButton({required this.user});

  final UserModel? user;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxs),
      child: InkWell(
        onTap: () => context.push(AppRoutes.studentProfile),
        customBorder: const CircleBorder(),
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: AppAvatar(name: user?.name, size: 32),
        ),
      ),
    );
  }
}

/// The horizontal nav strip under the app bar: Explore (this screen,
/// always shown active) plus the two other real student destinations that
/// belong in top-level navigation rather than the main content area —
/// Applications and Invitations. Horizontally scrollable so it can never
/// overflow at any width, from a 375px phone up.
class _ExploreNavTabs extends StatelessWidget {
  const _ExploreNavTabs({required this.applicationsCount});

  final int applicationsCount;

  @override
  Widget build(BuildContext context) {
    return Container(
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screenHorizontal),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            const _NavTab(label: 'Discover', icon: Icons.explore_outlined, isActive: true),
            const SizedBox(width: AppSpacing.xs),
            _NavTab(
              label: 'My Applications',
              icon: Icons.description_outlined,
              badgeCount: applicationsCount,
              onTap: () => context.push(AppRoutes.studentApplications),
            ),
            const SizedBox(width: AppSpacing.xs),
            _NavTab(
              label: 'Invitations',
              icon: Icons.mail_outline_rounded,
              onTap: () => context.push(AppRoutes.studentInvitations),
            ),
          ],
        ),
      ),
    );
  }
}

class _NavTab extends StatelessWidget {
  const _NavTab({
    required this.label,
    required this.icon,
    this.isActive = false,
    this.badgeCount = 0,
    this.onTap,
  });

  final String label;
  final IconData icon;
  final bool isActive;
  final int badgeCount;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final color = isActive ? AppColors.primary : AppColors.textSecondary;

    return InkWell(
      onTap: onTap,
      borderRadius: AppRadius.mediumRadius,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 18, color: color),
                const SizedBox(width: AppSpacing.xxs),
                Text(
                  label,
                  style: textTheme.titleSmall?.copyWith(
                    color: color,
                    fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
                if (badgeCount > 0) ...[
                  const SizedBox(width: AppSpacing.xxs),
                  Badge(label: Text('$badgeCount')),
                ],
              ],
            ),
            const SizedBox(height: 6),
            AnimatedContainer(
              duration: AppMotion.reduced(context, AppMotion.fast),
              height: 2,
              width: 28,
              color: isActive ? AppColors.primary : AppColors.transparent,
            ),
          ],
        ),
      ),
    );
  }
}

/// A compact, single-block greeting — deliberately not a tall hero card.
/// Real name, real time-aware greeting, and a small blue/purple accent bar
/// for personality, without pushing the opportunity grid below the fold.
/// On wide Web (UI Phase 1.3), an optional abstract discovery visual sits
/// to the right — pure gradients/shapes/icons, no external image asset.
class _CompactGreeting extends StatelessWidget {
  const _CompactGreeting({required this.user, required this.showVisual});

  final UserModel? user;
  final bool showVisual;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final name = user?.name.trim();
    final firstName = (name == null || name.isEmpty)
        ? null
        : name.split(RegExp(r'\s+')).first;
    final greeting = _greetingForHour(DateTime.now().hour);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 4,
          height: 36,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [AppColors.primary, AppColors.aiAccent],
            ),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                firstName == null ? '$greeting! 👋' : '$greeting, $firstName 👋',
                style: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
              ),
              Text(
                'Discover your next opportunity — jobs, internships, '
                'scholarships, and more.',
                style: textTheme.bodyMedium?.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
        if (showVisual) ...[
          const SizedBox(width: AppSpacing.md),
          const _DiscoveryVisual(),
        ],
      ],
    );
  }
}

/// A small, abstract discovery visual for the greeting on wide Web —
/// gradients, shapes, and an icon only (career discovery/growth/matching),
/// deliberately not a stock photograph or a hotlinked/remote image. Sized
/// so it never dominates the greeting.
class _DiscoveryVisual extends StatelessWidget {
  const _DiscoveryVisual();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 84,
      height: 64,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned(
            right: 0,
            top: 0,
            child: _glowCircle(56, AppColors.primary.withValues(alpha: 0.14)),
          ),
          Positioned(
            left: 0,
            bottom: 0,
            child: _glowCircle(40, AppColors.aiAccent.withValues(alpha: 0.16)),
          ),
          Container(
            width: 44,
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [AppColors.primary, AppColors.aiAccent],
              ),
              shape: BoxShape.circle,
              boxShadow: AppShadows.card,
            ),
            child: Icon(
              Icons.explore_outlined,
              color: AppColors.textOnPrimary,
              size: 22,
            ),
          ),
        ],
      ),
    );
  }

  Widget _glowCircle(double size, Color color) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
    );
  }
}

/// A prominent, marketplace-style search bar — the same real, server-side
/// keyword search [StudentOpportunitiesScreen] already used, just given
/// more visual weight (elevated surface, larger touch target) to match the
/// reference's search prominence.
class _ExploreSearchBar extends StatelessWidget {
  const _ExploreSearchBar({required this.controller, required this.onChanged});

  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadius.mediumRadius,
        border: Border.all(color: AppColors.border),
        boxShadow: AppShadows.card,
      ),
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxs),
      child: AppSearchField(
        controller: controller,
        hint: 'Search by title, organization, or keyword',
        onChanged: onChanged,
      ),
    );
  }
}

/// A real-filter summary row: an optional "Filters" entry point (shown
/// only when the persistent sidebar is collapsed) plus one removable chip
/// per currently-active [StudentOpportunitiesProvider] filter — every
/// value shown here is a live filter the provider is already applying to
/// its next fetch, never a placeholder/example option.
class _FilterChipsRow extends StatelessWidget {
  const _FilterChipsRow({
    required this.showFiltersTrigger,
    required this.onOpenFilters,
  });

  final bool showFiltersTrigger;
  final VoidCallback onOpenFilters;

  void _clearOne(BuildContext context, StudentOpportunitiesProvider provider, {
    bool clearOpportunityType = false,
    bool clearEmploymentType = false,
    bool clearWorkMode = false,
    bool clearExperienceLevel = false,
    bool clearLocation = false,
    bool clearFieldOfStudy = false,
  }) {
    provider.applyFilters(
      opportunityType: clearOpportunityType ? null : provider.opportunityType,
      employmentType: clearEmploymentType ? null : provider.employmentType,
      workMode: clearWorkMode ? null : provider.workMode,
      experienceLevel: clearExperienceLevel ? null : provider.experienceLevel,
      location: clearLocation ? null : provider.location,
      fieldOfStudy: clearFieldOfStudy ? null : provider.fieldOfStudy,
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<StudentOpportunitiesProvider>();

    if (!showFiltersTrigger && !provider.hasActiveFilters) {
      return const SizedBox.shrink();
    }

    return Wrap(
      spacing: AppSpacing.xs,
      runSpacing: AppSpacing.xs,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (showFiltersTrigger)
          ActionChip(
            avatar: Icon(
              provider.hasActiveFilters ? Icons.filter_alt : Icons.filter_alt_outlined,
              size: 18,
              color: provider.hasActiveFilters ? AppColors.primary : AppColors.textSecondary,
            ),
            label: const Text('Filters'),
            onPressed: onOpenFilters,
            backgroundColor: provider.hasActiveFilters
                ? AppColors.primaryContainer
                : AppColors.surface,
            side: BorderSide(
              color: provider.hasActiveFilters ? AppColors.primary : AppColors.border,
            ),
          ),
        if (provider.opportunityType != null)
          _ActiveFilterChip(
            label: opportunityTypeLabels[provider.opportunityType] ?? provider.opportunityType!,
            onDeleted: () => _clearOne(context, provider, clearOpportunityType: true),
          ),
        if (provider.employmentType != null)
          _ActiveFilterChip(
            label: employmentTypeLabels[provider.employmentType] ?? provider.employmentType!,
            onDeleted: () => _clearOne(context, provider, clearEmploymentType: true),
          ),
        if (provider.workMode != null)
          _ActiveFilterChip(
            label: workModeLabels[provider.workMode] ?? provider.workMode!,
            onDeleted: () => _clearOne(context, provider, clearWorkMode: true),
          ),
        if (provider.experienceLevel != null)
          _ActiveFilterChip(
            label: experienceLevelLabels[provider.experienceLevel] ?? provider.experienceLevel!,
            onDeleted: () => _clearOne(context, provider, clearExperienceLevel: true),
          ),
        if (provider.location != null)
          _ActiveFilterChip(
            label: provider.location!,
            onDeleted: () => _clearOne(context, provider, clearLocation: true),
          ),
        if (provider.fieldOfStudy != null)
          _ActiveFilterChip(
            label: provider.fieldOfStudy!,
            onDeleted: () => _clearOne(context, provider, clearFieldOfStudy: true),
          ),
      ],
    );
  }
}

class _ActiveFilterChip extends StatelessWidget {
  const _ActiveFilterChip({required this.label, required this.onDeleted});

  final String label;
  final VoidCallback onDeleted;

  @override
  Widget build(BuildContext context) {
    return InputChip(
      label: Text(label),
      onDeleted: onDeleted,
      backgroundColor: AppColors.surface,
      side: BorderSide(color: AppColors.border),
      deleteIconColor: AppColors.textSecondary,
    );
  }
}

/// The persistent left Filters panel shown on wide Web (>=900px) — the
/// same six real, backend-documented [StudentOpportunitiesProvider]
/// filters used by [OpportunityFilterSheet] (the narrow-layout fallback),
/// just presented as a standing sidebar with chip/radio-style controls
/// instead of a modal's dropdowns.
class _FilterSidebar extends StatefulWidget {
  const _FilterSidebar({super.key});

  @override
  State<_FilterSidebar> createState() => _FilterSidebarState();
}

class _FilterSidebarState extends State<_FilterSidebar> {
  late final TextEditingController _locationController;
  late final TextEditingController _fieldOfStudyController;

  @override
  void initState() {
    super.initState();
    final provider = context.read<StudentOpportunitiesProvider>();
    _locationController = TextEditingController(text: provider.location ?? '');
    _fieldOfStudyController = TextEditingController(text: provider.fieldOfStudy ?? '');
  }

  @override
  void dispose() {
    _locationController.dispose();
    _fieldOfStudyController.dispose();
    super.dispose();
  }

  void _setSingleValueFilter(
    StudentOpportunitiesProvider provider, {
    String? opportunityType,
    String? employmentType,
    String? workMode,
    String? experienceLevel,
  }) {
    provider.applyFilters(
      opportunityType: opportunityType ?? provider.opportunityType,
      employmentType: employmentType ?? provider.employmentType,
      workMode: workMode ?? provider.workMode,
      experienceLevel: experienceLevel ?? provider.experienceLevel,
      location: provider.location,
      fieldOfStudy: provider.fieldOfStudy,
    );
  }

  void _submitLocation(StudentOpportunitiesProvider provider) {
    final value = _locationController.text.trim();
    provider.applyFilters(
      opportunityType: provider.opportunityType,
      employmentType: provider.employmentType,
      workMode: provider.workMode,
      experienceLevel: provider.experienceLevel,
      location: value.isEmpty ? null : value,
      fieldOfStudy: provider.fieldOfStudy,
    );
  }

  void _submitFieldOfStudy(StudentOpportunitiesProvider provider) {
    final value = _fieldOfStudyController.text.trim();
    provider.applyFilters(
      opportunityType: provider.opportunityType,
      employmentType: provider.employmentType,
      workMode: provider.workMode,
      experienceLevel: provider.experienceLevel,
      location: provider.location,
      fieldOfStudy: value.isEmpty ? null : value,
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<StudentOpportunitiesProvider>();
    final textTheme = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: Text('Filters', style: textTheme.titleMedium)),
            if (provider.hasActiveFilters)
              TextButton(
                onPressed: provider.clearFilters,
                child: const Text('Reset All'),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        _SidebarChipGroup(
          title: 'Opportunity Type',
          options: opportunityTypeLabels,
          selected: provider.opportunityType,
          onSelect: (value) => _setSingleValueFilter(provider, opportunityType: value),
        ),
        _SidebarChipGroup(
          title: 'Employment Type',
          options: employmentTypeLabels,
          selected: provider.employmentType,
          onSelect: (value) => _setSingleValueFilter(provider, employmentType: value),
        ),
        _SidebarChipGroup(
          title: 'Work Mode',
          options: workModeLabels,
          selected: provider.workMode,
          onSelect: (value) => _setSingleValueFilter(provider, workMode: value),
        ),
        _SidebarChipGroup(
          title: 'Experience Level',
          options: experienceLevelLabels,
          selected: provider.experienceLevel,
          onSelect: (value) => _setSingleValueFilter(provider, experienceLevel: value),
        ),
        Text('Location', style: textTheme.titleSmall),
        const SizedBox(height: AppSpacing.xs),
        AppTextField(
          controller: _locationController,
          hint: 'e.g. Amman',
          prefixIcon: Icons.place_outlined,
          textInputAction: TextInputAction.search,
          onFieldSubmitted: (_) => _submitLocation(provider),
          suffixIcon: IconButton(
            icon: const Icon(Icons.arrow_forward, size: 18),
            tooltip: 'Apply location filter',
            onPressed: () => _submitLocation(provider),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Text('Field of Study', style: textTheme.titleSmall),
        const SizedBox(height: AppSpacing.xs),
        AppTextField(
          controller: _fieldOfStudyController,
          hint: 'e.g. Computer Science',
          prefixIcon: Icons.school_outlined,
          textInputAction: TextInputAction.search,
          onFieldSubmitted: (_) => _submitFieldOfStudy(provider),
          suffixIcon: IconButton(
            icon: const Icon(Icons.arrow_forward, size: 18),
            tooltip: 'Apply field of study filter',
            onPressed: () => _submitFieldOfStudy(provider),
          ),
        ),
      ],
    );
  }
}

class _SidebarChipGroup extends StatelessWidget {
  const _SidebarChipGroup({
    required this.title,
    required this.options,
    required this.selected,
    required this.onSelect,
  });

  final String title;
  final Map<String, String> options;
  final String? selected;
  final ValueChanged<String?> onSelect;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: AppSpacing.xs),
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            children: [
              for (final entry in options.entries)
                ChoiceChip(
                  label: Text(entry.value),
                  selected: selected == entry.key,
                  onSelected: (isSelected) => onSelect(isSelected ? entry.key : null),
                  selectedColor: AppColors.primaryContainer,
                  backgroundColor: AppColors.surface,
                  side: BorderSide(
                    color: selected == entry.key ? AppColors.primary : AppColors.border,
                  ),
                  labelStyle: TextStyle(
                    color: selected == entry.key
                        ? AppColors.primaryDark
                        : AppColors.textSecondary,
                    fontWeight: selected == entry.key ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// The centerpiece discovery feed: a responsive grid of real, colored
/// [OpportunityCard]s over [StudentOpportunitiesProvider]'s already-loaded
/// (search/filter-aware) results, with real loading/error/empty states and
/// the provider's own real pagination ("Load More").
class _OpportunitiesSection extends StatelessWidget {
  const _OpportunitiesSection({required this.columns, required this.onOpenDetails});

  final int columns;
  final ValueChanged<int> onOpenDetails;

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<StudentOpportunitiesProvider>();
    final isFiltering = provider.hasActiveFilters || provider.keyword.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(
          title: 'Discover Opportunities',
          subtitle: provider.opportunities.isEmpty
              ? null
              : '${provider.opportunities.length}'
                    '${provider.hasMore ? '+' : ''} opportunity'
                    '${provider.opportunities.length == 1 && !provider.hasMore ? '' : 'ies'}'
                    ' found',
        ),
        AnimatedSwitcher(
          duration: AppMotion.reduced(context, AppMotion.normal),
          child: _buildBody(context, provider, isFiltering),
        ),
      ],
    );
  }

  Widget _buildBody(
    BuildContext context,
    StudentOpportunitiesProvider provider,
    bool isFiltering,
  ) {
    if (provider.isLoadingList && provider.opportunities.isEmpty) {
      return AppSkeletonList(key: const ValueKey('loading'), count: columns == 1 ? 3 : columns * 2);
    }

    if (provider.listErrorMessage != null && provider.opportunities.isEmpty) {
      return AppErrorView(
        key: const ValueKey('error'),
        message: provider.listErrorMessage!,
        onRetry: () => provider.loadOpportunities(forceRefresh: true),
      );
    }

    if (provider.opportunities.isEmpty) {
      return AppEmptyView(
        key: const ValueKey('empty'),
        icon: Icons.work_outline_rounded,
        title: 'No Opportunities Found',
        message: isFiltering
            ? 'Try adjusting your search or filters.'
            : 'Check back soon for new opportunities.',
      );
    }

    return Column(
      key: ValueKey('grid-${provider.opportunities.length}'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            const spacing = AppSpacing.sm;
            final cardWidth = columns == 1
                ? constraints.maxWidth
                : (constraints.maxWidth - spacing * (columns - 1)) / columns;

            return Wrap(
              spacing: spacing,
              runSpacing: spacing,
              children: [
                for (final opportunity in provider.opportunities)
                  SizedBox(
                    width: cardWidth,
                    child: OpportunityCard(
                      opportunity: opportunity,
                      onTap: () => onOpenDetails(opportunity.id),
                    ),
                  ),
              ],
            );
          },
        ),
        if (provider.hasMore || provider.isLoadingMore) ...[
          const SizedBox(height: AppSpacing.md),
          Center(
            child: provider.isLoadingMore
                ? const AppLoading(compact: true)
                : SecondaryButton(label: 'Load More', onPressed: provider.loadMore),
          ),
        ],
      ],
    );
  }
}
