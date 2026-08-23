import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_motion.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/app_animated_status_icon.dart';
import '../../../core/widgets/app_error_view.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../core/widgets/auth_animated_background.dart';
import '../../../core/widgets/auth_entrance.dart';
import '../../../core/widgets/primary_button.dart';
import '../../../core/widgets/theme_toggle_button.dart';
import '../../../providers/auth_provider.dart';
import '../../../routes/app_routes.dart';

/// Requests a password-reset email (Phase 8B-2). Reached from the
/// "Forgot Password?" action on [LoginScreen]. Always shows the same
/// safe success message on submit, regardless of whether the entered
/// email actually belongs to an account — never reveals that
/// distinction, matching the backend's own privacy behavior.
class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  String? _validateEmail(String? value) {
    final email = value?.trim() ?? '';
    if (email.isEmpty) return 'Email is required';
    final isValidEmail = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email);
    if (!isValidEmail) return 'Enter a valid email address';
    return null;
  }

  void _submit(AuthProvider authProvider) {
    FocusScope.of(context).unfocus();

    final isValid = _formKey.currentState?.validate() ?? false;
    if (!isValid) return;

    authProvider.forgotPassword(_emailController.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = context.watch<AuthProvider>();
    final textTheme = Theme.of(context).textTheme;
    final isLoading = authProvider.isSendingResetLink;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Forgot Password'),
        actions: const [ThemeToggleButton()],
      ),
      body: Stack(
        children: [
          const Positioned.fill(child: AuthAnimatedBackground()),
          SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                return SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.screenHorizontal,
                    vertical: AppSpacing.screenVertical,
                  ),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: constraints.maxHeight,
                    ),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 480),
                        child: AnimatedSwitcher(
                          duration: AppMotion.reduced(
                            context,
                            AppMotion.normal,
                          ),
                          transitionBuilder: (child, animation) =>
                              FadeTransition(
                                opacity: animation,
                                child: ScaleTransition(
                                  scale: Tween<double>(
                                    begin: 0.97,
                                    end: 1.0,
                                  ).animate(animation),
                                  child: child,
                                ),
                              ),
                          child: authProvider.forgotPasswordSucceeded
                              ? const _SuccessMessage(key: ValueKey('success'))
                              : Form(
                                  key: _formKey,
                                  child: AuthEntrance(
                                    key: const ValueKey('form'),
                                    children: [
                                      Text(
                                        'Reset Your Password',
                                        textAlign: TextAlign.center,
                                        style: textTheme.headlineSmall,
                                      ),
                                      const SizedBox(height: AppSpacing.xs),
                                      Text(
                                        'Enter your account email and we\'ll send you '
                                        'a link to reset your password.',
                                        textAlign: TextAlign.center,
                                        style: textTheme.bodyMedium?.copyWith(
                                          color: AppColors.textSecondary,
                                        ),
                                      ),
                                      const SizedBox(height: AppSpacing.lg),
                                      AppTextField(
                                        controller: _emailController,
                                        label: 'Email',
                                        hint: 'you@example.com',
                                        prefixIcon: Icons.mail_outline,
                                        keyboardType:
                                            TextInputType.emailAddress,
                                        textInputAction: TextInputAction.done,
                                        autofillHints: const [
                                          AutofillHints.email,
                                        ],
                                        enabled: !isLoading,
                                        validator: _validateEmail,
                                        onFieldSubmitted: (_) =>
                                            _submit(authProvider),
                                      ),
                                      AnimatedSwitcher(
                                        duration: AppMotion.reduced(
                                          context,
                                          AppMotion.fast,
                                        ),
                                        child:
                                            authProvider
                                                    .forgotPasswordErrorMessage ==
                                                null
                                            ? const SizedBox(
                                                width: double.infinity,
                                              )
                                            : Padding(
                                                key: ValueKey(
                                                  authProvider
                                                      .forgotPasswordErrorMessage,
                                                ),
                                                padding: const EdgeInsets.only(
                                                  top: AppSpacing.xs,
                                                ),
                                                child: AppErrorView(
                                                  title: 'Something Went Wrong',
                                                  message: authProvider
                                                      .forgotPasswordErrorMessage!,
                                                  compact: true,
                                                ),
                                              ),
                                      ),
                                      const SizedBox(height: AppSpacing.lg),
                                      PrimaryButton(
                                        label: 'Send Reset Link',
                                        isLoading: isLoading,
                                        onPressed: () => _submit(authProvider),
                                      ),
                                    ],
                                  ),
                                ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _SuccessMessage extends StatelessWidget {
  const _SuccessMessage({super.key});

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AppAnimatedStatusIcon(
          icon: Icons.mark_email_read_outlined,
          color: AppColors.success,
          backgroundColor: AppColors.successBackground,
        ),
        const SizedBox(height: AppSpacing.md),
        Text(
          'Check Your Email',
          textAlign: TextAlign.center,
          style: textTheme.headlineSmall,
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          'If an account exists for this email, password reset '
          'instructions have been sent.',
          textAlign: TextAlign.center,
          style: textTheme.bodyMedium?.copyWith(color: AppColors.textSecondary),
        ),
        const SizedBox(height: AppSpacing.lg),
        PrimaryButton(
          label: 'Back to Login',
          onPressed: () => context.go(AppRoutes.login),
        ),
      ],
    );
  }
}
