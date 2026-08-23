import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/app_animated_status_icon.dart';
import '../../../core/widgets/auth_animated_background.dart';
import '../../../core/widgets/auth_entrance.dart';
import '../../../core/widgets/primary_button.dart';
import '../../../core/widgets/theme_toggle_button.dart';
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
      appBar: AppBar(
        title: const Text('Email Verification'),
        actions: const [ThemeToggleButton()],
      ),
      body: Stack(
        children: [
          const Positioned.fill(child: AuthAnimatedBackground()),
          SafeArea(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.screenHorizontal,
                ),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 480),
                  child: AuthEntrance(
                    children: [
                      AppAnimatedStatusIcon(
                        icon: isSuccess
                            ? Icons.check_circle_outline_rounded
                            : Icons.error_outline_rounded,
                        color: isSuccess ? AppColors.success : AppColors.error,
                        backgroundColor: isSuccess
                            ? AppColors.successBackground
                            : AppColors.errorBackground,
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
        ],
      ),
    );
  }
}
