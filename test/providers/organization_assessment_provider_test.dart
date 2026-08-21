// Direct unit tests for OrganizationAssessmentProvider, using a fake
// repository (no real network) and a real AuthProvider (with a fake
// AuthRepository) so the reset-on-logout listener can be exercised
// genuinely. Mirrors organization_applications_provider_test.dart's
// structure and conventions.

import 'package:flutter_test/flutter_test.dart';

import 'package:opportunityhub_flutter/core/api/api_client.dart';
import 'package:opportunityhub_flutter/core/storage/token_storage_service.dart';
import 'package:opportunityhub_flutter/features/assessments/data/assessment_repository.dart';
import 'package:opportunityhub_flutter/features/assessments/data/interview_create_input.dart';
import 'package:opportunityhub_flutter/features/assessments/data/quiz_create_input.dart';
import 'package:opportunityhub_flutter/features/auth/data/auth_repository.dart';
import 'package:opportunityhub_flutter/models/assessment_model.dart';
import 'package:opportunityhub_flutter/models/interview_model.dart';
import 'package:opportunityhub_flutter/providers/auth_provider.dart';
import 'package:opportunityhub_flutter/providers/organization_assessment_provider.dart';

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

InterviewCreateInput _validInput() {
  return InterviewCreateInput(
    interviewType: 'online',
    scheduledAt: DateTime(2026, 8, 10, 10),
    meetingLink: 'https://meet.example.com/room',
  );
}

QuizCreateInput _validQuizInput() {
  return const QuizCreateInput(title: 'Backend Fundamentals', passingScore: 70);
}

AssessmentModel _quizAssessment({int id = 1, int applicationId = 5}) {
  return AssessmentModel(
    id: id,
    applicationId: applicationId,
    type: 'quiz',
    status: 'pending',
  );
}

InterviewModel _completedInterview({
  int id = 1,
  int assessmentId = 1,
  String? decision = 'passed',
}) {
  return InterviewModel(
    id: id,
    assessmentId: assessmentId,
    interviewType: 'online',
    status: 'completed',
    decision: decision,
    completedAt: DateTime(2026, 8, 15, 11),
  );
}

/// The refreshed [AssessmentModel] `completeInterview()` reads back via
/// [OrganizationAssessmentProvider.loadForApplication] after a successful
/// completion — its own nested `interview` reflects the completed state.
AssessmentModel _completedAssessment({
  int id = 1,
  int applicationId = 5,
  String? result = 'passed',
}) {
  return AssessmentModel(
    id: id,
    applicationId: applicationId,
    type: 'interview',
    status: 'completed',
    result: result,
    interview: _completedInterview(assessmentId: id, decision: result),
  );
}

class _FakeAssessmentRepository extends AssessmentRepository {
  _FakeAssessmentRepository()
    : super(apiClient: ApiClient(tokenStorageService: TokenStorageService()));

  AssessmentModel? loadResult;
  ApiException? loadError;
  Object? loadRuntimeError;
  int getAssessmentCallCount = 0;
  final List<int> requestedApplicationIds = [];

  /// Per-application overrides — when set for a given ID, take priority
  /// over the single [loadResult]/no-delay defaults. Lets a test give two
  /// different applications two different results and/or delays, to
  /// exercise the stale-response-must-not-win scenario.
  Map<int, AssessmentModel?>? resultsByApplication;
  Map<int, Duration>? delaysByApplication;

  AssessmentModel? createResult;
  ApiException? createError;
  Object? createRuntimeError;
  Duration createDelay = Duration.zero;
  int createCallCount = 0;
  String? lastCreateType;
  InterviewCreateInput? lastInterviewInput;
  QuizCreateInput? lastQuizInput;

  @override
  Future<AssessmentModel?> getAssessmentForApplication(
    int applicationId,
  ) async {
    getAssessmentCallCount++;
    requestedApplicationIds.add(applicationId);

    final delay = delaysByApplication?[applicationId] ?? Duration.zero;
    if (delay > Duration.zero) {
      await Future<void>.delayed(delay);
    }
    if (loadRuntimeError != null) throw loadRuntimeError!;
    if (loadError != null) throw loadError!;
    if (resultsByApplication != null) {
      return resultsByApplication![applicationId];
    }
    return loadResult;
  }

