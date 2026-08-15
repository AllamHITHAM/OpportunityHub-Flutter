// Direct unit tests for OrganizationMatchAnalysisProvider, using a fake
// repository (no real network) and a real AuthProvider (with a fake
// AuthRepository) so the reset-on-logout listener can be exercised
// genuinely. Mirrors organization_offer_provider_test.dart's structure and
// conventions.

import 'package:flutter_test/flutter_test.dart';

import 'package:opportunityhub_flutter/core/api/api_client.dart';
import 'package:opportunityhub_flutter/core/storage/token_storage_service.dart';
import 'package:opportunityhub_flutter/features/applications/data/application_repository.dart';
import 'package:opportunityhub_flutter/features/auth/data/auth_repository.dart';
import 'package:opportunityhub_flutter/models/match_analysis_model.dart';
import 'package:opportunityhub_flutter/providers/auth_provider.dart';
import 'package:opportunityhub_flutter/providers/organization_match_analysis_provider.dart';

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
    // `isAuthenticated` to false, not the real network/secure-storage
    // calls that would otherwise require a platform-channel binding.
  }
}

MatchAnalysisModel _analysis({
  double overallMatchScore = 87,
  double? skillsMatchScore = 90,
  double? fieldMatchScore = 100,
  double? experienceMatchScore = 66.67,
}) {
  return MatchAnalysisModel(
    overallMatchScore: overallMatchScore,
    skillsMatchScore: skillsMatchScore,
    fieldMatchScore: fieldMatchScore,
    experienceMatchScore: experienceMatchScore,
    strengths: const ['Matches required skill: Laravel'],
    weaknesses: const ['Missing preferred skill: Docker'],
    recommendation: 'Strong candidate, recommended for interview.',
  );
}

class _FakeApplicationRepository extends ApplicationRepository {
  _FakeApplicationRepository()
    : super(apiClient: ApiClient(tokenStorageService: TokenStorageService()));

  ApiException? loadError;
  Object? loadRuntimeError;
  int getAnalysisCallCount = 0;
  final List<int> requestedApplicationIds = [];

  /// Per-application overrides — when set for a given ID, take priority
  /// over the single [loadResult]/no-delay defaults. Lets a test give two
  /// different applications two different results and/or delays, to
  /// exercise the stale-response-must-not-win scenario.
  Map<int, MatchAnalysisModel?>? resultsByApplication;
  Map<int, Duration>? delaysByApplication;
  MatchAnalysisModel? loadResult;

  MatchAnalysisModel? recalculateResult;
  ApiException? recalculateError;
  Object? recalculateRuntimeError;
  Duration recalculateDelay = Duration.zero;
  int recalculateCallCount = 0;

  @override
  Future<MatchAnalysisModel> getApplicationAnalysis(int applicationId) async {
    getAnalysisCallCount++;
    requestedApplicationIds.add(applicationId);

    final delay = delaysByApplication?[applicationId] ?? Duration.zero;
    if (delay > Duration.zero) {
      await Future<void>.delayed(delay);
    }
    if (loadRuntimeError != null) throw loadRuntimeError!;
    if (loadError != null) throw loadError!;

    final MatchAnalysisModel? result;
    if (resultsByApplication != null) {
      result = resultsByApplication![applicationId];
    } else {
      result = loadResult;
    }
    if (result == null) {
      throw ApiException('Application analysis not found', statusCode: 404);
    }
    return result;
  }

  @override
  Future<MatchAnalysisModel> analyzeApplication(int applicationId) async {
    recalculateCallCount++;
    if (recalculateDelay > Duration.zero) {
      await Future<void>.delayed(recalculateDelay);
    }
    if (recalculateRuntimeError != null) throw recalculateRuntimeError!;
    if (recalculateError != null) throw recalculateError!;
    return recalculateResult ?? _analysis();
  }
}

