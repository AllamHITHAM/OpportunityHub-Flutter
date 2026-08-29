import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_motion.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/date_formatter.dart';
import '../../../core/widgets/app_widgets.dart';
import '../../../models/opportunity_model.dart';
import '../../../providers/organization_opportunities_provider.dart';
import '../../../routes/app_routes.dart';
import 'opportunity_display.dart';

/// Real, responsive breakpoints for the card grid — mirrors the bands
/// already used on the Organization Dashboard and Student Explore screens.
const _wideBreakpoint = 1200.0;
const _desktopBreakpoint = 900.0;
const _tabletBreakpoint = 600.0;
const _maxContentWidth = 1200.0;

/// Client-side sort options over the already-loaded list — the backend
/// list endpoint (`GET /organization/opportunities`) returns every one of
/// this organization's opportunities in one response with no query
/// parameters at all, so search/filter/sort all operate purely on data
/// already in memory; nothing here ever triggers a second network request.
enum _SortOption { newest, deadlineSoonest, title }

const _sortLabels = {
  _SortOption.newest: 'Newest',
  _SortOption.deadlineSoonest: 'Deadline Soonest',
  _SortOption.title: 'Title',
};

/// Lists the authenticated organization's own opportunities — a compact,
/// scannable management view (search/filter/sort, all real, all
/// client-side) rather than the previous sparse full-width list. Every
/// field rendered anywhere on this screen comes straight from
/// [OpportunityModel] (itself sourced from the real, already-used
/// `GET /organization/opportunities` response) — no fabricated metric,
/// list, or field. Business logic (create/update/delete, status meaning,
/// recruitment process) is untouched; this phase only changes presentation.
class OrganizationOpportunitiesScreen extends StatefulWidget {
  const OrganizationOpportunitiesScreen({super.key});

  @override
  State<OrganizationOpportunitiesScreen> createState() =>
      _OrganizationOpportunitiesScreenState();
}