  @override
  Future<AssessmentModel> createAssessment({
    required int applicationId,
    required String type,
    InterviewCreateInput? interviewInput,
    QuizCreateInput? quizInput,
  }) async {
    createCallCount++;
    lastCreateType = type;
    lastInterviewInput = interviewInput;
    lastQuizInput = quizInput;
    if (createDelay > Duration.zero) {
      await Future<void>.delayed(createDelay);
    }
    if (createRuntimeError != null) throw createRuntimeError!;
    if (createError != null) throw createError!;
    return createResult!;
  }

  InterviewModel? completeResult;
  ApiException? completeError;
  Object? completeRuntimeError;
  Duration completeDelay = Duration.zero;
  int completeCallCount = 0;
  int? lastCompleteInterviewId;
  String? lastCompleteDecision;
  int? lastCompleteRating;
  String? lastCompleteCompanyFeedback;

  @override
  Future<InterviewModel> completeInterview({
    required int interviewId,
    String? decision,
    int? rating,
    String? companyFeedback,
  }) async {
    completeCallCount++;
    lastCompleteInterviewId = interviewId;
    lastCompleteDecision = decision;
    lastCompleteRating = rating;
    lastCompleteCompanyFeedback = companyFeedback;
    if (completeDelay > Duration.zero) {
      await Future<void>.delayed(completeDelay);
    }
    if (completeRuntimeError != null) throw completeRuntimeError!;
    if (completeError != null) throw completeError!;
    return completeResult!;
  }
}

