// Direct unit tests for StudentSkillProvider, using a fake repository (no
// real network) and a real AuthProvider (with a fake AuthRepository) so the
// reset-on-logout listener can be exercised genuinely. Mirrors
// student_cv_provider_test.dart's own conventions.

import 'package:flutter_test/flutter_test.dart';

import 'package:opportunityhub_flutter/core/api/api_client.dart';
import 'package:opportunityhub_flutter/core/storage/token_storage_service.dart';
import 'package:opportunityhub_flutter/features/auth/data/auth_repository.dart';
import 'package:opportunityhub_flutter/features/skills/data/student_skill_repository.dart';
import 'package:opportunityhub_flutter/models/skill_model.dart';
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

  @override
  Future<void> logout() async {
    // A no-op -- this test only cares that AuthProvider.logout() flips
    // `isAuthenticated` to false, not the real network/secure-storage calls.
  }
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

  List<SkillModel>? catalogResult;
  ApiException? catalogError;
  Duration catalogDelay = Duration.zero;
  int getSkillCatalogCallCount = 0;

  StudentSkillModel? addResult;
  ApiException? addError;
  Object? addRuntimeError;
  Duration addDelay = Duration.zero;
  int addSkillCallCount = 0;
  int? lastAddedSkillId;
  String? lastAddedLevel;

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

  @override
  Future<List<SkillModel>> getSkillCatalog() async {
    getSkillCatalogCallCount++;
    if (catalogDelay > Duration.zero) {
      await Future<void>.delayed(catalogDelay);
    }
    if (catalogError != null) throw catalogError!;
    return catalogResult ?? [];
  }

  @override
  Future<StudentSkillModel> addSkill({
    required int skillId,
    String level = 'intermediate',
    String source = 'manual',
    int? cvId,
  }) async {
    addSkillCallCount++;
    lastAddedSkillId = skillId;
    lastAddedLevel = level;
    if (addDelay > Duration.zero) {
      await Future<void>.delayed(addDelay);
    }
    if (addRuntimeError != null) throw addRuntimeError!;
    if (addError != null) throw addError!;
    return addResult ??
        StudentSkillModel(
          id: 100 + addSkillCallCount,
          skillId: skillId,
          skillName: 'Added Skill',
          level: level,
          source: source,
        );
  }
}

