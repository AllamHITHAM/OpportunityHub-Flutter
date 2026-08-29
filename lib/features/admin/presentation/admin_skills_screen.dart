import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/date_formatter.dart';
import '../../../core/widgets/app_widgets.dart';
import '../../../models/skill_model.dart';
import '../../../models/skill_suggestion_model.dart';
import '../../../providers/admin_skill_suggestions_provider.dart';
import '../../../providers/admin_skills_provider.dart';

/// Admin Manage Skills Final UI + Responsive Fix: the same centered
/// desktop max-width and breakpoint already established on the polished
/// Admin Dashboard — not a new, competing value invented for this screen.
const _desktopBreakpoint = 900.0;
const _maxContentWidth = 900.0;

/// Lists every platform skill and lets an admin create, rename, or delete
/// one. `category` exists on the backend record but isn't collected or
/// shown here — this phase's UI only manages `name`.
class AdminSkillsScreen extends StatefulWidget {
  const AdminSkillsScreen({super.key});

  @override
  State<AdminSkillsScreen> createState() => _AdminSkillsScreenState();
}

class _AdminSkillsScreenState extends State<AdminSkillsScreen> {
  @override
  void initState() {
    super.initState();
    // Deferred to the post-frame callback — see
    // StudentOpportunitiesScreen.initState for why calling this directly
    // here would violate Flutter's build-phase constraints. Called
    // exactly once here, regardless of which tab is active or how many
    // times the admin switches between them -- see the class doc comment
    // below for why switching tabs never re-fetches.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<AdminSkillsProvider>().load();
      // Independent of the catalog load above — a pending-suggestions
      // failure must never block the rest of this screen (see
      // _PendingSuggestionsTab, which renders its own tab-level
      // loading/error state).
      context.read<AdminSkillSuggestionsProvider>().load();
    });
  }

  Future<void> _openAddSheet() async {
    final provider = context.read<AdminSkillsProvider>();
    final created = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => ChangeNotifierProvider.value(
        value: provider,
        child: const _SkillFormSheet(),
      ),
    );
    if (created == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Skill created successfully')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final suggestionsProvider = context.watch<AdminSkillSuggestionsProvider>();
    final skillsProvider = context.watch<AdminSkillsProvider>();

    // Admin Manage Skills — UX Polish: two real tabs, not one long page
    // with Pending Suggestions stacked above the Skill Catalog — with
    // many pending suggestions, the admin previously had to scroll past
    // all of them just to reach the catalog. `DefaultTabController`
    // (the standard Flutter/Material tab mechanism, styled with this
    // app's own tokens below) is what drives both `TabBar` and
    // `TabBarView` here; neither tab's own `load()` is ever called on a
    // tab switch (only once, in `initState` above), so switching tabs
    // never re-fetches — each tab just shows whatever its own provider
    // already holds. The overflow fix itself (`CustomScrollView` +
    // genuine `SliverList`s) is unchanged and now lives inside each of
    // the two tabs below, one real dataset per tab instead of both
    // concatenated into one scroll region.
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Manage Skills'),
          actions: [
            // Deliberately global (both tabs), not swapped based on the
            // active tab — the simpler of the two options the spec
            // allows, and already how every other AppBar action in this
            // app behaves.
            IconButton(
              onPressed: _openAddSheet,
              icon: const Icon(Icons.add),
              tooltip: 'Add Skill',
            ),
          ],
          bottom: TabBar(
            labelColor: AppColors.primaryDark,
            unselectedLabelColor: AppColors.textSecondary,
            indicatorColor: AppColors.primary,
            tabs: [
              Tab(
                text:
                    'Pending Suggestions (${suggestionsProvider.suggestions.length})',
              ),
              // Never "Accepted" -- this tab holds every official Skill,
              // both AI-suggestion-approved and Admin-created directly.
              Tab(text: 'Skill Catalog (${skillsProvider.skills.length})'),
            ],
          ),
        ),
        body: const SafeArea(
          child: TabBarView(
            children: [_PendingSuggestionsTab(), _SkillCatalogTab()],
          ),
        ),
      ),
    );
  }
}

/// The "Pending Suggestions" tab -- exactly the same real data/actions
/// (Approve/Reject, loading/error/busy states) as before this phase, now
/// as its own full tab instead of a section stacked above the catalog.
/// `AutomaticKeepAliveClientMixin` keeps this tab's own scroll position
/// intact when the admin switches to Skill Catalog and back, rather than
/// resetting to the top every time.
class _PendingSuggestionsTab extends StatefulWidget {
  const _PendingSuggestionsTab();

