import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/date_formatter.dart';
import '../../../core/widgets/app_widgets.dart';
import '../../../models/admin_education_verification_model.dart';
import '../../../providers/admin_education_verifications_provider.dart';

/// Admin review of Student education-verification submissions (Phase
/// 8B-1). "Verified" means an Admin reviewed the uploaded document and
/// approved it -- see docs/BUSINESS_RULES.md. Kept minimal, mirroring
/// `AdminSkillsScreen`'s pending-suggestions section: list, per-row busy
/// state, Verify/Reject (Reject requires a reason first).
class AdminEducationVerificationsScreen extends StatefulWidget {
  const AdminEducationVerificationsScreen({super.key});

  @override
  State<AdminEducationVerificationsScreen> createState() =>
      _AdminEducationVerificationsScreenState();
}

class _AdminEducationVerificationsScreenState
    extends State<AdminEducationVerificationsScreen> {
  @override
  void initState() {
    super.initState();
    // Deferred to the post-frame callback — see
    // StudentOpportunitiesScreen.initState for why calling this directly
    // here would violate Flutter's build-phase constraints.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<AdminEducationVerificationsProvider>().load();
    });
  }

  Future<void> _viewDocument(
    AdminEducationVerificationModel verification,
  ) async {
    final provider = context.read<AdminEducationVerificationsProvider>();

    final bytes = await provider.downloadDocument(verification.id);
    if (!mounted) return;

    if (bytes != null) {
      final kb = (bytes.length / 1024).toStringAsFixed(0);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Document downloaded ($kb KB)')));
    } else if (provider.downloadErrorMessage != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(provider.downloadErrorMessage!)));
    }
  }

  Future<void> _verify(AdminEducationVerificationModel verification) async {
    final provider = context.read<AdminEducationVerificationsProvider>();
    final success = await provider.verify(verification.id);
    if (!mounted) return;

    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Education verification approved')),
      );
    } else if (provider.actionErrorMessage != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(provider.actionErrorMessage!)));
    }
  }

  Future<void> _reject(AdminEducationVerificationModel verification) async {
    final reason = await showDialog<String>(
      context: context,
      builder: (_) => const _RejectReasonDialog(),
    );
    if (reason == null || !mounted) return;

    final provider = context.read<AdminEducationVerificationsProvider>();
    final success = await provider.reject(verification.id, reason: reason);
    if (!mounted) return;

    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Education verification rejected')),
      );
    } else if (provider.actionErrorMessage != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(provider.actionErrorMessage!)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AdminEducationVerificationsProvider>();

    return Scaffold(
      appBar: AppBar(title: const Text('Education Verifications')),
      body: SafeArea(child: _buildBody(provider)),
    );
  }

  Widget _buildBody(AdminEducationVerificationsProvider provider) {
    if (provider.isLoading && provider.verifications.isEmpty) {
      return const AppSkeletonList();
    }

    if (provider.errorMessage != null && provider.verifications.isEmpty) {
      return AppErrorView(
        message: provider.errorMessage!,
        onRetry: () => provider.load(forceRefresh: true),
      );
    }

    if (provider.verifications.isEmpty) {
      return const AppEmptyView(
        title: 'No Submissions Yet',
        message: 'No students have submitted education verification yet.',
        icon: Icons.school_outlined,
      );
    }

    return RefreshIndicator(
      onRefresh: () => provider.load(forceRefresh: true),
      child: ListView.separated(
        padding: const EdgeInsets.all(AppSpacing.screenHorizontal),
        itemCount: provider.verifications.length,
        separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
        itemBuilder: (context, index) {
          final verification = provider.verifications[index];
          return _VerificationCard(
            verification: verification,
            isBusy: provider.isBusy(verification.id),
            onViewDocument: () => _viewDocument(verification),
            onVerify: () => _verify(verification),
            onReject: () => _reject(verification),
          );
        },
      ),
    );
  }
}

class _VerificationCard extends StatelessWidget {
  const _VerificationCard({
    required this.verification,
    required this.isBusy,
    required this.onViewDocument,
    required this.onVerify,
    required this.onReject,
  });

  final AdminEducationVerificationModel verification;
  final bool isBusy;
  final VoidCallback onViewDocument;
  final VoidCallback onVerify;
  final VoidCallback onReject;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      verification.studentName ?? 'Unnamed student',
                      style: textTheme.titleMedium,
                    ),
                    if (verification.studentEmail != null)
                      Text(
                        verification.studentEmail!,
                        style: textTheme.bodySmall,
                      ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              StatusChip(
                label: _statusLabel(verification.status),
                type: _statusType(verification.status),
                compact: true,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(verification.institutionName, style: textTheme.bodyMedium),
          Text(
            verification.degreeOrProgram,
            style: textTheme.bodySmall?.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          if (verification.submittedAt != null) ...[
            const SizedBox(height: AppSpacing.xxs),
            Text(
              'Submitted ${formatDate(verification.submittedAt!)}',
              style: textTheme.bodySmall?.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.sm),
          if (isBusy)
            const AppLoading(compact: true)
          else
            Row(
              children: [
                Expanded(
                  child: SecondaryButton(
                    label: 'View Document',
                    onPressed: onViewDocument,
                  ),
                ),
                if (verification.isPending) ...[
                  const SizedBox(width: AppSpacing.sm),
                  IconButton(
                    key: Key(
                      'verify-education-verification-${verification.id}',
                    ),
                    onPressed: onVerify,
                    icon: const Icon(Icons.check_circle_outline),
                    color: AppColors.success,
                    tooltip: 'Verify',
                  ),
                  IconButton(
                    key: Key(
                      'reject-education-verification-${verification.id}',
                    ),
                    onPressed: onReject,
                    icon: const Icon(Icons.cancel_outlined),
                    color: AppColors.error,
                    tooltip: 'Reject',
                  ),
                ],
              ],
            ),
        ],
      ),
    );
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'verified':
        return 'Verified';
      case 'rejected':
        return 'Rejected';
      default:
        return 'Pending';
    }
  }

  AppStatusType _statusType(String status) {
    switch (status) {
      case 'verified':
        return AppStatusType.success;
      case 'rejected':
        return AppStatusType.error;
      default:
        return AppStatusType.warning;
    }
  }
}

/// A small dialog collecting a required rejection reason. Returns the
/// trimmed reason on confirm, or `null` on cancel/dismiss -- the caller
/// never calls the reject action with an empty reason.
class _RejectReasonDialog extends StatefulWidget {
  const _RejectReasonDialog();

  @override
  State<_RejectReasonDialog> createState() => _RejectReasonDialogState();
}

class _RejectReasonDialogState extends State<_RejectReasonDialog> {
  final _controller = TextEditingController();
  String? _errorText;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _confirm() {
    final reason = _controller.text.trim();
    if (reason.isEmpty) {
      setState(() => _errorText = 'A rejection reason is required');
      return;
    }
    Navigator.of(context).pop(reason);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Reject Submission'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        maxLines: 3,
        decoration: InputDecoration(
          hintText: 'Reason for rejection',
          errorText: _errorText,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        DangerButton(label: 'Reject', onPressed: _confirm),
      ],
    );
  }
}
