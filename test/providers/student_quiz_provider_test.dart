// Direct unit tests for StudentQuizProvider, using a fake repository (no
// real network) and a real AuthProvider (with a fake AuthRepository) so the
// reset-on-logout listener can be exercised genuinely. Mirrors
// organization_quiz_provider_test.dart's structure and conventions.

import 'package:flutter_test/flutter_test.dart';

import 'package:opportunityhub_flutter/core/api/api_client.dart';
import 'package:opportunityhub_flutter/core/storage/token_storage_service.dart';
import 'package:opportunityhub_flutter/features/assessments/data/assessment_repository.dart';
import 'package:opportunityhub_flutter/features/auth/data/auth_repository.dart';
import 'package:opportunityhub_flutter/models/question_model.dart';
import 'package:opportunityhub_flutter/models/quiz_attempt_model.dart';
import 'package:opportunityhub_flutter/models/quiz_model.dart';
import 'package:opportunityhub_flutter/providers/auth_provider.dart';
import 'package:opportunityhub_flutter/providers/student_quiz_provider.dart';

class _FakeAuthRepository extends AuthRepository {
  _FakeAuthRepository()
    : super(
        apiClient: ApiClient(tokenStorageService: TokenStorageService()),
        tokenStorageService: TokenStorageService(),
      );

  @override
  Future<String?> getSavedToken() async => null;

  @override
  Future<void> logout() async {}
}

QuestionModel _question({
  int id = 1,
  int quizId = 1,
  String type = 'multiple_choice',
  int position = 0,
}) {
  return QuestionModel(
    id: id,
    quizId: quizId,
    prompt: 'What is the capital of France?',
    type: type,
    options: type == 'multiple_choice'
        ? const ['Paris', 'London', 'Berlin']
        : null,
    points: 1,
    position: position,
  );
}

QuizModel _quiz({
  int id = 1,
  int assessmentId = 1,
  int? timeLimitMinutes,
  int passingScore = 70,
  List<QuestionModel> questions = const [],
}) {
  return QuizModel(
    id: id,
    assessmentId: assessmentId,
    title: 'Backend Fundamentals',
    timeLimitMinutes: timeLimitMinutes,
    passingScore: passingScore,
    status: 'published',
    questions: questions,
  );
}

QuizAttemptModel _attempt({
  int id = 1,
  int quizId = 1,
  int applicationId = 5,
  Map<int, String> answers = const {},
  int? score,
  DateTime? startedAt,
  DateTime? submittedAt,
}) {
  return QuizAttemptModel(
    id: id,
    quizId: quizId,
    applicationId: applicationId,
    answers: answers,
    score: score,
    startedAt: startedAt ?? DateTime.now(),
    submittedAt: submittedAt,
  );
}

class _FakeAssessmentRepository extends AssessmentRepository {
  _FakeAssessmentRepository()
    : super(apiClient: ApiClient(tokenStorageService: TokenStorageService()));

  QuizModel? loadResult;
  ApiException? loadError;
  Object? loadRuntimeError;
  int getQuizCallCount = 0;
  final List<int> requestedAssessmentIds = [];
  Map<int, QuizModel>? resultsByAssessment;
  Map<int, Duration>? delaysByAssessment;

  QuizAttemptModel? startResult;
  ApiException? startError;
  Duration startDelay = Duration.zero;
  int startCallCount = 0;

  QuizAttemptModel? submitResult;
  ApiException? submitError;
  Duration submitDelay = Duration.zero;
  int submitCallCount = 0;
  Map<int, String>? lastSubmitAnswers;

  @override
  Future<QuizModel> getStudentQuiz(int assessmentId) async {
    getQuizCallCount++;
    requestedAssessmentIds.add(assessmentId);

    final delay = delaysByAssessment?[assessmentId] ?? Duration.zero;
    if (delay > Duration.zero) await Future<void>.delayed(delay);
    if (loadRuntimeError != null) throw loadRuntimeError!;
    if (loadError != null) throw loadError!;
    if (resultsByAssessment != null) return resultsByAssessment![assessmentId]!;
    return loadResult!;
  }

