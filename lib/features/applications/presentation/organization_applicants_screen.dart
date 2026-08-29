import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/date_formatter.dart';
import '../../../core/widgets/app_widgets.dart';
import '../../../models/application_model.dart';
import '../../../providers/organization_applications_provider.dart';
import '../../../routes/app_routes.dart';
import 'application_display.dart';

/// UI Phase O7: below this width, applicant cards stack into a single
/// column; at or above it, a responsive multi-column grid — matching the
/// same breakpoints/technique already used by the Opportunities list.
const _wideBreakpoint = 1200.0;
const _desktopBreakpoint = 900.0;

/// A centered, intentional desktop width — the same "don't stretch sparse
/// content edge-to-edge" treatment already applied throughout the
/// Organization UI.
const _maxContentWidth = 1100.0;

/// The real, documented `application.status` values worth their own filter
/// chip here — matches [applicationStatusLabels]' primary recruitment
/// funnel. `interview_scheduled` (legacy-only) and `withdrawn` are real
/// statuses too but deliberately excluded from this filter row to keep it
/// to the statuses an Organization actually acts on day to day; any
/// application in either state is still visible under "All".
const _filterableStatuses = [
  'pending',
  'reviewed',
  'shortlisted',
  'in_assessment',
  'offer_sent',
  'accepted',
  'rejected',
];

/// Lists the applicants for one of the organization's own opportunities.
/// No applicant-review actions live here — tapping a card opens
/// [ApplicationModel] details, where Mark Reviewed/Shortlist/Reject
/// actions live, to avoid accidental decisions from a list row.
///
/// UI Phase O7: purely a presentation polish over the exact same real
/// data — a theme toggle, real client-side search/filter, a responsive
/// card grid, and a more prominent match score. No status/ownership/
/// navigation/Match Analysis logic changed.
class OrganizationApplicantsScreen extends StatefulWidget {
  const OrganizationApplicantsScreen({
    super.key,
    required this.opportunityId,
    this.opportunityTitle,
  });

  final int opportunityId;

  /// Optional — only available when reached via in-app navigation (e.g.
  /// from Opportunity Details, via GoRouter `extra`). A direct URL visit
  /// has no `extra` to rely on, so the screen must render correctly
  /// without it; [opportunityId] alone is always sufficient to load data.
  final String? opportunityTitle;

  @override
  State<OrganizationApplicantsScreen> createState() =>
      _OrganizationApplicantsScreenState();
}

