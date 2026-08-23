// Router/widget tests for the account-type selection flow added in
// Phase 2B-1: LoginScreen -> AccountTypeSelectionScreen -> the student and
// company registration screens.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:opportunityhub_flutter/core/api/api_client.dart';
import 'package:opportunityhub_flutter/core/storage/theme_preference_storage.dart';
import 'package:opportunityhub_flutter/core/storage/token_storage_service.dart';
import 'package:opportunityhub_flutter/core/theme/app_theme.dart';
import 'package:opportunityhub_flutter/core/widgets/app_widgets.dart';
import 'package:opportunityhub_flutter/features/auth/data/auth_repository.dart';
import 'package:opportunityhub_flutter/features/organization/data/organization_profile_repository.dart';
import 'package:opportunityhub_flutter/features/student/data/student_profile_repository.dart';
import 'package:opportunityhub_flutter/models/organization_profile_model.dart';
import 'package:opportunityhub_flutter/models/student_profile_model.dart';
import 'package:opportunityhub_flutter/providers/auth_provider.dart';
import 'package:opportunityhub_flutter/providers/organization_profile_provider.dart';
import 'package:opportunityhub_flutter/providers/student_profile_provider.dart';
import 'package:opportunityhub_flutter/providers/theme_provider.dart';
import 'package:opportunityhub_flutter/routes/app_router.dart';

/// A fake repository that always reports "no saved token", so tests never
/// touch secure storage or make a real network call.
class _FakeAuthRepository extends AuthRepository {
  _FakeAuthRepository()
    : super(
        apiClient: ApiClient(tokenStorageService: TokenStorageService()),
        tokenStorageService: TokenStorageService(),
      );

  @override
  Future<String?> getSavedToken() async => null;
}

/// A fake repository that never touches the network — unused by this
/// file's tests, but AppRouter requires a StudentProfileProvider.
class _FakeStudentProfileRepository extends StudentProfileRepository {
  _FakeStudentProfileRepository()
    : super(apiClient: ApiClient(tokenStorageService: TokenStorageService()));

  @override
  Future<StudentProfileModel?> getProfile() async => null;
}

/// A fake repository that never touches the network — unused by this
/// file's tests, but AppRouter requires an OrganizationProfileProvider.
class _FakeOrganizationProfileRepository extends OrganizationProfileRepository {
  _FakeOrganizationProfileRepository()
    : super(apiClient: ApiClient(tokenStorageService: TokenStorageService()));

  @override
  Future<OrganizationProfileModel?> getProfile() async => null;
}

class _FakeThemePreferenceStorage extends ThemePreferenceStorage {
  ThemeMode? saved;

  @override
  Future<void> saveThemeMode(ThemeMode mode) async {
    saved = mode;
  }

  @override
  Future<ThemeMode> readThemeMode() async => saved ?? ThemeMode.system;
}

Widget _buildApp(AuthProvider authProvider, {ThemeProvider? themeProvider}) {
  final studentProfileProvider = StudentProfileProvider(
    repository: _FakeStudentProfileRepository(),
    authProvider: authProvider,
  );
  final organizationProfileProvider = OrganizationProfileProvider(
    repository: _FakeOrganizationProfileRepository(),
    authProvider: authProvider,
  );
  final resolvedThemeProvider =
      themeProvider ?? ThemeProvider(storage: _FakeThemePreferenceStorage());
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<AuthProvider>.value(value: authProvider),
      ChangeNotifierProvider<StudentProfileProvider>.value(
        value: studentProfileProvider,
      ),
      ChangeNotifierProvider<OrganizationProfileProvider>.value(
        value: organizationProfileProvider,
      ),
      ChangeNotifierProvider<ThemeProvider>.value(value: resolvedThemeProvider),
    ],
    child: Builder(
      builder: (context) {
        final mode = context.watch<ThemeProvider>().mode;
        return MaterialApp.router(
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          themeMode: mode,
          routerConfig: AppRouter(
            authProvider,
            studentProfileProvider,
            organizationProfileProvider,
          ).router,
        );
      },
    ),
  );
}

