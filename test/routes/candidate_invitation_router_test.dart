// Router-level tests for the Phase 8B-3 Candidate Search
// (`/organization/candidates`, organization-only) and received-invitations
// (`/student/invitations`, student-only) routes: role guards and
// unauthenticated redirects. Mirrors the conventions already used
// throughout the other `test/routes/*_router_test.dart` files.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:opportunityhub_flutter/core/api/api_client.dart';
import 'package:opportunityhub_flutter/core/api/paginated_result.dart';
import 'package:opportunityhub_flutter/core/storage/token_storage_service.dart';
import 'package:opportunityhub_flutter/core/theme/app_theme.dart';
import 'package:opportunityhub_flutter/features/admin/data/admin_dashboard_repository.dart';
import 'package:opportunityhub_flutter/features/applications/data/application_repository.dart';
import 'package:opportunityhub_flutter/features/auth/data/auth_repository.dart';
import 'package:opportunityhub_flutter/features/candidates/data/candidate_repository.dart';
import 'package:opportunityhub_flutter/features/cv/data/cv_repository.dart';
import 'package:opportunityhub_flutter/features/education_verification/data/education_verification_repository.dart';
import 'package:opportunityhub_flutter/features/invitations/data/invitation_repository.dart';
import 'package:opportunityhub_flutter/features/notifications/data/notification_repository.dart';
import 'package:opportunityhub_flutter/features/opportunities/data/opportunity_repository.dart';
import 'package:opportunityhub_flutter/features/organization/data/organization_profile_repository.dart';
import 'package:opportunityhub_flutter/features/skills/data/student_skill_repository.dart';
import 'package:opportunityhub_flutter/features/student/data/student_profile_repository.dart';
import 'package:opportunityhub_flutter/models/admin_dashboard_stats_model.dart';
import 'package:opportunityhub_flutter/models/application_model.dart';
import 'package:opportunityhub_flutter/models/candidate_model.dart';
import 'package:opportunityhub_flutter/models/cv_model.dart';
import 'package:opportunityhub_flutter/models/education_verification_model.dart';
import 'package:opportunityhub_flutter/models/invitation_model.dart';
import 'package:opportunityhub_flutter/models/notification_model.dart';
import 'package:opportunityhub_flutter/models/opportunity_model.dart';
import 'package:opportunityhub_flutter/models/organization_profile_model.dart';
import 'package:opportunityhub_flutter/models/student_profile_model.dart';
import 'package:opportunityhub_flutter/models/student_skill_model.dart';
import 'package:opportunityhub_flutter/models/user_model.dart';
import 'package:opportunityhub_flutter/providers/admin_dashboard_provider.dart';
import 'package:opportunityhub_flutter/providers/auth_provider.dart';
import 'package:opportunityhub_flutter/providers/candidate_search_provider.dart';
import 'package:opportunityhub_flutter/providers/notification_provider.dart';
import 'package:opportunityhub_flutter/providers/organization_opportunities_provider.dart';
import 'package:opportunityhub_flutter/providers/organization_profile_provider.dart';
import 'package:opportunityhub_flutter/providers/student_applications_provider.dart';
import 'package:opportunityhub_flutter/providers/student_cv_provider.dart';
import 'package:opportunityhub_flutter/providers/student_education_verification_provider.dart';
import 'package:opportunityhub_flutter/providers/student_invitations_provider.dart';
import 'package:opportunityhub_flutter/providers/student_opportunities_provider.dart';
import 'package:opportunityhub_flutter/providers/student_profile_provider.dart';
import 'package:opportunityhub_flutter/providers/student_skill_provider.dart';
import 'package:opportunityhub_flutter/routes/app_router.dart';
import 'package:opportunityhub_flutter/routes/app_routes.dart';
import 'package:opportunityhub_flutter/providers/theme_provider.dart';

class _FakeAuthRepository extends AuthRepository {
  _FakeAuthRepository({this.savedToken, this.currentUser})
    : super(
        apiClient: ApiClient(tokenStorageService: TokenStorageService()),
        tokenStorageService: TokenStorageService(),
      );

  String? savedToken;
  UserModel? currentUser;

  @override
  Future<String?> getSavedToken() async => savedToken;

  @override
  Future<UserModel> getCurrentUser() async => currentUser!;
}

class _FakeStudentProfileRepository extends StudentProfileRepository {
  _FakeStudentProfileRepository({this.getProfileResult})
    : super(apiClient: ApiClient(tokenStorageService: TokenStorageService()));