void main() {
  group('load', () {
    test('populates skills on success', () async {
      final repository = _FakeStudentSkillRepository()
        ..loadResult = [_skill(id: 1, skillName: 'AutoCAD')];
      final provider = StudentSkillProvider(
        repository: repository,
        authProvider: AuthProvider(authRepository: _FakeAuthRepository()),
      );

      await provider.load();

      expect(provider.skills, hasLength(1));
      expect(provider.skills.first.skillName, 'AutoCAD');
      expect(provider.isLoading, isFalse);
      expect(provider.errorMessage, isNull);
    });

    test('sets errorMessage on ApiException failure', () async {
      final repository = _FakeStudentSkillRepository()
        ..loadError = ApiException('Server error, please try again later.');
      final provider = StudentSkillProvider(
        repository: repository,
        authProvider: AuthProvider(authRepository: _FakeAuthRepository()),
      );

      await provider.load();

      expect(provider.skills, isEmpty);
      expect(provider.errorMessage, 'Server error, please try again later.');
    });

    test('concurrent calls share a single in-flight request', () async {
      final repository = _FakeStudentSkillRepository()
        ..loadResult = [_skill()]
        ..loadDelay = const Duration(milliseconds: 50);
      final provider = StudentSkillProvider(
        repository: repository,
        authProvider: AuthProvider(authRepository: _FakeAuthRepository()),
      );

      await Future.wait([provider.load(), provider.load()]);

      expect(repository.getStudentSkillsCallCount, 1);
    });

    test(
      'forceRefresh triggers a new request even if one already resolved',
      () async {
        final repository = _FakeStudentSkillRepository()
          ..loadResult = [_skill()];
        final provider = StudentSkillProvider(
          repository: repository,
          authProvider: AuthProvider(authRepository: _FakeAuthRepository()),
        );

        await provider.load();
        await provider.load(forceRefresh: true);

        expect(repository.getStudentSkillsCallCount, 2);
      },
    );
  });

  group('deleteSkill', () {
    test('removes the skill from the local list on success', () async {
      final repository = _FakeStudentSkillRepository()
        ..loadResult = [_skill(id: 1), _skill(id: 2, skillName: 'AutoCAD')];
      final provider = StudentSkillProvider(
        repository: repository,
        authProvider: AuthProvider(authRepository: _FakeAuthRepository()),
      );
      await provider.load();

      final success = await provider.deleteSkill(1);

      expect(success, isTrue);
      expect(repository.deletedIds, [1]);
      expect(provider.skills.map((s) => s.id), [2]);
    });

    test('a cv_ai skill is removable exactly like a manual skill', () async {
      final repository = _FakeStudentSkillRepository()
        ..loadResult = [_skill(id: 1, source: 'cv_ai')];
      final provider = StudentSkillProvider(
        repository: repository,
        authProvider: AuthProvider(authRepository: _FakeAuthRepository()),
      );
      await provider.load();

      final success = await provider.deleteSkill(1);

      expect(success, isTrue);
      expect(repository.deletedIds, [1]);
      expect(provider.skills, isEmpty);
    });

    test('keeps the skill and sets actionErrorMessage on failure', () async {
      final repository = _FakeStudentSkillRepository()
        ..loadResult = [_skill(id: 1)]
        ..deleteError = ApiException('Server error, please try again later.');
      final provider = StudentSkillProvider(
        repository: repository,
        authProvider: AuthProvider(authRepository: _FakeAuthRepository()),
      );
      await provider.load();

      final success = await provider.deleteSkill(1);

      expect(success, isFalse);
      expect(provider.skills, hasLength(1));
      expect(
        provider.actionErrorMessage,
        'Server error, please try again later.',
      );
    });

    test('a duplicate in-flight delete for the same id is ignored', () async {
      final repository = _FakeStudentSkillRepository()
        ..loadResult = [_skill(id: 1)]
        ..deleteDelay = const Duration(milliseconds: 50);
      final provider = StudentSkillProvider(
        repository: repository,
        authProvider: AuthProvider(authRepository: _FakeAuthRepository()),
      );
      await provider.load();

      final results = await Future.wait([
        provider.deleteSkill(1),
        provider.deleteSkill(1),
      ]);

      expect(repository.deletedIds, [1]);
      expect(results.where((success) => success), hasLength(1));
    });
  });

  group('loadCatalog (UI Phase 7.2)', () {
    test('populates catalogSkills on success', () async {
      final repository = _FakeStudentSkillRepository()
        ..catalogResult = const [
          SkillModel(id: 10, name: 'AutoCAD', category: 'Civil Engineering'),
          SkillModel(id: 11, name: 'Python'),
        ];
      final provider = StudentSkillProvider(
        repository: repository,
        authProvider: AuthProvider(authRepository: _FakeAuthRepository()),
      );

      await provider.loadCatalog();

      expect(provider.catalogSkills, hasLength(2));
      expect(provider.isLoadingCatalog, isFalse);
      expect(provider.catalogErrorMessage, isNull);
    });

    test('sets catalogErrorMessage on ApiException failure', () async {
      final repository = _FakeStudentSkillRepository()
        ..catalogError = ApiException('Server error, please try again later.');
      final provider = StudentSkillProvider(
        repository: repository,
        authProvider: AuthProvider(authRepository: _FakeAuthRepository()),
      );

      await provider.loadCatalog();

      expect(provider.catalogSkills, isEmpty);
      expect(
        provider.catalogErrorMessage,
        'Server error, please try again later.',
      );
    });

    test('concurrent calls share a single in-flight request', () async {
      final repository = _FakeStudentSkillRepository()
        ..catalogResult = const [SkillModel(id: 10, name: 'AutoCAD')]
        ..catalogDelay = const Duration(milliseconds: 50);
      final provider = StudentSkillProvider(
        repository: repository,
        authProvider: AuthProvider(authRepository: _FakeAuthRepository()),
      );

      await Future.wait([provider.loadCatalog(), provider.loadCatalog()]);

      expect(repository.getSkillCatalogCallCount, 1);
    });

    test('a second open reuses the cached catalog, no new request', () async {
      final repository = _FakeStudentSkillRepository()
        ..catalogResult = const [SkillModel(id: 10, name: 'AutoCAD')];
      final provider = StudentSkillProvider(
        repository: repository,
        authProvider: AuthProvider(authRepository: _FakeAuthRepository()),
      );

      await provider.loadCatalog();
      await provider.loadCatalog();

      expect(repository.getSkillCatalogCallCount, 1);
    });

    test('forceRefresh triggers a new request even if one already resolved', () async {
      final repository = _FakeStudentSkillRepository()
        ..catalogResult = const [SkillModel(id: 10, name: 'AutoCAD')];
      final provider = StudentSkillProvider(
        repository: repository,
        authProvider: AuthProvider(authRepository: _FakeAuthRepository()),
      );

      await provider.loadCatalog();
      await provider.loadCatalog(forceRefresh: true);

      expect(repository.getSkillCatalogCallCount, 2);
    });
  });

  group('addSkill (UI Phase 7.2 — real Manual Add Skill)', () {
    test('success appends the real, backend-returned skill to the list', () async {
      final repository = _FakeStudentSkillRepository()
        ..addResult = _skill(id: 5, skillId: 20, skillName: 'AutoCAD', level: 'expert');
      final provider = StudentSkillProvider(
        repository: repository,
        authProvider: AuthProvider(authRepository: _FakeAuthRepository()),
      );

      final success = await provider.addSkill(skillId: 20, level: 'expert');

      expect(success, isTrue);
      expect(repository.lastAddedSkillId, 20);
      expect(repository.lastAddedLevel, 'expert');
      expect(provider.skills, hasLength(1));
      expect(provider.skills.single.skillName, 'AutoCAD');
      expect(provider.skills.single.source, 'manual');
      expect(provider.isAddingSkill, isFalse);
      expect(provider.addErrorMessage, isNull);
    });

    test(
      'never adds a local placeholder before the backend actually confirms success',
      () async {
        final repository = _FakeStudentSkillRepository()
          ..addError = ApiException('You have already added this skill', statusCode: 409);
        final provider = StudentSkillProvider(
          repository: repository,
          authProvider: AuthProvider(authRepository: _FakeAuthRepository()),
        );

        final success = await provider.addSkill(skillId: 20, level: 'expert');

        expect(success, isFalse);
        expect(provider.skills, isEmpty);
        expect(provider.addErrorMessage, 'You have already added this skill');
      },
    );

    test('an unexpected (non-ApiException) failure exposes a safe message', () async {
      final repository = _FakeStudentSkillRepository()..addRuntimeError = TypeError();
      final provider = StudentSkillProvider(
        repository: repository,
        authProvider: AuthProvider(authRepository: _FakeAuthRepository()),
      );

      final success = await provider.addSkill(skillId: 1, level: 'beginner');

      expect(success, isFalse);
      expect(provider.addErrorMessage, isNotNull);
      expect(provider.addErrorMessage, isNot(contains('TypeError')));
      expect(provider.skills, isEmpty);
    });

    test('isAddingSkill is true only while the request is in flight', () async {
      final repository = _FakeStudentSkillRepository()
        ..addDelay = const Duration(milliseconds: 50);
      final provider = StudentSkillProvider(
        repository: repository,
        authProvider: AuthProvider(authRepository: _FakeAuthRepository()),
      );

      expect(provider.isAddingSkill, isFalse);
      final future = provider.addSkill(skillId: 1, level: 'beginner');
      expect(provider.isAddingSkill, isTrue);

      await future;
      expect(provider.isAddingSkill, isFalse);
    });

    test('a duplicate in-flight add is ignored, only one request sent', () async {
      final repository = _FakeStudentSkillRepository()
        ..addDelay = const Duration(milliseconds: 50);
      final provider = StudentSkillProvider(
        repository: repository,
        authProvider: AuthProvider(authRepository: _FakeAuthRepository()),
      );

      final results = await Future.wait([
        provider.addSkill(skillId: 1, level: 'beginner'),
        provider.addSkill(skillId: 1, level: 'beginner'),
      ]);

      expect(repository.addSkillCallCount, 1);
      expect(results.where((success) => success), hasLength(1));
    });
  });

  test('reset() clears state and is called on logout', () async {
    final repository = _FakeStudentSkillRepository()
      ..loadResult = [_skill()]
      ..catalogResult = const [SkillModel(id: 10, name: 'AutoCAD')];
    final authProvider = AuthProvider(authRepository: _FakeAuthRepository());
    final provider = StudentSkillProvider(
      repository: repository,
      authProvider: authProvider,
    );

    await provider.load();
    await provider.loadCatalog();
    expect(provider.skills, hasLength(1));
    expect(provider.catalogSkills, hasLength(1));

    await authProvider.logout();

    expect(provider.skills, isEmpty);
    expect(provider.isLoading, isFalse);
    expect(provider.errorMessage, isNull);
    expect(provider.actionErrorMessage, isNull);
    expect(provider.busySkillIds, isEmpty);
    expect(provider.catalogSkills, isEmpty);
    expect(provider.isLoadingCatalog, isFalse);
    expect(provider.catalogErrorMessage, isNull);
    expect(provider.isAddingSkill, isFalse);
    expect(provider.addErrorMessage, isNull);
  });
}
