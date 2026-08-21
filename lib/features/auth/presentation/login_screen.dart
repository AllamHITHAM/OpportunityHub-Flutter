import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/app_error_view.dart';
import '../../../core/widgets/app_password_field.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../core/widgets/primary_button.dart';
import '../../../providers/auth_provider.dart';
import '../../../routes/app_routes.dart';

/// The sign-in screen. The router sends the user to their role's home
/// screen automatically once login succeeds — this screen never navigates
/// on its own.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  String? _validateEmail(String? value) {
    final email = value?.trim() ?? '';
    if (email.isEmpty) return 'Email is required';
    final isValidEmail = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email);
    if (!isValidEmail) return 'Enter a valid email address';
    return null;
  }

  String? _validatePassword(String? value) {
    final password = value ?? '';
    if (password.isEmpty) return 'Password is required';
    if (password.length < 6) return 'Password must be at least 6 characters';
    return null;
  }

  void _submit(AuthProvider authProvider) {
    // Dismiss the keyboard as soon as a login attempt starts.
    FocusScope.of(context).unfocus();

    final isValid = _formKey.currentState?.validate() ?? false;
    if (!isValid) return;

    authProvider.login(_emailController.text.trim(), _passwordController.text);
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = context.watch<AuthProvider>();
    final textTheme = Theme.of(context).textTheme;
    final isLoading = authProvider.isLoading;

    return Scaffold(
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
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const SizedBox(height: AppSpacing.xl),
                          const _LogoPlaceholder(),
                          const SizedBox(height: AppSpacing.lg),
                          Text(
                            'Welcome Back',
                            textAlign: TextAlign.center,
                            style: textTheme.displaySmall,
                          ),
                          const SizedBox(height: AppSpacing.xs),
                          Text(
                            'Sign in to continue using OpportunityHub.',
                            textAlign: TextAlign.center,
                            style: textTheme.bodyMedium?.copyWith(
                              color: AppColors.textSecondary,
                            ),
                          ),
                          const SizedBox(height: AppSpacing.xl),
                          Card(
                            child: Padding(
                              padding: const EdgeInsets.all(
                                AppSpacing.cardPadding,
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  AppTextField(
                                    controller: _emailController,
                                    label: 'Email',
                                    hint: 'you@example.com',
                                    prefixIcon: Icons.mail_outline,
                                    keyboardType: TextInputType.emailAddress,
                                    textInputAction: TextInputAction.next,
                                    autofillHints: const [AutofillHints.email],
                                    enabled: !isLoading,
                                    validator: _validateEmail,
                                  ),
                                  const SizedBox(
                                    height: AppSpacing.inputSpacing,
                                  ),
                                  AppPasswordField(
                                    controller: _passwordController,
                                    label: 'Password',
                                    textInputAction: TextInputAction.done,
                                    autofillHints: const [
                                      AutofillHints.password,
                                    ],
                                    enabled: !isLoading,
                                    validator: _validatePassword,
                                    onFieldSubmitted: (_) =>
                                        _submit(authProvider),
                                  ),
                                  const SizedBox(height: AppSpacing.xxs),
                                  Align(
                                    alignment: Alignment.centerRight,
                                    child: TextButton(
                                      onPressed: () => context.push(
                                        AppRoutes.forgotPassword,
                                      ),
                                      child: const Text('Forgot Password?'),
                                    ),
                                  ),
                                  if (authProvider.errorMessage != null) ...[
                                    const SizedBox(height: AppSpacing.xs),
                                    AppErrorView(
                                      title: 'Login Failed',
                                      message: authProvider.errorMessage!,
                                      compact: true,
                                    ),
                                  ],
                                  const SizedBox(height: AppSpacing.sm),
                                  PrimaryButton(
                                    label: 'Login',
                                    isLoading: isLoading,
                                    onPressed: () => _submit(authProvider),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: AppSpacing.lg),
                          Row(
                            children: [
                              const Expanded(child: Divider()),
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: AppSpacing.sm,
                                ),
                                child: Text('OR', style: textTheme.labelMedium),
                              ),
                              const Expanded(child: Divider()),
                            ],
                          ),
                          const SizedBox(height: AppSpacing.lg),
                          Wrap(
                            alignment: WrapAlignment.center,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Text(
                                "Don't have an account?",
                                style: textTheme.bodyMedium,
                              ),
                              TextButton(
                                onPressed: () => context.push(
                                  AppRoutes.accountTypeSelection,
                                ),
                                child: const Text('Create Account'),
                              ),
                            ],
                          ),
                          const SizedBox(height: AppSpacing.xl),
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

class _LogoPlaceholder extends StatelessWidget {
  const _LogoPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 72,
        height: 72,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: AppColors.primaryContainer,
          borderRadius: AppRadius.largeRadius,
        ),
        child: const Icon(
          Icons.work_outline_rounded,
          size: 36,
          color: AppColors.primaryDark,
        ),
      ),
    );
  }
}
