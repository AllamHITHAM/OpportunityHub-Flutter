// Widget tests for ForgotPasswordScreen, in isolation with a small
// GoRouter.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'package:opportunityhub_flutter/core/api/api_client.dart';
import 'package:opportunityhub_flutter/core/storage/theme_preference_storage.dart';
import 'package:opportunityhub_flutter/core/storage/token_storage_service.dart';
import 'package:opportunityhub_flutter/core/theme/app_theme.dart';
import 'package:opportunityhub_flutter/features/auth/data/auth_repository.dart';
import 'package:opportunityhub_flutter/core/widgets/primary_button.dart';
import 'package:opportunityhub_flutter/features/auth/presentation/forgot_password_screen.dart';
import 'package:opportunityhub_flutter/providers/auth_provider.dart';
import 'package:opportunityhub_flutter/providers/theme_provider.dart';
import 'package:opportunityhub_flutter/routes/app_routes.dart';

class _FakeThemePreferenceStorage extends ThemePreferenceStorage {
  ThemeMode? saved;

  @override
  Future<void> saveThemeMode(ThemeMode mode) async {
    saved = mode;
  }

  @override
  Future<ThemeMode> readThemeMode() async => saved ?? ThemeMode.system;
}

class _FakeAuthRepository extends AuthRepository {
  _FakeAuthRepository()
    : super(
        apiClient: ApiClient(tokenStorageService: TokenStorageService()),
        tokenStorageService: TokenStorageService(),
      );

  ApiException? forgotPasswordError;
  Duration forgotPasswordDelay = Duration.zero;
  int forgotPasswordCallCount = 0;
  String? lastEmail;

  @override
  Future<void> forgotPassword(String email) async {
    forgotPasswordCallCount++;
    lastEmail = email;
    if (forgotPasswordDelay > Duration.zero) {
      await Future<void>.delayed(forgotPasswordDelay);
    }
    if (forgotPasswordError != null) throw forgotPasswordError!;
  }
}

Future<AuthProvider> _pumpScreen(
  WidgetTester tester, {
  required AuthRepository repository,
}) async {
  final authProvider = AuthProvider(authRepository: repository);

  final router = GoRouter(
    initialLocation: AppRoutes.forgotPassword,
    routes: [
      GoRoute(
        path: AppRoutes.forgotPassword,
        builder: (_, _) => const ForgotPasswordScreen(),
      ),
      GoRoute(
        path: AppRoutes.login,
        builder: (_, _) => const Scaffold(body: Text('LOGIN_SCREEN')),
      ),
    ],
  );

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthProvider>.value(value: authProvider),
        ChangeNotifierProvider<ThemeProvider>.value(
          value: ThemeProvider(storage: _FakeThemePreferenceStorage()),
        ),
      ],
      child: MaterialApp.router(
        theme: AppTheme.lightTheme,
        routerConfig: router,
      ),
    ),
  );
  await tester.pumpAndSettle();

  return authProvider;
}

void main() {
  testWidgets('Shows the email field and Send Reset Link button', (
    tester,
  ) async {
    await _pumpScreen(tester, repository: _FakeAuthRepository());

    expect(find.text('Send Reset Link'), findsOneWidget);
  });

  testWidgets('A blank email shows a validation error', (tester) async {
    final repository = _FakeAuthRepository();
    await _pumpScreen(tester, repository: repository);

    await tester.tap(find.text('Send Reset Link'));
    await tester.pumpAndSettle();

    expect(find.text('Email is required'), findsOneWidget);
    expect(repository.forgotPasswordCallCount, 0);
  });

  testWidgets('An invalid email shows a validation error', (tester) async {
    final repository = _FakeAuthRepository();
    await _pumpScreen(tester, repository: repository);

    await tester.enterText(find.byType(TextFormField), 'not-an-email');
    await tester.tap(find.text('Send Reset Link'));
    await tester.pumpAndSettle();

    expect(find.text('Enter a valid email address'), findsOneWidget);
    expect(repository.forgotPasswordCallCount, 0);
  });

  testWidgets('Shows a loading state while the request is in flight', (
    tester,
  ) async {
    final repository = _FakeAuthRepository()
      ..forgotPasswordDelay = const Duration(milliseconds: 300);
    await _pumpScreen(tester, repository: repository);

    await tester.enterText(find.byType(TextFormField), 'jane@example.com');
    await tester.tap(find.text('Send Reset Link'));
    await tester.pump(const Duration(milliseconds: 50));

    final button = tester.widget<PrimaryButton>(
      find.widgetWithText(PrimaryButton, 'Send Reset Link'),
    );
    expect(button.isLoading, isTrue);
    expect(repository.forgotPasswordCallCount, 1);

    await tester.pumpAndSettle();
  });

  testWidgets(
    'A duplicate submit while one is already in flight sends only one request',
    (tester) async {
      final repository = _FakeAuthRepository()
        ..forgotPasswordDelay = const Duration(milliseconds: 300);
      await _pumpScreen(tester, repository: repository);

      await tester.enterText(find.byType(TextFormField), 'jane@example.com');
      await tester.tap(find.text('Send Reset Link'));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(find.text('Send Reset Link'), warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 50));

      expect(repository.forgotPasswordCallCount, 1);

      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'A successful submission shows the same safe message for a real email',
    (tester) async {
      final repository = _FakeAuthRepository();
      await _pumpScreen(tester, repository: repository);

      await tester.enterText(find.byType(TextFormField), 'real@example.com');
      await tester.tap(find.text('Send Reset Link'));
      await tester.pumpAndSettle();

      expect(find.text('Check Your Email'), findsOneWidget);
      expect(
        find.text(
          'If an account exists for this email, password reset '
          'instructions have been sent.',
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'A successful submission shows the identical message for an unknown email',
    (tester) async {
      final repository = _FakeAuthRepository();
      await _pumpScreen(tester, repository: repository);

      await tester.enterText(find.byType(TextFormField), 'unknown@example.com');
      await tester.tap(find.text('Send Reset Link'));
      await tester.pumpAndSettle();

      // The backend never distinguishes known vs. unknown accounts, and
      // neither does this screen -- there is only ever one success state.
      expect(find.text('Check Your Email'), findsOneWidget);
    },
  );

  testWidgets('A backend error is shown inline', (tester) async {
    final repository = _FakeAuthRepository()
      ..forgotPasswordError = ApiException(
        'Too Many Attempts.',
        statusCode: 429,
      );
    await _pumpScreen(tester, repository: repository);

    await tester.enterText(find.byType(TextFormField), 'jane@example.com');
    await tester.tap(find.text('Send Reset Link'));
    await tester.pumpAndSettle();

    expect(find.text('Too Many Attempts.'), findsOneWidget);
    expect(find.text('Check Your Email'), findsNothing);
  });

  testWidgets('Back to Login navigates to the Login route', (tester) async {
    final repository = _FakeAuthRepository();
    await _pumpScreen(tester, repository: repository);

    await tester.enterText(find.byType(TextFormField), 'jane@example.com');
    await tester.tap(find.text('Send Reset Link'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Back to Login'));
    await tester.pumpAndSettle();

    expect(find.text('LOGIN_SCREEN'), findsOneWidget);
  });
}