  @override
  State<_PendingSuggestionsTab> createState() =>
      _PendingSuggestionsTabState();
}

class _PendingSuggestionsTabState extends State<_PendingSuggestionsTab>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final provider = context.watch<AdminSkillSuggestionsProvider>();

    return RefreshIndicator(
      onRefresh: () => provider.load(forceRefresh: true),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final horizontalPadding = width >= _desktopBreakpoint
              ? AppSpacing.xl
              : AppSpacing.screenHorizontal;

          return CustomScrollView(
            // Keyed so tests can target this tab's own `Scrollable`
            // precisely -- with `AutomaticKeepAliveClientMixin` on both
            // tabs, more than one `Scrollable` (this one, the Skill
            // Catalog tab's, and the `TabBarView`'s own horizontal
            // `PageView`) can coexist in the tree at once.
            key: const ValueKey('pending-suggestions-scroll'),
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              const _PendingSuggestionsStateSliver(),
              _PendingSuggestionsSliverList(
                horizontalPadding: horizontalPadding,
              ),
            ],
          );
        },
      ),
    );
  }
}

/// The Skill Catalog tab -- Search, the skill list itself, and Add/Edit/
/// Delete, all exactly as before this phase, now scoped to its own tab.
/// `AutomaticKeepAliveClientMixin` keeps the entered search text and
/// scroll position intact across a tab switch.
class _SkillCatalogTab extends StatefulWidget {
  const _SkillCatalogTab();

  @override
  State<_SkillCatalogTab> createState() => _SkillCatalogTabState();
}

class _SkillCatalogTabState extends State<_SkillCatalogTab>
    with AutomaticKeepAliveClientMixin {
  final _searchController = TextEditingController();
  String _query = '';

  @override
  bool get wantKeepAlive => true;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  /// Client-side only — name, case-insensitive. No backend query params,
  /// per this phase's scope.
  List<SkillModel> _filtered(List<SkillModel> skills) {
    final query = _query.trim().toLowerCase();
    if (query.isEmpty) return skills;
    return skills
        .where((skill) => skill.name.toLowerCase().contains(query))
        .toList();
  }

  Future<void> _openAddSheet() async {
    final provider = context.read<AdminSkillsProvider>();
    final created = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => ChangeNotifierProvider.value(
        value: provider,
        child: const _SkillFormSheet(),
      ),
    );
    if (created == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Skill created successfully')),
      );
    }
  }

  Future<void> _openEditSheet(SkillModel skill) async {
    final provider = context.read<AdminSkillsProvider>();
    final updated = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => ChangeNotifierProvider.value(
        value: provider,
        child: _SkillFormSheet(existingSkill: skill),
      ),
    );
    if (updated == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Skill updated successfully')),
      );
    }
  }

  Future<void> _confirmDelete(SkillModel skill) async {
    final provider = context.read<AdminSkillsProvider>();

    final confirmed = await showAppConfirmationDialog(
      context,
      title: 'Delete Skill',
      message: 'Are you sure you want to delete this skill?',
      confirmLabel: 'Delete',
      type: AppConfirmationType.danger,
    );
    if (!confirmed || !mounted) return;

    final success = await provider.deleteSkill(skill.id);
    if (!mounted) return;

    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Skill deleted successfully')),
      );
    } else if (provider.actionErrorMessage != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(provider.actionErrorMessage!)));
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final provider = context.watch<AdminSkillsProvider>();

    if (provider.isLoading && provider.skills.isEmpty) {
      return const AppSkeletonList();
    }

    if (provider.errorMessage != null && provider.skills.isEmpty) {
      return AppErrorView(
        message: provider.errorMessage!,
        onRetry: () => provider.load(forceRefresh: true),
      );
    }

    if (provider.skills.isEmpty) {
      return AppEmptyView(
        message: 'No skills available.',
        icon: Icons.psychology_outlined,
        actionLabel: 'Add Skill',
        onAction: _openAddSheet,
      );
    }

    final filtered = _filtered(provider.skills);

    return RefreshIndicator(
      onRefresh: () => provider.load(forceRefresh: true),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final horizontalPadding = width >= _desktopBreakpoint
              ? AppSpacing.xl
              : AppSpacing.screenHorizontal;

          return CustomScrollView(
            // See the matching key on the Pending Suggestions tab's own
            // `CustomScrollView` for why this is keyed.
            key: const ValueKey('skill-catalog-scroll'),
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverPadding(
                padding: EdgeInsets.fromLTRB(
                  horizontalPadding,
                  AppSpacing.screenHorizontal,
                  horizontalPadding,
                  0,
                ),
                sliver: SliverToBoxAdapter(
                  child: _Centered(
                    child: AppSearchField(
                      controller: _searchController,
                      hint: 'Search by name',
                      onChanged: (value) => setState(() => _query = value),
                    ),
                  ),
                ),
              ),
              if (provider.errorMessage != null)
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(
                    horizontalPadding,
                    AppSpacing.sm,
                    horizontalPadding,
                    0,
                  ),
                  sliver: SliverToBoxAdapter(
                    child: _Centered(
                      child: AppErrorView(
                        compact: true,
                        title: 'Refresh Failed',
                        message: provider.errorMessage!,
                        onRetry: () => provider.load(forceRefresh: true),
                      ),
                    ),
                  ),
                ),
              if (filtered.isEmpty)
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: Padding(
                    padding: EdgeInsets.only(top: AppSpacing.xxl),
                    child: _Centered(
                      child: AppEmptyView(
                        title: 'No Matches',
                        message: 'No skills match your search.',
                        icon: Icons.search_off_rounded,
                      ),
                    ),
                  ),
                )
              else
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(
                    horizontalPadding,
                    AppSpacing.screenHorizontal,
                    horizontalPadding,
                    AppSpacing.screenHorizontal,
                  ),
                  sliver: SliverList.separated(
                    itemCount: filtered.length,
                    separatorBuilder: (_, _) =>
                        const SizedBox(height: AppSpacing.sm),
                    itemBuilder: (context, index) {
                      final skill = filtered[index];
                      return _Centered(
                        child: _SkillCard(
                          skill: skill,
                          isBusy: provider.isBusy(skill.id),
                          onEdit: () => _openEditSheet(skill),
                          onDelete: () => _confirmDelete(skill),
                        ),
                      );
                    },
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

/// Caps content at [_maxContentWidth] on a wide desktop viewport (matching
/// the polished Admin Dashboard's own centered-content treatment) while
/// leaving the sliver it's used inside at its full natural width -- so a
/// `RefreshIndicator`'s pull gesture, and each `SliverPadding`'s own
/// horizontal inset, still span the entire scrollable area rather than
/// shrinking to the capped column too. Mirrors
/// `organization_quiz_results_screen.dart`'s own private `_Centered`
/// exactly (not shared between files -- this app's own established
/// convention for this kind of small, screen-local layout helper).
class _Centered extends StatelessWidget {
  const _Centered({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: _maxContentWidth),
        child: child,
      ),
    );
  }
}

