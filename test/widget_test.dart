// A basic widget test for the authentication foundation.
//
// It uses a fake AuthRepository (instead of the real one) so the test
// never touches secure storage or the network, and can run anywhere.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:opportunityhub_flutter/core/api/api_client.dart';
import 'package:opportunityhub_flutter/core/storage/token_storage_service.dart';
import 'package:opportunityhub_flutter/core/theme/app_theme.dart';
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

Widget _buildApp(AuthProvider authProvider) {
  final studentProfileProvider = StudentProfileProvider(
    repository: _FakeStudentProfileRepository(),
    authProvider: authProvider,
  );
  final organizationProfileProvider = OrganizationProfileProvider(
    repository: _FakeOrganizationProfileRepository(),
    authProvider: authProvider,
  );
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<AuthProvider>.value(value: authProvider),
      ChangeNotifierProvider<StudentProfileProvider>.value(
        value: studentProfileProvider,
      ),
      ChangeNotifierProvider<OrganizationProfileProvider>.value(
        value: organizationProfileProvider,
      ),
      ChangeNotifierProvider<ThemeProvider>.value(value: ThemeProvider()),
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

void main() {
  testWidgets('An unauthenticated user is redirected to the login screen', (
    WidgetTester tester,
  ) async {
    final authProvider = AuthProvider(authRepository: _FakeAuthRepository());

    await tester.pumpWidget(_buildApp(authProvider));
    await authProvider.initialize();
    await tester.pumpAndSettle();

    expect(find.text('Login'), findsWidgets);
    expect(find.byType(TextField), findsNWidgets(2));
    expect(find.widgetWithText(ElevatedButton, 'Login'), findsOneWidget);
  });
}
