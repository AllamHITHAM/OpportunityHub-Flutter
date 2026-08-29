// Widget tests for AdminHomeScreen, in isolation with a small GoRouter.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'package:opportunityhub_flutter/core/api/api_client.dart';
import 'package:opportunityhub_flutter/core/storage/token_storage_service.dart';
import 'package:opportunityhub_flutter/core/theme/app_theme.dart';
import 'package:opportunityhub_flutter/core/theme/app_colors.dart';
import 'package:opportunityhub_flutter/features/admin/data/admin_dashboard_repository.dart';
import 'package:opportunityhub_flutter/features/admin/data/admin_education_verifications_repository.dart';
import 'package:opportunityhub_flutter/features/admin/data/admin_organizations_repository.dart';
import 'package:opportunityhub_flutter/features/admin/data/admin_skill_suggestions_repository.dart';
import 'package:opportunityhub_flutter/features/admin/data/admin_skills_repository.dart';
import 'package:opportunityhub_flutter/features/admin/data/admin_users_repository.dart';
import 'package:opportunityhub_flutter/features/admin/presentation/admin_education_verifications_screen.dart';
import 'package:opportunityhub_flutter/features/admin/presentation/admin_home_screen.dart';
import 'package:opportunityhub_flutter/features/admin/presentation/admin_organizations_screen.dart';
import 'package:opportunityhub_flutter/features/admin/presentation/admin_skills_screen.dart';
import 'package:opportunityhub_flutter/features/admin/presentation/admin_users_screen.dart';
import 'package:opportunityhub_flutter/features/auth/data/auth_repository.dart';
import 'package:opportunityhub_flutter/features/notifications/data/notification_repository.dart';
import 'package:opportunityhub_flutter/models/admin_dashboard_stats_model.dart';
import 'package:opportunityhub_flutter/models/admin_education_verification_model.dart';
import 'package:opportunityhub_flutter/models/notification_model.dart';
import 'package:opportunityhub_flutter/models/organization_profile_model.dart';
import 'package:opportunityhub_flutter/models/skill_model.dart';
import 'package:opportunityhub_flutter/models/skill_suggestion_model.dart';
import 'package:opportunityhub_flutter/models/user_model.dart';
import 'package:opportunityhub_flutter/providers/admin_dashboard_provider.dart';
import 'package:opportunityhub_flutter/providers/admin_education_verifications_provider.dart';
import 'package:opportunityhub_flutter/providers/admin_organizations_provider.dart';
import 'package:opportunityhub_flutter/providers/admin_skill_suggestions_provider.dart';
import 'package:opportunityhub_flutter/providers/admin_skills_provider.dart';
import 'package:opportunityhub_flutter/providers/admin_users_provider.dart';
import 'package:opportunityhub_flutter/providers/auth_provider.dart';
import 'package:opportunityhub_flutter/providers/notification_provider.dart';
import 'package:opportunityhub_flutter/providers/theme_provider.dart';
import 'package:opportunityhub_flutter/routes/app_routes.dart';

class _FakeAuthRepository extends AuthRepository {
  _FakeAuthRepository()
    : super(
        apiClient: ApiClient(tokenStorageService: TokenStorageService()),
        tokenStorageService: TokenStorageService(),
      );

  int logoutCallCount = 0;
  int resendVerificationCallCount = 0;
  ApiException? resendVerificationError;

  @override
  Future<String?> getSavedToken() async => null;

  @override
  Future<void> logout() async {
    logoutCallCount++;
  }

  @override
  Future<void> resendVerificationEmail() async {
    resendVerificationCallCount++;
    if (resendVerificationError != null) throw resendVerificationError!;
  }
}

const _adminUser = UserModel(
  id: 1,
  name: 'Ada Admin',
  email: 'ada@example.com',
  role: 'admin',
  status: 'active',
);

