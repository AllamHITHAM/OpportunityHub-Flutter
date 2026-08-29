import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/app_widgets.dart';
import '../../../models/candidate_model.dart';
import '../../../providers/candidate_search_provider.dart';
import '../../../routes/app_routes.dart';
import '../../applications/presentation/application_display.dart';
import '../../opportunities/presentation/opportunity_display.dart';
import 'organization_candidate_profile_screen.dart';

/// UI Phase O8: below this width, candidate cards stack into a single
/// column with a full-width View Profile button; at or above it, a
/// responsive multi-column grid with a compact trailing action — matching
/// the same breakpoints/technique already used by the Applicants list.
const _wideBreakpoint = 1200.0;
const _desktopBreakpoint = 900.0;

/// A centered, intentional desktop width — the same "don't stretch sparse
/// content edge-to-edge" treatment already applied throughout the
/// Organization UI.
const _maxContentWidth = 1100.0;

/// Talent Directory (Phase 8B-3, Flow B; renamed from "Find Candidates" in
/// Phase O8.1) — lets an Organization browse and discover Student profiles.
/// Filter/search-only, matching `StudentOpportunitiesScreen`'s own
/// search+filter-sheet shape.
///
/// Phase O8.1: this screen is pure profile discovery — inviting a student
/// now happens from a specific Opportunity's Recommended Candidates screen,
/// where eligibility and match context are already known. The Invite
/// action and its opportunity-picker dialog were removed from this flow;
/// the primary action here is "View Profile"
/// ([OrganizationCandidateProfileScreen]). No search/filter logic changed.
class CandidateSearchScreen extends StatefulWidget {
  const CandidateSearchScreen({super.key});

  @override
  State<CandidateSearchScreen> createState() => _CandidateSearchScreenState();
}

class _CandidateSearchScreenState extends State<CandidateSearchScreen> {
  final _nameController = TextEditingController();
  Timer? _debounce;

  String? _major;
  String? _university;
  int? _graduationYear;
  String? _skill;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<CandidateSearchProvider>().search();
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _nameController.dispose();
    super.dispose();
  }

  bool get _hasActiveFilters =>
      _major != null || _university != null || _graduationYear != null || _skill != null;

  int get _activeFilterCount => [
    _major,
    _university,
    _graduationYear,
    _skill,
  ].where((value) => value != null).length;

  void _runSearch() {
    context.read<CandidateSearchProvider>().search(
      name: _nameController.text.trim().isEmpty
          ? null
          : _nameController.text.trim(),
      major: _major,
      university: _university,
      graduationYear: _graduationYear,
      skill: _skill,
    );
  }

  void _onNameChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      if (!mounted) return;
      _runSearch();
    });
  }

  Future<void> _openFilters() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _FilterSheet(
        major: _major,
        university: _university,
        graduationYear: _graduationYear,
        skill: _skill,
        onApply: (major, university, graduationYear, skill) {
          setState(() {
            _major = major;
            _university = university;
            _graduationYear = graduationYear;
            _skill = skill;
          });
          _runSearch();
        },
      ),
    );
  }

  void _viewProfile(CandidateModel candidate) {
    context.push(
      AppRoutes.organizationCandidateProfile(candidate.id),
      extra: CandidateProfileView.fromCandidate(candidate),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<CandidateSearchProvider>();
    final filterCount = _activeFilterCount;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Talent Directory'),
            Text(
              'Browse student profiles to discover future candidates',
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
        actions: [
          Badge(
            label: Text('$filterCount'),
            isLabelVisible: filterCount > 0,
            child: IconButton(
              onPressed: _openFilters,
              icon: Icon(
                _hasActiveFilters
                    ? Icons.filter_alt
                    : Icons.filter_alt_outlined,
              ),
              tooltip: filterCount > 0
                  ? 'Filters ($filterCount active)'
                  : 'Filters',
            ),
          ),
          const ThemeToggleSurface(),
        ],
      ),
      body: SafeArea(child: _buildBody(provider)),
    );
  }

  Widget _buildBody(CandidateSearchProvider provider) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;

        return Column(
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(
                width >= _desktopBreakpoint
                    ? AppSpacing.xl
                    : AppSpacing.screenHorizontal,
                AppSpacing.md,
                width >= _desktopBreakpoint
                    ? AppSpacing.xl
                    : AppSpacing.screenHorizontal,
                AppSpacing.sm,
              ),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: _maxContentWidth),
                  child: AppSearchField(
                    controller: _nameController,
                    hint: 'Search candidates by name',
                    onChanged: _onNameChanged,
                  ),
                ),
              ),
            ),
            Expanded(child: _buildResults(provider, width)),
          ],
        );
      },
    );
  }

  Widget _buildResults(CandidateSearchProvider provider, double width) {
    if (provider.isSearching && provider.candidates.isEmpty) {
      return const AppSkeletonList();
    }

    if (provider.searchErrorMessage != null && provider.candidates.isEmpty) {
      return AppErrorView(
        message: provider.searchErrorMessage!,
        onRetry: _runSearch,
      );
    }

    if (provider.candidates.isEmpty) {
      return AppEmptyView(
        title: 'No Candidates Found',
        message: _hasActiveFilters || _nameController.text.isNotEmpty
            ? 'Try adjusting your search or filters.'
            : 'No student profiles are available yet.',
        icon: Icons.people_outline_rounded,
      );
    }

    return RefreshIndicator(
      onRefresh: () async => _runSearch(),
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.symmetric(
          horizontal: width >= _desktopBreakpoint
              ? AppSpacing.xl
              : AppSpacing.screenHorizontal,
          vertical: AppSpacing.sm,
        ),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: _maxContentWidth),
            child: _CandidateGrid(
              candidates: provider.candidates,
              width: width,
              onViewProfile: _viewProfile,
            ),
          ),
        ),
      ),
    );
  }
}