/// Admin Manage Skills — UX Polish: the Pending Suggestions tab's own
/// loading/error/empty state, as a sliver so it composes directly with
/// [_PendingSuggestionsSliverList] inside the same `CustomScrollView`
/// (see `_PendingSuggestionsTab`). Now that Pending Suggestions is its
/// own full tab (previously a section stacked above the catalog on one
/// long page), a genuinely empty list shows an explicit "No pending
/// skill suggestions." message instead of rendering nothing — an empty
/// tab with literally no content would otherwise look broken, and the
/// spec's own empty-state text calls for this explicitly.
class _PendingSuggestionsStateSliver extends StatelessWidget {
  const _PendingSuggestionsStateSliver();

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AdminSkillSuggestionsProvider>();

    if (provider.isLoading && provider.suggestions.isEmpty) {
      return const SliverFillRemaining(
        hasScrollBody: false,
        child: AppSkeletonList(),
      );
    }

    if (provider.errorMessage != null && provider.suggestions.isEmpty) {
      return SliverFillRemaining(
        hasScrollBody: false,
        child: AppErrorView(
          title: 'Could Not Load Suggestions',
          message: provider.errorMessage!,
          onRetry: () => provider.load(forceRefresh: true),
        ),
      );
    }

    if (provider.suggestions.isEmpty) {
      return const SliverFillRemaining(
        hasScrollBody: false,
        child: AppEmptyView(
          message: 'No pending skill suggestions.',
          icon: Icons.psychology_outlined,
        ),
      );
    }

    return const SliverToBoxAdapter(child: SizedBox.shrink());
  }
}

