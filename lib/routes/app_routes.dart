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

  /// Phase 8B-2 password recovery — public (reachable while
  /// unauthenticated) and role-agnostic, like the backend endpoints
  /// behind them. See `AppRouter` for why an authenticated session is
  /// still allowed to open these too, unlike [login].
  static const String forgotPassword = '/forgot-password';
  static const String resetPassword = '/reset-password';

  /// Phase 8B-2 — where the backend's signed email-verification link
  /// redirects to after verifying (or rejecting) it server-side. Reads a
  /// `status` query parameter (`success`/`invalid`); see
  /// `EmailVerifiedScreen`.
  static const String emailVerified = '/email-verified';

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

  /// Shared across all three roles — the backend's own
  /// `GET/PUT /api/notifications*` endpoints are role-agnostic (see
  /// `NotificationRepository`), so there is exactly one route here, not a
  /// role-prefixed one per role like every other feature area below.
  static const String notifications = '/notifications';

  /// Admin-only dashboard home — see `AppRouter` for the role gating
  /// applied to it. Unlike the student/organization home paths, admin has
  /// no profile-completion concept.
  static const String adminHome = '/admin';

  /// Admin-only user management — see `AppRouter` for the role gating
  /// applied to it (shares the same `/admin` prefix guard as [adminHome]).
  static const String adminUsers = '$adminHome/users';

  /// Admin-only organization management — see `AppRouter` for the role
  /// gating applied to it (shares the same `/admin` prefix guard as
  /// [adminHome]).
  static const String adminOrganizations = '$adminHome/organizations';

  static String adminOrganizationDetails(int id) => '$adminOrganizations/$id';

  /// Admin-only skill management — see `AppRouter` for the role gating
  /// applied to it (shares the same `/admin` prefix guard as [adminHome]).
  /// No dedicated detail route — create/edit/delete all happen inline via
  /// dialogs on this one screen.
  static const String adminSkills = '$adminHome/skills';

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

  /// Phase O8.1 — real, eligible candidates ranked for one of the
  /// organization's own opportunities, highest match first. Nested under
  /// [organizationOpportunities] like [organizationApplicants], so it's
  /// already covered by that prefix's existing role/profile-completion
  /// gating in `AppRouter` without needing a second redirect check.
  static String organizationOpportunityRecommendedCandidates(
    int opportunityId,
  ) => '$organizationOpportunities/$opportunityId/recommended-candidates';

  /// Phase 10A.4B — the Opportunity's shared Quiz template (create/edit
  /// settings, manage questions, publish) — mirrors [organizationApplicants]'s
  /// nesting convention for an Opportunity-scoped sub-route.
  static String organizationOpportunityQuiz(int opportunityId) =>
      '$organizationOpportunities/$opportunityId/quiz';

  /// The template's own settings-creation form — a distinct route from
  /// [organizationOpportunityQuiz] (which shows the *current* state:
  /// not-configured/draft/published) the same way [organizationCreateQuiz]
  /// is distinct from the read/manage view it hands off to on success.
  static String organizationCreateQuizForOpportunity(int opportunityId) =>
      '$organizationOpportunities/$opportunityId/quiz/new';

  /// Phase 10A.4B — every candidate's score/result/decision for the
  /// Opportunity's shared Quiz.
  static String organizationOpportunityQuizResults(int opportunityId) =>
      '$organizationOpportunities/$opportunityId/quiz/results';

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

  /// Organization-only Quiz draft creation for one application's
  /// Assessment — nested under `organizationApplications` for the same
  /// reason as [organizationScheduleInterview]: no new router guard needed.
  static String organizationCreateQuiz(int applicationId) =>
      '$organizationApplications/$applicationId/assessment/quiz';

  /// Organization-only Assessment-addressed routes — currently only the
  /// Quiz editor below, reached by Assessment ID (not Application ID)
  /// because the backend's Quiz-authoring routes are themselves addressed
  /// by assessment/quiz ID, not application ID. See `AppRouter` for the
  /// role/profile-completion gating applied to this prefix.
  static const String organizationAssessments = '/organization/assessments';

  /// Organization-only Quiz question authoring/publish for one Assessment
  /// — see [organizationAssessments].
  static String organizationQuizEditor(int assessmentId) =>
      '$organizationAssessments/$assessmentId/quiz';

  /// Student-only opportunity browsing — see `AppRouter` for the
  /// role/profile-completion gating applied to these.
  static const String studentOpportunities = '/student/opportunities';

  static String studentOpportunityDetails(int id) =>
      '$studentOpportunities/$id';

  /// Student-only CV management — see `AppRouter` for the
  /// role/profile-completion gating applied to this.
  static const String studentCvs = '/student/cvs';

  /// Student-only read-only "My Skills" list (Phase 8A-6.1) — nested
  /// under [studentCvs] so it's covered by that same route's existing
  /// role/profile-completion gating in `AppRouter` without needing a
  /// second prefix/redirect check of its own.
  static const String studentSkills = '$studentCvs/skills';

  /// Student-only application management — see `AppRouter` for the
  /// role/profile-completion gating applied to these.
  static const String studentApplications = '/student/applications';

  static String studentApplicationDetails(int id) => '$studentApplications/$id';

  /// Student-only Assessment-addressed routes — currently only the Quiz
  /// taking screen below, reached by Assessment ID (not Application ID)
  /// because the backend's Student Quiz endpoints are themselves addressed
  /// by assessment/quiz ID, not application ID — mirrors
  /// [organizationAssessments] for the same reason. See `AppRouter` for the
  /// role/profile-completion gating applied to this prefix.
  static const String studentAssessments = '/student/assessments';

  /// Student-only Quiz taking for one Assessment — see [studentAssessments].
  static String studentQuiz(int assessmentId) =>
      '$studentAssessments/$assessmentId/quiz';

  /// Student-only education-verification submission/status (Phase 8B-1) —
  /// see `AppRouter` for the role/profile-completion gating applied to
  /// this. A top-level prefix of its own (not nested under [studentCvs])
  /// since this is a distinct feature area, matching the majority
  /// convention every other student area here already follows.
  static const String studentEducationVerification =
      '/student/education-verification';

  /// Admin-only education-verification review (Phase 8B-1) — see
  /// `AppRouter` for the role gating applied to it (shares the same
  /// `/admin` prefix guard as [adminHome]).
  static const String adminEducationVerifications =
      '$adminHome/education-verifications';

  /// Organization-only Talent Directory (Phase 8B-3, Flow B — renamed from
  /// "Find Candidates" in Phase O8.1 once inviting moved to Recommended
  /// Candidates) — see `AppRouter` for the role gating applied to it.
  static const String organizationCandidates = '/organization/candidates';

  /// Phase O8.1 — the read-only Organization-facing Candidate Profile,
  /// reached from "View Profile" in either the Talent Directory or
  /// Recommended Candidates. Nested under [organizationCandidates] so it's
  /// already covered by that prefix's existing gating in `AppRouter`.
  static String organizationCandidateProfile(int candidateId) =>
      '$organizationCandidates/$candidateId';

  /// Student-only received invitations (Phase 8B-3, Flow B) — see
  /// `AppRouter` for the role gating applied to it.
  static const String studentInvitations = '/student/invitations';

  /// UI Phase 1.2 — a minimal presentation shell exposing the account-level
  /// destinations (My CVs, My Skills, Education Verification, Logout) that
  /// used to live directly on Student Home/Explore, plus the avatar's
  /// navigation target in the top bar. Not a full Student Profile redesign
  /// — that follows in a later phase. See `AppRouter` for the role gating
  /// applied to it.
  static const String studentProfile = '$studentHome/profile';

  /// UI Phase 3.1 — the real Student Profile edit form (university, major,
  /// graduation year, phone, bio). Nested under [studentProfile] so it's
  /// covered by that same route's existing student-only role guard in
  /// `AppRouter`, matching how [studentSkills] shares [studentCvs]'s guard.
  static const String studentProfileEdit = '$studentProfile/edit';

  /// Messaging MVP — Student-only conversation list. A top-level prefix
  /// of its own (not nested under [studentProfile]), matching the
  /// majority convention every other student feature area here already
  /// follows.
  static const String studentMessages = '/student/messages';

  static String studentConversation(int conversationId) =>
      '$studentMessages/$conversationId';

  /// Messaging MVP — Organization-only conversation list.
  static const String organizationMessages = '/organization/messages';

  static String organizationConversation(int conversationId) =>
      '$organizationMessages/$conversationId';

  /// Organization Public Profile phase — the authenticated organization's
  /// own "Company Profile" screen (owner view: About, Company Details,
  /// Open Opportunities, Updates & Achievements, plus Edit/Create
  /// controls). See `AppRouter` for the organization-only role gating
  /// applied to this and [organizationProfileEdit].
  static const String organizationProfile = '/organization/profile';

  static const String organizationProfileEdit = '$organizationProfile/edit';

  /// Organization Public Profile phase — the read-only, public-facing
  /// Company Profile for any organization by ID. Reachable by any
  /// authenticated role (a Student reaches it from an Opportunity's
  /// company identity; an Organization can preview its own public page
  /// the same way). Deliberately a distinct top-level prefix from
  /// [organizationProfile] (no trailing "s" there vs. "organizations"
  /// here) so the two can never be confused by a `startsWith()` guard in
  /// `AppRouter`.
  static String companyProfile(int organizationId) =>
      '/organizations/$organizationId';
}