void main() {
  late AuthProvider authProvider;
  late _FakeAssessmentRepository repository;
  late OrganizationAssessmentProvider provider;

  setUp(() {
    authProvider = AuthProvider(authRepository: _FakeAuthRepository());
    repository = _FakeAssessmentRepository();
    provider = OrganizationAssessmentProvider(
      repository: repository,
      authProvider: authProvider,
    );
  });

  test('initial state is empty and idle', () {
    expect(provider.assessment, isNull);
    expect(provider.loadedApplicationId, isNull);
    expect(provider.isLoading, isFalse);
    expect(provider.errorMessage, isNull);
    expect(provider.isCreating, isFalse);
    expect(provider.actionErrorMessage, isNull);
    expect(provider.fieldErrors, isEmpty);
    expect(provider.busyApplicationIds, isEmpty);
    expect(provider.completingInterviewIds, isEmpty);
  });

  test('loading an existing assessment populates state', () async {
    repository.loadResult = _assessment(applicationId: 5);

    await provider.loadForApplication(5);

    expect(provider.assessment, isNotNull);
    expect(provider.assessment!.applicationId, 5);
    expect(provider.loadedApplicationId, 5);
    expect(provider.isLoading, isFalse);
    expect(provider.errorMessage, isNull);
    expect(provider.hasAssessmentFor(5), isTrue);
  });

  test(
    'loading with no assessment is represented correctly, not as an error',
    () async {
      await provider.loadForApplication(5);

      expect(provider.assessment, isNull);
      expect(provider.errorMessage, isNull);
      expect(provider.hasAssessmentFor(5), isFalse);
    },
  );

  test('load failure surfaces the error and is retryable', () async {
    repository.loadError = ApiException('Application not found');

    await provider.loadForApplication(5);

    expect(provider.errorMessage, 'Application not found');
    expect(provider.assessment, isNull);

    repository.loadError = null;
    repository.loadResult = _assessment(applicationId: 5);
    await provider.loadForApplication(5, forceRefresh: true);

    expect(provider.errorMessage, isNull);
    expect(provider.assessment, isNotNull);
  });

  test('malformed load data never leaves the provider stuck loading', () async {
    repository.loadRuntimeError = TypeError();

    await provider.loadForApplication(5);

    expect(provider.isLoading, isFalse);
    expect(provider.errorMessage, isNotNull);
    expect(provider.errorMessage, isNot(contains('TypeError')));
  });

  test('forceRefresh starts a new fetch even while unchanged', () async {
    await provider.loadForApplication(5);
    await provider.loadForApplication(5, forceRefresh: true);

    expect(repository.getAssessmentCallCount, 2);
  });

  test(
    'concurrent duplicate loads for the same application are prevented',
    () async {
      repository.loadResult = _assessment(applicationId: 5);

      final first = provider.loadForApplication(5);
      final second = provider.loadForApplication(5);
      await Future.wait([first, second]);

      expect(repository.getAssessmentCallCount, 1);
    },
  );

  test(
    'loading application 5 then application 9 loads application 9 correctly, not application 5\'s in-flight future',
    () async {
      repository.delaysByApplication = {5: const Duration(milliseconds: 100)};
      repository.resultsByApplication = {
        5: _assessment(id: 1, applicationId: 5),
        9: _assessment(id: 2, applicationId: 9),
      };

      final firstCall = provider.loadForApplication(5);
      final secondCall = provider.loadForApplication(9);
      await Future.wait([firstCall, secondCall]);

      expect(provider.assessment?.applicationId, 9);
      expect(provider.loadedApplicationId, 9);
      expect(repository.requestedApplicationIds, containsAll([5, 9]));
    },
  );

  test(
    'a slower stale response for application 5 cannot overwrite the newer application 9 state',
    () async {
      repository.resultsByApplication = {
        9: _assessment(id: 9, applicationId: 9),
        5: _assessment(id: 5, applicationId: 5),
      };

      await provider.loadForApplication(9);
      expect(provider.assessment?.applicationId, 9);

      repository.delaysByApplication = {5: const Duration(milliseconds: 100)};
      final staleCall = provider.loadForApplication(5);

      // Switch back to application 9 before the stale application-5
      // response arrives.
      await provider.loadForApplication(9, forceRefresh: true);
      expect(provider.assessment?.applicationId, 9);

      await staleCall;

      expect(provider.assessment?.applicationId, 9);
      expect(provider.loadedApplicationId, 9);
    },
  );

  test(
    'createAssessment success sets the assessment and loadedApplicationId',
    () async {
      repository.createResult = _assessment(applicationId: 5);

      final success = await provider.createAssessment(
        applicationId: 5,
        type: 'interview',
        interviewInput: _validInput(),
      );

      expect(success, isTrue);
      expect(provider.assessment, isNotNull);
      expect(provider.assessment!.applicationId, 5);
      expect(provider.loadedApplicationId, 5);
      expect(provider.actionErrorMessage, isNull);
      expect(provider.fieldErrors, isEmpty);
      expect(repository.lastCreateType, 'interview');
      expect(repository.lastInterviewInput, isNotNull);
    },
  );

  test(
    'createAssessment quiz success sets the assessment and loadedApplicationId',
    () async {
      repository.createResult = _quizAssessment(applicationId: 5);

      final success = await provider.createAssessment(
        applicationId: 5,
        type: 'quiz',
        quizInput: _validQuizInput(),
      );

      expect(success, isTrue);
      expect(provider.assessment, isNotNull);
      expect(provider.assessment!.type, 'quiz');
      expect(provider.loadedApplicationId, 5);
      expect(repository.lastCreateType, 'quiz');
      expect(repository.lastQuizInput, isNotNull);
      expect(repository.lastInterviewInput, isNull);
    },
  );

  test('createAssessment quiz validation error exposes field errors', () async {
    repository.createError = ApiException(
      'The given data was invalid.',
      statusCode: 422,
      errors: {
        'quiz.passing_score': ['The quiz.passing score field is required.'],
      },
    );

    final success = await provider.createAssessment(
      applicationId: 5,
      type: 'quiz',
      quizInput: _validQuizInput(),
    );

    expect(success, isFalse);
    expect(provider.fieldErrors['quiz.passing_score'], isNotNull);
    expect(provider.assessment, isNull);
  });

  test(
    'a duplicate quiz create submission for the same application is blocked',
    () async {
      repository.createDelay = const Duration(milliseconds: 50);
      repository.createResult = _quizAssessment(applicationId: 5);

      final first = provider.createAssessment(
        applicationId: 5,
        type: 'quiz',
        quizInput: _validQuizInput(),
      );
      final second = provider.createAssessment(
        applicationId: 5,
        type: 'quiz',
        quizInput: _validQuizInput(),
      );

      final results = await Future.wait([first, second]);

      expect(repository.createCallCount, 1);
      expect(results.where((success) => success).length, 1);
    },
  );

  test(
    'createAssessment rejects a quizInput when type is interview (local guard)',
    () {
      expect(
        () => provider.createAssessment(
          applicationId: 5,
          type: 'interview',
          interviewInput: _validInput(),
          quizInput: _validQuizInput(),
        ),
        throwsA(isA<ArgumentError>()),
      );
    },
  );

  test(
    'createAssessment rejects an interviewInput when type is quiz (local guard)',
    () {
      expect(
        () => provider.createAssessment(
          applicationId: 5,
          type: 'quiz',
          quizInput: _validQuizInput(),
          interviewInput: _validInput(),
        ),
        throwsA(isA<ArgumentError>()),
      );
    },
  );

  test(
    'interview creation behavior is unchanged by the quiz addition',
    () async {
      repository.createResult = _assessment(applicationId: 5);

      final success = await provider.createAssessment(
        applicationId: 5,
        type: 'interview',
        interviewInput: _validInput(),
      );

      expect(success, isTrue);
      expect(provider.assessment!.type, 'interview');
      expect(repository.lastQuizInput, isNull);
      expect(repository.lastInterviewInput, isNotNull);
    },
  );

  test('createAssessment API failure exposes the backend message', () async {
    repository.createError = ApiException(
      'An assessment already exists for this application',
      statusCode: 409,
    );

    final success = await provider.createAssessment(
      applicationId: 5,
      type: 'interview',
      interviewInput: _validInput(),
    );

    expect(success, isFalse);
    expect(
      provider.actionErrorMessage,
      'An assessment already exists for this application',
    );
    expect(provider.assessment, isNull);
  });

  test('createAssessment unexpected failure exposes a safe message', () async {
    repository.createRuntimeError = TypeError();

    final success = await provider.createAssessment(
      applicationId: 5,
      type: 'interview',
      interviewInput: _validInput(),
    );

    expect(success, isFalse);
    expect(provider.actionErrorMessage, isNotNull);
    expect(provider.actionErrorMessage, isNot(contains('TypeError')));
    expect(
      provider.actionErrorMessage,
      'Something went wrong. Please try again.',
    );
  });

  test('field errors are stored from a 422 response', () async {
    repository.createError = ApiException(
      'The given data was invalid.',
      statusCode: 422,
      errors: {
        'interview.meeting_link': [
          'The interview.meeting link field is required.',
        ],
      },
    );

    await provider.createAssessment(
      applicationId: 5,
      type: 'interview',
      interviewInput: _validInput(),
    );

    expect(provider.fieldErrors, isNotEmpty);
    expect(provider.fieldErrors['interview.meeting_link'], isNotNull);
  });

  test(
    'nested error keys are preserved exactly, never renamed/stripped',
    () async {
      repository.createError = ApiException(
        'The given data was invalid.',
        statusCode: 422,
        errors: {
          'interview.meeting_link': ['required'],
          'interview.location': ['required'],
          'interview.scheduled_at': ['required'],
        },
      );

      await provider.createAssessment(
        applicationId: 5,
        type: 'interview',
        interviewInput: _validInput(),
      );

      expect(
        provider.fieldErrors.keys,
        containsAll([
          'interview.meeting_link',
          'interview.location',
          'interview.scheduled_at',
        ]),
      );
    },
  );

  test(
    'a duplicate create submission for the same application is blocked',
    () async {
      repository.createDelay = const Duration(milliseconds: 50);
      repository.createResult = _assessment(applicationId: 5);

      final first = provider.createAssessment(
        applicationId: 5,
        type: 'interview',
        interviewInput: _validInput(),
      );
      final second = provider.createAssessment(
        applicationId: 5,
        type: 'interview',
        interviewInput: _validInput(),
      );

      final results = await Future.wait([first, second]);

      expect(repository.createCallCount, 1);
      expect(results.where((success) => success).length, 1);
      expect(results.where((success) => !success).length, 1);
    },
  );

  test('busy ID is removed in finally after a successful create', () async {
    repository.createResult = _assessment(applicationId: 5);

    expect(provider.isCreatingFor(5), isFalse);
    final future = provider.createAssessment(
      applicationId: 5,
      type: 'interview',
      interviewInput: _validInput(),
    );
    expect(provider.isCreatingFor(5), isTrue);
    expect(provider.isCreating, isTrue);
    await future;
    expect(provider.isCreatingFor(5), isFalse);
    expect(provider.isCreating, isFalse);
  });

  test('busy ID is removed in finally after a failed create', () async {
    repository.createError = ApiException('Server error.');

    await provider.createAssessment(
      applicationId: 5,
      type: 'interview',
      interviewInput: _validInput(),
    );

    expect(provider.isCreatingFor(5), isFalse);
  });

  test('previous assessment is retained after a failed create', () async {
    repository.loadResult = _assessment(id: 1, applicationId: 5);
    await provider.loadForApplication(5);
    expect(provider.assessment?.id, 1);

    repository.createError = ApiException('Server error.');
    await provider.createAssessment(
      applicationId: 5,
      type: 'interview',
      interviewInput: _validInput(),
    );

    expect(provider.assessment?.id, 1);
  });

  test('clearActionError clears the action error message', () async {
    repository.createError = ApiException('Server error.');
    await provider.createAssessment(
      applicationId: 5,
      type: 'interview',
      interviewInput: _validInput(),
    );
    expect(provider.actionErrorMessage, isNotNull);

    provider.clearActionError();

    expect(provider.actionErrorMessage, isNull);
  });

  test('clearFieldErrors clears the field-error map', () async {
    repository.createError = ApiException(
      'The given data was invalid.',
      statusCode: 422,
      errors: {
        'interview.meeting_link': ['required'],
      },
    );
    await provider.createAssessment(
      applicationId: 5,
      type: 'interview',
      interviewInput: _validInput(),
    );
    expect(provider.fieldErrors, isNotEmpty);

    provider.clearFieldErrors();

    expect(provider.fieldErrors, isEmpty);
  });

  test(
    'completeInterview success refreshes assessment from the backend',
    () async {
      repository.loadResult = _completedAssessment(applicationId: 5);
      repository.completeResult = _completedInterview();

      final success = await provider.completeInterview(
        applicationId: 5,
        interviewId: 1,
      );

      expect(success, isTrue);
      expect(provider.assessment?.status, 'completed');
      expect(provider.assessment?.interview?.status, 'completed');
      expect(provider.actionErrorMessage, isNull);
      expect(provider.fieldErrors, isEmpty);
    },
  );

  test('completeInterview succeeds with a completely empty payload', () async {
    repository.loadResult = _completedAssessment(applicationId: 5, result: null);
    repository.completeResult = _completedInterview(decision: null);

    final success = await provider.completeInterview(
      applicationId: 5,
      interviewId: 1,
    );

    expect(success, isTrue);
    expect(repository.lastCompleteDecision, isNull);
    expect(repository.lastCompleteRating, isNull);
    expect(repository.lastCompleteCompanyFeedback, isNull);
  });

  test('completeInterview forwards the decision', () async {
    repository.loadResult = _completedAssessment(applicationId: 5);
    repository.completeResult = _completedInterview();

    await provider.completeInterview(
      applicationId: 5,
      interviewId: 1,
      decision: 'passed',
    );

    expect(repository.lastCompleteInterviewId, 1);
    expect(repository.lastCompleteDecision, 'passed');
  });

  test('completeInterview forwards rating and company feedback', () async {
    repository.loadResult = _completedAssessment(applicationId: 5);
    repository.completeResult = _completedInterview();

    await provider.completeInterview(
      applicationId: 5,
      interviewId: 1,
      rating: 5,
      companyFeedback: 'Great candidate.',
    );

    expect(repository.lastCompleteRating, 5);
    expect(repository.lastCompleteCompanyFeedback, 'Great candidate.');
  });

  test('completeInterview validation error exposes field errors', () async {
    repository.loadResult = _assessment(applicationId: 5);
    await provider.loadForApplication(5);

    repository.completeError = ApiException(
      'The given data was invalid.',
      statusCode: 422,
      errors: {
        'rating': ['The rating must be at least 1.'],
      },
    );

    final success = await provider.completeInterview(
      applicationId: 5,
      interviewId: 1,
      rating: 0,
    );

    expect(success, isFalse);
    expect(provider.fieldErrors['rating'], isNotNull);
    // The previous (still-scheduled) assessment is untouched — no false
    // completion.
    expect(provider.assessment?.status, 'scheduled');
  });

  test(
    'completeInterview business error exposes the backend message and leaves assessment untouched',
    () async {
      repository.loadResult = _assessment(applicationId: 5);
      await provider.loadForApplication(5);

      repository.completeError = ApiException(
        'Interview not found',
        statusCode: 404,
      );

      final success = await provider.completeInterview(
        applicationId: 5,
        interviewId: 1,
      );

      expect(success, isFalse);
      expect(provider.actionErrorMessage, 'Interview not found');
      expect(provider.assessment?.status, 'scheduled');
    },
  );

  test('completeInterview unexpected failure exposes a safe message', () async {
    repository.completeRuntimeError = TypeError();

    final success = await provider.completeInterview(
      applicationId: 5,
      interviewId: 1,
    );

    expect(success, isFalse);
    expect(
      provider.actionErrorMessage,
      'Something went wrong. Please try again.',
    );
  });

  test(
    'a duplicate completeInterview submission for the same interview is blocked',
    () async {
      repository.completeDelay = const Duration(milliseconds: 50);
      repository.completeResult = _completedInterview();
      repository.loadResult = _completedAssessment(applicationId: 5);

      final first = provider.completeInterview(
        applicationId: 5,
        interviewId: 1,
      );
      final second = provider.completeInterview(
        applicationId: 5,
        interviewId: 1,
      );

      final results = await Future.wait([first, second]);

      expect(repository.completeCallCount, 1);
      expect(results.where((success) => success).length, 1);
      expect(results.where((success) => !success).length, 1);
    },
  );

  test(
    'isCompletingInterview is true only while in flight, for the right interview',
    () async {
      repository.completeDelay = const Duration(milliseconds: 50);
      repository.completeResult = _completedInterview();
      repository.loadResult = _completedAssessment(applicationId: 5);

      expect(provider.isCompletingInterview(1), isFalse);
      final future = provider.completeInterview(
        applicationId: 5,
        interviewId: 1,
      );
      expect(provider.isCompletingInterview(1), isTrue);
      expect(provider.isCompletingInterview(2), isFalse);
      await future;
      expect(provider.isCompletingInterview(1), isFalse);
    },
  );

  test('reset clears all state (called on logout)', () async {
    repository.loadResult = _assessment(applicationId: 5);
    await provider.loadForApplication(5);
    expect(provider.assessment, isNotNull);

    await authProvider.logout();

    expect(provider.assessment, isNull);
    expect(provider.loadedApplicationId, isNull);
    expect(provider.isLoading, isFalse);
    expect(provider.errorMessage, isNull);
    expect(provider.actionErrorMessage, isNull);
    expect(provider.fieldErrors, isEmpty);
    expect(provider.busyApplicationIds, isEmpty);
    expect(provider.completingInterviewIds, isEmpty);
  });

  test(
    'dispose removes the AuthProvider listener (no error on logout after dispose)',
    () async {
      provider.dispose();

      await expectLater(authProvider.logout(), completes);
    },
  );
}
