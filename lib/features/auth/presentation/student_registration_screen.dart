import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_motion.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/app_error_view.dart';
import '../../../core/widgets/app_password_field.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../core/widgets/auth_animated_background.dart';
import '../../../core/widgets/auth_entrance.dart';
import '../../../core/widgets/primary_button.dart';
import '../../../core/widgets/section_header.dart';
import '../../../core/widgets/theme_toggle_button.dart';
import '../../../providers/auth_provider.dart';
import '../../../routes/app_routes.dart';
import 'registration_step_progress.dart';

/// Step 1 of student registration: collects account information and
/// creates the account via `POST /register/student`.
///
/// On success the user is already authenticated (the token is saved by
/// `AuthRepository`, exactly like login) and this screen hands off to
/// Step 2, which depends only on that authenticated state — not on
/// anything collected here. The router itself keeps an already-signed-in
/// student from ever reaching this screen again, so there's no in-screen
/// guard against resubmission.
class StudentRegistrationScreen extends StatefulWidget {
  const StudentRegistrationScreen({super.key});

  @override
  State<StudentRegistrationScreen> createState() =>
      _StudentRegistrationScreenState();
}

class _StudentRegistrationScreenState extends State<StudentRegistrationScreen> {
  final _formKey = GlobalKey<FormState>();

  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  String? _validateFullName(String? value) {
    final name = value?.trim() ?? '';
    if (name.isEmpty) return 'Full name is required';
    if (name.length < 2) return 'Enter your full name';
    return null;
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

  Future<void> _continue(AuthProvider authProvider) async {
    // Dismiss the keyboard as soon as a submission attempt starts.
    FocusScope.of(context).unfocus();

    final isValid = _formKey.currentState?.validate() ?? false;
    if (!isValid) return;

    final fullName = _nameController.text.trim();
    final email = _emailController.text.trim();
    final password = _passwordController.text;

    final success = await authProvider.registerStudent(
      name: fullName,
      email: email,
      password: password,
    );

    if (!mounted) return;
    // On failure, errorMessage is already set and shown reactively below —
    // nothing else to do here but stay on this screen.
    if (!success) return;

    // `go`, not `push`. Registration is reached via a push chain rooted at
    // /login, and /login's own redirect verdict flips the instant this
    // screen authenticates the user — go_router then revalidates that
    // whole chain and collapses it to the home route. Using `go` here (and
    // for every hop in this flow, forward and back) makes each step a
    // fresh, independent location instead of another link in that chain,
    // which avoids the collapse entirely.
    //
    // Note: the router's own redirect logic reacts to this new
    // authenticated state before this line even runs (AuthProvider's own
    // notifyListeners() fires synchronously inside registerStudent()), so
    // it may have already navigated to Step 2 (or Home, if a profile
    // somehow already exists) by the time this call executes — in which
    // case it's a harmless no-op.
    context.go(AppRoutes.studentProfileRegistration);
  }

  void _goToLogin() {
    // A single, safe navigation that replaces the whole stack with one
    // clean login location.
    context.go(AppRoutes.login);
  }

  void _goToAccountTypeSelection() {
    context.go(AppRoutes.accountTypeSelection);
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = context.watch<AuthProvider>();
    final textTheme = Theme.of(context).textTheme;
    final isLoading = authProvider.isLoading;

    return Scaffold(
      // This screen is reached with `context.go` (see `_continue`), which
      // leaves nothing to pop — so the back arrow needs an explicit
      // target instead of relying on Navigator.canPop.
      appBar: AppBar(
        leading: BackButton(onPressed: _goToAccountTypeSelection),
        actions: const [ThemeToggleButton()],
      ),
      body: Stack(
        children: [
          const Positioned.fill(child: AuthAnimatedBackground()),
          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.screenHorizontal,
                vertical: AppSpacing.screenVertical,
              ),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 600),
                  child: Form(
                    key: _formKey,
                    child: AuthEntrance(
                      children: [
                        Text(
                          'Create Student Account',
                          textAlign: TextAlign.center,
                          style: textTheme.displaySmall,
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          'Enter your account information to get started.',
                          textAlign: TextAlign.center,
                          style: textTheme.bodyMedium?.copyWith(
                            color: AppColors.textSecondary,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.md),
                        const RegistrationStepProgress(
                          progress: 0.5,
                          stepText: 'Step 1 of 2',
                          label: 'Account Information',
                        ),
                        const SizedBox(height: AppSpacing.xl),
                        AppCard(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              const SectionHeader(title: 'Account Information'),
                              const SizedBox(height: AppSpacing.xs),
                              AppTextField(
                                controller: _nameController,
                                label: 'Full Name',
                                hint: 'Jane Doe',
                                prefixIcon: Icons.person_outline,
                                textInputAction: TextInputAction.next,
                                autofillHints: const [AutofillHints.name],
                                enabled: !isLoading,
                                validator: _validateFullName,
                              ),
                              const SizedBox(height: AppSpacing.inputSpacing),
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
                              const SizedBox(height: AppSpacing.inputSpacing),
                              AppPasswordField(
                                controller: _passwordController,
                                label: 'Password',
                                textInputAction: TextInputAction.next,
                                autofillHints: const [
                                  AutofillHints.newPassword,
                                ],
                                enabled: !isLoading,
                                validator: _validatePassword,
                              ),
                              const SizedBox(height: AppSpacing.inputSpacing),
                              AppPasswordField(
                                controller: _confirmPasswordController,
                                label: 'Confirm Password',
                                textInputAction: TextInputAction.done,
                                autofillHints: const [
                                  AutofillHints.newPassword,
                                ],
                                enabled: !isLoading,
                                validator: _validateConfirmPassword,
                                onFieldSubmitted: (_) =>
                                    _continue(authProvider),
                              ),
                              AnimatedSwitcher(
                                duration: AppMotion.reduced(
                                  context,
                                  AppMotion.fast,
                                ),
                                child: authProvider.errorMessage == null
                                    ? const SizedBox(width: double.infinity)
                                    : Padding(
                                        key: ValueKey(
                                          authProvider.errorMessage,
                                        ),
                                        padding: const EdgeInsets.only(
                                          top: AppSpacing.xs,
                                        ),
                                        child: AppErrorView(
                                          title: 'Registration Failed',
                                          message: authProvider.errorMessage!,
                                          compact: true,
                                        ),
                                      ),
                              ),
                              const SizedBox(height: AppSpacing.sm),
                              PrimaryButton(
                                label: 'Continue',
                                isLoading: isLoading,
                                onPressed: () => _continue(authProvider),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: AppSpacing.lg),
                        Wrap(
                          alignment: WrapAlignment.center,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text(
                              'Already have an account?',
                              style: textTheme.bodyMedium,
                            ),
                            TextButton(
                              onPressed: _goToLogin,
                              child: const Text('Sign In'),
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
          ),
        ],
      ),
    );
  }
}
