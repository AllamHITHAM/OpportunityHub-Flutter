// Widget/router tests for Step 2 of the two-step Student Registration UI
// (Phase 2B-4): student-profile information, submitted via a real (faked)
// POST /api/student/profile call.
//
// Step 2 no longer depends on a Step-1-created draft — it depends only on
// the authenticated session, so these tests exercise both the "just
// registered" path (Step 1 -> Step 2) and the "returning authenticated
// student opens Step 2 directly" path (cold start / browser refresh).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:opportunityhub_flutter/core/api/api_client.dart';
import 'package:opportunityhub_flutter/core/storage/token_storage_service.dart';
import 'package:opportunityhub_flutter/core/theme/app_theme.dart';
import 'package:opportunityhub_flutter/features/auth/data/auth_repository.dart';
import 'package:opportunityhub_flutter/features/notifications/data/notification_repository.dart';
import 'package:opportunityhub_flutter/features/organization/data/organization_profile_repository.dart';
import 'package:opportunityhub_flutter/features/student/data/student_profile_repository.dart';
import 'package:opportunityhub_flutter/models/notification_model.dart';
import 'package:opportunityhub_flutter/models/organization_profile_model.dart';
import 'package:opportunityhub_flutter/models/student_profile_model.dart';
import 'package:opportunityhub_flutter/models/user_model.dart';
import 'package:opportunityhub_flutter/providers/auth_provider.dart';
import 'package:opportunityhub_flutter/providers/notification_provider.dart';
import 'package:opportunityhub_flutter/providers/organization_profile_provider.dart';
import 'package:opportunityhub_flutter/providers/student_profile_provider.dart';
import 'package:opportunityhub_flutter/routes/app_router.dart';
import 'package:opportunityhub_flutter/routes/app_routes.dart';

/// A fake repository that never touches secure storage or the network.
///
/// [registerStudent] always succeeds. [savedToken]/[currentUser] let tests
/// simulate an already-authenticated returning student (cold start), and
/// [getCurrentUserError] simulates an invalid saved session.
class _FakeAuthRepository extends AuthRepository {
  _FakeAuthRepository({this.savedToken, this.currentUser})
    : super(
        apiClient: ApiClient(tokenStorageService: TokenStorageService()),
        tokenStorageService: TokenStorageService(),
      );

  String? savedToken;
  UserModel? currentUser;

  int registerStudentCallCount = 0;

  @override
  Future<String?> getSavedToken() async => savedToken;

  @override
  Future<UserModel> getCurrentUser() async => currentUser!;

  @override
  Future<UserModel> registerStudent({
    required String name,
    required String email,
    required String password,
  }) async {
    registerStudentCallCount++;
    return UserModel(
      id: 1,
      name: name,
      email: email,
      role: 'student',
      status: 'active',
    );
  }
}

/// A fake repository that never touches the network.
///
/// [createProfile] can be configured to succeed (the default), fail with a
/// given [ApiException], or wait for [createDelay] before resolving.
/// [getProfileResult] configures what a `GET /api/student/profile` call
/// (used both for cold-start detection and 409 verification) returns.
class _FakeStudentProfileRepository extends StudentProfileRepository {
  _FakeStudentProfileRepository({
    this.createDelay = Duration.zero,
    this.createError,
    this.getProfileResult,
    this.getProfileError,
  }) : super(apiClient: ApiClient(tokenStorageService: TokenStorageService()));

  final Duration createDelay;
  ApiException? createError;
  StudentProfileModel? getProfileResult;
  ApiException? getProfileError;

  int createProfileCallCount = 0;
  int getProfileCallCount = 0;
  Map<String, dynamic>? lastCreateProfilePayload;

  @override
  Future<StudentProfileModel> createProfile({
    required String university,
    required String major,
    required int graduationYear,
  }) async {
    createProfileCallCount++;
    lastCreateProfilePayload = {
      'university': university,
      'major': major,
      'graduation_year': graduationYear,
    };
    if (createDelay > Duration.zero) {
      await Future<void>.delayed(createDelay);
    }
    if (createError != null) throw createError!;
    return StudentProfileModel(
      id: 1,
      university: university,
      major: major,
      graduationYear: graduationYear,
    );
  }

  @override
  Future<StudentProfileModel?> getProfile() async {
    getProfileCallCount++;
    if (getProfileError != null) throw getProfileError!;
    return getProfileResult;
  }
}

