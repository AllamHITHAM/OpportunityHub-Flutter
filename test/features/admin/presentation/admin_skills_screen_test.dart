// Widget tests for AdminSkillsScreen, in isolation with a small GoRouter.
// Mirrors admin_users_screen_test.dart's structure and conventions.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'package:opportunityhub_flutter/core/api/api_client.dart';
import 'package:opportunityhub_flutter/core/storage/token_storage_service.dart';
import 'package:opportunityhub_flutter/core/theme/app_colors.dart';
import 'package:opportunityhub_flutter/core/theme/app_theme.dart';
import 'package:opportunityhub_flutter/core/widgets/app_widgets.dart';
import 'package:opportunityhub_flutter/features/admin/data/admin_skill_suggestions_repository.dart';
import 'package:opportunityhub_flutter/features/admin/data/admin_skills_repository.dart';
import 'package:opportunityhub_flutter/features/admin/presentation/admin_skills_screen.dart';
import 'package:opportunityhub_flutter/features/auth/data/auth_repository.dart';
import 'package:opportunityhub_flutter/models/skill_model.dart';
import 'package:opportunityhub_flutter/models/skill_suggestion_model.dart';
import 'package:opportunityhub_flutter/providers/admin_skill_suggestions_provider.dart';
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

SkillSuggestionModel _suggestion({
  int id = 1,
  String name = 'Primavera P6',
  String source = 'ai_cv',
  String status = 'pending',
}) {
  return SkillSuggestionModel(
    id: id,
    name: name,
    source: source,
    status: status,
  );
}

class _FakeAdminSkillSuggestionsRepository
    extends AdminSkillSuggestionsRepository {
  _FakeAdminSkillSuggestionsRepository()
    : super(apiClient: ApiClient(tokenStorageService: TokenStorageService()));

  List<SkillSuggestionModel>? loadResult;
  ApiException? loadError;
  Duration loadDelay = Duration.zero;
  int getPendingSuggestionsCallCount = 0;

  ApiException? approveError;
  Duration approveDelay = Duration.zero;
  final List<int> approvedIds = [];

  ApiException? rejectError;
  Duration rejectDelay = Duration.zero;
  final List<int> rejectedIds = [];

  @override
  Future<List<SkillSuggestionModel>> getPendingSuggestions() async {
    getPendingSuggestionsCallCount++;
    if (loadDelay > Duration.zero) {
      await Future<void>.delayed(loadDelay);
    }
    if (loadError != null) throw loadError!;
    return loadResult ?? [];
  }

  @override
  Future<void> approve(int suggestionId) async {
    approvedIds.add(suggestionId);
    if (approveDelay > Duration.zero) {
      await Future<void>.delayed(approveDelay);
    }
    if (approveError != null) throw approveError!;
  }

  @override
  Future<void> reject(int suggestionId) async {
    rejectedIds.add(suggestionId);
    if (rejectDelay > Duration.zero) {
      await Future<void>.delayed(rejectDelay);
    }
    if (rejectError != null) throw rejectError!;
  }
}

class _Providers {
  _Providers({required this.skills, required this.suggestions});

  final AdminSkillsProvider skills;
  final AdminSkillSuggestionsProvider suggestions;
}

Future<_Providers> _pumpScreen(
  WidgetTester tester, {
  required AdminSkillsRepository repository,
  AdminSkillSuggestionsRepository? suggestionsRepository,
  Size size = const Size(420, 1400),
  bool dark = false,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  if (dark) {
    AppColors.updateBrightness(Brightness.dark);
    addTearDown(() => AppColors.updateBrightness(Brightness.light));
  }

  final authProvider = AuthProvider(authRepository: _FakeAuthRepository());
  final skillsProvider = AdminSkillsProvider(
    repository: repository,
    authProvider: authProvider,
  );
  final suggestionsProvider = AdminSkillSuggestionsProvider(
    repository: suggestionsRepository ?? _FakeAdminSkillSuggestionsRepository(),
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
        ChangeNotifierProvider<AdminSkillSuggestionsProvider>.value(
          value: suggestionsProvider,
        ),
      ],
      child: MaterialApp.router(
        theme: dark ? AppTheme.darkTheme : AppTheme.lightTheme,
        routerConfig: router,
      ),
    ),
  );
  await tester.pumpAndSettle();

  return _Providers(skills: skillsProvider, suggestions: suggestionsProvider);
}

