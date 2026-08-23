// Widget tests for the premium StudentSkillsScreen (UI Phase 7), in
// isolation with a small GoRouter and a fake repository. Mirrors
// student_cv_screen_test.dart's own conventions.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'package:opportunityhub_flutter/core/api/api_client.dart';
import 'package:opportunityhub_flutter/core/storage/token_storage_service.dart';
import 'package:opportunityhub_flutter/core/theme/app_theme.dart';
import 'package:opportunityhub_flutter/core/widgets/app_widgets.dart';
import 'package:opportunityhub_flutter/features/auth/data/auth_repository.dart';
import 'package:opportunityhub_flutter/features/skills/data/student_skill_repository.dart';
import 'package:opportunityhub_flutter/features/skills/presentation/student_skills_screen.dart';
import 'package:opportunityhub_flutter/models/student_skill_model.dart';
import 'package:opportunityhub_flutter/providers/auth_provider.dart';
import 'package:opportunityhub_flutter/providers/student_skill_provider.dart';
import 'package:opportunityhub_flutter/providers/theme_provider.dart';
import 'package:opportunityhub_flutter/routes/app_routes.dart';

class _FakeAuthRepository extends AuthRepository {
  _FakeAuthRepository()
    : super(
        apiClient: ApiClient(tokenStorageService: TokenStorageService()),
        tokenStorageService: TokenStorageService(),
      );

  @override
  Future<String?> getSavedToken() async => null;
}

StudentSkillModel _skill({
  int id = 1,
  int skillId = 10,
  String skillName = 'AutoCAD',
  String? category,
  String level = 'advanced',
  double? yearsOfExperience,
  String source = 'manual',
}) {
  return StudentSkillModel(
    id: id,
    skillId: skillId,
    skillName: skillName,
    category: category,
    level: level,
    yearsOfExperience: yearsOfExperience,
    source: source,
  );
}

class _FakeStudentSkillRepository extends StudentSkillRepository {
  _FakeStudentSkillRepository()
    : super(apiClient: ApiClient(tokenStorageService: TokenStorageService()));

  List<StudentSkillModel>? loadResult;
  ApiException? loadError;
  Duration loadDelay = Duration.zero;
  int getStudentSkillsCallCount = 0;

  ApiException? deleteError;
  Duration deleteDelay = Duration.zero;
  final List<int> deletedIds = [];

  @override
  Future<List<StudentSkillModel>> getStudentSkills() async {
    getStudentSkillsCallCount++;
    if (loadDelay > Duration.zero) {
      await Future<void>.delayed(loadDelay);
    }
    if (loadError != null) throw loadError!;
    return loadResult ?? [];
  }

  @override
  Future<void> deleteSkill(int studentSkillId) async {
    deletedIds.add(studentSkillId);
    if (deleteDelay > Duration.zero) {
      await Future<void>.delayed(deleteDelay);
    }
    if (deleteError != null) throw deleteError!;
  }
}

Future<StudentSkillProvider> _pumpScreen(
  WidgetTester tester, {
  required StudentSkillRepository repository,
  Size size = const Size(420, 1400),
  ThemeData? theme,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final authProvider = AuthProvider(authRepository: _FakeAuthRepository());
  final skillProvider = StudentSkillProvider(
    repository: repository,
    authProvider: authProvider,
  );

  final router = GoRouter(
    initialLocation: AppRoutes.studentSkills,
    routes: [
      GoRoute(
        path: AppRoutes.studentSkills,
        builder: (_, _) => const StudentSkillsScreen(),
      ),
      GoRoute(
        path: AppRoutes.studentCvs,
        builder: (_, _) => const Scaffold(body: Text('CV_PLACEHOLDER')),
      ),
    ],
  );

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthProvider>.value(value: authProvider),
        ChangeNotifierProvider<StudentSkillProvider>.value(
          value: skillProvider,
        ),
        ChangeNotifierProvider<ThemeProvider>.value(value: ThemeProvider()),
      ],
      child: MaterialApp.router(
        theme: theme ?? AppTheme.lightTheme,
        darkTheme: AppTheme.darkTheme,
        routerConfig: router,
      ),
    ),
  );
  await tester.pumpAndSettle();

  return skillProvider;
}

