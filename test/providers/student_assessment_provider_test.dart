// Direct unit tests for StudentAssessmentProvider, using a fake repository
// (no real network) and a real AuthProvider (with a fake AuthRepository) so
// the reset-on-logout listener can be exercised genuinely. Mirrors
// organization_assessment_provider_test.dart's structure and conventions,
// minus everything write-related (this provider is read-only).

import 'package:flutter_test/flutter_test.dart';

import 'package:opportunityhub_flutter/core/api/api_client.dart';
import 'package:opportunityhub_flutter/core/storage/token_storage_service.dart';
import 'package:opportunityhub_flutter/features/assessments/data/assessment_repository.dart';
import 'package:opportunityhub_flutter/features/auth/data/auth_repository.dart';
import 'package:opportunityhub_flutter/models/assessment_model.dart';
import 'package:opportunityhub_flutter/providers/auth_provider.dart';
import 'package:opportunityhub_flutter/providers/student_assessment_provider.dart';

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

AssessmentModel _assessment({int id = 1, int applicationId = 5}) {
  return AssessmentModel(
    id: id,
    applicationId: applicationId,
    type: 'interview',
    status: 'scheduled',
  );
}

class _FakeAssessmentRepository extends AssessmentRepository {
  _FakeAssessmentRepository()
    : super(apiClient: ApiClient(tokenStorageService: TokenStorageService()));

  AssessmentModel? loadResult;

  /// Phase 10A.3 — set this instead of [loadResult] to return a full,
  /// multi-element history in one response. Takes priority over both
  /// [loadResult] and [resultsByApplication] when non-null.
  List<AssessmentModel>? historyResult;
  ApiException? loadError;
  Object? loadRuntimeError;
  int getStudentAssessmentForApplicationCallCount = 0;
  final List<int> requestedApplicationIds = [];

  /// Per-application overrides — when set for a given ID, take priority
  /// over the single [loadResult]/no-delay defaults. Lets a test give two
  /// different applications two different results and/or delays, to
  /// exercise the stale-response-must-not-win scenario.
  Map<int, AssessmentModel?>? resultsByApplication;
  Map<int, Duration>? delaysByApplication;

  @override
  Future<List<AssessmentModel>> getStudentAssessmentsForApplication(
    int applicationId,
  ) async {
    getStudentAssessmentForApplicationCallCount++;
    requestedApplicationIds.add(applicationId);

    final delay = delaysByApplication?[applicationId] ?? Duration.zero;
    if (delay > Duration.zero) {
      await Future<void>.delayed(delay);
    }
    if (loadRuntimeError != null) throw loadRuntimeError!;
    if (loadError != null) throw loadError!;
    if (historyResult != null) return historyResult!;
    if (resultsByApplication != null) {
      final result = resultsByApplication![applicationId];
      return result == null ? [] : [result];
    }
    return loadResult == null ? [] : [loadResult!];
  }
}

