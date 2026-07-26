import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/primary_button.dart';
import '../../../routes/app_routes.dart';

/// Lets a new user choose whether they're signing up as a student/job
/// seeker or as a company/organization, before landing on that account
/// type's (not yet built) registration form.
///
/// UI-only: "Company" is shown to the user, but the underlying route and
/// role stay named "organization" throughout the app.
class AccountTypeSelectionScreen extends StatelessWidget {
  const AccountTypeSelectionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Align(
              alignment: Alignment.topLeft,
              child: IconButton(
                // `go`, not `pop`: this screen can be reached either by a
                // push from LoginScreen, or via `go` from Step 1's own
                // back button (see StudentRegistrationScreen), which
                // leaves nothing to pop back to. An explicit target works
                // regardless of how we got here.
                onPressed: () => context.go(AppRoutes.login),
                icon: const Icon(Icons.arrow_back),
                tooltip: 'Back',
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.screenHorizontal,
                  vertical: AppSpacing.screenVertical,
                ),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 720),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const _LogoPlaceholder(),
                        const SizedBox(height: AppSpacing.lg),
                        Text(
                          'Create Your Account',
                          textAlign: TextAlign.center,
                          style: textTheme.displaySmall,
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          'Choose the account type that best describes you.',
                          textAlign: TextAlign.center,
                          style: textTheme.bodyMedium?.copyWith(
                            color: AppColors.textSecondary,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.xl),
                        _AccountTypeCards(
                          // `go`, not `push`, for both — see
                          // StudentRegistrationScreen for why. Organization
                          // registration now authenticates too (a single
                          // combined account+profile call), so it needs the
                          // same treatment to avoid the same push-chain
                          // collapse.
                          onSelectStudent: () =>
                              context.go(AppRoutes.studentRegistration),
                          onSelectOrganization: () =>
                              context.go(AppRoutes.organizationRegistration),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
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

/// Lays the two account-type cards out side by side once there's enough
/// width (tablet/web), and stacked vertically otherwise (mobile).
class _AccountTypeCards extends StatelessWidget {
  const _AccountTypeCards({
    required this.onSelectStudent,
    required this.onSelectOrganization,
  });

  final VoidCallback onSelectStudent;
  final VoidCallback onSelectOrganization;

  static const double _wideBreakpoint = 640;

  @override
  Widget build(BuildContext context) {
    final studentCard = _AccountTypeCard(
      icon: Icons.school_outlined,
      title: 'Student / Job Seeker',
      description:
          'Find jobs and internships, build your profile, and manage '
          'your applications.',
      actionLabel: 'Continue as Student',
      onSelect: onSelectStudent,
    );

    final organizationCard = _AccountTypeCard(
      icon: Icons.business_outlined,
      title: 'Company',
      description:
          'Publish opportunities, review applicants, and manage interviews.',
      actionLabel: 'Continue as Company',
      onSelect: onSelectOrganization,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= _wideBreakpoint) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: studentCard),
              const SizedBox(width: AppSpacing.md),
              Expanded(child: organizationCard),
            ],
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            studentCard,
            const SizedBox(height: AppSpacing.md),
            organizationCard,
          ],
        );
      },
    );
  }
}

/// A single selectable account-type option: icon, title, description, and
/// an explicit action button — the whole card is also tappable via
/// [AppCard.onTap], both triggering the same [onSelect] callback.
class _AccountTypeCard extends StatelessWidget {
  const _AccountTypeCard({
    required this.icon,
    required this.title,
    required this.description,
    required this.actionLabel,
    required this.onSelect,
  });

  final IconData icon;
  final String title;
  final String description;
  final String actionLabel;
  final VoidCallback onSelect;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return AppCard(
      onTap: onSelect,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 56,
            height: 56,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.primaryContainer,
              borderRadius: AppRadius.mediumRadius,
            ),
            child: Icon(icon, size: 28, color: AppColors.primaryDark),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(title, style: textTheme.titleLarge),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            description,
            style: textTheme.bodyMedium?.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          PrimaryButton(label: actionLabel, onPressed: onSelect),
        ],
      ),
    );
  }
}
