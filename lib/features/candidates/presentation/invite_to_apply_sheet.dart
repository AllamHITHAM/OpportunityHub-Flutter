import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/app_widgets.dart';
import '../../../models/recommended_candidate_model.dart';
import '../../../providers/opportunity_recommendations_provider.dart';

/// A modal bottom sheet to invite [candidate] to apply — reached only from
/// Recommended Candidates (Phase O8.1), where the Opportunity is already
/// known from context. Deliberately no "choose an Opportunity" step: the
/// old directory-wide Invite flow's picker (`InviteBottomSheet`, removed
/// this phase along with its only caller) existed specifically because
/// that context did *not* know the Opportunity yet — here it always does,
/// so this sheet only ever needs an optional message and a confirm.
class InviteToApplySheet extends StatefulWidget {
  const InviteToApplySheet({
    super.key,
    required this.candidate,
    required this.opportunityId,
    required this.opportunityTitle,
  });

  final RecommendedCandidateModel candidate;
  final int opportunityId;
  final String opportunityTitle;

  @override
  State<InviteToApplySheet> createState() => _InviteToApplySheetState();
}

class _InviteToApplySheetState extends State<InviteToApplySheet> {
  final _messageController = TextEditingController();
  bool _hasSubmitted = false;

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _submit(OpportunityRecommendationsProvider provider) async {
    _hasSubmitted = true;
    FocusScope.of(context).unfocus();

    final message = _messageController.text.trim();
    final success = await provider.sendInvitation(
      studentId: widget.candidate.id,
      opportunityId: widget.opportunityId,
      message: message.isEmpty ? null : message,
    );
    if (!mounted || !success) return;

    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<OpportunityRecommendationsProvider>();
    final isLoading = provider.isSendingInvite;

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
            SectionHeader(title: 'Invite ${widget.candidate.name}'),
            const SizedBox(height: AppSpacing.xxs),
            Text(
              'to apply for ${widget.opportunityTitle}',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: AppSpacing.inputSpacing),
            AppTextField(
              controller: _messageController,
              label: 'Message (optional)',
              hint: 'Tell them why you think they would be a great fit',
              maxLines: 4,
              maxLength: 1000,
              enabled: !isLoading,
            ),
            if (_hasSubmitted && provider.inviteErrorMessage != null) ...[
              const SizedBox(height: AppSpacing.xs),
              AppErrorView(
                title: 'Something Went Wrong',
                message: provider.inviteErrorMessage!,
                compact: true,
              ),
            ],
            const SizedBox(height: AppSpacing.lg),
            PrimaryButton(
              label: 'Send Invitation',
              isLoading: isLoading,
              onPressed: isLoading ? null : () => _submit(provider),
            ),
          ],
        ),
      ),
    );
  }
}

/// Shows [InviteToApplySheet] with the ancestor provider it needs, and
/// returns `true` only when the invitation was successfully sent.
Future<bool> showInviteToApplySheet(
  BuildContext context, {
  required RecommendedCandidateModel candidate,
  required int opportunityId,
  required String opportunityTitle,
}) async {
  final provider = context.read<OpportunityRecommendationsProvider>();

  final result = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    builder: (_) =>
        ChangeNotifierProvider<OpportunityRecommendationsProvider>.value(
          value: provider,
          child: InviteToApplySheet(
            candidate: candidate,
            opportunityId: opportunityId,
            opportunityTitle: opportunityTitle,
          ),
        ),
  );
  return result ?? false;
}
