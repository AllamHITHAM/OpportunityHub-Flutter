// Widget/router tests for Company (organization) Registration.
//
// Unlike student registration, this is ONE screen with two visual pages
// (account info, then company info) rather than two separate routes: the
// real backend has no endpoint to create an organization profile on its
// own (only POST /register/organization, which creates the account and
// its profile atomically). So "Step 1" and "Step 2" below refer to pages
// within the same widget's local state, not separate navigations — the
// API is only ever called once, when "Finish" is tapped on the company
// info page.

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

/// A fake repository that never touches secure storage or the network.
///
/// [registerOrganization] can be configured to succeed (the default), fail
/// with a given [ApiException], or wait for [registerDelay] before
/// resolving — letting tests observe the in-flight loading state.
class _FakeAuthRepository extends AuthRepository {
  _FakeAuthRepository({this.registerDelay = Duration.zero, this.registerError})
    : super(
        apiClient: ApiClient(tokenStorageService: TokenStorageService()),
        tokenStorageService: TokenStorageService(),
      );

  final Duration registerDelay;
  ApiException? registerError;

  int registerOrganizationCallCount = 0;
  Map<String, String?>? lastRegisterOrganizationArgs;

  @override
  Future<String?> getSavedToken() async => null;

  @override
  Future<UserModel> registerOrganization({
    required String name,
    required String email,
    required String password,
    required String organizationName,
    required String organizationType,
    String? industry,
    String? description,
    String? website,
    String? phone,
  }) async {
    registerOrganizationCallCount++;
    lastRegisterOrganizationArgs = {
      'name': name,
      'email': email,
      'password': password,
      'organizationName': organizationName,
      'organizationType': organizationType,
      'industry': industry,
      'description': description,
      'website': website,
      'phone': phone,
    };
    if (registerDelay > Duration.zero) {
      await Future<void>.delayed(registerDelay);
    }
    if (registerError != null) throw registerError!;
    return UserModel(
      id: 1,
      name: name,
      email: email,
      role: 'organization',
      status: 'active',
    );
  }
}

/// A fake repository that never touches the network — unused by this
/// file's tests, but AppRouter requires a StudentProfileProvider.
class _FakeStudentProfileRepository extends StudentProfileRepository {
  _FakeStudentProfileRepository()
    : super(apiClient: ApiClient(tokenStorageService: TokenStorageService()));

  @override
  Future<StudentProfileModel?> getProfile() async => null;
}

/// A fake repository that never touches the network.
/// [getProfileCallCount] lets tests prove the profile-status check runs
/// exactly once per sign-in, not repeatedly.
class _FakeOrganizationProfileRepository extends OrganizationProfileRepository {
  _FakeOrganizationProfileRepository()
    : super(apiClient: ApiClient(tokenStorageService: TokenStorageService()));

  int getProfileCallCount = 0;

