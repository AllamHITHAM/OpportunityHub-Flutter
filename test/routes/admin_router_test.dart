// Router-level tests for the Admin dashboard route: role gating,
// direct-URL safety, current suspended-account behavior, and no redirect
// loops. Mirrors organization_applications_router_test.dart's structure
// and conventions.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:opportunityhub_flutter/core/api/api_client.dart';
import 'package:opportunityhub_flutter/core/storage/token_storage_service.dart';
import 'package:opportunityhub_flutter/core/theme/app_theme.dart';
import 'package:opportunityhub_flutter/features/admin/data/admin_dashboard_repository.dart';
import 'package:opportunityhub_flutter/features/auth/data/auth_repository.dart';
import 'package:opportunityhub_flutter/features/organization/data/organization_profile_repository.dart';
import 'package:opportunityhub_flutter/features/student/data/student_profile_repository.dart';
import 'package:opportunityhub_flutter/models/admin_dashboard_stats_model.dart';
import 'package:opportunityhub_flutter/models/organization_profile_model.dart';
import 'package:opportunityhub_flutter/models/student_profile_model.dart';
import 'package:opportunityhub_flutter/models/user_model.dart';
import 'package:opportunityhub_flutter/providers/admin_dashboard_provider.dart';
import 'package:opportunityhub_flutter/providers/auth_provider.dart';
import 'package:opportunityhub_flutter/providers/organization_profile_provider.dart';
import 'package:opportunityhub_flutter/providers/student_profile_provider.dart';
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

AdminDashboardStatsModel _stats() {
  return const AdminDashboardStatsModel(
    totalUsers: 42,
    totalStudents: 30,
    totalOrganizations: 10,
    pendingOrganizations: 3,
    approvedOrganizations: 6,
    rejectedOrganizations: 1,
    totalOpportunities: 20,
    openOpportunities: 15,
    closedOpportunities: 5,
    totalApplications: 100,
    totalInterviews: 8,
  );
}

class _FakeAdminDashboardRepository extends AdminDashboardRepository {
  _FakeAdminDashboardRepository({this.loadError})
    : super(apiClient: ApiClient(tokenStorageService: TokenStorageService()));

  ApiException? loadError;

  @override
  Future<AdminDashboardStatsModel> getDashboardStats() async {
    if (loadError != null) throw loadError!;
    return _stats();
  }
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
  String status = 'active',
  ApiException? dashboardError,
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
        status: status,
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
  final organizationProfileProvider = OrganizationProfileProvider(
    repository: _FakeOrganizationProfileRepository(
      getProfileResult: role == 'organization'
          ? const OrganizationProfileModel(
              id: 1,
              organizationName: 'Acme Corp',
              organizationType: 'company',
              approvalStatus: 'approved',
            )
          : null,
    ),
    authProvider: authProvider,
  );
  final adminDashboardProvider = AdminDashboardProvider(
    repository: _FakeAdminDashboardRepository(loadError: dashboardError),
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
  testWidgets('An authenticated active admin can open /admin', (tester) async {
    await _pumpAsRole(tester, role: 'admin', initialPath: AppRoutes.adminHome);

    expect(find.text('Admin Dashboard'), findsOneWidget);
    expect(find.text('42'), findsOneWidget); // total_users from the fake
    expect(tester.takeException(), isNull);
  });

  testWidgets('Direct URL /admin works for an admin', (tester) async {
    await _pumpAsRole(tester, role: 'admin', initialPath: '/admin');

    expect(find.text('Admin Dashboard'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Admin login/home redirect resolves to /admin, not another role\'s home',
    (tester) async {
      await _pumpAsRole(tester, role: 'admin', initialPath: AppRoutes.login);

      expect(find.text('Admin Dashboard'), findsOneWidget);
      expect(find.text('Login'), findsNothing);
    },
  );

  testWidgets('Students cannot access /admin', (tester) async {
    await _pumpAsRole(
      tester,
      role: 'student',
      initialPath: AppRoutes.adminHome,
    );

    expect(find.text('Admin Dashboard'), findsNothing);
    expect(find.text('Role: Student'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Organizations cannot access /admin', (tester) async {
    await _pumpAsRole(
      tester,
      role: 'organization',
      initialPath: AppRoutes.adminHome,
    );

    expect(find.text('Admin Dashboard'), findsNothing);
    expect(find.text('Role: Organization'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('An unauthenticated guest is redirected to login from /admin', (
    tester,
  ) async {
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
    final adminDashboardProvider = AdminDashboardProvider(
      repository: _FakeAdminDashboardRepository(),
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
        ],
        child: MaterialApp.router(
          theme: AppTheme.lightTheme,
          routerConfig: appRouter.router,
        ),
      ),
    );

    appRouter.router.go(AppRoutes.adminHome);
    await authProvider.initialize();
    await tester.pumpAndSettle();

    expect(find.text('Admin Dashboard'), findsNothing);
    expect(find.text('Login'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'A suspended admin (restored session) follows current active-account '
    'behavior: the router still resolves to /admin, and the dashboard '
    'surfaces the backend\'s inactive-account error rather than crashing '
    'or silently showing stats',
    (tester) async {
      await _pumpAsRole(
        tester,
        role: 'admin',
        initialPath: AppRoutes.adminHome,
        status: 'suspended',
        dashboardError: ApiException('Account is not active', statusCode: 403),
      );

      // No router-level redirect exists for account status today (see
      // AppRouter._redirect — it checks `role` only) — this test documents
      // that existing behavior rather than inventing a new one.
      expect(find.text('Admin Dashboard'), findsOneWidget);
      expect(find.text('Account is not active'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('No redirect loop occurs for the admin route', (tester) async {
    await _pumpAsRole(tester, role: 'admin', initialPath: AppRoutes.adminHome);

    // Settling completed without a pumpAndSettle timeout (which throws if
    // frames never stop scheduling, e.g. from a redirect loop).
    expect(find.text('Admin Dashboard'), findsOneWidget);
  });
}
