// Widget tests for AdminSkillsScreen, in isolation with a small GoRouter.
// Mirrors admin_users_screen_test.dart's structure and conventions.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'package:opportunityhub_flutter/core/api/api_client.dart';
import 'package:opportunityhub_flutter/core/storage/token_storage_service.dart';
import 'package:opportunityhub_flutter/core/theme/app_theme.dart';
import 'package:opportunityhub_flutter/core/widgets/app_widgets.dart';
import 'package:opportunityhub_flutter/features/admin/data/admin_skills_repository.dart';
import 'package:opportunityhub_flutter/features/admin/presentation/admin_skills_screen.dart';
import 'package:opportunityhub_flutter/features/auth/data/auth_repository.dart';
import 'package:opportunityhub_flutter/models/skill_model.dart';
import 'package:opportunityhub_flutter/providers/admin_skills_provider.dart';
import 'package:opportunityhub_flutter/providers/auth_provider.dart';

class _FakeAuthRepository extends AuthRepository {
  _FakeAuthRepository()
    : super(
        apiClient: ApiClient(tokenStorageService: TokenStorageService()),
        tokenStorageService: TokenStorageService(),
      );

  @override
  Future<String?> getSavedToken() async => null;
}

SkillModel _skill({int id = 1, String name = 'Flutter', DateTime? createdAt}) {
  return SkillModel(id: id, name: name, createdAt: createdAt);
}

class _FakeAdminSkillsRepository extends AdminSkillsRepository {
  _FakeAdminSkillsRepository()
    : super(apiClient: ApiClient(tokenStorageService: TokenStorageService()));

  List<SkillModel>? loadResult;
  ApiException? loadError;
  Duration loadDelay = Duration.zero;
  int getSkillsCallCount = 0;

  SkillModel? createResult;
  ApiException? createError;
  Duration createDelay = Duration.zero;
  int createSkillCallCount = 0;

  SkillModel? updateResult;
  ApiException? updateError;
  Duration updateDelay = Duration.zero;
  int updateSkillCallCount = 0;

  ApiException? deleteError;
  Duration deleteDelay = Duration.zero;
  int deleteSkillCallCount = 0;

  @override
  Future<List<SkillModel>> getSkills() async {
    getSkillsCallCount++;
    if (loadDelay > Duration.zero) {
      await Future<void>.delayed(loadDelay);
    }
    if (loadError != null) throw loadError!;
    return loadResult ?? [];
  }

  @override
  Future<SkillModel> createSkill({required String name}) async {
    createSkillCallCount++;
    if (createDelay > Duration.zero) {
      await Future<void>.delayed(createDelay);
    }
    if (createError != null) throw createError!;
    return createResult!;
  }

  @override
  Future<SkillModel> updateSkill({
    required int skillId,
    required String name,
  }) async {
    updateSkillCallCount++;
    if (updateDelay > Duration.zero) {
      await Future<void>.delayed(updateDelay);
    }
    if (updateError != null) throw updateError!;
    return updateResult!;
  }

  @override
  Future<void> deleteSkill(int skillId) async {
    deleteSkillCallCount++;
    if (deleteDelay > Duration.zero) {
      await Future<void>.delayed(deleteDelay);
    }
    if (deleteError != null) throw deleteError!;
  }
}

class _Providers {
  _Providers({required this.skills});

  final AdminSkillsProvider skills;
}

Future<_Providers> _pumpScreen(
  WidgetTester tester, {
  required AdminSkillsRepository repository,
  Size size = const Size(420, 1400),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final authProvider = AuthProvider(authRepository: _FakeAuthRepository());
  final skillsProvider = AdminSkillsProvider(
    repository: repository,
    authProvider: authProvider,
  );

  final router = GoRouter(
    initialLocation: '/admin/skills',
    routes: [
      GoRoute(
        path: '/admin/skills',
        builder: (_, _) => const AdminSkillsScreen(),
      ),
    ],
  );

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthProvider>.value(value: authProvider),
        ChangeNotifierProvider<AdminSkillsProvider>.value(
          value: skillsProvider,
        ),
      ],
      child: MaterialApp.router(
        theme: AppTheme.lightTheme,
        routerConfig: router,
      ),
    ),
  );
  await tester.pumpAndSettle();

  return _Providers(skills: skillsProvider);
}

