import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_motion.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_shadows.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/date_formatter.dart';
import '../../../core/widgets/app_widgets.dart';
import '../../../models/application_model.dart';
import '../../../models/opportunity_model.dart';
import '../../../providers/student_applications_provider.dart';
import '../../../routes/app_routes.dart';
import '../../opportunities/presentation/opportunity_display.dart';
import 'application_display.dart';

const _desktopBreakpoint = 1200.0;
const _tabletBreakpoint = 900.0;
const _mobileBreakpoint = 600.0;

enum _ScreenTier { mobile, tablet, desktop, wide }

_ScreenTier _tierFor(double width) {
  if (width >= _desktopBreakpoint) return _ScreenTier.wide;
  if (width >= _tabletBreakpoint) return _ScreenTier.desktop;
  if (width >= _mobileBreakpoint) return _ScreenTier.tablet;
  return _ScreenTier.mobile;
}

/// The student's own application-tracking dashboard (UI Phase 4) — a real
/// pipeline overview, local search/filtering, and a redesigned card
/// language, all built strictly from [ApplicationModel]s the app already
/// loads (`GET /api/student/applications`). No match percentage, applicant
/// count, recruiter views, or interview probability exist anywhere in this
/// app's data — none are fabricated here. Withdraw does not exist as a
/// student-facing action anywhere in this app today (`ApplicationRepository`
/// has no such method), so no Withdraw button is added; see this phase's
/// final report for that gap.
class StudentApplicationsScreen extends StatefulWidget {
  const StudentApplicationsScreen({super.key});

  @override
  State<StudentApplicationsScreen> createState() =>
      _StudentApplicationsScreenState();
}

/// Local-only filters over the already-loaded application list — no new
/// backend query, matching every status mapping [application_display.dart]
/// already defines.
enum _Filter { all, active, assessment, offers, accepted, rejected, withdrawn }

const _filterLabels = {
  _Filter.all: 'All',
  _Filter.active: 'Active',
  _Filter.assessment: 'Assessment',
  _Filter.offers: 'Offers',
  _Filter.accepted: 'Accepted',
  _Filter.rejected: 'Rejected',
  _Filter.withdrawn: 'Withdrawn',
};

bool _matchesFilter(_Filter filter, String status) {
  switch (filter) {
    case _Filter.all:
      return true;
    case _Filter.active:
      return !isTerminalApplicationStatus(status);
    case _Filter.assessment:
      return status == 'in_assessment' || status == 'interview_scheduled';
    case _Filter.offers:
      return status == 'offer_sent';
    case _Filter.accepted:
      return status == 'accepted';
    case _Filter.rejected:
      return status == 'rejected';
    case _Filter.withdrawn:
      return status == 'withdrawn';
  }
}