  @override
  Future<OrganizationProfileModel?> getProfile() async {
    getProfileCallCount++;
    // A brand-new organization always has a profile the instant it's
    // authenticated (created atomically by registration), so the fake
    // mirrors that reality once one exists.
    return const OrganizationProfileModel(
      id: 1,
      organizationName: 'Acme Corp',
      organizationType: 'company',
      approvalStatus: 'pending',
    );
  }
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
      routerConfig: AppRouter(
        authProvider,
        studentProfileProvider,
        organizationProfileProvider,
      ).router,
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
/// Login -> account-type selection -> Company registration Step 1
/// (account information), exactly as a real user tapping through the
/// sign-up flow would.
Future<(AuthProvider, _FakeAuthRepository)> _pumpToAccountStep(
  WidgetTester tester, {
  Size size = _formViewport,
  _FakeAuthRepository? authRepository,
}) async {
  _setViewSize(tester, size);

  final fakeAuthRepository = authRepository ?? _FakeAuthRepository();
  final authProvider = AuthProvider(authRepository: fakeAuthRepository);
  final studentProfileProvider = StudentProfileProvider(
    repository: _FakeStudentProfileRepository(),
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

  final continueAsCompany = find.text('Continue as Company');
  await tester.ensureVisible(continueAsCompany);
  await tester.tap(continueAsCompany);
  await tester.pumpAndSettle();

  return (authProvider, fakeAuthRepository);
}

Future<void> _fillValidAccountStep(WidgetTester tester) async {
  await _enterText(tester, 'Full Name', 'Jane Recruiter');
  await _enterText(tester, 'Email', 'jane@acme.example.com');
  await _enterText(tester, 'Password', 'password123');
  await _enterText(tester, 'Confirm Password', 'password123');
}

/// From the account-information page, validates and moves to the
/// company-information page (no API call — see file header).
Future<void> _continueToCompanyStep(WidgetTester tester) async {
  final continueButton = find.text('Continue');
  await _tapVisible(tester, continueButton);
  await tester.pumpAndSettle();
}

Future<void> _fillValidCompanyStep(WidgetTester tester) async {
  await _enterText(tester, 'Company Name', 'Acme Corp');

  final dropdown = find.widgetWithText(
    DropdownButtonFormField<String>,
    'Company Type',
  );
  await _tapVisible(tester, dropdown);
  await tester.pumpAndSettle();

  await tester.tap(find.text('Company').last);
  await tester.pumpAndSettle();
}

/// Pumps all the way through to the company-information page with valid
/// account-step data already entered.
Future<(AuthProvider, _FakeAuthRepository)> _pumpToCompanyStep(
  WidgetTester tester, {
  Size size = _formViewport,
  _FakeAuthRepository? authRepository,
}) async {
  final result = await _pumpToAccountStep(
    tester,
    size: size,
    authRepository: authRepository,
  );
  await _fillValidAccountStep(tester);
  await _continueToCompanyStep(tester);
  return result;
}

void main() {
  testWidgets('Company selection opens the real company registration screen', (
    tester,
  ) async {
    await _pumpToAccountStep(tester);

    expect(find.text('Create Company Account'), findsOneWidget);
    expect(find.text('Step 1 of 2'), findsOneWidget);
  });

  testWidgets('The old placeholder message is gone', (tester) async {
    await _pumpToAccountStep(tester);

    expect(
      find.text('Registration form will be implemented in the next phase.'),
      findsNothing,
    );
    expect(find.text('Company Registration'), findsNothing);
  });

  testWidgets('Account step renders only account fields', (tester) async {
    await _pumpToAccountStep(tester);

    expect(find.text('Full Name'), findsOneWidget);
    expect(find.text('Email'), findsOneWidget);
    expect(find.text('Password'), findsOneWidget);
    expect(find.text('Confirm Password'), findsOneWidget);
    expect(find.text('Company Name'), findsNothing);
    expect(find.text('Company Type'), findsNothing);
  });

  testWidgets(
    'Empty account-step submit shows local validation without any API call',
    (tester) async {
      final authRepository = _FakeAuthRepository();
      await _pumpToAccountStep(tester, authRepository: authRepository);

      await _continueToCompanyStep(tester);

      expect(find.text('Full name is required'), findsOneWidget);
      expect(find.text('Email is required'), findsOneWidget);
      expect(find.text('Password is required'), findsOneWidget);
      expect(find.text('Please confirm your password'), findsOneWidget);
      expect(find.text('Create Company Account'), findsOneWidget);
      expect(authRepository.registerOrganizationCallCount, 0);
    },
  );

  testWidgets('Invalid email is rejected locally and does not advance', (
    tester,
  ) async {
    final authRepository = _FakeAuthRepository();
    await _pumpToAccountStep(tester, authRepository: authRepository);

    await _enterText(tester, 'Full Name', 'Jane Recruiter');
    await _enterText(tester, 'Email', 'not-an-email');
    await _enterText(tester, 'Password', 'password123');
    await _enterText(tester, 'Confirm Password', 'password123');
    await _continueToCompanyStep(tester);

    expect(find.text('Enter a valid email address'), findsOneWidget);
    expect(find.text('Complete Your Company Profile'), findsNothing);
    expect(authRepository.registerOrganizationCallCount, 0);
  });

  testWidgets('Password mismatch is rejected locally and does not advance', (
    tester,
  ) async {
    final authRepository = _FakeAuthRepository();
    await _pumpToAccountStep(tester, authRepository: authRepository);

    await _enterText(tester, 'Full Name', 'Jane Recruiter');
    await _enterText(tester, 'Email', 'jane@acme.example.com');
    await _enterText(tester, 'Password', 'password123');
    await _enterText(tester, 'Confirm Password', 'different123');
    await _continueToCompanyStep(tester);

    expect(find.text('Passwords do not match'), findsOneWidget);
    expect(find.text('Complete Your Company Profile'), findsNothing);
    expect(authRepository.registerOrganizationCallCount, 0);
  });

  testWidgets(
    'Valid account step advances to the company-information page with no API call yet',
    (tester) async {
      final authRepository = _FakeAuthRepository();
      await _pumpToCompanyStep(tester, authRepository: authRepository);

      expect(find.text('Complete Your Company Profile'), findsOneWidget);
      expect(find.text('Step 2 of 2'), findsOneWidget);
      expect(authRepository.registerOrganizationCallCount, 0);
    },
  );

  testWidgets('Company step renders only company fields', (tester) async {
    await _pumpToCompanyStep(tester);

    expect(find.text('Company Name'), findsOneWidget);
    expect(find.text('Company Type'), findsOneWidget);
    expect(find.text('Industry (optional)'), findsOneWidget);
    expect(find.text('Website (optional)'), findsOneWidget);
    expect(find.text('Phone (optional)'), findsOneWidget);
    expect(find.text('Description (optional)'), findsOneWidget);
    expect(find.text('Full Name'), findsNothing);
    expect(find.text('Password'), findsNothing);
  });

  testWidgets('Company step has no back action to the account step', (
    tester,
  ) async {
    await _pumpToCompanyStep(tester);

    expect(find.byType(BackButton), findsNothing);
    expect(find.byIcon(Icons.arrow_back), findsNothing);
  });

  testWidgets('Company step has no Sign In action', (tester) async {
    await _pumpToCompanyStep(tester);

    expect(find.text('Sign In'), findsNothing);
    expect(find.text('Already have an account?'), findsNothing);
  });

  testWidgets(
    'Empty company-step submit shows local validation without any API call',
    (tester) async {
      final authRepository = _FakeAuthRepository();
      await _pumpToCompanyStep(tester, authRepository: authRepository);

      final finishButton = find.text('Finish');
      await _tapVisible(tester, finishButton);
      await tester.pumpAndSettle();

      expect(find.text('Company name is required'), findsOneWidget);
      expect(find.text('Company type is required'), findsOneWidget);
      expect(authRepository.registerOrganizationCallCount, 0);
    },
  );

  testWidgets(
    'Valid Finish sends exactly the documented account + company fields',
    (tester) async {
      final authRepository = _FakeAuthRepository();
      await _pumpToCompanyStep(tester, authRepository: authRepository);
      await _fillValidCompanyStep(tester);

      final finishButton = find.text('Finish');
      await _tapVisible(tester, finishButton);
      await tester.pumpAndSettle();

      expect(authRepository.registerOrganizationCallCount, 1);
      final args = authRepository.lastRegisterOrganizationArgs!;
      expect(args['name'], 'Jane Recruiter');
      expect(args['email'], 'jane@acme.example.com');
      expect(args['password'], 'password123');
      expect(args['organizationName'], 'Acme Corp');
      expect(args['organizationType'], 'company');
      // Optional fields left blank are passed through as null, not empty
      // strings — AuthRepository is responsible for omitting them from
      // the actual request body (see auth_repository_test.dart).
      expect(args['industry'], isNull);
      expect(args['website'], isNull);
      expect(args['phone'], isNull);
      expect(args['description'], isNull);
    },
  );

  testWidgets(
    'Successful Finish authenticates role organization and navigates to Organization Home',
    (tester) async {
      final (authProvider, _) = await _pumpToCompanyStep(tester);
      await _fillValidCompanyStep(tester);

      final finishButton = find.text('Finish');
      await _tapVisible(tester, finishButton);
      await tester.pumpAndSettle();

      expect(find.text('Role: Organization'), findsOneWidget);
      expect(authProvider.isAuthenticated, isTrue);
      expect(authProvider.user?.role, 'organization');
    },
  );

  testWidgets(
    'Finish shows a loading state, disables fields, and prevents double submission',
    (tester) async {
      final authRepository = _FakeAuthRepository(
        registerDelay: const Duration(milliseconds: 200),
      );
      await _pumpToCompanyStep(tester, authRepository: authRepository);
      await _fillValidCompanyStep(tester);

      final finishButton = find.text('Finish');
      await _tapVisible(tester, finishButton);
      await tester.pump(); // Start the request, but don't let it resolve yet.

      final companyNameField =
          tester.widget(find.widgetWithText(TextFormField, 'Company Name'))
              as TextFormField;
      expect(companyNameField.enabled, isFalse);

      // A second tap while loading must not trigger a second request.
      await tester.tap(finishButton, warnIfMissed: false);
      await tester.pump();
      expect(authRepository.registerOrganizationCallCount, 1);

      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'Registration error remains on the company step and shows AppErrorView, preserving values',
    (tester) async {
      final authRepository = _FakeAuthRepository(
        registerError: ApiException('Something went wrong. Please try again.'),
      );
      await _pumpToCompanyStep(tester, authRepository: authRepository);
      await _fillValidCompanyStep(tester);

      final finishButton = find.text('Finish');
      await _tapVisible(tester, finishButton);
      await tester.pumpAndSettle();

      expect(find.text('Complete Your Company Profile'), findsOneWidget);
      expect(find.text('Something Went Wrong'), findsOneWidget);
      expect(
        find.text('Something went wrong. Please try again.'),
        findsOneWidget,
      );

      final companyNameField =
          tester.widget(find.widgetWithText(TextFormField, 'Company Name'))
              as TextFormField;
      expect(companyNameField.controller?.text, 'Acme Corp');
    },
  );

  testWidgets('422 preserves values and remains on the company step', (
    tester,
  ) async {
    final authRepository = _FakeAuthRepository(
      registerError: ApiException(
        'The given data was invalid.',
        statusCode: 422,
        errors: {
          'organization_name': ['The organization name field is required.'],
        },
      ),
    );
    await _pumpToCompanyStep(tester, authRepository: authRepository);
    await _fillValidCompanyStep(tester);

    final finishButton = find.text('Finish');
    await _tapVisible(tester, finishButton);
    await tester.pumpAndSettle();

    expect(find.text('Complete Your Company Profile'), findsOneWidget);
    expect(find.text('The given data was invalid.'), findsOneWidget);
  });

  testWidgets('Network failure keeps the user on the company step', (
    tester,
  ) async {
    final authRepository = _FakeAuthRepository(
      registerError: ApiException('No internet connection.'),
    );
    await _pumpToCompanyStep(tester, authRepository: authRepository);
    await _fillValidCompanyStep(tester);

    final finishButton = find.text('Finish');
    await _tapVisible(tester, finishButton);
    await tester.pumpAndSettle();

    expect(find.text('Complete Your Company Profile'), findsOneWidget);
    expect(find.text('No internet connection.'), findsOneWidget);
  });

  testWidgets(
    '500 error displays safely and keeps the user on the company step',
    (tester) async {
      final authRepository = _FakeAuthRepository(
        registerError: ApiException('Server error, please try again later.'),
      );
      await _pumpToCompanyStep(tester, authRepository: authRepository);
      await _fillValidCompanyStep(tester);

      final finishButton = find.text('Finish');
      await _tapVisible(tester, finishButton);
      await tester.pumpAndSettle();

      expect(find.text('Complete Your Company Profile'), findsOneWidget);
      expect(
        find.text('Server error, please try again later.'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'Retry after a failure calls registration again exactly once more (nothing was created on the failed attempt)',
    (tester) async {
      final authRepository = _FakeAuthRepository(
        registerError: ApiException('Something went wrong. Please try again.'),
      );
      await _pumpToCompanyStep(tester, authRepository: authRepository);
      await _fillValidCompanyStep(tester);

      final finishButton = find.text('Finish');
      await _tapVisible(tester, finishButton);
      await tester.pumpAndSettle();

      expect(authRepository.registerOrganizationCallCount, 1);
      expect(
        find.text('Something went wrong. Please try again.'),
        findsOneWidget,
      );

      // Retry: clear the error and submit again, successfully this time.
      authRepository.registerError = null;
      await _tapVisible(tester, finishButton);
      await tester.pumpAndSettle();

      expect(authRepository.registerOrganizationCallCount, 2);
      expect(find.text('Role: Organization'), findsOneWidget);
    },
  );

  testWidgets(
    'A successful registration is never followed by another registration call',
    (tester) async {
      final authRepository = _FakeAuthRepository();
      await _pumpToCompanyStep(tester, authRepository: authRepository);
      await _fillValidCompanyStep(tester);

      final finishButton = find.text('Finish');
      await _tapVisible(tester, finishButton);
      await tester.pumpAndSettle();

      expect(authRepository.registerOrganizationCallCount, 1);
      expect(find.text('Role: Organization'), findsOneWidget);

      // Nothing about arriving at Organization Home should trigger another
      // registration call.
      await tester.pumpAndSettle();
      expect(authRepository.registerOrganizationCallCount, 1);
    },
  );

  testWidgets('Account step does not overflow at a narrow 320x720 viewport', (
    tester,
  ) async {
    await _pumpToAccountStep(tester, size: const Size(320, 720));

    expect(tester.takeException(), isNull);
    expect(find.text('Create Company Account'), findsOneWidget);
  });

  testWidgets('Company step does not overflow at a narrow 320x720 viewport', (
    tester,
  ) async {
    await _pumpToCompanyStep(tester, size: const Size(320, 720));

    expect(tester.takeException(), isNull);
    expect(find.text('Complete Your Company Profile'), findsOneWidget);
  });

  testWidgets('Sign In from the account step returns to LoginScreen', (
    tester,
  ) async {
    await _pumpToAccountStep(tester);

    final signIn = find.text('Sign In');
    await _tapVisible(tester, signIn);
    await tester.pumpAndSettle();

    expect(find.text('Welcome Back'), findsOneWidget);
  });
}
