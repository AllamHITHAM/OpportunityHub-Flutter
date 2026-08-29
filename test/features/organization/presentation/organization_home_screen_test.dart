// Widget tests for the redesigned OrganizationHomeScreen — real dashboard
// statistics, verification banner, quick actions, and the notification
// bell, in isolation with a small GoRouter.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'package:opportunityhub_flutter/core/api/api_client.dart';
import 'package:opportunityhub_flutter/core/storage/token_storage_service.dart';
import 'package:opportunityhub_flutter/core/theme/app_theme.dart';
import 'package:opportunityhub_flutter/features/auth/data/auth_repository.dart';
import 'package:opportunityhub_flutter/features/messaging/data/conversation_repository.dart';
import 'package:opportunityhub_flutter/features/notifications/data/notification_repository.dart';
import 'package:opportunityhub_flutter/features/organization/data/organization_dashboard_repository.dart';
import 'package:opportunityhub_flutter/features/organization/data/organization_profile_repository.dart';
import 'package:opportunityhub_flutter/features/notifications/presentation/notification_bell_action.dart';
import 'package:opportunityhub_flutter/features/organization/presentation/organization_home_screen.dart';
import 'package:opportunityhub_flutter/models/conversation_model.dart';
import 'package:opportunityhub_flutter/models/notification_model.dart';
import 'package:opportunityhub_flutter/models/organization_dashboard_stats_model.dart';
import 'package:opportunityhub_flutter/models/organization_profile_model.dart';
import 'package:opportunityhub_flutter/models/user_model.dart';
import 'package:opportunityhub_flutter/providers/auth_provider.dart';
import 'package:opportunityhub_flutter/providers/conversations_provider.dart';
import 'package:opportunityhub_flutter/providers/notification_provider.dart';
import 'package:opportunityhub_flutter/providers/organization_dashboard_provider.dart';
import 'package:opportunityhub_flutter/providers/organization_profile_provider.dart';
import 'package:opportunityhub_flutter/providers/theme_provider.dart';
import 'package:opportunityhub_flutter/routes/app_routes.dart';

class _FakeAuthRepository extends AuthRepository {
  _FakeAuthRepository()
    : super(
        apiClient: ApiClient(tokenStorageService: TokenStorageService()),
        tokenStorageService: TokenStorageService(),
      );

  int logoutCallCount = 0;

  @override
  Future<String?> getSavedToken() async => null;

  @override
  Future<void> logout() async {
    logoutCallCount++;
  }
}

class _FakeNotificationRepository extends NotificationRepository {
  _FakeNotificationRepository({this.listResult = const []})
    : super(apiClient: ApiClient(tokenStorageService: TokenStorageService()));

  List<NotificationModel> listResult;

  @override
  Future<List<NotificationModel>> getNotifications() async => listResult;
}

class _FakeConversationRepository extends ConversationRepository {
  _FakeConversationRepository()
    : super(apiClient: ApiClient(tokenStorageService: TokenStorageService()));

  @override
  Future<List<ConversationSummaryModel>> getConversations() async => [];
}

class _FakeOrganizationDashboardRepository
    extends OrganizationDashboardRepository {
  _FakeOrganizationDashboardRepository()
    : super(apiClient: ApiClient(tokenStorageService: TokenStorageService()));

  OrganizationDashboardStatsModel? statsResult;
  ApiException? statsError;
  Duration delay = Duration.zero;
  int callCount = 0;

  @override
  Future<OrganizationDashboardStatsModel> getDashboardStats() async {
    callCount++;
    if (delay > Duration.zero) {
      await Future<void>.delayed(delay);
    }
    if (statsError != null) throw statsError!;
    return statsResult!;
  }
}

class _FakeOrganizationProfileRepository extends OrganizationProfileRepository {
  _FakeOrganizationProfileRepository()
    : super(apiClient: ApiClient(tokenStorageService: TokenStorageService()));

  OrganizationProfileModel? profileResult;

  @override
  Future<OrganizationProfileModel?> getProfile() async => profileResult;
}

NotificationModel _notification({int id = 1, bool isRead = false}) {
  return NotificationModel(
    id: id,
    userId: 1,
    title: 'Notice',
    message: 'A notification.',
    priority: 'normal',
    type: 'system',
    isRead: isRead,
  );
}

