// Router-level tests for student application-management routes:
// role/profile gating, direct-URL safety, and no redirect loops.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:opportunityhub_flutter/core/api/api_client.dart';
import 'package:opportunityhub_flutter/core/storage/token_storage_service.dart';
import 'package:opportunityhub_flutter/core/theme/app_theme.dart';
import 'package:opportunityhub_flutter/features/admin/data/admin_dashboard_repository.dart';
import 'package:opportunityhub_flutter/features/applications/data/application_repository.dart';
import 'package:opportunityhub_flutter/features/assessments/data/assessment_repository.dart';
import 'package:opportunityhub_flutter/features/auth/data/auth_repository.dart';
import 'package:opportunityhub_flutter/features/locations/data/location_repository.dart';
import 'package:opportunityhub_flutter/features/messaging/data/conversation_repository.dart';
import 'package:opportunityhub_flutter/features/notifications/data/notification_repository.dart';
import 'package:opportunityhub_flutter/features/offers/data/offer_repository.dart';
import 'package:opportunityhub_flutter/features/organization/data/organization_dashboard_repository.dart';
import 'package:opportunityhub_flutter/features/organization/data/organization_profile_repository.dart';
import 'package:opportunityhub_flutter/features/organization/presentation/organization_home_screen.dart';
import 'package:opportunityhub_flutter/features/student/data/student_profile_repository.dart';
import 'package:opportunityhub_flutter/models/admin_dashboard_stats_model.dart';
import 'package:opportunityhub_flutter/models/application_model.dart';
import 'package:opportunityhub_flutter/models/assessment_model.dart';
import 'package:opportunityhub_flutter/models/conversation_model.dart';
import 'package:opportunityhub_flutter/models/location_model.dart';
import 'package:opportunityhub_flutter/models/notification_model.dart';
import 'package:opportunityhub_flutter/models/offer_model.dart';
import 'package:opportunityhub_flutter/models/organization_dashboard_stats_model.dart';
import 'package:opportunityhub_flutter/models/organization_profile_model.dart';
import 'package:opportunityhub_flutter/models/student_profile_model.dart';
import 'package:opportunityhub_flutter/models/user_model.dart';
import 'package:opportunityhub_flutter/providers/admin_dashboard_provider.dart';
import 'package:opportunityhub_flutter/providers/auth_provider.dart';
import 'package:opportunityhub_flutter/providers/conversations_provider.dart';
import 'package:opportunityhub_flutter/providers/location_catalog_provider.dart';
import 'package:opportunityhub_flutter/providers/notification_provider.dart';
import 'package:opportunityhub_flutter/providers/organization_dashboard_provider.dart';
import 'package:opportunityhub_flutter/providers/organization_profile_provider.dart';
import 'package:opportunityhub_flutter/providers/student_applications_provider.dart';
import 'package:opportunityhub_flutter/providers/student_assessment_provider.dart';
import 'package:opportunityhub_flutter/providers/student_offer_provider.dart';
import 'package:opportunityhub_flutter/providers/student_profile_provider.dart';
import 'package:opportunityhub_flutter/providers/theme_provider.dart';
import 'package:opportunityhub_flutter/routes/app_router.dart';
import 'package:opportunityhub_flutter/routes/app_routes.dart';

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

class _FakeApplicationRepository extends ApplicationRepository {
  _FakeApplicationRepository()
    : super(apiClient: ApiClient(tokenStorageService: TokenStorageService()));

  @override
  Future<List<ApplicationModel>> getStudentApplications() async => [];
}

class _FakeAssessmentRepository extends AssessmentRepository {
  _FakeAssessmentRepository()
    : super(apiClient: ApiClient(tokenStorageService: TokenStorageService()));

  @override
  Future<List<AssessmentModel>> getStudentAssessmentsForApplication(
    int applicationId,
  ) async => [];
}

class _FakeOfferRepository extends OfferRepository {
  _FakeOfferRepository()
    : super(apiClient: ApiClient(tokenStorageService: TokenStorageService()));

