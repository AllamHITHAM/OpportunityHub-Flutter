// Direct unit tests for AdminSkillsProvider, using a fake repository (no
// real network) and a real AuthProvider (with a fake AuthRepository) so
// the reset-on-logout listener can be exercised genuinely. Mirrors
// admin_users_provider_test.dart's and
// admin_organizations_provider_test.dart's structure and conventions.

import 'package:flutter_test/flutter_test.dart';

import 'package:opportunityhub_flutter/core/api/api_client.dart';
import 'package:opportunityhub_flutter/core/storage/token_storage_service.dart';
import 'package:opportunityhub_flutter/features/admin/data/admin_skills_repository.dart';
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

  @override
  Future<void> logout() async {
    // A no-op: this test only cares that AuthProvider.logout() flips
    // `isAuthenticated` to false (which it does regardless of what the
    // repository does), not about the real network/secure-storage calls
    // that would otherwise require a platform-channel binding.
  }
}

SkillModel _skill({int id = 1, String name = 'Flutter'}) {
  return SkillModel(id: id, name: name);
}

class _FakeAdminSkillsRepository extends AdminSkillsRepository {
  _FakeAdminSkillsRepository()
    : super(apiClient: ApiClient(tokenStorageService: TokenStorageService()));

  List<SkillModel>? loadResult;
  ApiException? loadError;
  Object? loadRuntimeError;
  Duration loadDelay = Duration.zero;
  int getSkillsCallCount = 0;

  SkillModel? createResult;
  ApiException? createError;
  Object? createRuntimeError;
  Duration createDelay = Duration.zero;
  int createSkillCallCount = 0;

  SkillModel? updateResult;
  ApiException? updateError;
  Object? updateRuntimeError;
  Duration updateDelay = Duration.zero;
  int updateSkillCallCount = 0;

  ApiException? deleteError;
  Object? deleteRuntimeError;
  Duration deleteDelay = Duration.zero;
  int deleteSkillCallCount = 0;

  @override
  Future<List<SkillModel>> getSkills() async {
    getSkillsCallCount++;
    // Captured immediately, like a real request's response would be
    // determined by what the server had at request time — not whichever
    // fields happen to be set by the time a later `await` resumes. This
    // lets a test simulate two genuinely different in-flight responses.
    final result = loadResult ?? [];
    final runtimeError = loadRuntimeError;
    final error = loadError;
    if (loadDelay > Duration.zero) {
      await Future<void>.delayed(loadDelay);
    }
    if (runtimeError != null) throw runtimeError;
    if (error != null) throw error;
    return result;
  }

  @override
  Future<SkillModel> createSkill({required String name}) async {
    createSkillCallCount++;
    if (createDelay > Duration.zero) {
      await Future<void>.delayed(createDelay);
    }
    if (createRuntimeError != null) throw createRuntimeError!;
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
    if (updateRuntimeError != null) throw updateRuntimeError!;
    if (updateError != null) throw updateError!;
    return updateResult!;
  }

  @override
  Future<void> deleteSkill(int skillId) async {
    deleteSkillCallCount++;
    if (deleteDelay > Duration.zero) {
      await Future<void>.delayed(deleteDelay);
    }
    if (deleteRuntimeError != null) throw deleteRuntimeError!;
    if (deleteError != null) throw deleteError!;
  }
}

