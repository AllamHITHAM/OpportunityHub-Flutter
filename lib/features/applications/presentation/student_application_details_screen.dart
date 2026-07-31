import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/date_formatter.dart';
import '../../../core/widgets/app_widgets.dart';
import '../../../models/application_model.dart';
import '../../../providers/student_applications_provider.dart';
import '../../opportunities/presentation/opportunity_display.dart';
import 'application_display.dart';

/// Read-only application details for students. Reached by ID alone (a
/// route parameter, never GoRouter `extra`) — since no single-application
/// GET endpoint exists on the backend, a cached copy from the already-
/// loaded list is used when available, otherwise the full list is loaded
/// once and this ID is resolved from it. No applicant-review/shortlist/
/// assessment/offer UI belongs here.
class StudentApplicationDetailsScreen extends StatefulWidget {
  const StudentApplicationDetailsScreen({
    super.key,
    required this.applicationId,
  });

  final int applicationId;

  @override
  State<StudentApplicationDetailsScreen> createState() =>
      _StudentApplicationDetailsScreenState();
}

class _StudentApplicationDetailsScreenState
    extends State<StudentApplicationDetailsScreen> {
  @override
  void initState() {
    super.initState();
    // Deferred to the post-frame callback — see
    // StudentOpportunitiesScreen.initState for why calling this directly
    // here would violate Flutter's build-phase constraints.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<StudentApplicationsProvider>().loadApplicationDetails(
        widget.applicationId,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<StudentApplicationsProvider>();
    final application = provider.selectedApplication;
    final isThisOne = application?.id == widget.applicationId;

    return Scaffold(
      appBar: AppBar(title: const Text('Application Details')),
      body: SafeArea(child: _buildBody(provider, application, isThisOne)),
    );
  }

  Widget _buildBody(
    StudentApplicationsProvider provider,
    ApplicationModel? application,
    bool isThisOne,
  ) {
    if (provider.isLoadingDetails && !isThisOne) {
      return const AppLoading();
    }

    if (provider.detailsErrorMessage != null && !isThisOne) {
      return AppErrorView(
        message: provider.detailsErrorMessage!,
        onRetry: () => provider.loadApplicationDetails(
          widget.applicationId,
          forceRefresh: true,
        ),
      );
    }

    if (application == null || !isThisOne) {
      return const AppLoading();
    }

    final textTheme = Theme.of(context).textTheme;
    final organization = application.opportunity?.organizationProfile;
    final coverLetter = application.coverLetter;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.screenHorizontal),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  application.opportunity?.title ?? 'Opportunity',
                  style: textTheme.headlineSmall,
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              StatusChip(
                label:
                    applicationStatusLabels[application.status] ??
                    application.status,
                type: applicationStatusChipType(application.status),
              ),
            ],
          ),
          if (organization != null) ...[
            const SizedBox(height: AppSpacing.xxs),
            Text(
              organization.organizationName,
              style: textTheme.titleSmall?.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.lg),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SectionHeader(title: 'Details'),
                OpportunityDetailRow(label: 'CV', value: application.cv.title),
                OpportunityDetailRow(
                  label: 'Applied',
                  value: application.appliedAt != null
                      ? formatDate(application.appliedAt!)
                      : 'Not specified',
                ),
              ],
            ),
          ),
          if (coverLetter != null && coverLetter.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SectionHeader(title: 'Cover Letter'),
                  Text(coverLetter, style: textTheme.bodyMedium),
                ],
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.xl),
        ],
      ),
    );
  }
}
