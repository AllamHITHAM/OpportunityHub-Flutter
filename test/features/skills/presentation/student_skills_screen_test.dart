// Widget tests for StudentSkillsScreen, in isolation with a small GoRouter.
// Mirrors admin_skills_screen_test.dart's structure and conventions.

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
  String level = 'advanced',
  String source = 'manual',
}) {
  return StudentSkillModel(
    id: id,
    skillId: skillId,
    skillName: skillName,
    level: level,
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
    initialLocation: '/student/cvs/skills',
    routes: [
      GoRoute(
        path: '/student/cvs/skills',
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
      ],
      child: MaterialApp.router(
        theme: AppTheme.lightTheme,
        routerConfig: router,
      ),
    ),
  );
  await tester.pumpAndSettle();

  return skillProvider;
}

void main() {
  testWidgets('Loading state renders while skills are in flight', (
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
      initialLocation: '/student/cvs/skills',
      routes: [
        GoRoute(
          path: '/student/cvs/skills',
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

  testWidgets('Empty state shows AppEmptyView', (tester) async {
    final repository = _FakeStudentSkillRepository()..loadResult = [];

    await _pumpScreen(tester, repository: repository);

    expect(find.text('No Skills Yet'), findsOneWidget);
  });

  testWidgets('A CV-supported skill shows the CV-supported label', (
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

  testWidgets('No overflow at a narrow 320-wide viewport', (tester) async {
    final repository = _FakeStudentSkillRepository()
      ..loadResult = [
        _skill(skillName: 'A Very Long Skill Name That Might Wrap Or Overflow'),
      ];

    await _pumpScreen(
      tester,
      repository: repository,
      size: const Size(320, 700),
    );

    expect(tester.takeException(), isNull);
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
}
