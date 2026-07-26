// Widget/router tests for Step 1 of the two-step Student Registration UI
// (Phase 2B-3): account information, now backed by a real
// POST /register/student call (via a configurable fake AuthRepository, so
// these tests never touch secure storage or the network directly).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'package:opportunityhub_flutter/core/api/api_client.dart';
import 'package:opportunityhub_flutter/core/storage/token_storage_service.dart';
import 'package:opportunityhub_flutter/core/theme/app_theme.dart';
import 'package:opportunityhub_flutter/features/auth/data/auth_repository.dart';
import 'package:opportunityhub_flutter/features/organization/data/organization_profile_repository.dart';
import 'package:opportunityhub_flutter/features/student/data/student_profile_repository.dart';
import 'package:opportunityhub_flutter/models/organization_profile_model.dart';
import 'package:opportunityhub_flutter/models/student_profile_model.dart';
import 'package:opportunityhub_flutter/models/user_model.dart';
import 'package:opportunityhub_flutter/providers/auth_provider.dart';
import 'package:opportunityhub_flutter/providers/organization_profile_provider.dart';
import 'package:opportunityhub_flutter/providers/student_profile_provider.dart';
import 'package:opportunityhub_flutter/routes/app_router.dart';
import 'package:opportunityhub_flutter/routes/app_routes.dart';

/// A fake repository that never touches secure storage or the network.
///
/// [registerStudent] can be configured to succeed (the default), fail with
/// a given [ApiException], or wait for [registerDelay] before resolving —
/// letting tests observe the in-flight loading state.
class _FakeAuthRepository extends AuthRepository {
  _FakeAuthRepository({this.registerDelay = Duration.zero, this.registerError})
    : super(
        apiClient: ApiClient(tokenStorageService: TokenStorageService()),
        tokenStorageService: TokenStorageService(),
      );

  final Duration registerDelay;
  final ApiException? registerError;

  int registerStudentCallCount = 0;

  @override
  Future<String?> getSavedToken() async => null;

