import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/auth_animated_background.dart';
import '../../../core/widgets/auth_entrance.dart';
import '../../../core/widgets/theme_toggle_button.dart';
import '../../../routes/app_routes.dart';
import 'interactive_role_card.dart';

/// Lets a new user choose whether they're signing up as a student/job
/// seeker or as a company/organization, before landing on that account
/// type's registration form.
///
/// UI-only: "Company" is shown to the user, but the underlying route and
/// role stay named "organization" throughout the app.
///
/// UI Phase 1.5: tapping a role card selects it (a deliberate, reversible
/// choice, tracked in local `_selectedRole` state) without navigating —
/// only the card's own "Continue as ..." button navigates. Selecting
/// isn't required before continuing (either button always works on its
/// own), it just gives hovering/tapping a card a real, visible effect
/// before the user commits.
class AccountTypeSelectionScreen extends StatefulWidget {
  const AccountTypeSelectionScreen({super.key});

  @override
  State<AccountTypeSelectionScreen> createState() =>
      _AccountTypeSelectionScreenState();
}

enum _AccountRole { student, organization }

class _AccountTypeSelectionScreenState
    extends State<AccountTypeSelectionScreen> {
  _AccountRole? _selectedRole;

  void _select(_AccountRole role) {
    setState(() => _selectedRole = role);
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      body: SafeArea(
        child: Stack(
          children: [
            const Positioned.fill(child: AuthAnimatedBackground()),
            Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    IconButton(
                      // `go`, not `pop`: this screen can be reached either
                      // by a push from LoginScreen, or via `go` from Step
                      // 1's own back button (see StudentRegistrationScreen),
                      // which leaves nothing to pop back to. An explicit
                      // target works regardless of how we got here.
                      onPressed: () => context.go(AppRoutes.login),
                      icon: const Icon(Icons.arrow_back),
                      tooltip: 'Back',
                    ),
                    const ThemeToggleButton(),
                  ],
                ),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.screenHorizontal,
                      vertical: AppSpacing.screenVertical,
                    ),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 900),
                        child: AuthEntrance(
                          children: [
                            const _LogoPlaceholder(),
                            const SizedBox(height: AppSpacing.lg),
                            Text(
                              'How will you use OpportunityHub?',
                              textAlign: TextAlign.center,
                              style: textTheme.displaySmall,
                            ),
                            const SizedBox(height: AppSpacing.xs),
                            Text(
                              'Choose how you want to get started.',
                              textAlign: TextAlign.center,
                              style: textTheme.bodyMedium?.copyWith(
                                color: AppColors.textSecondary,
                              ),
                            ),
                            const SizedBox(height: AppSpacing.xl),
                            _AccountTypeCards(
                              selectedRole: _selectedRole,
                              onSelectStudentCard: () =>
                                  _select(_AccountRole.student),
                              onSelectOrganizationCard: () =>
                                  _select(_AccountRole.organization),
                              // `go`, not `push`, for both — Organization
                              // registration authenticates too (a single
                              // combined account+profile call), so it needs
                              // the same treatment as Student to avoid a
                              // push-chain collapse once authenticated.
                              onContinueAsStudent: () =>
                                  context.go(AppRoutes.studentRegistration),
                              onContinueAsOrganization: () => context.go(
                                AppRoutes.organizationRegistration,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
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
        child: Icon(
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
    required this.selectedRole,
    required this.onSelectStudentCard,
    required this.onSelectOrganizationCard,
    required this.onContinueAsStudent,
    required this.onContinueAsOrganization,
  });

  final _AccountRole? selectedRole;
  final VoidCallback onSelectStudentCard;
  final VoidCallback onSelectOrganizationCard;
  final VoidCallback onContinueAsStudent;
  final VoidCallback onContinueAsOrganization;

  static const double _wideBreakpoint = 640;

  @override
  Widget build(BuildContext context) {
    // Every capability listed here corresponds to a screen that already
    // exists in the app today (Discover Opportunities, My Applications,
    // CV/Skills/Education Verification for students; Manage Opportunities,
    // Candidate Search/Invitations, and Applications/Assessments for
    // organizations) — nothing here describes a feature that doesn't
    // actually exist yet.
    final studentCard = InteractiveRoleCard(
      icon: Icons.school_outlined,
      accentColor: AppColors.primary,
      title: 'Student / Job Seeker',
      description:
          'Find jobs and internships, build your profile, and manage '
          'your applications.',
      benefits: const [
        'Discover and apply to opportunities',
        'Track every application in one place',
        'Build your CV, skills, and verified education',
      ],
      actionLabel: 'Continue as Student',
      isSelected: selectedRole == _AccountRole.student,
      onSelect: onSelectStudentCard,
      onContinue: onContinueAsStudent,
    );

    final organizationCard = InteractiveRoleCard(
      icon: Icons.business_outlined,
      accentColor: AppColors.primaryDark,
      title: 'Company',
      description:
          'Publish opportunities, review applicants, and manage interviews.',
      benefits: const [
        'Publish and manage opportunities',
        'Discover and invite candidates',
        'Manage applications, assessments, and interviews',
      ],
      actionLabel: 'Continue as Company',
      isSelected: selectedRole == _AccountRole.organization,
      onSelect: onSelectOrganizationCard,
      onContinue: onContinueAsOrganization,
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