Future<void> _openAddSheet(WidgetTester tester) async {
  await tester.tap(find.widgetWithIcon(IconButton, Icons.add));
  await tester.pumpAndSettle();
}

/// Switches from the default Pending Suggestions tab to the Skill Catalog
/// tab. Matched by partial text since the tab's own label carries a live
/// count (e.g. "Skill Catalog (3)") that varies per test's fixture data.
Future<void> _switchToSkillCatalogTab(WidgetTester tester) async {
  await tester.tap(find.textContaining('Skill Catalog'));
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
    final suggestionsProvider = AdminSkillSuggestionsProvider(
      repository: _FakeAdminSkillSuggestionsRepository(),
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
          ChangeNotifierProvider<AdminSkillSuggestionsProvider>.value(
            value: suggestionsProvider,
          ),
        ],
        child: MaterialApp.router(
          theme: AppTheme.lightTheme,
          routerConfig: router,
        ),
      ),
    );
    await tester.pump();

    // Skill Catalog content only ever renders on its own tab now -- switch
    // to it (a plain `pump()`, not `pumpAndSettle()`, so the still-pending
    // 200ms delayed load is not fast-forwarded to completion by this tap).
    await tester.tap(find.textContaining('Skill Catalog'));
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
      await _switchToSkillCatalogTab(tester);

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
    await _switchToSkillCatalogTab(tester);

    expect(find.text('No skills available.'), findsOneWidget);
    expect(find.text('Add Skill'), findsOneWidget);
  });

  testWidgets('Add Skill action is available when the list is populated', (
    tester,
  ) async {
    final repository = _FakeAdminSkillsRepository()..loadResult = [_skill()];

    await _pumpScreen(tester, repository: repository);

    // Global AppBar action -- reachable regardless of the active tab.
    expect(find.widgetWithIcon(IconButton, Icons.add), findsOneWidget);
  });

  testWidgets('Renders skill name and created date', (tester) async {
    final repository = _FakeAdminSkillsRepository()
      ..loadResult = [
        _skill(id: 1, name: 'Flutter', createdAt: DateTime(2026, 7, 1)),
      ];

    await _pumpScreen(tester, repository: repository);
    await _switchToSkillCatalogTab(tester);

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
    await _switchToSkillCatalogTab(tester);

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
      await _switchToSkillCatalogTab(tester);

      await tester.enterText(
        find.byType(TextFormField),
        'nonexistent-skill-xyz',
      );
      await tester.pumpAndSettle();

      expect(find.text('No Matches'), findsOneWidget);
      expect(find.text('No skills available.'), findsNothing);
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
        expect(find.text('Skill created successfully'), findsOneWidget);
        // No reload -- still exactly the one initial GET.
        expect(repository.getSkillsCallCount, 1);

        await _switchToSkillCatalogTab(tester);
        expect(find.text('Docker'), findsOneWidget);
      },
    );
  });

  group('Edit Skill', () {
    testWidgets('Prefills the current name', (tester) async {
      final repository = _FakeAdminSkillsRepository()
        ..loadResult = [_skill(id: 1, name: 'Flutter')];
      await _pumpScreen(tester, repository: repository);
      await _switchToSkillCatalogTab(tester);

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
        await _switchToSkillCatalogTab(tester);

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
      await _switchToSkillCatalogTab(tester);

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
      await _switchToSkillCatalogTab(tester);

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
        await _switchToSkillCatalogTab(tester);

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
        await _switchToSkillCatalogTab(tester);

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
      await _switchToSkillCatalogTab(tester);

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
    await _switchToSkillCatalogTab(tester);

    unawaited(
      tester
          .state<RefreshIndicatorState>(find.byType(RefreshIndicator))
          .show(),
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
      await _switchToSkillCatalogTab(tester);
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
    await _switchToSkillCatalogTab(tester);

    expect(tester.takeException(), isNull);
  });

  group('Pending Skill Suggestions', () {
    testWidgets('Renders pending suggestions on the default tab', (
      tester,
    ) async {
      final repository = _FakeAdminSkillsRepository()..loadResult = [_skill()];
      final suggestionsRepository = _FakeAdminSkillSuggestionsRepository()
        ..loadResult = [_suggestion(id: 1, name: 'Primavera P6')];

      await _pumpScreen(
        tester,
        repository: repository,
        suggestionsRepository: suggestionsRepository,
      );

      // Pending Suggestions is the tab shown by default, without needing
      // any tap -- no separate section header text is needed to identify
      // it, since the tab label itself carries that ("Pending Suggestions
      // (1)").
      expect(find.text('Pending Suggestions (1)'), findsOneWidget);
      expect(find.text('Primavera P6'), findsOneWidget);
      expect(find.text('From AI CV extraction'), findsOneWidget);
    });

    testWidgets(
      'Shows the exact empty-state text when there are no pending suggestions',
      (tester) async {
        final repository = _FakeAdminSkillsRepository()..loadResult = [_skill()];
        final suggestionsRepository = _FakeAdminSkillSuggestionsRepository()
          ..loadResult = [];

        await _pumpScreen(
          tester,
          repository: repository,
          suggestionsRepository: suggestionsRepository,
        );

        expect(find.text('No pending skill suggestions.'), findsOneWidget);
      },
    );

    testWidgets('Loading state shows a compact loading indicator', (
      tester,
    ) async {
      final repository = _FakeAdminSkillsRepository()..loadResult = [_skill()];
      final suggestionsRepository = _FakeAdminSkillSuggestionsRepository()
        ..loadResult = [_suggestion(id: 1, name: 'Primavera P6')]
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
      final suggestionsProvider = AdminSkillSuggestionsProvider(
        repository: suggestionsRepository,
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
            ChangeNotifierProvider<AdminSkillSuggestionsProvider>.value(
              value: suggestionsProvider,
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

      expect(suggestionsProvider.isLoading, isTrue);
      expect(find.text('Primavera P6'), findsNothing);

      await tester.pumpAndSettle();
    });

    testWidgets('Error state shows a retry that reloads the suggestions', (
      tester,
    ) async {
      final repository = _FakeAdminSkillsRepository()..loadResult = [_skill()];
      final suggestionsRepository = _FakeAdminSkillSuggestionsRepository()
        ..loadError = ApiException('Server error, please try again later.');

      final providers = await _pumpScreen(
        tester,
        repository: repository,
        suggestionsRepository: suggestionsRepository,
      );

      expect(find.text('Could Not Load Suggestions'), findsOneWidget);
      expect(
        find.text('Server error, please try again later.'),
        findsOneWidget,
      );

      suggestionsRepository.loadError = null;
      suggestionsRepository.loadResult = [
        _suggestion(id: 1, name: 'Primavera P6'),
      ];
      await tester.tap(find.text('Try Again'));
      await tester.pumpAndSettle();

      expect(find.text('Primavera P6'), findsOneWidget);
      expect(providers.suggestions.suggestions, hasLength(1));
    });

    testWidgets(
      'Approve calls the repository, removes the row, shows a SnackBar',
      (tester) async {
        final repository = _FakeAdminSkillsRepository()
          ..loadResult = [_skill()];
        final suggestionsRepository = _FakeAdminSkillSuggestionsRepository()
          ..loadResult = [_suggestion(id: 5, name: 'Primavera P6')];

        await _pumpScreen(
          tester,
          repository: repository,
          suggestionsRepository: suggestionsRepository,
        );

        await tester.tap(find.byKey(const Key('approve-suggestion-5')));
        await tester.pumpAndSettle();

        expect(suggestionsRepository.approvedIds, [5]);
        expect(find.text('Primavera P6'), findsNothing);
        expect(find.text('Skill suggestion approved'), findsOneWidget);
      },
    );

    testWidgets(
      'Reject calls the repository, removes the row, shows a SnackBar',
      (tester) async {
        final repository = _FakeAdminSkillsRepository()
          ..loadResult = [_skill()];
        final suggestionsRepository = _FakeAdminSkillSuggestionsRepository()
          ..loadResult = [_suggestion(id: 5, name: 'Primavera P6')];

        await _pumpScreen(
          tester,
          repository: repository,
          suggestionsRepository: suggestionsRepository,
        );

        await tester.tap(find.byKey(const Key('reject-suggestion-5')));
        await tester.pumpAndSettle();

        expect(suggestionsRepository.rejectedIds, [5]);
        expect(find.text('Primavera P6'), findsNothing);
        expect(find.text('Skill suggestion rejected'), findsOneWidget);
      },
    );

    testWidgets('A failed approve keeps the row and shows the error', (
      tester,
    ) async {
      final repository = _FakeAdminSkillsRepository()..loadResult = [_skill()];
      final suggestionsRepository = _FakeAdminSkillSuggestionsRepository()
        ..loadResult = [_suggestion(id: 5, name: 'Primavera P6')]
        ..approveError = ApiException(
          'This suggestion has already been reviewed.',
          statusCode: 409,
        );

      await _pumpScreen(
        tester,
        repository: repository,
        suggestionsRepository: suggestionsRepository,
      );

      await tester.tap(find.byKey(const Key('approve-suggestion-5')));
      await tester.pumpAndSettle();

      expect(find.text('Primavera P6'), findsOneWidget); // row preserved
      expect(
        find.text('This suggestion has already been reviewed.'),
        findsOneWidget,
      );
    });

    testWidgets('Busy state disables the row actions while in flight', (
      tester,
    ) async {
      final repository = _FakeAdminSkillsRepository()..loadResult = [_skill()];
      final suggestionsRepository = _FakeAdminSkillSuggestionsRepository()
        ..loadResult = [_suggestion(id: 5, name: 'Primavera P6')]
        ..approveDelay = const Duration(milliseconds: 2000);

      await _pumpScreen(
        tester,
        repository: repository,
        suggestionsRepository: suggestionsRepository,
      );

      await tester.tap(find.byKey(const Key('approve-suggestion-5')));
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.byKey(const Key('approve-suggestion-5')), findsNothing);
      expect(find.byKey(const Key('reject-suggestion-5')), findsNothing);

      await tester.pumpAndSettle();
    });
  });

  group('Overflow + responsive fix (Admin Manage Skills Final UI)', () {
    const veryLongSkillName =
        'A Very Long Skill Name That Should Wrap Instead Of Overflowing '
        'Or Being Truncated On Any Realistic Screen Width';

    testWidgets(
      '100+ pending suggestions render and scroll with no RenderFlex '
      'overflow',
      (tester) async {
        final repository = _FakeAdminSkillsRepository()
          ..loadResult = [_skill(id: 1, name: 'Flutter')];
        final suggestionsRepository = _FakeAdminSkillSuggestionsRepository()
          ..loadResult = List.generate(
            120,
            (i) => _suggestion(id: i, name: 'Suggestion $i'),
          );

        await _pumpScreen(
          tester,
          repository: repository,
          suggestionsRepository: suggestionsRepository,
        );

        expect(tester.takeException(), isNull);

        // The list is genuinely lazy (a real `SliverList`) -- the last
        // suggestion isn't built yet until scrolled into view. Scoped to
        // this tab's own keyed `Scrollable` -- with keep-alive on both
        // tabs, more than one `Scrollable` can coexist in the tree
        // (this tab's, the Skill Catalog tab's, and the `TabBarView`'s
        // own horizontal `PageView`), so an unscoped `find.byType` isn't
        // reliably disambiguated by position alone.
        await tester.scrollUntilVisible(
          find.text('Suggestion 119'),
          500,
          scrollable: find.descendant(
            of: find.byKey(const ValueKey('pending-suggestions-scroll')),
            matching: find.byType(Scrollable),
          ),
        );

        expect(find.text('Suggestion 119'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'a large Pending list does not require scrolling to reach the Skill '
      'Catalog -- a single tab tap reaches it directly, and its own list '
      'still scrolls to its last item',
      (tester) async {
        final repository = _FakeAdminSkillsRepository()
          ..loadResult = List.generate(
            80,
            (i) => _skill(id: i + 1, name: 'Catalog Skill $i'),
          );
        final suggestionsRepository = _FakeAdminSkillSuggestionsRepository()
          ..loadResult = List.generate(
            60,
            (i) => _suggestion(id: i, name: 'Suggestion $i'),
          );

        await _pumpScreen(
          tester,
          repository: repository,
          suggestionsRepository: suggestionsRepository,
        );

        // No scrolling through 60 pending suggestions -- one tap reaches
        // the catalog.
        await _switchToSkillCatalogTab(tester);
        expect(find.text('Catalog Skill 0'), findsOneWidget);

        // The catalog's own list is still a genuine, scrollable
        // `SliverList` capable of reaching its final item -- scoped to
        // its own keyed `Scrollable`, see the equivalent Pending
        // Suggestions scroll test above for why. `.first`, not the bare
        // descendant search -- the search field inside this tab is a
        // `TextField`, which has its own internal `Scrollable` for
        // cursor movement, nested inside the outer one.
        await tester.scrollUntilVisible(
          find.text('Catalog Skill 79'),
          500,
          scrollable: find
              .descendant(
                of: find.byKey(const ValueKey('skill-catalog-scroll')),
                matching: find.byType(Scrollable),
              )
              .first,
        );

        expect(find.text('Catalog Skill 79'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('a very long skill name in the catalog wraps, never '
        'overflows', (tester) async {
      final repository = _FakeAdminSkillsRepository()
        ..loadResult = [_skill(id: 1, name: veryLongSkillName)];

      await _pumpScreen(
        tester,
        repository: repository,
        size: const Size(320, 700),
      );
      await _switchToSkillCatalogTab(tester);

      expect(find.textContaining('A Very Long Skill Name'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'a very long pending suggestion name wraps, never overflows',
      (tester) async {
        final repository = _FakeAdminSkillsRepository()
          ..loadResult = [_skill(id: 1, name: 'Flutter')];
        final suggestionsRepository = _FakeAdminSkillSuggestionsRepository()
          ..loadResult = [_suggestion(id: 1, name: veryLongSkillName)];

        await _pumpScreen(
          tester,
          repository: repository,
          suggestionsRepository: suggestionsRepository,
          size: const Size(320, 700),
        );

        expect(find.textContaining('A Very Long Skill Name'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );

    for (final entry in {
      'desktop (1400x900)': const Size(1400, 900),
      'tablet (700x900)': const Size(700, 900),
      '320px mobile': const Size(320, 700),
      '375px mobile': const Size(375, 812),
      '430px mobile': const Size(430, 900),
    }.entries) {
      testWidgets(
        'no overflow with a large real dataset at ${entry.key}, on either '
        'tab',
        (tester) async {
          final repository = _FakeAdminSkillsRepository()
            ..loadResult = List.generate(
              40,
              (i) => _skill(id: i + 1, name: 'Catalog Skill $i'),
            );
          final suggestionsRepository = _FakeAdminSkillSuggestionsRepository()
            ..loadResult = List.generate(
              40,
              (i) => _suggestion(id: i, name: 'Suggestion $i'),
            );

          await _pumpScreen(
            tester,
            repository: repository,
            suggestionsRepository: suggestionsRepository,
            size: entry.value,
          );

          // Pending tab (the default), TabBar included -- the tab bar
          // itself must fit at every one of these widths without pushing
          // the page into horizontal scroll.
          expect(tester.takeException(), isNull);

          await _switchToSkillCatalogTab(tester);
          expect(tester.takeException(), isNull);
        },
      );
    }

    testWidgets('renders correctly in Dark Mode with a populated screen', (
      tester,
    ) async {
      final repository = _FakeAdminSkillsRepository()
        ..loadResult = [_skill(id: 1, name: 'Flutter')];
      final suggestionsRepository = _FakeAdminSkillSuggestionsRepository()
        ..loadResult = [_suggestion(id: 1, name: 'Primavera P6')];

      await _pumpScreen(
        tester,
        repository: repository,
        suggestionsRepository: suggestionsRepository,
        dark: true,
      );

      expect(tester.takeException(), isNull);
      expect(find.text('Primavera P6'), findsOneWidget);

      await _switchToSkillCatalogTab(tester);
      expect(tester.takeException(), isNull);
      expect(find.text('Flutter'), findsOneWidget);
    });

    testWidgets(
      'Approve/Reject expose a distinct semantic label per suggestion, '
      'not just a bare "Approve"/"Reject"',
      (tester) async {
        final repository = _FakeAdminSkillsRepository()
          ..loadResult = [_skill(id: 1, name: 'Flutter')];
        final suggestionsRepository = _FakeAdminSkillSuggestionsRepository()
          ..loadResult = [_suggestion(id: 5, name: 'Primavera P6')];

        await _pumpScreen(
          tester,
          repository: repository,
          suggestionsRepository: suggestionsRepository,
        );

        final labels = tester
            .widgetList<Semantics>(find.byType(Semantics))
            .map((s) => s.properties.label)
            .whereType<String>()
            .toSet();

        expect(labels, contains('Approve suggestion: Primavera P6'));
        expect(labels, contains('Reject suggestion: Primavera P6'));
      },
    );

    testWidgets(
      'the centered desktop content never exceeds the Admin Dashboard\'s '
      'own max content width',
      (tester) async {
        final repository = _FakeAdminSkillsRepository()
          ..loadResult = [_skill(id: 1, name: 'Flutter')];

        await _pumpScreen(
          tester,
          repository: repository,
          size: const Size(1600, 900),
        );
        await _switchToSkillCatalogTab(tester);

        final cardBox = tester.getSize(
          find.ancestor(
            of: find.text('Flutter'),
            matching: find.byType(AppCard),
          ),
        );
        expect(cardBox.width, lessThanOrEqualTo(900));
      },
    );
  });

  group('Admin Manage Skills -- UX Polish (tabs)', () {
    testWidgets('Pending Suggestions is the active tab on initial open', (
      tester,
    ) async {
      final repository = _FakeAdminSkillsRepository()
        ..loadResult = [_skill(id: 1, name: 'Flutter')];
      final suggestionsRepository = _FakeAdminSkillSuggestionsRepository()
        ..loadResult = [_suggestion(id: 1, name: 'Primavera P6')];

      await _pumpScreen(
        tester,
        repository: repository,
        suggestionsRepository: suggestionsRepository,
      );

      // The Pending Suggestions content is visible without any tap...
      expect(find.text('Primavera P6'), findsOneWidget);
      // ...while the Skill Catalog's own content is not yet rendered.
      expect(find.text('Flutter'), findsNothing);

      final tabController = DefaultTabController.of(
        tester.element(find.byType(TabBarView)),
      );
      expect(tabController.index, 0);
    });

    testWidgets(
      'Switching to the Skill Catalog tab renders catalog content and '
      'hides the Pending Suggestions list',
      (tester) async {
        final repository = _FakeAdminSkillsRepository()
          ..loadResult = [_skill(id: 1, name: 'Flutter')];
        final suggestionsRepository = _FakeAdminSkillSuggestionsRepository()
          ..loadResult = [_suggestion(id: 1, name: 'Primavera P6')];

        await _pumpScreen(
          tester,
          repository: repository,
          suggestionsRepository: suggestionsRepository,
        );

        await _switchToSkillCatalogTab(tester);

        expect(find.text('Flutter'), findsOneWidget);
        expect(find.text('Primavera P6'), findsNothing);
      },
    );

    testWidgets(
      'The tab label is exactly "Skill Catalog", never "Accepted"',
      (tester) async {
        final repository = _FakeAdminSkillsRepository()
          ..loadResult = [_skill(id: 1, name: 'Flutter')];
        final suggestionsRepository = _FakeAdminSkillSuggestionsRepository()
          ..loadResult = [_suggestion(id: 1, name: 'Primavera P6')];

        await _pumpScreen(
          tester,
          repository: repository,
          suggestionsRepository: suggestionsRepository,
        );

        expect(find.textContaining('Skill Catalog'), findsOneWidget);
        expect(find.textContaining('Accepted'), findsNothing);
      },
    );

    testWidgets(
      'Tab labels show live counts for both Pending Suggestions and Skill '
      'Catalog',
      (tester) async {
        final repository = _FakeAdminSkillsRepository()
          ..loadResult = [
            _skill(id: 1, name: 'Flutter'),
            _skill(id: 2, name: 'Laravel'),
          ];
        final suggestionsRepository = _FakeAdminSkillSuggestionsRepository()
          ..loadResult = [_suggestion(id: 1, name: 'Primavera P6')];

        await _pumpScreen(
          tester,
          repository: repository,
          suggestionsRepository: suggestionsRepository,
        );

        expect(find.text('Pending Suggestions (1)'), findsOneWidget);
        expect(find.text('Skill Catalog (2)'), findsOneWidget);
      },
    );

    testWidgets('Switching tabs does not trigger another fetch', (
      tester,
    ) async {
      final repository = _FakeAdminSkillsRepository()
        ..loadResult = [_skill(id: 1, name: 'Flutter')];
      final suggestionsRepository = _FakeAdminSkillSuggestionsRepository()
        ..loadResult = [_suggestion(id: 1, name: 'Primavera P6')];

      await _pumpScreen(
        tester,
        repository: repository,
        suggestionsRepository: suggestionsRepository,
      );
      expect(repository.getSkillsCallCount, 1);
      expect(suggestionsRepository.getPendingSuggestionsCallCount, 1);

      await _switchToSkillCatalogTab(tester);
      await tester.tap(find.textContaining('Pending Suggestions'));
      await tester.pumpAndSettle();
      await _switchToSkillCatalogTab(tester);

      expect(repository.getSkillsCallCount, 1);
      expect(suggestionsRepository.getPendingSuggestionsCallCount, 1);
    });
  });
}