void main() {
  late AuthProvider authProvider;
  late _FakeAssessmentRepository repository;
  late StudentAssessmentProvider provider;

  setUp(() {
    authProvider = AuthProvider(authRepository: _FakeAuthRepository());
    repository = _FakeAssessmentRepository();
    provider = StudentAssessmentProvider(
      repository: repository,
      authProvider: authProvider,
    );
  });

  test('initial state is empty and idle', () {
    expect(provider.latestAssessment, isNull);
    expect(provider.loadedApplicationId, isNull);
    expect(provider.isLoading, isFalse);
    expect(provider.errorMessage, isNull);
  });

  test('loading an existing assessment populates state', () async {
    repository.loadResult = _assessment(applicationId: 5);

    await provider.loadForApplication(5);

    expect(provider.latestAssessment, isNotNull);
    expect(provider.latestAssessment!.applicationId, 5);
    expect(provider.loadedApplicationId, 5);
    expect(provider.isLoading, isFalse);
    expect(provider.errorMessage, isNull);
    expect(provider.hasAssessmentFor(5), isTrue);
  });

  test(
    'loading with no assessment is represented correctly, not as an error',
    () async {
      await provider.loadForApplication(5);

      expect(provider.latestAssessment, isNull);
      expect(provider.errorMessage, isNull);
      expect(provider.hasAssessmentFor(5), isFalse);
    },
  );

  test('load failure surfaces the error and is retryable', () async {
    repository.loadError = ApiException('Something went wrong.');

    await provider.loadForApplication(5);

    expect(provider.errorMessage, 'Something went wrong.');
    expect(provider.latestAssessment, isNull);

    repository.loadError = null;
    repository.loadResult = _assessment(applicationId: 5);
    await provider.loadForApplication(5, forceRefresh: true);

    expect(provider.errorMessage, isNull);
    expect(provider.latestAssessment, isNotNull);
  });

  test('an unexpected parsing/runtime error exposes a safe message and never '
      'leaves the provider stuck loading', () async {
    repository.loadRuntimeError = TypeError();

    await provider.loadForApplication(5);

    expect(provider.isLoading, isFalse);
    expect(provider.errorMessage, isNotNull);
    expect(provider.errorMessage, isNot(contains('TypeError')));
    expect(provider.errorMessage, 'Something went wrong. Please try again.');
  });

  test(
    'concurrent duplicate loads for the same application are prevented',
    () async {
      repository.loadResult = _assessment(applicationId: 5);
      repository.delaysByApplication = {5: const Duration(milliseconds: 50)};

      final first = provider.loadForApplication(5);
      final second = provider.loadForApplication(5);
      await Future.wait([first, second]);

      expect(repository.getStudentAssessmentForApplicationCallCount, 1);
    },
  );

  test('forceRefresh starts a new fetch even while unchanged', () async {
    await provider.loadForApplication(5);
    await provider.loadForApplication(5, forceRefresh: true);

    expect(repository.getStudentAssessmentForApplicationCallCount, 2);
  });

  test("loading application 5 then application 9 loads application 9 "
      "correctly, not application 5's in-flight future", () async {
    repository.delaysByApplication = {5: const Duration(milliseconds: 100)};
    repository.resultsByApplication = {
      5: _assessment(id: 1, applicationId: 5),
      9: _assessment(id: 2, applicationId: 9),
    };

    final firstCall = provider.loadForApplication(5);
    final secondCall = provider.loadForApplication(9);
    await Future.wait([firstCall, secondCall]);

    expect(provider.latestAssessment?.applicationId, 9);
    expect(provider.loadedApplicationId, 9);
    expect(repository.requestedApplicationIds, containsAll([5, 9]));
  });

  test('a slower stale response for application 5 cannot overwrite the newer '
      'application 9 state', () async {
    repository.resultsByApplication = {
      9: _assessment(id: 9, applicationId: 9),
      5: _assessment(id: 5, applicationId: 5),
    };

    await provider.loadForApplication(9);
    expect(provider.latestAssessment?.applicationId, 9);

    repository.delaysByApplication = {5: const Duration(milliseconds: 100)};
    final staleCall = provider.loadForApplication(5);

    // Switch back to application 9 before the stale application-5
    // response arrives.
    await provider.loadForApplication(9, forceRefresh: true);
    expect(provider.latestAssessment?.applicationId, 9);

    await staleCall;

    expect(provider.latestAssessment?.applicationId, 9);
    expect(provider.loadedApplicationId, 9);
  });

  test('a stale forceRefresh for the same application cannot overwrite a '
      'newer forceRefresh — the newest request always wins', () async {
    repository.resultsByApplication = {5: _assessment(id: 1, applicationId: 5)};
    repository.delaysByApplication = {5: const Duration(milliseconds: 100)};
    final staleCall = provider.loadForApplication(5, forceRefresh: true);

    repository.resultsByApplication = {5: _assessment(id: 2, applicationId: 5)};
    repository.delaysByApplication = {5: Duration.zero};
    await provider.loadForApplication(5, forceRefresh: true);

    expect(provider.latestAssessment?.id, 2);

    await staleCall;

    expect(provider.latestAssessment?.id, 2);
  });

  test('a refresh failure for the same application retains the previously '
      'loaded assessment', () async {
    repository.loadResult = _assessment(id: 1, applicationId: 5);
    await provider.loadForApplication(5);
    expect(provider.latestAssessment?.id, 1);

    repository.loadResult = null;
    repository.loadError = ApiException('Server error, please retry.');
    await provider.loadForApplication(5, forceRefresh: true);

    expect(provider.latestAssessment?.id, 1);
    expect(provider.errorMessage, 'Server error, please retry.');
  });

  test('hasAssessmentFor is false for a different application', () async {
    repository.loadResult = _assessment(applicationId: 5);
    await provider.loadForApplication(5);

    expect(provider.hasAssessmentFor(5), isTrue);
    expect(provider.hasAssessmentFor(9), isFalse);
  });

  test('reset clears all state', () async {
    repository.loadResult = _assessment(applicationId: 5);
    await provider.loadForApplication(5);
    expect(provider.latestAssessment, isNotNull);

    provider.reset();

    expect(provider.latestAssessment, isNull);
    expect(provider.loadedApplicationId, isNull);
    expect(provider.isLoading, isFalse);
    expect(provider.errorMessage, isNull);
  });

  test('reset clears state on logout', () async {
    repository.loadResult = _assessment(applicationId: 5);
    await provider.loadForApplication(5);
    expect(provider.latestAssessment, isNotNull);

    await authProvider.logout();

    expect(provider.latestAssessment, isNull);
    expect(provider.loadedApplicationId, isNull);
    expect(provider.errorMessage, isNull);
  });

  test('reset invalidates a load still in flight', () async {
    repository.loadResult = _assessment(id: 1, applicationId: 5);
    repository.delaysByApplication = {5: const Duration(milliseconds: 50)};
    final staleLoad = provider.loadForApplication(5);

    provider.reset();
    await staleLoad;

    // The stale response must not repopulate state after reset.
    expect(provider.latestAssessment, isNull);
    expect(provider.loadedApplicationId, isNull);
  });

  test(
    'dispose removes the AuthProvider listener (no error on logout after dispose)',
    () async {
      provider.dispose();

      await expectLater(authProvider.logout(), completes);
    },
  );

  group('Assessment history (Phase 10A.3)', () {
    test('assessments holds the full history; latestAssessment is the last '
        'element', () async {
      final quizAssessment = AssessmentModel(
        id: 1,
        applicationId: 5,
        type: 'quiz',
        status: 'completed',
        result: 'passed',
      );
      final interviewAssessment = _assessment(id: 2, applicationId: 5);
      repository.historyResult = [quizAssessment, interviewAssessment];

      await provider.loadForApplication(5);

      expect(provider.assessments, hasLength(2));
      expect(provider.assessments.first.id, 1);
      expect(provider.latestAssessment?.id, 2);
      expect(provider.latestAssessment?.type, 'interview');
    });
  });
}
