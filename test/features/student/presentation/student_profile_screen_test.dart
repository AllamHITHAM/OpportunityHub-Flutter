// Widget tests for the premium Student Profile screen (UI Phase 3) —
// verifies the hero renders the real authenticated name/email/university/
// major/graduation year, a truthful (non-percentage) readiness checklist,
// real CV/Skills/Education Verification summaries and their navigation to
// the real routes, Logout calls through to the real auth repository, the
// app-bar theme toggle switches the resolved theme, and the layout adapts
// across desktop/tablet/mobile viewports without overflow.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'package:opportunityhub_flutter/core/api/api_client.dart';
import 'package:opportunityhub_flutter/core/storage/theme_preference_storage.dart';
import 'package:opportunityhub_flutter/core/storage/token_storage_service.dart';
import 'package:opportunityhub_flutter/core/theme/app_colors.dart';
import 'package:opportunityhub_flutter/core/theme/app_theme.dart';
import 'package:opportunityhub_flutter/core/widgets/app_widgets.dart';
import 'package:opportunityhub_flutter/features/auth/data/auth_repository.dart';
import 'package:opportunityhub_flutter/features/cv/data/cv_repository.dart';
import 'package:opportunityhub_flutter/features/education_verification/data/education_verification_repository.dart';
import 'package:opportunityhub_flutter/features/skills/data/student_skill_repository.dart';
import 'package:opportunityhub_flutter/features/student/data/student_profile_repository.dart';
import 'package:opportunityhub_flutter/features/student/presentation/student_profile_screen.dart';
import 'package:opportunityhub_flutter/models/cv_model.dart';
import 'package:opportunityhub_flutter/models/education_verification_model.dart';
import 'package:opportunityhub_flutter/models/student_profile_model.dart';
import 'package:opportunityhub_flutter/models/student_skill_model.dart';
import 'package:opportunityhub_flutter/models/user_model.dart';
import 'package:opportunityhub_flutter/providers/auth_provider.dart';
import 'package:opportunityhub_flutter/providers/student_cv_provider.dart';
import 'package:opportunityhub_flutter/providers/student_education_verification_provider.dart';
import 'package:opportunityhub_flutter/providers/student_profile_provider.dart';
import 'package:opportunityhub_flutter/providers/student_skill_provider.dart';
import 'package:opportunityhub_flutter/providers/theme_provider.dart';
import 'package:opportunityhub_flutter/routes/app_routes.dart';

class _FakeAuthRepository extends AuthRepository {
  _FakeAuthRepository()
    : super(
        apiClient: ApiClient(tokenStorageService: TokenStorageService()),
        tokenStorageService: TokenStorageService(),
      );

  int logoutCallCount = 0;

  @override
  Future<String?> getSavedToken() async => null;

  @override
  Future<void> logout() async {
    logoutCallCount++;
  }
}

class _FakeStudentProfileRepository extends StudentProfileRepository {
  _FakeStudentProfileRepository({this.getProfileResult})
    : super(apiClient: ApiClient(tokenStorageService: TokenStorageService()));

  StudentProfileModel? getProfileResult;

  @override
  Future<StudentProfileModel?> getProfile() async => getProfileResult;
}

class _FakeCvRepository extends CvRepository {
  _FakeCvRepository({this.cvs = const [], this.delay})
    : super(apiClient: ApiClient(tokenStorageService: TokenStorageService()));

  List<CvModel> cvs;
  Duration? delay;

  @override
  Future<List<CvModel>> getStudentCvs() async {
    if (delay != null) await Future<void>.delayed(delay!);
    return cvs;
  }
}

class _FakeStudentSkillRepository extends StudentSkillRepository {
  _FakeStudentSkillRepository({this.skills = const []})
    : super(apiClient: ApiClient(tokenStorageService: TokenStorageService()));

  List<StudentSkillModel> skills;

  @override
  Future<List<StudentSkillModel>> getStudentSkills() async => skills;
}