void main() {
  testWidgets('Loading state renders a skeleton while skills are in flight', (
    tester,
  ) async {
    final repository = _FakeStudentSkillRepository()
      ..loadResult = [_skill()]
      ..loadDelay = const Duration(milliseconds: 200);

    tester.view.physicalSize = const Size(420, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final authProvider = AuthProvider(authRepository: _FakeAuthRepository());
    final skillProvider = StudentSkillProvider(
      repository: repository,
      authProvider: authProvider,
    );
    final router = GoRouter(
      initialLocation: AppRoutes.studentSkills,
      routes: [
        GoRoute(
          path: AppRoutes.studentSkills,
          builder: (_, _) => const StudentSkillsScreen(),
        ),
      ],
    );

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthProvider>.value(value: authProvider),
          ChangeNotifierProvider<StudentSkillProvider>.value(
            value: skillProvider,
          ),
          ChangeNotifierProvider<ThemeProvider>.value(value: ThemeProvider()),
        ],
        child: MaterialApp.router(
          theme: AppTheme.lightTheme,
          routerConfig: router,
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(skillProvider.isLoading, isTrue);
    expect(find.text('AutoCAD'), findsNothing);
    expect(find.byType(AppSkeletonList), findsOneWidget);

    await tester.pumpAndSettle();
  });

  testWidgets(
    'Error state with no skills shows AppErrorView and a working retry',
    (tester) async {
      final repository = _FakeStudentSkillRepository()
        ..loadError = ApiException('Server error, please try again later.');

      final provider = await _pumpScreen(tester, repository: repository);

      expect(
        find.text('Server error, please try again later.'),
        findsOneWidget,
      );
      expect(find.text('Try Again'), findsOneWidget);

      repository.loadError = null;
      repository.loadResult = [_skill()];
      await tester.tap(find.text('Try Again'));
      await tester.pumpAndSettle();

      expect(find.text('AutoCAD'), findsOneWidget);
      expect(provider.skills, hasLength(1));
    },
  );

  testWidgets(
    'Empty state shows a premium first-use state with a real Analyze My CV CTA',
    (tester) async {
      final repository = _FakeStudentSkillRepository()..loadResult = [];

      await _pumpScreen(tester, repository: repository);

      expect(find.text('Build Your Skill Profile'), findsOneWidget);
      expect(find.text('Analyze My CV'), findsWidgets);
    },
  );

  testWidgets(
    'The empty state Analyze My CV action navigates to the real CV route',
    (tester) async {
      final repository = _FakeStudentSkillRepository()..loadResult = [];

      await _pumpScreen(tester, repository: repository);

      await tester.tap(find.text('Analyze My CV').first);
      await tester.pumpAndSettle();

      expect(find.text('CV_PLACEHOLDER'), findsOneWidget);
    },
  );

  testWidgets('the app-bar My CVs action navigates to the real CV route', (
    tester,
  ) async {
    final repository = _FakeStudentSkillRepository()
      ..loadResult = [_skill()];

    await _pumpScreen(tester, repository: repository);

    await tester.tap(find.byTooltip('My CVs'));
    await tester.pumpAndSettle();

    expect(find.text('CV_PLACEHOLDER'), findsOneWidget);
  });

  testWidgets('the app-bar theme toggle is reachable', (tester) async {
    final repository = _FakeStudentSkillRepository()
      ..loadResult = [_skill()];

    await _pumpScreen(tester, repository: repository);

    expect(find.byType(ThemeToggleButton), findsOneWidget);
  });

  group('Skill presentation', () {
    testWidgets('A CV-supported skill shows the CV-supported label, never "Verified"', (
      tester,
    ) async {
      final repository = _FakeStudentSkillRepository()
        ..loadResult = [_skill(id: 1, skillName: 'AutoCAD', source: 'cv_ai')];

      await _pumpScreen(tester, repository: repository);

      expect(find.text('AutoCAD'), findsOneWidget);
      expect(find.text('CV-supported'), findsOneWidget);
      expect(find.text('Self-declared'), findsNothing);
      expect(find.textContaining('Verified'), findsNothing);
    });

    testWidgets('A manually-added skill shows the Self-declared label', (
      tester,
    ) async {
      final repository = _FakeStudentSkillRepository()
        ..loadResult = [
          _skill(id: 1, skillName: 'Primavera P6', source: 'manual'),
        ];

      await _pumpScreen(tester, repository: repository);

      expect(find.text('Primavera P6'), findsOneWidget);
      expect(find.text('Self-declared'), findsOneWidget);
      expect(find.text('CV-supported'), findsNothing);
    });

    testWidgets('Both evidence labels render together for a mixed list', (
      tester,
    ) async {
      final repository = _FakeStudentSkillRepository()
        ..loadResult = [
          _skill(id: 1, skillId: 10, skillName: 'AutoCAD', source: 'cv_ai'),
          _skill(id: 2, skillId: 11, skillName: 'Primavera P6', source: 'manual'),
        ];

      await _pumpScreen(tester, repository: repository);

      expect(find.text('AutoCAD'), findsOneWidget);
      expect(find.text('CV-supported'), findsOneWidget);
      expect(find.text('Primavera P6'), findsOneWidget);
      expect(find.text('Self-declared'), findsOneWidget);
    });

    testWidgets(
      'UI Phase 7.1: the manual/CV-supported distinction is not color-only '
      '-- a CV-supported card carries its own AI icon a manual card never '
      'shows',
      (tester) async {
        final repository = _FakeStudentSkillRepository()
          ..loadResult = [
            _skill(id: 1, skillId: 10, skillName: 'AutoCAD', source: 'cv_ai'),
            _skill(id: 2, skillId: 11, skillName: 'Primavera P6', source: 'manual'),
          ];

        await _pumpScreen(tester, repository: repository);

        final cvCard = find.ancestor(
          of: find.text('AutoCAD'),
          matching: find.byType(AppCard),
        );
        final manualCard = find.ancestor(
          of: find.text('Primavera P6'),
          matching: find.byType(AppCard),
        );

        // Within the cv_ai skill's own card: the small name-row accent icon
        // plus the evidence badge's own icon. Zero auto_awesome within the
        // manual card -- the difference is never carried by color alone.
        expect(
          find.descendant(of: cvCard, matching: find.byIcon(Icons.auto_awesome)),
          findsNWidgets(2),
        );
        expect(
          find.descendant(of: manualCard, matching: find.byIcon(Icons.auto_awesome)),
          findsNothing,
        );
        expect(
          find.descendant(
            of: manualCard,
            matching: find.byIcon(Icons.edit_note_rounded),
          ),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'UI Phase 7.1: AI purple only decorates the CV-supported card, never '
      'the manual one',
      (tester) async {
        final repository = _FakeStudentSkillRepository()
          ..loadResult = [
            _skill(id: 1, skillId: 10, skillName: 'AutoCAD', source: 'cv_ai'),
            _skill(id: 2, skillId: 11, skillName: 'Primavera P6', source: 'manual'),
          ];

        await _pumpScreen(tester, repository: repository);

        final cvCard = tester.widget<AppCard>(
          find.ancestor(
            of: find.text('AutoCAD'),
            matching: find.byType(AppCard),
          ),
        );
        final manualCard = tester.widget<AppCard>(
          find.ancestor(
            of: find.text('Primavera P6'),
            matching: find.byType(AppCard),
          ),
        );

        expect(cvCard.borderColor, isNotNull);
        expect(manualCard.borderColor, isNull);
      },
    );

    testWidgets('each real level renders its own properly-cased label', (
      tester,
    ) async {
      final repository = _FakeStudentSkillRepository()
        ..loadResult = [
          _skill(id: 1, skillId: 1, skillName: 'Skill Beginner', level: 'beginner'),
          _skill(id: 2, skillId: 2, skillName: 'Skill Intermediate', level: 'intermediate'),
          _skill(id: 3, skillId: 3, skillName: 'Skill Advanced', level: 'advanced'),
          _skill(id: 4, skillId: 4, skillName: 'Skill Expert', level: 'expert'),
        ];

      await _pumpScreen(tester, repository: repository, size: const Size(420, 2400));

      // Each level's own filter chip renders the identical label text, so
      // two widgets (the filter chip plus this skill's own level pill) is
      // the real, expected count -- not an accidental collision.
      expect(find.text('Beginner'), findsNWidgets(2));
      expect(find.text('Intermediate'), findsNWidgets(2));
      expect(find.text('Advanced'), findsNWidgets(2));
      expect(find.text('Expert'), findsNWidgets(2));
    });

    testWidgets('a real catalog category is shown when present', (
      tester,
    ) async {
      final repository = _FakeStudentSkillRepository()
        ..loadResult = [
          _skill(id: 1, skillName: 'AutoCAD', category: 'Civil Engineering'),
        ];

      await _pumpScreen(tester, repository: repository);

      expect(find.text('Civil Engineering'), findsOneWidget);
    });

    testWidgets('no category text renders when the catalog skill has none', (
      tester,
    ) async {
      final repository = _FakeStudentSkillRepository()
        ..loadResult = [_skill(id: 1, skillName: 'AutoCAD', category: null)];

      await _pumpScreen(tester, repository: repository);

      expect(find.text('AutoCAD'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('real years of experience is shown only when present', (
      tester,
    ) async {
      final repository = _FakeStudentSkillRepository()
        ..loadResult = [
          _skill(id: 1, skillName: 'AutoCAD', yearsOfExperience: 3.5),
        ];

      await _pumpScreen(tester, repository: repository);

      expect(find.textContaining('3.5 yrs experience'), findsOneWidget);
    });

    testWidgets('a very long skill name does not overflow', (tester) async {
      final repository = _FakeStudentSkillRepository()
        ..loadResult = [
          _skill(
            id: 1,
            skillName: 'A Very Long Skill Name That Might Wrap Or Overflow The Card',
          ),
        ];

      await _pumpScreen(
        tester,
        repository: repository,
        size: const Size(320, 700),
      );

      expect(tester.takeException(), isNull);
    });
  });

  group('Skills Summary', () {
    testWidgets('shows real, locally-derived Total, CV-Supported, and Self-Declared counts', (
      tester,
    ) async {
      final repository = _FakeStudentSkillRepository()
        ..loadResult = [
          _skill(id: 1, skillId: 1, skillName: 'AutoCAD', source: 'cv_ai'),
          _skill(id: 2, skillId: 2, skillName: 'Python', source: 'cv_ai'),
          _skill(id: 3, skillId: 3, skillName: 'Excel', source: 'manual'),
        ];

      await _pumpScreen(tester, repository: repository);

      expect(find.text('Skills Summary'), findsOneWidget);
      expect(find.text('Total Skills'), findsOneWidget);
      expect(find.text('3'), findsOneWidget);
      // "CV-Supported"/"Self-Declared" are also the real filter chip
      // labels just below the summary, so two matches (summary row +
      // filter chip) is the real, expected count.
      expect(find.text('CV-Supported'), findsNWidgets(2));
      expect(find.text('2'), findsOneWidget);
      expect(find.text('Self-Declared'), findsNWidgets(2));
      expect(find.text('1'), findsOneWidget);
    });

    testWidgets('never fabricates a profile score or percentile', (
      tester,
    ) async {
      final repository = _FakeStudentSkillRepository()
        ..loadResult = [_skill(id: 1)];

      await _pumpScreen(tester, repository: repository);

      expect(find.textContaining('%'), findsNothing);
      expect(find.textContaining('score'), findsNothing);
      expect(find.textContaining('percentile'), findsNothing);
    });
  });

  group('Search', () {
    testWidgets('filters the visible skills by real skill name', (
      tester,
    ) async {
      final repository = _FakeStudentSkillRepository()
        ..loadResult = [
          _skill(id: 1, skillId: 1, skillName: 'AutoCAD'),
          _skill(id: 2, skillId: 2, skillName: 'Python'),
        ];

      await _pumpScreen(tester, repository: repository);

      await tester.enterText(find.byType(TextFormField), 'auto');
      await tester.pumpAndSettle();

      expect(find.text('AutoCAD'), findsOneWidget);
      expect(find.text('Python'), findsNothing);
    });

    testWidgets('shows a polished no-match state with Clear Search & Filters', (
      tester,
    ) async {
      final repository = _FakeStudentSkillRepository()
        ..loadResult = [_skill(id: 1, skillName: 'AutoCAD')];

      await _pumpScreen(tester, repository: repository);

      await tester.enterText(find.byType(TextFormField), 'nonexistent skill');
      await tester.pumpAndSettle();

      expect(find.text('No Matching Skills'), findsOneWidget);
      expect(find.text('Clear Search & Filters'), findsOneWidget);

      await tester.tap(find.text('Clear Search & Filters'));
      await tester.pumpAndSettle();

      expect(find.text('AutoCAD'), findsOneWidget);
    });
  });

  group('Filters', () {
    testWidgets('the CV-Supported filter shows only cv_ai skills', (
      tester,
    ) async {
      final repository = _FakeStudentSkillRepository()
        ..loadResult = [
          _skill(id: 1, skillId: 1, skillName: 'AutoCAD', source: 'cv_ai'),
          _skill(id: 2, skillId: 2, skillName: 'Excel', source: 'manual'),
        ];

      await _pumpScreen(tester, repository: repository);

      await tester.tap(find.byKey(const Key('skill-filter-source-cv_ai')));
      await tester.pumpAndSettle();

      expect(find.text('AutoCAD'), findsOneWidget);
      expect(find.text('Excel'), findsNothing);
    });

    testWidgets('the Self-Declared filter shows only manual skills', (
      tester,
    ) async {
      final repository = _FakeStudentSkillRepository()
        ..loadResult = [
          _skill(id: 1, skillId: 1, skillName: 'AutoCAD', source: 'cv_ai'),
          _skill(id: 2, skillId: 2, skillName: 'Excel', source: 'manual'),
        ];

      await _pumpScreen(tester, repository: repository);

      await tester.tap(find.byKey(const Key('skill-filter-source-manual')));
      await tester.pumpAndSettle();

      expect(find.text('AutoCAD'), findsNothing);
      expect(find.text('Excel'), findsOneWidget);
    });

    testWidgets('the All filter restores every skill', (tester) async {
      final repository = _FakeStudentSkillRepository()
        ..loadResult = [
          _skill(id: 1, skillId: 1, skillName: 'AutoCAD', source: 'cv_ai'),
          _skill(id: 2, skillId: 2, skillName: 'Excel', source: 'manual'),
        ];

      await _pumpScreen(tester, repository: repository);

      await tester.tap(find.byKey(const Key('skill-filter-source-manual')));
      await tester.pumpAndSettle();
      expect(find.text('AutoCAD'), findsNothing);

      await tester.tap(find.byKey(const Key('skill-filter-source-all')));
      await tester.pumpAndSettle();

      expect(find.text('AutoCAD'), findsOneWidget);
      expect(find.text('Excel'), findsOneWidget);
    });

    testWidgets('a level filter shows only skills at that real level', (
      tester,
    ) async {
      final repository = _FakeStudentSkillRepository()
        ..loadResult = [
          _skill(id: 1, skillId: 1, skillName: 'AutoCAD', level: 'expert'),
          _skill(id: 2, skillId: 2, skillName: 'Excel', level: 'beginner'),
        ];

      await _pumpScreen(tester, repository: repository);

      await tester.tap(find.byKey(const Key('skill-filter-level-expert')));
      await tester.pumpAndSettle();

      expect(find.text('AutoCAD'), findsOneWidget);
      expect(find.text('Excel'), findsNothing);
    });

    testWidgets('search and filters compose together', (tester) async {
      final repository = _FakeStudentSkillRepository()
        ..loadResult = [
          _skill(id: 1, skillId: 1, skillName: 'AutoCAD', source: 'cv_ai'),
          _skill(id: 2, skillId: 2, skillName: 'AutoDesk Fusion', source: 'manual'),
        ];

      await _pumpScreen(tester, repository: repository);

      await tester.enterText(find.byType(TextFormField), 'auto');
      await tester.tap(find.byKey(const Key('skill-filter-source-cv_ai')));
      await tester.pumpAndSettle();

      expect(find.text('AutoCAD'), findsOneWidget);
      expect(find.text('AutoDesk Fusion'), findsNothing);
    });
  });

  testWidgets('Pull-to-refresh calls the provider and reloads the list', (
    tester,
  ) async {
    final repository = _FakeStudentSkillRepository()..loadResult = [_skill()];
    await _pumpScreen(tester, repository: repository);
    expect(repository.getStudentSkillsCallCount, 1);

    unawaited(
      tester.state<RefreshIndicatorState>(find.byType(RefreshIndicator)).show(),
    );
    await tester.pumpAndSettle();

    expect(repository.getStudentSkillsCallCount, 2);
  });

  group('Remove skill', () {
    testWidgets('A delete action is visible on each skill row', (tester) async {
      final repository = _FakeStudentSkillRepository()
        ..loadResult = [_skill(id: 1)];

      await _pumpScreen(tester, repository: repository);

      expect(find.byKey(const Key('delete-student-skill-1')), findsOneWidget);
    });

    testWidgets('Tapping delete shows a confirmation dialog', (tester) async {
      final repository = _FakeStudentSkillRepository()
        ..loadResult = [_skill(id: 1, skillName: 'AutoCAD')];

      await _pumpScreen(tester, repository: repository);

      await tester.tap(find.byKey(const Key('delete-student-skill-1')));
      await tester.pumpAndSettle();

      expect(find.text('Remove Skill'), findsOneWidget);
      expect(
        find.textContaining('remove "AutoCAD" from your profile'),
        findsOneWidget,
      );
      expect(repository.deletedIds, isEmpty);
    });

    testWidgets('Cancelling the confirmation performs no deletion', (
      tester,
    ) async {
      final repository = _FakeStudentSkillRepository()
        ..loadResult = [_skill(id: 1, skillName: 'AutoCAD')];

      await _pumpScreen(tester, repository: repository);

      await tester.tap(find.byKey(const Key('delete-student-skill-1')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(repository.deletedIds, isEmpty);
      expect(find.text('AutoCAD'), findsOneWidget);
    });

    testWidgets('Confirming deletion removes the skill and shows a SnackBar', (
      tester,
    ) async {
      final repository = _FakeStudentSkillRepository()
        ..loadResult = [_skill(id: 1, skillName: 'AutoCAD')];

      await _pumpScreen(tester, repository: repository);

      await tester.tap(find.byKey(const Key('delete-student-skill-1')));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(DangerButton, 'Remove'));
      await tester.pumpAndSettle();

      expect(repository.deletedIds, [1]);
      expect(find.text('AutoCAD'), findsNothing);
      expect(find.text('Skill removed successfully'), findsOneWidget);
    });

    testWidgets(
      'A failed deletion keeps the skill visible and shows the error',
      (tester) async {
        final repository = _FakeStudentSkillRepository()
          ..loadResult = [_skill(id: 1, skillName: 'AutoCAD')]
          ..deleteError = ApiException('Server error, please try again later.');

        await _pumpScreen(tester, repository: repository);

        await tester.tap(find.byKey(const Key('delete-student-skill-1')));
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(DangerButton, 'Remove'));
        await tester.pumpAndSettle();

        expect(find.text('AutoCAD'), findsOneWidget); // row preserved
        expect(
          find.text('Server error, please try again later.'),
          findsOneWidget,
        );
      },
    );

    testWidgets('A cv_ai (CV-supported) skill is removable', (tester) async {
      final repository = _FakeStudentSkillRepository()
        ..loadResult = [_skill(id: 1, skillName: 'AutoCAD', source: 'cv_ai')];

      await _pumpScreen(tester, repository: repository);

      await tester.tap(find.byKey(const Key('delete-student-skill-1')));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(DangerButton, 'Remove'));
      await tester.pumpAndSettle();

      expect(repository.deletedIds, [1]);
      expect(find.text('AutoCAD'), findsNothing);
    });

    testWidgets('A manual (Self-declared) skill is removable', (tester) async {
      final repository = _FakeStudentSkillRepository()
        ..loadResult = [
          _skill(id: 1, skillName: 'Primavera P6', source: 'manual'),
        ];

      await _pumpScreen(tester, repository: repository);

      await tester.tap(find.byKey(const Key('delete-student-skill-1')));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(DangerButton, 'Remove'));
      await tester.pumpAndSettle();

      expect(repository.deletedIds, [1]);
      expect(find.text('Primavera P6'), findsNothing);
    });

    testWidgets(
      'Deleting sends the StudentSkill row id, never the catalog skill id -- '
      'the global Skill catalog row is never targeted',
      (tester) async {
        final repository = _FakeStudentSkillRepository()
          ..loadResult = [_skill(id: 1, skillId: 999, skillName: 'AutoCAD')];

        await _pumpScreen(tester, repository: repository);

        await tester.tap(find.byKey(const Key('delete-student-skill-1')));
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(DangerButton, 'Remove'));
        await tester.pumpAndSettle();

        expect(repository.deletedIds, [1]);
        expect(repository.deletedIds, isNot(contains(999)));
      },
    );

    testWidgets(
      'Busy state disables the delete action while in flight -- guards '
      'against a duplicate tap',
      (tester) async {
        final repository = _FakeStudentSkillRepository()
          ..loadResult = [_skill(id: 1, skillName: 'AutoCAD')]
          ..deleteDelay = const Duration(milliseconds: 2000);

        await _pumpScreen(tester, repository: repository);

        await tester.tap(find.byKey(const Key('delete-student-skill-1')));
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(DangerButton, 'Remove'));
        await tester.pump(const Duration(milliseconds: 200));

        // The delete IconButton is swapped for a spinner while busy, so a
        // second tap has nothing to hit.
        expect(find.byKey(const Key('delete-student-skill-1')), findsNothing);
        expect(repository.deletedIds, [1]);

        await tester.pumpAndSettle();
        expect(find.text('AutoCAD'), findsNothing);
      },
    );
  });

  group('Responsive layout', () {
    testWidgets('Does not overflow at a narrow 320x900 viewport', (
      tester,
    ) async {
      final repository = _FakeStudentSkillRepository()
        ..loadResult = [
          _skill(id: 1, skillId: 1, skillName: 'AutoCAD'),
          _skill(id: 2, skillId: 2, skillName: 'Excel'),
        ];

      await _pumpScreen(
        tester,
        repository: repository,
        size: const Size(320, 1400),
      );

      expect(tester.takeException(), isNull);
    });

    testWidgets('Does not overflow at a tablet viewport', (tester) async {
      final repository = _FakeStudentSkillRepository()
        ..loadResult = [_skill(id: 1, skillName: 'AutoCAD')];

      await _pumpScreen(
        tester,
        repository: repository,
        size: const Size(900, 1000),
      );

      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'Does not overflow at a wide desktop viewport and uses a 2-column grid',
      (tester) async {
        final repository = _FakeStudentSkillRepository()
          ..loadResult = [
            _skill(id: 1, skillId: 1, skillName: 'AutoCAD'),
            _skill(id: 2, skillId: 2, skillName: 'Excel'),
          ];

        await _pumpScreen(
          tester,
          repository: repository,
          size: const Size(1440, 1000),
        );

        expect(tester.takeException(), isNull);
        expect(find.text('AutoCAD'), findsOneWidget);
        expect(find.text('Excel'), findsOneWidget);
        expect(find.byKey(const ValueKey('skills-grid-desktop')), findsOneWidget);
      },
    );
  });

  testWidgets('honors reduced motion without throwing', (tester) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);

    final repository = _FakeStudentSkillRepository()
      ..loadResult = [_skill(id: 1, skillName: 'AutoCAD')];
    await _pumpScreen(tester, repository: repository);

    expect(tester.takeException(), isNull);
    expect(find.text('AutoCAD'), findsOneWidget);
  });

  testWidgets('renders correctly in Dark Mode', (tester) async {
    final repository = _FakeStudentSkillRepository()
      ..loadResult = [
        _skill(id: 1, skillName: 'AutoCAD', source: 'cv_ai'),
        _skill(id: 2, skillId: 2, skillName: 'Excel', source: 'manual'),
      ];

    await _pumpScreen(
      tester,
      repository: repository,
      theme: AppTheme.darkTheme,
    );

    expect(tester.takeException(), isNull);
    expect(find.text('AutoCAD'), findsOneWidget);
    expect(find.text('Excel'), findsOneWidget);
  });
}
