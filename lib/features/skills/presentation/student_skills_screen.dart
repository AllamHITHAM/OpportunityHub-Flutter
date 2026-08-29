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
import '../../../models/skill_model.dart';
import '../../../models/student_skill_model.dart';
import '../../../providers/student_skill_provider.dart';
import '../../../routes/app_routes.dart';

const _tabletBreakpoint = 600.0;
const _desktopBreakpoint = 1200.0;

enum _ScreenTier { mobile, tablet, desktop }

_ScreenTier _tierFor(double width) {
  if (width >= _desktopBreakpoint) return _ScreenTier.desktop;
  if (width >= _tabletBreakpoint) return _ScreenTier.tablet;
  return _ScreenTier.mobile;
}

/// The only two real `StudentSkill.source` values (`docs/BUSINESS_RULES.md`
/// section 9a) -- `all` is a local, UI-only filter option, never sent
/// anywhere.
enum _SourceFilter { all, manual, cvAi }

/// The real `StudentSkill.level` enum, exactly as `StoreStudentSkillRequest`
/// validates it -- used for both display and this screen's local level
/// filter.
const _levels = ['beginner', 'intermediate', 'advanced', 'expert'];

String _levelLabel(String level) =>
    level.isEmpty ? level : '${level[0].toUpperCase()}${level.substring(1)}';

/// A real skill profile (UI Phase 7) for the authenticated student's own
/// `StudentSkill` rows -- a summary, local search/filters, a richer
/// per-skill card, and (Phase 8A-6.3/UI Phase 7.2) a real, persisted Manual
/// Add Skill flow, all over the exact same [StudentSkillProvider].
/// Presentation only -- Manual Add reuses the pre-existing
/// `POST /student/skills` endpoint unchanged; the only new backend surface
/// is the read-only `GET /student/skills/catalog` this flow needed to have
/// a real catalog to pick from.
///
/// **Audited gaps this screen still deliberately does not paper over:**
/// - There is still no `PATCH`/`PUT` for a `StudentSkill` row, so there is
///   no Edit action (e.g. changing level after the fact) -- adding one
///   would need a real backend endpoint that doesn't exist yet.
/// - A `SkillSuggestion` (pending catalog review) is never returned by
///   `GET /student/skills` -- it isn't a `StudentSkill` at all until an
///   Admin approves it -- so there is no real "Pending Catalog Approval"
///   state to show among a student's *own* skills, and this screen never
///   invents one. Likewise, students still have no supported way to
///   *suggest* a name missing from the catalog (`SkillSuggestion.source`
///   only allows `ai_cv` to be created today) -- so Add Skill has no
///   "suggest a new skill" action either; see this phase's final report.
class StudentSkillsScreen extends StatefulWidget {
  const StudentSkillsScreen({super.key});

  @override
  State<StudentSkillsScreen> createState() => _StudentSkillsScreenState();
}