class _OrganizationOpportunitiesScreenState
    extends State<OrganizationOpportunitiesScreen> {
  final _searchController = TextEditingController();

  /// `null` means "All" for each filter.
  String? _statusFilter;
  String? _typeFilter;
  String? _workModeFilter;
  _SortOption _sort = _SortOption.newest;

  @override
  void initState() {
    super.initState();
    // Loaded once here, not in build — loadOpportunities() itself also
    // guards against concurrent duplicate calls, but this avoids even
    // attempting one on every rebuild. Deferred to the post-frame callback
    // because the provider's first action is a synchronous
    // notifyListeners() (setting isLoadingList), and calling that directly
    // from initState would try to rebuild this screen's own ancestor
    // Provider while the widget tree is still being built for the first
    // time — a real Flutter constraint violation, not just a test quirk.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<OrganizationOpportunitiesProvider>().loadOpportunities();
    });
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged() => setState(() {});

  void _openCreate() {
    context.push(AppRoutes.organizationOpportunityCreate);
  }

  void _openDetails(int id) {
    context.push(AppRoutes.organizationOpportunityDetails(id));
  }

  void _openEdit(int id) {
    context.push(AppRoutes.organizationOpportunityEdit(id));
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
    if (!confirmed || !mounted) return;

    final success = await provider.deleteOpportunity(opportunity.id);
    if (!mounted) return;

    if (!success && provider.deleteErrorMessage != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(provider.deleteErrorMessage!)));
    }
  }

  /// Real client-side search/filter/sort over [all] — never a second
  /// network request. Search matches [OpportunityModel.title] and
  /// [OpportunityModel.location] (both real, already-loaded fields).
  List<OpportunityModel> _visible(List<OpportunityModel> all) {
    final query = _searchController.text.trim().toLowerCase();

    final filtered = all.where((opportunity) {
      if (_statusFilter != null && opportunity.status != _statusFilter) {
        return false;
      }
      if (_typeFilter != null &&
          opportunity.opportunityType != _typeFilter) {
        return false;
      }
      if (_workModeFilter != null &&
          opportunity.workMode != _workModeFilter) {
        return false;
      }
      if (query.isEmpty) return true;
      final title = opportunity.title.toLowerCase();
      final location = opportunity.location?.toLowerCase() ?? '';
      return title.contains(query) || location.contains(query);
    }).toList();

    switch (_sort) {
      case _SortOption.newest:
        filtered.sort((a, b) {
          final aCreated = a.createdAt;
          final bCreated = b.createdAt;
          if (aCreated == null && bCreated == null) return 0;
          if (aCreated == null) return 1;
          if (bCreated == null) return -1;
          return bCreated.compareTo(aCreated);
        });
      case _SortOption.deadlineSoonest:
        filtered.sort((a, b) {
          final aDeadline = a.applicationDeadline;
          final bDeadline = b.applicationDeadline;
          if (aDeadline == null && bDeadline == null) return 0;
          if (aDeadline == null) return 1;
          if (bDeadline == null) return -1;
          return aDeadline.compareTo(bDeadline);
        });
      case _SortOption.title:
        filtered.sort(
          (a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()),
        );
    }

    return filtered;
  }

  bool get _hasActiveFilters =>
      _statusFilter != null ||
      _typeFilter != null ||
      _workModeFilter != null ||
      _searchController.text.trim().isNotEmpty;

  void _clearFilters() {
    setState(() {
      _statusFilter = null;
      _typeFilter = null;
      _workModeFilter = null;
      _searchController.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<OrganizationOpportunitiesProvider>();

    return Scaffold(
      appBar: AppBar(title: const Text('Opportunities')),
      body: SafeArea(child: _buildBody(provider)),
    );
  }

  Widget _buildBody(OrganizationOpportunitiesProvider provider) {
    if (provider.isLoadingList && provider.opportunities.isEmpty) {
      return const AppSkeletonList();
    }

    if (provider.listErrorMessage != null && provider.opportunities.isEmpty) {
      return AppErrorView(
        message: provider.listErrorMessage!,
        onRetry: provider.loadOpportunities,
      );
    }

    if (provider.opportunities.isEmpty) {
      return AppEmptyView(
        title: 'No Opportunities Yet',
        message:
            'Create your first opportunity to start receiving applications.',
        icon: Icons.work_outline_rounded,
        actionLabel: 'Create Opportunity',
        onAction: _openCreate,
      );
    }

    final visible = _visible(provider.opportunities);

    return RefreshIndicator(
      onRefresh: provider.loadOpportunities,
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
                    _PageHeader(width: width, onCreate: _openCreate),
                    const SizedBox(height: AppSpacing.md),
                    _SummaryStrip(opportunities: provider.opportunities),
                    const SizedBox(height: AppSpacing.md),
                    _SearchAndFilters(
                      searchController: _searchController,
                      statusFilter: _statusFilter,
                      typeFilter: _typeFilter,
                      workModeFilter: _workModeFilter,
                      sort: _sort,
                      hasActiveFilters: _hasActiveFilters,
                      onStatusChanged: (value) =>
                          setState(() => _statusFilter = value),
                      onTypeChanged: (value) =>
                          setState(() => _typeFilter = value),
                      onWorkModeChanged: (value) =>
                          setState(() => _workModeFilter = value),
                      onSortChanged: (value) => setState(() => _sort = value),
                      onClearFilters: _clearFilters,
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      '${visible.length} of ${provider.opportunities.length} '
                      'opportunit${provider.opportunities.length == 1 ? 'y' : 'ies'}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    if (visible.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          vertical: AppSpacing.lg,
                        ),
                        child: AppEmptyView(
                          icon: Icons.filter_alt_off_outlined,
                          title: 'No Matching Opportunities',
                          message: 'Try adjusting your search or filters.',
                          actionLabel: _hasActiveFilters
                              ? 'Clear Filters'
                              : null,
                          onAction: _hasActiveFilters ? _clearFilters : null,
                        ),
                      )
                    else
                      _OpportunityGrid(
                        opportunities: visible,
                        width: width,
                        onOpenDetails: _openDetails,
                        onOpenEdit: _openEdit,
                        onDelete: _confirmDelete,
                      ),
                    const SizedBox(height: AppSpacing.xl),
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

/// A strong, compact page header — real title/subtext plus an obvious
/// primary Create action (fixing the old screen's weak AppBar-icon-only
/// entry point). Stacks vertically on narrow widths so the button never
/// competes for space with the title.
class _PageHeader extends StatelessWidget {
  const _PageHeader({required this.width, required this.onCreate});

  final double width;
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final narrow = width < _tabletBreakpoint;

    final titleBlock = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Opportunities',
          style: textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: AppSpacing.xxs),
        Text(
          'Manage your active and past opportunities.',
          style: textTheme.bodyMedium?.copyWith(
            color: AppColors.textSecondary,
          ),
        ),
      ],
    );

    final createButton = PrimaryButton(
      label: 'Create Opportunity',
      icon: Icons.add,
      onPressed: onCreate,
      width: narrow ? double.infinity : null,
    );

    if (narrow) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          titleBlock,
          const SizedBox(height: AppSpacing.sm),
          createButton,
        ],
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(child: titleBlock),
        const SizedBox(width: AppSpacing.md),
        createButton,
      ],
    );
  }
}

