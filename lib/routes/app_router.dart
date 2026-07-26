import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../features/admin/presentation/admin_home_screen.dart';
import '../features/auth/presentation/account_type_selection_screen.dart';
import '../features/auth/presentation/login_screen.dart';
import '../features/auth/presentation/organization_profile_setup_screen.dart';
import '../features/auth/presentation/organization_registration_screen.dart';
import '../features/auth/presentation/splash_screen.dart';
import '../features/auth/presentation/student_profile_registration_screen.dart';
import '../features/auth/presentation/student_registration_screen.dart';
import '../features/opportunities/presentation/opportunity_form_screen.dart';
import '../features/opportunities/presentation/organization_opportunities_screen.dart';
import '../features/opportunities/presentation/organization_opportunity_details_screen.dart';
import '../features/organization/presentation/organization_home_screen.dart';
import '../features/student/presentation/student_home_screen.dart';
import '../providers/auth_provider.dart';
import '../providers/organization_profile_provider.dart';
import '../providers/student_profile_provider.dart';
import 'app_routes.dart';

const _splashPath = '/splash';
const _loginPath = AppRoutes.login;
const _studentPath = AppRoutes.studentHome;
const _organizationPath = AppRoutes.organizationHome;
const _adminPath = '/admin';

/// Routes reachable without being signed in — i.e. [_loginPath] plus the
/// account-type selection and registration screens added for the sign-up
/// flow.
///
/// Step 2 of student registration and the organization profile-setup
/// fallback are deliberately NOT here: both depend on an authenticated
/// session, so an unauthenticated visitor is redirected to login like any
/// other protected route, rather than being shown a profile screen for no
/// one in particular. Organization registration itself IS public — unlike
/// student, it's a single screen/route that only ever calls the API once,
/// at the very end, so there's no separate "step 2" route boundary to
/// worry about here.
const _publicPaths = {
  _loginPath,
  AppRoutes.accountTypeSelection,
  AppRoutes.studentRegistration,
  AppRoutes.organizationRegistration,
};

/// Both steps of student registration — an authenticated student is never
/// allowed to linger on either once their profile is confirmed complete.
const _studentOnboardingPaths = {
  AppRoutes.studentRegistration,
  AppRoutes.studentProfileRegistration,
};

/// Organization registration plus its defensive profile-setup fallback —
/// an authenticated organization is never allowed to linger on either once
/// its profile is confirmed complete (which, in practice, is always true
/// the instant it's authenticated — see OrganizationProfileSetupScreen).
const _organizationOnboardingPaths = {
  AppRoutes.organizationRegistration,
  AppRoutes.organizationProfileRegistration,
};

/// Organization opportunity management — a protected feature area, not
/// onboarding. Matched by prefix (not an exact set) since these routes
/// carry dynamic `:id` segments.
const _organizationOpportunitiesPathPrefix =
    AppRoutes.organizationOpportunities;

/// Defines the app's navigation routes and redirects based on
/// [AuthProvider], [StudentProfileProvider], and [OrganizationProfileProvider].
class AppRouter {
  AppRouter(
    this.authProvider,
    this.studentProfileProvider,
    this.organizationProfileProvider,
  ) {
    router = GoRouter(
      initialLocation: _splashPath,
      refreshListenable: Listenable.merge([
        authProvider,
        studentProfileProvider,
        organizationProfileProvider,
      ]),
      redirect: _redirect,
      routes: [
        GoRoute(path: _splashPath, builder: (_, _) => const SplashScreen()),
        GoRoute(path: _loginPath, builder: (_, _) => const LoginScreen()),
        GoRoute(
          path: AppRoutes.accountTypeSelection,
          builder: (_, _) => const AccountTypeSelectionScreen(),
        ),
        GoRoute(
          path: AppRoutes.studentRegistration,
          builder: (_, _) => const StudentRegistrationScreen(),
        ),
        GoRoute(
          path: AppRoutes.studentProfileRegistration,
          builder: (_, _) => const StudentProfileRegistrationScreen(),
        ),
        GoRoute(
          path: AppRoutes.organizationRegistration,
          builder: (_, _) => const OrganizationRegistrationScreen(),
        ),
        GoRoute(
          path: AppRoutes.organizationProfileRegistration,
          builder: (_, _) => const OrganizationProfileSetupScreen(),
        ),
        GoRoute(
          path: _studentPath,
          builder: (_, _) => const StudentHomeScreen(),
        ),
        GoRoute(
          path: _organizationPath,
          builder: (_, _) => const OrganizationHomeScreen(),
        ),
        GoRoute(path: _adminPath, builder: (_, _) => const AdminHomeScreen()),
        // The literal "/new" segment is declared before the parameterized
        // "/:id" route below so it's never mistaken for an ID.
        GoRoute(
          path: AppRoutes.organizationOpportunityCreate,
          builder: (_, _) => const OpportunityFormScreen(),
        ),
        GoRoute(
          path: AppRoutes.organizationOpportunities,
          builder: (_, _) => const OrganizationOpportunitiesScreen(),
        ),
        GoRoute(
          path: '${AppRoutes.organizationOpportunities}/:id/edit',
          builder: (_, state) => OpportunityFormScreen(
            // A malformed ID becomes 0 rather than null — null means
            // "create mode" to this screen, which a broken edit link must
            // never silently fall into. An id of 0 instead reaches the
            // same safe "not found" error path a valid-but-nonexistent ID
            // would.
            opportunityId: int.tryParse(state.pathParameters['id'] ?? '') ?? 0,
          ),
        ),
        GoRoute(
          path: '${AppRoutes.organizationOpportunities}/:id',
          builder: (_, state) => OrganizationOpportunityDetailsScreen(
            opportunityId: int.tryParse(state.pathParameters['id'] ?? '') ?? 0,
          ),
        ),
      ],
    );
  }

