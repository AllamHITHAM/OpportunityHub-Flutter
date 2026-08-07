/// Route path constants for screens that need to be navigated to from
/// outside [AppRouter] (e.g. from a button on another screen).
///
/// [login] is included because registration screens navigate back to it
/// directly. [studentHome]/[organizationHome]/[adminHome] are included
/// because registration navigates there directly on success, and tests
/// reference them the same way every other route constant is referenced.
/// Splash is the only route that's still purely reached through the
/// router's own redirect logic and never needs an entry here — it stays a
/// private constant inside `app_router.dart`.
class AppRoutes {
  AppRoutes._();

  static const String login = '/login';
  static const String accountTypeSelection = '/register/account-type';
  static const String studentRegistration = '/register/student';
  static const String studentProfileRegistration = '/register/student/profile';
  static const String organizationRegistration = '/register/organization';

  /// A defensive landing spot for an authenticated organization whose
  /// profile is confirmed missing. Under normal operation this can't
  /// happen — `POST /register/organization` creates the account and its
  /// profile atomically in one transaction — but the route exists so a
  /// direct visit or a future backend inconsistency has somewhere safe to
  /// go instead of crashing or looping. See `OrganizationProfileSetupScreen`.
  static const String organizationProfileRegistration =
      '/register/organization/profile';

  static const String studentHome = '/student';
  static const String organizationHome = '/organization';

  /// Admin-only dashboard home — see `AppRouter` for the role gating
  /// applied to it. Unlike the student/organization home paths, admin has
  /// no profile-completion concept and no feature-area sub-routes yet
  /// (Users/Organizations/Skills management are later phases), so this is
  /// currently the only admin route constant.
  static const String adminHome = '/admin';

  /// Organization-only opportunity management — see `AppRouter` for the
  /// role/profile-completion gating applied to all of these.
  static const String organizationOpportunities = '/organization/opportunities';
  static const String organizationOpportunityCreate =
      '$organizationOpportunities/new';

  static String organizationOpportunityDetails(int id) =>
      '$organizationOpportunities/$id';

  static String organizationOpportunityEdit(int id) =>
      '$organizationOpportunities/$id/edit';

  /// The applicants for one of the organization's own opportunities — see
  /// `AppRouter` for the role/profile-completion gating applied to this.
  static String organizationApplicants(int opportunityId) =>
      '$organizationOpportunities/$opportunityId/applicants';

  /// Organization-only application details — not nested under an
  /// opportunity path, since the backend's single-application endpoint
  /// doesn't need the opportunity ID to resolve.
  static const String organizationApplications = '/organization/applications';

  static String organizationApplicationDetails(int id) =>
      '$organizationApplications/$id';

  /// Organization-only Interview scheduling for one application's
  /// Assessment — nested under the same `organizationApplications` prefix
  /// that already gates the details route above, so no new router guard
  /// is needed.
  static String organizationScheduleInterview(int applicationId) =>
      '$organizationApplications/$applicationId/assessment/interview';

  /// Student-only opportunity browsing — see `AppRouter` for the
  /// role/profile-completion gating applied to these.
  static const String studentOpportunities = '/student/opportunities';

  static String studentOpportunityDetails(int id) =>
      '$studentOpportunities/$id';

  /// Student-only CV management — see `AppRouter` for the
  /// role/profile-completion gating applied to this.
  static const String studentCvs = '/student/cvs';

  /// Student-only application management — see `AppRouter` for the
  /// role/profile-completion gating applied to these.
  static const String studentApplications = '/student/applications';

  static String studentApplicationDetails(int id) => '$studentApplications/$id';
}
