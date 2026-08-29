// Router-level tests for the `/reset-password` public route.
//
// A password-reset link opened directly by URL (e.g. from an email client)
// was landing on Login instead of the Reset Password screen. The actual
// root cause was Flutter Web defaulting to hash-based URLs
// (`#/reset-password?...`): a clean path link never reached GoRouter as
// `/reset-password` at all, so no redirect/guard logic in `AppRouter` was
// ever even evaluated against it -- the app booted at `/` and the link's
// `token`/`email` query was lost before any routing decision was made. The
// fix is `usePathUrlStrategy()` in `main()` (see `lib/main.dart`); no
// change was needed in `AppRouter`'s redirect/guard logic itself, which
// already serves `/reset-password` correctly once it's the location
// actually being requested -- these tests lock in that guard behavior via
// `router.go(...)`, the same direct-navigation pattern already used by
// every other file in this directory.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:opportunityhub_flutter/core/api/api_client.dart';
import 'package:opportunityhub_flutter/core/storage/token_storage_service.dart';
import 'package:opportunityhub_flutter/core/theme/app_theme.dart';
import 'package:opportunityhub_flutter/features/admin/data/admin_dashboard_repository.dart';
import 'package:opportunityhub_flutter/features/auth/data/auth_repository.dart';
import 'package:opportunityhub_flutter/features/cv/data/cv_repository.dart';
import 'package:opportunityhub_flutter/features/messaging/data/conversation_repository.dart';
import 'package:opportunityhub_flutter/features/notifications/data/notification_repository.dart';
import 'package:opportunityhub_flutter/features/organization/data/organization_dashboard_repository.dart';
import 'package:opportunityhub_flutter/features/organization/data/organization_profile_repository.dart';
import 'package:opportunityhub_flutter/features/organization/presentation/organization_home_screen.dart';
import 'package:opportunityhub_flutter/features/skills/data/student_skill_repository.dart';
import 'package:opportunityhub_flutter/features/student/data/student_profile_repository.dart';
import 'package:opportunityhub_flutter/models/admin_dashboard_stats_model.dart';
import 'package:opportunityhub_flutter/models/conversation_model.dart';
import 'package:opportunityhub_flutter/models/cv_model.dart';
import 'package:opportunityhub_flutter/models/notification_model.dart';
import 'package:opportunityhub_flutter/models/organization_dashboard_stats_model.dart';
import 'package:opportunityhub_flutter/models/organization_profile_model.dart';
import 'package:opportunityhub_flutter/models/student_profile_model.dart';
import 'package:opportunityhub_flutter/models/user_model.dart';
import 'package:opportunityhub_flutter/providers/admin_dashboard_provider.dart';
import 'package:opportunityhub_flutter/providers/auth_provider.dart';
import 'package:opportunityhub_flutter/providers/conversations_provider.dart';
import 'package:opportunityhub_flutter/providers/notification_provider.dart';
import 'package:opportunityhub_flutter/providers/organization_dashboard_provider.dart';
import 'package:opportunityhub_flutter/providers/organization_profile_provider.dart';
import 'package:opportunityhub_flutter/providers/student_cv_provider.dart';
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

class _FakeCvRepository extends CvRepository {
  _FakeCvRepository()
    : super(apiClient: ApiClient(tokenStorageService: TokenStorageService()));

  @override
  Future<List<CvModel>> getStudentCvs() async => [];
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

void _setViewSize(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

class _Harness {
  _Harness({required this.appRouter, required this.authProvider});

  final AppRouter appRouter;
  final AuthProvider authProvider;
}

/// Builds the real [AppRouter] (not a bespoke test router) with no saved
/// session, matching a fresh, unauthenticated browser tab. Mirrors the
/// "Unauthenticated users are redirected to login" setup already used
/// throughout `test/routes/*_router_test.dart`, including the
/// `.go(initialPath)`-before-`initialize()` ordering, which is exactly
/// what reproduces "a direct URL visit arrives while the startup session
/// check is still pending" -- the scenario this fix targets.
Future<_Harness> _pumpUnauthenticated(
  WidgetTester tester, {
  required String initialPath,
}) async {
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
  final cvProvider = StudentCvProvider(
    repository: _FakeCvRepository(),
    studentSkillRepository: StudentSkillRepository(
      apiClient: ApiClient(tokenStorageService: TokenStorageService()),
    ),
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
        ChangeNotifierProvider<StudentCvProvider>.value(value: cvProvider),
        ChangeNotifierProvider<ThemeProvider>.value(value: ThemeProvider()),
      ],
      child: MaterialApp.router(
        theme: AppTheme.lightTheme,
        routerConfig: appRouter.router,
      ),
    ),
  );

  // Simulates a direct URL visit (e.g. clicking an email link): the
  // navigation request arrives while the startup session check
  // (`authProvider.initialize()`) is still pending, not after.
  appRouter.router.go(initialPath);
  await authProvider.initialize();
  await tester.pumpAndSettle();

  return _Harness(appRouter: appRouter, authProvider: authProvider);
}

