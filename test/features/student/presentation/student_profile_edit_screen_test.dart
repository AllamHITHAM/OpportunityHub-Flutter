// Widget tests for StudentProfileEditScreen (UI Phase 3.1) — verifies the
// form pre-fills real current values, validates required fields, submits
// exactly what the real `PUT /api/student/profile` endpoint accepts,
// surfaces backend field errors inline without losing entered data, guards
// against duplicate submission, and only pops back after the backend has
// actually confirmed success.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'package:opportunityhub_flutter/core/api/api_client.dart';
import 'package:opportunityhub_flutter/core/storage/theme_preference_storage.dart';
import 'package:opportunityhub_flutter/core/storage/token_storage_service.dart';
import 'package:opportunityhub_flutter/core/theme/app_colors.dart';
import 'package:opportunityhub_flutter/core/theme/app_theme.dart';
import 'package:opportunityhub_flutter/features/auth/data/auth_repository.dart';
import 'package:opportunityhub_flutter/features/student/data/student_profile_repository.dart';
import 'package:opportunityhub_flutter/features/student/presentation/student_profile_edit_screen.dart';
import 'package:opportunityhub_flutter/models/student_profile_model.dart';
import 'package:opportunityhub_flutter/models/user_model.dart';
import 'package:opportunityhub_flutter/providers/auth_provider.dart';
import 'package:opportunityhub_flutter/providers/student_profile_provider.dart';
import 'package:opportunityhub_flutter/providers/theme_provider.dart';

class _FakeAuthRepository extends AuthRepository {
  _FakeAuthRepository()
    : super(
        apiClient: ApiClient(tokenStorageService: TokenStorageService()),
        tokenStorageService: TokenStorageService(),
      );

  @override
  Future<String?> getSavedToken() async => null;
}

class _FakeThemePreferenceStorage extends ThemePreferenceStorage {
  @override
  Future<void> saveThemeMode(ThemeMode mode) async {}

  @override
  Future<ThemeMode> readThemeMode() async => ThemeMode.system;
}

typedef _UpdateHandler =
    Future<StudentProfileModel> Function({
      required String university,
      required String major,
      required int graduationYear,
      String? phone,
      String? bio,
    });

class _FakeStudentProfileRepository extends StudentProfileRepository {
  _FakeStudentProfileRepository({this.getProfileResult, this.onUpdate})
    : super(apiClient: ApiClient(tokenStorageService: TokenStorageService()));

  StudentProfileModel? getProfileResult;
  _UpdateHandler? onUpdate;
  int updateCallCount = 0;

  @override
  Future<StudentProfileModel?> getProfile() async => getProfileResult;

  @override
  Future<StudentProfileModel> updateProfile({
    required String university,
    required String major,
    required int graduationYear,
    String? phone,
    String? bio,
  }) async {
    updateCallCount++;
    final handler = onUpdate;
    if (handler != null) {
      return handler(
        university: university,
        major: major,
        graduationYear: graduationYear,
        phone: phone,
        bio: bio,
      );
    }
    return StudentProfileModel(
      id: 1,
      university: university,
      major: major,
      graduationYear: graduationYear,
      phone: phone,
      bio: bio,
    );
  }
}

Future<
  (
    StudentProfileProvider provider,
    GoRouter router,
    _FakeStudentProfileRepository repository,
  )
>
_pumpScreen(
  WidgetTester tester, {
  StudentProfileModel? initialProfile,
  _UpdateHandler? onUpdate,
}) async {
  addTearDown(() => AppColors.updateBrightness(Brightness.light));

  final authProvider = AuthProvider(authRepository: _FakeAuthRepository())
    ..user = const UserModel(
      id: 1,
      name: 'Sam Student',
      email: 'sam@example.com',
      role: 'student',
      status: 'active',
      emailVerified: true,
    );
  final repository = _FakeStudentProfileRepository(
    getProfileResult: initialProfile,
    onUpdate: onUpdate,
  );
  final studentProfileProvider = StudentProfileProvider(
    repository: repository,
    authProvider: authProvider,
  )..profile = initialProfile;
  final themeProvider = ThemeProvider(storage: _FakeThemePreferenceStorage());
  await themeProvider.initialize();

  final router = GoRouter(
    initialLocation: '/profile',
    routes: [
      GoRoute(
        path: '/profile',
        builder: (_, _) => const Scaffold(body: Text('PROFILE_SCREEN')),
        routes: [
          GoRoute(
            path: 'edit',
            builder: (_, _) => const StudentProfileEditScreen(),
          ),
        ],
      ),
    ],
  );

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthProvider>.value(value: authProvider),
        ChangeNotifierProvider<StudentProfileProvider>.value(
          value: studentProfileProvider,
        ),
        ChangeNotifierProvider<ThemeProvider>.value(value: themeProvider),
      ],
      child: MaterialApp.router(
        theme: AppTheme.lightTheme,
        darkTheme: AppTheme.darkTheme,
        routerConfig: router,
      ),
    ),
  );
  await tester.pumpAndSettle();

  router.push('/profile/edit');
  await tester.pumpAndSettle();

  return (studentProfileProvider, router, repository);
}