class _StudentSkillsScreenState extends State<StudentSkillsScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _entranceController;
  final _searchController = TextEditingController();
  _SourceFilter _sourceFilter = _SourceFilter.all;
  String? _selectedLevel;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<StudentSkillProvider>().load();
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

    _searchController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _entranceController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _confirmDelete(StudentSkillModel skill) async {
    final provider = context.read<StudentSkillProvider>();

    final confirmed = await showAppConfirmationDialog(
      context,
      title: 'Remove Skill',
      message:
          'Are you sure you want to remove "${skill.skillName}" from '
          'your profile?',
      confirmLabel: 'Remove',
      type: AppConfirmationType.danger,
    );
    if (!confirmed || !mounted) return;

    final success = await provider.deleteSkill(skill.id);
    if (!mounted) return;

    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Skill removed successfully')),
      );
    } else if (provider.actionErrorMessage != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(provider.actionErrorMessage!)));
    }
  }

  Future<void> _openAddSkillSheet() async {
    final provider = context.read<StudentSkillProvider>();
    final added = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => ChangeNotifierProvider.value(
        value: provider,
        child: const _AddSkillSheet(),
      ),
    );
    if (added == true && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Skill added successfully')));
    }
  }

  void _clearFilters() {
    setState(() {
      _searchController.clear();
      _sourceFilter = _SourceFilter.all;
      _selectedLevel = null;
    });
  }

  List<StudentSkillModel> _applyFilters(List<StudentSkillModel> skills) {
    final query = _searchController.text.trim().toLowerCase();

    return skills.where((skill) {
      if (query.isNotEmpty && !skill.skillName.toLowerCase().contains(query)) {
        return false;
      }
      if (_sourceFilter == _SourceFilter.manual && skill.isCvSupported) {
        return false;
      }
      if (_sourceFilter == _SourceFilter.cvAi && !skill.isCvSupported) {
        return false;
      }
      if (_selectedLevel != null && skill.level != _selectedLevel) {
        return false;
      }
      return true;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<StudentSkillProvider>();
    final tier = _tierFor(MediaQuery.sizeOf(context).width);

    return Scaffold(
      appBar: AppBar(
        title: const Text('My Skills'),
        actions: [
          const ThemeToggleButton(),
          IconButton(
            onPressed: () => context.push(AppRoutes.studentCvs),
            icon: const Icon(Icons.description_outlined),
            tooltip: 'My CVs',
          ),
        ],
      ),
      body: SafeArea(child: _buildBody(provider, tier)),
    );
  }

  Widget _buildBody(StudentSkillProvider provider, _ScreenTier tier) {
    if (provider.isLoading && provider.skills.isEmpty) {
      return const _SkillsLibrarySkeleton();
    }

    if (provider.errorMessage != null && provider.skills.isEmpty) {
      return AppErrorView(
        message: provider.errorMessage!,
        onRetry: () => provider.load(forceRefresh: true),
      );
    }

    final horizontalPadding = tier == _ScreenTier.mobile
        ? AppSpacing.screenHorizontal
        : AppSpacing.xl;
    final maxWidth = tier == _ScreenTier.desktop ? 1100.0 : 760.0;

    if (provider.skills.isEmpty) {
      return RefreshIndicator(
        onRefresh: () => provider.load(forceRefresh: true),
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _PageHeader(tier: tier, entranceController: _entranceController),
              SizedBox(
                height: 440,
                child: AppEmptyView(
                  icon: Icons.workspace_premium_outlined,
                  title: 'Build Your Skill Profile',
                  message:
                      'Analyze a CV to discover real skills from your '
                      'experience — accepted suggestions will appear here.',
                  actionLabel: 'Analyze My CV',
                  onAction: () => context.push(AppRoutes.studentCvs),
                ),
              ),
            ],
          ),
        ),
      );
    }

    final allSkills = provider.skills;
    final filtered = _applyFilters(allSkills);

    return RefreshIndicator(
      onRefresh: () => provider.load(forceRefresh: true),
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxWidth),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _PageHeader(tier: tier, entranceController: _entranceController),
                _Stagger(
                  controller: _entranceController,
                  index: 1,
                  count: 4,
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(
                      horizontalPadding,
                      AppSpacing.lg,
                      horizontalPadding,
                      0,
                    ),
                    child: _SummaryAndDiscoverRow(tier: tier, skills: allSkills),
                  ),
                ),
                _Stagger(
                  controller: _entranceController,
                  index: 2,
                  count: 4,
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(
                      horizontalPadding,
                      AppSpacing.lg,
                      horizontalPadding,
                      0,
                    ),
                    child: _FiltersAndSearch(
                      searchController: _searchController,
                      sourceFilter: _sourceFilter,
                      selectedLevel: _selectedLevel,
                      resultCount: filtered.length,
                      onSourceChanged: (value) =>
                          setState(() => _sourceFilter = value),
                      onLevelChanged: (value) =>
                          setState(() => _selectedLevel = value),
                      onAddSkill: _openAddSkillSheet,
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
                  child: AnimatedSize(
                    duration: AppMotion.reduced(context, AppMotion.normal),
                    curve: AppMotion.standard,
                    alignment: Alignment.topCenter,
                    child: AnimatedSwitcher(
                      duration: AppMotion.reduced(context, AppMotion.normal),
                      transitionBuilder: (child, animation) =>
                          FadeTransition(opacity: animation, child: child),
                      child: filtered.isEmpty
                          ? _NoMatchState(
                              key: const ValueKey('no-match'),
                              onClear: _clearFilters,
                            )
                          : _SkillsGrid(
                              key: const ValueKey('skills-grid'),
                              tier: tier,
                              skills: filtered,
                              entranceController: _entranceController,
                              isBusy: provider.isBusy,
                              onDelete: _confirmDelete,
                            ),
                    ),
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

/// Fades and slides a section in as part of the staged entrance — a private
/// per-file copy of the same small helper other premium screens this
/// session define (see e.g. `StudentCvScreen`'s own doc comment on why it's
/// kept separate rather than shared).
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

/// A compact page identity, matching `StudentCvScreen`'s own header
/// language. Plain primary color (not the `[primary, aiAccent]` gradient
/// `StudentCvScreen` uses) — this page is a general skill profile, most of
/// which is typically self-declared, not an AI-exclusive feature the way
/// CV analysis is.
class _PageHeader extends StatelessWidget {
  const _PageHeader({required this.tier, required this.entranceController});

  final _ScreenTier tier;
  final AnimationController entranceController;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final horizontalPadding = tier == _ScreenTier.mobile
        ? AppSpacing.screenHorizontal
        : AppSpacing.xl;

    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.primaryContainer.withValues(alpha: 0.5),
            AppColors.surface,
          ],
        ),
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          horizontalPadding,
          AppSpacing.lg,
          horizontalPadding,
          AppSpacing.md,
        ),
        child: _Stagger(
          controller: entranceController,
          index: 0,
          count: 4,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 44,
                height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.primary,
                  boxShadow: AppShadows.card,
                ),
                child: const Icon(
                  Icons.workspace_premium_outlined,
                  color: Colors.white,
                  size: 22,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'My Skills',
                      style: textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Build a clearer picture of what you know and where '
                      'your experience comes from.',
                      style: textTheme.bodyMedium?.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// [Skills Summary] + [Discover More] side by side at tablet/desktop
/// widths, stacked on mobile — matching `StudentCvScreen`'s own preferred
/// wide-Web concept. The summary uses only real, already-loaded
/// [StudentSkillModel] data; the discover panel is purely explanatory with
/// one real navigation action.
class _SummaryAndDiscoverRow extends StatelessWidget {
  const _SummaryAndDiscoverRow({required this.tier, required this.skills});

  final _ScreenTier tier;
  final List<StudentSkillModel> skills;

  @override
  Widget build(BuildContext context) {
    final summary = _SkillsSummaryCard(skills: skills);
    const discover = _DiscoverMoreCard();

    if (tier == _ScreenTier.mobile) {
      return Column(
        children: [summary, const SizedBox(height: AppSpacing.sm), discover],
      );
    }

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(flex: 2, child: summary),
          const SizedBox(width: AppSpacing.sm),
          const Expanded(flex: 3, child: discover),
        ],
      ),
    );
  }
}