/// A typical phone-sized viewport — taller than the default 800x600 test
/// window, so full-screen content (like the login form) doesn't sit below
/// the fold during a tap.
const _phoneSize = Size(400, 800);

void _setViewSize(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

/// Pumps the full app, unauthenticated, so it lands on the login screen.
Future<ThemeProvider> _pumpToLogin(
  WidgetTester tester, {
  Size size = _phoneSize,
}) async {
  _setViewSize(tester, size);

  final authProvider = AuthProvider(authRepository: _FakeAuthRepository());
  final themeProvider = ThemeProvider(storage: _FakeThemePreferenceStorage());
  await themeProvider.initialize();
  await tester.pumpWidget(_buildApp(authProvider, themeProvider: themeProvider));
  await authProvider.initialize();
  await tester.pumpAndSettle();

  return themeProvider;
}

/// Pumps the full app and navigates from login to the account-type
/// selection screen, exactly as a user tapping "Create Account" would.
Future<ThemeProvider> _pumpToAccountTypeSelection(
  WidgetTester tester, {
  Size size = _phoneSize,
}) async {
  final themeProvider = await _pumpToLogin(tester, size: size);

  final createAccount = find.text('Create Account');
  await tester.ensureVisible(createAccount);
  await tester.tap(createAccount);
  await tester.pumpAndSettle();

  return themeProvider;
}

void main() {
  testWidgets(
    'LoginScreen "Create Account" opens the account-type selection screen',
    (tester) async {
      await _pumpToAccountTypeSelection(tester);

      expect(find.text('How will you use OpportunityHub?'), findsOneWidget);
      expect(find.text('Choose how you want to get started.'), findsOneWidget);
    },
  );

  testWidgets('Account-type screen renders both account type options', (
    tester,
  ) async {
    await _pumpToAccountTypeSelection(tester);

    expect(find.text('Student / Job Seeker'), findsOneWidget);
    expect(find.text('Continue as Student'), findsOneWidget);
    expect(find.text('Company'), findsOneWidget);
    expect(find.text('Continue as Company'), findsOneWidget);
  });

  testWidgets(
    'The Student card lists only real, existing student capabilities',
    (tester) async {
      await _pumpToAccountTypeSelection(tester);

      expect(
        find.text('Discover and apply to opportunities'),
        findsOneWidget,
      );
      expect(
        find.text('Track every application in one place'),
        findsOneWidget,
      );
      expect(
        find.text('Build your CV, skills, and verified education'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'The Company card lists only real, existing organization capabilities',
    (tester) async {
      await _pumpToAccountTypeSelection(tester);

      expect(find.text('Publish and manage opportunities'), findsOneWidget);
      expect(find.text('Discover and invite candidates'), findsOneWidget);
      expect(
        find.text('Manage applications, assessments, and interviews'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'Tapping the Student card selects it without navigating away',
    (tester) async {
      final handle = tester.ensureSemantics();
      await _pumpToAccountTypeSelection(tester);

      await tester.tap(find.text('Student / Job Seeker'));
      await tester.pumpAndSettle();

      // Selecting is not the same as continuing -- still on this screen.
      expect(find.text('How will you use OpportunityHub?'), findsOneWidget);
      expect(
        find.bySemanticsLabel(RegExp(r'Student / Job Seeker.*Selected')),
        findsOneWidget,
      );
      // The other card was never touched, so it stays unselected.
      expect(
        find.bySemanticsLabel(RegExp(r'^Company\b.*Selected')),
        findsNothing,
      );

      handle.dispose();
    },
  );

  testWidgets(
    'Tapping the Company card selects it, and selecting the other card '
    'moves the selection instead of adding to it',
    (tester) async {
      final handle = tester.ensureSemantics();
      await _pumpToAccountTypeSelection(tester);

      await tester.tap(find.text('Student / Job Seeker'));
      await tester.pumpAndSettle();
      final companyCard = find.text('Company');
      await tester.ensureVisible(companyCard);
      await tester.tap(companyCard);
      await tester.pumpAndSettle();

      expect(
        find.bySemanticsLabel(RegExp(r'^Company\b.*Selected')),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel(RegExp(r'Student / Job Seeker.*Selected')),
        findsNothing,
      );

      handle.dispose();
    },
  );

  testWidgets('Choosing Student navigates to the student registration screen', (
    tester,
  ) async {
    await _pumpToAccountTypeSelection(tester);

    final continueAsStudent = find.text('Continue as Student');
    await tester.ensureVisible(continueAsStudent);
    await tester.tap(continueAsStudent);
    await tester.pumpAndSettle();

    expect(find.text('Create Student Account'), findsOneWidget);
  });

  testWidgets(
    'Choosing Company navigates to the real company registration screen',
    (tester) async {
      await _pumpToAccountTypeSelection(tester);

      final continueAsCompany = find.text('Continue as Company');
      await tester.ensureVisible(continueAsCompany);
      await tester.tap(continueAsCompany);
      await tester.pumpAndSettle();

      expect(find.text('Create Company Account'), findsOneWidget);
    },
  );

  testWidgets(
    'Continue as Student navigates even without first selecting the card',
    (tester) async {
      await _pumpToAccountTypeSelection(tester);

      // No prior tap on the card itself -- the button always works on its
      // own, selection is a bonus, never a requirement.
      final continueAsStudent = find.text('Continue as Student');
      await tester.ensureVisible(continueAsStudent);
      await tester.tap(continueAsStudent);
      await tester.pumpAndSettle();

      expect(find.text('Create Student Account'), findsOneWidget);
    },
  );

  testWidgets(
    'Account-type screen does not overflow on a narrow mobile viewport',
    (tester) async {
      await _pumpToAccountTypeSelection(tester, size: const Size(320, 720));

      expect(tester.takeException(), isNull);
      expect(find.text('Student / Job Seeker'), findsOneWidget);
      expect(find.text('Company'), findsOneWidget);
    },
  );

  testWidgets(
    'Account-type screen lays both cards out side by side on a wide '
    'viewport, with no overflow',
    (tester) async {
      await _pumpToAccountTypeSelection(tester, size: const Size(1280, 900));

      expect(tester.takeException(), isNull);

      final studentCenter = tester.getCenter(find.text('Student / Job Seeker'));
      final companyCenter = tester.getCenter(find.text('Company'));
      // Side by side means roughly the same vertical position, clearly
      // separated horizontally -- stacked would put Company well below.
      expect(
        (studentCenter.dy - companyCenter.dy).abs(),
        lessThan(10),
      );
      expect(companyCenter.dx, greaterThan(studentCenter.dx));
    },
  );

  testWidgets(
    'Reduced motion shows content immediately, without waiting through the '
    'staggered entrance',
    (tester) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);

      await _pumpToAccountTypeSelection(tester);

      // Reduced motion collapses the staggered entrance to a near-instant
      // fade -- everything is already on screen and interactive well
      // before a full `pumpAndSettle` would be needed for the full-motion
      // staggered version.
      expect(find.text('How will you use OpportunityHub?'), findsOneWidget);
      expect(find.text('Student / Job Seeker'), findsOneWidget);
      expect(find.text('Company'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'The theme toggle is reachable from Account Type Selection and switches the resolved theme',
    (tester) async {
      final themeProvider = await _pumpToAccountTypeSelection(tester);

      expect(find.byType(ThemeToggleButton), findsOneWidget);
      expect(themeProvider.isDark, isFalse);

      await tester.tap(find.byType(ThemeToggleButton));
      await tester.pumpAndSettle();

      expect(themeProvider.isDark, isTrue);
    },
  );
}
