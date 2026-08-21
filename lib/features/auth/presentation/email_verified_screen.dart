import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/primary_button.dart';
import '../../../routes/app_routes.dart';

/// The landing spot the backend's signed email-verification link
/// redirects to after verifying (or rejecting) it server-side (Phase
/// 8B-2) — see `EmailVerificationController::verify()`. No signed-link
/// data (id/hash/signature) is ever handled here; by the time this
/// screen renders, the backend has already fully decided the outcome,
/// carried only as a `status` query parameter (`success`/`invalid`). A
/// missing/unrecognized status is treated the same as `invalid`, never a
/// crash.
class EmailVerifiedScreen extends StatelessWidget {
  const EmailVerifiedScreen({super.key, this.status});

  final String? status;

  @override
  Widget build(BuildContext context) {
    final isSuccess = status == 'success';
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Email Verification')),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.screenHorizontal,
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    isSuccess
                        ? Icons.check_circle_outline_rounded
                        : Icons.error_outline_rounded,
                    size: 56,
                    color: isSuccess ? AppColors.success : AppColors.error,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    isSuccess ? 'Email Verified' : 'Verification Failed',
                    textAlign: TextAlign.center,
                    style: textTheme.headlineSmall,
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    isSuccess
                        ? 'Your email address has been verified successfully.'
                        : 'This verification link is invalid or has expired. '
                              'You can request a new one from your account.',
                    textAlign: TextAlign.center,
                    style: textTheme.bodyMedium?.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  PrimaryButton(
                    label: 'Go to Login',
                    onPressed: () => context.go(AppRoutes.login),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
