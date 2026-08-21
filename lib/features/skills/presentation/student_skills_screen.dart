import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/app_widgets.dart';
import '../../../models/student_skill_model.dart';
import '../../../providers/student_skill_provider.dart';

/// A list of the authenticated student's own skills, each labeled with its
/// evidence source (Phase 8A-6.1) -- "CV-supported" for skills accepted
/// from an AI CV suggestion, "Self-declared" for manually-added ones -- and
/// removable regardless of source. No add action here; accepting an AI CV
/// suggestion already goes through `StudentCvProvider.addSelectedSkills`,
/// and the ordinary manual-add flow has no Flutter UI yet.
class StudentSkillsScreen extends StatefulWidget {
  const StudentSkillsScreen({super.key});

  @override
  State<StudentSkillsScreen> createState() => _StudentSkillsScreenState();
}

class _StudentSkillsScreenState extends State<StudentSkillsScreen> {
  @override
  void initState() {
    super.initState();
    // Deferred to the post-frame callback — see
    // StudentOpportunitiesScreen.initState for why calling this directly
    // here would violate Flutter's build-phase constraints.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<StudentSkillProvider>().load();
    });
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

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<StudentSkillProvider>();

    return Scaffold(
      appBar: AppBar(title: const Text('My Skills')),
      body: SafeArea(child: _buildBody(provider)),
    );
  }

  Widget _buildBody(StudentSkillProvider provider) {
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
      return const AppEmptyView(
        title: 'No Skills Yet',
        message:
            'Add skills manually or accept AI suggestions from a CV '
            'analysis to see them here.',
        icon: Icons.psychology_outlined,
      );
    }

    return RefreshIndicator(
      onRefresh: () => provider.load(forceRefresh: true),
      child: ListView.separated(
        padding: const EdgeInsets.all(AppSpacing.screenHorizontal),
        itemCount: provider.skills.length,
        separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
        itemBuilder: (context, index) {
          final skill = provider.skills[index];
          return _SkillCard(
            skill: skill,
            isBusy: provider.isBusy(skill.id),
            onDelete: () => _confirmDelete(skill),
          );
        },
      ),
    );
  }
}

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

    return AppCard(
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(skill.skillName, style: textTheme.titleMedium),
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  skill.evidenceLabel,
                  style: textTheme.bodySmall?.copyWith(
                    color: skill.isCvSupported
                        ? AppColors.info
                        : AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
          StatusChip(
            label: skill.level,
            type: skill.isCvSupported
                ? AppStatusType.info
                : AppStatusType.neutral,
            compact: true,
          ),
          if (isBusy)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: AppSpacing.sm),
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
    );
  }
}