/// A responsive grid of [_CandidateCard]s — a single stacked column below
/// [_desktopBreakpoint] (full-width View Profile button), up to 3 columns
/// on wide desktop (compact trailing action), so compact cards never
/// stretch across the full page with mostly blank space.
class _CandidateGrid extends StatelessWidget {
  const _CandidateGrid({
    required this.candidates,
    required this.width,
    required this.onViewProfile,
  });

  final List<CandidateModel> candidates;
  final double width;
  final ValueChanged<CandidateModel> onViewProfile;

  int get _columns {
    if (width >= _wideBreakpoint) return 3;
    if (width >= _desktopBreakpoint) return 2;
    return 1;
  }

  @override
  Widget build(BuildContext context) {
    final columns = _columns;
    const spacing = AppSpacing.md;

    return LayoutBuilder(
      builder: (context, constraints) {
        final tileWidth = columns == 1
            ? constraints.maxWidth
            : (constraints.maxWidth - spacing * (columns - 1)) / columns;

        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            for (final candidate in candidates)
              SizedBox(
                width: tileWidth,
                child: _CandidateCard(
                  candidate: candidate,
                  compactAction: columns > 1,
                  onViewProfile: () => onViewProfile(candidate),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// Skill chips beyond this count collapse into a single "+N more" chip —
/// keeps a candidate with a long skill list from making their card much
/// taller than everyone else's (goal: consistent, scannable card rhythm).
const _maxVisibleSkills = 4;

/// A soft floor so cards with little data (no major/university/skills)
/// still read as deliberate tiles rather than looking collapsed/broken
/// next to fuller ones in the same grid row.
const _cardMinHeight = 220.0;

class _CandidateCard extends StatelessWidget {
  const _CandidateCard({
    required this.candidate,
    required this.compactAction,
    required this.onViewProfile,
  });

  final CandidateModel candidate;

  /// True in a multi-column desktop grid — the View Profile action reads
  /// as a compact trailing/footer button rather than a full-width one.
  final bool compactAction;

  final VoidCallback onViewProfile;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final visibleSkills = candidate.skills.take(_maxVisibleSkills).toList();
    final hiddenSkillCount = candidate.skills.length - visibleSkills.length;

    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: _cardMinHeight),
      child: AppCard(
        borderColor: AppColors.secondaryLight,
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              candidate.name,
              style: textTheme.titleMedium,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            if (candidate.major != null) ...[
              const SizedBox(height: AppSpacing.xs),
              _IconLine(icon: Icons.school_outlined, text: candidate.major!),
            ],
            if (candidate.university != null) ...[
              const SizedBox(height: AppSpacing.xxs),
              _IconLine(
                icon: Icons.account_balance_outlined,
                text: candidate.university!,
              ),
            ],
            if (candidate.graduationYear != null) ...[
              const SizedBox(height: AppSpacing.xxs),
              _IconLine(
                icon: Icons.calendar_today_outlined,
                text: 'Class of ${candidate.graduationYear}',
              ),
            ],
            const SizedBox(height: AppSpacing.sm),
            // The education-verification chip always sits under its own
            // real, truthful label ("Education Verification") instead of
            // appearing as a bare, unlabeled "Not Submitted"/"Verified"
            // chip with no context.
            Text(
              'Education Verification',
              style: textTheme.labelSmall?.copyWith(
                color: AppColors.textMuted,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: AppSpacing.xxs),
            StatusChip(
              label: educationVerificationStatusLabel(
                candidate.educationVerificationStatus,
              ),
              type: candidate.educationVerificationStatus == 'verified'
                  ? AppStatusType.success
                  : AppStatusType.neutral,
              compact: true,
            ),
            if (candidate.skills.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(
                'Skills',
                style: textTheme.labelSmall?.copyWith(
                  color: AppColors.textMuted,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: AppSpacing.xxs),
              Wrap(
                spacing: AppSpacing.xs,
                runSpacing: AppSpacing.xxs,
                children: [
                  for (final skill in visibleSkills)
                    StatusChip(
                      label: '${skill.name} (${skill.evidenceLabel})',
                      compact: true,
                    ),
                  if (hiddenSkillCount > 0)
                    StatusChip(
                      label: '+$hiddenSkillCount more',
                      type: AppStatusType.neutral,
                      compact: true,
                    ),
                ],
              ),
            ],
            if (candidate.interestedIn != null &&
                candidate.interestedIn!.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(
                'Interested In',
                style: textTheme.labelSmall?.copyWith(
                  color: AppColors.textMuted,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: AppSpacing.xxs),
              Wrap(
                spacing: AppSpacing.xs,
                runSpacing: AppSpacing.xxs,
                children: [
                  for (final type in candidate.interestedIn!)
                    StatusChip(
                      label: opportunityTypeLabels[type] ?? type,
                      type: AppStatusType.info,
                      compact: true,
                    ),
                ],
              ),
            ],
            const SizedBox(height: AppSpacing.sm),
            const Divider(height: 1),
            const SizedBox(height: AppSpacing.sm),
            if (compactAction)
              Align(
                alignment: Alignment.centerRight,
                child: SecondaryButton(
                  label: 'View Profile',
                  icon: Icons.person_outline,
                  onPressed: onViewProfile,
                ),
              )
            else
              SecondaryButton(
                label: 'View Profile',
                icon: Icons.person_outline,
                width: double.infinity,
                onPressed: onViewProfile,
              ),
          ],
        ),
      ),
    );
  }
}

/// A small leading-icon + text row for a scannable candidate fact (major,
/// university, graduation year) — wraps naturally rather than truncating,
/// so a long university/major name never gets clipped.
class _IconLine extends StatelessWidget {
  const _IconLine({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 15, color: AppColors.textMuted),
        const SizedBox(width: AppSpacing.xxs),
        Expanded(
          child: Text(
            text,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
        ),
      ],
    );
  }
}

/// A modal bottom sheet for the candidate-search filters -- major,
/// university, graduation year, skill. Mirrors
/// `StudentOpportunitiesScreen._FilterSheet`'s own local-state-until-Apply
/// shape.
class _FilterSheet extends StatefulWidget {
  const _FilterSheet({
    required this.major,
    required this.university,
    required this.graduationYear,
    required this.skill,
    required this.onApply,
  });

  final String? major;
  final String? university;
  final int? graduationYear;
  final String? skill;
  final void Function(
    String? major,
    String? university,
    int? graduationYear,
    String? skill,
  )
  onApply;

  @override
  State<_FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<_FilterSheet> {
  late final _majorController = TextEditingController(text: widget.major);
  late final _universityController = TextEditingController(
    text: widget.university,
  );
  late final _graduationYearController = TextEditingController(
    text: widget.graduationYear?.toString(),
  );
  late final _skillController = TextEditingController(text: widget.skill);

  @override
  void dispose() {
    _majorController.dispose();
    _universityController.dispose();
    _graduationYearController.dispose();
    _skillController.dispose();
    super.dispose();
  }

  void _apply() {
    widget.onApply(
      _majorController.text.trim().isEmpty ? null : _majorController.text.trim(),
      _universityController.text.trim().isEmpty
          ? null
          : _universityController.text.trim(),
      int.tryParse(_graduationYearController.text.trim()),
      _skillController.text.trim().isEmpty ? null : _skillController.text.trim(),
    );
    Navigator.of(context).pop();
  }

  void _clear() {
    widget.onApply(null, null, null, null);
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
            Center(
              child: Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: AppSpacing.sm),
                decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SectionHeader(title: 'Filters'),
            const SizedBox(height: AppSpacing.xs),
            AppTextField(
              controller: _majorController,
              label: 'Major (optional)',
              hint: 'e.g. Computer Science',
            ),
            const SizedBox(height: AppSpacing.inputSpacing),
            AppTextField(
              controller: _universityController,
              label: 'University (optional)',
              hint: 'e.g. State University',
            ),
            const SizedBox(height: AppSpacing.inputSpacing),
            AppTextField(
              controller: _graduationYearController,
              label: 'Graduation Year (optional)',
              hint: 'e.g. 2026',
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: AppSpacing.inputSpacing),
            AppTextField(
              controller: _skillController,
              label: 'Skill (optional)',
              hint: 'e.g. PHP',
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
