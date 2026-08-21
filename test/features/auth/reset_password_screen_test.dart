// Widget tests for ResetPasswordScreen, in isolation with a small
// GoRouter, exercising query-parameter parsing via real navigation.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'package:opportunityhub_flutter/core/api/api_client.dart';
import 'package:opportunityhub_flutter/core/storage/token_storage_service.dart';
import 'package:opportunityhub_flutter/core/theme/app_theme.dart';
import 'package:opportunityhub_flutter/core/widgets/primary_button.dart';
import 'package:opportunityhub_flutter/features/auth/data/auth_repository.dart';
import 'package:opportunityhub_flutter/features/auth/presentation/reset_password_screen.dart';
import 'package:opportunityhub_flutter/providers/auth_provider.dart';
import 'package:opportunityhub_flutter/routes/app_routes.dart';

class _FakeAuthRepository extends AuthRepository {
  _FakeAuthRepository()
    : super(
        apiClient: ApiClient(tokenStorageService: TokenStorageService()),
        tokenStorageService: TokenStorageService(),
      );

  ApiException? resetPasswordError;
  int resetPasswordCallCount = 0;
  String? lastEmail;
  String? lastToken;
  String? lastPassword;

  @override
  Future<void> resetPassword({
    required String email,
    required String token,
    required String password,
  }) async {
    resetPasswordCallCount++;
    lastEmail = email;
    lastToken = token;
    lastPassword = password;
    if (resetPasswordError != null) throw resetPasswordError!;
  }
}

