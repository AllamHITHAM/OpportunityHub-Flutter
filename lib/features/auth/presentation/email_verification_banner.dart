import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/app_card.dart';
import '../../../providers/auth_provider.dart';

/// A small, shared "Email not verified" banner with a resend action
/// (Phase 8B-2) — reused across Student/Organization/Admin Home screens
/// rather than a separate account-settings feature, per this phase's own
/// "do not build a large account-settings feature" scope. Renders nothing
/// at all when the current user is already verified (or unknown), so it
/// never adds empty chrome.
class EmailVerificationBanner extends StatelessWidget {
  const EmailVerificationBanner({super.key});

  Future<void> _resend(BuildContext context) async {
    final authProvider = context.read<AuthProvider>();
    await authProvider.resendVerificationEmail();
    if (!context.mounted) return;

    if (authProvider.resendVerificationSucceeded) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Verification email sent')));
    } else if (authProvider.resendVerificationErrorMessage != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(authProvider.resendVerificationErrorMessage!)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = context.watch<AuthProvider>();
    final user = authProvider.user;

    if (user == null || user.emailVerified) {
      return const SizedBox.shrink();
    }

    final textTheme = Theme.of(context).textTheme;
    final isResending = authProvider.isResendingVerification;

    return AppCard(
      child: Row(
        children: [
          const Icon(Icons.mail_outline_rounded, color: AppColors.warning),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text('Email not verified', style: textTheme.bodyMedium),
          ),
          const SizedBox(width: AppSpacing.sm),
          TextButton(
            onPressed: isResending ? null : () => _resend(context),
            child: isResending
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Resend'),
          ),
        ],
      ),
    );
  }
}
