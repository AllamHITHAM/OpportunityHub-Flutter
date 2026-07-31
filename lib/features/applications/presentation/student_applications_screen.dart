import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/date_formatter.dart';
import '../../../core/widgets/app_widgets.dart';
import '../../../models/application_model.dart';
import '../../../providers/student_applications_provider.dart';
import '../../../routes/app_routes.dart';
import 'application_display.dart';

/// Lists the authenticated student's own applications. No applicant
/// review/shortlist/assessment/offer UI belongs here — this phase covers
/// the student's own view only.
class StudentApplicationsScreen extends StatefulWidget {
  const StudentApplicationsScreen({super.key});

  @override
  State<StudentApplicationsScreen> createState() =>
      _StudentApplicationsScreenState();
}

class _StudentApplicationsScreenState extends State<StudentApplicationsScreen> {
  @override
  void initState() {
    super.initState();
    // Deferred to the post-frame callback — see
    // StudentOpportunitiesScreen.initState for why calling this directly
    // here would violate Flutter's build-phase constraints.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<StudentApplicationsProvider>().loadApplications();
    });
  }

  void _openDetails(int id) {
    context.push(AppRoutes.studentApplicationDetails(id));
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<StudentApplicationsProvider>();

    return Scaffold(
      appBar: AppBar(title: const Text('My Applications')),
      body: SafeArea(child: _buildBody(provider)),
    );
  }

  Widget _buildBody(StudentApplicationsProvider provider) {
    if (provider.isLoadingList && provider.applications.isEmpty) {
      return const AppSkeletonList();
    }

    if (provider.listErrorMessage != null && provider.applications.isEmpty) {
      return AppErrorView(
        message: provider.listErrorMessage!,
        onRetry: provider.refresh,
      );
    }

    if (provider.applications.isEmpty) {
      return const AppEmptyView(
        title: 'No Applications Yet',
        message: 'Applications you submit will appear here.',
        icon: Icons.assignment_outlined,
      );
    }

    return RefreshIndicator(
      onRefresh: provider.refresh,
      child: ListView.separated(
        padding: const EdgeInsets.all(AppSpacing.screenHorizontal),
        itemCount: provider.applications.length,
        separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
        itemBuilder: (context, index) {
          final application = provider.applications[index];
          return _ApplicationCard(
            application: application,
            onTap: () => _openDetails(application.id),
          );
        },
      ),
    );
  }
}

class _ApplicationCard extends StatelessWidget {
  const _ApplicationCard({required this.application, required this.onTap});

  final ApplicationModel application;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final organizationName =
        application.opportunity?.organizationProfile?.organizationName;

    return AppCard(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  application.opportunity?.title ?? 'Opportunity',
                  style: textTheme.titleMedium,
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              StatusChip(
                label:
                    applicationStatusLabels[application.status] ??
                    application.status,
                type: applicationStatusChipType(application.status),
                compact: true,
              ),
            ],
          ),
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
          Text(
            'CV: ${application.cv.title}',
            style: textTheme.bodySmall?.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          if (application.appliedAt != null) ...[
            const SizedBox(height: AppSpacing.xxs),
            Text(
              'Applied ${formatDate(application.appliedAt!)}',
              style: textTheme.bodySmall?.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