/// Real, truthful counts only, derived from the full (unfiltered) skill
/// list — the summary never shifts as the student types a search query or
/// taps a filter chip below.
class _SkillsSummaryCard extends StatelessWidget {
  const _SkillsSummaryCard({required this.skills});

  final List<StudentSkillModel> skills;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final total = skills.length;
    final cvSupported = skills.where((s) => s.isCvSupported).length;
    final manual = total - cvSupported;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: AppRadius.largeRadius,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Skills Summary',
            style: textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: AppSpacing.sm),
          _SummaryRow(
            icon: Icons.workspace_premium_outlined,
            label: 'Total Skills',
            value: total,
          ),
          const SizedBox(height: AppSpacing.xs),
          _SummaryRow(
            icon: Icons.auto_awesome,
            iconColor: AppColors.aiAccent,
            valueColor: AppColors.aiAccentDark,
            label: 'CV-Supported',
            value: cvSupported,
          ),
          const SizedBox(height: AppSpacing.xs),
          _SummaryRow(
            icon: Icons.edit_note_rounded,
            label: 'Self-Declared',
            value: manual,
          ),
        ],
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({
    required this.icon,
    required this.label,
    required this.value,
    this.iconColor,
    this.valueColor,
  });

  final IconData icon;
  final String label;
  final int value;
  final Color? iconColor;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Row(
      children: [
        Icon(icon, size: 18, color: iconColor ?? AppColors.textSecondary),
        const SizedBox(width: AppSpacing.xs),
        Text(
          label,
          style: textTheme.bodySmall?.copyWith(color: AppColors.textSecondary),
        ),
        const Spacer(),
        TweenAnimationBuilder<int>(
          tween: IntTween(begin: 0, end: value),
          duration: AppMotion.reduced(context, const Duration(milliseconds: 700)),
          curve: AppMotion.entrance,
          builder: (context, animatedValue, _) => Text(
            '$animatedValue',
            style: textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
              color: valueColor,
            ),
          ),
        ),
      ],
    );
  }
}

