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
import 'package:opportunityhub_flutter/features/admin/data/admin_organizations_repository.dart';
import 'package:opportunityhub_flutter/features/admin/data/admin_skill_suggestions_repository.dart';
import 'package:opportunityhub_flutter/features/admin/data/admin_skills_repository.dart';
import 'package:opportunityhub_flutter/features/admin/data/admin_users_repository.dart';
import 'package:opportunityhub_flutter/features/auth/data/auth_repository.dart';
import 'package:opportunityhub_flutter/features/notifications/data/notification_repository.dart';
import 'package:opportunityhub_flutter/features/organization/data/organization_profile_repository.dart';
import 'package:opportunityhub_flutter/features/student/data/student_profile_repository.dart';
import 'package:opportunityhub_flutter/models/admin_dashboard_stats_model.dart';
import 'package:opportunityhub_flutter/models/notification_model.dart';
import 'package:opportunityhub_flutter/models/organization_profile_model.dart';
import 'package:opportunityhub_flutter/models/skill_model.dart';
import 'package:opportunityhub_flutter/models/skill_suggestion_model.dart';
import 'package:opportunityhub_flutter/models/student_profile_model.dart';
import 'package:opportunityhub_flutter/models/user_model.dart';
import 'package:opportunityhub_flutter/providers/admin_dashboard_provider.dart';
import 'package:opportunityhub_flutter/providers/admin_organizations_provider.dart';
import 'package:opportunityhub_flutter/providers/admin_skill_suggestions_provider.dart';
import 'package:opportunityhub_flutter/providers/admin_skills_provider.dart';
import 'package:opportunityhub_flutter/providers/admin_users_provider.dart';
import 'package:opportunityhub_flutter/providers/auth_provider.dart';
import 'package:opportunityhub_flutter/providers/notification_provider.dart';
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

class _FakeAdminUsersRepository extends AdminUsersRepository {
  _FakeAdminUsersRepository()
    : super(apiClient: ApiClient(tokenStorageService: TokenStorageService()));

  @override
  Future<List<UserModel>> getUsers() async => [];
}

class _FakeAdminOrganizationsRepository extends AdminOrganizationsRepository {
  _FakeAdminOrganizationsRepository()
    : super(apiClient: ApiClient(tokenStorageService: TokenStorageService()));

  @override
  Future<List<OrganizationProfileModel>> getOrganizations() async => [];

  @override
  Future<OrganizationProfileModel> getOrganization(int organizationId) async {
    throw ApiException('No query results.', statusCode: 404);
  }
}

class _FakeAdminSkillsRepository extends AdminSkillsRepository {
  _FakeAdminSkillsRepository()
    : super(apiClient: ApiClient(tokenStorageService: TokenStorageService()));

  @override
  Future<List<SkillModel>> getSkills() async => [];
}

class _FakeAdminSkillSuggestionsRepository
    extends AdminSkillSuggestionsRepository {
  _FakeAdminSkillSuggestionsRepository()
    : super(apiClient: ApiClient(tokenStorageService: TokenStorageService()));

  @override
  Future<List<SkillSuggestionModel>> getPendingSuggestions() async => [];
}

class _FakeNotificationRepository extends NotificationRepository {
  _FakeNotificationRepository()
    : super(apiClient: ApiClient(tokenStorageService: TokenStorageService()));