  final AuthProvider authProvider;
  final StudentProfileProvider studentProfileProvider;
  final OrganizationProfileProvider organizationProfileProvider;
  late final GoRouter router;

  Future<String?> _redirect(BuildContext context, GoRouterState state) async {
    final currentPath = state.matchedLocation;

    // Still checking for a saved session at startup: stay on the splash
    // screen until that finishes.
    if (!authProvider.isInitialized) {
      return currentPath == _splashPath ? null : _splashPath;
    }

    if (!authProvider.isAuthenticated) {
      return _publicPaths.contains(currentPath) ? null : _loginPath;
    }

    final role = authProvider.user?.role;

    // A student's or organization's profile-completion status is the one
    // piece of state the router needs beyond auth itself. It's asked for
    // at most once per sign-in (guarded by `hasChecked`) and cached from
    // then on — this is not a fabricated flag, it's the real backend
    // answer, kept around so redirect doesn't re-fetch it on every
    // navigation.
    if (role == 'student' && !studentProfileProvider.hasChecked) {
      await studentProfileProvider.checkProfileStatus();
    }
    if (role == 'organization' && !organizationProfileProvider.hasChecked) {
      await organizationProfileProvider.checkProfileStatus();
    }

    final homePath = _homePathForRole(role);

    // Authenticated users shouldn't linger on splash or login.
    if (currentPath == _splashPath || currentPath == _loginPath) {
      return homePath;
    }

    // Nor should they be able to open a different role's home screen.
    if (_isHomePath(currentPath) && currentPath != homePath) {
      return homePath;
    }

    // No role may use another role's onboarding routes.
    if (role != 'student' && _studentOnboardingPaths.contains(currentPath)) {
      return homePath;
    }
    if (role != 'organization' &&
        _organizationOnboardingPaths.contains(currentPath)) {
      return homePath;
    }

    // Opportunity management is an organization-only feature area — not
    // onboarding, but still off-limits to every other role.
    if (role != 'organization' &&
        currentPath.startsWith(_organizationOpportunitiesPathPrefix)) {
      return homePath;
    }

    if (role == 'student') {
      return _redirectForStudent(currentPath, homePath);
    }
    if (role == 'organization') {
      return _redirectForOrganization(currentPath, homePath);
    }

    return null;
  }

  String? _redirectForStudent(String currentPath, String homePath) {
    final profileComplete =
        studentProfileProvider.isProfileStatusKnown &&
        studentProfileProvider.hasProfile;
    final profileIncomplete =
        studentProfileProvider.isProfileStatusKnown &&
        !studentProfileProvider.hasProfile;

    // An authenticated student can never resubmit Step 1 — send them
    // onward to wherever they actually belong.
    if (currentPath == AppRoutes.studentRegistration) {
      return profileComplete ? homePath : AppRoutes.studentProfileRegistration;
    }

    // Step 2 is open to an authenticated student unless their profile is
    // already confirmed complete.
    if (currentPath == AppRoutes.studentProfileRegistration) {
      return profileComplete ? homePath : null;
    }

    // Anywhere else: a student with a confirmed-incomplete profile must
    // finish onboarding first. An unknown status (not yet checked, or the
    // check itself failed) never forces a redirect — that would mean
    // guessing at state the backend hasn't actually confirmed.
    if (profileIncomplete) {
      return AppRoutes.studentProfileRegistration;
    }

    return null;
  }

  String? _redirectForOrganization(String currentPath, String homePath) {
    final profileComplete =
        organizationProfileProvider.isProfileStatusKnown &&
        organizationProfileProvider.hasProfile;
    final profileIncomplete =
        organizationProfileProvider.isProfileStatusKnown &&
        !organizationProfileProvider.hasProfile;

    // An authenticated organization can never resubmit registration —
    // send them onward to wherever they actually belong. In practice this
    // always means home: registration creates the profile atomically, so
    // an authenticated organization is complete from the moment it exists.
    if (currentPath == AppRoutes.organizationRegistration) {
      return profileComplete
          ? homePath
          : AppRoutes.organizationProfileRegistration;
    }

    if (currentPath == AppRoutes.organizationProfileRegistration) {
      return profileComplete ? homePath : null;
    }

    // Anywhere else: an organization with a confirmed-incomplete profile
    // (unreachable in normal operation, but handled defensively) is sent
    // to the profile-setup fallback. An unknown status (not yet checked,
    // or the check itself failed) never forces a redirect.
    if (profileIncomplete) {
      return AppRoutes.organizationProfileRegistration;
    }

    return null;
  }

  bool _isHomePath(String path) {
    return path == _studentPath ||
        path == _organizationPath ||
        path == _adminPath;
  }

  String _homePathForRole(String? role) {
    switch (role) {
      case 'student':
        return _studentPath;
      case 'organization':
        return _organizationPath;
      case 'admin':
        return _adminPath;
      default:
        // An unknown role shouldn't happen, but fall back to login
        // rather than crashing.
        return _loginPath;
    }
  }
}
