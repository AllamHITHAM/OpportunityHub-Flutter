import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/date_formatter.dart';
import '../../../core/widgets/app_widgets.dart';
import '../../../models/opportunity_model.dart';
import '../../../providers/organization_opportunities_provider.dart';
import '../../../routes/app_routes.dart';
import 'opportunity_display.dart';

/// Lists the authenticated organization's own opportunities.
class OrganizationOpportunitiesScreen extends StatefulWidget {
  const OrganizationOpportunitiesScreen({super.key});

  @override
  State<OrganizationOpportunitiesScreen> createState() =>
      _OrganizationOpportunitiesScreenState();
}

class _OrganizationOpportunitiesScreenState
    extends State<OrganizationOpportunitiesScreen> {
  @override
  void initState() {
    super.initState();
    // Loaded once here, not in build — loadOpportunities() itself also
    // guards against concurrent duplicate calls, but this avoids even
    // attempting one on every rebuild. Deferred to the post-frame callback
    // because the provider's first action is a synchronous
    // notifyListeners() (setting isLoadingList), and calling that directly
    // from initState would try to rebuild this screen's own ancestor
    // Provider while the widget tree is still being built for the first
    // time — a real Flutter constraint violation, not just a test quirk.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<OrganizationOpportunitiesProvider>().loadOpportunities();
    });
  }

  void _openCreate() {
    context.push(AppRoutes.organizationOpportunityCreate);
  }

  void _openDetails(int id) {
    context.push(AppRoutes.organizationOpportunityDetails(id));
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<OrganizationOpportunitiesProvider>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Opportunities'),
        actions: [
          IconButton(
            onPressed: _openCreate,
            icon: const Icon(Icons.add),
            tooltip: 'Create Opportunity',
          ),
        ],
      ),
      body: SafeArea(child: _buildBody(provider)),
    );
  }

  Widget _buildBody(OrganizationOpportunitiesProvider provider) {
    if (provider.isLoadingList && provider.opportunities.isEmpty) {
      return const AppSkeletonList();
    }

    if (provider.listErrorMessage != null && provider.opportunities.isEmpty) {
      return AppErrorView(
        message: provider.listErrorMessage!,
        onRetry: provider.loadOpportunities,
      );
    }

    if (provider.opportunities.isEmpty) {
      return AppEmptyView(
        title: 'No Opportunities Yet',
        message:
            'Create your first opportunity to start receiving applications.',
        icon: Icons.work_outline_rounded,
        actionLabel: 'Create Opportunity',
        onAction: _openCreate,
      );
    }

    return RefreshIndicator(
      onRefresh: provider.loadOpportunities,
      child: ListView.separated(
        padding: const EdgeInsets.all(AppSpacing.screenHorizontal),
        itemCount: provider.opportunities.length,
        separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
        itemBuilder: (context, index) {
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

    return AppCard(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(opportunity.title, style: textTheme.titleMedium),
              ),
              const SizedBox(width: AppSpacing.xs),
              StatusChip(
                label: statusLabels[opportunity.status] ?? opportunity.status,
                type: statusChipType(opportunity.status),
              ),
            ],
          ),
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
              if (opportunity.location != null)
                StatusChip(
                  label: opportunity.location!,
                  icon: Icons.place_outlined,
                  compact: true,
                ),
            ],
          ),
          if (opportunity.applicationDeadline != null) ...[
            const SizedBox(height: AppSpacing.xxs),
            Text(
              'Deadline: ${formatDate(opportunity.applicationDeadline!)}',
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
