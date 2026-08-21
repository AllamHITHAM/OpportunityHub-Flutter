import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/app_widgets.dart';
import '../../../models/candidate_model.dart';
import '../../../providers/candidate_search_provider.dart';
import '../../applications/presentation/application_display.dart';
import 'invite_bottom_sheet.dart';

/// Candidate Search (Phase 8B-3, Flow B) — lets an Organization discover
/// Student profiles to invite. Filter/search-only, matching
/// `StudentOpportunitiesScreen`'s own search+filter-sheet shape.
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

  Future<void> _invite(CandidateModel candidate) async {
    final sent = await showInviteBottomSheet(context, candidate: candidate);
    if (!mounted) return;
    if (sent) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Invitation sent')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<CandidateSearchProvider>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Find Candidates'),
        actions: [
          IconButton(
            onPressed: _openFilters,
            icon: Icon(
              _hasActiveFilters ? Icons.filter_alt : Icons.filter_alt_outlined,
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
                controller: _nameController,
                hint: 'Search candidates by name',
                onChanged: _onNameChanged,
              ),
            ),
            Expanded(child: _buildBody(provider)),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(CandidateSearchProvider provider) {
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
      child: ListView.separated(
        padding: const EdgeInsets.all(AppSpacing.screenHorizontal),
        itemCount: provider.candidates.length,
        separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
        itemBuilder: (context, index) {
          final candidate = provider.candidates[index];
          return _CandidateCard(
            candidate: candidate,
            onInvite: () => _invite(candidate),
          );
        },
      ),
    );
  }
}

class _CandidateCard extends StatelessWidget {
  const _CandidateCard({required this.candidate, required this.onInvite});

  final CandidateModel candidate;
  final VoidCallback onInvite;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final subtitleParts = [
      candidate.major,
      candidate.university,
      if (candidate.graduationYear != null) 'Class of ${candidate.graduationYear}',
    ].whereType<String>().where((s) => s.isNotEmpty).toList();

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(candidate.name, style: textTheme.titleMedium),
          if (subtitleParts.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.xxs),
            Text(
              subtitleParts.join(' · '),
              style: textTheme.bodyMedium?.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.xs),
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xxs,
            children: [
              StatusChip(
                label: educationVerificationStatusLabel(
                  candidate.educationVerificationStatus,
                ),
                type: candidate.educationVerificationStatus == 'verified'
                    ? AppStatusType.success
                    : AppStatusType.neutral,
                compact: true,
              ),
              for (final skill in candidate.skills)
                StatusChip(
                  label: '${skill.name} (${skill.evidenceLabel})',
                  compact: true,
                ),
            ],
          ),
          if (candidate.alreadyApplied == true ||
              candidate.alreadyInvited == true) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              candidate.alreadyApplied == true
                  ? 'Already applied to this opportunity'
                  : 'Already invited to this opportunity',
              style: textTheme.bodySmall?.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.sm),
          Align(
            alignment: Alignment.centerRight,
            child: SecondaryButton(
              label: 'Invite',
              onPressed: candidate.alreadyApplied == true
                  ? null
                  : onInvite,
            ),
          ),
        ],
      ),
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