class _StudentApplicationsScreenState extends State<StudentApplicationsScreen>
    with SingleTickerProviderStateMixin {
  final _searchController = TextEditingController();
  _Filter _filter = _Filter.all;
  String _query = '';

  late final AnimationController _entranceController;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<StudentApplicationsProvider>().loadApplications();
    });

    final reducedMotion = SchedulerBinding
        .instance
        .platformDispatcher
        .accessibilityFeatures
        .disableAnimations;
    _entranceController = AnimationController(
      vsync: this,
      duration: reducedMotion
          ? const Duration(milliseconds: 1)
          : const Duration(milliseconds: 600),
    )..forward();

    _searchController.addListener(() {
      setState(() => _query = _searchController.text.trim().toLowerCase());
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _entranceController.dispose();
    super.dispose();
  }

  void _openDetails(int id) =>
      context.push(AppRoutes.studentApplicationDetails(id));

  void _clearFilters() {
    setState(() {
      _filter = _Filter.all;
      _searchController.clear();
    });
  }

  List<ApplicationModel> _filtered(List<ApplicationModel> applications) {
    return applications.where((application) {
      if (!_matchesFilter(_filter, application.status)) return false;
      if (_query.isEmpty) return true;
      final title = application.opportunity?.title.toLowerCase() ?? '';
      final org =
          application.opportunity?.organizationProfile?.organizationName
              .toLowerCase() ??
          '';
      return title.contains(_query) || org.contains(_query);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<StudentApplicationsProvider>();
    final tier = _tierFor(MediaQuery.sizeOf(context).width);

    return Scaffold(
      appBar: AppBar(
        title: const Text('My Applications'),
        actions: const [
          ThemeToggleButton(),
          SizedBox(width: AppSpacing.xs),
        ],
      ),
      body: SafeArea(child: _buildBody(provider, tier)),
    );
  }

  Widget _buildBody(StudentApplicationsProvider provider, _ScreenTier tier) {
    if (provider.isLoadingList && provider.applications.isEmpty) {
      return _ApplicationsSkeleton(tier: tier);
    }

    if (provider.listErrorMessage != null && provider.applications.isEmpty) {
      return AppErrorView(
        message: provider.listErrorMessage!,
        onRetry: provider.refresh,
      );
    }

    final all = provider.applications;
    final horizontalPadding = tier == _ScreenTier.mobile
        ? AppSpacing.screenHorizontal
        : AppSpacing.xl;
    final maxWidth = tier == _ScreenTier.wide ? 1000.0 : double.infinity;

    if (all.isEmpty) {
      return RefreshIndicator(
        onRefresh: provider.refresh,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Hero(
                tier: tier,
                entranceController: _entranceController,
                total: 0,
                active: 0,
                offers: 0,
              ),
              SizedBox(
                height: 420,
                child: AppEmptyView(
                  icon: Icons.assignment_outlined,
                  title: 'No Applications Yet',
                  message: 'Applications you submit will appear here.',
                  actionLabel: 'Explore Opportunities',
                  onAction: () => context.go(AppRoutes.studentOpportunities),
                ),
              ),
            ],
          ),
        ),
      );
    }

    final filtered = _filtered(all);
    final total = all.length;
    final active = all
        .where(
          (application) => !isTerminalApplicationStatus(application.status),
        )
        .length;
    final offers = all
        .where((application) => application.status == 'offer_sent')
        .length;

    return RefreshIndicator(
      onRefresh: provider.refresh,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxWidth),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _Hero(
                  tier: tier,
                  entranceController: _entranceController,
                  total: total,
                  active: active,
                  offers: offers,
                ),
                _Stagger(
                  controller: _entranceController,
                  index: 1,
                  count: 3,
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(
                      horizontalPadding,
                      AppSpacing.lg,
                      horizontalPadding,
                      0,
                    ),
                    child: _PipelineOverview(applications: all, tier: tier),
                  ),
                ),
                _Stagger(
                  controller: _entranceController,
                  index: 2,
                  count: 3,
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(
                      horizontalPadding,
                      AppSpacing.lg,
                      horizontalPadding,
                      0,
                    ),
                    child: _SearchAndFilters(
                      controller: _searchController,
                      filter: _filter,
                      onFilterChanged: (value) =>
                          setState(() => _filter = value),
                    ),
                  ),
                ),
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    horizontalPadding,
                    AppSpacing.md,
                    horizontalPadding,
                    AppSpacing.xxl,
                  ),
                  child: filtered.isEmpty
                      ? Padding(
                          padding: const EdgeInsets.only(top: AppSpacing.xl),
                          child: AppEmptyView(
                            icon: Icons.search_off_rounded,
                            title: 'No Matching Applications',
                            message:
                                'Try a different search term or clear your filters.',
                            actionLabel: 'Clear Filters',
                            onAction: _clearFilters,
                          ),
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            for (var i = 0; i < filtered.length; i++) ...[
                              if (i > 0) const SizedBox(height: AppSpacing.sm),
                              _Stagger(
                                controller: _entranceController,
                                index: 3,
                                count: 3,
                                child: _ApplicationCard(
                                  application: filtered[i],
                                  onTap: () => _openDetails(filtered[i].id),
                                ),
                              ),
                            ],
                          ],
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Fades and slides a section in as part of the staged entrance. Mirrors
/// the private `_Stagger` already used by `StudentProfileScreen`/
/// `StudentOpportunityDetailsScreen` — kept separate rather than shared,
/// since none of the three is part of this app's public design-system API
/// yet.
class _Stagger extends StatelessWidget {
  const _Stagger({
    required this.controller,
    required this.index,
    required this.count,
    required this.child,
  });

