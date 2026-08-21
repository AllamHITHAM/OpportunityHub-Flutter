// Widget tests for EmailVerificationBanner.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:opportunityhub_flutter/core/api/api_client.dart';
import 'package:opportunityhub_flutter/core/storage/token_storage_service.dart';
import 'package:opportunityhub_flutter/features/auth/data/auth_repository.dart';
import 'package:opportunityhub_flutter/features/auth/presentation/email_verification_banner.dart';
import 'package:opportunityhub_flutter/models/user_model.dart';
import 'package:opportunityhub_flutter/providers/auth_provider.dart';

class _FakeAuthRepository extends AuthRepository {
  _FakeAuthRepository()
    : super(
        apiClient: ApiClient(tokenStorageService: TokenStorageService()),
        tokenStorageService: TokenStorageService(),
      );

  ApiException? resendError;
  Duration resendDelay = Duration.zero;
  int resendCallCount = 0;

  @override
  Future<void> resendVerificationEmail() async {
    resendCallCount++;
    if (resendDelay > Duration.zero) {
      await Future<void>.delayed(resendDelay);
    }
    if (resendError != null) throw resendError!;
  }
}

UserModel _user({required bool emailVerified}) {
  return UserModel(
    id: 1,
    name: 'Jane Doe',
    email: 'jane@example.com',
    role: 'student',
    status: 'active',
    emailVerified: emailVerified,
  );
}

Future<AuthProvider> _pumpBanner(
  WidgetTester tester, {
  required AuthRepository repository,
  UserModel? user,
}) async {
  final authProvider = AuthProvider(authRepository: repository)..user = user;

  await tester.pumpWidget(
    ChangeNotifierProvider<AuthProvider>.value(
      value: authProvider,
      child: const MaterialApp(home: Scaffold(body: EmailVerificationBanner())),
    ),
  );
  await tester.pumpAndSettle();

  return authProvider;
}

void main() {
  testWidgets('Renders nothing when the user is verified', (tester) async {
    await _pumpBanner(
      tester,
      repository: _FakeAuthRepository(),
      user: _user(emailVerified: true),
    );

    expect(find.text('Email not verified'), findsNothing);
    expect(find.byType(SizedBox), findsWidgets);
  });

  testWidgets('Renders nothing when there is no user at all', (tester) async {
    await _pumpBanner(tester, repository: _FakeAuthRepository(), user: null);

    expect(find.text('Email not verified'), findsNothing);
  });

  testWidgets('Shows the unverified banner with a Resend action', (
    tester,
  ) async {
    await _pumpBanner(
      tester,
      repository: _FakeAuthRepository(),
      user: _user(emailVerified: false),
    );

    expect(find.text('Email not verified'), findsOneWidget);
    expect(find.text('Resend'), findsOneWidget);
  });

  testWidgets('Resend calls the provider and shows a SnackBar on success', (
    tester,
  ) async {
    final repository = _FakeAuthRepository();
    await _pumpBanner(
      tester,
      repository: repository,
      user: _user(emailVerified: false),
    );

    await tester.tap(find.text('Resend'));
    await tester.pumpAndSettle();

    expect(repository.resendCallCount, 1);
    expect(find.text('Verification email sent'), findsOneWidget);
  });

  testWidgets('Shows a loading state while the resend is in flight', (
    tester,
  ) async {
    final repository = _FakeAuthRepository()
      ..resendDelay = const Duration(milliseconds: 300);
    await _pumpBanner(
      tester,
      repository: repository,
      user: _user(emailVerified: false),
    );

    await tester.tap(find.text('Resend'));
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Resend'), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    await tester.pumpAndSettle();
  });

  testWidgets('A resend failure shows the backend error via SnackBar', (
    tester,
  ) async {
    final repository = _FakeAuthRepository()
      ..resendError = ApiException('Too Many Attempts.', statusCode: 429);
    await _pumpBanner(
      tester,
      repository: repository,
      user: _user(emailVerified: false),
    );

    await tester.tap(find.text('Resend'));
    await tester.pumpAndSettle();

    expect(find.text('Too Many Attempts.'), findsOneWidget);
  });
}