class _FakeEducationVerificationRepository
    extends EducationVerificationRepository {
  _FakeEducationVerificationRepository({required this.status})
    : super(apiClient: ApiClient(tokenStorageService: TokenStorageService()));

  EducationVerificationModel status;

  @override
  Future<EducationVerificationModel> getStatus() async => status;
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

const _notSubmitted = EducationVerificationModel(
  institutionName: null,
  degreeOrProgram: null,
  status: 'not_submitted',
);

Future<
  (
    AuthProvider,
    ThemeProvider,
    StudentCvProvider,
    StudentSkillProvider,
    StudentEducationVerificationProvider,
  )
>
_pumpScreen(
  WidgetTester tester, {
  StudentProfileModel? studentProfile,
  bool emailVerified = true,
  List<CvModel> cvs = const [],
  Duration? cvDelay,
  List<StudentSkillModel> skills = const [],
  EducationVerificationModel verification = _notSubmitted,
  Size surfaceSize = const Size(1400, 1000),
}) async {
  addTearDown(() => AppColors.updateBrightness(Brightness.light));

  tester.view.physicalSize = surfaceSize;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final authProvider = AuthProvider(authRepository: _FakeAuthRepository())
    ..user = UserModel(
      id: 1,
      name: 'Sam Student',
      email: 'sam@example.com',
      role: 'student',
      status: 'active',
      emailVerified: emailVerified,
    );
  final studentProfileProvider = StudentProfileProvider(
    repository: _FakeStudentProfileRepository(getProfileResult: studentProfile),
    authProvider: authProvider,
  )..profile = studentProfile;
  final cvProvider = StudentCvProvider(
    repository: _FakeCvRepository(cvs: cvs, delay: cvDelay),
    studentSkillRepository: _FakeStudentSkillRepository(),
    authProvider: authProvider,
  );
  final skillProvider = StudentSkillProvider(
    repository: _FakeStudentSkillRepository(skills: skills),
    authProvider: authProvider,
  );
  final educationProvider = StudentEducationVerificationProvider(
    repository: _FakeEducationVerificationRepository(status: verification),
    authProvider: authProvider,
  );
  final themeProvider = ThemeProvider(storage: _FakeThemePreferenceStorage());
  await themeProvider.initialize();

  final router = GoRouter(
    initialLocation: AppRoutes.studentProfile,
    routes: [
      GoRoute(
        path: AppRoutes.studentProfile,
        builder: (_, _) => const StudentProfileScreen(),
      ),
      GoRoute(
        path: AppRoutes.studentCvs,
        builder: (_, _) => const Scaffold(body: Text('CVS_SCREEN')),
      ),
      GoRoute(
        path: AppRoutes.studentSkills,
        builder: (_, _) => const Scaffold(body: Text('SKILLS_SCREEN')),
      ),
      GoRoute(
        path: AppRoutes.studentEducationVerification,
        builder: (_, _) => const Scaffold(body: Text('EDUCATION_SCREEN')),
      ),
      GoRoute(
        path: AppRoutes.studentProfileEdit,
        builder: (_, _) => const Scaffold(body: Text('EDIT_PROFILE_SCREEN')),
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
        ChangeNotifierProvider<StudentCvProvider>.value(value: cvProvider),
        ChangeNotifierProvider<StudentSkillProvider>.value(value: skillProvider),
        ChangeNotifierProvider<StudentEducationVerificationProvider>.value(
          value: educationProvider,
        ),
        ChangeNotifierProvider<ThemeProvider>.value(value: themeProvider),
      ],
      child: Builder(
        builder: (context) {
          final mode = context.watch<ThemeProvider>().mode;
          return MaterialApp.router(
            theme: AppTheme.lightTheme,
            darkTheme: AppTheme.darkTheme,
            themeMode: mode,
            routerConfig: router,
          );
        },
      ),
    ),
  );
  await tester.pumpAndSettle();

  return (authProvider, themeProvider, cvProvider, skillProvider, educationProvider);
}

void main() {
  testWidgets('renders the real authenticated student name and email', (
    tester,
  ) async {
    await _pumpScreen(tester);

    expect(find.text('Sam Student'), findsOneWidget);
    expect(find.text('sam@example.com'), findsOneWidget);
  });

  testWidgets(
    'renders real university, major, and graduation year for a full profile',
    (tester) async {
      await _pumpScreen(
        tester,
        studentProfile: const StudentProfileModel(
          id: 1,
          university: 'State University',
          major: 'Computer Science',
          graduationYear: 2027,
        ),
      );

      expect(find.textContaining('Computer Science'), findsWidgets);
      expect(find.textContaining('State University'), findsWidgets);
      expect(find.textContaining('2027'), findsWidgets);
    },
  );

  testWidgets('renders gracefully with no student profile yet (partial data)', (
    tester,
  ) async {
    await _pumpScreen(tester);

    expect(tester.takeException(), isNull);
    expect(find.text('Sam Student'), findsOneWidget);
    // No fabricated N/A rows for the missing university/major/graduation year.
    expect(find.textContaining('N/A'), findsNothing);
  });

  testWidgets('does not overflow with a very long student name', (tester) async {
    final authProvider = AuthProvider(authRepository: _FakeAuthRepository())
      ..user = const UserModel(
        id: 1,
        name:
            'Alexandria Katherine Constantinopoulos-Montgomery-Fitzgerald',
        email: 'alexandria@example.com',
        role: 'student',
        status: 'active',
        emailVerified: true,
      );
    final studentProfileProvider = StudentProfileProvider(
      repository: _FakeStudentProfileRepository(),
      authProvider: authProvider,
    );
    final themeProvider = ThemeProvider(storage: _FakeThemePreferenceStorage());
    await themeProvider.initialize();
    addTearDown(() => AppColors.updateBrightness(Brightness.light));

    final router = GoRouter(
      initialLocation: AppRoutes.studentProfile,
      routes: [
        GoRoute(
          path: AppRoutes.studentProfile,
          builder: (_, _) => const StudentProfileScreen(),
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
          ChangeNotifierProvider<StudentCvProvider>.value(
            value: StudentCvProvider(
              repository: _FakeCvRepository(),
              studentSkillRepository: _FakeStudentSkillRepository(),
              authProvider: authProvider,
            ),
          ),
          ChangeNotifierProvider<StudentSkillProvider>.value(
            value: StudentSkillProvider(
              repository: _FakeStudentSkillRepository(),
              authProvider: authProvider,
            ),
          ),
          ChangeNotifierProvider<StudentEducationVerificationProvider>.value(
            value: StudentEducationVerificationProvider(
              repository: _FakeEducationVerificationRepository(
                status: _notSubmitted,
              ),
              authProvider: authProvider,
            ),
          ),
          ChangeNotifierProvider<ThemeProvider>.value(value: themeProvider),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });

  group('Profile Readiness', () {
    testWidgets('shows attention states when nothing is set up yet', (
      tester,
    ) async {
      await _pumpScreen(tester, emailVerified: false);

      expect(find.text('Profile Readiness'), findsOneWidget);
      expect(find.text('Email verified'), findsOneWidget);
      expect(find.text('CV uploaded'), findsOneWidget);
      // Never a fabricated completion percentage.
      expect(find.textContaining('%'), findsNothing);
    });

    testWidgets('shows done states once real data exists', (tester) async {
      await _pumpScreen(
        tester,
        studentProfile: const StudentProfileModel(
          id: 1,
          university: 'State University',
          major: 'Computer Science',
          graduationYear: 2027,
        ),
        cvs: const [
          CvModel(
            id: 1,
            studentId: 1,
            title: 'My Resume',
            filePath: 'cvs/1/resume.pdf',
            version: 1,
            isDefault: true,
            createdByAi: false,
          ),
        ],
        skills: const [
          StudentSkillModel(
            id: 1,
            skillId: 1,
            skillName: 'Flutter',
            level: 'advanced',
            source: 'manual',
          ),
        ],
        verification: const EducationVerificationModel(
          institutionName: 'State University',
          degreeOrProgram: 'B.Sc. Computer Science',
          status: 'verified',
        ),
      );

      expect(find.text('Profile Readiness'), findsOneWidget);
      expect(find.textContaining('%'), findsNothing);
    });
  });

  group('CV summary', () {
    testWidgets('shows "Add Your First CV" when the student has no CV', (
      tester,
    ) async {
      await _pumpScreen(tester);

      expect(find.text('No CV uploaded yet.'), findsOneWidget);
      expect(find.text('Add Your First CV'), findsOneWidget);
    });

    testWidgets('shows the real CV count and default CV title', (
      tester,
    ) async {
      await _pumpScreen(
        tester,
        cvs: const [
          CvModel(
            id: 1,
            studentId: 1,
            title: 'Software Engineer Resume',
            filePath: 'cvs/1/a.pdf',
            version: 1,
            isDefault: true,
            createdByAi: false,
          ),
          CvModel(
            id: 2,
            studentId: 1,
            title: 'Old Resume',
            filePath: 'cvs/1/b.pdf',
            version: 1,
            isDefault: false,
            createdByAi: false,
          ),
        ],
      );

      expect(find.text('2 CVs on file'), findsOneWidget);
      expect(find.textContaining('Software Engineer Resume'), findsOneWidget);
      expect(find.text('View My CVs'), findsOneWidget);
    });

    testWidgets('"View My CVs" navigates to the real CVs route', (
      tester,
    ) async {
      await _pumpScreen(
        tester,
        cvs: const [
          CvModel(
            id: 1,
            studentId: 1,
            title: 'Resume',
            filePath: 'cvs/1/a.pdf',
            version: 1,
            isDefault: true,
            createdByAi: false,
          ),
        ],
      );

      await tester.tap(find.text('View My CVs'));
      await tester.pumpAndSettle();

      expect(find.text('CVS_SCREEN'), findsOneWidget);
    });
  });

  group('Skills preview', () {
    testWidgets('shows "No skills added yet" when the student has none', (
      tester,
    ) async {
      await _pumpScreen(tester);

      expect(find.text('No skills added yet.'), findsOneWidget);
    });

    testWidgets('shows real skill chips with their evidence source', (
      tester,
    ) async {
      await _pumpScreen(
        tester,
        skills: const [
          StudentSkillModel(
            id: 1,
            skillId: 1,
            skillName: 'Flutter',
            level: 'advanced',
            source: 'manual',
          ),
          StudentSkillModel(
            id: 2,
            skillId: 2,
            skillName: 'Python',
            level: 'intermediate',
            source: 'cv_ai',
          ),
        ],
      );

      expect(find.text('Flutter'), findsOneWidget);
      expect(find.text('Python'), findsOneWidget);
      // Never a fabricated "Verified" label for cv_ai-sourced skills.
      expect(find.text('Verified'), findsNothing);
    });

    testWidgets('"View All Skills" navigates to the real Skills route', (
      tester,
    ) async {
      await _pumpScreen(tester);

      await tester.tap(find.text('View All Skills'));
      await tester.pumpAndSettle();

      expect(find.text('SKILLS_SCREEN'), findsOneWidget);
    });
  });

  group('Education Verification', () {
    testWidgets('shows "Not Submitted" and a Submit CTA by default', (
      tester,
    ) async {
      await _pumpScreen(tester);

      expect(find.text('Not Submitted'), findsOneWidget);
      expect(find.text('Submit Verification'), findsOneWidget);
    });

    testWidgets('shows "Pending Review" for a pending submission', (
      tester,
    ) async {
      await _pumpScreen(
        tester,
        verification: const EducationVerificationModel(
          institutionName: 'State University',
          degreeOrProgram: 'B.Sc. Computer Science',
          status: 'pending',
        ),
      );

      expect(find.text('Pending Review'), findsOneWidget);
      expect(find.text('View Verification'), findsOneWidget);
    });

    testWidgets('shows "Verified" for an approved submission', (
      tester,
    ) async {
      await _pumpScreen(
        tester,
        verification: const EducationVerificationModel(
          institutionName: 'State University',
          degreeOrProgram: 'B.Sc. Computer Science',
          status: 'verified',
        ),
      );

      expect(find.text('Verified'), findsOneWidget);
    });

    testWidgets('shows "Rejected" with a Resubmit CTA', (tester) async {
      await _pumpScreen(
        tester,
        verification: const EducationVerificationModel(
          institutionName: 'State University',
          degreeOrProgram: 'B.Sc. Computer Science',
          status: 'rejected',
          rejectionReason: 'Document unreadable',
        ),
      );

      expect(find.text('Rejected'), findsOneWidget);
      expect(find.text('Resubmit Verification'), findsOneWidget);
    });

    testWidgets('the Submit CTA navigates to the real route', (tester) async {
      await _pumpScreen(tester);

      await tester.tap(find.text('Submit Verification'));
      await tester.pumpAndSettle();

      expect(find.text('EDUCATION_SCREEN'), findsOneWidget);
    });
  });

  group('Account trust', () {
    testWidgets('shows the email-not-verified banner when unverified', (
      tester,
    ) async {
      await _pumpScreen(tester, emailVerified: false);

      expect(find.text('Email not verified'), findsOneWidget);
    });

    testWidgets('hides the email banner once verified', (tester) async {
      await _pumpScreen(tester, emailVerified: true);

      expect(find.text('Email not verified'), findsNothing);
    });

    testWidgets('Logout calls through to the real auth repository', (
      tester,
    ) async {
      final (authProvider, _, _, _, _) = await _pumpScreen(tester);
      final authRepository =
          authProvider.authRepository as _FakeAuthRepository;

      await tester.ensureVisible(find.text('Logout'));
      await tester.tap(find.text('Logout'));
      await tester.pumpAndSettle();

      expect(authRepository.logoutCallCount, 1);
    });
  });

  testWidgets('the app-bar theme toggle switches the resolved theme', (
    tester,
  ) async {
    final (_, themeProvider, _, _, _) = await _pumpScreen(tester);

    expect(themeProvider.isDark, isFalse);

    await tester.tap(find.byType(ThemeToggleButton));
    await tester.pumpAndSettle();

    expect(themeProvider.isDark, isTrue);
    expect(
      Theme.of(tester.element(find.byType(Scaffold).first)).brightness,
      Brightness.dark,
    );

    await tester.tap(find.byType(ThemeToggleButton));
    await tester.pumpAndSettle();

    expect(themeProvider.isDark, isFalse);
  });

  testWidgets('renders without overflow at a wide desktop viewport', (
    tester,
  ) async {
    await _pumpScreen(tester, surfaceSize: const Size(1440, 1000));

    expect(tester.takeException(), isNull);
    expect(find.text('Sam Student'), findsOneWidget);
  });

  testWidgets('renders without overflow at a tablet viewport', (
    tester,
  ) async {
    await _pumpScreen(tester, surfaceSize: const Size(1000, 900));

    expect(tester.takeException(), isNull);
    expect(find.text('Sam Student'), findsOneWidget);
  });

  testWidgets('does not overflow at a narrow 320x720 mobile viewport', (
    tester,
  ) async {
    await _pumpScreen(tester, surfaceSize: const Size(320, 720));

    expect(tester.takeException(), isNull);
    expect(find.text('Sam Student'), findsOneWidget);
  });

  testWidgets('shows a CV skeleton while the CV list is still loading', (
    tester,
  ) async {
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
    final themeProvider = ThemeProvider(storage: _FakeThemePreferenceStorage());
    await themeProvider.initialize();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthProvider>.value(value: authProvider),
          ChangeNotifierProvider<StudentProfileProvider>.value(
            value: StudentProfileProvider(
              repository: _FakeStudentProfileRepository(),
              authProvider: authProvider,
            ),
          ),
          ChangeNotifierProvider<StudentCvProvider>.value(
            value: StudentCvProvider(
              repository: _FakeCvRepository(
                delay: const Duration(milliseconds: 200),
              ),
              studentSkillRepository: _FakeStudentSkillRepository(),
              authProvider: authProvider,
            ),
          ),
          ChangeNotifierProvider<StudentSkillProvider>.value(
            value: StudentSkillProvider(
              repository: _FakeStudentSkillRepository(),
              authProvider: authProvider,
            ),
          ),
          ChangeNotifierProvider<StudentEducationVerificationProvider>.value(
            value: StudentEducationVerificationProvider(
              repository: _FakeEducationVerificationRepository(
                status: _notSubmitted,
              ),
              authProvider: authProvider,
            ),
          ),
          ChangeNotifierProvider<ThemeProvider>.value(value: themeProvider),
        ],
        child: MaterialApp(
          theme: AppTheme.lightTheme,
          home: const StudentProfileScreen(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.byType(AppSkeleton), findsWidgets);

    await tester.pumpAndSettle(const Duration(milliseconds: 250));
  });

  testWidgets('honors reduced motion without throwing', (tester) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);

    await _pumpScreen(tester);

    expect(tester.takeException(), isNull);
    expect(find.text('Sam Student'), findsOneWidget);
  });

  group('Edit Profile', () {
    testWidgets('shows a labeled Edit Profile action on a wide desktop hero', (
      tester,
    ) async {
      await _pumpScreen(tester, surfaceSize: const Size(1440, 1000));

      expect(find.text('Edit Profile'), findsOneWidget);
    });

    testWidgets(
      'shows a compact Edit Profile icon action on a narrow mobile hero',
      (tester) async {
        await _pumpScreen(tester, surfaceSize: const Size(375, 800));

        expect(find.text('Edit Profile'), findsNothing);
        expect(find.byIcon(Icons.edit_outlined), findsOneWidget);
      },
    );

    testWidgets('navigates to the real Edit Profile route', (tester) async {
      await _pumpScreen(tester, surfaceSize: const Size(1440, 1000));

      await tester.tap(find.text('Edit Profile'));
      await tester.pumpAndSettle();

      expect(find.text('EDIT_PROFILE_SCREEN'), findsOneWidget);
    });
  });

  group('Contact section', () {
    testWidgets('renders nothing when phone and bio are both unset', (
      tester,
    ) async {
      await _pumpScreen(
        tester,
        studentProfile: const StudentProfileModel(
          id: 1,
          university: 'State University',
          major: 'Computer Science',
          graduationYear: 2027,
        ),
      );

      expect(find.text('Contact'), findsNothing);
    });

    testWidgets('renders real phone and bio when set', (tester) async {
      await _pumpScreen(
        tester,
        studentProfile: const StudentProfileModel(
          id: 1,
          university: 'State University',
          major: 'Computer Science',
          graduationYear: 2027,
          phone: '0791234567',
          bio: 'A motivated computer science student.',
        ),
      );

      expect(find.text('Contact'), findsOneWidget);
      expect(find.text('0791234567'), findsOneWidget);
      expect(
        find.text('A motivated computer science student.'),
        findsOneWidget,
      );
    });
  });
}