void main() {
  late AuthProvider authProvider;
  late _FakeApplicationRepository repository;
  late OrganizationMatchAnalysisProvider provider;

  setUp(() {
    authProvider = AuthProvider(authRepository: _FakeAuthRepository());
    repository = _FakeApplicationRepository();
    provider = OrganizationMatchAnalysisProvider(
      repository: repository,
      authProvider: authProvider,
    );
  });

  test('initial state is empty and idle', () {
    expect(provider.analysis, isNull);
    expect(provider.loadedApplicationId, isNull);
    expect(provider.isLoading, isFalse);
    expect(provider.isRecalculating, isFalse);
    expect(provider.errorMessage, isNull);
    expect(provider.actionErrorMessage, isNull);
  });

  test('loading an existing analysis populates state', () async {
    repository.loadResult = _analysis(overallMatchScore: 72);

    await provider.loadForApplication(5);

    expect(provider.analysis, isNotNull);
    expect(provider.analysis!.overallMatchScore, 72);
    expect(provider.loadedApplicationId, 5);
    expect(provider.isLoading, isFalse);
    expect(provider.errorMessage, isNull);
    expect(provider.hasAnalysisFor(5), isTrue);
  });

  test(
    'a 404 (never analyzed yet) is represented correctly, not as an error',
    () async {
      await provider.loadForApplication(5);

      expect(provider.analysis, isNull);
      expect(provider.errorMessage, isNull);
      expect(provider.hasAnalysisFor(5), isFalse);
    },
  );

  test('a non-404 load failure surfaces the error and is retryable', () async {
    repository.loadError = ApiException(
      'Application not found',
      statusCode: 403,
    );

    await provider.loadForApplication(5);

    expect(provider.errorMessage, 'Application not found');
    expect(provider.analysis, isNull);

    repository.loadError = null;
    repository.loadResult = _analysis();
    await provider.loadForApplication(5, forceRefresh: true);

    expect(provider.errorMessage, isNull);
    expect(provider.analysis, isNotNull);
  });

  test('malformed load data never leaves the provider stuck loading', () async {
    repository.loadRuntimeError = TypeError();

    await provider.loadForApplication(5);

    expect(provider.isLoading, isFalse);
    expect(provider.errorMessage, isNotNull);
    expect(provider.errorMessage, isNot(contains('TypeError')));
  });

  test('forceRefresh starts a new fetch even while unchanged', () async {
    repository.loadResult = _analysis();

    await provider.loadForApplication(5);
    await provider.loadForApplication(5, forceRefresh: true);

    expect(repository.getAnalysisCallCount, 2);
  });

  test(
    'concurrent duplicate loads for the same application are prevented',
    () async {
      repository.loadResult = _analysis();

      final first = provider.loadForApplication(5);
      final second = provider.loadForApplication(5);
      await Future.wait([first, second]);

      expect(repository.getAnalysisCallCount, 1);
    },
  );

  test(
    'loading application 5 then application 9 loads application 9 correctly, not application 5\'s in-flight future',
    () async {
      repository.delaysByApplication = {5: const Duration(milliseconds: 100)};
      repository.resultsByApplication = {
        5: _analysis(overallMatchScore: 10),
        9: _analysis(overallMatchScore: 90),
      };

      final firstCall = provider.loadForApplication(5);
      final secondCall = provider.loadForApplication(9);
      await Future.wait([firstCall, secondCall]);

      expect(provider.analysis?.overallMatchScore, 90);
      expect(provider.loadedApplicationId, 9);
      expect(repository.requestedApplicationIds, containsAll([5, 9]));
    },
  );

  test(
    'a slower stale response for application 5 cannot overwrite the newer application 9 state',
    () async {
      repository.resultsByApplication = {
        9: _analysis(overallMatchScore: 9),
        5: _analysis(overallMatchScore: 5),
      };

      await provider.loadForApplication(9);
      expect(provider.analysis?.overallMatchScore, 9);

      repository.delaysByApplication = {5: const Duration(milliseconds: 100)};
      final staleCall = provider.loadForApplication(5);

      // Switch back to application 9 before the stale application-5
      // response arrives.
      await provider.loadForApplication(9, forceRefresh: true);
      expect(provider.analysis?.overallMatchScore, 9);

      await staleCall;

      expect(provider.analysis?.overallMatchScore, 9);
      expect(provider.loadedApplicationId, 9);
    },
  );

  test(
    'recalculate success replaces the analysis and sets loadedApplicationId',
    () async {
      repository.recalculateResult = _analysis(overallMatchScore: 95);

      final success = await provider.recalculate(5);

      expect(success, isTrue);
      expect(provider.analysis, isNotNull);
      expect(provider.analysis!.overallMatchScore, 95);
      expect(provider.loadedApplicationId, 5);
      expect(provider.actionErrorMessage, isNull);
    },
  );

  test('recalculate failure preserves the previous analysis', () async {
    repository.loadResult = _analysis(overallMatchScore: 60);
    await provider.loadForApplication(5);

    repository.recalculateError = ApiException('Server error.');
    final success = await provider.recalculate(5);

    expect(success, isFalse);
    expect(provider.analysis, isNotNull);
    expect(provider.analysis!.overallMatchScore, 60);
    expect(provider.actionErrorMessage, 'Server error.');
  });

  test('recalculate unexpected failure exposes a safe message', () async {
    repository.recalculateRuntimeError = TypeError();

    final success = await provider.recalculate(5);

    expect(success, isFalse);
    expect(provider.actionErrorMessage, isNotNull);
    expect(provider.actionErrorMessage, isNot(contains('TypeError')));
    expect(
      provider.actionErrorMessage,
      'Something went wrong. Please try again.',
    );
  });

  test('a duplicate recalculate submission is blocked', () async {
    repository.recalculateDelay = const Duration(milliseconds: 50);
    repository.recalculateResult = _analysis();

    final first = provider.recalculate(5);
    final second = provider.recalculate(5);

    final results = await Future.wait([first, second]);

    expect(repository.recalculateCallCount, 1);
    expect(results.where((success) => success).length, 1);
    expect(results.where((success) => !success).length, 1);
  });

  test('clearActionError clears only the action error', () async {
    repository.recalculateError = ApiException('Server error.');
    await provider.recalculate(5);
    expect(provider.actionErrorMessage, isNotNull);

    provider.clearActionError();

    expect(provider.actionErrorMessage, isNull);
  });

  test('reset clears all state (called on logout)', () async {
    repository.loadResult = _analysis();
    await provider.loadForApplication(5);
    expect(provider.analysis, isNotNull);

    await authProvider.logout();

    expect(provider.analysis, isNull);
    expect(provider.loadedApplicationId, isNull);
    expect(provider.isLoading, isFalse);
    expect(provider.errorMessage, isNull);
    expect(provider.isRecalculating, isFalse);
    expect(provider.actionErrorMessage, isNull);
  });

  test(
    'dispose removes the AuthProvider listener (no error on logout after dispose)',
    () async {
      provider.dispose();

      await expectLater(authProvider.logout(), completes);
    },
  );
}