class _OrganizationApplicantsScreenState
    extends State<OrganizationApplicantsScreen> {
  final _searchController = TextEditingController();

  /// `null` means "All".
  String? _statusFilter;

  @override
  void initState() {
    super.initState();
    // Deferred to the post-frame callback — see
    // StudentOpportunitiesScreen.initState for why calling this directly
    // here would violate Flutter's build-phase constraints.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context
          .read<OrganizationApplicationsProvider>()
          .loadApplicationsForOpportunity(widget.opportunityId);
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

  bool get _hasActiveFilters =>
      _statusFilter != null || _searchController.text.trim().isNotEmpty;

  void _clearFilters() {
    setState(() {
      _statusFilter = null;
      _searchController.clear();
    });
  }

  /// Real client-side search/filter over [all] — never a second network
  /// request. Search matches name/email, and major/university when
  /// present (real, already-loaded [ApplicantSummaryModel] fields).
  List<ApplicationModel> _visible(List<ApplicationModel> all) {
    final query = _searchController.text.trim().toLowerCase();

    return all.where((application) {
      if (_statusFilter != null && application.status != _statusFilter) {
        return false;
      }
      if (query.isEmpty) return true;

      final applicant = application.applicant;
      final haystack = [
        applicant?.name,
        applicant?.email,
        applicant?.major,
        applicant?.university,
      ].whereType<String>().join(' ').toLowerCase();
      return haystack.contains(query);
    }).toList();
  }

  /// Opens Application Details and, on return, force-refreshes this list.
  /// Backend ranking depends on the stored `match_score` (Phase 8A-1), and
  /// a Recalculate on the details screen (Phase 8A-3) only updates that
  /// screen's own `selectedApplication` — never this list's `applications`
  /// array — so without this refresh, a changed score/ranking wouldn't be
  /// reflected until some unrelated action reloaded the list. Mirrors
  /// `_QuizAssessmentSummaryCard._openEditor`'s own "await the push, then
  /// force-refresh on return" pattern. The backend remains the sole
  /// ranking authority — this never introduces client-side sorting, just
  /// re-fetches the backend's own order.
  Future<void> _openDetails(int applicationId) async {
    await context.push(AppRoutes.organizationApplicationDetails(applicationId));
    if (!mounted) return;
    context
        .read<OrganizationApplicationsProvider>()
        .loadApplicationsForOpportunity(
          widget.opportunityId,
          forceRefresh: true,
        );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<OrganizationApplicationsProvider>();

    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.opportunityTitle != null
              ? 'Applicants for ${widget.opportunityTitle}'
              : 'Applicants',
        ),
        actions: const [ThemeToggleSurface()],
      ),
      body: SafeArea(child: _buildBody(provider)),
    );
  }

  Widget _buildBody(OrganizationApplicationsProvider provider) {
    if (provider.isLoadingList && provider.applications.isEmpty) {
      return const AppSkeletonList();
    }

    if (provider.listErrorMessage != null && provider.applications.isEmpty) {
      return AppErrorView(
        message: provider.listErrorMessage!,
        onRetry: () => provider.loadApplicationsForOpportunity(
          widget.opportunityId,
          forceRefresh: true,
        ),
      );
    }

    if (provider.applications.isEmpty) {
      return const AppEmptyView(
        title: 'No Applicants Yet',
        message: 'Applications submitted to this opportunity will appear here.',
        icon: Icons.people_outline,
      );
    }

    final visible = _visible(provider.applications);

    return RefreshIndicator(
      onRefresh: () => provider.loadApplicationsForOpportunity(
        widget.opportunityId,
        forceRefresh: true,
      ),
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
                    _CountHeader(count: provider.applications.length),
                    const SizedBox(height: AppSpacing.md),
                    _SearchAndFilters(
                      searchController: _searchController,
                      statusFilter: _statusFilter,
                      onStatusChanged: (value) =>
                          setState(() => _statusFilter = value),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      '${visible.length} of ${provider.applications.length} '
                      'applicant${provider.applications.length == 1 ? '' : 's'}',
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
                          title: 'No Matching Applicants',
                          message: 'Try adjusting your search or filters.',
                          actionLabel: _hasActiveFilters
                              ? 'Clear Filters'
                              : null,
                          onAction: _hasActiveFilters ? _clearFilters : null,
                        ),
                      )
                    else
                      _ApplicantGrid(
                        applications: visible,
                        width: width,
                        onOpenDetails: _openDetails,
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

/// A compact, real applicant count — "N Applicants" from the already-loaded
/// list length, never a fabricated metric. Omitted entirely if there were
/// no applicants to begin with (that state renders [AppEmptyView] instead
/// and never reaches this widget).
class _CountHeader extends StatelessWidget {
  const _CountHeader({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Text(
      '$count Applicant${count == 1 ? '' : 's'}',
      style: Theme.of(
        context,
      ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
    );
  }
}

/// Search (name/email/major/university, real client-side filtering) plus
/// compact status filter chips built from the real, already-documented
/// [applicationStatusLabels] vocabulary — never an invented status.
class _SearchAndFilters extends StatelessWidget {
  const _SearchAndFilters({
    required this.searchController,
    required this.statusFilter,
    required this.onStatusChanged,
  });

  final TextEditingController searchController;
  final String? statusFilter;
  final ValueChanged<String?> onStatusChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppSearchField(
          controller: searchController,
          hint: 'Search by name or email',
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
              for (final status in _filterableStatuses) ...[
                _StatusChoiceChip(
                  label: applicationStatusLabels[status] ?? status,
                  selected: statusFilter == status,
                  onSelected: () => onStatusChanged(status),
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

/// A responsive grid of [_ApplicantCard]s — a single stacked column below
/// [_desktopBreakpoint], up to 3 columns on very wide desktop, so compact
/// cards never stretch two short lines across the full page width.
class _ApplicantGrid extends StatelessWidget {
  const _ApplicantGrid({
    required this.applications,
    required this.width,
    required this.onOpenDetails,
  });

  final List<ApplicationModel> applications;
  final double width;
  final ValueChanged<int> onOpenDetails;

  int get _columns {
    if (width >= _wideBreakpoint) return 3;
    if (width >= _desktopBreakpoint) return 2;
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
            for (final application in applications)
              SizedBox(
                width: tileWidth,
                child: _ApplicantCard(
                  application: application,
                  onTap: () => onOpenDetails(application.id),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _ApplicantCard extends StatelessWidget {
  const _ApplicantCard({required this.application, required this.onTap});

  final ApplicationModel application;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final applicant = application.applicant;
    final name = cleanDisplayText(applicant?.name);
    final email = cleanDisplayText(applicant?.email);
    final matchScore = application.matchScore;

    final studyLine = _studyLine(
      cleanDisplayText(applicant?.major),
      cleanDisplayText(applicant?.university),
    );

    return AppCard(
      onTap: onTap,
      interactive: true,
      borderColor: AppColors.secondaryLight,
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  name ?? 'Unnamed applicant',
                  style: textTheme.titleMedium,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              Flexible(
                child: StatusChip(
                  label:
                      applicationStatusLabels[application.status] ??
                      application.status,
                  type: applicationStatusChipType(application.status),
                  compact: true,
                ),
              ),
            ],
          ),
          if (email != null) ...[
            const SizedBox(height: AppSpacing.xxs),
            Text(
              email,
              style: textTheme.bodyMedium?.copyWith(
                color: AppColors.textSecondary,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          if (studyLine != null) ...[
            const SizedBox(height: AppSpacing.xxs),
            Text(
              studyLine,
              style: textTheme.bodySmall?.copyWith(
                color: AppColors.textSecondary,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          const SizedBox(height: AppSpacing.sm),
          const Divider(height: 1),
          const SizedBox(height: AppSpacing.sm),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _MetaColumn(
                  label: 'Applied',
                  value: application.appliedAt != null
                      ? formatDate(application.appliedAt!)
                      : 'Not specified',
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: _MetaColumn(
                  label: 'Match',
                  value: matchScore != null
                      ? '${matchScore.toStringAsFixed(0)}%'
                      : 'Not available',
                  valueColor: matchScore != null
                      ? AppColors.primary
                      : AppColors.textMuted,
                  emphasize: matchScore != null,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String? _studyLine(String? major, String? university) {
    if (major != null && university != null) return '$major, $university';
    return major ?? university;
  }
}

/// A small label-above-value pair for the card's Applied/Match footer —
/// [emphasize] makes the Match value read as more prominent (bold, larger,
/// colored) than a plain detail row, per this phase's "make match score
/// easier to notice" goal, while [valueColor] keeps a genuinely missing
/// score visibly muted rather than implying a real number.
class _MetaColumn extends StatelessWidget {
  const _MetaColumn({
    required this.label,
    required this.value,
    this.valueColor,
    this.emphasize = false,
  });

  final String label;
  final String value;
  final Color? valueColor;
  final bool emphasize;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: textTheme.bodySmall?.copyWith(color: AppColors.textSecondary),
        ),
        Text(
          value,
          style:
              (emphasize ? textTheme.titleMedium : textTheme.bodyMedium)
                  ?.copyWith(
                    fontWeight: emphasize ? FontWeight.bold : FontWeight.w600,
                    color: valueColor ?? AppColors.textPrimary,
                  ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}
