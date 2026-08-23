import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_motion.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/app_widgets.dart';
import '../../../providers/auth_provider.dart';
import '../../../routes/app_routes.dart';
import 'registration_step_progress.dart';

/// The exact backend enum values for `organization_type`, mapped to
/// user-facing labels. Must match `RegisterOrganizationRequest`'s
/// `in:company,university,ngo,training_center,government,other` rule.
const _organizationTypeLabels = {
  'company': 'Company',
  'university': 'University',
  'ngo': 'NGO',
  'training_center': 'Training Center',
  'government': 'Government',
  'other': 'Other',
};

/// Company registration: a single screen presenting account information
/// and company information as two visual steps, submitted together as one
/// `POST /register/organization` call.
///
/// Unlike student registration, this can't be two separate steps hitting
/// two separate endpoints — the backend has no endpoint to create an
/// organization profile on its own (only `GET`/`PUT`, which require one to
/// already exist); `POST /register/organization` creates the account and
/// its profile atomically in one request, requiring the profile fields
/// up front. Splitting this across two *screens* (with a real navigation
/// and an API call in between, the way student registration works) would
/// mean either calling the endpoint too early without the profile fields,
/// or carrying the account fields (including the password) across a route
/// boundary — exactly what's not allowed. Keeping both steps as pages of
/// one widget's local state avoids both problems: nothing is submitted
/// until "Finish", and no account data ever leaves this State object.
class OrganizationRegistrationScreen extends StatefulWidget {
  const OrganizationRegistrationScreen({super.key});

  @override
  State<OrganizationRegistrationScreen> createState() =>
      _OrganizationRegistrationScreenState();
}