  @override
  Future<UserModel> registerStudent({
    required String name,
    required String email,
    required String password,
  }) async {
    registerStudentCallCount++;
    if (registerDelay > Duration.zero) {
      await Future<void>.delayed(registerDelay);
    }
    if (registerError != null) throw registerError!;
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
/// [getProfileCallCount] lets tests prove the profile-status check runs
/// exactly once per sign-in, not repeatedly.
class _FakeStudentProfileRepository extends StudentProfileRepository {
  _FakeStudentProfileRepository()
    : super(apiClient: ApiClient(tokenStorageService: TokenStorageService()));

  int getProfileCallCount = 0;

  @override
  Future<StudentProfileModel?> getProfile() async {
    getProfileCallCount++;
    return null;
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

Widget _buildApp(
  AuthProvider authProvider,
  StudentProfileProvider studentProfileProvider,
  OrganizationProfileProvider organizationProfileProvider,
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
    ],
    child: MaterialApp.router(
      theme: AppTheme.lightTheme,
      routerConfig: AppRouter(
        authProvider,
        studentProfileProvider,
        organizationProfileProvider,
      ).router,
    ),
  );
}

const _formViewport = Size(420, 1200);

void _setViewSize(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

/// Pumps the full app, unauthenticated, and navigates
/// Login -> account-type selection -> Step 1, exactly as a real user
/// tapping through the sign-up flow would.
Future<(AuthProvider, _FakeStudentProfileRepository)> _pumpToStep1(
  WidgetTester tester, {
  Size size = _formViewport,
  AuthRepository? authRepository,
}) async {
  _setViewSize(tester, size);

  final authProvider = AuthProvider(
    authRepository: authRepository ?? _FakeAuthRepository(),
  );
  final studentProfileRepository = _FakeStudentProfileRepository();
  final studentProfileProvider = StudentProfileProvider(
    repository: studentProfileRepository,
    authProvider: authProvider,
  );
  final organizationProfileProvider = OrganizationProfileProvider(
    repository: _FakeOrganizationProfileRepository(),
    authProvider: authProvider,
  );
  await tester.pumpWidget(
    _buildApp(
      authProvider,
      studentProfileProvider,
      organizationProfileProvider,
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

  return (authProvider, studentProfileRepository);
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

Future<void> _fillValidStep1(WidgetTester tester) async {
  await _enterText(tester, 'Full Name', 'Jane Doe');
  await _enterText(tester, 'Email', 'jane.doe@example.com');
  await _enterText(tester, 'Password', 'password123');
  await _enterText(tester, 'Confirm Password', 'password123');
}

void main() {
  testWidgets('/register/student renders Step 1', (tester) async {
    await _pumpToStep1(tester);

    expect(find.text('Create Student Account'), findsOneWidget);
    expect(find.text('Step 1 of 2'), findsOneWidget);
  });

  testWidgets('Step 1 renders only account fields', (tester) async {
    await _pumpToStep1(tester);

    expect(find.text('Full Name'), findsOneWidget);
    expect(find.text('Email'), findsOneWidget);
    expect(find.text('Password'), findsOneWidget);
    expect(find.text('Confirm Password'), findsOneWidget);
  });

  testWidgets(
    'Step 1 no longer renders University, Major, Graduation Year, or GPA',
    (tester) async {
      await _pumpToStep1(tester);

      expect(find.text('University'), findsNothing);
      expect(find.text('Major'), findsNothing);
      expect(find.text('Expected Graduation Year'), findsNothing);
      expect(find.text('GPA'), findsNothing);
    },
  );

  testWidgets('Empty Step 1 submit shows validation errors', (tester) async {
    final authRepository = _FakeAuthRepository();
    await _pumpToStep1(tester, authRepository: authRepository);

    final continueButton = find.text('Continue');
    await _tapVisible(tester, continueButton);
    await tester.pumpAndSettle();

    expect(find.text('Full name is required'), findsOneWidget);
    expect(find.text('Email is required'), findsOneWidget);
    expect(find.text('Password is required'), findsOneWidget);
    expect(find.text('Please confirm your password'), findsOneWidget);
    // Client-side validation failed, so the API was never called.
    expect(authRepository.registerStudentCallCount, 0);
  });

  testWidgets('Invalid Step 1 does not navigate', (tester) async {
    final authRepository = _FakeAuthRepository();
    await _pumpToStep1(tester, authRepository: authRepository);

    await _enterText(tester, 'Email', 'not-an-email');

    final continueButton = find.text('Continue');
    await _tapVisible(tester, continueButton);
    await tester.pumpAndSettle();

    expect(find.text('Create Student Account'), findsOneWidget);
    expect(find.text('Complete Your Student Profile'), findsNothing);
    expect(authRepository.registerStudentCallCount, 0);
  });

  testWidgets(
    'Continue shows a loading state and disables fields while registering',
    (tester) async {
      final (authProvider, _) = await _pumpToStep1(
        tester,
        authRepository: _FakeAuthRepository(
          registerDelay: const Duration(milliseconds: 200),
        ),
      );

      await _fillValidStep1(tester);

      final continueButton = find.text('Continue');
      await _tapVisible(tester, continueButton);
      await tester.pump(); // Start the request, but don't let it resolve yet.

      expect(authProvider.isLoading, isTrue);
      final nameField =
          tester.widget(find.widgetWithText(TextFormField, 'Full Name'))
              as TextFormField;
      expect(nameField.enabled, isFalse);

      // Let the in-flight request finish so nothing leaks into later tests.
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'Valid Step 1 navigates to Step 2 and marks the user authenticated',
    (tester) async {
      final (authProvider, _) = await _pumpToStep1(tester);

      await _fillValidStep1(tester);

      final continueButton = find.text('Continue');
      await _tapVisible(tester, continueButton);
      await tester.pumpAndSettle();

      expect(find.text('Complete Your Student Profile'), findsOneWidget);
      expect(authProvider.isAuthenticated, isTrue);
      expect(authProvider.user?.email, 'jane.doe@example.com');
    },
  );

  testWidgets(
    'Landing on Step 2 after registering checks profile status exactly once (no redundant polling)',
    (tester) async {
      final (_, studentProfileRepository) = await _pumpToStep1(tester);

      await _fillValidStep1(tester);

      final continueButton = find.text('Continue');
      await _tapVisible(tester, continueButton);
      await tester.pumpAndSettle();

      // The router verifies profile status via the real backend signal
      // (GET /api/student/profile, 404 for a brand-new account) exactly
      // once per sign-in — not on every subsequent navigation.
      expect(find.text('Finish'), findsOneWidget);
      expect(studentProfileRepository.getProfileCallCount, 1);
    },
  );

  testWidgets(
    'An authenticated student cannot navigate back to Step 1 (no duplicate registration)',
    (tester) async {
      final authRepository = _FakeAuthRepository();
      final (authProvider, _) = await _pumpToStep1(
        tester,
        authRepository: authRepository,
      );

      await _fillValidStep1(tester);

      final continueButton = find.text('Continue');
      await _tapVisible(tester, continueButton);
      await tester.pumpAndSettle();

      expect(authProvider.isAuthenticated, isTrue);
      expect(authRepository.registerStudentCallCount, 1);

      // Simulate the user manually navigating (or refreshing) back to
      // Step 1's URL while already authenticated.
      final context = tester.element(find.byType(Scaffold).first);
      GoRouter.of(context).go(AppRoutes.studentRegistration);
      await tester.pumpAndSettle();

      // The router redirects them away instead of rendering Step 1 again.
      expect(find.text('Create Student Account'), findsNothing);
      expect(find.text('Complete Your Student Profile'), findsOneWidget);
      expect(authRepository.registerStudentCallCount, 1);
    },
  );

  testWidgets('API failure keeps the user on Step 1 and shows AppErrorView', (
    tester,
  ) async {
    final authRepository = _FakeAuthRepository(
      registerError: ApiException('Something went wrong. Please try again.'),
    );
    await _pumpToStep1(tester, authRepository: authRepository);

    await _fillValidStep1(tester);

    final continueButton = find.text('Continue');
    await _tapVisible(tester, continueButton);
    await tester.pumpAndSettle();

    expect(find.text('Create Student Account'), findsOneWidget);
    expect(find.text('Registration Failed'), findsOneWidget);
    expect(
      find.text('Something went wrong. Please try again.'),
      findsOneWidget,
    );
  });

  testWidgets('Duplicate email (422) shows the backend validation message', (
    tester,
  ) async {
    final authRepository = _FakeAuthRepository(
      registerError: ApiException(
        'The given data was invalid.',
        statusCode: 422,
        errors: {
          'email': ['The email has already been taken.'],
        },
      ),
    );
    await _pumpToStep1(tester, authRepository: authRepository);

    await _fillValidStep1(tester);

    final continueButton = find.text('Continue');
    await _tapVisible(tester, continueButton);
    await tester.pumpAndSettle();

    expect(find.text('The given data was invalid.'), findsOneWidget);
    expect(find.text('Complete Your Student Profile'), findsNothing);
  });

  testWidgets('Network failure shows a connectivity message', (tester) async {
    final authRepository = _FakeAuthRepository(
      registerError: ApiException('No internet connection.'),
    );
    await _pumpToStep1(tester, authRepository: authRepository);

    await _fillValidStep1(tester);

    final continueButton = find.text('Continue');
    await _tapVisible(tester, continueButton);
    await tester.pumpAndSettle();

    expect(find.text('No internet connection.'), findsOneWidget);
  });

  testWidgets('Sign In from Step 1 returns to LoginScreen', (tester) async {
    await _pumpToStep1(tester);

    final signIn = find.text('Sign In');
    await _tapVisible(tester, signIn);
    await tester.pumpAndSettle();

    expect(find.text('Welcome Back'), findsOneWidget);
  });

  testWidgets('Step 1 does not overflow at a narrow 320x720 viewport', (
    tester,
  ) async {
    await _pumpToStep1(tester, size: const Size(320, 720));

    expect(tester.takeException(), isNull);
    expect(find.text('Create Student Account'), findsOneWidget);
  });
}