/// A fake repository that never touches the network — unused by this
/// file's tests, but AppRouter requires an OrganizationProfileProvider.
class _FakeOrganizationProfileRepository extends OrganizationProfileRepository {
  _FakeOrganizationProfileRepository()
    : super(apiClient: ApiClient(tokenStorageService: TokenStorageService()));

  @override
  Future<OrganizationProfileModel?> getProfile() async => null;
}

/// A fake repository that never touches the network — unused by this
/// file's tests, but the Home screens' NotificationBellAction requires a
/// NotificationProvider wherever the router can land after registration.
class _FakeNotificationRepository extends NotificationRepository {
  _FakeNotificationRepository()
    : super(apiClient: ApiClient(tokenStorageService: TokenStorageService()));

  @override
  Future<List<NotificationModel>> getNotifications() async => [];
}

Widget _buildApp(
  AuthProvider authProvider,
  StudentProfileProvider studentProfileProvider,
  OrganizationProfileProvider organizationProfileProvider,
  AppRouter appRouter,
) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<AuthProvider>.value(value: authProvider),
      ChangeNotifierProvider<StudentProfileProvider>.value(
        value: studentProfileProvider,
      ),
      ChangeNotifierProvider<OrganizationProfileProvider>.value(
        value: organizationProfileProvider,
      ),
      ChangeNotifierProvider<NotificationProvider>(
        create: (_) => NotificationProvider(
          repository: _FakeNotificationRepository(),
          authProvider: authProvider,
        ),
      ),
    ],
    child: MaterialApp.router(
      theme: AppTheme.lightTheme,
      routerConfig: appRouter.router,
    ),
  );
}

const _formViewport = Size(420, 1400);

void _setViewSize(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> _enterText(WidgetTester tester, String label, String value) async {
  final field = find.widgetWithText(TextFormField, label);
  await tester.ensureVisible(field);
  await tester.enterText(field, value);
}

Future<void> _tapVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.tap(finder);
}

/// Pumps the full app, unauthenticated, and navigates
/// Login -> account-type selection -> Step 1 (filled with valid data) ->
/// Step 2, exactly as a real user would.
Future<(AuthProvider, StudentProfileProvider, _FakeStudentProfileRepository)>
_pumpToStep2(
  WidgetTester tester, {
  Size size = _formViewport,
  _FakeStudentProfileRepository? studentProfileRepository,
}) async {
  _setViewSize(tester, size);

  final authProvider = AuthProvider(authRepository: _FakeAuthRepository());
  final repository =
      studentProfileRepository ?? _FakeStudentProfileRepository();
  final studentProfileProvider = StudentProfileProvider(
    repository: repository,
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
    _buildApp(
      authProvider,
      studentProfileProvider,
      organizationProfileProvider,
      appRouter,
    ),
  );
  await authProvider.initialize();
  await tester.pumpAndSettle();

  final createAccount = find.text('Create Account');
  await tester.ensureVisible(createAccount);
  await tester.tap(createAccount);
  await tester.pumpAndSettle();

  final continueAsStudent = find.text('Continue as Student');
  await tester.ensureVisible(continueAsStudent);
  await tester.tap(continueAsStudent);
  await tester.pumpAndSettle();

  await _enterText(tester, 'Full Name', 'Jane Doe');
  await _enterText(tester, 'Email', 'jane.doe@example.com');
  await _enterText(tester, 'Password', 'password123');
  await _enterText(tester, 'Confirm Password', 'password123');

  final continueButton = find.text('Continue');
  await _tapVisible(tester, continueButton);
  await tester.pumpAndSettle();

  return (authProvider, studentProfileProvider, repository);
}

/// Simulates a cold start (e.g. a browser refresh) directly at
/// `/register/student/profile`, for an already-authenticated returning
/// student — no Step 1 involved in this session at all.
Future<(AuthProvider, _FakeStudentProfileRepository)>
_pumpDirectlyToStep2AsAuthenticatedStudent(
  WidgetTester tester, {
  Size size = _formViewport,
  StudentProfileModel? existingProfile,
}) async {
  _setViewSize(tester, size);

  final authProvider = AuthProvider(
    authRepository: _FakeAuthRepository(
      savedToken: 'saved-token',
      currentUser: UserModel(
        id: 7,
        name: 'Returning Student',
        email: 'returning@example.com',
        role: 'student',
        status: 'active',
      ),
    ),
  );
  final repository = _FakeStudentProfileRepository(
    getProfileResult: existingProfile,
  );
  final studentProfileProvider = StudentProfileProvider(
    repository: repository,
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
    _buildApp(
      authProvider,
      studentProfileProvider,
      organizationProfileProvider,
      appRouter,
    ),
  );

  appRouter.router.go(AppRoutes.studentProfileRegistration);
  await authProvider.initialize();
  await tester.pumpAndSettle();

  return (authProvider, repository);
}

