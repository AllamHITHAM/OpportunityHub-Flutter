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

/// Lists every platform skill and lets an admin create, rename, or delete
/// one. `category` exists on the backend record but isn't collected or
/// shown here — this phase's UI only manages `name`.
class AdminSkillsScreen extends StatefulWidget {
  const AdminSkillsScreen({super.key});

  @override
  State<AdminSkillsScreen> createState() => _AdminSkillsScreenState();
}

class _AdminSkillsScreenState extends State<AdminSkillsScreen> {
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void initState() {
    super.initState();
    // Deferred to the post-frame callback — see
    // StudentOpportunitiesScreen.initState for why calling this directly
    // here would violate Flutter's build-phase constraints.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<AdminSkillsProvider>().load();
      // Independent of the catalog load above — a pending-suggestions
      // failure must never block the rest of this screen (see
      // _PendingSuggestionsSection, which renders its own section-level
      // loading/error state).
      context.read<AdminSkillSuggestionsProvider>().load();
    });
  }

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
    final provider = context.watch<AdminSkillsProvider>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Manage Skills'),
        actions: [
          IconButton(
            onPressed: _openAddSheet,
            icon: const Icon(Icons.add),
            tooltip: 'Add Skill',
          ),
        ],
      ),
      body: SafeArea(child: _buildBody(provider)),
    );
  }

  Widget _buildBody(AdminSkillsProvider provider) {
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
        title: 'No Skills Yet',
        message: 'There are no skills on the platform yet.',
        icon: Icons.psychology_outlined,
        actionLabel: 'Add Skill',
        onAction: _openAddSheet,
      );
    }

    final filtered = _filtered(provider.skills);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(
            AppSpacing.screenHorizontal,
            AppSpacing.screenHorizontal,
            AppSpacing.screenHorizontal,
            0,
          ),
          child: _PendingSuggestionsSection(),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.screenHorizontal,
            AppSpacing.screenHorizontal,
            AppSpacing.screenHorizontal,
            0,
          ),
          child: AppSearchField(
            controller: _searchController,
            hint: 'Search by name',
            onChanged: (value) => setState(() => _query = value),
          ),
        ),
        if (provider.errorMessage != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.screenHorizontal,
              AppSpacing.sm,
              AppSpacing.screenHorizontal,
              0,
            ),
            child: AppErrorView(
              compact: true,
              title: 'Refresh Failed',
              message: provider.errorMessage!,
              onRetry: () => provider.load(forceRefresh: true),
            ),
          ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: () => provider.load(forceRefresh: true),
            child: filtered.isEmpty
                ? ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: const [
                      SizedBox(height: AppSpacing.xxl),
                      AppEmptyView(
                        title: 'No Matches',
                        message: 'No skills match your search.',
                        icon: Icons.search_off_rounded,
                      ),
                    ],
                  )
                : ListView.separated(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(AppSpacing.screenHorizontal),
                    itemCount: filtered.length,
                    separatorBuilder: (_, _) =>
                        const SizedBox(height: AppSpacing.sm),
                    itemBuilder: (context, index) {
                      final skill = filtered[index];
                      return _SkillCard(
                        skill: skill,
                        isBusy: provider.isBusy(skill.id),
                        onEdit: () => _openEditSheet(skill),
                        onDelete: () => _confirmDelete(skill),
                      );
                    },
                  ),
          ),
        ),
      ],
    );
  }
}

/// Phase 8A-6.1: pending AI-derived Skill catalog suggestions awaiting
/// Admin review. Renders nothing when there are none and nothing is
/// loading/erroring, so it never adds empty chrome to a catalog with no
/// suggestions outstanding — the same posture other section-level widgets
/// in this app already take (e.g. Organization's `_AssessmentSection`).
class _PendingSuggestionsSection extends StatelessWidget {
  const _PendingSuggestionsSection();

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

    if (provider.isLoading && provider.suggestions.isEmpty) {
      return const Padding(
        padding: EdgeInsets.only(bottom: AppSpacing.sm),
        child: AppLoading(compact: true),
      );
    }

    if (provider.errorMessage != null && provider.suggestions.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.sm),
        child: AppErrorView(
          compact: true,
          title: 'Could Not Load Suggestions',
          message: provider.errorMessage!,
          onRetry: () => provider.load(forceRefresh: true),
        ),
      );
    }

    if (provider.suggestions.isEmpty) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SectionHeader(title: 'Pending Skill Suggestions'),
            const SizedBox(height: AppSpacing.xs),
            for (final suggestion in provider.suggestions)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                child: _SuggestionRow(
                  suggestion: suggestion,
                  isBusy: provider.isBusy(suggestion.id),
                  onApprove: () => _approve(context, suggestion.id),
                  onReject: () => _reject(context, suggestion.id),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _SuggestionRow extends StatelessWidget {
  const _SuggestionRow({
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

    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
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
          IconButton(
            key: Key('approve-suggestion-${suggestion.id}'),
            onPressed: onApprove,
            icon: const Icon(Icons.check_circle_outline),
            color: AppColors.success,
            tooltip: 'Approve',
          ),
          IconButton(
            key: Key('reject-suggestion-${suggestion.id}'),
            onPressed: onReject,
            icon: const Icon(Icons.cancel_outlined),
            color: AppColors.error,
            tooltip: 'Reject',
          ),
        ],
      ],
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
