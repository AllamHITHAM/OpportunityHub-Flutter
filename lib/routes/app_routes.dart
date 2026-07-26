/// Route path constants for screens that need to be navigated to from
/// outside [AppRouter] (e.g. from a button on another screen).
///
/// [login] is included because registration screens navigate back to it
/// directly. [studentHome]/[organizationHome] are included because
/// registration navigates there directly on success. Routes that are only
/// ever reached through the router's own redirect logic (splash and the
/// admin home screen) don't need an entry here — they stay as private
/// constants inside `app_router.dart`.
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

  /// Organization-only opportunity management — see `AppRouter` for the
  /// role/profile-completion gating applied to all of these.
  static const String organizationOpportunities = '/organization/opportunities';
  static const String organizationOpportunityCreate =
      '$organizationOpportunities/new';

  static String organizationOpportunityDetails(int id) =>
      '$organizationOpportunities/$id';

  static String organizationOpportunityEdit(int id) =>
      '$organizationOpportunities/$id/edit';

  /// Student-only opportunity browsing — see `AppRouter` for the
  /// role/profile-completion gating applied to these.
  static const String studentOpportunities = '/student/opportunities';

  static String studentOpportunityDetails(int id) =>
      '$studentOpportunities/$id';
}
