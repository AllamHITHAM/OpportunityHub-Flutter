import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../features/admin/presentation/admin_education_verifications_screen.dart';
import '../features/admin/presentation/admin_home_screen.dart';
import '../features/admin/presentation/admin_organization_details_screen.dart';
import '../features/admin/presentation/admin_organizations_screen.dart';
import '../features/admin/presentation/admin_skills_screen.dart';
import '../features/admin/presentation/admin_users_screen.dart';
import '../features/auth/presentation/account_type_selection_screen.dart';
import '../features/auth/presentation/email_verified_screen.dart';
import '../features/auth/presentation/forgot_password_screen.dart';
import '../features/auth/presentation/login_screen.dart';
import '../features/auth/presentation/organization_profile_setup_screen.dart';
import '../features/auth/presentation/organization_registration_screen.dart';
import '../features/auth/presentation/reset_password_screen.dart';
import '../features/auth/presentation/splash_screen.dart';
import '../features/auth/presentation/student_profile_registration_screen.dart';
import '../features/auth/presentation/student_registration_screen.dart';
import '../features/applications/presentation/organization_applicants_screen.dart';
import '../features/applications/presentation/organization_application_details_screen.dart';
import '../features/applications/presentation/student_application_details_screen.dart';
import '../features/applications/presentation/student_applications_screen.dart';
import '../features/assessments/presentation/create_quiz_screen.dart';
import '../features/assessments/presentation/organization_quiz_editor_screen.dart';
import '../features/assessments/presentation/organization_quiz_results_screen.dart';
import '../features/assessments/presentation/schedule_interview_screen.dart';
import '../features/assessments/presentation/student_quiz_screen.dart';
import '../features/candidates/presentation/candidate_search_screen.dart';
import '../features/candidates/presentation/organization_candidate_profile_screen.dart';
import '../features/candidates/presentation/organization_recommended_candidates_screen.dart';
import '../features/cv/presentation/student_cv_screen.dart';
import '../features/education_verification/presentation/student_education_verification_screen.dart';
import '../features/invitations/presentation/student_invitations_screen.dart';
import '../features/messaging/presentation/conversation_list_screen.dart';
import '../features/messaging/presentation/conversation_screen.dart';
import '../features/organization_profile/presentation/company_profile_screen.dart';
import '../features/organization_profile/presentation/organization_profile_edit_screen.dart';
import '../features/skills/presentation/student_skills_screen.dart';
import '../features/opportunities/presentation/opportunity_form_screen.dart';
import '../features/opportunities/presentation/organization_opportunities_screen.dart';
import '../features/opportunities/presentation/organization_opportunity_details_screen.dart';
import '../features/opportunities/presentation/student_opportunities_screen.dart';
import '../features/opportunities/presentation/student_opportunity_details_screen.dart';
import '../features/notifications/presentation/notification_screen.dart';
import '../features/organization/presentation/organization_home_screen.dart';
import '../features/student/presentation/student_home_screen.dart';
import '../features/student/presentation/student_profile_edit_screen.dart';
import '../features/student/presentation/student_profile_screen.dart';
import '../providers/auth_provider.dart';
import '../providers/organization_profile_provider.dart';
import '../providers/student_profile_provider.dart';
import 'app_routes.dart';

const _splashPath = '/splash';
const _loginPath = AppRoutes.login;
const _studentPath = AppRoutes.studentHome;
const _organizationPath = AppRoutes.organizationHome;
const _adminPath = '/admin';

/// Admin-only feature area — not onboarding, but off-limits to every
/// other role. Matched by prefix (not just the exact `_adminPath` the
/// [_isHomePath] check already covers) so sub-routes like
/// [AppRoutes.adminUsers] are protected too, the same pattern already
/// applied to every other role-scoped feature area below.
const _adminPathPrefix = _adminPath;

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
  // Phase 8B-2: reachable while unauthenticated (a user recovering a
  // forgotten password isn't signed in), and deliberately never added to
  // any "authenticated user must leave" redirect set below either — an
  // already-authenticated session (e.g. a stale tab) must not be bounced
  // away from a reset/verification link it just opened.
  AppRoutes.forgotPassword,
  AppRoutes.resetPassword,
  AppRoutes.emailVerified,
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

/// Student opportunity browsing — a protected feature area, not onboarding.
/// Matched by prefix for the same reason as
/// [_organizationOpportunitiesPathPrefix].
const _studentOpportunitiesPathPrefix = AppRoutes.studentOpportunities;