/// Pumps the full app, authenticated as [role] with a saved token
/// (simulating a returning user), and navigates straight to [initialPath].
/// Mirrors the identical helper already used across the other
/// `test/routes/*_router_test.dart` files.
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
  final cvProvider = StudentCvProvider(
    repository: _FakeCvRepository(),
    studentSkillRepository: StudentSkillRepository(
      apiClient: ApiClient(tokenStorageService: TokenStorageService()),
    ),
    authProvider: authProvider,
  );
  final adminDashboardProvider = AdminDashboardProvider(
    repository: _FakeAdminDashboardRepository(),
    authProvider: authProvider,
  );
  final organizationDashboardProvider = OrganizationDashboardProvider(
    repository: _FakeOrganizationDashboardRepository(),
    authProvider: authProvider,
  );
  final notificationProvider = NotificationProvider(
    repository: _FakeNotificationRepository(),
    authProvider: authProvider,
  );
  // MessagesBellAction now renders unconditionally next to
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
        ChangeNotifierProvider<StudentCvProvider>.value(value: cvProvider),
        ChangeNotifierProvider<NotificationProvider>.value(
          value: notificationProvider,
        ),
        ChangeNotifierProvider<ConversationsProvider>.value(
          value: conversationsProvider,
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
  testWidgets(
    'An unauthenticated direct visit to a valid reset-password URL opens '
    'the Reset Password screen instead of redirecting to Login',
    (tester) async {
      final harness = await _pumpUnauthenticated(
        tester,
        initialPath:
            '${AppRoutes.resetPassword}?token=real-token&email=jane%40example.com',
      );

      expect(harness.authProvider.isAuthenticated, isFalse);
      expect(find.text('Set a New Password'), findsOneWidget);
      expect(find.text('Login'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'The token and email query parameters reach ResetPasswordScreen',
    (tester) async {
      await _pumpUnauthenticated(
        tester,
        initialPath:
            '${AppRoutes.resetPassword}?token=real-token&email=jane%40example.com',
      );

      // The screen shows the email read-only and only renders the New/
      // Confirm Password form (rather than the invalid-link state) when it
      // actually received a non-empty token too.
      expect(find.text('jane@example.com'), findsOneWidget);
      expect(find.text('New Password'), findsOneWidget);
      expect(find.text('Confirm Password'), findsOneWidget);
      expect(find.text('Invalid Reset Link'), findsNothing);
    },
  );

  testWidgets(
    'A reset-password URL missing the token renders the safe invalid-link '
    'state, not a redirect to Login',
    (tester) async {
      final harness = await _pumpUnauthenticated(
        tester,
        initialPath: '${AppRoutes.resetPassword}?email=jane%40example.com',
      );

      expect(find.text('Invalid Reset Link'), findsOneWidget);
      expect(find.text('Login'), findsNothing);
      expect(harness.authProvider.isAuthenticated, isFalse);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'A reset-password URL with no query parameters at all renders the safe '
    'invalid-link state, not a redirect to Login',
    (tester) async {
      await _pumpUnauthenticated(tester, initialPath: AppRoutes.resetPassword);

      expect(find.text('Invalid Reset Link'), findsOneWidget);
      expect(find.text('Login'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'forgot-password remains reachable unauthenticated, unaffected by the fix',
    (tester) async {
      await _pumpUnauthenticated(
        tester,
        initialPath: AppRoutes.forgotPassword,
      );

      expect(find.text('Send Reset Link'), findsOneWidget);
      expect(find.text('Login'), findsNothing);
    },
  );

  testWidgets(
    'An unauthenticated direct visit to a PROTECTED route is still sent to '
    'Login -- the fix does not weaken that guard',
    (tester) async {
      final harness = await _pumpUnauthenticated(
        tester,
        initialPath: AppRoutes.studentCvs,
      );

      expect(harness.authProvider.isAuthenticated, isFalse);
      expect(find.text('My CVs'), findsNothing);
      expect(find.text('Login'), findsWidgets);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'An authenticated student is still routed normally -- protected-route '
    'behavior for signed-in users is unaffected by the fix',
    (tester) async {
      await _pumpAsRole(
        tester,
        role: 'student',
        initialPath: AppRoutes.studentCvs,
        studentProfile: _completeProfile,
      );

      // "My CVs" now legitimately appears twice — the AppBar title and the
      // premium screen's own page header (UI Phase 6) — not a duplicate-
      // rendering bug.
      expect(find.text('My CVs'), findsWidgets);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'An authenticated organization still cannot open a student-only route '
    '-- role guards are unaffected by the fix',
    (tester) async {
      await _pumpAsRole(
        tester,
        role: 'organization',
        initialPath: AppRoutes.studentCvs,
      );

      expect(find.text('My CVs'), findsNothing);
      expect(find.byType(OrganizationHomeScreen), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'An authenticated admin still cannot open a student-only route -- role '
    'guards are unaffected by the fix',
    (tester) async {
      await _pumpAsRole(
        tester,
        role: 'admin',
        initialPath: AppRoutes.studentCvs,
      );

      expect(find.text('My CVs'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