OrganizationDashboardStatsModel _stats({
  int totalOpportunities = 5,
  int openOpportunities = 3,
  int closedOpportunities = 1,
  int draftOpportunities = 1,
  int totalApplications = 20,
  int pendingApplications = 4,
  int shortlistedApplications = 6,
  int offerSentApplications = 2,
  int acceptedApplications = 3,
  int rejectedApplications = 5,
  int totalInterviews = 8,
  int completedInterviews = 5,
}) {
  return OrganizationDashboardStatsModel(
    totalOpportunities: totalOpportunities,
    openOpportunities: openOpportunities,
    closedOpportunities: closedOpportunities,
    draftOpportunities: draftOpportunities,
    totalApplications: totalApplications,
    pendingApplications: pendingApplications,
    shortlistedApplications: shortlistedApplications,
    offerSentApplications: offerSentApplications,
    acceptedApplications: acceptedApplications,
    rejectedApplications: rejectedApplications,
    totalInterviews: totalInterviews,
    completedInterviews: completedInterviews,
  );
}

OrganizationProfileModel _profile({
  String organizationName = 'Acme Technologies',
  String organizationType = 'company',
  String? industry = 'Software',
}) {
  return OrganizationProfileModel(
    id: 1,
    organizationName: organizationName,
    organizationType: organizationType,
    approvalStatus: 'approved',
    industry: industry,
  );
}

class _Providers {
  _Providers({
    required this.auth,
    required this.dashboard,
    required this.profile,
  });

  final AuthProvider auth;
  final OrganizationDashboardProvider dashboard;
  final OrganizationProfileProvider profile;
}

Future<_Providers> _pumpScreen(
  WidgetTester tester, {
  required _FakeNotificationRepository notificationRepository,
  required _FakeOrganizationDashboardRepository dashboardRepository,
  _FakeOrganizationProfileRepository? profileRepository,
  bool emailVerified = true,
  Size size = const Size(420, 1600),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final authProvider = AuthProvider(authRepository: _FakeAuthRepository())
    ..user = UserModel(
      id: 1,
      name: 'Ola Org',
      email: 'ola@example.com',
      role: 'organization',
      status: 'active',
      emailVerified: emailVerified,
    );
  final notificationProvider = NotificationProvider(
    repository: notificationRepository,
    authProvider: authProvider,
  );
  // MessagesBellAction now renders unconditionally next to
  // NotificationBellAction in the AppBar.
  final conversationsProvider = ConversationsProvider(
    repository: _FakeConversationRepository(),
    authProvider: authProvider,
  );
  final dashboardProvider = OrganizationDashboardProvider(
    repository: dashboardRepository,
    authProvider: authProvider,
  );
  final profileProvider = OrganizationProfileProvider(
    repository: profileRepository ?? _FakeOrganizationProfileRepository(),
    authProvider: authProvider,
  );

  final router = GoRouter(
    initialLocation: AppRoutes.organizationHome,
    routes: [
      GoRoute(
        path: AppRoutes.organizationHome,
        builder: (_, _) => const OrganizationHomeScreen(),
      ),
      GoRoute(
        path: AppRoutes.notifications,
        builder: (_, _) => const Scaffold(body: Text('NOTIFICATIONS_SCREEN')),
      ),
      GoRoute(
        path: AppRoutes.organizationOpportunityCreate,
        builder: (_, _) =>
            const Scaffold(body: Text('CREATE_OPPORTUNITY_SCREEN')),
      ),
      GoRoute(
        path: AppRoutes.organizationOpportunities,
        builder: (_, _) =>
            const Scaffold(body: Text('MANAGE_OPPORTUNITIES_SCREEN')),
      ),
      GoRoute(
        path: AppRoutes.organizationCandidates,
        builder: (_, _) => const Scaffold(body: Text('FIND_CANDIDATES_SCREEN')),
      ),
    ],
  );

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthProvider>.value(value: authProvider),
        ChangeNotifierProvider<NotificationProvider>.value(
          value: notificationProvider,
        ),
        ChangeNotifierProvider<ConversationsProvider>.value(
          value: conversationsProvider,
        ),
        ChangeNotifierProvider<OrganizationDashboardProvider>.value(
          value: dashboardProvider,
        ),
        ChangeNotifierProvider<OrganizationProfileProvider>.value(
          value: profileProvider,
        ),
        ChangeNotifierProvider<ThemeProvider>.value(value: ThemeProvider()),
      ],
      child: MaterialApp.router(
        theme: AppTheme.lightTheme,
        routerConfig: router,
      ),
    ),
  );
  await tester.pumpAndSettle();

  return _Providers(
    auth: authProvider,
    dashboard: dashboardProvider,
    profile: profileProvider,
  );
}

