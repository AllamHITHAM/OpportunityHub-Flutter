import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/app_widgets.dart';
import '../../../models/opportunity_model.dart';
import '../../../providers/student_opportunities_provider.dart';
import '../../../routes/app_routes.dart';
import 'opportunity_display.dart';

/// Lists publicly browsable opportunities, with search and filters — no
/// apply/save/applicant actions belong here, this phase covers browsing
/// only.
class StudentOpportunitiesScreen extends StatefulWidget {
  const StudentOpportunitiesScreen({super.key});

  @override
  State<StudentOpportunitiesScreen> createState() =>
      _StudentOpportunitiesScreenState();
}

class _StudentOpportunitiesScreenState
    extends State<StudentOpportunitiesScreen> {
  final _searchController = TextEditingController();
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    // Deferred to the post-frame callback: the provider's first action is
    // a synchronous notifyListeners() (setting isLoadingList), and calling
    // that directly from initState would try to rebuild this screen's own
    // ancestor Provider while the widget tree is still being built for the
    // first time — a real Flutter build-phase constraint.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<StudentOpportunitiesProvider>().loadOpportunities();
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
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

  Future<void> _openFilters() async {
    final provider = context.read<StudentOpportunitiesProvider>();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => ChangeNotifierProvider.value(
        value: provider,
        child: const _FilterSheet(),
      ),
    );
  }

  void _openDetails(int id) {
    context.push(AppRoutes.studentOpportunityDetails(id));
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<StudentOpportunitiesProvider>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Opportunities'),
        actions: [
          IconButton(
            onPressed: _openFilters,
            icon: Icon(
              provider.hasActiveFilters
                  ? Icons.filter_alt
                  : Icons.filter_alt_outlined,
            ),
            tooltip: 'Filters',
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.screenHorizontal,
                AppSpacing.sm,
                AppSpacing.screenHorizontal,
                AppSpacing.xs,
              ),
              child: AppSearchField(
                controller: _searchController,
                hint: 'Search opportunities',
                onChanged: _onSearchChanged,
              ),
            ),
            Expanded(child: _buildBody(provider)),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(StudentOpportunitiesProvider provider) {
    if (provider.isLoadingList && provider.opportunities.isEmpty) {
      return const AppSkeletonList();
    }

    if (provider.listErrorMessage != null && provider.opportunities.isEmpty) {
      return AppErrorView(
        message: provider.listErrorMessage!,
        onRetry: () => provider.loadOpportunities(forceRefresh: true),
      );
    }

    if (provider.opportunities.isEmpty) {
      return AppEmptyView(
        title: 'No Opportunities Found',
        message: provider.hasActiveFilters || provider.keyword.isNotEmpty
            ? 'Try adjusting your search or filters.'
            : 'Check back soon for new opportunities.',
        icon: Icons.work_outline_rounded,
      );
    }

    return RefreshIndicator(
      onRefresh: () => provider.loadOpportunities(forceRefresh: true),
      child: ListView.separated(
        padding: const EdgeInsets.all(AppSpacing.screenHorizontal),
        itemCount: provider.opportunities.length + (provider.hasMore ? 1 : 0),
        separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
        itemBuilder: (context, index) {
          if (index >= provider.opportunities.length) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
              child: Center(
                child: provider.isLoadingMore
                    ? const AppLoading(compact: true)
                    : SecondaryButton(
                        label: 'Load More',
                        onPressed: provider.loadMore,
                      ),
              ),
            );
          }

          final opportunity = provider.opportunities[index];
          return _OpportunityCard(
            opportunity: opportunity,
            onTap: () => _openDetails(opportunity.id),
          );
        },
      ),
    );
  }
}

class _OpportunityCard extends StatelessWidget {
  const _OpportunityCard({required this.opportunity, required this.onTap});

  final OpportunityModel opportunity;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final organizationName = opportunity.organizationProfile?.organizationName;