/// Student CV management — a protected feature area, not onboarding.
/// Matched by prefix for consistency with the other feature areas, even
/// though this one currently has no dynamic `:id` sub-routes.
const _studentCvsPathPrefix = AppRoutes.studentCvs;

/// Student application management — a protected feature area, not
/// onboarding. Matched by prefix for the same reason as
/// [_studentOpportunitiesPathPrefix].
const _studentApplicationsPathPrefix = AppRoutes.studentApplications;

/// Organization application management — a protected feature area, not
/// onboarding. The applicants-list route
/// (`/organization/opportunities/:id/applicants`) is already covered by
/// [_organizationOpportunitiesPathPrefix]; this prefix additionally covers
/// the standalone `/organization/applications/:id` details route.
const _organizationApplicationsPathPrefix = AppRoutes.organizationApplications;

/// Organization Quiz editor — a protected feature area, not onboarding.
/// A separate prefix from [_organizationApplicationsPathPrefix] because
/// these routes are addressed by Assessment ID
/// (`AppRoutes.organizationAssessments`), not Application ID.
const _organizationAssessmentsPathPrefix = AppRoutes.organizationAssessments;

/// Student Quiz taking — a protected feature area, not onboarding. A
/// separate prefix from [_studentApplicationsPathPrefix] because these
/// routes are addressed by Assessment ID ([AppRoutes.studentAssessments]),
/// not Application ID — mirrors [_organizationAssessmentsPathPrefix] for
/// the same reason.
const _studentAssessmentsPathPrefix = AppRoutes.studentAssessments;

/// Student education-verification submission/status (Phase 8B-1) — a
/// protected feature area, not onboarding. Matched by prefix for
/// consistency with the other feature areas above, even though this one
/// currently has no dynamic `:id` sub-routes.
const _studentEducationVerificationPathPrefix =
    AppRoutes.studentEducationVerification;

/// Organization-only Candidate Search (Phase 8B-3, Flow B) — a protected
/// feature area, not onboarding. Matched by prefix for consistency with
/// the other feature areas above, even though this one currently has no
/// dynamic `:id` sub-routes.
const _organizationCandidatesPathPrefix = AppRoutes.organizationCandidates;

/// Student-only received invitations (Phase 8B-3, Flow B) — a protected
/// feature area, not onboarding. Matched by prefix for consistency with
/// the other feature areas above, even though this one currently has no
/// dynamic `:id` sub-routes.
const _studentInvitationsPathPrefix = AppRoutes.studentInvitations;

/// UI Phase 1.2 — the minimal Student Profile shell exposing account-level
/// destinations. A protected feature area, not onboarding. Matched by
/// prefix for consistency with the other feature areas above, even though
/// this one currently has no dynamic `:id` sub-routes.
const _studentProfilePathPrefix = AppRoutes.studentProfile;

/// Messaging MVP — Student-only conversation list/detail. A protected
/// feature area, not onboarding. Matched by prefix since
/// [AppRoutes.studentConversation] carries a dynamic `:id` segment.
const _studentMessagesPathPrefix = AppRoutes.studentMessages;

/// Messaging MVP — Organization-only conversation list/detail. Matched by
/// prefix for the same reason as [_studentMessagesPathPrefix].
const _organizationMessagesPathPrefix = AppRoutes.organizationMessages;

