// Router-level tests for the student- and organization-onboarding redirect
// rules: profile-completion-aware routing for /register/student,
// /register/student/profile, /register/organization,
// /register/organization/profile, and their interaction with other roles.

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
import 'package:opportunityhub_flutter/features/cv/data/cv_repository.dart';
import 'package:opportunityhub_flutter/features/education_verification/data/education_verification_repository.dart';
import 'package:opportunityhub_flutter/features/locations/data/location_repository.dart';
import 'package:opportunityhub_flutter/features/messaging/data/conversation_repository.dart';
import 'package:opportunityhub_flutter/features/notifications/data/notification_repository.dart';
import 'package:opportunityhub_flutter/features/opportunities/data/opportunity_repository.dart';
import 'package:opportunityhub_flutter/features/organization/data/organization_dashboard_repository.dart';
import 'package:opportunityhub_flutter/features/organization/data/organization_profile_repository.dart';
import 'package:opportunityhub_flutter/features/organization/presentation/organization_home_screen.dart';
import 'package:opportunityhub_flutter/features/skills/data/student_skill_repository.dart';
import 'package:opportunityhub_flutter/features/student/data/student_profile_repository.dart';
import 'package:opportunityhub_flutter/models/admin_dashboard_stats_model.dart';
import 'package:opportunityhub_flutter/models/application_model.dart';
import 'package:opportunityhub_flutter/models/conversation_model.dart';
import 'package:opportunityhub_flutter/models/cv_model.dart';
import 'package:opportunityhub_flutter/models/education_verification_model.dart';
import 'package:opportunityhub_flutter/models/location_model.dart';
import 'package:opportunityhub_flutter/models/notification_model.dart';
import 'package:opportunityhub_flutter/models/opportunity_model.dart';
import 'package:opportunityhub_flutter/models/organization_dashboard_stats_model.dart';
import 'package:opportunityhub_flutter/models/organization_profile_model.dart';
import 'package:opportunityhub_flutter/models/student_profile_model.dart';
import 'package:opportunityhub_flutter/models/student_skill_model.dart';
import 'package:opportunityhub_flutter/models/user_model.dart';
import 'package:opportunityhub_flutter/providers/admin_dashboard_provider.dart';
import 'package:opportunityhub_flutter/providers/auth_provider.dart';
import 'package:opportunityhub_flutter/providers/conversations_provider.dart';
import 'package:opportunityhub_flutter/providers/location_catalog_provider.dart';
import 'package:opportunityhub_flutter/providers/notification_provider.dart';
import 'package:opportunityhub_flutter/providers/organization_dashboard_provider.dart';
import 'package:opportunityhub_flutter/providers/organization_profile_provider.dart';
import 'package:opportunityhub_flutter/providers/student_applications_provider.dart';
import 'package:opportunityhub_flutter/providers/student_cv_provider.dart';
import 'package:opportunityhub_flutter/providers/student_education_verification_provider.dart';
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

  @override
  Future<void> logout() async {}
}

class _FakeStudentProfileRepository extends StudentProfileRepository {
  _FakeStudentProfileRepository({this.getProfileResult, this.getProfileError})
    : super(apiClient: ApiClient(tokenStorageService: TokenStorageService()));

  StudentProfileModel? getProfileResult;
  ApiException? getProfileError;
  int getProfileCallCount = 0;

  @override
  Future<StudentProfileModel?> getProfile() async {
    getProfileCallCount++;
    if (getProfileError != null) throw getProfileError!;
    return getProfileResult;
  }
}

class _FakeOrganizationProfileRepository extends OrganizationProfileRepository {
  _FakeOrganizationProfileRepository({
    this.getProfileResult,
    this.getProfileError,
  }) : super(apiClient: ApiClient(tokenStorageService: TokenStorageService()));

  OrganizationProfileModel? getProfileResult;
  ApiException? getProfileError;
  int getProfileCallCount = 0;

  @override
  Future<OrganizationProfileModel?> getProfile() async {
    getProfileCallCount++;
    if (getProfileError != null) throw getProfileError!;
    return getProfileResult;
  }
}

class _FakeAdminDashboardRepository extends AdminDashboardRepository {
  _FakeAdminDashboardRepository()
    : super(apiClient: ApiClient(tokenStorageService: TokenStorageService()));

