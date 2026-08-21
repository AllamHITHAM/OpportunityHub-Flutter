// Direct unit tests for AdminSkillSuggestionsProvider, using a fake
// repository (no real network) and a real AuthProvider (with a fake
// AuthRepository) so the reset-on-logout listener can be exercised
// genuinely. Mirrors student_skill_provider_test.dart's own conventions.

import 'package:flutter_test/flutter_test.dart';

import 'package:opportunityhub_flutter/core/api/api_client.dart';
import 'package:opportunityhub_flutter/core/storage/token_storage_service.dart';
import 'package:opportunityhub_flutter/features/admin/data/admin_skill_suggestions_repository.dart';
import 'package:opportunityhub_flutter/features/auth/data/auth_repository.dart';
import 'package:opportunityhub_flutter/models/skill_suggestion_model.dart';
import 'package:opportunityhub_flutter/providers/admin_skill_suggestions_provider.dart';
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
    // A no-op -- this test only cares that AuthProvider.logout() flips
    // `isAuthenticated` to false, not the real network/secure-storage calls.
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

void main() {
  group('load', () {
    test('populates suggestions on success', () async {
      final repository = _FakeAdminSkillSuggestionsRepository()
        ..loadResult = [_suggestion(id: 1, name: 'Primavera P6')];
      final provider = AdminSkillSuggestionsProvider(
        repository: repository,
        authProvider: AuthProvider(authRepository: _FakeAuthRepository()),
      );

      await provider.load();

      expect(provider.suggestions, hasLength(1));
      expect(provider.suggestions.first.name, 'Primavera P6');
      expect(provider.isLoading, isFalse);
      expect(provider.errorMessage, isNull);
    });

    test('sets errorMessage on ApiException failure', () async {
      final repository = _FakeAdminSkillSuggestionsRepository()
        ..loadError = ApiException('Server error, please try again later.');
      final provider = AdminSkillSuggestionsProvider(
        repository: repository,
        authProvider: AuthProvider(authRepository: _FakeAuthRepository()),
      );

      await provider.load();

      expect(provider.suggestions, isEmpty);
      expect(provider.errorMessage, 'Server error, please try again later.');
    });

    test('concurrent calls share a single in-flight request', () async {
      final repository = _FakeAdminSkillSuggestionsRepository()
        ..loadResult = [_suggestion()]
        ..loadDelay = const Duration(milliseconds: 50);
      final provider = AdminSkillSuggestionsProvider(
        repository: repository,
        authProvider: AuthProvider(authRepository: _FakeAuthRepository()),
      );

      await Future.wait([provider.load(), provider.load()]);

      expect(repository.getPendingSuggestionsCallCount, 1);
    });
  });

  group('approve', () {
    test('removes the suggestion from the local list on success', () async {
      final repository = _FakeAdminSkillSuggestionsRepository()
        ..loadResult = [
          _suggestion(id: 1),
          _suggestion(id: 2, name: 'AutoCAD'),
        ];
      final provider = AdminSkillSuggestionsProvider(
        repository: repository,
        authProvider: AuthProvider(authRepository: _FakeAuthRepository()),
      );
      await provider.load();

      final success = await provider.approve(1);

      expect(success, isTrue);
      expect(repository.approvedIds, [1]);
      expect(provider.suggestions.map((s) => s.id), [2]);
    });

    test(
      'keeps the suggestion and sets actionErrorMessage on failure',
      () async {
        final repository = _FakeAdminSkillSuggestionsRepository()
          ..loadResult = [_suggestion(id: 1)]
          ..approveError = ApiException(
            'This suggestion has already been reviewed.',
            statusCode: 409,
          );
        final provider = AdminSkillSuggestionsProvider(
          repository: repository,
          authProvider: AuthProvider(authRepository: _FakeAuthRepository()),
        );
        await provider.load();

        final success = await provider.approve(1);

        expect(success, isFalse);
        expect(provider.suggestions, hasLength(1));
        expect(
          provider.actionErrorMessage,
          'This suggestion has already been reviewed.',
        );
      },
    );

    test('a duplicate in-flight approve for the same id is ignored', () async {
      final repository = _FakeAdminSkillSuggestionsRepository()
        ..loadResult = [_suggestion(id: 1)]
        ..approveDelay = const Duration(milliseconds: 50);
      final provider = AdminSkillSuggestionsProvider(
        repository: repository,
        authProvider: AuthProvider(authRepository: _FakeAuthRepository()),
      );
      await provider.load();

      final results = await Future.wait([
        provider.approve(1),
        provider.approve(1),
      ]);

      expect(repository.approvedIds, [1]);
      expect(results.where((success) => success), hasLength(1));
    });
  });

  group('reject', () {
    test('removes the suggestion from the local list on success', () async {
      final repository = _FakeAdminSkillSuggestionsRepository()
        ..loadResult = [_suggestion(id: 1)];
      final provider = AdminSkillSuggestionsProvider(
        repository: repository,
        authProvider: AuthProvider(authRepository: _FakeAuthRepository()),
      );
      await provider.load();

      final success = await provider.reject(1);

      expect(success, isTrue);
      expect(repository.rejectedIds, [1]);
      expect(provider.suggestions, isEmpty);
    });

    test(
      'keeps the suggestion and sets actionErrorMessage on failure',
      () async {
        final repository = _FakeAdminSkillSuggestionsRepository()
          ..loadResult = [_suggestion(id: 1)]
          ..rejectError = ApiException(
            'Something went wrong.',
            statusCode: 500,
          );
        final provider = AdminSkillSuggestionsProvider(
          repository: repository,
          authProvider: AuthProvider(authRepository: _FakeAuthRepository()),
        );
        await provider.load();

        final success = await provider.reject(1);

        expect(success, isFalse);
        expect(provider.suggestions, hasLength(1));
        expect(provider.actionErrorMessage, isNotNull);
      },
    );
  });

  test('reset() clears state and is called on logout', () async {
    final repository = _FakeAdminSkillSuggestionsRepository()
      ..loadResult = [_suggestion(id: 1)];
    final authProvider = AuthProvider(authRepository: _FakeAuthRepository());
    final provider = AdminSkillSuggestionsProvider(
      repository: repository,
      authProvider: authProvider,
    );

    await provider.load();
    expect(provider.suggestions, hasLength(1));

    await authProvider.logout();

    expect(provider.suggestions, isEmpty);
    expect(provider.isLoading, isFalse);
    expect(provider.errorMessage, isNull);
    expect(provider.actionErrorMessage, isNull);
    expect(provider.busySuggestionIds, isEmpty);
  });
}