/// Organization Public Profile phase — the Organization's own Company
/// Profile view/edit is an organization-only feature area, not
/// onboarding. Matched by prefix so it also covers
/// [AppRoutes.organizationProfileEdit]. The public
/// `/organizations/:id` route is a *different*, unrelated prefix
/// (plural "organizations") reachable by any authenticated role, so it
/// deliberately has no guard here.
const _organizationProfilePathPrefix = AppRoutes.organizationProfile;

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
          path: AppRoutes.forgotPassword,
          builder: (_, _) => const ForgotPasswordScreen(),
        ),
        GoRoute(
          path: AppRoutes.resetPassword,
          builder: (_, state) => ResetPasswordScreen(
            token: state.uri.queryParameters['token'],
            email: state.uri.queryParameters['email'],
          ),
        ),
        GoRoute(
          path: AppRoutes.emailVerified,
          builder: (_, state) =>
              EmailVerifiedScreen(status: state.uri.queryParameters['status']),
        ),
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
        // Shared across all three roles -- deliberately not gated by any
        // role-specific prefix check in `_redirect` below, unlike every
        // other feature area. A student/organization with an incomplete
        // profile is still redirected here the same as any other protected
        // route, via the same generic `profileIncomplete` fallthrough
        // those roles' own redirect helpers already apply everywhere else.
        GoRoute(
          path: AppRoutes.notifications,
          builder: (_, _) => const NotificationScreen(),
        ),
        GoRoute(
          path: AppRoutes.adminUsers,
          builder: (_, _) => const AdminUsersScreen(),
        ),
        GoRoute(
          path: AppRoutes.adminOrganizations,
          builder: (_, _) => const AdminOrganizationsScreen(),
        ),
        GoRoute(
          path: '${AppRoutes.adminOrganizations}/:id',
          builder: (_, state) => AdminOrganizationDetailsScreen(
            organizationId: int.tryParse(state.pathParameters['id'] ?? '') ?? 0,
          ),
        ),
        GoRoute(
          path: AppRoutes.adminSkills,
          builder: (_, _) => const AdminSkillsScreen(),
        ),
        GoRoute(
          path: AppRoutes.adminEducationVerifications,
          builder: (_, _) => const AdminEducationVerificationsScreen(),
        ),
        GoRoute(
          path: AppRoutes.organizationCandidates,
          builder: (_, _) => const CandidateSearchScreen(),
        ),
        GoRoute(
          path: '${AppRoutes.organizationCandidates}/:id',
          builder: (_, state) => OrganizationCandidateProfileScreen(
            // Phase O8.1 — only ever passed by "View Profile" (Talent
            // Directory or Recommended Candidates); there is no
            // single-candidate-by-ID backend endpoint to fall back to on a
            // direct URL visit, so a missing `extra` renders the screen's
            // own graceful "not found" state instead of crashing.
            candidate: state.extra is CandidateProfileView
                ? state.extra as CandidateProfileView
                : null,
          ),
        ),
        GoRoute(
          path: AppRoutes.studentInvitations,
          builder: (_, _) => const StudentInvitationsScreen(),
        ),
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
        GoRoute(
          path: '${AppRoutes.organizationOpportunities}/:id/applicants',
          builder: (_, state) => OrganizationApplicantsScreen(
            opportunityId: int.tryParse(state.pathParameters['id'] ?? '') ?? 0,
            // Only ever available via in-app navigation (see
            // OrganizationOpportunityDetailsScreen) — a direct URL visit
            // has no `extra`, which the screen handles safely on its own.
            opportunityTitle: state.extra is String
                ? state.extra as String
                : null,
          ),
        ),
        GoRoute(
          path:
              '${AppRoutes.organizationOpportunities}/:id/recommended-candidates',
          builder: (_, state) => OrganizationRecommendedCandidatesScreen(
            opportunityId: int.tryParse(state.pathParameters['id'] ?? '') ?? 0,
            // Only ever available via in-app navigation (see
            // OrganizationOpportunityDetailsScreen) — mirrors
            // OrganizationApplicantsScreen's own `opportunityTitle` extra
            // just above.
            opportunityTitle: state.extra is String
                ? state.extra as String
                : null,
          ),
        ),
        GoRoute(
          path: '${AppRoutes.organizationApplications}/:id',
          builder: (_, state) => OrganizationApplicationDetailsScreen(
            applicationId: int.tryParse(state.pathParameters['id'] ?? '') ?? 0,
          ),
        ),
        GoRoute(
          path:
              '${AppRoutes.organizationApplications}/:id/assessment/interview',
          builder: (_, state) => ScheduleInterviewScreen(
            applicationId: int.tryParse(state.pathParameters['id'] ?? '') ?? 0,
            // Phase 10A.4A: only passed by `_QuizAssessmentSummaryCard`'s
            // "Advance to Interview" decision action — `extra` (not a path
            // param) since this is transient action state, not a
            // deep-linkable route, the same convention this file's own
            // `opportunityTitle` extra just above already uses.
            nextActionOriginAssessmentId: state.extra is int
                ? state.extra as int
                : null,
          ),
        ),
        GoRoute(
          path: '${AppRoutes.organizationApplications}/:id/assessment/quiz',
          builder: (_, state) => CreateQuizScreen(
            applicationId: int.tryParse(state.pathParameters['id'] ?? '') ?? 0,
          ),
        ),
        GoRoute(
          path: '${AppRoutes.organizationAssessments}/:id/quiz',
          builder: (_, state) => OrganizationQuizEditorScreen(
            assessmentId: int.tryParse(state.pathParameters['id'] ?? '') ?? 0,
          ),
        ),
        // Phase 10A.4B — the shared Opportunity Quiz template. Registered
        // before the read/manage route below so the more specific
        // `/quiz/new` path always wins.
        GoRoute(
          path: '${AppRoutes.organizationOpportunities}/:id/quiz/new',
          builder: (_, state) => CreateQuizScreen(
            opportunityId: int.tryParse(state.pathParameters['id'] ?? '') ?? 0,
          ),
        ),
        GoRoute(
          path: '${AppRoutes.organizationOpportunities}/:id/quiz',
          builder: (_, state) => OrganizationQuizEditorScreen(
            opportunityId: int.tryParse(state.pathParameters['id'] ?? '') ?? 0,
          ),
        ),
        GoRoute(
          path: '${AppRoutes.organizationOpportunities}/:id/quiz/results',
          builder: (_, state) => OrganizationQuizResultsScreen(
            opportunityId: int.tryParse(state.pathParameters['id'] ?? '') ?? 0,
          ),
        ),
        GoRoute(
          path: AppRoutes.studentOpportunities,
          builder: (_, _) => const StudentOpportunitiesScreen(),
        ),
        GoRoute(
          path: '${AppRoutes.studentOpportunities}/:id',
          builder: (_, state) => StudentOpportunityDetailsScreen(
            opportunityId: int.tryParse(state.pathParameters['id'] ?? '') ?? 0,
          ),
        ),
        GoRoute(
          path: AppRoutes.studentCvs,
          builder: (_, _) => const StudentCvScreen(),
        ),
        GoRoute(
          path: AppRoutes.studentSkills,
          builder: (_, _) => const StudentSkillsScreen(),
        ),
        GoRoute(
          path: AppRoutes.studentApplications,
          builder: (_, _) => const StudentApplicationsScreen(),
        ),
        GoRoute(
          path: '${AppRoutes.studentApplications}/:id',
          builder: (_, state) => StudentApplicationDetailsScreen(
            applicationId: int.tryParse(state.pathParameters['id'] ?? '') ?? 0,
          ),
        ),
        GoRoute(
          path: '${AppRoutes.studentAssessments}/:id/quiz',
          builder: (_, state) => StudentQuizScreen(
            assessmentId: int.tryParse(state.pathParameters['id'] ?? '') ?? 0,
          ),
        ),
        GoRoute(
          path: AppRoutes.studentEducationVerification,
          builder: (_, _) => const StudentEducationVerificationScreen(),
        ),
        GoRoute(
          path: AppRoutes.studentProfile,
          builder: (_, _) => const StudentProfileScreen(),
        ),
        GoRoute(
          path: AppRoutes.studentProfileEdit,
          builder: (_, _) => const StudentProfileEditScreen(),
        ),
        // Messaging MVP — role-gated the same way every other protected
        // feature area above is (see the `_redirect` guards near
        // `_studentMessagesPathPrefix`/`_organizationMessagesPathPrefix`).
        GoRoute(
          path: AppRoutes.studentMessages,
          builder: (_, _) => const StudentMessagesScreen(),
        ),
        GoRoute(
          path: '${AppRoutes.studentMessages}/:id',
          builder: (_, state) => ConversationScreen(
            conversationId: int.tryParse(state.pathParameters['id'] ?? '') ?? 0,
          ),
        ),
        GoRoute(
          path: AppRoutes.organizationMessages,
          builder: (_, _) => const OrganizationMessagesScreen(),
        ),
        GoRoute(
          path: '${AppRoutes.organizationMessages}/:id',
          builder: (_, state) => ConversationScreen(
            conversationId: int.tryParse(state.pathParameters['id'] ?? '') ?? 0,
          ),
        ),
        // Organization Public Profile phase — the owner's own Company
        // Profile (organization-only, see the `_organizationProfilePathPrefix`
        // guard) plus its Edit screen.
        GoRoute(
          path: AppRoutes.organizationProfile,
          builder: (_, _) => const OrganizationOwnProfileScreen(),
        ),
        GoRoute(
          path: AppRoutes.organizationProfileEdit,
          builder: (_, _) => const OrganizationProfileEditScreen(),
        ),
        // The public, read-only Company Profile for any organization by
        // ID -- reachable by any authenticated role (no extra role guard
        // below), same as `/notifications`.
        GoRoute(
          path: '/organizations/:id',
          builder: (_, state) => CompanyProfileScreen(
            organizationId: int.tryParse(state.pathParameters['id'] ?? '') ?? 0,
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
    // onboarding, but still off-limits to every other role. This also
    // covers the applicants-list route
    // (/organization/opportunities/:id/applicants), which shares this
    // prefix.
    if (role != 'organization' &&
        currentPath.startsWith(_organizationOpportunitiesPathPrefix)) {
      return homePath;
    }

    // Application management is an organization-only feature area — not
    // onboarding, but still off-limits to every other role.
    if (role != 'organization' &&
        currentPath.startsWith(_organizationApplicationsPathPrefix)) {
      return homePath;
    }

    // The Quiz editor (Assessment-ID-addressed routes) is an
    // organization-only feature area — not onboarding, but still
    // off-limits to every other role.
    if (role != 'organization' &&
        currentPath.startsWith(_organizationAssessmentsPathPrefix)) {
      return homePath;
    }

    // Admin management screens (Users, and later Organizations/Skills) —
    // not onboarding, but still off-limits to every other role. The exact
    // `_adminPath` match is already covered by the `_isHomePath` check
    // above; this additionally covers its sub-routes.
    if (role != 'admin' && currentPath.startsWith(_adminPathPrefix)) {
      return homePath;
    }

    // Opportunity browsing is a student-only feature area — not
    // onboarding, but still off-limits to every other role.
    if (role != 'student' &&
        currentPath.startsWith(_studentOpportunitiesPathPrefix)) {
      return homePath;
    }

    // CV management is a student-only feature area — not onboarding, but
    // still off-limits to every other role.
    if (role != 'student' && currentPath.startsWith(_studentCvsPathPrefix)) {
      return homePath;
    }

    // Application management is a student-only feature area — not
    // onboarding, but still off-limits to every other role.
    if (role != 'student' &&
        currentPath.startsWith(_studentApplicationsPathPrefix)) {
      return homePath;
    }

    // Quiz taking (Assessment-ID-addressed routes) is a student-only
    // feature area — not onboarding, but still off-limits to every other
    // role.
    if (role != 'student' &&
        currentPath.startsWith(_studentAssessmentsPathPrefix)) {
      return homePath;
    }

    // Education verification is a student-only feature area — not
    // onboarding, but still off-limits to every other role.
    if (role != 'student' &&
        currentPath.startsWith(_studentEducationVerificationPathPrefix)) {
      return homePath;
    }

    // Candidate Search (Phase 8B-3) is an organization-only feature area —
    // not onboarding, but still off-limits to every other role.
    if (role != 'organization' &&
        currentPath.startsWith(_organizationCandidatesPathPrefix)) {
      return homePath;
    }

    // Received invitations (Phase 8B-3) is a student-only feature area —
    // not onboarding, but still off-limits to every other role.
    if (role != 'student' &&
        currentPath.startsWith(_studentInvitationsPathPrefix)) {
      return homePath;
    }

    // The Student Profile shell (UI Phase 1.2) is a student-only feature
    // area — not onboarding, but still off-limits to every other role.
    if (role != 'student' &&
        currentPath.startsWith(_studentProfilePathPrefix)) {
      return homePath;
    }

    // Messaging MVP — Student conversations are a student-only feature
    // area, not onboarding, but still off-limits to every other role.
    if (role != 'student' &&
        currentPath.startsWith(_studentMessagesPathPrefix)) {
      return homePath;
    }

    // Messaging MVP — Organization conversations are an organization-only
    // feature area, not onboarding, but still off-limits to every other
    // role.
    if (role != 'organization' &&
        currentPath.startsWith(_organizationMessagesPathPrefix)) {
      return homePath;
    }

    // Organization Public Profile phase — the owner's own Company
    // Profile view/edit is an organization-only feature area, not
    // onboarding. The public `/organizations/:id` route is intentionally
    // NOT guarded here (reachable by any authenticated role).
    if (role != 'organization' &&
        currentPath.startsWith(_organizationProfilePathPrefix)) {
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
