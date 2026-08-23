// Widget tests for EmailVerifiedScreen, in isolation with a small
// GoRouter, exercising the `status` query parameter via real navigation.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'package:opportunityhub_flutter/core/storage/theme_preference_storage.dart';
import 'package:opportunityhub_flutter/core/theme/app_theme.dart';
import 'package:opportunityhub_flutter/features/auth/presentation/email_verified_screen.dart';
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

Future<void> _pumpScreen(
  WidgetTester tester, {
  required String initialLocation,
}) async {
  final router = GoRouter(
    initialLocation: initialLocation,
    routes: [
      GoRoute(
        path: AppRoutes.emailVerified,
        builder: (_, state) =>
            EmailVerifiedScreen(status: state.uri.queryParameters['status']),
      ),
      GoRoute(
        path: AppRoutes.login,
        builder: (_, _) => const Scaffold(body: Text('LOGIN_SCREEN')),
      ),
    ],
  );

  await tester.pumpWidget(
    ChangeNotifierProvider<ThemeProvider>.value(
      value: ThemeProvider(storage: _FakeThemePreferenceStorage()),
      child: MaterialApp.router(theme: AppTheme.lightTheme, routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('status=success shows the verified state', (tester) async {
    await _pumpScreen(
      tester,
      initialLocation: '/email-verified?status=success',
    );

    expect(find.text('Email Verified'), findsOneWidget);
  });

  testWidgets('status=invalid shows the failure state', (tester) async {
    await _pumpScreen(
      tester,
      initialLocation: '/email-verified?status=invalid',
    );

    expect(find.text('Verification Failed'), findsOneWidget);
  });

  testWidgets('a missing status is treated as failure, not a crash', (
    tester,
  ) async {
    await _pumpScreen(tester, initialLocation: '/email-verified');

    expect(find.text('Verification Failed'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('an unrecognized status value is treated as failure', (
    tester,
  ) async {
    await _pumpScreen(
      tester,
      initialLocation: '/email-verified?status=something-else',
    );

    expect(find.text('Verification Failed'), findsOneWidget);
  });

  testWidgets('Go to Login navigates to the Login route', (tester) async {
    await _pumpScreen(
      tester,
      initialLocation: '/email-verified?status=success',
    );

    await tester.tap(find.text('Go to Login'));
    await tester.pumpAndSettle();

    expect(find.text('LOGIN_SCREEN'), findsOneWidget);
  });
}