  final AnimationController controller;
  final int index;
  final int count;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final start = count <= 1 ? 0.0 : index / count;
    final end = count <= 1 ? 1.0 : ((index + 1.4) / count).clamp(start, 1.0);
    final curved = CurvedAnimation(
      parent: controller,
      curve: Interval(start, end, curve: AppMotion.entrance),
    );

    return FadeTransition(
      opacity: curved,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.03),
          end: Offset.zero,
        ).animate(curved),
        child: child,
      ),
    );
  }
}

/// A compact premium heading — real, truthful counts only (never a fake
/// analytics number). Kept deliberately small relative to the rest of the
/// page, per this phase's own "not huge" hero direction.
class _Hero extends StatelessWidget {
  const _Hero({
    required this.tier,
    required this.entranceController,
    required this.total,
    required this.active,
    required this.offers,
  });

  final _ScreenTier tier;
  final AnimationController entranceController;
  final int total;
  final int active;
  final int offers;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final isMobile = tier == _ScreenTier.mobile;
    final horizontalPadding = isMobile
        ? AppSpacing.screenHorizontal
        : AppSpacing.xl;

    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.primary, AppColors.primaryDark],
        ),
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          horizontalPadding,
          AppSpacing.lg,
          horizontalPadding,
          AppSpacing.lg,
        ),
        child: _Stagger(
          controller: entranceController,
          index: 0,
          count: 3,
          child: Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            runSpacing: AppSpacing.md,
            spacing: AppSpacing.lg,
            children: [
              ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 220),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'My Applications',
                      style: textTheme.headlineMedium?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Track your applications and see what comes next.',
                      style: textTheme.bodyMedium?.copyWith(
                        color: Colors.white.withValues(alpha: 0.9),
                      ),
                    ),
                  ],
                ),
              ),
              if (total > 0)
                Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.xs,
                  children: [
                    _HeroStat(label: 'Total', value: total),
                    _HeroStat(label: 'Active', value: active),
                    _HeroStat(label: 'Offers', value: offers),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HeroStat extends StatelessWidget {
  const _HeroStat({required this.label, required this.value});

  final String label;
  final int value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.14),
        borderRadius: AppRadius.mediumRadius,
        border: Border.all(color: Colors.white.withValues(alpha: 0.28)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TweenAnimationBuilder<int>(
            tween: IntTween(begin: 0, end: value),
            duration: AppMotion.reduced(
              context,
              const Duration(milliseconds: 700),
            ),
            curve: AppMotion.entrance,
            builder: (context, animatedValue, _) => Text(
              '$animatedValue',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 20,
              ),
            ),
          ),
          Text(
            label,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.85),
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// A visually strong summary of the real, currently-loaded application
/// pipeline — five real stage counts derived from
/// [pipelineStageForStatus], never a fabricated personal history. Terminal
/// outcomes (accepted/rejected/withdrawn) are deliberately excluded from
/// these counts — see [isTerminalApplicationStatus].
class _PipelineOverview extends StatelessWidget {
  const _PipelineOverview({required this.applications, required this.tier});

  final List<ApplicationModel> applications;
  final _ScreenTier tier;

  @override
  Widget build(BuildContext context) {
    final counts = {
      for (final stage in ApplicationPipelineStage.values) stage: 0,
    };
    for (final application in applications) {
      final stage = pipelineStageForStatus(application.status);
      if (stage != null) counts[stage] = (counts[stage] ?? 0) + 1;
    }

    final tiles = [
      for (final stage in ApplicationPipelineStage.values)
        _PipelineStageTile(stage: stage, count: counts[stage] ?? 0),
    ];

    final row = Row(
      children: [
        for (var i = 0; i < tiles.length; i++) ...[
          if (i > 0) const _PipelineConnector(),
          Expanded(child: tiles[i]),
        ],
      ],
    );

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: AppRadius.largeRadius,
      ),
      child: tier == _ScreenTier.mobile
          ? SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SizedBox(width: tiles.length * 108.0, child: row),
            )
          : row,
    );
  }
}