void main() {
  group('loading / error / retry', () {
    testWidgets('shows a spinner while the dashboard is loading', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(420, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final authProvider = AuthProvider(authRepository: _FakeAuthRepository())
        ..user = const UserModel(
          id: 1,
          name: 'Ola Org',
          email: 'ola@example.com',
          role: 'organization',
          status: 'active',
        );
      final dashboardRepository = _FakeOrganizationDashboardRepository()
        ..statsResult = _stats()
        ..delay = const Duration(milliseconds: 100);
      final dashboardProvider = OrganizationDashboardProvider(
        repository: dashboardRepository,
        authProvider: authProvider,
      );
      final profileProvider = OrganizationProfileProvider(
        repository: _FakeOrganizationProfileRepository(),
        authProvider: authProvider,
      );
      final notificationProvider = NotificationProvider(
        repository: _FakeNotificationRepository(),
        authProvider: authProvider,
      );
      // MessagesBellAction now renders unconditionally next to
      // NotificationBellAction in the AppBar.
      final conversationsProvider = ConversationsProvider(
        repository: _FakeConversationRepository(),
        authProvider: authProvider,
      );

      final router = GoRouter(
        initialLocation: AppRoutes.organizationHome,
        routes: [
          GoRoute(
            path: AppRoutes.organizationHome,
            builder: (_, _) => const OrganizationHomeScreen(),
          ),
        ],
      );

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<AuthProvider>.value(value: authProvider),
            ChangeNotifierProvider<NotificationProvider>.value(
              value: notificationProvider,
            ),
            ChangeNotifierProvider<ConversationsProvider>.value(
              value: conversationsProvider,
            ),
            ChangeNotifierProvider<OrganizationDashboardProvider>.value(
              value: dashboardProvider,
            ),
            ChangeNotifierProvider<OrganizationProfileProvider>.value(
              value: profileProvider,
            ),
            ChangeNotifierProvider<ThemeProvider>.value(value: ThemeProvider()),
          ],
          child: MaterialApp.router(
            theme: AppTheme.lightTheme,
            routerConfig: router,
          ),
        ),
      );
      // Deliberately not pumpAndSettle -- catches the loading frame before
      // the (artificially delayed) load resolves.
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      await tester.pumpAndSettle();
    });

    testWidgets('an initial load failure shows a full error with retry', (
      tester,
    ) async {
      final dashboardRepository = _FakeOrganizationDashboardRepository()
        ..statsError = ApiException('Something went wrong');

      await _pumpScreen(
        tester,
        notificationRepository: _FakeNotificationRepository(),
        dashboardRepository: dashboardRepository,
      );

      expect(find.text('Something went wrong'), findsOneWidget);
      expect(find.text('Try Again'), findsOneWidget);

      dashboardRepository.statsError = null;
      dashboardRepository.statsResult = _stats();
      await tester.tap(find.text('Try Again'));
      await tester.pumpAndSettle();

      expect(find.text('Something went wrong'), findsNothing);
      expect(find.text('Opportunities'), findsOneWidget);
    });

    testWidgets(
      'a refresh failure after a successful load keeps the existing stats visible with a compact retry',
      (tester) async {
        final dashboardRepository = _FakeOrganizationDashboardRepository()
          ..statsResult = _stats(totalOpportunities: 7);

        final providers = await _pumpScreen(
          tester,
          notificationRepository: _FakeNotificationRepository(),
          dashboardRepository: dashboardRepository,
        );

        dashboardRepository.statsError = ApiException('Refresh failed');
        await providers.dashboard.load(forceRefresh: true);
        await tester.pumpAndSettle();

        expect(find.text('Refresh Failed'), findsOneWidget);
        expect(find.text('7'), findsOneWidget);
      },
    );
  });

  group('real dashboard data', () {
    testWidgets('renders every real Opportunities/Applications/Interviews metric', (
      tester,
    ) async {
      final dashboardRepository = _FakeOrganizationDashboardRepository()
        ..statsResult = _stats(
          totalOpportunities: 11,
          openOpportunities: 12,
          closedOpportunities: 13,
          draftOpportunities: 14,
          totalApplications: 21,
          pendingApplications: 22,
          shortlistedApplications: 23,
          offerSentApplications: 24,
          acceptedApplications: 25,
          rejectedApplications: 26,
          totalInterviews: 31,
          completedInterviews: 32,
        );

      await _pumpScreen(
        tester,
        notificationRepository: _FakeNotificationRepository(),
        dashboardRepository: dashboardRepository,
      );

      expect(find.text('Opportunities'), findsOneWidget);
      expect(find.text('Applications'), findsOneWidget);
      expect(find.text('Interviews'), findsOneWidget);

      expect(find.text('11'), findsOneWidget);
      expect(find.text('12'), findsOneWidget);
      expect(find.text('13'), findsOneWidget);
      expect(find.text('14'), findsOneWidget);
      expect(find.text('21'), findsOneWidget);
      expect(find.text('22'), findsOneWidget);
      expect(find.text('23'), findsOneWidget);
      expect(find.text('24'), findsOneWidget);
      expect(find.text('25'), findsOneWidget);
      expect(find.text('26'), findsOneWidget);
      expect(find.text('31'), findsOneWidget);
      expect(find.text('32'), findsOneWidget);

      expect(find.text('Total'), findsWidgets);
      expect(find.text('Open'), findsOneWidget);
      expect(find.text('Closed'), findsOneWidget);
      expect(find.text('Draft'), findsOneWidget);
      expect(find.text('Pending Review'), findsOneWidget);
      expect(find.text('Shortlisted'), findsOneWidget);
      expect(find.text('Offer Sent'), findsOneWidget);
      expect(find.text('Accepted'), findsOneWidget);
      expect(find.text('Rejected'), findsOneWidget);
      expect(find.text('Completed'), findsOneWidget);

      // No invented metric ever appears.
      expect(find.text('Candidates in Assessment'), findsNothing);
      expect(find.text('Decisions Required'), findsNothing);
    });

    testWidgets('zero values render as real 0s, not hidden or blank', (
      tester,
    ) async {
      final dashboardRepository = _FakeOrganizationDashboardRepository()
        ..statsResult = _stats(
          totalOpportunities: 0,
          openOpportunities: 0,
          closedOpportunities: 0,
          draftOpportunities: 0,
          totalApplications: 0,
          pendingApplications: 0,
          shortlistedApplications: 0,
          offerSentApplications: 0,
          acceptedApplications: 0,
          rejectedApplications: 0,
          totalInterviews: 0,
          completedInterviews: 0,
        );

      await _pumpScreen(
        tester,
        notificationRepository: _FakeNotificationRepository(),
        dashboardRepository: dashboardRepository,
      );

      expect(find.text('0'), findsWidgets);
      expect(tester.takeException(), isNull);
    });

    testWidgets('shows the real organization name and type/industry context', (
      tester,
    ) async {
      final dashboardRepository = _FakeOrganizationDashboardRepository()
        ..statsResult = _stats();
      final profileRepository = _FakeOrganizationProfileRepository()
        ..profileResult = _profile(
          organizationName: 'Acme Technologies',
          organizationType: 'company',
          industry: 'Software',
        );

      await _pumpScreen(
        tester,
        notificationRepository: _FakeNotificationRepository(),
        dashboardRepository: dashboardRepository,
        profileRepository: profileRepository,
      );

      expect(find.text('Welcome, Acme Technologies'), findsOneWidget);
      expect(find.text('Company · Software'), findsOneWidget);
    });

    testWidgets(
      'falls back to the user name when the organization profile has not loaded',
      (tester) async {
        final dashboardRepository = _FakeOrganizationDashboardRepository()
          ..statsResult = _stats();
        final profileRepository = _FakeOrganizationProfileRepository()
          ..profileResult = null;

        await _pumpScreen(
          tester,
          notificationRepository: _FakeNotificationRepository(),
          dashboardRepository: dashboardRepository,
          profileRepository: profileRepository,
        );

        expect(find.text('Welcome, Ola Org'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  });

  group('email verification', () {
    testWidgets('shows the compact warning and Resend for an unverified user', (
      tester,
    ) async {
      final dashboardRepository = _FakeOrganizationDashboardRepository()
        ..statsResult = _stats();

      await _pumpScreen(
        tester,
        notificationRepository: _FakeNotificationRepository(),
        dashboardRepository: dashboardRepository,
        emailVerified: false,
      );

      expect(find.text('Email not verified'), findsOneWidget);
      expect(find.text('Resend'), findsOneWidget);
    });

    testWidgets('shows no verification warning for an already-verified user', (
      tester,
    ) async {
      final dashboardRepository = _FakeOrganizationDashboardRepository()
        ..statsResult = _stats();

      await _pumpScreen(
        tester,
        notificationRepository: _FakeNotificationRepository(),
        dashboardRepository: dashboardRepository,
        emailVerified: true,
      );

      expect(find.text('Email not verified'), findsNothing);
    });
  });

  group('quick actions', () {
    testWidgets('Create Opportunity navigates to the real creation route', (
      tester,
    ) async {
      final dashboardRepository = _FakeOrganizationDashboardRepository()
        ..statsResult = _stats();

      await _pumpScreen(
        tester,
        notificationRepository: _FakeNotificationRepository(),
        dashboardRepository: dashboardRepository,
      );

      await tester.tap(find.text('Create Opportunity'));
      await tester.pumpAndSettle();

      expect(find.text('CREATE_OPPORTUNITY_SCREEN'), findsOneWidget);
    });

    testWidgets('Manage Opportunities navigates to the real management route', (
      tester,
    ) async {
      final dashboardRepository = _FakeOrganizationDashboardRepository()
        ..statsResult = _stats();

      await _pumpScreen(
        tester,
        notificationRepository: _FakeNotificationRepository(),
        dashboardRepository: dashboardRepository,
      );

      await tester.tap(find.text('Manage Opportunities'));
      await tester.pumpAndSettle();

      expect(find.text('MANAGE_OPPORTUNITIES_SCREEN'), findsOneWidget);
    });

    testWidgets('Browse Talent navigates to the real candidates route', (
      tester,
    ) async {
      final dashboardRepository = _FakeOrganizationDashboardRepository()
        ..statsResult = _stats();

      await _pumpScreen(
        tester,
        notificationRepository: _FakeNotificationRepository(),
        dashboardRepository: dashboardRepository,
      );

      await tester.tap(find.text('Browse Talent'));
      await tester.pumpAndSettle();

      expect(find.text('FIND_CANDIDATES_SCREEN'), findsOneWidget);
    });

    testWidgets('Logout is visually secondary but still works', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(420, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final authRepository = _FakeAuthRepository();
      final authProvider = AuthProvider(authRepository: authRepository)
        ..user = const UserModel(
          id: 1,
          name: 'Ola Org',
          email: 'ola@example.com',
          role: 'organization',
          status: 'active',
        );
      final dashboardProvider = OrganizationDashboardProvider(
        repository: _FakeOrganizationDashboardRepository()
          ..statsResult = _stats(),
        authProvider: authProvider,
      );
      final profileProvider = OrganizationProfileProvider(
        repository: _FakeOrganizationProfileRepository(),
        authProvider: authProvider,
      );
      final notificationProvider = NotificationProvider(
        repository: _FakeNotificationRepository(),
        authProvider: authProvider,
      );
      // MessagesBellAction now renders unconditionally next to
      // NotificationBellAction in the AppBar.
      final conversationsProvider = ConversationsProvider(
        repository: _FakeConversationRepository(),
        authProvider: authProvider,
      );

      final router = GoRouter(
        initialLocation: AppRoutes.organizationHome,
        routes: [
          GoRoute(
            path: AppRoutes.organizationHome,
            builder: (_, _) => const OrganizationHomeScreen(),
          ),
        ],
      );

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<AuthProvider>.value(value: authProvider),
            ChangeNotifierProvider<NotificationProvider>.value(
              value: notificationProvider,
            ),
            ChangeNotifierProvider<ConversationsProvider>.value(
              value: conversationsProvider,
            ),
            ChangeNotifierProvider<OrganizationDashboardProvider>.value(
              value: dashboardProvider,
            ),
            ChangeNotifierProvider<OrganizationProfileProvider>.value(
              value: profileProvider,
            ),
            ChangeNotifierProvider<ThemeProvider>.value(value: ThemeProvider()),
          ],
          child: MaterialApp.router(
            theme: AppTheme.lightTheme,
            routerConfig: router,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Not a large ElevatedButton -- a small, secondary TextButton.
      expect(find.widgetWithText(ElevatedButton, 'Logout'), findsNothing);
      final logoutFinder = find.widgetWithText(TextButton, 'Logout');
      expect(logoutFinder, findsOneWidget);

      await tester.tap(logoutFinder);
      // Deliberately plain pump() calls, never pumpAndSettle(): once
      // AuthProvider.user goes null, every dependent provider resets and
      // this screen falls back to its indeterminate AppLoading spinner
      // (nothing re-triggers a real load afterward in this bare test
      // router, unlike the real app, where the router's own redirect
      // immediately navigates away from this screen on logout) -- an
      // indeterminate CircularProgressIndicator never settles.
      await tester.pump();
      await tester.pump();

      expect(authRepository.logoutCallCount, 1);
    });
  });

  group('notification bell (preserved)', () {
    testWidgets('is present in the AppBar', (tester) async {
      final dashboardRepository = _FakeOrganizationDashboardRepository()
        ..statsResult = _stats();

      await _pumpScreen(
        tester,
        notificationRepository: _FakeNotificationRepository(),
        dashboardRepository: dashboardRepository,
      );

      expect(find.byIcon(Icons.notifications_outlined), findsOneWidget);
    });

    testWidgets('shows the unread count badge', (tester) async {
      // Deliberately avoids any dashboard metric equal to the unread count
      // (2) below, so the badge's own "2" is unambiguous.
      final dashboardRepository = _FakeOrganizationDashboardRepository()
        ..statsResult = _stats(
          totalOpportunities: 51,
          openOpportunities: 52,
          closedOpportunities: 53,
          draftOpportunities: 54,
          totalApplications: 55,
          pendingApplications: 56,
          shortlistedApplications: 57,
          offerSentApplications: 58,
          acceptedApplications: 59,
          rejectedApplications: 60,
          totalInterviews: 61,
          completedInterviews: 62,
        );

      await _pumpScreen(
        tester,
        notificationRepository: _FakeNotificationRepository(
          listResult: [
            _notification(id: 1, isRead: false),
            _notification(id: 2, isRead: true),
            _notification(id: 3, isRead: false),
          ],
        ),
        dashboardRepository: dashboardRepository,
      );

      // Scoped to the notification bell specifically -- MessagesBellAction
      // now renders its own separate Badge alongside it in the AppBar
      // (hidden, since this test's fake ConversationRepository returns no
      // conversations), so a bare `find.byType(Badge)` would match two
      // widgets.
      final badge = tester.widget<Badge>(
        find.descendant(
          of: find.byType(NotificationBellAction),
          matching: find.byType(Badge),
        ),
      );
      expect(badge.isLabelVisible, isTrue);
      expect(find.text('2'), findsOneWidget);
    });

    testWidgets('tapping the bell opens the Notifications screen', (
      tester,
    ) async {
      final dashboardRepository = _FakeOrganizationDashboardRepository()
        ..statsResult = _stats();

      await _pumpScreen(
        tester,
        notificationRepository: _FakeNotificationRepository(),
        dashboardRepository: dashboardRepository,
      );

      await tester.tap(find.byIcon(Icons.notifications_outlined));
      await tester.pumpAndSettle();

      expect(find.text('NOTIFICATIONS_SCREEN'), findsOneWidget);
    });
  });

  group('responsive / theming / motion', () {
    testWidgets('desktop viewport (>=1200) renders without overflow', (
      tester,
    ) async {
      final dashboardRepository = _FakeOrganizationDashboardRepository()
        ..statsResult = _stats();

      await _pumpScreen(
        tester,
        notificationRepository: _FakeNotificationRepository(),
        dashboardRepository: dashboardRepository,
        size: const Size(1400, 900),
      );

      expect(tester.takeException(), isNull);
    });

    testWidgets('900-1199 viewport renders without overflow', (tester) async {
      final dashboardRepository = _FakeOrganizationDashboardRepository()
        ..statsResult = _stats();

      await _pumpScreen(
        tester,
        notificationRepository: _FakeNotificationRepository(),
        dashboardRepository: dashboardRepository,
        size: const Size(1000, 900),
      );

      expect(tester.takeException(), isNull);
    });

    testWidgets('600-899 (tablet) viewport renders without overflow', (
      tester,
    ) async {
      final dashboardRepository = _FakeOrganizationDashboardRepository()
        ..statsResult = _stats();

      await _pumpScreen(
        tester,
        notificationRepository: _FakeNotificationRepository(),
        dashboardRepository: dashboardRepository,
        size: const Size(700, 900),
      );

      expect(tester.takeException(), isNull);
    });

    testWidgets('375-430 (mobile) viewport renders without overflow', (
      tester,
    ) async {
      final dashboardRepository = _FakeOrganizationDashboardRepository()
        ..statsResult = _stats();

      await _pumpScreen(
        tester,
        notificationRepository: _FakeNotificationRepository(),
        dashboardRepository: dashboardRepository,
        size: const Size(375, 812),
      );

      expect(tester.takeException(), isNull);
    });

    testWidgets('renders correctly in Dark Mode', (tester) async {
      final dashboardRepository = _FakeOrganizationDashboardRepository()
        ..statsResult = _stats();

      tester.view.physicalSize = const Size(420, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final authProvider = AuthProvider(authRepository: _FakeAuthRepository())
        ..user = const UserModel(
          id: 1,
          name: 'Ola Org',
          email: 'ola@example.com',
          role: 'organization',
          status: 'active',
        );
      final dashboardProvider = OrganizationDashboardProvider(
        repository: dashboardRepository,
        authProvider: authProvider,
      );
      final profileProvider = OrganizationProfileProvider(
        repository: _FakeOrganizationProfileRepository(),
        authProvider: authProvider,
      );
      final notificationProvider = NotificationProvider(
        repository: _FakeNotificationRepository(),
        authProvider: authProvider,
      );
      // MessagesBellAction now renders unconditionally next to
      // NotificationBellAction in the AppBar.
      final conversationsProvider = ConversationsProvider(
        repository: _FakeConversationRepository(),
        authProvider: authProvider,
      );

      final router = GoRouter(
        initialLocation: AppRoutes.organizationHome,
        routes: [
          GoRoute(
            path: AppRoutes.organizationHome,
            builder: (_, _) => const OrganizationHomeScreen(),
          ),
        ],
      );

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<AuthProvider>.value(value: authProvider),
            ChangeNotifierProvider<NotificationProvider>.value(
              value: notificationProvider,
            ),
            ChangeNotifierProvider<ConversationsProvider>.value(
              value: conversationsProvider,
            ),
            ChangeNotifierProvider<OrganizationDashboardProvider>.value(
              value: dashboardProvider,
            ),
            ChangeNotifierProvider<OrganizationProfileProvider>.value(
              value: profileProvider,
            ),
            ChangeNotifierProvider<ThemeProvider>.value(value: ThemeProvider()),
          ],
          child: MaterialApp.router(
            theme: AppTheme.darkTheme,
            routerConfig: router,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Opportunities'), findsOneWidget);
    });

    testWidgets('honors reduced motion without throwing', (tester) async {
      final dashboardRepository = _FakeOrganizationDashboardRepository()
        ..statsResult = _stats();

      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);

      await _pumpScreen(
        tester,
        notificationRepository: _FakeNotificationRepository(),
        dashboardRepository: dashboardRepository,
      );

      expect(tester.takeException(), isNull);
      expect(find.text('Opportunities'), findsOneWidget);
    });
  });
}