/// Purely explanatory — describes the real, already-implemented AI CV
/// Analysis workflow and links to it. Restrained AI purple accent, exactly
/// like `StudentCvScreen`'s own `_AiHighlightCard`. This is the one real,
/// working way a student gains a *new* skill today — see this file's own
/// top doc comment on why there is no local "Add Skill" catalog form.
class _DiscoverMoreCard extends StatelessWidget {
  const _DiscoverMoreCard();

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.aiAccentBackground,
        borderRadius: AppRadius.largeRadius,
        border: Border.all(color: AppColors.aiAccent.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: [AppColors.primary, AppColors.aiAccent],
                  ),
                ),
                child: const Icon(
                  Icons.auto_awesome,
                  color: Colors.white,
                  size: 16,
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              Flexible(
                child: Text(
                  'Discover More Skills',
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                  style: textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: AppColors.aiAccentDark,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Analyze a CV to find more skills backed by real evidence from '
            'your experience — you choose which ones to add.',
            style: textTheme.bodySmall?.copyWith(color: AppColors.textSecondary),
          ),
          const SizedBox(height: AppSpacing.sm),
          SecondaryButton(
            label: 'Analyze My CV',
            icon: Icons.auto_awesome,
            height: 40,
            onPressed: () => context.push(AppRoutes.studentCvs),
          ),
        ],
      ),
    );
  }
}

/// Local search + the two real local filters (evidence source, level) —
/// no backend call, filtering an already-loaded list exactly as UI Phase 7
/// requires. [resultCount] is shown so the student can see the filtered
/// count without counting cards themselves.
class _FiltersAndSearch extends StatelessWidget {
  const _FiltersAndSearch({
    required this.searchController,
    required this.sourceFilter,
    required this.selectedLevel,
    required this.resultCount,
    required this.onSourceChanged,
    required this.onLevelChanged,
    required this.onAddSkill,
  });