  @override
  Future<QuizAttemptModel> startStudentQuiz(int quizId) async {
    startCallCount++;
    if (startDelay > Duration.zero) {
      await Future<void>.delayed(startDelay);
    }
    if (startError != null) throw startError!;
    return startResult!;
  }

  @override
  Future<QuizAttemptModel> submitStudentQuiz({
    required int quizId,
    required Map<int, String> answers,
  }) async {
    submitCallCount++;
    lastSubmitAnswers = answers;
    if (submitDelay > Duration.zero) {
      await Future<void>.delayed(submitDelay);
    }
    if (submitError != null) throw submitError!;
    return submitResult!;
  }
}

void main() {
  late AuthProvider authProvider;
  late _FakeAssessmentRepository repository;
  late StudentQuizProvider provider;

  setUp(() {
    authProvider = AuthProvider(authRepository: _FakeAuthRepository());
    repository = _FakeAssessmentRepository();
    provider = StudentQuizProvider(
      repository: repository,
      authProvider: authProvider,
    );
  });

  test('initial state is empty and idle', () {
    expect(provider.quiz, isNull);
    expect(provider.attempt, isNull);
    expect(provider.selectedAnswers, isEmpty);
    expect(provider.loadedAssessmentId, isNull);
    expect(provider.isLoading, isFalse);
    expect(provider.errorMessage, isNull);
    expect(provider.isStarting, isFalse);
    expect(provider.isSubmitting, isFalse);
    expect(provider.actionErrorMessage, isNull);
    expect(provider.startAlreadySubmitted, isFalse);
    expect(provider.fieldErrors, isEmpty);
    expect(provider.remainingTime, isNull);
    expect(provider.isExpired, isFalse);
  });

  group('loadQuiz', () {
    test('loading an existing quiz populates state', () async {
      repository.loadResult = _quiz(assessmentId: 7);

      await provider.loadQuiz(7);

      expect(provider.quiz, isNotNull);
      expect(provider.quiz!.assessmentId, 7);
      expect(provider.loadedAssessmentId, 7);
      expect(provider.isLoading, isFalse);
      expect(provider.errorMessage, isNull);
    });

    test('load failure surfaces the error and is retryable', () async {
      repository.loadError = ApiException('Quiz not found');

      await provider.loadQuiz(7);

      expect(provider.errorMessage, 'Quiz not found');
      expect(provider.quiz, isNull);

      repository.loadError = null;
      repository.loadResult = _quiz(assessmentId: 7);
      await provider.loadQuiz(7, forceRefresh: true);

      expect(provider.errorMessage, isNull);
      expect(provider.quiz, isNotNull);
    });

    test(
      'malformed load data never leaves the provider stuck loading',
      () async {
        repository.loadRuntimeError = TypeError();

        await provider.loadQuiz(7);

        expect(provider.isLoading, isFalse);
        expect(provider.errorMessage, isNotNull);
        expect(provider.errorMessage, isNot(contains('TypeError')));
      },
    );

    test('forceRefresh starts a new fetch even while unchanged', () async {
      repository.loadResult = _quiz(assessmentId: 7);
      await provider.loadQuiz(7);
      await provider.loadQuiz(7, forceRefresh: true);

      expect(repository.getQuizCallCount, 2);
    });

    test(
      'concurrent duplicate loads for the same assessment are prevented',
      () async {
        repository.loadResult = _quiz(assessmentId: 7);

        final first = provider.loadQuiz(7);
        final second = provider.loadQuiz(7);
        await Future.wait([first, second]);

        expect(repository.getQuizCallCount, 1);
      },
    );

    test(
      'a slower stale response for assessment 7 cannot overwrite the newer assessment 9 state',
      () async {
        repository.resultsByAssessment = {
          9: _quiz(id: 9, assessmentId: 9),
          7: _quiz(id: 7, assessmentId: 7),
        };

        await provider.loadQuiz(9);
        expect(provider.quiz?.assessmentId, 9);

        repository.delaysByAssessment = {7: const Duration(milliseconds: 100)};
        final staleCall = provider.loadQuiz(7);

        await provider.loadQuiz(9, forceRefresh: true);
        expect(provider.quiz?.assessmentId, 9);

        await staleCall;

        expect(provider.quiz?.assessmentId, 9);
        expect(provider.loadedAssessmentId, 9);
      },
    );
  });

  group('start', () {
    test('returns false when no quiz is loaded yet', () async {
      final success = await provider.start();

      expect(success, isFalse);
      expect(repository.startCallCount, 0);
    });

    test('success populates attempt and restores answers', () async {
      repository.loadResult = _quiz(assessmentId: 7);
      await provider.loadQuiz(7);
      final startedAt = DateTime.now();
      repository.startResult = _attempt(startedAt: startedAt);

      final success = await provider.start();

      expect(success, isTrue);
      expect(provider.attempt, isNotNull);
      expect(provider.attempt!.isSubmitted, isFalse);
      expect(provider.selectedAnswers, isEmpty);
      expect(provider.effectiveStartedAt, startedAt);
    });

    test('a resumed attempt with existing answers restores them', () async {
      repository.loadResult = _quiz(assessmentId: 7);
      await provider.loadQuiz(7);
      repository.startResult = _attempt(answers: {1: 'Paris'});

      await provider.start();

      expect(provider.selectedAnswers, {1: 'Paris'});
    });

    test('a duplicate tap while one is in flight is blocked', () async {
      repository.loadResult = _quiz(assessmentId: 7);
      await provider.loadQuiz(7);
      repository.startDelay = const Duration(milliseconds: 50);
      repository.startResult = _attempt();

      final first = provider.start();
      final second = provider.start();
      final results = await Future.wait([first, second]);

      expect(repository.startCallCount, 1);
      expect(results.where((success) => success).length, 1);
    });

    test('isStarting is set during the request and cleared after', () async {
      repository.loadResult = _quiz(assessmentId: 7);
      await provider.loadQuiz(7);
      repository.startDelay = const Duration(milliseconds: 20);
      repository.startResult = _attempt();

      expect(provider.isStarting, isFalse);
      final future = provider.start();
      expect(provider.isStarting, isTrue);
      await future;
      expect(provider.isStarting, isFalse);
    });

    test(
      'a 409 (already submitted) sets startAlreadySubmitted and the backend message',
      () async {
        repository.loadResult = _quiz(assessmentId: 7);
        await provider.loadQuiz(7);
        repository.startError = ApiException(
          'Quiz has already been submitted',
          statusCode: 409,
        );

        final success = await provider.start();

        expect(success, isFalse);
        expect(provider.startAlreadySubmitted, isTrue);
        expect(provider.actionErrorMessage, 'Quiz has already been submitted');
        expect(provider.attempt, isNull);
      },
    );

    test('a non-409 failure does not set startAlreadySubmitted', () async {
      repository.loadResult = _quiz(assessmentId: 7);
      await provider.loadQuiz(7);
      repository.startError = ApiException('Quiz not found', statusCode: 404);

      final success = await provider.start();

      expect(success, isFalse);
      expect(provider.startAlreadySubmitted, isFalse);
      expect(provider.actionErrorMessage, 'Quiz not found');
    });
  });

  group('selectAnswer / hasAnswer / allQuestionsAnswered', () {
    test('selecting an answer before starting is a no-op', () {
      provider.selectAnswer(questionId: 1, answer: 'Paris');

      expect(provider.selectedAnswers, isEmpty);
      expect(provider.hasAnswer(1), isFalse);
    });

    test('selecting an answer after starting records it', () async {
      repository.loadResult = _quiz(
        assessmentId: 7,
        questions: [_question(id: 1)],
      );
      await provider.loadQuiz(7);
      repository.startResult = _attempt();
      await provider.start();

      provider.selectAnswer(questionId: 1, answer: 'Paris');

      expect(provider.selectedAnswers[1], 'Paris');
      expect(provider.hasAnswer(1), isTrue);
    });

    test('a later selection overwrites the previous one', () async {
      repository.loadResult = _quiz(
        assessmentId: 7,
        questions: [_question(id: 1)],
      );
      await provider.loadQuiz(7);
      repository.startResult = _attempt();
      await provider.start();

      provider.selectAnswer(questionId: 1, answer: 'Paris');
      provider.selectAnswer(questionId: 1, answer: 'Berlin');

      expect(provider.selectedAnswers[1], 'Berlin');
    });

    test('selecting an answer once submitted is a no-op', () async {
      repository.loadResult = _quiz(
        assessmentId: 7,
        questions: [_question(id: 1)],
      );
      await provider.loadQuiz(7);
      repository.startResult = _attempt();
      await provider.start();
      provider.selectAnswer(questionId: 1, answer: 'Paris');
      repository.submitResult = _attempt(
        answers: {1: 'Paris'},
        score: 100,
        submittedAt: DateTime.now(),
      );
      await provider.submit();

      provider.selectAnswer(questionId: 1, answer: 'Berlin');

      expect(provider.selectedAnswers[1], 'Paris');
    });

    test('allQuestionsAnswered is false with no quiz loaded', () {
      expect(provider.allQuestionsAnswered, isFalse);
    });

    test('allQuestionsAnswered is false with an empty question list', () async {
      repository.loadResult = _quiz(assessmentId: 7, questions: const []);
      await provider.loadQuiz(7);

      expect(provider.allQuestionsAnswered, isFalse);
    });

    test(
      'allQuestionsAnswered is false until every question has an answer',
      () async {
        repository.loadResult = _quiz(
          assessmentId: 7,
          questions: [_question(id: 1), _question(id: 2, position: 1)],
        );
        await provider.loadQuiz(7);
        repository.startResult = _attempt();
        await provider.start();

        provider.selectAnswer(questionId: 1, answer: 'Paris');
        expect(provider.allQuestionsAnswered, isFalse);

        provider.selectAnswer(questionId: 2, answer: 'Paris');
        expect(provider.allQuestionsAnswered, isTrue);
      },
    );
  });

  group('submit', () {
    test('returns false when no attempt has started yet', () async {
      repository.loadResult = _quiz(
        assessmentId: 7,
        questions: [_question(id: 1)],
      );
      await provider.loadQuiz(7);

      final success = await provider.submit();

      expect(success, isFalse);
      expect(repository.submitCallCount, 0);
    });

    test('returns false when not every question is answered', () async {
      repository.loadResult = _quiz(
        assessmentId: 7,
        questions: [_question(id: 1), _question(id: 2, position: 1)],
      );
      await provider.loadQuiz(7);
      repository.startResult = _attempt();
      await provider.start();
      provider.selectAnswer(questionId: 1, answer: 'Paris');

      final success = await provider.submit();

      expect(success, isFalse);
      expect(repository.submitCallCount, 0);
    });

    test(
      'success grades the attempt and sends exactly selectedAnswers',
      () async {
        repository.loadResult = _quiz(
          assessmentId: 7,
          questions: [_question(id: 1)],
        );
        await provider.loadQuiz(7);
        repository.startResult = _attempt();
        await provider.start();
        provider.selectAnswer(questionId: 1, answer: 'Paris');
        repository.submitResult = _attempt(
          answers: {1: 'Paris'},
          score: 100,
          submittedAt: DateTime.now(),
        );

        final success = await provider.submit();

        expect(success, isTrue);
        expect(provider.attempt!.isSubmitted, isTrue);
        expect(provider.attempt!.score, 100);
        expect(repository.lastSubmitAnswers, {1: 'Paris'});
      },
    );

    test('a duplicate submit while one is in flight is blocked', () async {
      repository.loadResult = _quiz(
        assessmentId: 7,
        questions: [_question(id: 1)],
      );
      await provider.loadQuiz(7);
      repository.startResult = _attempt();
      await provider.start();
      provider.selectAnswer(questionId: 1, answer: 'Paris');
      repository.submitDelay = const Duration(milliseconds: 50);
      repository.submitResult = _attempt(
        answers: {1: 'Paris'},
        score: 100,
        submittedAt: DateTime.now(),
      );

      final first = provider.submit();
      final second = provider.submit();
      final results = await Future.wait([first, second]);

      expect(repository.submitCallCount, 1);
      expect(results.where((success) => success).length, 1);
    });

    test('isSubmitting is set during the request and cleared after', () async {
      repository.loadResult = _quiz(
        assessmentId: 7,
        questions: [_question(id: 1)],
      );
      await provider.loadQuiz(7);
      repository.startResult = _attempt();
      await provider.start();
      provider.selectAnswer(questionId: 1, answer: 'Paris');
      repository.submitDelay = const Duration(milliseconds: 20);
      repository.submitResult = _attempt(
        answers: {1: 'Paris'},
        score: 100,
        submittedAt: DateTime.now(),
      );

      expect(provider.isSubmitting, isFalse);
      final future = provider.submit();
      expect(provider.isSubmitting, isTrue);
      await future;
      expect(provider.isSubmitting, isFalse);
    });

    test('failure preserves the student\'s selected answers', () async {
      repository.loadResult = _quiz(
        assessmentId: 7,
        questions: [_question(id: 1)],
      );
      await provider.loadQuiz(7);
      repository.startResult = _attempt();
      await provider.start();
      provider.selectAnswer(questionId: 1, answer: 'Paris');
      repository.submitError = ApiException('Server error.');

      final success = await provider.submit();

      expect(success, isFalse);
      expect(provider.actionErrorMessage, 'Server error.');
      expect(provider.selectedAnswers[1], 'Paris');
      expect(provider.attempt!.isSubmitted, isFalse);
    });

    test('field errors are stored from a 422 response', () async {
      repository.loadResult = _quiz(
        assessmentId: 7,
        questions: [_question(id: 1)],
      );
      await provider.loadQuiz(7);
      repository.startResult = _attempt();
      await provider.start();
      provider.selectAnswer(questionId: 1, answer: 'Paris');
      repository.submitError = ApiException(
        'The given data was invalid.',
        statusCode: 422,
        errors: {
          'answers': ['Every quiz question must be answered.'],
        },
      );

      await provider.submit();

      expect(provider.fieldErrors['answers'], isNotNull);
    });

    test(
      'submitting an already-submitted attempt is blocked locally',
      () async {
        repository.loadResult = _quiz(
          assessmentId: 7,
          questions: [_question(id: 1)],
        );
        await provider.loadQuiz(7);
        repository.startResult = _attempt();
        await provider.start();
        provider.selectAnswer(questionId: 1, answer: 'Paris');
        repository.submitResult = _attempt(
          answers: {1: 'Paris'},
          score: 100,
          submittedAt: DateTime.now(),
        );
        await provider.submit();

        final success = await provider.submit();

        expect(success, isFalse);
        expect(repository.submitCallCount, 1);
      },
    );
  });

  group('timer', () {
    test('a quiz with no time limit never starts a countdown', () async {
      repository.loadResult = _quiz(assessmentId: 7, timeLimitMinutes: null);
      await provider.loadQuiz(7);
      repository.startResult = _attempt();

      await provider.start();

      expect(provider.remainingTime, isNull);
      expect(provider.isExpired, isFalse);
    });

    test(
      'a resumed attempt uses its own real startedAt, not the local start() call time',
      () async {
        repository.loadResult = _quiz(assessmentId: 7, timeLimitMinutes: 30);
        await provider.loadQuiz(7);
        final realStartedAt = DateTime.now().subtract(
          const Duration(minutes: 10),
        );
        repository.startResult = _attempt(startedAt: realStartedAt);

        await provider.start();

        expect(provider.effectiveStartedAt, realStartedAt);
        // ~20 minutes should remain (30 minute limit, 10 already elapsed).
        expect(provider.remainingTime!.inMinutes, lessThanOrEqualTo(20));
        expect(provider.remainingTime!.inMinutes, greaterThan(18));
        expect(provider.isExpired, isFalse);
      },
    );

    test(
      'an attempt whose time limit has already elapsed is immediately marked expired',
      () async {
        repository.loadResult = _quiz(assessmentId: 7, timeLimitMinutes: 30);
        await provider.loadQuiz(7);
        final longAgo = DateTime.now().subtract(const Duration(minutes: 40));
        repository.startResult = _attempt(startedAt: longAgo);

        await provider.start();

        expect(provider.isExpired, isTrue);
        expect(provider.remainingTime, Duration.zero);
      },
    );

    test('submit stops the countdown', () async {
      repository.loadResult = _quiz(
        assessmentId: 7,
        timeLimitMinutes: 30,
        questions: [_question(id: 1)],
      );
      await provider.loadQuiz(7);
      repository.startResult = _attempt();
      await provider.start();
      provider.selectAnswer(questionId: 1, answer: 'Paris');
      repository.submitResult = _attempt(
        answers: {1: 'Paris'},
        score: 100,
        submittedAt: DateTime.now(),
      );

      await provider.submit();

      // A subsequent real tick (if the timer were still running) would
      // flip `isExpired`/`remainingTime` — waiting past one tick interval
      // and confirming nothing changed proves the timer was actually
      // cancelled, not just coincidentally idle.
      final remainingBefore = provider.remainingTime;
      await Future<void>.delayed(const Duration(milliseconds: 1100));
      expect(provider.remainingTime, remainingBefore);
    });
  });

  test('reset clears all state (called on logout)', () async {
    repository.loadResult = _quiz(
      assessmentId: 7,
      timeLimitMinutes: 30,
      questions: [_question(id: 1)],
    );
    await provider.loadQuiz(7);
    repository.startResult = _attempt();
    await provider.start();
    provider.selectAnswer(questionId: 1, answer: 'Paris');
    expect(provider.quiz, isNotNull);
    expect(provider.attempt, isNotNull);

    await authProvider.logout();

    expect(provider.quiz, isNull);
    expect(provider.attempt, isNull);
    expect(provider.selectedAnswers, isEmpty);
    expect(provider.loadedAssessmentId, isNull);
    expect(provider.isLoading, isFalse);
    expect(provider.errorMessage, isNull);
    expect(provider.isStarting, isFalse);
    expect(provider.isSubmitting, isFalse);
    expect(provider.actionErrorMessage, isNull);
    expect(provider.startAlreadySubmitted, isFalse);
    expect(provider.fieldErrors, isEmpty);
    expect(provider.remainingTime, isNull);
    expect(provider.isExpired, isFalse);
  });

  test('reset invalidates a load still in flight', () async {
    repository.loadResult = _quiz(assessmentId: 7);
    repository.delaysByAssessment = {7: const Duration(milliseconds: 50)};
    final staleLoad = provider.loadQuiz(7);

    provider.reset();
    await staleLoad;

    expect(provider.quiz, isNull);
    expect(provider.loadedAssessmentId, isNull);
  });

  test(
    'dispose removes the AuthProvider listener (no error on logout after dispose)',
    () async {
      provider.dispose();

      await expectLater(authProvider.logout(), completes);
    },
  );
}
