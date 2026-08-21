import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/app_widgets.dart';
import '../../../models/invitation_model.dart';
import '../../../providers/student_invitations_provider.dart';
import '../../../routes/app_routes.dart';

/// Lists the student's received invitations (Phase 8B-3, Flow B) with
/// Accept/Decline actions. Accepting never creates an Application by
/// itself — it routes to the existing Opportunity details/Apply flow,
/// where the student picks a CV exactly as a direct (Flow A) applicant
/// would.
class StudentInvitationsScreen extends StatefulWidget {
  const StudentInvitationsScreen({super.key});

  @override
  State<StudentInvitationsScreen> createState() =>
      _StudentInvitationsScreenState();
}

class _StudentInvitationsScreenState extends State<StudentInvitationsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<StudentInvitationsProvider>().loadInvitations();
    });
  }

  Future<void> _accept(InvitationModel invitation) async {
    final provider = context.read<StudentInvitationsProvider>();
    await provider.accept(invitation.id);
    if (!mounted) return;
    if (provider.respondErrorMessage != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(provider.respondErrorMessage!)),
      );
      return;
    }
    context.push(AppRoutes.studentOpportunityDetails(invitation.opportunityId));
  }

  Future<void> _decline(InvitationModel invitation) async {
    final provider = context.read<StudentInvitationsProvider>();
    await provider.decline(invitation.id);
    if (!mounted) return;
    if (provider.respondErrorMessage != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(provider.respondErrorMessage!)),
      );
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Invitation declined')));
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<StudentInvitationsProvider>();

    return Scaffold(
      appBar: AppBar(title: const Text('Invitations')),
      body: SafeArea(child: _buildBody(provider)),
    );
  }

  Widget _buildBody(StudentInvitationsProvider provider) {
    if (provider.isLoading && provider.invitations.isEmpty) {
      return const AppSkeletonList();
    }

    if (provider.listErrorMessage != null && provider.invitations.isEmpty) {
      return AppErrorView(
        message: provider.listErrorMessage!,
        onRetry: provider.loadInvitations,
      );
    }

    if (provider.invitations.isEmpty) {
      return const AppEmptyView(
        title: 'No Invitations Yet',
        message: 'Organizations that invite you to apply will appear here.',
        icon: Icons.mail_outline_rounded,
      );
    }

    return RefreshIndicator(
      onRefresh: provider.loadInvitations,
      child: ListView.separated(
        padding: const EdgeInsets.all(AppSpacing.screenHorizontal),
        itemCount: provider.invitations.length,
        separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
        itemBuilder: (context, index) {
          final invitation = provider.invitations[index];
          return _InvitationCard(
            invitation: invitation,
            isResponding: provider.isRespondingTo(invitation.id),
            onAccept: () => _accept(invitation),
            onDecline: () => _decline(invitation),
          );
        },
      ),
    );
  }
}

class _InvitationCard extends StatelessWidget {
  const _InvitationCard({
    required this.invitation,
    required this.isResponding,
    required this.onAccept,
    required this.onDecline,
  });

  final InvitationModel invitation;
  final bool isResponding;
  final VoidCallback onAccept;
  final VoidCallback onDecline;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  invitation.opportunityTitle,
                  style: textTheme.titleMedium,
                ),
              ),
              StatusChip(
                label: _statusLabel(invitation.status),
                type: _statusChipType(invitation.status),
                compact: true,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            invitation.organizationName,
            style: textTheme.bodyMedium?.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          if (invitation.message != null && invitation.message!.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(invitation.message!, style: textTheme.bodyMedium),
          ],
          if (invitation.isPending) ...[
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                Expanded(
                  child: SecondaryButton(
                    label: 'Decline',
                    onPressed: isResponding ? null : onDecline,
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: PrimaryButton(
                    label: 'Accept',
                    isLoading: isResponding,
                    onPressed: isResponding ? null : onAccept,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'accepted':
        return 'Accepted';
      case 'declined':
        return 'Declined';
      case 'pending':
      default:
        return 'Pending';
    }
  }

  AppStatusType _statusChipType(String status) {
    switch (status) {
      case 'accepted':
        return AppStatusType.success;
      case 'declined':
        return AppStatusType.neutral;
      case 'pending':
      default:
        return AppStatusType.warning;
    }
  }
}
