import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/major_eligibility.dart';
import '../../../core/widgets/app_widgets.dart';
import '../../../models/candidate_model.dart';
import '../../../models/opportunity_model.dart';
import '../../../providers/candidate_search_provider.dart';
import '../../../providers/organization_opportunities_provider.dart';

/// A modal bottom sheet to invite [candidate] to apply — the Organization
/// picks one of its own open Opportunities, optionally adds a message, and
/// sends. Mirrors `ApplyBottomSheet`'s own shape (pick-one-then-submit,
/// same loading/error handling) for the Student side of the exact same
/// underlying `Invitation`.
class InviteBottomSheet extends StatefulWidget {
  const InviteBottomSheet({super.key, required this.candidate});

  final CandidateModel candidate;

  @override
  State<InviteBottomSheet> createState() => _InviteBottomSheetState();
}

class _InviteBottomSheetState extends State<InviteBottomSheet> {
  final _messageController = TextEditingController();
  int? _selectedOpportunityId;
  bool _hasSubmitted = false;

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _submit(CandidateSearchProvider provider) async {
    final opportunityId = _selectedOpportunityId;
    if (opportunityId == null) return;

    _hasSubmitted = true;
    FocusScope.of(context).unfocus();

    final message = _messageController.text.trim();
    await provider.sendInvitation(
      studentId: widget.candidate.id,
      opportunityId: opportunityId,
      message: message.isEmpty ? null : message,
    );
    if (!mounted) return;
    if (provider.inviteErrorMessage != null) return;

    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final opportunitiesProvider = context.watch<OrganizationOpportunitiesProvider>();
    final candidateProvider = context.watch<CandidateSearchProvider>();
    final isLoading = candidateProvider.isSendingInvite;
    final openOpportunities = opportunitiesProvider.opportunities
        .where((o) => o.status == 'open')
        .toList();

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
            const SizedBox(height: AppSpacing.sm),
            if (opportunitiesProvider.isLoadingList &&
                openOpportunities.isEmpty)
              const AppLoading(compact: true)
            else if (openOpportunities.isEmpty)
              const AppEmptyView(
                compact: true,
                icon: Icons.work_outline_rounded,
                title: 'No Open Opportunities',
                message: 'Publish an open opportunity before inviting candidates.',
              )
            else ...[
              Text('Opportunity', style: Theme.of(context).textTheme.titleSmall),
              RadioGroup<int>(
                groupValue: _selectedOpportunityId,
                onChanged: isLoading
                    ? (_) {}
                    : (value) => setState(() => _selectedOpportunityId = value),
                child: Column(
                  children: [
                    for (final OpportunityModel opportunity in openOpportunities)
                      Builder(
                        builder: (context) {
                          final eligible = isCandidateEligibleForOpportunity(
                            widget.candidate,
                            opportunity,
                          );
                          return RadioListTile<int>(
                            contentPadding: EdgeInsets.zero,
                            value: opportunity.id,
                            enabled: !isLoading && eligible,
                            title: Text(opportunity.title),
                            subtitle: eligible
                                ? null
                                : Text(
                                    'Not eligible for ${widget.candidate.name}\'s major',
                                    style: Theme.of(context).textTheme.bodySmall
                                        ?.copyWith(color: AppColors.error),
                                  ),
                          );
                        },
                      ),
                  ],
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
              if (_hasSubmitted &&
                  candidateProvider.inviteErrorMessage != null) ...[
                const SizedBox(height: AppSpacing.xs),
                AppErrorView(
                  title: 'Something Went Wrong',
                  message: candidateProvider.inviteErrorMessage!,
                  compact: true,
                ),
              ],
              const SizedBox(height: AppSpacing.lg),
              PrimaryButton(
                label: 'Send Invitation',
                isLoading: isLoading,
                onPressed: _selectedOpportunityId == null
                    ? null
                    : () => _submit(candidateProvider),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Shows [InviteBottomSheet] with the ancestor providers it needs, and
/// returns `true` only when the invitation was successfully sent.
Future<bool> showInviteBottomSheet(
  BuildContext context, {
  required CandidateModel candidate,
}) async {
  final candidateProvider = context.read<CandidateSearchProvider>();
  final opportunitiesProvider = context.read<OrganizationOpportunitiesProvider>();
  opportunitiesProvider.loadOpportunities();

  final result = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    builder: (_) => MultiProvider(
      providers: [
        ChangeNotifierProvider<CandidateSearchProvider>.value(
          value: candidateProvider,
        ),
        ChangeNotifierProvider<OrganizationOpportunitiesProvider>.value(
          value: opportunitiesProvider,
        ),
      ],
      child: InviteBottomSheet(candidate: candidate),
    ),
  );
  return result ?? false;
}