  @override
  Future<AdminDashboardStatsModel> getDashboardStats() async {
    throw ApiException('Not used in these router tests');
  }
}

class _FakeOrganizationDashboardRepository
    extends OrganizationDashboardRepository {
  _FakeOrganizationDashboardRepository()
    : super(apiClient: ApiClient(tokenStorageService: TokenStorageService()));

  @override
  Future<OrganizationDashboardStatsModel> getDashboardStats() async {
    throw ApiException('Not used in these router tests');
  }
}

class _FakeNotificationRepository extends NotificationRepository {
  _FakeNotificationRepository()
    : super(apiClient: ApiClient(tokenStorageService: TokenStorageService()));

  @override
  Future<List<NotificationModel>> getNotifications() async => [];
}

class _FakeConversationRepository extends ConversationRepository {
  _FakeConversationRepository()
    : super(apiClient: ApiClient(tokenStorageService: TokenStorageService()));

  @override
  Future<List<ConversationSummaryModel>> getConversations() async => [];
}

class _FakeApplicationRepository extends ApplicationRepository {
  _FakeApplicationRepository()
    : super(apiClient: ApiClient(tokenStorageService: TokenStorageService()));

  @override
  Future<List<ApplicationModel>> getStudentApplications() async => [];
}

class _FakeOpportunityRepository extends OpportunityRepository {
  _FakeOpportunityRepository()
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
    int? organizationId,
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

/// A fake repository that never touches the network — unused by this
/// file's tests, but Student Profile Setup (reached when an incomplete
/// profile redirects there) reads LocationCatalogProvider unconditionally.
class _FakeLocationRepository extends LocationRepository {
  _FakeLocationRepository()
    : super(apiClient: ApiClient(tokenStorageService: TokenStorageService()));