class _OrganizationRegistrationScreenState
    extends State<OrganizationRegistrationScreen> {
  final _accountFormKey = GlobalKey<FormState>();
  final _companyFormKey = GlobalKey<FormState>();

  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  final _organizationNameController = TextEditingController();
  final _industryController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _websiteController = TextEditingController();
  final _phoneController = TextEditingController();
  String? _organizationType;

  /// 0 = account information, 1 = company information. Purely a local UI
  /// concern — never reflected in the route, so there's nothing to carry
  /// across a navigation boundary.
  int _step = 0;

  /// +1 when moving Account -> Company, -1 moving back. Drives which side
  /// the step-transition slide enters/exits from — read once per
  /// `setState` by the `AnimatedSwitcher` in [build], never mutated mid
  /// transition.
  int _stepDirection = 1;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _organizationNameController.dispose();
    _industryController.dispose();
    _descriptionController.dispose();
    _websiteController.dispose();
    _phoneController.dispose();
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

  String? _validateOrganizationName(String? value) {
    final name = value?.trim() ?? '';
    if (name.isEmpty) return 'Company name is required';
    return null;
  }

  String? _validateOrganizationType(String? value) {
    if (value == null || value.isEmpty) return 'Company type is required';
    return null;
  }

  void _continueToCompanyStep() {
    // Dismiss the keyboard as soon as a submission attempt starts.
    FocusScope.of(context).unfocus();

    final isValid = _accountFormKey.currentState?.validate() ?? false;
    if (!isValid) return;

    setState(() {
      _stepDirection = 1;
      _step = 1;
    });
  }

  /// Safe: nothing is submitted to the backend until "Finish" on the
  /// Company step, so no account exists yet to invalidate, and every
  /// field already entered on the Account step stays intact (its
  /// controllers are never cleared) — this is purely local UI state
  /// (UI Phase 1.4).
  void _backToAccountStep() {
    setState(() {
      _stepDirection = -1;
      _step = 0;
    });
  }

  Future<void> _finish(AuthProvider authProvider) async {
    FocusScope.of(context).unfocus();

    final isValid = _companyFormKey.currentState?.validate() ?? false;
    if (!isValid) return;

    String? orNull(TextEditingController controller) {
      final value = controller.text.trim();
      return value.isEmpty ? null : value;
    }

    final success = await authProvider.registerOrganization(
      name: _nameController.text.trim(),
      email: _emailController.text.trim(),
      password: _passwordController.text,
      organizationName: _organizationNameController.text.trim(),
      organizationType: _organizationType!,
      industry: orNull(_industryController),
      description: orNull(_descriptionController),
      website: orNull(_websiteController),
      phone: orNull(_phoneController),
    );

    if (!mounted) return;
    // On failure, errorMessage is already set and shown reactively below —
    // nothing else to do here but stay on this screen. The account was
    // never created, so nothing about Step 1 needs to change either.
    if (!success) return;

    // A brand-new organization always has its profile created atomically
    // by the call above — there's nowhere else to route to but home.
    context.go(AppRoutes.organizationHome);
  }

  void _goToLogin() {
    context.go(AppRoutes.login);
  }

  void _goToAccountTypeSelection() {
    context.go(AppRoutes.accountTypeSelection);
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = context.watch<AuthProvider>();
    final currentStep = _step == 0
        ? _AccountStep(
            key: const ValueKey(0),
            formKey: _accountFormKey,
            nameController: _nameController,
            emailController: _emailController,
            passwordController: _passwordController,
            confirmPasswordController: _confirmPasswordController,
            isLoading: authProvider.isLoading,
            errorMessage: authProvider.errorMessage,
            validateFullName: _validateFullName,
            validateEmail: _validateEmail,
            validatePassword: _validatePassword,
            validateConfirmPassword: _validateConfirmPassword,
            onBack: _goToAccountTypeSelection,
            onContinue: _continueToCompanyStep,
            onSignIn: _goToLogin,
          )
        : _CompanyStep(
            key: const ValueKey(1),
            formKey: _companyFormKey,
            organizationNameController: _organizationNameController,
            organizationType: _organizationType,
            onOrganizationTypeChanged: (value) =>
                setState(() => _organizationType = value),
            industryController: _industryController,
            descriptionController: _descriptionController,
            websiteController: _websiteController,
            phoneController: _phoneController,
            isLoading: authProvider.isLoading,
            errorMessage: authProvider.errorMessage,
            validateOrganizationName: _validateOrganizationName,
            validateOrganizationType: _validateOrganizationType,
            onBack: _backToAccountStep,
            onFinish: () => _finish(authProvider),
          );

    // A directional slide+fade between the two steps -- which side each
    // one enters/exits from depends on `_stepDirection`, not just which
    // child is "new" vs "old" (the default `AnimatedSwitcher` recipe only
    // gives every child the same transition). Comparing `child.key` to the
    // step actually being switched *to* is what tells the same shared
    // `transitionBuilder` apart for the incoming vs. outgoing widget.
    //
    // Both `_AccountStep`/`_CompanyStep` are stateless -- every controller
    // they read lives on this State object, not inside them -- so swapping
    // which one is mounted here never recreates or discards a controller.
    return AnimatedSwitcher(
      duration: AppMotion.reduced(context, AppMotion.normal),
      switchInCurve: AppMotion.entrance,
      switchOutCurve: AppMotion.standard,
      transitionBuilder: (child, animation) {
        final isIncoming = child.key == ValueKey(_step);
        final sign = isIncoming ? _stepDirection : -_stepDirection;
        return SlideTransition(
          position: Tween<Offset>(
            begin: Offset(0.06 * sign, 0),
            end: Offset.zero,
          ).animate(animation),
          child: FadeTransition(opacity: animation, child: child),
        );
      },
      layoutBuilder: (currentChild, previousChildren) => Stack(
        alignment: Alignment.topCenter,
        children: [...previousChildren, ?currentChild],
      ),
      child: currentStep,
    );
  }
}

/// Step 1 of 2: account information (name, email, password).
class _AccountStep extends StatelessWidget {
  const _AccountStep({
    super.key,
    required this.formKey,
    required this.nameController,
    required this.emailController,
    required this.passwordController,
    required this.confirmPasswordController,
    required this.isLoading,
    required this.errorMessage,
    required this.validateFullName,
    required this.validateEmail,
    required this.validatePassword,
    required this.validateConfirmPassword,
    required this.onBack,
    required this.onContinue,
    required this.onSignIn,
  });