/// Real Total/Open/Closed/Draft counts, computed from the full
/// (unfiltered) list — a truthful portfolio summary, never affected by
/// whatever search/filter is currently applied to the list below it.
class _SummaryStrip extends StatelessWidget {
  const _SummaryStrip({required this.opportunities});

  final List<OpportunityModel> opportunities;

  @override
  Widget build(BuildContext context) {
    final open = opportunities.where((o) => o.status == 'open').length;
    final closed = opportunities.where((o) => o.status == 'closed').length;
    final draft = opportunities.where((o) => o.status == 'draft').length;

    return AppCard(
      child: Wrap(
        spacing: AppSpacing.md,
        runSpacing: AppSpacing.xs,
        children: [
          _SummaryStat(label: 'Total', value: opportunities.length),
          _SummaryStat(label: 'Open', value: open, color: AppColors.success),
          _SummaryStat(label: 'Closed', value: closed),
          _SummaryStat(label: 'Draft', value: draft, color: AppColors.warning),
        ],
      ),
    );
  }
}

class _SummaryStat extends StatelessWidget {
  const _SummaryStat({required this.label, required this.value, this.color});

  final String label;
  final int value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '$value',
          style: textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
        Text(
          label,
          style: textTheme.bodySmall?.copyWith(color: AppColors.textSecondary),
        ),
      ],
    );
  }
}

/// Search (title/location, real client-side filtering) plus compact
/// Status/Type/Work Mode filters and a lightweight Sort control — every
/// option here is a real, already-documented field value, never invented.
class _SearchAndFilters extends StatelessWidget {
  const _SearchAndFilters({
    required this.searchController,
    required this.statusFilter,
    required this.typeFilter,
    required this.workModeFilter,
    required this.sort,
    required this.hasActiveFilters,
    required this.onStatusChanged,
    required this.onTypeChanged,
    required this.onWorkModeChanged,
    required this.onSortChanged,
    required this.onClearFilters,
  });

  final TextEditingController searchController;
  final String? statusFilter;
  final String? typeFilter;
  final String? workModeFilter;
  final _SortOption sort;
  final bool hasActiveFilters;
  final ValueChanged<String?> onStatusChanged;
  final ValueChanged<String?> onTypeChanged;
  final ValueChanged<String?> onWorkModeChanged;
  final ValueChanged<_SortOption> onSortChanged;
  final VoidCallback onClearFilters;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppSearchField(
          controller: searchController,
          hint: 'Search by title or location',
        ),
        const SizedBox(height: AppSpacing.sm),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              _StatusChoiceChip(
                label: 'All',
                selected: statusFilter == null,
                onSelected: () => onStatusChanged(null),
              ),
              const SizedBox(width: AppSpacing.xs),
              for (final entry in statusLabels.entries) ...[
                _StatusChoiceChip(
                  label: entry.value,
                  selected: statusFilter == entry.key,
                  onSelected: () => onStatusChanged(entry.key),
                ),
                const SizedBox(width: AppSpacing.xs),
              ],
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Wrap(
          spacing: AppSpacing.xs,
          runSpacing: AppSpacing.xs,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            _FilterDropdown<String?>(
              label: 'Type',
              value: typeFilter,
              selectedLabel: typeFilter == null
                  ? 'All'
                  : (opportunityTypeLabels[typeFilter] ?? typeFilter!),
              items: [
                const DropdownMenuItem(value: null, child: Text('All Types')),
                for (final entry in opportunityTypeLabels.entries)
                  DropdownMenuItem(value: entry.key, child: Text(entry.value)),
              ],
              onChanged: onTypeChanged,
            ),
            _FilterDropdown<String?>(
              label: 'Mode',
              value: workModeFilter,
              selectedLabel: workModeFilter == null
                  ? 'All'
                  : (workModeLabels[workModeFilter] ?? workModeFilter!),
              items: [
                const DropdownMenuItem(value: null, child: Text('All Modes')),
                for (final entry in workModeLabels.entries)
                  DropdownMenuItem(value: entry.key, child: Text(entry.value)),
              ],
              onChanged: onWorkModeChanged,
            ),
            _FilterDropdown<_SortOption>(
              label: 'Sort',
              value: sort,
              selectedLabel: _sortLabels[sort] ?? '',
              items: [
                for (final entry in _sortLabels.entries)
                  DropdownMenuItem(value: entry.key, child: Text(entry.value)),
              ],
              onChanged: (value) {
                if (value != null) onSortChanged(value);
              },
            ),
            if (hasActiveFilters)
              TextButton(
                onPressed: onClearFilters,
                child: const Text('Clear Filters'),
              ),
          ],
        ),
      ],
    );
  }
}