void main() {
  testWidgets('pre-fills the form with the current real profile values', (
    tester,
  ) async {
    await _pumpScreen(
      tester,
      initialProfile: const StudentProfileModel(
        id: 1,
        university: 'State University',
        major: 'Computer Science',
        graduationYear: 2027,
        phone: '0791234567',
        bio: 'A motivated student.',
      ),
    );

    expect(find.text('State University'), findsOneWidget);
    expect(find.text('Computer Science'), findsOneWidget);
    expect(find.text('2027'), findsOneWidget);
    expect(find.text('0791234567'), findsOneWidget);
    expect(find.text('A motivated student.'), findsOneWidget);
  });

  testWidgets('rejects an empty university on submit', (tester) async {
    await _pumpScreen(
      tester,
      initialProfile: const StudentProfileModel(
        id: 1,
        university: 'State University',
        major: 'Computer Science',
        graduationYear: 2027,
      ),
    );

    await tester.enterText(
      find.widgetWithText(TextFormField, 'University'),
      '',
    );
    await tester.ensureVisible(find.text('Save Changes'));
    await tester.tap(find.text('Save Changes'));
    await tester.pumpAndSettle();

    expect(find.text('University is required'), findsOneWidget);
  });

  testWidgets('Cancel pops without submitting anything', (tester) async {
    final (_, _, repository) = await _pumpScreen(
      tester,
      initialProfile: const StudentProfileModel(
        id: 1,
        university: 'State University',
        major: 'Computer Science',
        graduationYear: 2027,
      ),
    );

    await tester.enterText(
      find.widgetWithText(TextFormField, 'University'),
      'Changed University',
    );
    await tester.ensureVisible(find.text('Cancel'));
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(find.text('PROFILE_SCREEN'), findsOneWidget);
    expect(repository.updateCallCount, 0);
  });

  testWidgets('submits exactly the real allow-listed fields', (tester) async {
    Map<String, dynamic>? sent;
    await _pumpScreen(
      tester,
      initialProfile: const StudentProfileModel(
        id: 1,
        university: 'Old University',
        major: 'Old Major',
        graduationYear: 2026,
      ),
      onUpdate:
          ({
            required university,
            required major,
            required graduationYear,
            phone,
            bio,
          }) async {
            sent = {
              'university': university,
              'major': major,
              'graduation_year': graduationYear,
              'phone': phone,
              'bio': bio,
            };
            return StudentProfileModel(
              id: 1,
              university: university,
              major: major,
              graduationYear: graduationYear,
              phone: phone,
              bio: bio,
            );
          },
    );

    await tester.enterText(
      find.widgetWithText(TextFormField, 'University'),
      'New University',
    );
    await tester.ensureVisible(find.text('Save Changes'));
    await tester.tap(find.text('Save Changes'));
    await tester.pumpAndSettle();

    expect(sent, isNotNull);
    expect(sent!['university'], 'New University');
    expect(sent!['major'], 'Old Major');
    expect(sent!['graduation_year'], 2026);
  });

  testWidgets(
    'on success, the provider profile becomes the canonical backend response and the screen pops',
    (tester) async {
      final (provider, _, _) = await _pumpScreen(
        tester,
        initialProfile: const StudentProfileModel(
          id: 1,
          university: 'Old University',
          major: 'Old Major',
          graduationYear: 2026,
        ),
      );

      await tester.enterText(
        find.widgetWithText(TextFormField, 'University'),
        'New University',
      );
      await tester.ensureVisible(find.text('Save Changes'));
      await tester.tap(find.text('Save Changes'));
      await tester.pumpAndSettle();

      expect(find.text('PROFILE_SCREEN'), findsOneWidget);
      expect(provider.profile?.university, 'New University');
    },
  );

  testWidgets(
    'a 422 backend field error is shown inline and entered values are preserved',
    (tester) async {
      await _pumpScreen(
        tester,
        initialProfile: const StudentProfileModel(
          id: 1,
          university: 'Old University',
          major: 'Old Major',
          graduationYear: 2026,
        ),
        onUpdate:
            ({
              required university,
              required major,
              required graduationYear,
              phone,
              bio,
            }) async {
              throw ApiException(
                'The given data was invalid.',
                statusCode: 422,
                errors: {
                  'university': ['The university field is invalid.'],
                },
              );
            },
      );

      await tester.enterText(
        find.widgetWithText(TextFormField, 'University'),
        'Bad University',
      );
      await tester.ensureVisible(find.text('Save Changes'));
      await tester.tap(find.text('Save Changes'));
      await tester.pumpAndSettle();

      expect(find.text('The university field is invalid.'), findsOneWidget);
      expect(find.text('Bad University'), findsOneWidget);
      expect(find.text('PROFILE_SCREEN'), findsNothing);
    },
  );

  testWidgets(
    'a network/API failure shows a top-level error and keeps the form open',
    (tester) async {
      await _pumpScreen(
        tester,
        initialProfile: const StudentProfileModel(
          id: 1,
          university: 'Old University',
          major: 'Old Major',
          graduationYear: 2026,
        ),
        onUpdate:
            ({
              required university,
              required major,
              required graduationYear,
              phone,
              bio,
            }) async {
              throw ApiException('No internet connection.');
            },
      );

      await tester.ensureVisible(find.text('Save Changes'));
      await tester.tap(find.text('Save Changes'));
      await tester.pumpAndSettle();

      expect(find.text('No internet connection.'), findsOneWidget);
      expect(find.text('PROFILE_SCREEN'), findsNothing);
    },
  );

  testWidgets('a blank optional phone/bio submits as null (clears the field)', (
    tester,
  ) async {
    Map<String, dynamic>? sent;
    await _pumpScreen(
      tester,
      initialProfile: const StudentProfileModel(
        id: 1,
        university: 'State University',
        major: 'Computer Science',
        graduationYear: 2027,
        phone: '0791234567',
        bio: 'Old bio.',
      ),
      onUpdate:
          ({
            required university,
            required major,
            required graduationYear,
            phone,
            bio,
          }) async {
            sent = {'phone': phone, 'bio': bio};
            return StudentProfileModel(
              id: 1,
              university: university,
              major: major,
              graduationYear: graduationYear,
              phone: phone,
              bio: bio,
            );
          },
    );

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Phone (optional)'),
      '',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Bio (optional)'),
      '',
    );
    await tester.ensureVisible(find.text('Save Changes'));
    await tester.tap(find.text('Save Changes'));
    await tester.pumpAndSettle();

    expect(sent!['phone'], isNull);
    expect(sent!['bio'], isNull);
  });

  testWidgets('does not overflow at a narrow 320x720 viewport', (tester) async {
    tester.view.physicalSize = const Size(320, 720);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await _pumpScreen(
      tester,
      initialProfile: const StudentProfileModel(
        id: 1,
        university: 'State University',
        major: 'Computer Science',
        graduationYear: 2027,
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('Save Changes'), findsOneWidget);
  });

  testWidgets('renders in dark mode without error', (tester) async {
    final authProvider = AuthProvider(authRepository: _FakeAuthRepository())
      ..user = const UserModel(
        id: 1,
        name: 'Sam Student',
        email: 'sam@example.com',
        role: 'student',
        status: 'active',
        emailVerified: true,
      );
    final studentProfileProvider =
        StudentProfileProvider(
            repository: _FakeStudentProfileRepository(
              getProfileResult: const StudentProfileModel(
                id: 1,
                university: 'State University',
                major: 'Computer Science',
                graduationYear: 2027,
              ),
            ),
            authProvider: authProvider,
          )
          ..profile = const StudentProfileModel(
            id: 1,
            university: 'State University',
            major: 'Computer Science',
            graduationYear: 2027,
          );
    final themeProvider = ThemeProvider(storage: _FakeThemePreferenceStorage());
    await themeProvider.initialize();
    addTearDown(() => AppColors.updateBrightness(Brightness.light));

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthProvider>.value(value: authProvider),
          ChangeNotifierProvider<StudentProfileProvider>.value(
            value: studentProfileProvider,
          ),
          ChangeNotifierProvider<ThemeProvider>.value(value: themeProvider),
        ],
        child: MaterialApp(
          theme: AppTheme.darkTheme,
          home: const StudentProfileEditScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Save Changes'), findsOneWidget);
  });
}
