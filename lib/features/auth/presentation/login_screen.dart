import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_motion.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/app_error_view.dart';
import '../../../core/widgets/app_password_field.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../core/widgets/auth_animated_background.dart';
import '../../../core/widgets/auth_entrance.dart';
import '../../../core/widgets/primary_button.dart';
import '../../../core/widgets/theme_toggle_button.dart';
import '../../../providers/auth_provider.dart';
import '../../../routes/app_routes.dart';

/// Viewport width above which Login shows the two-panel Web layout
/// (brand panel + form) instead of the single-column mobile layout.
const _wideBreakpoint = 900.0;

/// The sign-in screen. The router sends the user to their role's home
/// screen automatically once login succeeds — this screen never navigates
/// on its own.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  late final AnimationController _entranceController;
  late final Animation<double> _entranceOpacity;
  late final Animation<Offset> _entranceSlide;

  @override
  void initState() {
    super.initState();
    final reducedMotion = SchedulerBinding
        .instance
        .platformDispatcher
        .accessibilityFeatures
        .disableAnimations;

    _entranceController = AnimationController(
      vsync: this,
      duration: reducedMotion ? const Duration(milliseconds: 1) : AppMotion.normal,
    )..forward();
    _entranceOpacity = CurvedAnimation(
      parent: _entranceController,
      curve: AppMotion.entrance,
    );
    _entranceSlide =
        Tween<Offset>(
          begin: reducedMotion ? Offset.zero : const Offset(0, 0.03),
          end: Offset.zero,
        ).animate(
          CurvedAnimation(parent: _entranceController, curve: AppMotion.entrance),
        );
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _entranceController.dispose();
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
    final isLoading = authProvider.isLoading;

    return Scaffold(
      body: SafeArea(
        child: Stack(
          children: [
            LayoutBuilder(
              builder: (context, constraints) {
                final isWide = constraints.maxWidth >= _wideBreakpoint;

                final formPanel = FadeTransition(
                  opacity: _entranceOpacity,
                  child: SlideTransition(
                    position: _entranceSlide,
                    child: _LoginFormPanel(
                      formKey: _formKey,
                      emailController: _emailController,
                      passwordController: _passwordController,
                      isLoading: isLoading,
                      errorMessage: authProvider.errorMessage,
                      validateEmail: _validateEmail,
                      validatePassword: _validatePassword,
                      onSubmit: () => _submit(authProvider),
                      showHeader: !isWide,
                    ),
                  ),
                );

                if (!isWide) {
                  return Stack(
                    children: [
                      const Positioned.fill(child: AuthAnimatedBackground()),
                      SingleChildScrollView(
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
                              child: formPanel,
                            ),
                          ),
                        ),
                      ),
                    ],
                  );
                }

                return Row(
                  children: [
                    const Expanded(flex: 5, child: _BrandPanel()),
                    Expanded(
                      flex: 4,
                      child: ColoredBox(
                        color: AppColors.background,
                        child: Stack(
                          children: [
                            const Positioned.fill(
                              child: AuthAnimatedBackground(),
                            ),
                            Center(
                              child: SingleChildScrollView(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: AppSpacing.xl,
                                  vertical: AppSpacing.screenVertical,
                                ),
                                child: ConstrainedBox(
                                  constraints: const BoxConstraints(
                                    maxWidth: 420,
                                  ),
                                  child: formPanel,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
            const Positioned(
              top: AppSpacing.xs,
              right: AppSpacing.xs,
              child: ThemeToggleButton(),
            ),
          ],
        ),
      ),
    );
  }
}

/// The left brand panel shown only on wide (Web/desktop) viewports —
/// built entirely from Flutter shapes/icons, no image asset.
///
/// UI Phase 1.5: the gradient angle settles into place once as the panel
/// first appears (a subtle, one-shot drift rather than a perpetual loop —
/// see `AuthAnimatedBackground`'s doc comment for why this codebase avoids
/// repeating animations on Auth screens), and its content fades/slides in
/// staggered via [AuthEntrance].
class _BrandPanel extends StatefulWidget {
  const _BrandPanel();

  @override
  State<_BrandPanel> createState() => _BrandPanelState();
}

class _BrandPanelState extends State<_BrandPanel>
    with SingleTickerProviderStateMixin {
  late final AnimationController _gradientController;
  late final bool _reducedMotion;

  @override
  void initState() {
    super.initState();
    _reducedMotion = SchedulerBinding
        .instance
        .platformDispatcher
        .accessibilityFeatures
        .disableAnimations;

    _gradientController = AnimationController(
      vsync: this,
      duration: _reducedMotion
          ? const Duration(milliseconds: 1)
          : const Duration(seconds: 5),
    )..forward();
  }

  @override
  void dispose() {
    _gradientController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _gradientController,
      builder: (context, child) {
        final t = _reducedMotion
            ? 1.0
            : Curves.easeOut.transform(_gradientController.value);

        return DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.lerp(
                const Alignment(-0.35, -1.3),
                Alignment.topLeft,
                t,
              )!,
              end: Alignment.lerp(
                const Alignment(1.35, 0.3),
                Alignment.bottomRight,
                t,
              )!,
              colors: [
                AppColors.textPrimary,
                AppColors.primaryDark,
                AppColors.primary,
              ],
            ),
          ),
          child: child,
        );
      },
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xxl),
        child: AuthEntrance(
          mainAxisSize: MainAxisSize.max,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 64,
              height: 64,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: Colors.white.withValues(alpha: 0.24)),
              ),
              child: const Icon(
                Icons.work_outline_rounded,
                size: 32,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              'OpportunityHub',
              style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Where talent meets opportunity — smart matching for '
              'students and the organizations hiring them.',
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: Colors.white.withValues(alpha: 0.85),
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
            const _BrandHighlightRow(
              icon: Icons.auto_awesome_outlined,
              label: 'AI-assisted candidate matching',
            ),
            const SizedBox(height: AppSpacing.sm),
            const _BrandHighlightRow(
              icon: Icons.fact_check_outlined,
              label: 'Verified skills and education',
            ),
            const SizedBox(height: AppSpacing.sm),
            const _BrandHighlightRow(
              icon: Icons.forum_outlined,
              label: 'One place to track every application',
            ),
          ],
        ),
      ),
    );
  }
}