  StudentProfileModel? getProfileResult;

  @override
  Future<StudentProfileModel?> getProfile() async => getProfileResult;
}

class _FakeOrganizationProfileRepository extends OrganizationProfileRepository {
  _FakeOrganizationProfileRepository({this.getProfileResult})
    : super(apiClient: ApiClient(tokenStorageService: TokenStorageService()));

  OrganizationProfileModel? getProfileResult;

  @override
  Future<OrganizationProfileModel?> getProfile() async => getProfileResult;
}

class _FakeCandidateRepository extends CandidateRepository {
  _FakeCandidateRepository()
    : super(apiClient: ApiClient(tokenStorageService: TokenStorageService()));

  @override
  Future<List<CandidateModel>> searchCandidates({
    String? name,
    String? major,
    String? university,
    int? graduationYear,
    String? skill,
    int? opportunityId,
  }) async => [];
}

class _FakeInvitationRepository extends InvitationRepository {
  _FakeInvitationRepository()
    : super(apiClient: ApiClient(tokenStorageService: TokenStorageService()));

  @override
  Future<List<InvitationModel>> getInvitations() async => [];
}

class _FakeOpportunityRepository extends OpportunityRepository {
  _FakeOpportunityRepository()
    : super(apiClient: ApiClient(tokenStorageService: TokenStorageService()));
}

/// AdminHomeScreen/StudentHomeScreen/OrganizationHomeScreen all now render
/// a NotificationBellAction unconditionally, and AdminHomeScreen also
/// requires AdminDashboardProvider directly — not exercised by these
/// candidate/invitation guard tests, but must exist in the tree so a
/// denied user redirected to their Home screen doesn't throw a
/// ProviderNotFoundError. Mirrors the identical fakes/reasoning already
/// used in `student_cvs_router_test.dart`.
class _FakeAdminDashboardRepository extends AdminDashboardRepository {
  _FakeAdminDashboardRepository()
    : super(apiClient: ApiClient(tokenStorageService: TokenStorageService()));

  @override
  Future<AdminDashboardStatsModel> getDashboardStats() async {
    throw ApiException('Not used in these router tests');
  }
}

class _FakeNotificationRepository extends NotificationRepository {
  _FakeNotificationRepository()
    : super(apiClient: ApiClient(tokenStorageService: TokenStorageService()));

  @override
  Future<List<NotificationModel>> getNotifications() async => [];
}

/// StudentHomeScreen now reads these 5 providers unconditionally in
/// initState — required whenever a denied user is redirected there.
class _FakeStudentApplicationRepository extends ApplicationRepository {
  _FakeStudentApplicationRepository()
    : super(apiClient: ApiClient(tokenStorageService: TokenStorageService()));

  @override
  Future<List<ApplicationModel>> getStudentApplications() async => [];
}

class _FakeStudentOpportunityRepository extends OpportunityRepository {
  _FakeStudentOpportunityRepository()
    : super(apiClient: ApiClient(tokenStorageService: TokenStorageService()));

  @override
  Future<PaginatedResult<OpportunityModel>> getPublicOpportunities({
    String? opportunityType,
    String? employmentType,
    String? workMode,
    String? experienceLevel,
    String? location,
    String? fieldOfStudy,
    String? keyword,
    int page = 1,
    int perPage = 15,
  }) async {
    return const PaginatedResult(items: [], currentPage: 1, lastPage: 1, total: 0);
  }
}

class _FakeCvRepository extends CvRepository {
  _FakeCvRepository()
    : super(apiClient: ApiClient(tokenStorageService: TokenStorageService()));

  @override
  Future<List<CvModel>> getStudentCvs() async => [];
}

class _FakeStudentSkillRepository extends StudentSkillRepository {
  _FakeStudentSkillRepository()
    : super(apiClient: ApiClient(tokenStorageService: TokenStorageService()));

  @override
  Future<List<StudentSkillModel>> getStudentSkills() async => [];
}

class _FakeEducationVerificationRepository
    extends EducationVerificationRepository {
  _FakeEducationVerificationRepository()
    : super(apiClient: ApiClient(tokenStorageService: TokenStorageService()));

  @override
  Future<EducationVerificationModel> getStatus() async =>
      const EducationVerificationModel(
        institutionName: null,
        degreeOrProgram: null,
        status: 'not_submitted',
      );
}