Future<void> _fillValidStep2(WidgetTester tester) async {
  await _enterText(tester, 'University', 'State University');
  await _enterText(tester, 'Major', 'Computer Science');

  final dropdown = find.widgetWithText(
    DropdownButtonFormField<int>,
    'Expected Graduation Year',
  );
  await _tapVisible(tester, dropdown);
  await tester.pumpAndSettle();

  final currentYear = DateTime.now().year;
  await tester.tap(find.text('$currentYear').last);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'Step 2 renders University, Major, and Expected Graduation Year',
    (tester) async {
      await _pumpToStep2(tester);

      expect(find.text('University'), findsOneWidget);
      expect(find.text('Major'), findsOneWidget);
      expect(find.text('Expected Graduation Year'), findsOneWidget);
    },
  );

  testWidgets('Step 2 does not render GPA', (tester) async {
    await _pumpToStep2(tester);

    expect(find.text('GPA'), findsNothing);
  });

  testWidgets('Step 2 does not render an account-email caption', (
    tester,
  ) async {
    await _pumpToStep2(tester);

    expect(find.textContaining('Account:'), findsNothing);
  });

  testWidgets('Step 2 does not render "Back to Account Information"', (
    tester,
  ) async {
    await _pumpToStep2(tester);

    expect(find.text('Back to Account Information'), findsNothing);
  });

  testWidgets(
    'Step 2 does not render "Sign In" or "Already have an account?"',
    (tester) async {
      await _pumpToStep2(tester);

      expect(find.text('Sign In'), findsNothing);
      expect(find.text('Already have an account?'), findsNothing);
    },
  );

  testWidgets(
    'Step 2 has no AppBar back action (nothing leads back to Step 1)',
    (tester) async {
      await _pumpToStep2(tester);

      expect(find.byType(BackButton), findsNothing);
      expect(find.byIcon(Icons.arrow_back), findsNothing);
    },
  );

  testWidgets(
    'A returning authenticated student can open Step 2 directly (cold start), no extra required',
    (tester) async {
      await _pumpDirectlyToStep2AsAuthenticatedStudent(tester);

      expect(find.text('Complete Your Student Profile'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'An unauthenticated visitor to Step 2 is redirected safely (not shown a crash)',
    (tester) async {
      _setViewSize(tester, _formViewport);

      final authProvider = AuthProvider(authRepository: _FakeAuthRepository());
      final repository = _FakeStudentProfileRepository();
      final studentProfileProvider = StudentProfileProvider(
        repository: repository,
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
        _buildApp(
          authProvider,
          studentProfileProvider,
          organizationProfileProvider,
          appRouter,
        ),
      );

      appRouter.router.go(AppRoutes.studentProfileRegistration);
      await authProvider.initialize();
      await tester.pumpAndSettle();

      expect(find.text('Complete Your Student Profile'), findsNothing);
      expect(find.text('Login'), findsWidgets);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'A student with an already-complete profile opening Step 2 is sent home',
    (tester) async {
      final (_, _) = await _pumpDirectlyToStep2AsAuthenticatedStudent(
        tester,
        existingProfile: const StudentProfileModel(
          id: 1,
          university: 'State University',
          major: 'Computer Science',
          graduationYear: 2027,
        ),
      );

      expect(find.text('Role: Student'), findsOneWidget);
      expect(find.text('Complete Your Student Profile'), findsNothing);
    },
  );

  testWidgets('Empty Step 2 submit shows required errors and calls no API', (
    tester,
  ) async {
    final repository = _FakeStudentProfileRepository();
    await _pumpToStep2(tester, studentProfileRepository: repository);

    final finishButton = find.text('Finish');
    await _tapVisible(tester, finishButton);
    await tester.pumpAndSettle();

    expect(find.text('University is required'), findsOneWidget);
    expect(find.text('Major is required'), findsOneWidget);
    expect(find.text('Expected graduation year is required'), findsOneWidget);
    expect(repository.createProfileCallCount, 0);
  });

  testWidgets('Graduation-year options are generated and selectable', (
    tester,
  ) async {
    await _pumpToStep2(tester);

    final dropdown = find.widgetWithText(
      DropdownButtonFormField<int>,
      'Expected Graduation Year',
    );
    await _tapVisible(tester, dropdown);
    await tester.pumpAndSettle();

    final currentYear = DateTime.now().year;
    expect(find.text('${currentYear - 1}'), findsWidgets);
    expect(find.text('${currentYear + 8}'), findsWidgets);

    await tester.tap(find.text('${currentYear + 1}').last);
    await tester.pumpAndSettle();

    expect(find.text('${currentYear + 1}'), findsOneWidget);
  });

  testWidgets(
    'Valid Step 2 Finish sends exactly university, major, graduation_year',
    (tester) async {
      final repository = _FakeStudentProfileRepository();
      await _pumpToStep2(tester, studentProfileRepository: repository);

      await _fillValidStep2(tester);

      final finishButton = find.text('Finish');
      await _tapVisible(tester, finishButton);
      await tester.pumpAndSettle();

      expect(repository.createProfileCallCount, 1);
      expect(repository.lastCreateProfilePayload?.keys.toSet(), {
        'university',
        'major',
        'graduation_year',
      });
      expect(
        repository.lastCreateProfilePayload?['university'],
        'State University',
      );
      expect(repository.lastCreateProfilePayload?['major'], 'Computer Science');
    },
  );

  testWidgets(
    'Valid Step 2 Finish navigates to Student Home and does not show the old placeholder message',
    (tester) async {
      await _pumpToStep2(tester);

      await _fillValidStep2(tester);

      final finishButton = find.text('Finish');
      await _tapVisible(tester, finishButton);
      await tester.pumpAndSettle();

      expect(find.text('Role: Student'), findsOneWidget);
      expect(
        find.text(
          'Student account and profile API integration will be added in the next phase.',
        ),
        findsNothing,
      );
    },
  );

  testWidgets(
    'Successful Finish leaves auth state authenticated (no re-login, no token churn)',
    (tester) async {
      final (authProvider, _, _) = await _pumpToStep2(tester);
      final userBeforeFinish = authProvider.user;

      await _fillValidStep2(tester);
      final finishButton = find.text('Finish');
      await _tapVisible(tester, finishButton);
      await tester.pumpAndSettle();

      expect(authProvider.isAuthenticated, isTrue);
      expect(authProvider.user, same(userBeforeFinish));
    },
  );

  testWidgets(
    'Finish shows a loading state, disables fields, and prevents double submission',
    (tester) async {
      final repository = _FakeStudentProfileRepository(
        createDelay: const Duration(milliseconds: 200),
      );
      final (_, profileProvider, _) = await _pumpToStep2(
        tester,
        studentProfileRepository: repository,
      );

      await _fillValidStep2(tester);

      final finishButton = find.text('Finish');
      await _tapVisible(tester, finishButton);
      await tester.pump(); // Start the request, but don't let it resolve yet.

      expect(profileProvider.isLoading, isTrue);
      final universityField =
          tester.widget(find.widgetWithText(TextFormField, 'University'))
              as TextFormField;
      expect(universityField.enabled, isFalse);

      // A second tap while loading must not trigger a second request. The
      // button's disabled visuals intentionally sit in the way of the tap
      // landing on the label itself — that's the point being tested, so
      // the usual "did the tap actually connect" warning is expected here.
      await tester.tap(finishButton, warnIfMissed: false);
      await tester.pump();
      expect(repository.createProfileCallCount, 1);

      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    '422 keeps the user on Step 2, preserves entered values, and shows the backend message',
    (tester) async {
      final repository = _FakeStudentProfileRepository(
        createError: ApiException(
          'The given data was invalid.',
          statusCode: 422,
          errors: {
            'graduation_year': ['The graduation year field is required.'],
          },
        ),
      );
      await _pumpToStep2(tester, studentProfileRepository: repository);

      await _fillValidStep2(tester);
      final finishButton = find.text('Finish');
      await _tapVisible(tester, finishButton);
      await tester.pumpAndSettle();

      expect(find.text('Complete Your Student Profile'), findsOneWidget);
      expect(find.text('The given data was invalid.'), findsOneWidget);

      final universityField =
          tester.widget(find.widgetWithText(TextFormField, 'University'))
              as TextFormField;
      expect(universityField.controller?.text, 'State University');
    },
  );

  testWidgets('Network failure keeps the user on Step 2 with a clear message', (
    tester,
  ) async {
    final repository = _FakeStudentProfileRepository(
      createError: ApiException('No internet connection.'),
    );
    await _pumpToStep2(tester, studentProfileRepository: repository);

    await _fillValidStep2(tester);
    final finishButton = find.text('Finish');
    await _tapVisible(tester, finishButton);
    await tester.pumpAndSettle();

    expect(find.text('Complete Your Student Profile'), findsOneWidget);
    expect(find.text('No internet connection.'), findsOneWidget);
  });

  testWidgets('500 keeps the user on Step 2 with a clear message', (
    tester,
  ) async {
    final repository = _FakeStudentProfileRepository(
      createError: ApiException('Server error, please try again later.'),
    );
    await _pumpToStep2(tester, studentProfileRepository: repository);

    await _fillValidStep2(tester);
    final finishButton = find.text('Finish');
    await _tapVisible(tester, finishButton);
    await tester.pumpAndSettle();

    expect(find.text('Complete Your Student Profile'), findsOneWidget);
    expect(find.text('Server error, please try again later.'), findsOneWidget);
  });

  testWidgets(
    'Retry after a failure calls only the profile endpoint, never /register/student',
    (tester) async {
      final repository = _FakeStudentProfileRepository(
        createError: ApiException('Something went wrong. Please try again.'),
      );
      final (authProvider, _, _) = await _pumpToStep2(
        tester,
        studentProfileRepository: repository,
      );
      final authRepository = authProvider.authRepository as _FakeAuthRepository;

      await _fillValidStep2(tester);
      final finishButton = find.text('Finish');
      await _tapVisible(tester, finishButton);
      await tester.pumpAndSettle();

      expect(repository.createProfileCallCount, 1);
      expect(
        find.text('Something went wrong. Please try again.'),
        findsOneWidget,
      );

      // Retry: clear the error and submit again, successfully this time.
      repository.createError = null;
      await _tapVisible(tester, finishButton);
      await tester.pumpAndSettle();

      expect(repository.createProfileCallCount, 2);
      expect(authRepository.registerStudentCallCount, 1);
      expect(find.text('Role: Student'), findsOneWidget);
    },
  );

  testWidgets(
    '409 "Profile already exists" verified via GET navigates home instead of showing an error',
    (tester) async {
      final repository = _FakeStudentProfileRepository(
        createError: ApiException('Profile already exists.', statusCode: 409),
      );
      await _pumpToStep2(tester, studentProfileRepository: repository);

      // Only now does the backend actually have a profile — simulating an
      // earlier request that succeeded server-side even though its
      // response was lost. This is set after landing on Step 2 (not in
      // the constructor above), since arriving at Step 2 itself performs
      // a genuine profile-status check that must find nothing yet.
      repository.getProfileResult = const StudentProfileModel(
        id: 5,
        university: 'State University',
        major: 'Computer Science',
        graduationYear: 2027,
      );

      await _fillValidStep2(tester);
      final finishButton = find.text('Finish');
      await _tapVisible(tester, finishButton);
      await tester.pumpAndSettle();

      expect(repository.getProfileCallCount, greaterThanOrEqualTo(2));
      expect(find.text('Role: Student'), findsOneWidget);
    },
  );

  testWidgets(
    '409 that cannot be verified (GET also fails) remains a visible error, not a silent success',
    (tester) async {
      final repository = _FakeStudentProfileRepository(
        createError: ApiException('Profile already exists.', statusCode: 409),
        getProfileError: ApiException(
          'Something went wrong. Please try again.',
        ),
      );
      await _pumpToStep2(tester, studentProfileRepository: repository);

      await _fillValidStep2(tester);
      final finishButton = find.text('Finish');
      await _tapVisible(tester, finishButton);
      await tester.pumpAndSettle();

      expect(find.text('Complete Your Student Profile'), findsOneWidget);
      expect(find.text('Role: Student'), findsNothing);
    },
  );

  testWidgets('Step 2 does not overflow at a narrow 320x720 viewport', (
    tester,
  ) async {
    await _pumpToStep2(tester, size: const Size(320, 720));

    expect(tester.takeException(), isNull);
    expect(find.text('Complete Your Student Profile'), findsOneWidget);
  });
}