  final GlobalKey<FormState> formKey;
  final TextEditingController nameController;
  final TextEditingController emailController;
  final TextEditingController passwordController;
  final TextEditingController confirmPasswordController;
  final bool isLoading;
  final String? errorMessage;
  final FormFieldValidator<String> validateFullName;
  final FormFieldValidator<String> validateEmail;
  final FormFieldValidator<String> validatePassword;
  final FormFieldValidator<String> validateConfirmPassword;
  final VoidCallback onBack;
  final VoidCallback onContinue;
  final VoidCallback onSignIn;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      // Reached with `context.go` (see AccountTypeSelectionScreen), which
      // leaves nothing to pop — so the back arrow needs an explicit target
      // instead of relying on Navigator.canPop.
      appBar: AppBar(
        leading: BackButton(onPressed: onBack),
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
                    key: formKey,
                    child: AuthEntrance(
                      children: [
                        Text(
                          'Create Company Account',
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
                                controller: nameController,
                                label: 'Full Name',
                                hint: 'Jane Doe',
                                prefixIcon: Icons.person_outline,
                                textInputAction: TextInputAction.next,
                                autofillHints: const [AutofillHints.name],
                                enabled: !isLoading,
                                validator: validateFullName,
                              ),
                              const SizedBox(height: AppSpacing.inputSpacing),
                              AppTextField(
                                controller: emailController,
                                label: 'Email',
                                hint: 'you@example.com',
                                prefixIcon: Icons.mail_outline,
                                keyboardType: TextInputType.emailAddress,
                                textInputAction: TextInputAction.next,
                                autofillHints: const [AutofillHints.email],
                                enabled: !isLoading,
                                validator: validateEmail,
                              ),
                              const SizedBox(height: AppSpacing.inputSpacing),
                              AppPasswordField(
                                controller: passwordController,
                                label: 'Password',
                                textInputAction: TextInputAction.next,
                                autofillHints: const [
                                  AutofillHints.newPassword,
                                ],
                                enabled: !isLoading,
                                validator: validatePassword,
                              ),
                              const SizedBox(height: AppSpacing.inputSpacing),
                              AppPasswordField(
                                controller: confirmPasswordController,
                                label: 'Confirm Password',
                                textInputAction: TextInputAction.done,
                                autofillHints: const [
                                  AutofillHints.newPassword,
                                ],
                                enabled: !isLoading,
                                validator: validateConfirmPassword,
                                onFieldSubmitted: (_) => onContinue(),
                              ),
                              AnimatedSwitcher(
                                duration: AppMotion.reduced(
                                  context,
                                  AppMotion.fast,
                                ),
                                child: errorMessage == null
                                    ? const SizedBox(width: double.infinity)
                                    : Padding(
                                        key: ValueKey(errorMessage),
                                        padding: const EdgeInsets.only(
                                          top: AppSpacing.xs,
                                        ),
                                        child: AppErrorView(
                                          title: 'Registration Failed',
                                          message: errorMessage!,
                                          compact: true,
                                        ),
                                      ),
                              ),
                              const SizedBox(height: AppSpacing.sm),
                              PrimaryButton(
                                label: 'Continue',
                                onPressed: onContinue,
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
                              onPressed: onSignIn,
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

/// Step 2 of 2: company information, submitted together with Step 1's
/// account fields as a single `POST /register/organization` call.
class _CompanyStep extends StatelessWidget {
  const _CompanyStep({
    super.key,
    required this.formKey,
    required this.organizationNameController,
    required this.organizationType,
    required this.onOrganizationTypeChanged,
    required this.industryController,
    required this.descriptionController,
    required this.websiteController,
    required this.phoneController,
    required this.isLoading,
    required this.errorMessage,
    required this.validateOrganizationName,
    required this.validateOrganizationType,
    required this.onBack,
    required this.onFinish,
  });

  final GlobalKey<FormState> formKey;
  final TextEditingController organizationNameController;
  final String? organizationType;
  final ValueChanged<String?> onOrganizationTypeChanged;
  final TextEditingController industryController;
  final TextEditingController descriptionController;
  final TextEditingController websiteController;
  final TextEditingController phoneController;
  final bool isLoading;
  final String? errorMessage;
  final FormFieldValidator<String> validateOrganizationName;
  final FormFieldValidator<String> validateOrganizationType;
  final VoidCallback onBack;
  final VoidCallback onFinish;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      // Back here just returns to Step 1's local page (`_step = 0`) —
      // safe, since nothing is submitted to the backend until Finish, so
      // no account exists yet to invalidate (UI Phase 1.4).
      appBar: AppBar(
        leading: BackButton(onPressed: isLoading ? null : onBack),
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
                    key: formKey,
                    child: AuthEntrance(
                      children: [
                        Text(
                          'Complete Your Company Profile',
                          textAlign: TextAlign.center,
                          style: textTheme.displaySmall,
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          'Tell us about your company so we can personalise '
                          'opportunities for you.',
                          textAlign: TextAlign.center,
                          style: textTheme.bodyMedium?.copyWith(
                            color: AppColors.textSecondary,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.md),
                        const RegistrationStepProgress(
                          progress: 1,
                          stepText: 'Step 2 of 2',
                          label: 'Company Information',
                        ),
                        const SizedBox(height: AppSpacing.xl),
                        AppCard(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              const SectionHeader(title: 'Company Information'),
                              const SizedBox(height: AppSpacing.xs),
                              AppTextField(
                                controller: organizationNameController,
                                label: 'Company Name',
                                hint: 'Acme Corp',
                                prefixIcon: Icons.business_outlined,
                                textInputAction: TextInputAction.next,
                                enabled: !isLoading,
                                validator: validateOrganizationName,
                              ),
                              const SizedBox(height: AppSpacing.inputSpacing),
                              DropdownButtonFormField<String>(
                                initialValue: organizationType,
                                // Without this, the button sizes itself around
                                // its widest item ("Training Center") rather
                                // than the available width, overflowing on
                                // narrow screens instead of ellipsizing.
                                isExpanded: true,
                                decoration: const InputDecoration(
                                  labelText: 'Company Type',
                                ),
                                items: [
                                  for (final entry
                                      in _organizationTypeLabels.entries)
                                    DropdownMenuItem(
                                      value: entry.key,
                                      child: Text(
                                        entry.value,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                ],
                                onChanged: isLoading
                                    ? null
                                    : onOrganizationTypeChanged,
                                validator: validateOrganizationType,
                              ),
                              const SizedBox(height: AppSpacing.inputSpacing),
                              AppTextField(
                                controller: industryController,
                                label: 'Industry (optional)',
                                hint: 'e.g. Software',
                                prefixIcon: Icons.factory_outlined,
                                textInputAction: TextInputAction.next,
                                enabled: !isLoading,
                              ),
                              const SizedBox(height: AppSpacing.inputSpacing),
                              AppTextField(
                                controller: websiteController,
                                label: 'Website (optional)',
                                hint: 'https://example.com',
                                prefixIcon: Icons.link,
                                keyboardType: TextInputType.url,
                                textInputAction: TextInputAction.next,
                                enabled: !isLoading,
                              ),
                              const SizedBox(height: AppSpacing.inputSpacing),
                              AppTextField(
                                controller: phoneController,
                                label: 'Phone (optional)',
                                hint: '+1 555 123 4567',
                                prefixIcon: Icons.phone_outlined,
                                keyboardType: TextInputType.phone,
                                textInputAction: TextInputAction.next,
                                enabled: !isLoading,
                              ),
                              const SizedBox(height: AppSpacing.inputSpacing),
                              AppTextField(
                                controller: descriptionController,
                                label: 'Description (optional)',
                                hint: 'What does your company do?',
                                prefixIcon: Icons.notes_outlined,
                                textInputAction: TextInputAction.done,
                                enabled: !isLoading,
                                maxLines: 3,
                                onFieldSubmitted: (_) => onFinish(),
                              ),
                              AnimatedSwitcher(
                                duration: AppMotion.reduced(
                                  context,
                                  AppMotion.fast,
                                ),
                                child: errorMessage == null
                                    ? const SizedBox(width: double.infinity)
                                    : Padding(
                                        key: ValueKey(errorMessage),
                                        padding: const EdgeInsets.only(
                                          top: AppSpacing.xs,
                                        ),
                                        child: AppErrorView(
                                          title: 'Something Went Wrong',
                                          message: errorMessage!,
                                          compact: true,
                                        ),
                                      ),
                              ),
                              const SizedBox(height: AppSpacing.lg),
                              PrimaryButton(
                                label: 'Finish',
                                isLoading: isLoading,
                                onPressed: onFinish,
                              ),
                            ],
                          ),
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