Future<AuthProvider> _pumpScreen(
  WidgetTester tester, {
  required AuthRepository repository,
  String initialLocation =
      '/reset-password?token=real-token&email=jane%40example.com',
}) async {
  final authProvider = AuthProvider(authRepository: repository);

  final router = GoRouter(
    initialLocation: initialLocation,
    routes: [
      GoRoute(
        path: AppRoutes.resetPassword,
        builder: (_, state) => ResetPasswordScreen(
          token: state.uri.queryParameters['token'],
          email: state.uri.queryParameters['email'],
        ),
      ),
      GoRoute(
        path: AppRoutes.login,
        builder: (_, _) => const Scaffold(body: Text('LOGIN_SCREEN')),
      ),
      GoRoute(
        path: AppRoutes.forgotPassword,
        builder: (_, _) => const Scaffold(body: Text('FORGOT_PASSWORD_SCREEN')),
      ),
    ],
  );

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthProvider>.value(value: authProvider),
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

Finder _passwordField(String label) =>
    find.ancestor(of: find.text(label), matching: find.byType(TextFormField));

void main() {
  testWidgets('Reads token and email from the route query parameters', (
    tester,
  ) async {
    await _pumpScreen(tester, repository: _FakeAuthRepository());

    expect(find.text('jane@example.com'), findsOneWidget);
    expect(find.text('New Password'), findsOneWidget);
    expect(find.text('Confirm Password'), findsOneWidget);
  });

  testWidgets('A missing token shows a safe invalid-link state, not a crash', (
    tester,
  ) async {
    await _pumpScreen(
      tester,
      repository: _FakeAuthRepository(),
      initialLocation: '/reset-password?email=jane%40example.com',
    );

    expect(find.text('Invalid Reset Link'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('A missing email shows a safe invalid-link state, not a crash', (
    tester,
  ) async {
    await _pumpScreen(
      tester,
      repository: _FakeAuthRepository(),
      initialLocation: '/reset-password?token=real-token',
    );

    expect(find.text('Invalid Reset Link'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('No query parameters at all shows a safe invalid-link state', (
    tester,
  ) async {
    await _pumpScreen(
      tester,
      repository: _FakeAuthRepository(),
      initialLocation: '/reset-password',
    );

    expect(find.text('Invalid Reset Link'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Request New Link navigates to Forgot Password', (tester) async {
    await _pumpScreen(
      tester,
      repository: _FakeAuthRepository(),
      initialLocation: '/reset-password',
    );

    await tester.tap(find.text('Request New Link'));
    await tester.pumpAndSettle();

    expect(find.text('FORGOT_PASSWORD_SCREEN'), findsOneWidget);
  });

  testWidgets('Blank passwords show validation errors', (tester) async {
    final repository = _FakeAuthRepository();
    await _pumpScreen(tester, repository: repository);

    await tester.tap(find.widgetWithText(PrimaryButton, 'Reset Password'));
    await tester.pumpAndSettle();

    expect(find.text('Password is required'), findsOneWidget);
    expect(find.text('Please confirm your password'), findsOneWidget);
    expect(repository.resetPasswordCallCount, 0);
  });

  testWidgets('A short password is rejected', (tester) async {
    final repository = _FakeAuthRepository();
    await _pumpScreen(tester, repository: repository);

    await tester.enterText(_passwordField('New Password'), 'short');
    await tester.enterText(_passwordField('Confirm Password'), 'short');
    await tester.tap(find.widgetWithText(PrimaryButton, 'Reset Password'));
    await tester.pumpAndSettle();

    expect(find.text('Password must be at least 8 characters'), findsOneWidget);
    expect(repository.resetPasswordCallCount, 0);
  });

  testWidgets('A confirmation mismatch is rejected', (tester) async {
    final repository = _FakeAuthRepository();
    await _pumpScreen(tester, repository: repository);

    await tester.enterText(_passwordField('New Password'), 'new-password-456');
    await tester.enterText(
      _passwordField('Confirm Password'),
      'different-password',
    );
    await tester.tap(find.widgetWithText(PrimaryButton, 'Reset Password'));
    await tester.pumpAndSettle();

    expect(find.text('Passwords do not match'), findsOneWidget);
    expect(repository.resetPasswordCallCount, 0);
  });

  testWidgets(
    'A valid submission succeeds, sends the token/email, and shows a success state',
    (tester) async {
      final repository = _FakeAuthRepository();
      await _pumpScreen(tester, repository: repository);

      await tester.enterText(
        _passwordField('New Password'),
        'new-password-456',
      );
      await tester.enterText(
        _passwordField('Confirm Password'),
        'new-password-456',
      );
      await tester.tap(find.widgetWithText(PrimaryButton, 'Reset Password'));
      await tester.pumpAndSettle();

      expect(repository.resetPasswordCallCount, 1);
      expect(repository.lastEmail, 'jane@example.com');
      expect(repository.lastToken, 'real-token');
      expect(repository.lastPassword, 'new-password-456');
      expect(find.text('Password Reset'), findsOneWidget);
    },
  );

  testWidgets(
    'An invalid/expired token backend error is shown, form stays visible',
    (tester) async {
      final repository = _FakeAuthRepository()
        ..resetPasswordError = ApiException(
          'This password reset token is invalid.',
          statusCode: 422,
        );
      await _pumpScreen(tester, repository: repository);

      await tester.enterText(
        _passwordField('New Password'),
        'new-password-456',
      );
      await tester.enterText(
        _passwordField('Confirm Password'),
        'new-password-456',
      );
      await tester.tap(find.widgetWithText(PrimaryButton, 'Reset Password'));
      await tester.pumpAndSettle();

      expect(
        find.text('This password reset token is invalid.'),
        findsOneWidget,
      );
      expect(find.text('Password Reset'), findsNothing);
    },
  );

  testWidgets('Go to Login navigates to the Login route, no auto-login', (
    tester,
  ) async {
    final repository = _FakeAuthRepository();
    final authProvider = await _pumpScreen(tester, repository: repository);

    await tester.enterText(_passwordField('New Password'), 'new-password-456');
    await tester.enterText(
      _passwordField('Confirm Password'),
      'new-password-456',
    );
    await tester.tap(find.widgetWithText(PrimaryButton, 'Reset Password'));
    await tester.pumpAndSettle();

    expect(authProvider.isAuthenticated, isFalse);

    await tester.tap(find.text('Go to Login'));
    await tester.pumpAndSettle();

    expect(find.text('LOGIN_SCREEN'), findsOneWidget);
    expect(authProvider.isAuthenticated, isFalse);
  });
}