class _PipelineConnector extends StatelessWidget {
  const _PipelineConnector();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: AppSpacing.sm,
      height: 2,
      margin: const EdgeInsets.only(bottom: 20),
      color: AppColors.border,
    );
  }
}

class _PipelineStageTile extends StatefulWidget {
  const _PipelineStageTile({required this.stage, required this.count});

  final ApplicationPipelineStage stage;
  final int count;

  @override
  State<_PipelineStageTile> createState() => _PipelineStageTileState();
}

class _PipelineStageTileState extends State<_PipelineStageTile> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final hasApplications = widget.count > 0;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: AppMotion.reduced(context, AppMotion.fast),
        curve: AppMotion.standard,
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
        decoration: BoxDecoration(
          borderRadius: AppRadius.mediumRadius,
          color: _hovered
              ? AppColors.primaryContainer.withValues(alpha: 0.5)
              : null,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36,
              height: 36,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: hasApplications
                    ? AppColors.primaryContainer
                    : AppColors.surface,
                border: Border.all(
                  color: hasApplications ? AppColors.primary : AppColors.border,
                ),
              ),
              child: Icon(
                applicationPipelineStageIcons[widget.stage],
                size: 18,
                color: hasApplications
                    ? AppColors.primaryDark
                    : AppColors.textMuted,
              ),
            ),
            const SizedBox(height: AppSpacing.xxs),
            TweenAnimationBuilder<int>(
              tween: IntTween(begin: 0, end: widget.count),
              duration: AppMotion.reduced(
                context,
                const Duration(milliseconds: 700),
              ),
              curve: AppMotion.entrance,
              builder: (context, value, _) => Text(
                '$value',
                style: textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            Text(
              applicationPipelineStageLabels[widget.stage]!,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: textTheme.labelSmall?.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SearchAndFilters extends StatelessWidget {
  const _SearchAndFilters({
    required this.controller,
    required this.filter,
    required this.onFilterChanged,
  });

  final TextEditingController controller;
  final _Filter filter;
  final ValueChanged<_Filter> onFilterChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppTextField(
          controller: controller,
          hint: 'Search by opportunity or organization',
          prefixIcon: Icons.search,
        ),
        const SizedBox(height: AppSpacing.sm),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final option in _Filter.values) ...[
                _FilterChip(
                  label: _filterLabels[option]!,
                  selected: filter == option,
                  onTap: () => onFilterChanged(option),
                ),
                const SizedBox(width: AppSpacing.xs),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: AppMotion.reduced(context, AppMotion.fast),
        curve: AppMotion.standard,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.xs,
        ),
        decoration: BoxDecoration(
          color: selected ? AppColors.primary : AppColors.surfaceVariant,
          borderRadius: AppRadius.pillRadius,
          border: Border.all(
            color: selected ? AppColors.primary : AppColors.border,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? AppColors.onPrimary : AppColors.textSecondary,
            fontWeight: FontWeight.w600,
            fontSize: 13,
          ),
        ),
      ),
    );
  }
}

/// A calmer, tracking-focused application card — deliberately not the
/// colorful Discover opportunity-ad language (see `OpportunityCard`). Real
/// fields only: opportunity title, organization identity, type/work mode,
/// applied date, and current status; no match score, applicant count, or
/// interview probability exist anywhere in this app's data.
class _ApplicationCard extends StatefulWidget {
  const _ApplicationCard({required this.application, required this.onTap});

  final ApplicationModel application;
  final VoidCallback onTap;

  @override
  State<_ApplicationCard> createState() => _ApplicationCardState();
}

class _ApplicationCardState extends State<_ApplicationCard> {
  bool _hovered = false;

  Color get _accent =>
      applicationStatusChipType(widget.application.status) ==
          AppStatusType.success
      ? AppColors.success
      : applicationStatusChipType(widget.application.status) ==
            AppStatusType.info
      ? AppColors.info
      : applicationStatusChipType(widget.application.status) ==
            AppStatusType.warning
      ? AppColors.warning
      : AppColors.textMuted;

