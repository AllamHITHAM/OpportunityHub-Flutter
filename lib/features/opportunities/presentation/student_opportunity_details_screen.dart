import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/date_formatter.dart';
import '../../../core/widgets/app_widgets.dart';
import '../../../models/opportunity_model.dart';
import '../../../providers/student_applications_provider.dart';
import '../../../providers/student_cv_provider.dart';
import '../../../providers/student_opportunities_provider.dart';
import '../../applications/presentation/apply_bottom_sheet.dart';
import 'opportunity_display.dart';

/// Opportunity details for students. Reached by ID alone (a route
/// parameter, never GoRouter `extra`), so a direct URL visit or a browser
/// refresh renders correctly instead of crashing.
///
/// The only student action here is Apply — no save/quiz/interview controls
/// belong here yet.
class StudentOpportunityDetailsScreen extends StatefulWidget {
  const StudentOpportunityDetailsScreen({
    super.key,
    required this.opportunityId,
  });

  final int opportunityId;

  @override
  State<StudentOpportunityDetailsScreen> createState() =>
      _StudentOpportunityDetailsScreenState();
}

class _StudentOpportunityDetailsScreenState
    extends State<StudentOpportunityDetailsScreen> {
  @override
  void initState() {
    super.initState();
    // Deferred to the post-frame callback — see
    // StudentOpportunitiesScreen.initState for why calling this directly
    // here would violate Flutter's build-phase constraints.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<StudentOpportunitiesProvider>().loadOpportunityDetails(
        widget.opportunityId,
      );
      // Loaded proactively so "Already Applied" is accurate as soon as
      // this screen opens, and so CVs are ready by the time Apply is
      // tapped — both calls are reentrancy-safe and cheap if already
      // loaded.
      context.read<StudentApplicationsProvider>().loadApplications();
      context.read<StudentCvProvider>().loadCvs();
    });
  }

  Future<void> _openApplySheet(OpportunityModel opportunity) async {
    final applied = await showApplyBottomSheet(
      context,
      opportunityId: opportunity.id,
      opportunityTitle: opportunity.title,
    );
    if (applied && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Application submitted successfully')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<StudentOpportunitiesProvider>();
    final opportunity = provider.selectedOpportunity;
    final isThisOne = opportunity?.id == widget.opportunityId;

    return Scaffold(
      appBar: AppBar(title: const Text('Opportunity Details')),
      body: SafeArea(child: _buildBody(provider, opportunity, isThisOne)),
    );
  }

  Widget _buildBody(
    StudentOpportunitiesProvider provider,
    OpportunityModel? opportunity,
    bool isThisOne,
  ) {
    if (provider.isLoadingDetails && !isThisOne) {
      return const AppLoading();
    }

    if (provider.detailsErrorMessage != null && !isThisOne) {
      return AppErrorView(
        message: provider.detailsErrorMessage!,
        onRetry: () => provider.loadOpportunityDetails(
          widget.opportunityId,
          forceRefresh: true,
        ),
      );
    }

    if (opportunity == null || !isThisOne) {
      return const AppLoading();
    }

    final textTheme = Theme.of(context).textTheme;
    final organization = opportunity.organizationProfile;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.screenHorizontal),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(opportunity.title, style: textTheme.headlineSmall),
          if (organization != null) ...[
            const SizedBox(height: AppSpacing.xxs),
            Text(
              organization.organizationName,
              style: textTheme.titleSmall?.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xxs,
            children: [
              StatusChip(
                label:
                    opportunityTypeLabels[opportunity.opportunityType] ??
                    opportunity.opportunityType,
                type: AppStatusType.primary,
              ),
              StatusChip(
                label:
                    employmentTypeLabels[opportunity.employmentType] ??
                    opportunity.employmentType,
              ),
              StatusChip(
                label:
                    workModeLabels[opportunity.workMode] ??
                    opportunity.workMode,
              ),
              StatusChip(
                label:
                    experienceLevelLabels[opportunity.experienceLevel] ??
                    opportunity.experienceLevel,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          _ApplySection(
            opportunity: opportunity,
            onApply: () => _openApplySheet(opportunity),
          ),
          const SizedBox(height: AppSpacing.lg),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SectionHeader(title: 'Description'),
                Text(opportunity.description, style: textTheme.bodyMedium),
              ],
            ),
          ),
          if (opportunity.opportunitySkills.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SectionHeader(title: 'Skills'),
                  const SizedBox(height: AppSpacing.xs),
                  Wrap(
                    spacing: AppSpacing.xs,
                    runSpacing: AppSpacing.xxs,
                    children: [
                      for (final opportunitySkill
                          in opportunity.opportunitySkills)
                        StatusChip(
                          label: opportunitySkill.isRequired
                              ? '${opportunitySkill.skill.name} (Required)'
                              : opportunitySkill.skill.name,
                          type: opportunitySkill.isRequired
                              ? AppStatusType.primary
                              : AppStatusType.neutral,
                          compact: true,
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SectionHeader(title: 'Details'),
                OpportunityDetailRow(
                  label: 'Location',
                  value: opportunity.location ?? 'Not specified',
                ),
                OpportunityDetailRow(
                  label: 'Field of Study',
                  value: opportunity.fieldOfStudy ?? 'Not specified',
                ),
                OpportunityDetailRow(
                  label: 'Education Level',
                  value:
                      educationLevelLabels[opportunity.educationLevel] ??
                      'Not specified',
                ),
                OpportunityDetailRow(
                  label: 'Salary Range',
                  value: formatSalaryRange(opportunity),
                ),
                OpportunityDetailRow(
                  label: 'Application Deadline',
                  value: opportunity.applicationDeadline != null
                      ? formatDate(opportunity.applicationDeadline!)
                      : 'Not specified',
                ),
                OpportunityDetailRow(
                  label: 'Positions Available',
                  value: '${opportunity.positionsAvailable}',
                ),
                if (opportunity.createdAt != null)
                  OpportunityDetailRow(
                    label: 'Posted',
                    value: formatDate(opportunity.createdAt!),
                  ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
        ],
      ),
    );
  }
}

/// Either an "Already Applied" indicator or an "Apply Now" call to
/// action — driven entirely by `StudentApplicationsProvider.hasAppliedTo`,
/// the single source of truth for this on the Flutter side. Rebuilds
/// automatically the moment a successful apply appends to the provider's
/// list, so this flips to "Already Applied" immediately, with no restart
/// required.
class _ApplySection extends StatelessWidget {
  const _ApplySection({required this.opportunity, required this.onApply});

  final OpportunityModel opportunity;
  final VoidCallback onApply;

  @override
  Widget build(BuildContext context) {
    final applicationsProvider = context.watch<StudentApplicationsProvider>();
    final alreadyApplied = applicationsProvider.hasAppliedTo(opportunity.id);

    if (alreadyApplied) {
      return const Align(
        alignment: Alignment.centerLeft,
        child: StatusChip(
          label: 'Already Applied',
          type: AppStatusType.success,
          icon: Icons.check_circle_outline,
        ),
      );
    }

    return PrimaryButton(label: 'Apply Now', onPressed: onApply);
  }
}