class _StatusChoiceChip extends StatelessWidget {
  const _StatusChoiceChip({
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

/// A compact, chip-styled dropdown — used for Type/Work Mode/Sort so they
/// read as part of the same filter row instead of a full-width form field.
/// Always displays as "Label: current selection" — via [selectedLabel], not
/// [DropdownButton]'s own `hint` (which Flutter only shows when [value] has
/// no matching item at all, so it would never appear once a real option,
/// including "All Types", is selected) — so the control's purpose stays
/// legible regardless of which option is currently chosen.
class _FilterDropdown<T> extends StatelessWidget {
  const _FilterDropdown({
    required this.label,
    required this.value,
    required this.selectedLabel,
    required this.items,
    required this.onChanged,
  });

  final String label;
  final T value;
  final String selectedLabel;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?> onChanged;

  @override
  Widget build(BuildContext context) {
    final textStyle = Theme.of(
      context,
    ).textTheme.bodySmall?.copyWith(color: AppColors.textPrimary);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          items: items,
          onChanged: onChanged,
          isDense: true,
          borderRadius: BorderRadius.circular(12),
          icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 18),
          style: textStyle,
          selectedItemBuilder: (context) => [
            for (final _ in items)
              Align(
                alignment: Alignment.centerLeft,
                child: Text('$label: $selectedLabel', style: textStyle),
              ),
          ],
        ),
      ),
    );
  }
}

/// A width-aware wrapping grid of [_OpportunityListCard]s — 1 column on
/// mobile, up to 3 on wide desktop, matching the responsive technique
/// already proven on the Organization Dashboard.
class _OpportunityGrid extends StatelessWidget {
  const _OpportunityGrid({
    required this.opportunities,
    required this.width,
    required this.onOpenDetails,
    required this.onOpenEdit,
    required this.onDelete,
  });

  final List<OpportunityModel> opportunities;
  final double width;
  final ValueChanged<int> onOpenDetails;
  final ValueChanged<int> onOpenEdit;
  final ValueChanged<OpportunityModel> onDelete;

  int get _columns {
    if (width >= _wideBreakpoint) return 3;
    if (width >= _desktopBreakpoint) return 2;
    if (width >= _tabletBreakpoint) return 2;
    return 1;
  }