  @override
  Widget build(BuildContext context) {
    final application = widget.application;
    final opportunity = application.opportunity;
    final organizationName = opportunity?.organizationProfile?.organizationName;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: AppMotion.reduced(context, AppMotion.normal),
          curve: AppMotion.standard,
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: AppRadius.largeRadius,
            // A single uniform-color border here — `BoxDecoration` cannot
            // combine a `borderRadius` with per-side border colors (throws
            // at paint time), so the status accent below is a separately
            // positioned, independently-rounded bar instead of a colored
            // left `BorderSide`.
            border: Border.all(
              color: _hovered
                  ? AppColors.primary.withValues(alpha: 0.35)
                  : AppColors.border,
            ),
            boxShadow: _hovered ? AppShadows.card : const [],
          ),
          child: Stack(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.md + 4,
                  AppSpacing.md,
                  AppSpacing.md,
                  AppSpacing.md,
                ),
                child: _CardContent(
                  application: application,
                  opportunity: opportunity,
                  organizationName: organizationName,
                  hovered: _hovered,
                ),
              ),
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                child: Container(
                  width: 4,
                  decoration: BoxDecoration(
                    color: _accent,
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(AppRadius.large),
                      bottomLeft: Radius.circular(AppRadius.large),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The card's real content — split out from [_ApplicationCardState] purely
/// to keep that class's build method shallow and easy to reason about; not
/// meant to be reused elsewhere.
class _CardContent extends StatelessWidget {
  const _CardContent({
    required this.application,
    required this.opportunity,
    required this.organizationName,
    required this.hovered,
  });

  final ApplicationModel application;
  final OpportunityModel? opportunity;
  final String? organizationName;
  final bool hovered;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final opportunity = this.opportunity;
    final organizationName = this.organizationName;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                color: AppColors.surface,
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.border),
              ),
              child: AppAvatar(
                name: organizationName,
                size: 40,
                fallbackIcon: Icons.apartment_outlined,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    opportunity?.title ?? 'Opportunity',
                    style: textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (organizationName != null)
                    Text(
                      organizationName,
                      style: textTheme.bodySmall?.copyWith(
                        color: AppColors.textSecondary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.xs),
            AnimatedSwitcher(
              duration: AppMotion.reduced(context, AppMotion.normal),
              transitionBuilder: (child, animation) =>
                  FadeTransition(opacity: animation, child: child),
              child: StatusChip(
                key: ValueKey(application.status),
                compact: true,
                label:
                    applicationStatusLabels[application.status] ??
                    application.status,
                type: applicationStatusChipType(application.status),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          spacing: AppSpacing.xs,
          runSpacing: AppSpacing.xxs,
          children: [
            if (opportunity != null)
              StatusChip(
                compact: true,
                label:
                    opportunityTypeLabels[opportunity.opportunityType] ??
                    opportunity.opportunityType,
              ),
            if (opportunity?.workMode != null)
              StatusChip(
                compact: true,
                icon: Icons.place_outlined,
                label:
                    workModeLabels[opportunity!.workMode] ??
                    opportunity.workMode,
              ),
            if (application.appliedAt != null)
              StatusChip(
                compact: true,
                icon: Icons.event_outlined,
                label: 'Applied ${formatDate(application.appliedAt!)}',
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        Row(
          children: [
            const Spacer(),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'View Application',
                  style: textTheme.labelMedium?.copyWith(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                AnimatedSlide(
                  duration: AppMotion.reduced(context, AppMotion.fast),
                  offset: hovered ? const Offset(0.15, 0) : Offset.zero,
                  child: Icon(
                    Icons.arrow_forward_rounded,
                    size: 16,
                    color: AppColors.primary,
                  ),
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }
}

class _ApplicationsSkeleton extends StatelessWidget {
  const _ApplicationsSkeleton({required this.tier});

  final _ScreenTier tier;

  @override
  Widget build(BuildContext context) {
    final horizontalPadding = tier == _ScreenTier.mobile
        ? AppSpacing.screenHorizontal
        : AppSpacing.xl;

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            height: 96,
            color: AppColors.primary.withValues(alpha: 0.15),
          ),
          Padding(
            padding: EdgeInsets.all(horizontalPadding),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const AppSkeleton(
                  height: 88,
                  borderRadius: AppRadius.largeRadius,
                ),
                const SizedBox(height: AppSpacing.lg),
                const AppSkeletonList(count: 4),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
