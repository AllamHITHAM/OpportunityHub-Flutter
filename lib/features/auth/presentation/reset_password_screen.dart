import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/app_error_view.dart';
import '../../../core/widgets/app_password_field.dart';
import '../../../core/widgets/primary_button.dart';
import '../../../providers/auth_provider.dart';
import '../../../routes/app_routes.dart';

/// Completes a password reset (Phase 8B-2) — reads `token`/`email` from
/// the reset link's query parameters (`/reset-password?token=...&email=...`,
/// see `AppRouter`), which the backend's `ResetPassword::createUrlUsing()`
/// generates. A missing/malformed link shows a safe inline error instead
/// of crashing or silently failing.
class ResetPasswordScreen extends StatefulWidget {
  const ResetPasswordScreen({super.key, this.token, this.email});

  final String? token;
  final String? email;

  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  @override
  void dispose() {
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  String? _validatePassword(String? value) {
    final password = value ?? '';
    if (password.isEmpty) return 'Password is required';
    if (password.length < 8) return 'Password must be at least 8 characters';
    return null;
  }

  String? _validateConfirmPassword(String? value) {
    final confirmation = value ?? '';
    if (confirmation.isEmpty) return 'Please confirm your password';
    if (confirmation != _passwordController.text) {
      return 'Passwords do not match';
    }
    return null;
  }

  void _submit(AuthProvider authProvider) {
    FocusScope.of(context).unfocus();

    final isValid = _formKey.currentState?.validate() ?? false;
    if (!isValid) return;

    authProvider.resetPassword(
      email: widget.email!,
      token: widget.token!,
      password: _passwordController.text,
    );
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = context.watch<AuthProvider>();
    final textTheme = Theme.of(context).textTheme;
    final isLoading = authProvider.isResettingPassword;
    final token = widget.token;
    final email = widget.email;
    final hasValidLink =
        token != null && token.isNotEmpty && email != null && email.isNotEmpty;

    return Scaffold(
      appBar: AppBar(title: const Text('Reset Password')),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.screenHorizontal,
                vertical: AppSpacing.screenVertical,
              ),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 480),
                    child: !hasValidLink
                        ? const _InvalidLinkMessage()
                        : authProvider.resetPasswordSucceeded
                        ? const _SuccessMessage()
                        : Form(
                            key: _formKey,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  'Set a New Password',
                                  textAlign: TextAlign.center,
                                  style: textTheme.headlineSmall,
                                ),
                                const SizedBox(height: AppSpacing.xs),
                                Text(
                                  email,
                                  textAlign: TextAlign.center,
                                  style: textTheme.bodyMedium?.copyWith(
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                                const SizedBox(height: AppSpacing.lg),
                                AppPasswordField(
                                  controller: _passwordController,
                                  label: 'New Password',
                                  textInputAction: TextInputAction.next,
                                  enabled: !isLoading,
                                  validator: _validatePassword,
                                ),
                                const SizedBox(height: AppSpacing.inputSpacing),
                                AppPasswordField(
                                  controller: _confirmPasswordController,
                                  label: 'Confirm Password',
                                  textInputAction: TextInputAction.done,
                                  enabled: !isLoading,
                                  validator: _validateConfirmPassword,
                                  onFieldSubmitted: (_) =>
                                      _submit(authProvider),
                                ),
                                if (authProvider.resetPasswordErrorMessage !=
                                    null) ...[
                                  const SizedBox(height: AppSpacing.xs),
                                  AppErrorView(
                                    title: 'Something Went Wrong',
                                    message:
                                        authProvider.resetPasswordErrorMessage!,
                                    compact: true,
                                  ),
                                ],
                                const SizedBox(height: AppSpacing.lg),
                                PrimaryButton(
                                  label: 'Reset Password',
                                  isLoading: isLoading,
                                  onPressed: () => _submit(authProvider),
                                ),
                              ],
                            ),
                          ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _InvalidLinkMessage extends StatelessWidget {
  const _InvalidLinkMessage();

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(
          Icons.error_outline_rounded,
          size: 56,
          color: AppColors.error,
        ),
        const SizedBox(height: AppSpacing.md),
        Text(
          'Invalid Reset Link',
          textAlign: TextAlign.center,
          style: textTheme.headlineSmall,
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          'This password reset link is missing required information. '
          'Please request a new one.',
          textAlign: TextAlign.center,
          style: textTheme.bodyMedium?.copyWith(color: AppColors.textSecondary),
        ),
        const SizedBox(height: AppSpacing.lg),
        PrimaryButton(
          label: 'Request New Link',
          onPressed: () => context.go(AppRoutes.forgotPassword),
        ),
      ],
    );
  }
}

class _SuccessMessage extends StatelessWidget {
  const _SuccessMessage();

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(
          Icons.check_circle_outline_rounded,
          size: 56,
          color: AppColors.success,
        ),
        const SizedBox(height: AppSpacing.md),
        Text(
          'Password Reset',
          textAlign: TextAlign.center,
          style: textTheme.headlineSmall,
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          'Your password has been reset successfully. You can now log in '
          'with your new password.',
          textAlign: TextAlign.center,
          style: textTheme.bodyMedium?.copyWith(color: AppColors.textSecondary),
        ),
        const SizedBox(height: AppSpacing.lg),
        PrimaryButton(
          label: 'Go to Login',
          onPressed: () => context.go(AppRoutes.login),
        ),
      ],
    );
  }
}
