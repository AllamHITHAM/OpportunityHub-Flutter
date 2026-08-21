// Widget tests for LoginScreen, in isolation with a small GoRouter.
// Phase 8B-2 added the "Forgot Password?" navigation (previously a UI-only
// no-op) -- this file also covers the pre-existing login form as a
// regression check, since no dedicated test file existed for this screen
// before.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'package:opportunityhub_flutter/core/api/api_client.dart';
import 'package:opportunityhub_flutter/core/storage/token_storage_service.dart';
import 'package:opportunityhub_flutter/core/theme/app_theme.dart';
import 'package:opportunityhub_flutter/features/auth/data/auth_repository.dart';
import 'package:opportunityhub_flutter/features/auth/presentation/login_screen.dart';
import 'package:opportunityhub_flutter/models/user_model.dart';
import 'package:opportunityhub_flutter/providers/auth_provider.dart';
import 'package:opportunityhub_flutter/routes/app_routes.dart';

class _FakeAuthRepository extends AuthRepository {
  _FakeAuthRepository()
    : super(
        apiClient: ApiClient(tokenStorageService: TokenStorageService()),
        tokenStorageService: TokenStorageService(),
      );

  UserModel? loginResult;
  ApiException? loginError;
  int loginCallCount = 0;
  String? lastEmail;
  String? lastPassword;

  @override
  Future<String?> getSavedToken() async => null;

  @override
  Future<UserModel> login(String email, String password) async {
    loginCallCount++;
    lastEmail = email;
    lastPassword = password;
    if (loginError != null) throw loginError!;
    return loginResult ??
        const UserModel(
          id: 1,
          name: 'Jane Doe',
          email: 'jane@example.com',
          role: 'student',
          status: 'active',
        );
  }
}

Future<AuthProvider> _pumpScreen(
  WidgetTester tester, {
  required AuthRepository repository,
}) async {
  final authProvider = AuthProvider(authRepository: repository);
  await authProvider.initialize();

  final router = GoRouter(
    initialLocation: AppRoutes.login,
    routes: [
      GoRoute(path: AppRoutes.login, builder: (_, _) => const LoginScreen()),
      GoRoute(
        path: AppRoutes.forgotPassword,
        builder: (_, _) => const Scaffold(body: Text('FORGOT_PASSWORD_SCREEN')),
      ),
      GoRoute(
        path: AppRoutes.accountTypeSelection,
        builder: (_, _) => const Scaffold(body: Text('ACCOUNT_TYPE_SCREEN')),
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

void main() {
  testWidgets('The Forgot Password? action is visible', (tester) async {
    await _pumpScreen(tester, repository: _FakeAuthRepository());

    expect(find.text('Forgot Password?'), findsOneWidget);
  });

  testWidgets(
    'Tapping Forgot Password? navigates to the Forgot Password screen',
    (tester) async {
      await _pumpScreen(tester, repository: _FakeAuthRepository());

      await tester.tap(find.text('Forgot Password?'));
      await tester.pumpAndSettle();

      expect(find.text('FORGOT_PASSWORD_SCREEN'), findsOneWidget);
    },
  );

  testWidgets('Regression: the login form still renders and submits', (
    tester,
  ) async {
    final repository = _FakeAuthRepository();
    final authProvider = await _pumpScreen(tester, repository: repository);

    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), 'jane@example.com');
    await tester.enterText(fields.at(1), 'password123');
    await tester.tap(find.text('Login'));
    await tester.pumpAndSettle();

    expect(repository.loginCallCount, 1);
    expect(repository.lastEmail, 'jane@example.com');
    expect(repository.lastPassword, 'password123');
    expect(authProvider.isAuthenticated, isTrue);
  });

  testWidgets('Regression: Create Account still navigates', (tester) async {
    await _pumpScreen(tester, repository: _FakeAuthRepository());

    await tester.ensureVisible(find.text('Create Account'));
    await tester.tap(find.text('Create Account'));
    await tester.pumpAndSettle();

    expect(find.text('ACCOUNT_TYPE_SCREEN'), findsOneWidget);
  });

  testWidgets('Regression: a login failure shows the backend error', (
    tester,
  ) async {
    final repository = _FakeAuthRepository()
      ..loginError = ApiException('Invalid credentials', statusCode: 401);
    final authProvider = await _pumpScreen(tester, repository: repository);

    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), 'jane@example.com');
    await tester.enterText(fields.at(1), 'wrong-password');
    await tester.tap(find.text('Login'));
    await tester.pumpAndSettle();

    expect(find.text('Invalid credentials'), findsOneWidget);
    expect(authProvider.isAuthenticated, isFalse);
  });
}