void _setViewSize(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

/// Pumps the full app, authenticated as [role] with a saved token, and
/// navigates straight to [initialPath]. Mirrors the identical helper
/// already used across the other `test/routes/*_router_test.dart` files.
Future<void> _pumpAsRole(
  WidgetTester tester, {
  required String role,
  required String initialPath,
}) async {
  _setViewSize(tester, const Size(420, 1400));

  final authProvider = AuthProvider(
    authRepository: _FakeAuthRepository(
      savedToken: 'saved-token',
      currentUser: UserModel(
        id: 1,
        name: 'Test User',
        email: 'test@example.com',
        role: role,
        status: 'active',
      ),
    ),
  );
  final studentProfileProvider = StudentProfileProvider(
    repository: _FakeStudentProfileRepository(
      getProfileResult: role == 'student'
          ? const StudentProfileModel(
              id: 1,
              university: 'State University',
              major: 'Computer Science',
              graduationYear: 2027,
            )
          : null,
    ),
    authProvider: authProvider,
  );
  const approvedOrgProfile = OrganizationProfileModel(
    id: 1,
    organizationName: 'Acme Corp',
    organizationType: 'company',
    approvalStatus: 'approved',
  );
  final organizationProfileProvider = OrganizationProfileProvider(
    repository: _FakeOrganizationProfileRepository(
      getProfileResult: role == 'organization' ? approvedOrgProfile : null,
    ),
    authProvider: authProvider,
  );
  final candidateProvider = CandidateSearchProvider(
    repository: _FakeCandidateRepository(),
    invitationRepository: _FakeInvitationRepository(),
    authProvider: authProvider,
  );
  final invitationsProvider = StudentInvitationsProvider(
    repository: _FakeInvitationRepository(),
    authProvider: authProvider,
  );
  final opportunitiesProvider = OrganizationOpportunitiesProvider(
    repository: _FakeOpportunityRepository(),
    authProvider: authProvider,
  );
  final adminDashboardProvider = AdminDashboardProvider(
    repository: _FakeAdminDashboardRepository(),
    authProvider: authProvider,
  );
  final notificationProvider = NotificationProvider(
    repository: _FakeNotificationRepository(),
    authProvider: authProvider,
  );
  final studentApplicationsProvider = StudentApplicationsProvider(
    repository: _FakeStudentApplicationRepository(),
    authProvider: authProvider,
  );
  final studentOpportunitiesProvider = StudentOpportunitiesProvider(
    repository: _FakeStudentOpportunityRepository(),
    authProvider: authProvider,
  );
  final studentCvProvider = StudentCvProvider(
    repository: _FakeCvRepository(),
    studentSkillRepository: _FakeStudentSkillRepository(),
    authProvider: authProvider,
  );
  final studentSkillProvider = StudentSkillProvider(
    repository: _FakeStudentSkillRepository(),
    authProvider: authProvider,
  );
  final studentEducationVerificationProvider =
      StudentEducationVerificationProvider(
        repository: _FakeEducationVerificationRepository(),
        authProvider: authProvider,
      );
  final appRouter = AppRouter(
    authProvider,
    studentProfileProvider,
    organizationProfileProvider,
  );

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthProvider>.value(value: authProvider),
        ChangeNotifierProvider<StudentProfileProvider>.value(
          value: studentProfileProvider,
        ),
        ChangeNotifierProvider<OrganizationProfileProvider>.value(
          value: organizationProfileProvider,
        ),
        ChangeNotifierProvider<CandidateSearchProvider>.value(
          value: candidateProvider,
        ),
        ChangeNotifierProvider<StudentInvitationsProvider>.value(
          value: invitationsProvider,
        ),
        ChangeNotifierProvider<OrganizationOpportunitiesProvider>.value(
          value: opportunitiesProvider,
        ),
        ChangeNotifierProvider<AdminDashboardProvider>.value(
          value: adminDashboardProvider,
        ),
        ChangeNotifierProvider<NotificationProvider>.value(
          value: notificationProvider,
        ),
        ChangeNotifierProvider<ThemeProvider>.value(value: ThemeProvider()),
        ChangeNotifierProvider<StudentApplicationsProvider>.value(
          value: studentApplicationsProvider,
        ),
        ChangeNotifierProvider<StudentOpportunitiesProvider>.value(
          value: studentOpportunitiesProvider,
        ),
        ChangeNotifierProvider<StudentCvProvider>.value(
          value: studentCvProvider,
        ),
        ChangeNotifierProvider<StudentSkillProvider>.value(
          value: studentSkillProvider,
        ),
        ChangeNotifierProvider<StudentEducationVerificationProvider>.value(
          value: studentEducationVerificationProvider,
        ),
      ],
      child: MaterialApp.router(
        theme: AppTheme.lightTheme,
        routerConfig: appRouter.router,
      ),
    ),
  );

  appRouter.router.go(initialPath);
  await authProvider.initialize();
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'An unauthenticated guest visiting Candidate Search is redirected to login',
    (tester) async {
      _setViewSize(tester, const Size(420, 1400));

      final authProvider = AuthProvider(
        authRepository: _FakeAuthRepository(),
      );
      final studentProfileProvider = StudentProfileProvider(
        repository: _FakeStudentProfileRepository(),
        authProvider: authProvider,
      );
      final organizationProfileProvider = OrganizationProfileProvider(
        repository: _FakeOrganizationProfileRepository(),
        authProvider: authProvider,
      );
      final candidateProvider = CandidateSearchProvider(
        repository: _FakeCandidateRepository(),
        invitationRepository: _FakeInvitationRepository(),
        authProvider: authProvider,
      );
      final opportunitiesProvider = OrganizationOpportunitiesProvider(
        repository: _FakeOpportunityRepository(),
        authProvider: authProvider,
      );
      final appRouter = AppRouter(
        authProvider,
        studentProfileProvider,
        organizationProfileProvider,
      );

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<AuthProvider>.value(value: authProvider),
            ChangeNotifierProvider<StudentProfileProvider>.value(
              value: studentProfileProvider,
            ),
            ChangeNotifierProvider<OrganizationProfileProvider>.value(
              value: organizationProfileProvider,
            ),
            ChangeNotifierProvider<CandidateSearchProvider>.value(
              value: candidateProvider,
            ),
            ChangeNotifierProvider<OrganizationOpportunitiesProvider>.value(
              value: opportunitiesProvider,
            ),
            ChangeNotifierProvider<ThemeProvider>.value(value: ThemeProvider()),
          ],
          child: MaterialApp.router(
            theme: AppTheme.lightTheme,
            routerConfig: appRouter.router,
          ),
        ),
      );

      appRouter.router.go(AppRoutes.organizationCandidates);
      await authProvider.initialize();
      await tester.pumpAndSettle();

      expect(find.text('Find Candidates'), findsNothing);
      expect(find.text('Login'), findsWidgets);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('A student cannot open Organization Candidate Search', (
    tester,
  ) async {
    await _pumpAsRole(
      tester,
      role: 'student',
      initialPath: AppRoutes.organizationCandidates,
    );

    expect(find.text('Find Candidates'), findsNothing);
    expect(find.text("Discover Opportunities"), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('An admin cannot open Organization Candidate Search', (
    tester,
  ) async {
    await _pumpAsRole(
      tester,
      role: 'admin',
      initialPath: AppRoutes.organizationCandidates,
    );

    expect(find.text('Find Candidates'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('An organization may open its own Candidate Search', (
    tester,
  ) async {
    await _pumpAsRole(
      tester,
      role: 'organization',
      initialPath: AppRoutes.organizationCandidates,
    );

    expect(find.text('Find Candidates'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('An organization cannot open Student Invitations', (
    tester,
  ) async {
    await _pumpAsRole(
      tester,
      role: 'organization',
      initialPath: AppRoutes.studentInvitations,
    );

    expect(find.text('No Invitations Yet'), findsNothing);
    expect(find.text('Role: Organization'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('An admin cannot open Student Invitations', (tester) async {
    await _pumpAsRole(
      tester,
      role: 'admin',
      initialPath: AppRoutes.studentInvitations,
    );

    expect(find.text('No Invitations Yet'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('A student may open their own Invitations', (tester) async {
    await _pumpAsRole(
      tester,
      role: 'student',
      initialPath: AppRoutes.studentInvitations,
    );

    expect(find.text('No Invitations Yet'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('No redirect loop occurs for either route', (tester) async {
    await _pumpAsRole(
      tester,
      role: 'organization',
      initialPath: AppRoutes.organizationCandidates,
    );

    // Settling completed without a pumpAndSettle timeout.
    expect(find.text('Find Candidates'), findsOneWidget);
  });
}