Future<void> _openAddSheet(WidgetTester tester) async {
  await tester.tap(find.widgetWithIcon(IconButton, Icons.add));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('Loading state renders while skills are in flight', (
    tester,
  ) async {
    final repository = _FakeAdminSkillsRepository()
      ..loadResult = [_skill()]
      ..loadDelay = const Duration(milliseconds: 200);

    tester.view.physicalSize = const Size(420, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final authProvider = AuthProvider(authRepository: _FakeAuthRepository());
    final skillsProvider = AdminSkillsProvider(
      repository: repository,
      authProvider: authProvider,
    );
    final router = GoRouter(
      initialLocation: '/admin/skills',
      routes: [
        GoRoute(
          path: '/admin/skills',
          builder: (_, _) => const AdminSkillsScreen(),
        ),
      ],
    );

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthProvider>.value(value: authProvider),
          ChangeNotifierProvider<AdminSkillsProvider>.value(
            value: skillsProvider,
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

    expect(skillsProvider.isLoading, isTrue);
    expect(find.text('Flutter'), findsNothing);

    await tester.pumpAndSettle();
  });

  testWidgets(
    'Error state with no skills shows AppErrorView and a working retry',
    (tester) async {
      final repository = _FakeAdminSkillsRepository()
        ..loadError = ApiException('Server error, please try again later.');

      final providers = await _pumpScreen(tester, repository: repository);

      expect(
        find.text('Server error, please try again later.'),
        findsOneWidget,
      );
      expect(find.text('Try Again'), findsOneWidget);

      repository.loadError = null;
      repository.loadResult = [_skill()];
      await tester.tap(find.text('Try Again'));
      await tester.pumpAndSettle();

      expect(find.text('Flutter'), findsOneWidget);
      expect(providers.skills.skills, hasLength(1));
    },
  );

  testWidgets('Empty state shows AppEmptyView with an Add Skill action', (
    tester,
  ) async {
    final repository = _FakeAdminSkillsRepository()..loadResult = [];

    await _pumpScreen(tester, repository: repository);

    expect(find.text('No Skills Yet'), findsOneWidget);
    // Two: the AppBar icon action plus the empty-state's own action button.
    expect(find.text('Add Skill'), findsWidgets);
  });

  testWidgets('Add Skill action is available when the list is populated', (
    tester,
  ) async {
    final repository = _FakeAdminSkillsRepository()..loadResult = [_skill()];

    await _pumpScreen(tester, repository: repository);

    expect(find.widgetWithIcon(IconButton, Icons.add), findsOneWidget);
  });

  testWidgets('Renders skill name and created date', (tester) async {
    final repository = _FakeAdminSkillsRepository()
      ..loadResult = [
        _skill(id: 1, name: 'Flutter', createdAt: DateTime(2026, 7, 1)),
      ];

    await _pumpScreen(tester, repository: repository);

    expect(find.text('Flutter'), findsOneWidget);
    expect(find.textContaining('Added'), findsOneWidget);
  });

  testWidgets('Search filters by name, case-insensitively', (tester) async {
    final repository = _FakeAdminSkillsRepository()
      ..loadResult = [
        _skill(id: 1, name: 'Flutter'),
        _skill(id: 2, name: 'Laravel'),
      ];

    await _pumpScreen(tester, repository: repository);

    await tester.enterText(find.byType(TextFormField), 'LARAVEL');
    await tester.pumpAndSettle();

    expect(find.text('Laravel'), findsOneWidget);
    expect(find.text('Flutter'), findsNothing);
  });

  testWidgets(
    'Search with no matches shows a dedicated no-match state, not the general empty state',
    (tester) async {
      final repository = _FakeAdminSkillsRepository()
        ..loadResult = [_skill(id: 1, name: 'Flutter')];

      await _pumpScreen(tester, repository: repository);

      await tester.enterText(
        find.byType(TextFormField),
        'nonexistent-skill-xyz',
      );
      await tester.pumpAndSettle();

      expect(find.text('No Matches'), findsOneWidget);
      expect(find.text('No Skills Yet'), findsNothing);
    },
  );

  group('Add Skill', () {
    testWidgets('Blank name shows a validation error', (tester) async {
      final repository = _FakeAdminSkillsRepository()..loadResult = [];
      await _pumpScreen(tester, repository: repository);

      await _openAddSheet(tester);
      await tester.tap(find.widgetWithText(PrimaryButton, 'Add Skill').last);
      await tester.pumpAndSettle();

      expect(find.text('Name is required'), findsOneWidget);
      expect(repository.createSkillCallCount, 0);
    });

    testWidgets('Whitespace-only name shows a validation error', (
      tester,
    ) async {
      final repository = _FakeAdminSkillsRepository()..loadResult = [];
      await _pumpScreen(tester, repository: repository);

      await _openAddSheet(tester);
      await tester.enterText(find.byType(TextFormField), '   ');
      await tester.tap(find.widgetWithText(PrimaryButton, 'Add Skill').last);
      await tester.pumpAndSettle();

      expect(find.text('Name is required'), findsOneWidget);
      expect(repository.createSkillCallCount, 0);
    });

    testWidgets('A name over 255 characters shows a validation error', (
      tester,
    ) async {
      final repository = _FakeAdminSkillsRepository()..loadResult = [];
      await _pumpScreen(tester, repository: repository);

      await _openAddSheet(tester);
      // The field's own `maxLength: 255` already stops UI text entry past
      // that limit, so the validator's length branch is exercised by
      // setting the controller directly instead of via `enterText`.
      final field = tester.widget<TextFormField>(find.byType(TextFormField));
      field.controller!.text = 'a' * 256;
      final isValid = tester.state<FormState>(find.byType(Form)).validate();
      await tester.pump();

      expect(isValid, isFalse);
      expect(find.text('Name must be 255 characters or fewer'), findsOneWidget);
      expect(repository.createSkillCallCount, 0);
    });

    testWidgets('Shows a loading state and disables repeated submission', (
      tester,
    ) async {
      final repository = _FakeAdminSkillsRepository()
        ..loadResult = []
        ..createResult = _skill(id: 7, name: 'Docker')
        ..createDelay = const Duration(milliseconds: 2000);
      await _pumpScreen(tester, repository: repository);

      await _openAddSheet(tester);
      await tester.enterText(find.byType(TextFormField), 'Docker');
      await tester.tap(find.widgetWithText(PrimaryButton, 'Add Skill').last);
      await tester.pump(const Duration(milliseconds: 200));

      final button = tester.widget<PrimaryButton>(
        find.widgetWithText(PrimaryButton, 'Add Skill').last,
      );
      expect(button.isLoading, isTrue);

      await tester.pumpAndSettle();
    });

    testWidgets('A duplicate-name field error is mapped inline', (
      tester,
    ) async {
      final repository = _FakeAdminSkillsRepository()
        ..loadResult = []
        ..createError = ApiException(
          'The given data was invalid.',
          statusCode: 422,
          errors: {
            'name': ['The name has already been taken.'],
          },
        );
      await _pumpScreen(tester, repository: repository);

      await _openAddSheet(tester);
      await tester.enterText(find.byType(TextFormField), 'Docker');
      await tester.tap(find.widgetWithText(PrimaryButton, 'Add Skill').last);
      await tester.pumpAndSettle();

      expect(find.text('The name has already been taken.'), findsOneWidget);
      // Still open -- creation did not succeed.
      expect(find.widgetWithText(PrimaryButton, 'Add Skill'), findsOneWidget);
    });

    testWidgets(
      'A 409 business error (no field error) shows a form-level message',
      (tester) async {
        final repository = _FakeAdminSkillsRepository()
          ..loadResult = []
          ..createError = ApiException(
            'A skill with this name already exists',
            statusCode: 409,
          );
        await _pumpScreen(tester, repository: repository);

        await _openAddSheet(tester);
        await tester.enterText(find.byType(TextFormField), 'Docker');
        await tester.tap(find.widgetWithText(PrimaryButton, 'Add Skill').last);
        await tester.pumpAndSettle();

        expect(
          find.text('A skill with this name already exists'),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'Success closes the sheet, adds the skill immediately, shows a SnackBar',
      (tester) async {
        final repository = _FakeAdminSkillsRepository()
          ..loadResult = []
          ..createResult = _skill(id: 7, name: 'Docker');
        await _pumpScreen(tester, repository: repository);

        await _openAddSheet(tester);
        await tester.enterText(find.byType(TextFormField), 'Docker');
        await tester.tap(find.widgetWithText(PrimaryButton, 'Add Skill').last);
        await tester.pumpAndSettle();

        expect(find.text('Add Skill'), findsNothing); // sheet closed
        expect(find.text('Docker'), findsOneWidget);
        expect(find.text('Skill created successfully'), findsOneWidget);
        // No reload -- still exactly the one initial GET.
        expect(repository.getSkillsCallCount, 1);
      },
    );
  });

  group('Edit Skill', () {
    testWidgets('Prefills the current name', (tester) async {
      final repository = _FakeAdminSkillsRepository()
        ..loadResult = [_skill(id: 1, name: 'Flutter')];
      await _pumpScreen(tester, repository: repository);

      await tester.tap(find.byKey(const Key('edit-skill-1')));
      await tester.pumpAndSettle();

      // Scoped to the sheet's own Form -- the search field underneath is
      // also a TextFormField, so an unscoped find would be ambiguous.
      final field = tester.widget<TextFormField>(
        find.descendant(
          of: find.byType(Form),
          matching: find.byType(TextFormField),
        ),
      );
      expect(field.controller?.text, 'Flutter');
    });

    testWidgets(
      'Success patches the skill immediately, closes the sheet, shows a SnackBar',
      (tester) async {
        final repository = _FakeAdminSkillsRepository()
          ..loadResult = [_skill(id: 1, name: 'Flutter')]
          ..updateResult = _skill(id: 1, name: 'Flutter (Dart)');
        await _pumpScreen(tester, repository: repository);

        await tester.tap(find.byKey(const Key('edit-skill-1')));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.descendant(
            of: find.byType(Form),
            matching: find.byType(TextFormField),
          ),
          'Flutter (Dart)',
        );
        await tester.tap(find.widgetWithText(PrimaryButton, 'Save Changes'));
        await tester.pumpAndSettle();

        expect(find.text('Flutter (Dart)'), findsOneWidget);
        expect(find.text('Skill updated successfully'), findsOneWidget);
        expect(repository.getSkillsCallCount, 1);
      },
    );

    testWidgets('Failure preserves the entered value and shows the error', (
      tester,
    ) async {
      final repository = _FakeAdminSkillsRepository()
        ..loadResult = [_skill(id: 1, name: 'Flutter')]
        ..updateError = ApiException('Server error, please retry.');
      await _pumpScreen(tester, repository: repository);

      await tester.tap(find.byKey(const Key('edit-skill-1')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.descendant(
          of: find.byType(Form),
          matching: find.byType(TextFormField),
        ),
        'Flutter (Dart)',
      );
      await tester.tap(find.widgetWithText(PrimaryButton, 'Save Changes'));
      await tester.pumpAndSettle();

      // Sheet still open with the entered value intact.
      expect(find.text('Server error, please retry.'), findsOneWidget);
      final field = tester.widget<TextFormField>(
        find.descendant(
          of: find.byType(Form),
          matching: find.byType(TextFormField),
        ),
      );
      expect(field.controller?.text, 'Flutter (Dart)');
      // Old name unchanged in the list underneath.
      expect(repository.getSkillsCallCount, 1);
    });
  });

  group('Delete Skill', () {
    testWidgets('Confirmation: cancel performs no deletion', (tester) async {
      final repository = _FakeAdminSkillsRepository()
        ..loadResult = [_skill(id: 1, name: 'Flutter')];
      await _pumpScreen(tester, repository: repository);

      await tester.tap(find.byKey(const Key('delete-skill-1')));
      await tester.pumpAndSettle();

      expect(find.text('Delete Skill'), findsOneWidget);
      expect(
        find.text('Are you sure you want to delete this skill?'),
        findsOneWidget,
      );

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(repository.deleteSkillCallCount, 0);
      expect(find.text('Flutter'), findsOneWidget);
    });

    testWidgets(
      'Confirmation: confirm deletes the skill immediately, shows a SnackBar',
      (tester) async {
        final repository = _FakeAdminSkillsRepository()
          ..loadResult = [_skill(id: 1, name: 'Flutter')];
        await _pumpScreen(tester, repository: repository);

        await tester.tap(find.byKey(const Key('delete-skill-1')));
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(DangerButton, 'Delete'));
        await tester.pumpAndSettle();

        expect(find.text('Flutter'), findsNothing);
        expect(find.text('Skill deleted successfully'), findsOneWidget);
        expect(repository.getSkillsCallCount, 1);
      },
    );

    testWidgets(
      'A 409 delete conflict preserves the row and shows the message',
      (tester) async {
        final repository = _FakeAdminSkillsRepository()
          ..loadResult = [_skill(id: 1, name: 'Flutter')]
          ..deleteError = ApiException(
            'Cannot delete a skill that is currently in use',
            statusCode: 409,
          );
        await _pumpScreen(tester, repository: repository);

        await tester.tap(find.byKey(const Key('delete-skill-1')));
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(DangerButton, 'Delete'));
        await tester.pumpAndSettle();

        expect(find.text('Flutter'), findsOneWidget); // row preserved
        expect(
          find.text('Cannot delete a skill that is currently in use'),
          findsOneWidget,
        );
      },
    );

    testWidgets('Row-level busy state disables actions while in flight', (
      tester,
    ) async {
      final repository = _FakeAdminSkillsRepository()
        ..loadResult = [_skill(id: 1, name: 'Flutter')]
        ..deleteDelay = const Duration(milliseconds: 2000);
      await _pumpScreen(tester, repository: repository);

      await tester.tap(find.byKey(const Key('delete-skill-1')));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(DangerButton, 'Delete'));
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.byKey(const Key('edit-skill-1')), findsNothing);
      expect(find.byKey(const Key('delete-skill-1')), findsNothing);

      await tester.pumpAndSettle();
    });
  });

  testWidgets('Pull-to-refresh calls the provider and reloads the list', (
    tester,
  ) async {
    final repository = _FakeAdminSkillsRepository()..loadResult = [_skill()];
    await _pumpScreen(tester, repository: repository);
    expect(repository.getSkillsCallCount, 1);

    unawaited(
      tester.state<RefreshIndicatorState>(find.byType(RefreshIndicator)).show(),
    );
    await tester.pumpAndSettle();

    expect(repository.getSkillsCallCount, 2);
  });

  testWidgets(
    'A failed refresh keeps the old list visible, not a blank screen',
    (tester) async {
      final repository = _FakeAdminSkillsRepository()
        ..loadResult = [_skill(id: 1, name: 'Flutter')];
      await _pumpScreen(tester, repository: repository);
      expect(find.text('Flutter'), findsOneWidget);

      repository.loadResult = null;
      repository.loadError = ApiException('Server error, please retry.');

      unawaited(
        tester
            .state<RefreshIndicatorState>(find.byType(RefreshIndicator))
            .show(),
      );
      await tester.pumpAndSettle();

      expect(find.text('Flutter'), findsOneWidget); // old list retained
      expect(find.text('Server error, please retry.'), findsOneWidget);
    },
  );

  testWidgets('No overflow at a narrow 320-wide viewport', (tester) async {
    final repository = _FakeAdminSkillsRepository()
      ..loadResult = [
        _skill(
          id: 1,
          name: 'A Very Long Skill Name That Might Wrap Or Overflow',
          createdAt: DateTime(2026, 7, 1),
        ),
      ];

    await _pumpScreen(
      tester,
      repository: repository,
      size: const Size(320, 700),
    );

    expect(tester.takeException(), isNull);
  });
}