AdminDashboardStatsModel _stats({
  int totalUsers = 42,
  int totalStudents = 17,
  int totalOrganizations = 8,
  int pendingOrganizations = 3,
  int approvedOrganizations = 4,
  int rejectedOrganizations = 1,
  int totalOpportunities = 25,
  int openOpportunities = 19,
  int closedOpportunities = 6,
  int totalApplications = 133,
  int totalInterviews = 11,
}) {
  return AdminDashboardStatsModel(
    totalUsers: totalUsers,
    totalStudents: totalStudents,
    totalOrganizations: totalOrganizations,
    pendingOrganizations: pendingOrganizations,
    approvedOrganizations: approvedOrganizations,
    rejectedOrganizations: rejectedOrganizations,
    totalOpportunities: totalOpportunities,
    openOpportunities: openOpportunities,
    closedOpportunities: closedOpportunities,
    totalApplications: totalApplications,
    totalInterviews: totalInterviews,
  );
}

class _FakeAdminDashboardRepository extends AdminDashboardRepository {
  _FakeAdminDashboardRepository()
    : super(apiClient: ApiClient(tokenStorageService: TokenStorageService()));

  AdminDashboardStatsModel? loadResult;
  ApiException? loadError;
  Duration loadDelay = Duration.zero;
  int getDashboardStatsCallCount = 0;

  @override
  Future<AdminDashboardStatsModel> getDashboardStats() async {
    getDashboardStatsCallCount++;
    if (loadDelay > Duration.zero) {
      await Future<void>.delayed(loadDelay);
    }
    if (loadError != null) throw loadError!;
    return loadResult!;
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
  _FakeNotificationRepository({this.listResult = const []})
    : super(apiClient: ApiClient(tokenStorageService: TokenStorageService()));

  List<NotificationModel> listResult;

  @override
  Future<List<NotificationModel>> getNotifications() async => listResult;
}

class _FakeAdminEducationVerificationsRepository
    extends AdminEducationVerificationsRepository {
  _FakeAdminEducationVerificationsRepository()
    : super(apiClient: ApiClient(tokenStorageService: TokenStorageService()));

  @override
  Future<List<AdminEducationVerificationModel>> getVerifications() async =>
      [];
}

class _Providers {
  _Providers({
    required this.auth,
    required this.dashboard,
    required this.notifications,
  });

  final AuthProvider auth;
  final AdminDashboardProvider dashboard;
  final NotificationProvider notifications;
}

/// A router with /admin, /admin/users, /admin/organizations, /admin/skills,
/// and /admin/education-verifications registered, matching the real
/// AppRouter's route table — needed now that every "Manage"/"Education
/// Verifications" entry actually navigates.
GoRouter _adminRouter() {
  return GoRouter(
    initialLocation: '/admin',
    routes: [
      GoRoute(path: '/admin', builder: (_, _) => const AdminHomeScreen()),
      GoRoute(
        path: AppRoutes.adminUsers,
        builder: (_, _) => const AdminUsersScreen(),
      ),
      GoRoute(
        path: AppRoutes.adminOrganizations,
        builder: (_, _) => const AdminOrganizationsScreen(),
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
        path: AppRoutes.notifications,
        builder: (_, _) => const Scaffold(body: Text('NOTIFICATIONS_SCREEN')),
      ),
    ],
  );
}

Future<_Providers> _pumpScreen(
  WidgetTester tester, {
  required AdminDashboardRepository repository,
  Size size = const Size(420, 1200),
  List<NotificationModel> notificationListResult = const [],
  bool dark = false,
  UserModel adminUser = _adminUser,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  if (dark) {
    AppColors.updateBrightness(Brightness.dark);
    addTearDown(() => AppColors.updateBrightness(Brightness.light));
  }

  final authProvider = AuthProvider(authRepository: _FakeAuthRepository())
    ..user = adminUser;
  final dashboardProvider = AdminDashboardProvider(
    repository: repository,
    authProvider: authProvider,
  );
  final usersProvider = AdminUsersProvider(
    repository: _FakeAdminUsersRepository(),
    authProvider: authProvider,
  );
  final organizationsProvider = AdminOrganizationsProvider(
    repository: _FakeAdminOrganizationsRepository(),
    authProvider: authProvider,
  );
  final skillsProvider = AdminSkillsProvider(
    repository: _FakeAdminSkillsRepository(),
    authProvider: authProvider,
  );
  final skillSuggestionsProvider = AdminSkillSuggestionsProvider(
    repository: _FakeAdminSkillSuggestionsRepository(),
    authProvider: authProvider,
  );
  final notificationProvider = NotificationProvider(
    repository: _FakeNotificationRepository(listResult: notificationListResult),
    authProvider: authProvider,
  );
  final educationVerificationsProvider = AdminEducationVerificationsProvider(
    repository: _FakeAdminEducationVerificationsRepository(),
    authProvider: authProvider,
  );

  final router = _adminRouter();

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthProvider>.value(value: authProvider),
        ChangeNotifierProvider<AdminDashboardProvider>.value(
          value: dashboardProvider,
        ),
        ChangeNotifierProvider<AdminUsersProvider>.value(value: usersProvider),
        ChangeNotifierProvider<AdminOrganizationsProvider>.value(
          value: organizationsProvider,
        ),
        ChangeNotifierProvider<AdminSkillsProvider>.value(
          value: skillsProvider,
        ),
        ChangeNotifierProvider<AdminSkillSuggestionsProvider>.value(
          value: skillSuggestionsProvider,
        ),
        ChangeNotifierProvider<NotificationProvider>.value(
          value: notificationProvider,
        ),
        ChangeNotifierProvider<AdminEducationVerificationsProvider>.value(
          value: educationVerificationsProvider,
        ),
        ChangeNotifierProvider<ThemeProvider>.value(value: ThemeProvider()),
      ],
      child: MaterialApp.router(
        theme: dark ? AppTheme.darkTheme : AppTheme.lightTheme,
        routerConfig: router,
      ),
    ),
  );
  await tester.pumpAndSettle();

  return _Providers(
    auth: authProvider,
    dashboard: dashboardProvider,
    notifications: notificationProvider,
  );
}