  @override
  Future<OfferModel> getStudentOffer(int applicationId) async {
    throw ApiException('Offer not found', statusCode: 404);
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

// See _FakeAdminDashboardRepository's own doc comment above —
// OrganizationHomeScreen now requires OrganizationDashboardProvider
// directly, for the identical reason.
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

/// Pumps the full app, authenticated as [role] with a saved token
/// (simulating a returning user), and navigates straight to [initialPath].
Future<void> _pumpAsRole(
  WidgetTester tester, {
  required String role,
  required String initialPath,
  StudentProfileModel? studentProfile,
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
      getProfileResult: role == 'student' ? studentProfile : null,
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
  final applicationsProvider = StudentApplicationsProvider(
    repository: _FakeApplicationRepository(),
    authProvider: authProvider,
  );
  // Registered because StudentApplicationDetailsScreen now renders a
  // read-only Assessment section backed by this provider (see
  // student_application_details_screen_test.dart for its own dedicated
  // coverage) — not itself under test here, just required for the route to
  // resolve without a ProviderNotFoundException.
  final assessmentProvider = StudentAssessmentProvider(
    repository: _FakeAssessmentRepository(),
    authProvider: authProvider,
  );
  // Registered for the same reason as `assessmentProvider` above — the
  // Offer section (Phase 6C-3) is another read-only, section-level piece
  // of `StudentApplicationDetailsScreen`.
  final offerProvider = StudentOfferProvider(
    repository: _FakeOfferRepository(),
    authProvider: authProvider,
  );
  // Not exercised by every test in this file, but registered because a
  // role='admin' request for a non-admin route redirects to
  // AdminHomeScreen, which now requires this provider to exist in the tree.
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
  // See the AdminDashboardProvider comment above — the same reasoning
  // applies here: MessagesBellAction now renders unconditionally next to
  // NotificationBellAction on Student/Organization Home.
  final conversationsProvider = ConversationsProvider(
    repository: _FakeConversationRepository(),
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
        ChangeNotifierProvider<AdminDashboardProvider>.value(
          value: adminDashboardProvider,
        ),
        ChangeNotifierProvider<OrganizationDashboardProvider>.value(
          value: organizationDashboardProvider,
        ),
        ChangeNotifierProvider<OrganizationProfileProvider>.value(
          value: organizationProfileProvider,
        ),
        ChangeNotifierProvider<StudentApplicationsProvider>.value(
          value: applicationsProvider,
        ),
        ChangeNotifierProvider<StudentAssessmentProvider>.value(
          value: assessmentProvider,
        ),
        ChangeNotifierProvider<StudentOfferProvider>.value(
          value: offerProvider,
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

const _completeProfile = StudentProfileModel(
  id: 1,
  university: 'State University',
  major: 'Computer Science',
  graduationYear: 2027,
);

void main() {
  testWidgets('Unauthenticated users are redirected to login', (tester) async {
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
    final applicationsProvider = StudentApplicationsProvider(
      repository: _FakeApplicationRepository(),
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
          ChangeNotifierProvider<StudentApplicationsProvider>.value(
            value: applicationsProvider,
          ),
          ChangeNotifierProvider<LocationCatalogProvider>(
            create: (_) =>
                LocationCatalogProvider(repository: _FakeLocationRepository()),
          ),
          ChangeNotifierProvider<ThemeProvider>.value(value: ThemeProvider()),
        ],
        child: MaterialApp.router(
          theme: AppTheme.lightTheme,
          routerConfig: appRouter.router,
        ),
      ),
    );

    appRouter.router.go(AppRoutes.studentApplications);
    await authProvider.initialize();
    await tester.pumpAndSettle();

    expect(find.text('My Applications'), findsNothing);
    expect(find.text('Login'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Organizations cannot access student application routes', (
    tester,
  ) async {
    await _pumpAsRole(
      tester,
      role: 'organization',
      initialPath: AppRoutes.studentApplications,
    );

    expect(find.text('My Applications'), findsNothing);
    expect(find.byType(OrganizationHomeScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Admins cannot access student application routes', (
    tester,
  ) async {
    await _pumpAsRole(
      tester,
      role: 'admin',
      initialPath: AppRoutes.studentApplications,
    );

    expect(find.text('My Applications'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'A student with an incomplete profile remains routed to onboarding',
    (tester) async {
      await _pumpAsRole(
        tester,
        role: 'student',
        initialPath: AppRoutes.studentApplications,
        studentProfile: null,
      );

      expect(find.text('My Applications'), findsNothing);
    },
  );

  testWidgets(
    'A student with a completed profile may access their applications',
    (tester) async {
      await _pumpAsRole(
        tester,
        role: 'student',
        initialPath: AppRoutes.studentApplications,
        studentProfile: _completeProfile,
      );

      // "My Applications" legitimately appears twice now — the AppBar
      // title and the premium page hero's own heading (UI Phase 4).
      expect(find.text('My Applications'), findsWidgets);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Direct URL access to a details route does not crash (uses the ID alone)',
    (tester) async {
      await _pumpAsRole(
        tester,
        role: 'student',
        initialPath: AppRoutes.studentApplicationDetails(123),
        studentProfile: _completeProfile,
      );

      // A nonexistent ID surfaces the documented not-found error safely,
      // rather than crashing — proving the route never depended on extra.
      expect(find.text('Application not found'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('No redirect loop occurs for the applications list route', (
    tester,
  ) async {
    await _pumpAsRole(
      tester,
      role: 'student',
      initialPath: AppRoutes.studentApplications,
      studentProfile: _completeProfile,
    );

    // "My Applications" legitimately appears twice now — the AppBar title
    // and the premium page hero's own heading (UI Phase 4).
    expect(find.text('My Applications'), findsWidgets);
  });
}