void main() {
  late AuthProvider authProvider;
  late _FakeAdminSkillsRepository repository;
  late AdminSkillsProvider provider;

  setUp(() {
    authProvider = AuthProvider(authRepository: _FakeAuthRepository());
    repository = _FakeAdminSkillsRepository();
    provider = AdminSkillsProvider(
      repository: repository,
      authProvider: authProvider,
    );
  });

  test('initial state is empty and idle', () {
    expect(provider.skills, isEmpty);
    expect(provider.isLoading, isFalse);
    expect(provider.errorMessage, isNull);
    expect(provider.actionErrorMessage, isNull);
    expect(provider.fieldErrors, isEmpty);
    expect(provider.busySkillIds, isEmpty);
    expect(provider.isCreating, isFalse);
  });

  group('load', () {
    test('success populates the list', () async {
      repository.loadResult = [_skill(id: 1), _skill(id: 2, name: 'Laravel')];

      await provider.load();

      expect(provider.skills, hasLength(2));
      expect(provider.isLoading, isFalse);
      expect(provider.errorMessage, isNull);
    });

    test('an empty list is represented correctly, not as an error', () async {
      await provider.load();

      expect(provider.skills, isEmpty);
      expect(provider.errorMessage, isNull);
    });

    test('failure surfaces the error and is retryable', () async {
      repository.loadError = ApiException(
        'Server error, please try again later.',
      );

      await provider.load();

      expect(provider.errorMessage, 'Server error, please try again later.');
      expect(provider.skills, isEmpty);

      repository.loadError = null;
      repository.loadResult = [_skill()];
      await provider.load(forceRefresh: true);

      expect(provider.errorMessage, isNull);
      expect(provider.skills, hasLength(1));
    });

    test('malformed repository data never enters provider.skills', () async {
      repository.loadRuntimeError = FormatException('Skill "id" is not an int');

      await provider.load();

      expect(provider.skills, isEmpty);
      expect(provider.isLoading, isFalse);
      expect(provider.errorMessage, 'Something went wrong. Please try again.');
      expect(provider.errorMessage, isNot(contains('FormatException')));
    });

    test('duplicate concurrent loads are deduplicated', () async {
      repository.loadResult = [_skill()];
      repository.loadDelay = const Duration(milliseconds: 50);

      final first = provider.load();
      final second = provider.load();
      await Future.wait([first, second]);

      expect(repository.getSkillsCallCount, 1);
    });

    test('forceRefresh starts a new fetch even while unchanged', () async {
      await provider.load();
      await provider.load(forceRefresh: true);

      expect(repository.getSkillsCallCount, 2);
    });

    test('a stale response from a slower first load never overwrites a faster '
        'forceRefresh — the newer request always wins, regardless of arrival '
        'order', () async {
      repository.loadResult = [_skill(id: 1, name: 'Stale')];
      repository.loadDelay = const Duration(milliseconds: 50);
      final firstLoad = provider.load();

      repository.loadResult = [_skill(id: 2, name: 'Fresh')];
      repository.loadDelay = const Duration(milliseconds: 5);
      await provider.load(forceRefresh: true);

      expect(provider.skills, hasLength(1));
      expect(provider.skills.single.name, 'Fresh');

      await firstLoad;

      expect(repository.getSkillsCallCount, 2);
      expect(provider.skills, hasLength(1));
      expect(provider.skills.single.name, 'Fresh');
    });

    test('reset invalidates a load still in flight', () async {
      repository.loadResult = [_skill(id: 1, name: 'Stale')];
      repository.loadDelay = const Duration(milliseconds: 50);
      final staleLoad = provider.load();

      provider.reset();
      await staleLoad;

      // The stale response must not repopulate state after reset.
      expect(provider.skills, isEmpty);
    });
  });

  group('createSkill', () {
    test('success adds the returned skill to the list', () async {
      repository.createResult = _skill(id: 7, name: 'Docker');

      final success = await provider.createSkill(name: 'Docker');

      expect(success, isTrue);
      expect(provider.skills, hasLength(1));
      expect(provider.skills.single.name, 'Docker');
    });

    test('does not reload the whole list', () async {
      repository.createResult = _skill(id: 7, name: 'Docker');

      await provider.createSkill(name: 'Docker');

      expect(repository.getSkillsCallCount, 0);
    });

    test('failure retains previous state', () async {
      repository.loadResult = [_skill(id: 1, name: 'Flutter')];
      await provider.load();

      repository.createError = ApiException('Server error.');
      final success = await provider.createSkill(name: 'Docker');

      expect(success, isFalse);
      expect(provider.skills, hasLength(1));
      expect(provider.actionErrorMessage, 'Server error.');
    });

    test('preserves backend field errors', () async {
      repository.createError = ApiException(
        'The given data was invalid.',
        statusCode: 422,
        errors: {
          'name': ['The name has already been taken.'],
        },
      );

      await provider.createSkill(name: 'Docker');

      expect(provider.fieldErrors['name'], [
        'The name has already been taken.',
      ]);
    });

    test(
      'an unexpected failure exposes a safe, non-technical message',
      () async {
        repository.createRuntimeError = TypeError();

        await provider.createSkill(name: 'Docker');

        expect(provider.actionErrorMessage, isNotNull);
        expect(provider.actionErrorMessage, isNot(contains('TypeError')));
        expect(
          provider.actionErrorMessage,
          'Something went wrong. Please try again.',
        );
        expect(provider.skills, isEmpty);
      },
    );

    test('a duplicate create tap while one is in flight is blocked (only one '
        'repository call)', () async {
      repository.createResult = _skill(id: 7, name: 'Docker');
      repository.createDelay = const Duration(milliseconds: 50);

      final first = provider.createSkill(name: 'Docker');
      final second = provider.createSkill(name: 'Docker');

      final results = await Future.wait([first, second]);

      expect(repository.createSkillCallCount, 1);
      expect(results.where((success) => success).length, 1);
      expect(results.where((success) => !success).length, 1);
    });

    test('isCreating is cleared in finally after success', () async {
      repository.createResult = _skill(id: 7, name: 'Docker');

      expect(provider.isCreating, isFalse);
      final future = provider.createSkill(name: 'Docker');
      expect(provider.isCreating, isTrue);
      await future;
      expect(provider.isCreating, isFalse);
    });

    test('isCreating is cleared in finally after failure', () async {
      repository.createError = ApiException('Server error.');

      await provider.createSkill(name: 'Docker');

      expect(provider.isCreating, isFalse);
    });
  });

  group('updateSkill', () {
    test('success patches only the matching skill', () async {
      repository.loadResult = [
        _skill(id: 1, name: 'Flutter'),
        _skill(id: 2, name: 'Laravel'),
      ];
      await provider.load();

      repository.updateResult = _skill(id: 1, name: 'Flutter (Dart)');
      final success = await provider.updateSkill(
        skillId: 1,
        name: 'Flutter (Dart)',
      );

      expect(success, isTrue);
      expect(
        provider.skills.firstWhere((s) => s.id == 1).name,
        'Flutter (Dart)',
      );
      // The other skill is untouched.
      expect(provider.skills.firstWhere((s) => s.id == 2).name, 'Laravel');
    });

    test('does not reload the whole list', () async {
      repository.loadResult = [_skill(id: 1, name: 'Flutter')];
      await provider.load();
      repository.updateResult = _skill(id: 1, name: 'New Name');

      await provider.updateSkill(skillId: 1, name: 'New Name');

      expect(repository.getSkillsCallCount, 1);
    });

    test('failure retains the old skill data', () async {
      repository.loadResult = [_skill(id: 1, name: 'Flutter')];
      await provider.load();

      repository.updateError = ApiException('Server error.');
      final success = await provider.updateSkill(skillId: 1, name: 'New Name');

      expect(success, isFalse);
      expect(provider.skills.single.name, 'Flutter');
      expect(provider.actionErrorMessage, 'Server error.');
    });

    test('preserves backend field errors', () async {
      repository.loadResult = [_skill(id: 1, name: 'Flutter')];
      await provider.load();

      repository.updateError = ApiException(
        'The given data was invalid.',
        statusCode: 422,
        errors: {
          'name': ['The name has already been taken.'],
        },
      );

      await provider.updateSkill(skillId: 1, name: 'Laravel');

      expect(provider.fieldErrors['name'], [
        'The name has already been taken.',
      ]);
    });

    test('busy ID is removed in finally after a successful update', () async {
      repository.loadResult = [_skill(id: 1, name: 'Flutter')];
      repository.updateResult = _skill(id: 1, name: 'New Name');
      await provider.load();

      expect(provider.isBusy(1), isFalse);
      final future = provider.updateSkill(skillId: 1, name: 'New Name');
      expect(provider.isBusy(1), isTrue);
      await future;
      expect(provider.isBusy(1), isFalse);
    });

    test('busy ID is removed in finally after a failed update', () async {
      repository.loadResult = [_skill(id: 1, name: 'Flutter')];
      repository.updateError = ApiException('Server error.');
      await provider.load();

      await provider.updateSkill(skillId: 1, name: 'New Name');

      expect(provider.isBusy(1), isFalse);
    });

    test('a second update for the same skill while one is in flight is blocked '
        '(only one repository call)', () async {
      repository.loadResult = [_skill(id: 1, name: 'Flutter')];
      repository.updateDelay = const Duration(milliseconds: 50);
      repository.updateResult = _skill(id: 1, name: 'New Name');
      await provider.load();

      final first = provider.updateSkill(skillId: 1, name: 'New Name');
      final second = provider.updateSkill(skillId: 1, name: 'New Name');

      final results = await Future.wait([first, second]);

      expect(repository.updateSkillCallCount, 1);
      expect(results.where((success) => success).length, 1);
      expect(results.where((success) => !success).length, 1);
    });
  });

  group('deleteSkill', () {
    test('success removes only the matching skill', () async {
      repository.loadResult = [
        _skill(id: 1, name: 'Flutter'),
        _skill(id: 2, name: 'Laravel'),
      ];
      await provider.load();

      final success = await provider.deleteSkill(1);

      expect(success, isTrue);
      expect(provider.skills, hasLength(1));
      expect(provider.skills.single.id, 2);
    });

    test('does not reload the whole list', () async {
      repository.loadResult = [_skill(id: 1, name: 'Flutter')];
      await provider.load();

      await provider.deleteSkill(1);

      expect(repository.getSkillsCallCount, 1);
    });

    test('a 409 delete conflict preserves the skill in the list', () async {
      repository.loadResult = [_skill(id: 1, name: 'Flutter')];
      await provider.load();

      repository.deleteError = ApiException(
        'Cannot delete a skill that is currently in use',
        statusCode: 409,
      );
      final success = await provider.deleteSkill(1);

      expect(success, isFalse);
      expect(provider.skills, hasLength(1));
      expect(
        provider.actionErrorMessage,
        'Cannot delete a skill that is currently in use',
      );
    });

    test('busy ID is removed in finally after a successful delete', () async {
      repository.loadResult = [_skill(id: 1, name: 'Flutter')];
      await provider.load();

      expect(provider.isBusy(1), isFalse);
      final future = provider.deleteSkill(1);
      expect(provider.isBusy(1), isTrue);
      await future;
      expect(provider.isBusy(1), isFalse);
    });

    test('busy ID is removed in finally after a failed delete', () async {
      repository.loadResult = [_skill(id: 1, name: 'Flutter')];
      repository.deleteError = ApiException('Server error.');
      await provider.load();

      await provider.deleteSkill(1);

      expect(provider.isBusy(1), isFalse);
    });

    test('a second delete for the same skill while one is in flight is blocked '
        '(only one repository call)', () async {
      repository.loadResult = [_skill(id: 1, name: 'Flutter')];
      repository.deleteDelay = const Duration(milliseconds: 50);
      await provider.load();

      final first = provider.deleteSkill(1);
      final second = provider.deleteSkill(1);

      final results = await Future.wait([first, second]);

      expect(repository.deleteSkillCallCount, 1);
      expect(results.where((success) => success).length, 1);
      expect(results.where((success) => !success).length, 1);
    });
  });

  test(
    'different skills can be acted on independently at the same time',
    () async {
      repository.loadResult = [
        _skill(id: 1, name: 'Flutter'),
        _skill(id: 2, name: 'Laravel'),
      ];
      repository.updateDelay = const Duration(milliseconds: 50);
      repository.updateResult = _skill(id: 1, name: 'New Name');
      await provider.load();

      final updateAction = provider.updateSkill(skillId: 1, name: 'New Name');
      expect(provider.isBusy(1), isTrue);
      expect(provider.isBusy(2), isFalse);

      final deleteAction = provider.deleteSkill(2);
      expect(provider.isBusy(2), isTrue);

      final results = await Future.wait([updateAction, deleteAction]);

      expect(repository.updateSkillCallCount, 1);
      expect(repository.deleteSkillCallCount, 1);
      expect(results, [true, true]);
    },
  );

  test('clearActionErrors clears the action error and field errors', () async {
    repository.createError = ApiException(
      'The given data was invalid.',
      statusCode: 422,
      errors: {
        'name': ['The name has already been taken.'],
      },
    );
    await provider.createSkill(name: 'Docker');
    expect(provider.actionErrorMessage, isNotNull);
    expect(provider.fieldErrors, isNotEmpty);

    provider.clearActionErrors();

    expect(provider.actionErrorMessage, isNull);
    expect(provider.fieldErrors, isEmpty);
  });

  test('reset clears all state', () async {
    repository.loadResult = [_skill(id: 1)];
    await provider.load();
    expect(provider.skills, isNotEmpty);

    provider.reset();

    expect(provider.skills, isEmpty);
    expect(provider.isLoading, isFalse);
    expect(provider.errorMessage, isNull);
    expect(provider.actionErrorMessage, isNull);
    expect(provider.fieldErrors, isEmpty);
    expect(provider.busySkillIds, isEmpty);
    expect(provider.isCreating, isFalse);
  });

  test('reset clears state on logout', () async {
    repository.loadResult = [_skill(id: 1)];
    await provider.load();
    expect(provider.skills, isNotEmpty);

    await authProvider.logout();

    expect(provider.skills, isEmpty);
    expect(provider.errorMessage, isNull);
    expect(provider.isLoading, isFalse);
  });

  test(
    'dispose removes the AuthProvider listener (no error on logout after dispose)',
    () async {
      provider.dispose();

      // Should complete cleanly even though the provider is disposed — the
      // listener was correctly removed, so AuthProvider's own
      // notifyListeners() never tries to call back into a disposed
      // ChangeNotifier (which would throw "used after being disposed").
      await expectLater(authProvider.logout(), completes);
    },
  );
}