  final TextEditingController searchController;
  final _SourceFilter sourceFilter;
  final String? selectedLevel;
  final int resultCount;
  final ValueChanged<_SourceFilter> onSourceChanged;
  final ValueChanged<String?> onLevelChanged;
  final VoidCallback onAddSkill;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: SectionHeader(
                title: 'Your Skills',
                subtitle: resultCount == 1 ? '1 skill' : '$resultCount skills',
                padding: EdgeInsets.zero,
              ),
            ),
            const SizedBox(width: AppSpacing.xs),
            SecondaryButton(
              key: const Key('add-skill-button'),
              label: 'Add Skill',
              icon: Icons.add,
              height: 40,
              onPressed: onAddSkill,
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        AppSearchField(
          controller: searchController,
          hint: 'Search skills',
        ),
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          spacing: AppSpacing.xs,
          runSpacing: AppSpacing.xs,
          children: [
            _FilterChip(
              key: const Key('skill-filter-source-all'),
              label: 'All',
              selected: sourceFilter == _SourceFilter.all,
              onTap: () => onSourceChanged(_SourceFilter.all),
            ),
            _FilterChip(
              key: const Key('skill-filter-source-cv_ai'),
              label: 'CV-Supported',
              icon: Icons.auto_awesome,
              selected: sourceFilter == _SourceFilter.cvAi,
              onTap: () => onSourceChanged(_SourceFilter.cvAi),
            ),
            _FilterChip(
              key: const Key('skill-filter-source-manual'),
              label: 'Self-Declared',
              selected: sourceFilter == _SourceFilter.manual,
              onTap: () => onSourceChanged(_SourceFilter.manual),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        Wrap(
          spacing: AppSpacing.xs,
          runSpacing: AppSpacing.xs,
          children: [
            _FilterChip(
              key: const Key('skill-filter-level-all'),
              label: 'All Levels',
              selected: selectedLevel == null,
              onTap: () => onLevelChanged(null),
            ),
            for (final level in _levels)
              _FilterChip(
                key: Key('skill-filter-level-$level'),
                label: _levelLabel(level),
                selected: selectedLevel == level,
                onTap: () => onLevelChanged(level),
              ),
          ],
        ),
      ],
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final duration = AppMotion.reduced(context, AppMotion.fast);

    return Material(
      color: AppColors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadius.pillRadius,
        child: AnimatedContainer(
          duration: duration,
          curve: AppMotion.standard,
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm,
            vertical: AppSpacing.xs,
          ),
          decoration: BoxDecoration(
            color: selected ? AppColors.primary : AppColors.surfaceVariant,
            borderRadius: AppRadius.pillRadius,
            border: Border.all(
              color: selected ? AppColors.primary : AppColors.border,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(
                  icon,
                  size: 14,
                  color: selected ? AppColors.onPrimary : AppColors.textSecondary,
                ),
                const SizedBox(width: 4),
              ],
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: selected ? AppColors.onPrimary : AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Shown when the student has real skills but the current search/filters
/// match none of them — distinct from the true empty state, and never
/// implies the profile itself is empty.
class _NoMatchState extends StatelessWidget {
  const _NoMatchState({super.key, required this.onClear});

  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return AppEmptyView(
      icon: Icons.search_off_rounded,
      title: 'No Matching Skills',
      message: 'Try a different search term or clear your filters.',
      actionLabel: 'Clear Search & Filters',
      onAction: onClear,
      compact: true,
    );
  }
}

/// 1 column on mobile, 2 on tablet/desktop — matching `StudentCvScreen`'s
/// own `_CvLibraryGrid`. `Wrap` (not `GridView`) since cards have genuinely
/// variable height (a long category label or evidence row wraps).
class _SkillsGrid extends StatelessWidget {
  const _SkillsGrid({
    super.key,
    required this.tier,
    required this.skills,
    required this.entranceController,
    required this.isBusy,
    required this.onDelete,
  });

  final _ScreenTier tier;
  final List<StudentSkillModel> skills;
  final AnimationController entranceController;
  final bool Function(int studentSkillId) isBusy;
  final ValueChanged<StudentSkillModel> onDelete;

  @override
  Widget build(BuildContext context) {
    if (tier == _ScreenTier.mobile) {
      return Column(
        key: const ValueKey('skills-grid-mobile'),
        children: [
          for (final skill in skills) ...[
            _Stagger(
              controller: entranceController,
              index: 3,
              count: 4,
              child: _SkillCard(
                skill: skill,
                isBusy: isBusy(skill.id),
                onDelete: () => onDelete(skill),
              ),
            ),
            if (skill != skills.last) const SizedBox(height: AppSpacing.sm),
          ],
        ],
      );
    }

    return LayoutBuilder(
      key: const ValueKey('skills-grid-desktop'),
      builder: (context, constraints) {
        const gap = AppSpacing.md;
        final cardWidth = (constraints.maxWidth - gap) / 2;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final skill in skills)
              SizedBox(
                width: cardWidth,
                child: _Stagger(
                  controller: entranceController,
                  index: 3,
                  count: 4,
                  child: _SkillCard(
                    skill: skill,
                    isBusy: isBusy(skill.id),
                    onDelete: () => onDelete(skill),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// One skill, presented as a real profile item — name, real level, real
/// evidence source, and its real catalog category when the backend has
/// one set. The purple `auto_awesome` accent and tinted border are the
/// only AI-attributed styling (design-system rule: AI purple appears
/// nowhere else) — the evidence badge text itself always stays the exact
/// two business-rule-defined labels ("CV-supported"/"Self-declared", see
/// `StudentSkillModel.evidenceLabel`), never "Verified".
class _SkillCard extends StatelessWidget {
  const _SkillCard({
    required this.skill,
    required this.isBusy,
    required this.onDelete,
  });

  final StudentSkillModel skill;
  final bool isBusy;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final isCvSupported = skill.isCvSupported;

    return Semantics(
      label:
          '${skill.skillName}, ${_levelLabel(skill.level)} level, '
          '${skill.evidenceLabel}',
      child: AppCard(
        borderColor: isCvSupported
            ? AppColors.aiAccent.withValues(alpha: 0.25)
            : null,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          if (isCvSupported) ...[
                            Icon(
                              Icons.auto_awesome,
                              size: 14,
                              color: AppColors.aiAccent,
                            ),
                            const SizedBox(width: 4),
                          ],
                          Flexible(
                            child: Text(
                              skill.skillName,
                              style: textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      if (skill.category != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          skill.category!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: textTheme.bodySmall?.copyWith(
                            color: AppColors.textMuted,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.xs),
                StatusChip(label: _levelLabel(skill.level), compact: true),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                StatusChip(
                  label: skill.evidenceLabel,
                  type: isCvSupported ? AppStatusType.info : AppStatusType.neutral,
                  icon: isCvSupported ? Icons.auto_awesome : Icons.edit_note_rounded,
                  compact: true,
                ),
                if (skill.yearsOfExperience != null) ...[
                  const SizedBox(width: AppSpacing.xs),
                  Flexible(
                    child: Text(
                      '${skill.yearsOfExperience} yrs experience',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.bodySmall?.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                ],
                const Spacer(),
                if (isBusy)
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: AppSpacing.xs),
                    child: AppLoading(compact: true),
                  )
                else
                  IconButton(
                    key: Key('delete-student-skill-${skill.id}'),
                    onPressed: onDelete,
                    icon: const Icon(Icons.delete_outline),
                    tooltip: 'Remove',
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// A polished skeleton for the initial load — real card skeletons, never a
/// single giant spinner.
class _SkillsLibrarySkeleton extends StatelessWidget {
  const _SkillsLibrarySkeleton();

  @override
  Widget build(BuildContext context) {
    return const SingleChildScrollView(
      padding: EdgeInsets.all(AppSpacing.screenHorizontal),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(height: AppSpacing.lg),
          AppSkeletonList(count: 4),
        ],
      ),
    );
  }
}

/// The real, persisted Manual Add Skill flow (Phase 8A-6.3/UI Phase 7.2):
/// search the real catalog (`GET /student/skills/catalog`), pick one real
/// Skill and one real level, and submit through the exact same
/// `POST /student/skills` endpoint every other skill-add path already
/// uses. The backend is the sole authority on `source` (always `manual`
/// here), duplicate rejection, and every other business rule — this sheet
/// never fabricates local state ahead of a real 201.
class _AddSkillSheet extends StatefulWidget {
  const _AddSkillSheet();

  @override
  State<_AddSkillSheet> createState() => _AddSkillSheetState();
}

class _AddSkillSheetState extends State<_AddSkillSheet> {
  final _searchController = TextEditingController();
  int? _selectedSkillId;
  String? _selectedLevel;
  bool _justAdded = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<StudentSkillProvider>().loadCatalog();
    });
    _searchController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<SkillModel> _filteredCatalog(List<SkillModel> catalog) {
    final query = _searchController.text.trim().toLowerCase();
    if (query.isEmpty) return catalog;
    return catalog.where((skill) => skill.name.toLowerCase().contains(query)).toList();
  }

  Future<void> _submit(StudentSkillProvider provider) async {
    final skillId = _selectedSkillId;
    final level = _selectedLevel;
    if (skillId == null || level == null || provider.isAddingSkill) return;

    final success = await provider.addSkill(skillId: skillId, level: level);
    if (!mounted || !success) return;

    setState(() => _justAdded = true);
    await Future.delayed(AppMotion.reduced(context, const Duration(milliseconds: 500)));
    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<StudentSkillProvider>();
    final textTheme = Theme.of(context).textTheme;
    final catalog = _filteredCatalog(provider.catalogSkills);
    final canSubmit = _selectedSkillId != null &&
        _selectedLevel != null &&
        !provider.isAddingSkill;
    final mediaQuery = MediaQuery.of(context);
    final maxSheetHeight = mediaQuery.size.height * 0.85;

    return Padding(
      padding: EdgeInsets.only(
        left: AppSpacing.screenHorizontal,
        right: AppSpacing.screenHorizontal,
        top: AppSpacing.md,
        bottom: mediaQuery.viewInsets.bottom + AppSpacing.md,
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxSheetHeight),
        child: AnimatedSwitcher(
          duration: AppMotion.reduced(context, AppMotion.normal),
          transitionBuilder: (child, animation) =>
              FadeTransition(opacity: animation, child: child),
          child: _justAdded
              ? const Padding(
                  key: ValueKey('add-skill-success'),
                  padding: EdgeInsets.symmetric(vertical: AppSpacing.lg),
                  child: AppSuccessView(
                    compact: true,
                    title: 'Skill Added',
                    message: 'Added to your profile as Self-Declared.',
                  ),
                )
              : Column(
                  key: const ValueKey('add-skill-form'),
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 36,
                          height: 36,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: AppColors.primaryContainer,
                          ),
                          child: Icon(
                            Icons.add_circle_outline,
                            color: AppColors.primaryDark,
                            size: 18,
                          ),
                        ),
                        const SizedBox(width: AppSpacing.xs),
                        const Expanded(
                          child: SectionHeader(title: 'Add Skill', padding: EdgeInsets.zero),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    AppSearchField(controller: _searchController, hint: 'Search skills'),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      'Available Skills',
                      style: textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: AppSpacing.xxs),
                    Expanded(child: _CatalogList(provider: provider, catalog: catalog, selectedSkillId: _selectedSkillId, onSelect: (id) => setState(() => _selectedSkillId = id))),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      'Proficiency Level',
                      style: textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: AppSpacing.xxs),
                    Wrap(
                      spacing: AppSpacing.xs,
                      runSpacing: AppSpacing.xs,
                      children: [
                        for (final level in _levels)
                          _FilterChip(
                            key: Key('add-skill-level-$level'),
                            label: _levelLabel(level),
                            selected: _selectedLevel == level,
                            onTap: () => setState(() => _selectedLevel = level),
                          ),
                      ],
                    ),
                    if (provider.addErrorMessage != null) ...[
                      const SizedBox(height: AppSpacing.xs),
                      AppErrorView(message: provider.addErrorMessage!, compact: true),
                    ],
                    const SizedBox(height: AppSpacing.md),
                    Row(
                      children: [
                        Expanded(
                          child: SecondaryButton(
                            label: 'Cancel',
                            onPressed: provider.isAddingSkill
                                ? null
                                : () => Navigator.of(context).pop(false),
                          ),
                        ),
                        const SizedBox(width: AppSpacing.xs),
                        Expanded(
                          child: PrimaryButton(
                            label: 'Add Skill',
                            isLoading: provider.isAddingSkill,
                            onPressed: canSubmit ? () => _submit(provider) : null,
                          ),
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

/// The scrollable catalog area inside [_AddSkillSheet] — real loading,
/// error/retry, empty-search, and selectable-row states.
class _CatalogList extends StatelessWidget {
  const _CatalogList({
    required this.provider,
    required this.catalog,
    required this.selectedSkillId,
    required this.onSelect,
  });

  final StudentSkillProvider provider;
  final List<SkillModel> catalog;
  final int? selectedSkillId;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    if (provider.isLoadingCatalog && provider.catalogSkills.isEmpty) {
      return const AppLoading(compact: true);
    }

    if (provider.catalogErrorMessage != null && provider.catalogSkills.isEmpty) {
      return AppErrorView(
        message: provider.catalogErrorMessage!,
        compact: true,
        onRetry: () => provider.loadCatalog(forceRefresh: true),
      );
    }

    if (catalog.isEmpty) {
      return const AppEmptyView(
        icon: Icons.search_off_rounded,
        message: 'No skills match your search.',
        compact: true,
      );
    }

    return ListView.builder(
      itemCount: catalog.length,
      itemBuilder: (context, index) {
        final skill = catalog[index];
        return _CatalogSkillRow(
          skill: skill,
          selected: skill.id == selectedSkillId,
          onTap: () => onSelect(skill.id),
        );
      },
    );
  }
}

class _CatalogSkillRow extends StatelessWidget {
  const _CatalogSkillRow({
    required this.skill,
    required this.selected,
    required this.onTap,
  });

  final SkillModel skill;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final duration = AppMotion.reduced(context, AppMotion.fast);

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xxs),
      child: Material(
        color: AppColors.transparent,
        child: InkWell(
          key: Key('catalog-skill-${skill.id}'),
          onTap: onTap,
          borderRadius: AppRadius.smallRadius,
          child: AnimatedContainer(
            duration: duration,
            curve: AppMotion.standard,
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.xs,
              vertical: AppSpacing.xs,
            ),
            decoration: BoxDecoration(
              color: selected
                  ? AppColors.primaryContainer.withValues(alpha: 0.4)
                  : AppColors.transparent,
              borderRadius: AppRadius.smallRadius,
              border: Border.all(
                color: selected ? AppColors.primary : AppColors.border,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  selected ? Icons.check_circle_rounded : Icons.circle_outlined,
                  size: 18,
                  color: selected ? AppColors.primary : AppColors.textMuted,
                ),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        skill.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                      ),
                      if (skill.category != null)
                        Text(
                          skill.category!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: textTheme.bodySmall?.copyWith(color: AppColors.textMuted),
                        ),
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