/// The Pending Suggestions rows themselves, as a genuine `SliverList`
/// (never an eagerly-built `Column` of every row at once) — this,
/// combined with [_PendingSuggestionsStateSliver] above never living
/// inside a fixed-height, non-scrolling `Column`, is the actual overflow
/// fix: a real dataset of 100+ suggestions now lays out and scrolls
/// exactly like any other list, instead of forcing the Skill Catalog
/// beneath it into negative available height (back when both lived on
/// one page — now each has its own full tab either way).
///
/// A widget whose `build()` returns a sliver (`SliverList`/
/// `SliverToBoxAdapter`) is valid Flutter as long as it's only ever
/// placed directly inside a `CustomScrollView`'s own `slivers` list, the
/// same way [_PendingSuggestionsStateSliver] above and [_Centered]
/// elsewhere in this file are both plain box widgets used the same way.
class _PendingSuggestionsSliverList extends StatelessWidget {
  const _PendingSuggestionsSliverList({required this.horizontalPadding});

  final double horizontalPadding;

  Future<void> _approve(BuildContext context, int suggestionId) async {
    final provider = context.read<AdminSkillSuggestionsProvider>();
    final success = await provider.approve(suggestionId);
    if (!context.mounted) return;

    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Skill suggestion approved')),
      );
    } else if (provider.actionErrorMessage != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(provider.actionErrorMessage!)));
    }
  }

  Future<void> _reject(BuildContext context, int suggestionId) async {
    final provider = context.read<AdminSkillSuggestionsProvider>();
    final success = await provider.reject(suggestionId);
    if (!context.mounted) return;

    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Skill suggestion rejected')),
      );
    } else if (provider.actionErrorMessage != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(provider.actionErrorMessage!)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AdminSkillSuggestionsProvider>();

    if (provider.suggestions.isEmpty) {
      return const SliverToBoxAdapter(child: SizedBox.shrink());
    }

    return SliverPadding(
      padding: EdgeInsets.fromLTRB(
        horizontalPadding,
        0,
        horizontalPadding,
        AppSpacing.screenHorizontal,
      ),
      sliver: SliverList.separated(
        itemCount: provider.suggestions.length,
        separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.xs),
        itemBuilder: (context, index) {
          final suggestion = provider.suggestions[index];
          return _Centered(
            child: _SuggestionCard(
              suggestion: suggestion,
              isBusy: provider.isBusy(suggestion.id),
              onApprove: () => _approve(context, suggestion.id),
              onReject: () => _reject(context, suggestion.id),
            ),
          );
        },
      ),
    );
  }
}

/// One pending suggestion, as its own compact card — mirrors [_SkillCard]
/// below (name/action row) so the Pending Suggestions and Skill Catalog
/// sections read as one consistent visual language, and so both scale to
/// a large real dataset the same way (a `SliverList` of individually
/// bordered cards, not one unbounded card containing every row).
class _SuggestionCard extends StatelessWidget {
  const _SuggestionCard({
    required this.suggestion,
    required this.isBusy,
    required this.onApprove,
    required this.onReject,
  });

  final SkillSuggestionModel suggestion;
  final bool isBusy;
  final VoidCallback onApprove;
  final VoidCallback onReject;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return AppCard(
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // No `overflow`/`maxLines` cap -- a long skill name must
                // wrap onto more lines, never truncate or push the
                // Approve/Reject actions off-card.
                Text(suggestion.name, style: textTheme.bodyMedium),
                Text(
                  'From AI CV extraction',
                  style: textTheme.bodySmall?.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          if (isBusy)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: AppSpacing.sm),
              child: AppLoading(compact: true),
            )
          else ...[
            Semantics(
              label: 'Approve suggestion: ${suggestion.name}',
              button: true,
              child: IconButton(
                key: Key('approve-suggestion-${suggestion.id}'),
                onPressed: onApprove,
                icon: const Icon(Icons.check_circle_outline),
                color: AppColors.success,
                tooltip: 'Approve suggestion',
              ),
            ),
            Semantics(
              label: 'Reject suggestion: ${suggestion.name}',
              button: true,
              child: IconButton(
                key: Key('reject-suggestion-${suggestion.id}'),
                onPressed: onReject,
                icon: const Icon(Icons.cancel_outlined),
                color: AppColors.error,
                tooltip: 'Reject suggestion',
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _SkillCard extends StatelessWidget {
  const _SkillCard({
    required this.skill,
    required this.isBusy,
    required this.onEdit,
    required this.onDelete,
  });

  final SkillModel skill;
  final bool isBusy;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final createdAt = skill.createdAt;

    return AppCard(
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(skill.name, style: textTheme.titleMedium),
                if (createdAt != null) ...[
                  const SizedBox(height: AppSpacing.xxs),
                  Text(
                    'Added ${formatDate(createdAt)}',
                    style: textTheme.bodySmall?.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (isBusy)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: AppSpacing.sm),
              child: AppLoading(compact: true),
            )
          else ...[
            IconButton(
              key: Key('edit-skill-${skill.id}'),
              onPressed: onEdit,
              icon: const Icon(Icons.edit_outlined),
              tooltip: 'Edit',
            ),
            IconButton(
              key: Key('delete-skill-${skill.id}'),
              onPressed: onDelete,
              icon: const Icon(Icons.delete_outline),
              tooltip: 'Delete',
            ),
          ],
        ],
      ),
    );
  }
}

/// A modal bottom sheet used for both creating a new skill and renaming an
/// existing one — just one text field, so a sheet keeps this lightweight
/// rather than a full route/screen (see `_AddCvSheet` for the identical
/// pattern).
class _SkillFormSheet extends StatefulWidget {
  const _SkillFormSheet({this.existingSkill});