    return AppCard(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(opportunity.title, style: textTheme.titleMedium),
          if (organizationName != null) ...[
            const SizedBox(height: AppSpacing.xxs),
            Text(
              organizationName,
              style: textTheme.bodyMedium?.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.xxs),
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xxs,
            children: [
              StatusChip(
                label:
                    opportunityTypeLabels[opportunity.opportunityType] ??
                    opportunity.opportunityType,
                type: AppStatusType.primary,
                compact: true,
              ),
              StatusChip(
                label:
                    workModeLabels[opportunity.workMode] ??
                    opportunity.workMode,
                compact: true,
              ),
              if (opportunity.location != null)
                StatusChip(
                  label: opportunity.location!,
                  icon: Icons.place_outlined,
                  compact: true,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// A modal bottom sheet for selecting the backend-documented public
/// opportunity filters. Local, unsaved selections live in this widget's own
/// state until "Apply Filters" commits them to the provider (and triggers a
/// refetch) — cancelling (dismissing the sheet) discards them.
class _FilterSheet extends StatefulWidget {
  const _FilterSheet();

  @override
  State<_FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<_FilterSheet> {
  String? _opportunityType;
  String? _employmentType;
  String? _workMode;
  String? _experienceLevel;
  final _locationController = TextEditingController();
  final _fieldOfStudyController = TextEditingController();

  @override
  void initState() {
    super.initState();
    final provider = context.read<StudentOpportunitiesProvider>();
    _opportunityType = provider.opportunityType;
    _employmentType = provider.employmentType;
    _workMode = provider.workMode;
    _experienceLevel = provider.experienceLevel;
    _locationController.text = provider.location ?? '';
    _fieldOfStudyController.text = provider.fieldOfStudy ?? '';
  }

  @override
  void dispose() {
    _locationController.dispose();
    _fieldOfStudyController.dispose();
    super.dispose();
  }

  Widget _dropdown({
    required String label,
    required String? value,
    required Map<String, String> options,
    required ValueChanged<String?> onChanged,
  }) {
    return DropdownButtonFormField<String>(
      initialValue: value,
      isExpanded: true,
      decoration: InputDecoration(labelText: label),
      items: [
        const DropdownMenuItem<String>(value: null, child: Text('Any')),
        for (final entry in options.entries)
          DropdownMenuItem(value: entry.key, child: Text(entry.value)),
      ],
      onChanged: onChanged,
    );
  }

  void _apply() {
    context.read<StudentOpportunitiesProvider>().applyFilters(
      opportunityType: _opportunityType,
      employmentType: _employmentType,
      workMode: _workMode,
      experienceLevel: _experienceLevel,
      location: _locationController.text.trim().isEmpty
          ? null
          : _locationController.text.trim(),
      fieldOfStudy: _fieldOfStudyController.text.trim().isEmpty
          ? null
          : _fieldOfStudyController.text.trim(),
    );
    Navigator.of(context).pop();
  }

  void _clear() {
    context.read<StudentOpportunitiesProvider>().clearFilters();
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: AppSpacing.screenHorizontal,
        right: AppSpacing.screenHorizontal,
        top: AppSpacing.md,
        bottom: MediaQuery.of(context).viewInsets.bottom + AppSpacing.md,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            const SectionHeader(title: 'Filters'),
            const SizedBox(height: AppSpacing.xs),
            _dropdown(
              label: 'Opportunity Type',
              value: _opportunityType,
              options: opportunityTypeLabels,
              onChanged: (value) => setState(() => _opportunityType = value),
            ),
            const SizedBox(height: AppSpacing.inputSpacing),
            _dropdown(
              label: 'Employment Type',
              value: _employmentType,
              options: employmentTypeLabels,
              onChanged: (value) => setState(() => _employmentType = value),
            ),
            const SizedBox(height: AppSpacing.inputSpacing),
            _dropdown(
              label: 'Work Mode',
              value: _workMode,
              options: workModeLabels,
              onChanged: (value) => setState(() => _workMode = value),
            ),
            const SizedBox(height: AppSpacing.inputSpacing),
            _dropdown(
              label: 'Experience Level',
              value: _experienceLevel,
              options: experienceLevelLabels,
              onChanged: (value) => setState(() => _experienceLevel = value),
            ),
            const SizedBox(height: AppSpacing.inputSpacing),
            AppTextField(
              controller: _locationController,
              label: 'Location (optional)',
              hint: 'e.g. Amman',
            ),
            const SizedBox(height: AppSpacing.inputSpacing),
            AppTextField(
              controller: _fieldOfStudyController,
              label: 'Field of Study (optional)',
              hint: 'e.g. Computer Science',
            ),
            const SizedBox(height: AppSpacing.lg),
            Row(
              children: [
                Expanded(
                  child: SecondaryButton(label: 'Clear', onPressed: _clear),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: PrimaryButton(
                    label: 'Apply Filters',
                    onPressed: _apply,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