class _BrandHighlightRow extends StatelessWidget {
  const _BrandHighlightRow({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 20, color: Colors.white.withValues(alpha: 0.9)),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Text(
            label,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Colors.white.withValues(alpha: 0.85),
            ),
          ),
        ),
      ],
    );
  }
}

/// The actual sign-in form — identical fields/validation/behavior on both
/// layouts, just re-parented. [showHeader] controls whether the compact
/// logo + "Welcome Back" header renders above the form card (mobile only —
/// the wide layout's [_BrandPanel] already carries the brand identity, so
/// repeating it in the form column would be redundant).
class _LoginFormPanel extends StatelessWidget {
  const _LoginFormPanel({
    required this.formKey,
    required this.emailController,
    required this.passwordController,
    required this.isLoading,
    required this.errorMessage,
    required this.validateEmail,
    required this.validatePassword,
    required this.onSubmit,
    required this.showHeader,
  });

  final GlobalKey<FormState> formKey;
  final TextEditingController emailController;
  final TextEditingController passwordController;
  final bool isLoading;
  final String? errorMessage;
  final FormFieldValidator<String> validateEmail;
  final FormFieldValidator<String> validatePassword;
  final VoidCallback onSubmit;
  final bool showHeader;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Form(
      key: formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showHeader) ...[
            const SizedBox(height: AppSpacing.xl),
            const _LogoPlaceholder(),
            const SizedBox(height: AppSpacing.lg),
          ],
          Text(
            'Welcome Back',
            textAlign: showHeader ? TextAlign.center : TextAlign.start,
            style: textTheme.displaySmall,
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Sign in to continue using OpportunityHub.',
            textAlign: showHeader ? TextAlign.center : TextAlign.start,
            style: textTheme.bodyMedium?.copyWith(color: AppColors.textSecondary),
          ),
          const SizedBox(height: AppSpacing.xl),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.cardPadding),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
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
                    textInputAction: TextInputAction.done,
                    autofillHints: const [AutofillHints.password],
                    enabled: !isLoading,
                    validator: validatePassword,
                    onFieldSubmitted: (_) => onSubmit(),
                  ),
                  const SizedBox(height: AppSpacing.xxs),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: () => context.push(AppRoutes.forgotPassword),
                      child: const Text('Forgot Password?'),
                    ),
                  ),
                  AnimatedSwitcher(
                    duration: AppMotion.reduced(context, AppMotion.fast),
                    child: errorMessage == null
                        ? const SizedBox(width: double.infinity)
                        : Padding(
                            key: ValueKey(errorMessage),
                            padding: const EdgeInsets.only(top: AppSpacing.xs),
                            child: AppErrorView(
                              title: 'Login Failed',
                              message: errorMessage!,
                              compact: true,
                            ),
                          ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  PrimaryButton(
                    label: 'Login',
                    isLoading: isLoading,
                    onPressed: () => onSubmit(),
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
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
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
              Text("Don't have an account?", style: textTheme.bodyMedium),
              TextButton(
                onPressed: () => context.push(AppRoutes.accountTypeSelection),
                child: const Text('Create Account'),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xl),
        ],
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
        child: Icon(
          Icons.work_outline_rounded,
          size: 36,
          color: AppColors.primaryDark,
        ),
      ),
    );
  }
}