  @override
  Future<List<NotificationModel>> getNotifications() async => [];
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
  final adminUsersProvider = AdminUsersProvider(
    repository: _FakeAdminUsersRepository(),
    authProvider: authProvider,
  );
  final adminOrganizationsProvider = AdminOrganizationsProvider(
    repository: _FakeAdminOrganizationsRepository(),
    authProvider: authProvider,
  );
  final adminSkillsProvider = AdminSkillsProvider(
    repository: _FakeAdminSkillsRepository(),
    authProvider: authProvider,
  );
  final adminSkillSuggestionsProvider = AdminSkillSuggestionsProvider(
    repository: _FakeAdminSkillSuggestionsRepository(),
    authProvider: authProvider,
  );
  final notificationProvider = NotificationProvider(
    repository: _FakeNotificationRepository(),
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
        ChangeNotifierProvider<AdminUsersProvider>.value(
          value: adminUsersProvider,
        ),
        ChangeNotifierProvider<AdminOrganizationsProvider>.value(
          value: adminOrganizationsProvider,
        ),
        ChangeNotifierProvider<AdminSkillsProvider>.value(
          value: adminSkillsProvider,
        ),
        ChangeNotifierProvider<AdminSkillSuggestionsProvider>.value(
          value: adminSkillSuggestionsProvider,
        ),
        ChangeNotifierProvider<NotificationProvider>.value(
          value: notificationProvider,
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

  testWidgets('An authenticated active admin can open /admin/users', (
    tester,
  ) async {
    await _pumpAsRole(tester, role: 'admin', initialPath: AppRoutes.adminUsers);

    expect(find.text('Manage Users'), findsOneWidget);
    expect(find.text('No Users Yet'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Direct URL /admin/users works for an admin', (tester) async {
    await _pumpAsRole(tester, role: 'admin', initialPath: '/admin/users');

    expect(find.text('Manage Users'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Students cannot access /admin/users', (tester) async {
    await _pumpAsRole(
      tester,
      role: 'student',
      initialPath: AppRoutes.adminUsers,
    );

    expect(find.text('Manage Users'), findsNothing);
    expect(find.text('Role: Student'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Organizations cannot access /admin/users', (tester) async {
    await _pumpAsRole(
      tester,
      role: 'organization',
      initialPath: AppRoutes.adminUsers,
    );

    expect(find.text('Manage Users'), findsNothing);
    expect(find.text('Role: Organization'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'An unauthenticated guest is redirected to login from /admin/users',
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
      final adminDashboardProvider = AdminDashboardProvider(
        repository: _FakeAdminDashboardRepository(),
        authProvider: authProvider,
      );
      final adminUsersProvider = AdminUsersProvider(
        repository: _FakeAdminUsersRepository(),
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
            ChangeNotifierProvider<AdminUsersProvider>.value(
              value: adminUsersProvider,
            ),
          ],
          child: MaterialApp.router(
            theme: AppTheme.lightTheme,
            routerConfig: appRouter.router,
          ),
        ),
      );

      appRouter.router.go(AppRoutes.adminUsers);
      await authProvider.initialize();
      await tester.pumpAndSettle();

      expect(find.text('Manage Users'), findsNothing);
      expect(find.text('Login'), findsWidgets);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('No redirect loop occurs for the admin users route', (
    tester,
  ) async {
    await _pumpAsRole(tester, role: 'admin', initialPath: AppRoutes.adminUsers);

    // Settling completed without a pumpAndSettle timeout (which throws if
    // frames never stop scheduling, e.g. from a redirect loop).
    expect(find.text('Manage Users'), findsOneWidget);
  });

  testWidgets('An authenticated active admin can open /admin/organizations', (
    tester,
  ) async {
    await _pumpAsRole(
      tester,
      role: 'admin',
      initialPath: AppRoutes.adminOrganizations,
    );

    expect(find.text('Manage Organizations'), findsOneWidget);
    expect(find.text('No Organizations Yet'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Direct URL /admin/organizations works for an admin', (
    tester,
  ) async {
    await _pumpAsRole(
      tester,
      role: 'admin',
      initialPath: '/admin/organizations',
    );

    expect(find.text('Manage Organizations'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'An authenticated active admin can open an organization details URL',
    (tester) async {
      await _pumpAsRole(
        tester,
        role: 'admin',
        initialPath: AppRoutes.adminOrganizationDetails(5),
      );

      // The fake repository's getOrganization always 404s — this proves
      // the route itself resolves and renders a controlled error, not a
      // crash, for an admin.
      expect(find.text('Organization Details'), findsOneWidget);
      expect(find.text('No query results.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'A malformed organization ID in the URL is handled safely, not a crash',
    (tester) async {
      await _pumpAsRole(
        tester,
        role: 'admin',
        initialPath: '/admin/organizations/not-a-number',
      );

      expect(find.text('Organization Details'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Students cannot access /admin/organizations', (tester) async {
    await _pumpAsRole(
      tester,
      role: 'student',
      initialPath: AppRoutes.adminOrganizations,
    );

    expect(find.text('Manage Organizations'), findsNothing);
    expect(find.text('Role: Student'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Organizations cannot access /admin/organizations', (
    tester,
  ) async {
    await _pumpAsRole(
      tester,
      role: 'organization',
      initialPath: AppRoutes.adminOrganizations,
    );

    expect(find.text('Manage Organizations'), findsNothing);
    expect(find.text('Role: Organization'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'An unauthenticated guest is redirected to login from /admin/organizations',
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
      final adminDashboardProvider = AdminDashboardProvider(
        repository: _FakeAdminDashboardRepository(),
        authProvider: authProvider,
      );
      final adminOrganizationsProvider = AdminOrganizationsProvider(
        repository: _FakeAdminOrganizationsRepository(),
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
            ChangeNotifierProvider<AdminOrganizationsProvider>.value(
              value: adminOrganizationsProvider,
            ),
          ],
          child: MaterialApp.router(
            theme: AppTheme.lightTheme,
            routerConfig: appRouter.router,
          ),
        ),
      );

      appRouter.router.go(AppRoutes.adminOrganizations);
      await authProvider.initialize();
      await tester.pumpAndSettle();

      expect(find.text('Manage Organizations'), findsNothing);
      expect(find.text('Login'), findsWidgets);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('No redirect loop occurs for the admin organizations route', (
    tester,
  ) async {
    await _pumpAsRole(
      tester,
      role: 'admin',
      initialPath: AppRoutes.adminOrganizations,
    );

    // Settling completed without a pumpAndSettle timeout (which throws if
    // frames never stop scheduling, e.g. from a redirect loop).
    expect(find.text('Manage Organizations'), findsOneWidget);
  });

  testWidgets('An authenticated active admin can open /admin/skills', (
    tester,
  ) async {
    await _pumpAsRole(
      tester,
      role: 'admin',
      initialPath: AppRoutes.adminSkills,
    );

    expect(find.text('Manage Skills'), findsOneWidget);
    expect(find.text('No Skills Yet'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Direct URL /admin/skills works for an admin', (tester) async {
    await _pumpAsRole(tester, role: 'admin', initialPath: '/admin/skills');

    expect(find.text('Manage Skills'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Students cannot access /admin/skills', (tester) async {
    await _pumpAsRole(
      tester,
      role: 'student',
      initialPath: AppRoutes.adminSkills,
    );

    expect(find.text('Manage Skills'), findsNothing);
    expect(find.text('Role: Student'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Organizations cannot access /admin/skills', (tester) async {
    await _pumpAsRole(
      tester,
      role: 'organization',
      initialPath: AppRoutes.adminSkills,
    );

    expect(find.text('Manage Skills'), findsNothing);
    expect(find.text('Role: Organization'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'An unauthenticated guest is redirected to login from /admin/skills',
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
      final adminDashboardProvider = AdminDashboardProvider(
        repository: _FakeAdminDashboardRepository(),
        authProvider: authProvider,
      );
      final adminSkillsProvider = AdminSkillsProvider(
        repository: _FakeAdminSkillsRepository(),
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
            ChangeNotifierProvider<AdminSkillsProvider>.value(
              value: adminSkillsProvider,
            ),
          ],
          child: MaterialApp.router(
            theme: AppTheme.lightTheme,
            routerConfig: appRouter.router,
          ),
        ),
      );

      appRouter.router.go(AppRoutes.adminSkills);
      await authProvider.initialize();
      await tester.pumpAndSettle();

      expect(find.text('Manage Skills'), findsNothing);
      expect(find.text('Login'), findsWidgets);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('No redirect loop occurs for the admin skills route', (
    tester,
  ) async {
    await _pumpAsRole(
      tester,
      role: 'admin',
      initialPath: AppRoutes.adminSkills,
    );

    // Settling completed without a pumpAndSettle timeout (which throws if
    // frames never stop scheduling, e.g. from a redirect loop).
    expect(find.text('Manage Skills'), findsOneWidget);
  });
}