  @override
  Widget build(BuildContext context) {
    final columns = _columns;
    const spacing = AppSpacing.sm;

    return LayoutBuilder(
      builder: (context, constraints) {
        final tileWidth = columns == 1
            ? constraints.maxWidth
            : (constraints.maxWidth - spacing * (columns - 1)) / columns;

        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            for (final opportunity in opportunities)
              SizedBox(
                width: tileWidth,
                child: _OpportunityListCard(
                  key: ValueKey(opportunity.id),
                  opportunity: opportunity,
                  onTap: () => onOpenDetails(opportunity.id),
                  onEdit: () => onOpenEdit(opportunity.id),
                  onDelete: () => onDelete(opportunity),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// One compact, scannable opportunity card — real fields only, a clear
/// tap-to-open-Details affordance, and a compact trailing menu for the
/// existing Edit/Delete actions (never large buttons cluttering the card).
class _OpportunityListCard extends StatefulWidget {
  const _OpportunityListCard({
    super.key,
    required this.opportunity,
    required this.onTap,
    required this.onEdit,
    required this.onDelete,
  });

  final OpportunityModel opportunity;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  State<_OpportunityListCard> createState() => _OpportunityListCardState();
}

class _OpportunityListCardState extends State<_OpportunityListCard> {
  double _entrance = 0;

  @override
  void initState() {
    super.initState();
    // A subtle one-time entrance, deferred one frame so it's a real
    // (if brief) transition rather than an instant jump — respects
    // reduced motion via the zero-length duration below.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() => _entrance = 1);
    });
  }

  void _handleMenuSelection(String action) {
    switch (action) {
      case 'edit':
        widget.onEdit();
      case 'delete':
        widget.onDelete();
    }
  }

  @override
  Widget build(BuildContext context) {
    final opportunity = widget.opportunity;
    final textTheme = Theme.of(context).textTheme;
    final duration = AppMotion.reduced(context, AppMotion.normal);
    final deadline = opportunity.applicationDeadline;
    final urgency = deadlineUrgencyFor(deadline);

    return AnimatedOpacity(
      opacity: _entrance,
      duration: duration,
      curve: AppMotion.entrance,
      child: AnimatedSlide(
        offset: Offset(0, (1 - _entrance) * 0.03),
        duration: duration,
        curve: AppMotion.entrance,
        child: AppCard(
          onTap: widget.onTap,
          interactive: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      opportunity.title,
                      style: textTheme.titleMedium,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.xxs),
                  StatusChip(
                    label: statusLabels[opportunity.status] ?? opportunity.status,
                    type: statusChipType(opportunity.status),
                    compact: true,
                  ),
                  PopupMenuButton<String>(
                    onSelected: _handleMenuSelection,
                    tooltip: 'More actions',
                    padding: EdgeInsets.zero,
                    icon: Icon(
                      Icons.more_vert,
                      size: 20,
                      color: AppColors.textSecondary,
                    ),
                    itemBuilder: (context) => [
                      const PopupMenuItem(
                        value: 'edit',
                        child: Text('Edit'),
                      ),
                      PopupMenuItem(
                        value: 'delete',
                        child: Text(
                          'Delete',
                          style: TextStyle(color: AppColors.error),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.xxs),
              Wrap(
                spacing: AppSpacing.xxs,
                runSpacing: AppSpacing.xxs,
                children: [
                  StatusChip(
                    compact: true,
                    type: AppStatusType.primary,
                    label:
                        opportunityTypeLabels[opportunity.opportunityType] ??
                        opportunity.opportunityType,
                  ),
                  StatusChip(
                    compact: true,
                    label:
                        employmentTypeLabels[opportunity.employmentType] ??
                        opportunity.employmentType,
                  ),
                  StatusChip(
                    compact: true,
                    label:
                        workModeLabels[opportunity.workMode] ??
                        opportunity.workMode,
                  ),
                  StatusChip(
                    compact: true,
                    icon: Icons.assignment_outlined,
                    type: opportunity.recruitmentProcess == 'none'
                        ? AppStatusType.neutral
                        : AppStatusType.info,
                    label:
                        recruitmentProcessLabels[opportunity.recruitmentProcess] ??
                        opportunity.recruitmentProcess,
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.xs),
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.xxs,
                children: [
                  if (opportunity.location != null)
                    _MetaItem(
                      icon: Icons.place_outlined,
                      text: opportunity.location!,
                    ),
                  _MetaItem(
                    icon: Icons.groups_outlined,
                    text:
                        '${opportunity.positionsAvailable} position'
                        '${opportunity.positionsAvailable == 1 ? '' : 's'}',
                  ),
                  if (deadline != null)
                    _MetaItem(
                      icon: Icons.event_outlined,
                      text: 'Due ${formatDate(deadline)}',
                      color: urgency == DeadlineUrgency.passed
                          ? AppColors.error
                          : urgency == DeadlineUrgency.soon
                          ? AppColors.warning
                          : null,
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A small icon+text metadata pair — used for the card's compact
/// location/positions/deadline row so it never needs a separate full-width
/// line per field.
class _MetaItem extends StatelessWidget {
  const _MetaItem({required this.icon, required this.text, this.color});

  final IconData icon;
  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final resolvedColor = color ?? AppColors.textSecondary;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: resolvedColor),
        const SizedBox(width: 4),
        Text(
          text,
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: resolvedColor),
        ),
      ],
    );
  }
}