void main() {
  testWidgets('Initial loading state renders while stats are in flight', (
    tester,
  ) async {
    final repository = _FakeAdminDashboardRepository()
      ..loadResult = _stats()
      ..loadDelay = const Duration(milliseconds: 200);

    tester.view.physicalSize = const Size(420, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final authProvider = AuthProvider(authRepository: _FakeAuthRepository())
      ..user = _adminUser;
    final dashboardProvider = AdminDashboardProvider(
      repository: repository,
      authProvider: authProvider,
    );
    final notificationProvider = NotificationProvider(
      repository: _FakeNotificationRepository(),
      authProvider: authProvider,
    );
    final router = GoRouter(
      initialLocation: '/admin',
      routes: [
        GoRoute(path: '/admin', builder: (_, _) => const AdminHomeScreen()),
      ],
    );

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthProvider>.value(value: authProvider),
          ChangeNotifierProvider<AdminDashboardProvider>.value(
            value: dashboardProvider,
          ),
          ChangeNotifierProvider<NotificationProvider>.value(
            value: notificationProvider,
          ),
          ChangeNotifierProvider<ThemeProvider>.value(value: ThemeProvider()),
        ],
        child: MaterialApp.router(
          theme: AppTheme.lightTheme,
          routerConfig: router,
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(dashboardProvider.isLoading, isTrue);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('42'), findsNothing);

    await tester.pumpAndSettle();
  });

  testWidgets(
    'Error state with no stats shows AppErrorView and a working retry',
    (tester) async {
      final repository = _FakeAdminDashboardRepository()
        ..loadError = ApiException('Account is not active');

      final providers = await _pumpScreen(tester, repository: repository);

      expect(find.text('Account is not active'), findsOneWidget);
      expect(find.text('Try Again'), findsOneWidget);
      expect(find.text('42'), findsNothing);

      repository.loadError = null;
      repository.loadResult = _stats();
      await tester.tap(find.text('Try Again'));
      await tester.pumpAndSettle();

      expect(find.text('Account is not active'), findsNothing);
      expect(find.text('42'), findsOneWidget);
      expect(providers.dashboard.stats, isNotNull);
    },
  );

  testWidgets('Dashboard renders all 11 statistics', (tester) async {
    final repository = _FakeAdminDashboardRepository()..loadResult = _stats();

    await _pumpScreen(tester, repository: repository);

    expect(find.text('42'), findsOneWidget); // total users
    expect(find.text('17'), findsOneWidget); // total students
    expect(find.text('8'), findsOneWidget); // total organizations
    expect(find.text('3'), findsOneWidget); // pending organizations
    expect(find.text('4'), findsOneWidget); // approved organizations
    expect(find.text('1'), findsOneWidget); // rejected organizations
    expect(find.text('25'), findsOneWidget); // total opportunities
    expect(find.text('19'), findsOneWidget); // open opportunities
    expect(find.text('6'), findsOneWidget); // closed opportunities
    expect(find.text('133'), findsOneWidget); // total applications
    expect(find.text('11'), findsOneWidget); // total interviews
  });

  testWidgets(
    'Statistics are not hard-coded — a different dataset renders different numbers',
    (tester) async {
      final repository = _FakeAdminDashboardRepository()
        ..loadResult = _stats(
          totalUsers: 999,
          totalStudents: 777,
          totalInterviews: 555,
        );

      await _pumpScreen(tester, repository: repository);

      expect(find.text('999'), findsOneWidget);
      expect(find.text('777'), findsOneWidget);
      expect(find.text('555'), findsOneWidget);
      expect(find.text('42'), findsNothing);
    },
  );

  testWidgets('Statistics are grouped under the correct section headers', (
    tester,
  ) async {
    final repository = _FakeAdminDashboardRepository()..loadResult = _stats();

    await _pumpScreen(tester, repository: repository);

    expect(find.text('Overview'), findsOneWidget);
    expect(find.text('Total Users'), findsOneWidget);
    expect(find.text('Students'), findsOneWidget);
    // Appears twice by design: once as the Overview section's summary
    // tile label, once as the section header for the breakdown below.
    expect(find.text('Organizations'), findsNWidgets(2));

    expect(find.text('Pending'), findsOneWidget);
    expect(find.text('Approved'), findsOneWidget);
    expect(find.text('Rejected'), findsOneWidget);

    expect(find.text('Opportunities'), findsOneWidget);
    expect(find.text('Open'), findsOneWidget);
    expect(find.text('Closed'), findsOneWidget);

    expect(find.text('Recruitment'), findsOneWidget);
    expect(find.text('Applications'), findsOneWidget);
    expect(find.text('Interviews'), findsOneWidget);
  });

  testWidgets('Logout remains available and calls AuthProvider.logout', (
    tester,
  ) async {
    final repository = _FakeAdminDashboardRepository()..loadResult = _stats();
    final providers = await _pumpScreen(tester, repository: repository);

    // Admin Dashboard Final UI Polish: Logout is now a restrained
    // `TextButton.icon` (matching OrganizationHomeScreen's own logout
    // treatment), not a full-width button -- the underlying behavior
    // this test verifies is unchanged.
    await tester.ensureVisible(find.widgetWithText(TextButton, 'Logout'));
    await tester.tap(find.widgetWithText(TextButton, 'Logout'));
    // Not `pumpAndSettle()`: logging out resets AdminDashboardProvider
    // (via its AuthProvider listener), and with no stats left to show and
    // no redirect logic in this isolated router (the real AppRouter would
    // navigate away from /admin the instant auth changes — see
    // admin_router_test.dart), the screen falls back to an indefinitely
    // animating spinner that would never let pumpAndSettle finish. A
    // couple of plain pumps is enough to let logout() itself resolve.
    await tester.pump();
    await tester.pump();

    expect(
      (providers.auth.authRepository as _FakeAuthRepository).logoutCallCount,
      1,
    );
  });

  testWidgets('Pull-to-refresh calls the provider and reloads stats', (
    tester,
  ) async {
    final repository = _FakeAdminDashboardRepository()..loadResult = _stats();
    await _pumpScreen(tester, repository: repository);

    expect(repository.getDashboardStatsCallCount, 1);

    // Deliberately not awaited: `show()`'s own Future only resolves once
    // frames are pumped, so awaiting it directly here (with nothing else
    // able to run on this single-threaded event loop) would deadlock.
    // `pumpAndSettle()` below both drives it to completion and settles.
    unawaited(
      tester.state<RefreshIndicatorState>(find.byType(RefreshIndicator)).show(),
    );
    await tester.pumpAndSettle();

    expect(repository.getDashboardStatsCallCount, 2);
  });

  testWidgets('Refresh keeps existing stats visible while it is in flight', (
    tester,
  ) async {
    final repository = _FakeAdminDashboardRepository()..loadResult = _stats();
    await _pumpScreen(tester, repository: repository);

    repository.loadDelay = const Duration(milliseconds: 200);
    unawaited(
      tester.state<RefreshIndicatorState>(find.byType(RefreshIndicator)).show(),
    );
    await tester.pump();

    // The old stats are still on screen -- no full-screen loading spinner
    // replaced them.
    expect(find.text('42'), findsOneWidget);

    await tester.pumpAndSettle();
  });

  testWidgets(
    'A failed refresh keeps old stats and shows a compact error, not a blank screen',
    (tester) async {
      final repository = _FakeAdminDashboardRepository()..loadResult = _stats();
      await _pumpScreen(tester, repository: repository);
      expect(find.text('42'), findsOneWidget);

      repository.loadResult = null;
      repository.loadError = ApiException('Server error, please retry.');

      // Not awaited -- see the identical comment above.
      unawaited(
        tester
            .state<RefreshIndicatorState>(find.byType(RefreshIndicator))
            .show(),
      );
      await tester.pumpAndSettle();

      expect(find.text('42'), findsOneWidget); // old stats retained
      expect(find.text('Server error, please retry.'), findsOneWidget);
    },
  );

  testWidgets('No overflow at a narrow 320-wide viewport', (tester) async {
    final repository = _FakeAdminDashboardRepository()..loadResult = _stats();

    await _pumpScreen(
      tester,
      repository: repository,
      size: const Size(320, 700),
    );

    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'All three management entries are enabled — no "Coming Soon" remains',
    (tester) async {
      final repository = _FakeAdminDashboardRepository()..loadResult = _stats();
      await _pumpScreen(tester, repository: repository);

      expect(find.text('Manage Users'), findsOneWidget);
      expect(find.text('Manage Organizations'), findsOneWidget);
      expect(find.text('Manage Skills'), findsOneWidget);
      expect(find.text('Coming Soon'), findsNothing);
    },
  );

  testWidgets('Manage Users is enabled and navigates to /admin/users', (
    tester,
  ) async {
    final repository = _FakeAdminDashboardRepository()..loadResult = _stats();
    await _pumpScreen(tester, repository: repository);

    expect(find.text('Manage Users'), findsOneWidget);

    await tester.ensureVisible(find.text('Manage Users'));
    await tester.tap(find.text('Manage Users'));
    await tester.pumpAndSettle();

    // Now on AdminUsersScreen -- its own AppBar title is also "Manage
    // Users", so this only proves navigation happened when combined with
    // the dashboard's own title being gone.
    expect(find.text('Manage Users'), findsOneWidget);
    expect(find.text('Admin Dashboard'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Manage Organizations is enabled and navigates to /admin/organizations',
    (tester) async {
      final repository = _FakeAdminDashboardRepository()..loadResult = _stats();
      await _pumpScreen(tester, repository: repository);

      expect(find.text('Manage Organizations'), findsOneWidget);

      await tester.ensureVisible(find.text('Manage Organizations'));
      await tester.tap(find.text('Manage Organizations'));
      await tester.pumpAndSettle();

      // Now on AdminOrganizationsScreen -- its own AppBar title is also
      // "Manage Organizations", so this only proves navigation happened
      // when combined with the dashboard's own title being gone.
      expect(find.text('Manage Organizations'), findsOneWidget);
      expect(find.text('Admin Dashboard'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Manage Skills is enabled and navigates to /admin/skills', (
    tester,
  ) async {
    final repository = _FakeAdminDashboardRepository()..loadResult = _stats();
    await _pumpScreen(tester, repository: repository);

    expect(find.text('Manage Skills'), findsOneWidget);

    await tester.ensureVisible(find.text('Manage Skills'));
    await tester.tap(find.text('Manage Skills'));
    await tester.pumpAndSettle();

    // Now on AdminSkillsScreen -- its own AppBar title is also "Manage
    // Skills", so this only proves navigation happened when combined with
    // the dashboard's own title being gone.
    expect(find.text('Manage Skills'), findsOneWidget);
    expect(find.text('Admin Dashboard'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('The notification bell is present in the AppBar', (tester) async {
    final repository = _FakeAdminDashboardRepository()..loadResult = _stats();
    await _pumpScreen(tester, repository: repository);

    expect(find.byIcon(Icons.notifications_outlined), findsOneWidget);
  });

  testWidgets('The badge is hidden when there is no unread notification', (
    tester,
  ) async {
    final repository = _FakeAdminDashboardRepository()..loadResult = _stats();
    await _pumpScreen(tester, repository: repository);

    final badge = tester.widget<Badge>(find.byType(Badge));
    expect(badge.isLabelVisible, isFalse);
  });

  testWidgets('The badge shows the unread count', (tester) async {
    final repository = _FakeAdminDashboardRepository()..loadResult = _stats();
    await _pumpScreen(
      tester,
      repository: repository,
      notificationListResult: [
        const NotificationModel(
          id: 1,
          userId: 1,
          title: 'Notice',
          message: 'A notification.',
          priority: 'normal',
          type: 'system',
          isRead: false,
        ),
      ],
    );

    final badge = tester.widget<Badge>(find.byType(Badge));
    expect(badge.isLabelVisible, isTrue);
    expect(
      find.descendant(of: find.byType(Badge), matching: find.text('1')),
      findsOneWidget,
    );
  });

  testWidgets('Tapping the bell opens the Notifications screen', (
    tester,
  ) async {
    final repository = _FakeAdminDashboardRepository()..loadResult = _stats();
    await _pumpScreen(tester, repository: repository);

    await tester.tap(find.byIcon(Icons.notifications_outlined));
    await tester.pumpAndSettle();

    expect(find.text('NOTIFICATIONS_SCREEN'), findsOneWidget);
  });

  testWidgets(
    'Education Verifications is enabled and navigates to '
    '/admin/education-verifications',
    (tester) async {
      final repository = _FakeAdminDashboardRepository()..loadResult = _stats();
      await _pumpScreen(tester, repository: repository);

      expect(find.text('Education Verifications'), findsOneWidget);

      await tester.ensureVisible(find.text('Education Verifications'));
      await tester.tap(find.text('Education Verifications'));
      await tester.pumpAndSettle();

      // Now on AdminEducationVerificationsScreen -- its own AppBar title
      // is also "Education Verifications", so this only proves
      // navigation happened when combined with the dashboard's own title
      // being gone.
      expect(find.text('Education Verifications'), findsOneWidget);
      expect(find.text('Admin Dashboard'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  group('Email verification banner (Admin Dashboard Final UI Polish)', () {
    testWidgets(
      'shows for a genuinely unverified Admin, and Resend works',
      (tester) async {
        final repository = _FakeAdminDashboardRepository()
          ..loadResult = _stats();
        // `_adminUser` has no `emailVerified: true` override -- a real,
        // supported unverified-Admin state, not a special case invented
        // for this test.
        final providers = await _pumpScreen(tester, repository: repository);

        expect(find.text('Email not verified'), findsOneWidget);
        expect(find.text('Resend'), findsOneWidget);

        await tester.tap(find.text('Resend'));
        await tester.pumpAndSettle();

        expect(
          (providers.auth.authRepository as _FakeAuthRepository)
              .resendVerificationCallCount,
          1,
        );
        expect(providers.auth.resendVerificationSucceeded, isTrue);
      },
    );

    testWidgets('never shows for a verified Admin', (tester) async {
      final repository = _FakeAdminDashboardRepository()..loadResult = _stats();
      await _pumpScreen(
        tester,
        repository: repository,
        adminUser: const UserModel(
          id: 1,
          name: 'Ada Admin',
          email: 'ada@example.com',
          role: 'admin',
          status: 'active',
          emailVerified: true,
        ),
      );

      expect(find.text('Email not verified'), findsNothing);
    });

    testWidgets('a failed resend shows a real error, not a silent failure', (
      tester,
    ) async {
      final repository = _FakeAdminDashboardRepository()..loadResult = _stats();
      final providers = await _pumpScreen(tester, repository: repository);

      (providers.auth.authRepository as _FakeAuthRepository)
              .resendVerificationError =
          ApiException('Could not send the email right now');

      await tester.tap(find.text('Resend'));
      await tester.pumpAndSettle();

      expect(
        find.text('Could not send the email right now'),
        findsOneWidget,
      );
    });
  });

  group('responsive / theming / motion (Admin Dashboard Final UI Polish)', () {
    testWidgets('desktop viewport (>=1200) renders without overflow', (
      tester,
    ) async {
      final repository = _FakeAdminDashboardRepository()..loadResult = _stats();

      await _pumpScreen(
        tester,
        repository: repository,
        size: const Size(1400, 900),
      );

      expect(tester.takeException(), isNull);
    });

    testWidgets('900-1199 viewport renders without overflow', (tester) async {
      final repository = _FakeAdminDashboardRepository()..loadResult = _stats();

      await _pumpScreen(
        tester,
        repository: repository,
        size: const Size(1000, 900),
      );

      expect(tester.takeException(), isNull);
    });

    testWidgets('600-899 (tablet) viewport renders without overflow', (
      tester,
    ) async {
      final repository = _FakeAdminDashboardRepository()..loadResult = _stats();

      await _pumpScreen(
        tester,
        repository: repository,
        size: const Size(700, 900),
      );

      expect(tester.takeException(), isNull);
    });

    testWidgets('a long Admin email wraps safely at a narrow phone width', (
      tester,
    ) async {
      final repository = _FakeAdminDashboardRepository()..loadResult = _stats();

      await _pumpScreen(
        tester,
        repository: repository,
        size: const Size(320, 900),
        adminUser: const UserModel(
          id: 1,
          name: 'Administrator With A Fairly Long Display Name',
          email: 'administrator.with.a.very.long.email.address@example.com',
          role: 'admin',
          status: 'active',
        ),
      );

      expect(tester.takeException(), isNull);
    });

    testWidgets('renders correctly in Dark Mode', (tester) async {
      final repository = _FakeAdminDashboardRepository()..loadResult = _stats();

      await _pumpScreen(tester, repository: repository, dark: true);

      expect(tester.takeException(), isNull);
      // Semantic status is never color-only -- the real text labels are
      // still present in Dark Mode too.
      expect(find.text('Pending'), findsOneWidget);
      expect(find.text('Approved'), findsOneWidget);
      expect(find.text('Rejected'), findsOneWidget);
    });

    testWidgets('honors reduced motion without throwing', (tester) async {
      final repository = _FakeAdminDashboardRepository()..loadResult = _stats();

      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);

      await _pumpScreen(tester, repository: repository);

      expect(tester.takeException(), isNull);
      expect(find.text('Overview'), findsOneWidget);
    });
  });

  group('semantic status (Admin Dashboard Final UI Polish)', () {
    testWidgets(
      'every metric exposes a screen-reader label pairing its name and '
      'real value',
      (tester) async {
        final repository = _FakeAdminDashboardRepository()
          ..loadResult = _stats(pendingOrganizations: 3);
        await _pumpScreen(tester, repository: repository);

        // Asserts on the `Semantics` widget's own declared `label`
        // property directly, rather than the rendered/merged
        // `SemanticsNode` tree (which combines a `Semantics` label with
        // its Text children's own auto-generated semantics in ways that
        // are an unrelated implementation detail, not what this test
        // cares about).
        final labels = tester
            .widgetList<Semantics>(find.byType(Semantics))
            .map((s) => s.properties.label)
            .whereType<String>()
            .toSet();

        expect(labels, contains('Pending, 3'));
        expect(labels, contains('Approved, 4'));
        expect(labels, contains('Rejected, 1'));
      },
    );

    testWidgets(
      'a nonzero Pending Organizations count still shows the real text '
      'label, not color alone',
      (tester) async {
        final repository = _FakeAdminDashboardRepository()
          ..loadResult = _stats(pendingOrganizations: 5);
        await _pumpScreen(tester, repository: repository);

        expect(find.text('Pending'), findsOneWidget);
        expect(find.text('5'), findsOneWidget);
      },
    );

    testWidgets('a zero Pending Organizations count renders normally too', (
      tester,
    ) async {
      final repository = _FakeAdminDashboardRepository()
        ..loadResult = _stats(pendingOrganizations: 0);
      await _pumpScreen(tester, repository: repository);

      expect(find.text('Pending'), findsOneWidget);
      expect(find.text('0'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