  /// `null` means "create a new skill"; non-null means "edit this one".
  final SkillModel? existingSkill;

  @override
  State<_SkillFormSheet> createState() => _SkillFormSheetState();
}

class _SkillFormSheetState extends State<_SkillFormSheet> {
  final _formKey = GlobalKey<FormState>();
  late final _nameController = TextEditingController(
    text: widget.existingSkill?.name ?? '',
  );

  bool get _isEdit => widget.existingSkill != null;

  // Matches the backend's own limit (StoreSkillRequest/UpdateSkillRequest:
  // name max:255) so an over-length value is rejected locally instead of
  // round-tripping to a 422.
  static const _nameMaxLength = 255;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  // No `isLoading` guard here deliberately: `fieldErrors` is already
  // cleared to `{}` at the start of every create/update call (see the
  // provider), so this naturally returns `null` while a request is
  // genuinely in flight without needing a separate check.
  String? _fieldError(AdminSkillsProvider provider) {
    final messages = provider.fieldErrors['name'];
    if (messages == null || messages.isEmpty) return null;
    return messages.first;
  }

  String? _validateName(String? value, AdminSkillsProvider provider) {
    final backendError = _fieldError(provider);
    if (backendError != null) return backendError;

    final trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) {
      return 'Name is required';
    }
    if (trimmed.length > _nameMaxLength) {
      return 'Name must be $_nameMaxLength characters or fewer';
    }
    return null;
  }

  Future<void> _submit(AdminSkillsProvider provider) async {
    FocusScope.of(context).unfocus();

    final isValid = _formKey.currentState?.validate() ?? false;
    if (!isValid) return;

    final name = _nameController.text.trim();
    final success = _isEdit
        ? await provider.updateSkill(
            skillId: widget.existingSkill!.id,
            name: name,
          )
        : await provider.createSkill(name: name);
    if (!mounted) return;

    if (!success) {
      // Forces the field to re-check `provider.fieldErrors` and show the
      // backend's message immediately, without waiting for the next field
      // interaction.
      _formKey.currentState?.validate();
      return;
    }

    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AdminSkillsProvider>();
    final isLoading = _isEdit
        ? provider.isBusy(widget.existingSkill!.id)
        : provider.isCreating;
    // A field error is already shown inline by the field's own validator
    // — showing the same failure again as a generic form-level message
    // underneath would be redundant noise. Only genuinely form-level
    // failures (e.g. the backend's 409 "A skill with this name already
    // exists" race-condition fallback, which has no field error) show here.
    final showFormError =
        provider.actionErrorMessage != null && _fieldError(provider) == null;

    return Padding(
      padding: EdgeInsets.only(
        left: AppSpacing.screenHorizontal,
        right: AppSpacing.screenHorizontal,
        top: AppSpacing.md,
        bottom: MediaQuery.of(context).viewInsets.bottom + AppSpacing.md,
      ),
      child: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              SectionHeader(title: _isEdit ? 'Edit Skill' : 'Add Skill'),
              const SizedBox(height: AppSpacing.xs),
              AppTextField(
                controller: _nameController,
                label: 'Name',
                hint: 'e.g. Flutter',
                enabled: !isLoading,
                textInputAction: TextInputAction.done,
                maxLength: _nameMaxLength,
                validator: (value) => _validateName(value, provider),
              ),
              if (showFormError) ...[
                const SizedBox(height: AppSpacing.xs),
                AppErrorView(
                  title: 'Something Went Wrong',
                  message: provider.actionErrorMessage!,
                  compact: true,
                ),
              ],
              const SizedBox(height: AppSpacing.lg),
              PrimaryButton(
                label: _isEdit ? 'Save Changes' : 'Add Skill',
                isLoading: isLoading,
                onPressed: () => _submit(provider),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
