import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/app_widgets.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/organization_profile_provider.dart';

/// A defensive landing spot for an authenticated organization whose
/// profile is confirmed missing.
///
/// Under normal operation this route is unreachable: `POST
/// /register/organization` creates the account and its profile atomically
/// in one database transaction (see `AuthRepository.registerOrganization`),
/// and the backend has no endpoint to create an organization profile on
/// its own afterward — only `GET`/`PUT /api/organization/profile`, and PUT
/// 404s if no profile exists yet. So there's no form this screen could
/// submit that the backend would accept.
///
/// It exists purely so a direct visit, a stale link, or a genuine backend
/// inconsistency has somewhere safe to land instead of crashing or looping
/// — with a way to re-check status rather than being stuck.
class OrganizationProfileSetupScreen extends StatelessWidget {
  const OrganizationProfileSetupScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final profileProvider = context.watch<OrganizationProfileProvider>();
    final authProvider = context.watch<AuthProvider>();

    return Scaffold(
      appBar: AppBar(actions: const [ThemeToggleButton()]),
      body: Stack(
        children: [
          const Positioned.fill(child: AuthAnimatedBackground()),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Center(
                child: AuthEntrance(
                  children: [
                    AppErrorView(
                      title: 'Company Profile Setup Incomplete',
                      message:
                          "We couldn't find a company profile for your account. "
                          'Please contact support, or try again.',
                      onRetry: () => profileProvider.checkProfileStatus(),
                      retryLabel: 'Check Again',
                    ),
                    const SizedBox(height: AppSpacing.md),
                    // The account itself is real and untouched -- this is
                    // the one safe way out of the (normally unreachable)
                    // confirmed-incomplete state rather than being stuck
                    // here. Signing back in later returns here again via
                    // the same router logic, unless the underlying
                    // inconsistency is resolved.
                    SecondaryButton(
                      label: 'Sign Out',
                      onPressed: authProvider.logout,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