  @override
  Future<List<LocationModel>> getLocations() async => [];
}

void _setViewSize(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

/// Pumps the app already authenticated as [role] and navigates straight to
/// [initialPath], simulating a returning user (saved token) rather than a
/// fresh login.
Future<
  (
    AuthProvider,
    AppRouter,
    _FakeStudentProfileRepository,
    _FakeOrganizationProfileRepository,
  )
>
_pumpAsRole(
  WidgetTester tester, {
  required String role,
  required String initialPath,
  StudentProfileModel? existingStudentProfile,
  ApiException? studentProfileCheckError,
  OrganizationProfileModel? existingOrganizationProfile,
  ApiException? organizationProfileCheckError,
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
  final studentRepository = _FakeStudentProfileRepository(
    getProfileResult: existingStudentProfile,
    getProfileError: studentProfileCheckError,
  );
  final studentProfileProvider = StudentProfileProvider(
    repository: studentRepository,
    authProvider: authProvider,
  );
  final organizationRepository = _FakeOrganizationProfileRepository(
    getProfileResult: existingOrganizationProfile,
    getProfileError: organizationProfileCheckError,
  );
  final organizationProfileProvider = OrganizationProfileProvider(
    repository: organizationRepository,
    authProvider: authProvider,
  );
  // Not exercised by most tests in this file, but registered because a
  // role='admin' request for a non-admin route (see the "Authenticated
  // admin user cannot enter..." tests below) redirects to AdminHomeScreen,
  // which now requires this provider to exist in the tree.
  final adminDashboardProvider = AdminDashboardProvider(
    repository: _FakeAdminDashboardRepository(),
    authProvider: authProvider,
  );
  // Not exercised by most tests in this file either, but registered for
  // the same reason as AdminDashboardProvider above: OrganizationHomeScreen
  // now reads this provider unconditionally in initState.
  final organizationDashboardProvider = OrganizationDashboardProvider(
    repository: _FakeOrganizationDashboardRepository(),
    authProvider: authProvider,
  );
  // See the AdminDashboardProvider comment above — the same reasoning
  // applies here, since AdminHomeScreen and the Student/Organization Home
  // screens all now render a NotificationBellAction unconditionally.
  final notificationProvider = NotificationProvider(
    repository: _FakeNotificationRepository(),
    authProvider: authProvider,
  );
  // Same reasoning as NotificationProvider above — MessagesBellAction now
  // renders unconditionally next to NotificationBellAction on Student/
  // Organization Home.
  final conversationsProvider = ConversationsProvider(
    repository: _FakeConversationRepository(),
    authProvider: authProvider,
  );
  // See the AdminDashboardProvider/NotificationProvider comments above —
  // the same reasoning applies: StudentHomeScreen now reads these 5
  // providers unconditionally in initState.
  final studentApplicationsProvider = StudentApplicationsProvider(
    repository: _FakeApplicationRepository(),
    authProvider: authProvider,
  );
  final studentOpportunitiesProvider = StudentOpportunitiesProvider(
    repository: _FakeOpportunityRepository(),
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
        ChangeNotifierProvider<AdminDashboardProvider>.value(
          value: adminDashboardProvider,
        ),
        ChangeNotifierProvider<OrganizationDashboardProvider>.value(
          value: organizationDashboardProvider,
        ),
        ChangeNotifierProvider<NotificationProvider>.value(
          value: notificationProvider,
        ),
        ChangeNotifierProvider<ConversationsProvider>.value(
          value: conversationsProvider,
        ),
        ChangeNotifierProvider<LocationCatalogProvider>(
          create: (_) =>
              LocationCatalogProvider(repository: _FakeLocationRepository()),
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

  return (authProvider, appRouter, studentRepository, organizationRepository);
}

void main() {
  testWidgets(
    'Authenticated organization user cannot enter student Step 1 or Step 2',
    (tester) async {
      await _pumpAsRole(
        tester,
        role: 'organization',
        initialPath: AppRoutes.studentRegistration,
        existingOrganizationProfile: const OrganizationProfileModel(
          id: 1,
          organizationName: 'Acme Corp',
          organizationType: 'company',
          approvalStatus: 'pending',
        ),
      );

      expect(find.text('Create Student Account'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Authenticated admin user cannot enter student profile completion',
    (tester) async {
      await _pumpAsRole(
        tester,
        role: 'admin',
        initialPath: AppRoutes.studentProfileRegistration,
      );

      expect(find.text('Complete Your Student Profile'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'A student whose profile check fails (unknown status) is not trapped in a redirect loop',
    (tester) async {
      final (_, _, studentRepository, _) = await _pumpAsRole(
        tester,
        role: 'student',
        initialPath: AppRoutes.studentHome,
        studentProfileCheckError: ApiException(
          'Server error, please try again later.',
        ),
      );

      // The check was attempted, failed, and the router did not force any
      // further redirect based on a guess — the student lands on whatever
      // was actually requested rather than bouncing indefinitely.
      expect(studentRepository.getProfileCallCount, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'A student with a confirmed-complete profile visiting Step 1 is sent home, not shown the form',
    (tester) async {
      await _pumpAsRole(
        tester,
        role: 'student',
        initialPath: AppRoutes.studentRegistration,
        existingStudentProfile: const StudentProfileModel(
          id: 1,
          university: 'State University',
          major: 'Computer Science',
          graduationYear: 2027,
        ),
      );

      expect(find.text("Discover Opportunities"), findsOneWidget);
      expect(find.text('Create Student Account'), findsNothing);
    },
  );

  testWidgets(
    'A student with a confirmed-incomplete profile visiting Student Home is sent to Step 2',
    (tester) async {
      await _pumpAsRole(
        tester,
        role: 'student',
        initialPath: AppRoutes.studentHome,
        existingStudentProfile: null,
      );

      expect(find.text('Complete Your Student Profile'), findsOneWidget);
      expect(find.text("Discover Opportunities"), findsNothing);
    },
  );

  // ---------------------------------------------------------------------
  // Organization onboarding routing
  // ---------------------------------------------------------------------

  testWidgets('Authenticated student user cannot enter company registration', (
    tester,
  ) async {
    await _pumpAsRole(
      tester,
      role: 'student',
      initialPath: AppRoutes.organizationRegistration,
      existingStudentProfile: const StudentProfileModel(
        id: 1,
        university: 'State University',
        major: 'Computer Science',
        graduationYear: 2027,
      ),
    );

    expect(find.text('Create Company Account'), findsNothing);
    expect(find.text("Discover Opportunities"), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Authenticated admin user cannot enter company profile setup', (
    tester,
  ) async {
    await _pumpAsRole(
      tester,
      role: 'admin',
      initialPath: AppRoutes.organizationProfileRegistration,
    );

    expect(find.text('Company Profile Setup Incomplete'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'An organization with a confirmed profile visiting registration is sent home, not shown the form',
    (tester) async {
      await _pumpAsRole(
        tester,
        role: 'organization',
        initialPath: AppRoutes.organizationRegistration,
        existingOrganizationProfile: const OrganizationProfileModel(
          id: 1,
          organizationName: 'Acme Corp',
          organizationType: 'company',
          approvalStatus: 'pending',
        ),
      );

      expect(find.byType(OrganizationHomeScreen), findsOneWidget);
      expect(find.text('Create Company Account'), findsNothing);
    },
  );

  testWidgets(
    'An organization with a confirmed profile opening Organization Home stays there',
    (tester) async {
      await _pumpAsRole(
        tester,
        role: 'organization',
        initialPath: AppRoutes.organizationHome,
        existingOrganizationProfile: const OrganizationProfileModel(
          id: 1,
          organizationName: 'Acme Corp',
          organizationType: 'company',
          approvalStatus: 'pending',
        ),
      );

      expect(find.byType(OrganizationHomeScreen), findsOneWidget);
    },
  );

  testWidgets(
    'An organization with a confirmed-missing profile visiting Organization Home is sent to the setup fallback',
    (tester) async {
      await _pumpAsRole(
        tester,
        role: 'organization',
        initialPath: AppRoutes.organizationHome,
        existingOrganizationProfile: null,
      );

      expect(find.text('Company Profile Setup Incomplete'), findsOneWidget);
      expect(find.byType(OrganizationHomeScreen), findsNothing);
    },
  );

  testWidgets(
    'An organization whose profile check fails (unknown status) is not trapped in a redirect loop',
    (tester) async {
      final (_, _, _, organizationRepository) = await _pumpAsRole(
        tester,
        role: 'organization',
        initialPath: AppRoutes.organizationHome,
        organizationProfileCheckError: ApiException(
          'Server error, please try again later.',
        ),
      );

      expect(organizationRepository.getProfileCallCount, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Direct URL access to the organization profile setup screen does not crash',
    (tester) async {
      await _pumpAsRole(
        tester,
        role: 'organization',
        initialPath: AppRoutes.organizationProfileRegistration,
        existingOrganizationProfile: null,
      );

      expect(find.text('Company Profile Setup Incomplete'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Sign Out from the organization setup fallback signs out and returns '
    'to Login with no redirect loop',
    (tester) async {
      final (authProvider, _, _, _) = await _pumpAsRole(
        tester,
        role: 'organization',
        initialPath: AppRoutes.organizationProfileRegistration,
        existingOrganizationProfile: null,
      );

      await tester.ensureVisible(find.text('Sign Out'));
      await tester.tap(find.text('Sign Out'));
      // pumpAndSettle completing (rather than timing out) is itself proof
      // there is no redirect loop between the now-unauthenticated state
      // and the protected setup route.
      await tester.pumpAndSettle();

      expect(authProvider.isAuthenticated, isFalse);
      expect(find.text('Company Profile Setup Incomplete'), findsNothing);
      expect(find.widgetWithText(ElevatedButton, 'Login'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'An unauthenticated visitor to the organization profile setup screen is redirected safely',
    (tester) async {
      _setViewSize(tester, const Size(420, 1400));

      final authProvider = AuthProvider(authRepository: _FakeAuthRepository());
      final studentProfileProvider = StudentProfileProvider(
        repository: _FakeStudentProfileRepository(),
        authProvider: authProvider,
      );
      final organizationProfileProvider = OrganizationProfileProvider(
        repository: _FakeOrganizationProfileRepository(),
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
            ChangeNotifierProvider<LocationCatalogProvider>(
              create: (_) => LocationCatalogProvider(
                repository: _FakeLocationRepository(),
              ),
            ),
            ChangeNotifierProvider<ThemeProvider>.value(value: ThemeProvider()),
          ],
          child: MaterialApp.router(
            theme: AppTheme.lightTheme,
            routerConfig: appRouter.router,
          ),
        ),
      );

      appRouter.router.go(AppRoutes.organizationProfileRegistration);
      await authProvider.initialize();
      await tester.pumpAndSettle();

      expect(find.text('Company Profile Setup Incomplete'), findsNothing);
      expect(find.text('Login'), findsWidgets);
      expect(tester.takeException(), isNull);
    },
  );
}
