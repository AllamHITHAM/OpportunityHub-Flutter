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
import 'package:opportunityhub_flutter/core/api/paginated_result.dart';
import 'package:opportunityhub_flutter/core/storage/token_storage_service.dart';
import 'package:opportunityhub_flutter/core/theme/app_theme.dart';
import 'package:opportunityhub_flutter/core/widgets/theme_toggle_button.dart';
import 'package:opportunityhub_flutter/features/applications/data/application_repository.dart';
import 'package:opportunityhub_flutter/features/auth/data/auth_repository.dart';
import 'package:opportunityhub_flutter/features/cv/data/cv_repository.dart';
import 'package:opportunityhub_flutter/features/education_verification/data/education_verification_repository.dart';
import 'package:opportunityhub_flutter/features/notifications/data/notification_repository.dart';
import 'package:opportunityhub_flutter/features/opportunities/data/opportunity_repository.dart';
import 'package:opportunityhub_flutter/features/organization/data/organization_profile_repository.dart';
import 'package:opportunityhub_flutter/features/skills/data/student_skill_repository.dart';
import 'package:opportunityhub_flutter/features/student/data/student_profile_repository.dart';
import 'package:opportunityhub_flutter/models/application_model.dart';
import 'package:opportunityhub_flutter/models/cv_model.dart';
import 'package:opportunityhub_flutter/models/education_verification_model.dart';
import 'package:opportunityhub_flutter/models/notification_model.dart';
import 'package:opportunityhub_flutter/models/opportunity_model.dart';
import 'package:opportunityhub_flutter/models/organization_profile_model.dart';
import 'package:opportunityhub_flutter/models/student_profile_model.dart';
import 'package:opportunityhub_flutter/models/student_skill_model.dart';
import 'package:opportunityhub_flutter/models/user_model.dart';
import 'package:opportunityhub_flutter/providers/auth_provider.dart';
import 'package:opportunityhub_flutter/providers/notification_provider.dart';
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
  Future<void> logout() async {}

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

/// Fake repositories below are unused by this file's tests, but
/// StudentHomeScreen now reads these 5 providers unconditionally in
/// initState, and a successful Step 2 submission navigates there.
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
      ChangeNotifierProvider<ThemeProvider>.value(value: ThemeProvider()),
      ChangeNotifierProvider<StudentApplicationsProvider>(
        create: (_) => StudentApplicationsProvider(
          repository: _FakeApplicationRepository(),
          authProvider: authProvider,
        ),
      ),
      ChangeNotifierProvider<StudentOpportunitiesProvider>(
        create: (_) => StudentOpportunitiesProvider(
          repository: _FakeOpportunityRepository(),
          authProvider: authProvider,
        ),
      ),
      ChangeNotifierProvider<StudentCvProvider>(
        create: (_) => StudentCvProvider(
          repository: _FakeCvRepository(),
          studentSkillRepository: _FakeStudentSkillRepository(),
          authProvider: authProvider,
        ),
      ),
      ChangeNotifierProvider<StudentSkillProvider>(
        create: (_) => StudentSkillProvider(
          repository: _FakeStudentSkillRepository(),
          authProvider: authProvider,
        ),
      ),
      ChangeNotifierProvider<StudentEducationVerificationProvider>(
        create: (_) => StudentEducationVerificationProvider(
          repository: _FakeEducationVerificationRepository(),
          authProvider: authProvider,
        ),
      ),
    ],
    child: Builder(
      builder: (context) {
        final mode = context.watch<ThemeProvider>().mode;
        return MaterialApp.router(
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          themeMode: mode,
          routerConfig: appRouter.router,
        );
      },
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
    'Step 2 shows a Leave-setup exit action that opens a confirmation dialog '
    'with the exact required copy',
    (tester) async {
      final (authProvider, _, _) = await _pumpToStep2(tester);

      await _tapVisible(tester, find.byIcon(Icons.close));
      await tester.pumpAndSettle();

      expect(find.text('Leave setup?'), findsOneWidget);
      expect(
        find.text(
          'Your account has been created, but your profile setup is not '
          'complete.',
        ),
        findsOneWidget,
      );
      expect(find.text('Continue Setup'), findsOneWidget);
      expect(find.text('Sign Out'), findsOneWidget);

      // Does not imply the account/data will be deleted -- it will not be.
      expect(find.textContaining('delete'), findsNothing);
      expect(find.textContaining('Delete'), findsNothing);
      expect(find.textContaining('lost'), findsNothing);
      expect(find.textContaining('permanently'), findsNothing);

      expect(authProvider.isAuthenticated, isTrue);
    },
  );

  testWidgets(
    'Continue Setup dismisses the dialog and keeps the student on Step 2, still signed in',
    (tester) async {
      final (authProvider, _, _) = await _pumpToStep2(tester);

      await _tapVisible(tester, find.byIcon(Icons.close));
      await tester.pumpAndSettle();

      await _tapVisible(tester, find.text('Continue Setup'));
      await tester.pumpAndSettle();

      expect(find.text('Leave setup?'), findsNothing);
      expect(find.text('Complete Your Student Profile'), findsOneWidget);
      expect(authProvider.isAuthenticated, isTrue);
    },
  );

  testWidgets(
    'Sign Out from the dialog signs the student out and returns to Login, '
    'with no redirect loop and no data silently discarded',
    (tester) async {
      final (authProvider, _, repository) = await _pumpToStep2(tester);

      await _tapVisible(tester, find.byIcon(Icons.close));
      await tester.pumpAndSettle();

      await _tapVisible(tester, find.text('Sign Out'));
      // pumpAndSettle completing (rather than timing out) is itself proof
      // there is no redirect loop between the now-unauthenticated state
      // and the protected Step 2 route.
      await tester.pumpAndSettle();

      expect(authProvider.isAuthenticated, isFalse);
      expect(find.text('Complete Your Student Profile'), findsNothing);
      expect(find.widgetWithText(ElevatedButton, 'Login'), findsOneWidget);
      // Nothing about signing out calls the profile-creation endpoint --
      // the account and its (still-incomplete) profile state are untouched.
      expect(repository.createProfileCallCount, 0);
      expect(tester.takeException(), isNull);
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

      expect(find.text("Discover Opportunities"), findsOneWidget);
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

      expect(find.text("Discover Opportunities"), findsOneWidget);
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
      expect(find.text("Discover Opportunities"), findsOneWidget);
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
      expect(find.text("Discover Opportunities"), findsOneWidget);
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
      expect(find.text("Discover Opportunities"), findsNothing);
    },
  );

  testWidgets('Step 2 does not overflow at a narrow 320x720 viewport', (
    tester,
  ) async {
    await _pumpToStep2(tester, size: const Size(320, 720));

    expect(tester.takeException(), isNull);
    expect(find.text('Complete Your Student Profile'), findsOneWidget);
  });

  testWidgets(
    'The theme toggle is reachable from Step 2 and switches the resolved theme',
    (tester) async {
      await _pumpToStep2(tester);

      expect(find.byType(ThemeToggleButton), findsOneWidget);
      expect(
        Theme.of(tester.element(find.byType(Scaffold).first)).brightness,
        Brightness.light,
      );

      await tester.tap(find.byType(ThemeToggleButton));
      await tester.pumpAndSettle();

      expect(
        Theme.of(tester.element(find.byType(Scaffold).first)).brightness,
        Brightness.dark,
      );
    },
  );

  testWidgets(
    'Reduced motion renders Step 2 immediately, without waiting through '
    'the staggered entrance',
    (tester) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);

      await _pumpToStep2(tester);

      expect(find.text('Complete Your Student Profile'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
