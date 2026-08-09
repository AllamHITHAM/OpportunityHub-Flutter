// Direct unit tests for OrganizationQuizProvider, using a fake repository
// (no real network) and a real AuthProvider (with a fake AuthRepository) so
// the reset-on-logout listener can be exercised genuinely. Mirrors
// organization_assessment_provider_test.dart's structure and conventions.

import 'package:flutter_test/flutter_test.dart';

import 'package:opportunityhub_flutter/core/api/api_client.dart';
import 'package:opportunityhub_flutter/core/storage/token_storage_service.dart';
import 'package:opportunityhub_flutter/features/assessments/data/assessment_repository.dart';
import 'package:opportunityhub_flutter/features/assessments/data/question_input.dart';
import 'package:opportunityhub_flutter/features/auth/data/auth_repository.dart';
import 'package:opportunityhub_flutter/models/question_model.dart';
import 'package:opportunityhub_flutter/models/quiz_model.dart';
import 'package:opportunityhub_flutter/providers/auth_provider.dart';
import 'package:opportunityhub_flutter/providers/organization_quiz_provider.dart';

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
  String prompt = 'What is the capital of France?',
  String correctAnswer = 'Paris',
  int position = 0,
}) {
  return QuestionModel(
    id: id,
    quizId: quizId,
    prompt: prompt,
    type: 'multiple_choice',
    options: const ['Paris', 'London', 'Berlin'],
    correctAnswer: correctAnswer,
    points: 1,
    position: position,
  );
}

QuizModel _quiz({
  int id = 1,
  int assessmentId = 1,
  String status = 'draft',
  List<QuestionModel> questions = const [],
  String? assessmentStatus,
}) {
  return QuizModel(
    id: id,
    assessmentId: assessmentId,
    title: 'Backend Fundamentals',
    passingScore: 70,
    status: status,
    questions: questions,
    assessmentStatus: assessmentStatus,
  );
}

QuestionInput _questionInput({String correctAnswer = 'Paris'}) {
  return QuestionInput(
    prompt: 'What is the capital of France?',
    type: 'multiple_choice',
    options: const ['Paris', 'London', 'Berlin'],
    correctAnswer: correctAnswer,
    points: 1,
    position: 0,
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
  Map<int, QuizModel?>? resultsByAssessment;
  Map<int, Duration>? delaysByAssessment;

  QuestionModel? createResult;
  ApiException? createError;
  Object? createRuntimeError;
  Duration createDelay = Duration.zero;
  int createCallCount = 0;

  QuestionModel? updateResult;
  ApiException? updateError;
  int updateCallCount = 0;

  ApiException? deleteError;
  int deleteCallCount = 0;

  QuizModel? publishResult;
  ApiException? publishError;
  int publishCallCount = 0;

  @override
  Future<QuizModel?> getOrganizationQuiz(int assessmentId) async {
    getQuizCallCount++;
    requestedAssessmentIds.add(assessmentId);

    final delay = delaysByAssessment?[assessmentId] ?? Duration.zero;
    if (delay > Duration.zero) await Future<void>.delayed(delay);
    if (loadRuntimeError != null) throw loadRuntimeError!;
    if (loadError != null) throw loadError!;
    if (resultsByAssessment != null) return resultsByAssessment![assessmentId];
    return loadResult;
  }

  @override
  Future<QuestionModel> createQuizQuestion({
    required int quizId,
    required QuestionInput input,
  }) async {
    createCallCount++;
    if (createDelay > Duration.zero) {
      await Future<void>.delayed(createDelay);
    }
    if (createRuntimeError != null) throw createRuntimeError!;
    if (createError != null) throw createError!;
    return createResult!;
  }

  @override
  Future<QuestionModel> updateQuizQuestion({
    required int quizId,
    required int questionId,
    required QuestionInput input,
  }) async {
    updateCallCount++;
    if (updateError != null) throw updateError!;
    return updateResult!;
  }

  @override
  Future<void> deleteQuizQuestion({
    required int quizId,
    required int questionId,
  }) async {
    deleteCallCount++;
    if (deleteError != null) throw deleteError!;
  }

  @override
  Future<QuizModel> publishQuiz(int quizId) async {
    publishCallCount++;
    if (publishError != null) throw publishError!;
    return publishResult!;
  }
}

void main() {
  late AuthProvider authProvider;
  late _FakeAssessmentRepository repository;
  late OrganizationQuizProvider provider;

  setUp(() {
    authProvider = AuthProvider(authRepository: _FakeAuthRepository());
    repository = _FakeAssessmentRepository();
    provider = OrganizationQuizProvider(
      repository: repository,
      authProvider: authProvider,
    );
  });

  test('initial state is empty and idle', () {
    expect(provider.quiz, isNull);
    expect(provider.loadedAssessmentId, isNull);
    expect(provider.isLoading, isFalse);
    expect(provider.errorMessage, isNull);
    expect(provider.actionErrorMessage, isNull);
    expect(provider.fieldErrors, isEmpty);
    expect(provider.busyQuestionIds, isEmpty);
    expect(provider.isCreatingQuestion, isFalse);
    expect(provider.isPublishing, isFalse);
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

    test(
      'loading with no quiz is represented correctly, not as an error',
      () async {
        await provider.loadQuiz(7);

        expect(provider.quiz, isNull);
        expect(provider.errorMessage, isNull);
      },
    );

    test('load failure surfaces the error and is retryable', () async {
      repository.loadError = ApiException('Assessment not found');

      await provider.loadQuiz(7);

      expect(provider.errorMessage, 'Assessment not found');
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
      'loading assessment 7 then assessment 9 loads assessment 9 correctly, not assessment 7\'s in-flight future',
      () async {
        repository.delaysByAssessment = {7: const Duration(milliseconds: 100)};
        repository.resultsByAssessment = {
          7: _quiz(id: 1, assessmentId: 7),
          9: _quiz(id: 2, assessmentId: 9),
        };

        final firstCall = provider.loadQuiz(7);
        final secondCall = provider.loadQuiz(9);
        await Future.wait([firstCall, secondCall]);

        expect(provider.quiz?.assessmentId, 9);
        expect(provider.loadedAssessmentId, 9);
        expect(repository.requestedAssessmentIds, containsAll([7, 9]));
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

  group('createQuestion', () {
    test('success appends the question to the local list', () async {
      repository.loadResult = _quiz(assessmentId: 7);
      await provider.loadQuiz(7);
      repository.createResult = _question(id: 1);

      final success = await provider.createQuestion(_questionInput());

      expect(success, isTrue);
      expect(provider.quiz!.questions, hasLength(1));
      expect(provider.quiz!.questions.first.id, 1);
      expect(repository.createCallCount, 1);
    });

    test(
      'does not trigger a full reload (no extra getOrganizationQuiz call)',
      () async {
        repository.loadResult = _quiz(assessmentId: 7);
        await provider.loadQuiz(7);
        repository.createResult = _question(id: 1);

        await provider.createQuestion(_questionInput());

        expect(repository.getQuizCallCount, 1);
      },
    );

    test(
      'API failure exposes the backend message and preserves old state',
      () async {
        repository.loadResult = _quiz(assessmentId: 7);
        await provider.loadQuiz(7);
        repository.createError = ApiException('Server error.');

        final success = await provider.createQuestion(_questionInput());

        expect(success, isFalse);
        expect(provider.actionErrorMessage, 'Server error.');
        expect(provider.quiz!.questions, isEmpty);
      },
    );

    test('field errors are stored from a 422 response', () async {
      repository.loadResult = _quiz(assessmentId: 7);
      await provider.loadQuiz(7);
      repository.createError = ApiException(
        'The given data was invalid.',
        statusCode: 422,
        errors: {
          'options': ['At least 2 options are required.'],
        },
      );

      await provider.createQuestion(_questionInput());

      expect(provider.fieldErrors['options'], isNotNull);
    });

    test('a duplicate submit while one is in flight is blocked', () async {
      repository.loadResult = _quiz(assessmentId: 7);
      await provider.loadQuiz(7);
      repository.createDelay = const Duration(milliseconds: 50);
      repository.createResult = _question(id: 1);

      final first = provider.createQuestion(_questionInput());
      final second = provider.createQuestion(_questionInput());
      final results = await Future.wait([first, second]);

      expect(repository.createCallCount, 1);
      expect(results.where((success) => success).length, 1);
    });

    test(
      'isCreatingQuestion is set during the request and cleared after',
      () async {
        repository.loadResult = _quiz(assessmentId: 7);
        await provider.loadQuiz(7);
        repository.createDelay = const Duration(milliseconds: 20);
        repository.createResult = _question(id: 1);

        expect(provider.isCreatingQuestion, isFalse);
        final future = provider.createQuestion(_questionInput());
        expect(provider.isCreatingQuestion, isTrue);
        await future;
        expect(provider.isCreatingQuestion, isFalse);
      },
    );

    test('is blocked locally (no request) for a published quiz', () async {
      repository.loadResult = _quiz(assessmentId: 7, status: 'published');
      await provider.loadQuiz(7);

      final success = await provider.createQuestion(_questionInput());

      expect(success, isFalse);
      expect(repository.createCallCount, 0);
      expect(
        provider.actionErrorMessage,
        'Published quizzes cannot be modified',
      );
    });

    test('returns false when no quiz is loaded yet', () async {
      final success = await provider.createQuestion(_questionInput());

      expect(success, isFalse);
      expect(repository.createCallCount, 0);
    });
  });

  group('updateQuestion', () {
    test('success patches the matching question in place', () async {
      repository.loadResult = _quiz(
        assessmentId: 7,
        questions: [_question(id: 1, correctAnswer: 'Paris')],
      );
      await provider.loadQuiz(7);
      repository.updateResult = _question(id: 1, correctAnswer: 'Berlin');

      final success = await provider.updateQuestion(
        questionId: 1,
        input: _questionInput(correctAnswer: 'Berlin'),
      );

      expect(success, isTrue);
      expect(provider.quiz!.questions.single.correctAnswer, 'Berlin');
    });

    test('leaves other questions untouched', () async {
      repository.loadResult = _quiz(
        assessmentId: 7,
        questions: [
          _question(id: 1, position: 0),
          _question(id: 2, position: 1, prompt: 'Second question'),
        ],
      );
      await provider.loadQuiz(7);
      repository.updateResult = _question(id: 1, correctAnswer: 'Berlin');

      await provider.updateQuestion(
        questionId: 1,
        input: _questionInput(correctAnswer: 'Berlin'),
      );

      expect(provider.quiz!.questions, hasLength(2));
      expect(
        provider.quiz!.questions.firstWhere((q) => q.id == 2).prompt,
        'Second question',
      );
    });

    test('per-question busy state guards a duplicate submit', () async {
      repository.loadResult = _quiz(
        assessmentId: 7,
        questions: [_question(id: 1)],
      );
      await provider.loadQuiz(7);
      repository.updateError = ApiException('slow');

      expect(provider.isBusyQuestion(1), isFalse);
      final future = provider.updateQuestion(
        questionId: 1,
        input: _questionInput(),
      );
      expect(provider.isBusyQuestion(1), isTrue);
      await future;
      expect(provider.isBusyQuestion(1), isFalse);
    });

    test('is blocked locally for a published quiz', () async {
      repository.loadResult = _quiz(
        assessmentId: 7,
        status: 'published',
        questions: [_question(id: 1)],
      );
      await provider.loadQuiz(7);

      final success = await provider.updateQuestion(
        questionId: 1,
        input: _questionInput(),
      );

      expect(success, isFalse);
      expect(repository.updateCallCount, 0);
    });

    test('API failure preserves the previous question data', () async {
      repository.loadResult = _quiz(
        assessmentId: 7,
        questions: [_question(id: 1, correctAnswer: 'Paris')],
      );
      await provider.loadQuiz(7);
      repository.updateError = ApiException('Server error.');

      await provider.updateQuestion(
        questionId: 1,
        input: _questionInput(correctAnswer: 'Berlin'),
      );

      expect(provider.quiz!.questions.single.correctAnswer, 'Paris');
    });
  });

  group('deleteQuestion', () {
    test('success removes the matching question', () async {
      repository.loadResult = _quiz(
        assessmentId: 7,
        questions: [_question(id: 1), _question(id: 2, position: 1)],
      );
      await provider.loadQuiz(7);

      final success = await provider.deleteQuestion(1);

      expect(success, isTrue);
      expect(provider.quiz!.questions, hasLength(1));
      expect(provider.quiz!.questions.single.id, 2);
    });

    test('per-question busy state guards a duplicate submit', () async {
      repository.loadResult = _quiz(
        assessmentId: 7,
        questions: [_question(id: 1)],
      );
      await provider.loadQuiz(7);
      repository.deleteError = ApiException('slow');

      final first = provider.deleteQuestion(1);
      final second = provider.deleteQuestion(1);
      final results = await Future.wait([first, second]);

      expect(repository.deleteCallCount, 1);
      expect(results.where((success) => success).length, 0);
    });

    test('is blocked locally for a published quiz', () async {
      repository.loadResult = _quiz(
        assessmentId: 7,
        status: 'published',
        questions: [_question(id: 1)],
      );
      await provider.loadQuiz(7);

      final success = await provider.deleteQuestion(1);

      expect(success, isFalse);
      expect(repository.deleteCallCount, 0);
      expect(provider.quiz!.questions, hasLength(1));
    });

    test('API failure preserves the question', () async {
      repository.loadResult = _quiz(
        assessmentId: 7,
        questions: [_question(id: 1)],
      );
      await provider.loadQuiz(7);
      repository.deleteError = ApiException('Server error.');

      await provider.deleteQuestion(1);

      expect(provider.quiz!.questions, hasLength(1));
    });
  });

  group('publish', () {
    test('success replaces quiz with the published result', () async {
      repository.loadResult = _quiz(
        assessmentId: 7,
        questions: [_question(id: 1)],
      );
      await provider.loadQuiz(7);
      repository.publishResult = _quiz(
        assessmentId: 7,
        status: 'published',
        questions: [_question(id: 1)],
        assessmentStatus: 'scheduled',
      );

      final success = await provider.publish();

      expect(success, isTrue);
      expect(provider.quiz!.status, 'published');
      expect(provider.quiz!.assessmentStatus, 'scheduled');
    });

    test(
      'does not trigger a reload of the quiz (no extra getOrganizationQuiz call)',
      () async {
        repository.loadResult = _quiz(
          assessmentId: 7,
          questions: [_question(id: 1)],
        );
        await provider.loadQuiz(7);
        repository.publishResult = _quiz(assessmentId: 7, status: 'published');

        await provider.publish();

        expect(repository.getQuizCallCount, 1);
      },
    );

    test(
      'zero-question 422 preserves draft state and shows the backend message',
      () async {
        repository.loadResult = _quiz(assessmentId: 7);
        await provider.loadQuiz(7);
        repository.publishError = ApiException(
          'A quiz must have at least one question before it can be published',
          statusCode: 422,
        );

        final success = await provider.publish();

        expect(success, isFalse);
        expect(
          provider.actionErrorMessage,
          'A quiz must have at least one question before it can be published',
        );
        expect(provider.quiz!.status, 'draft');
      },
    );

    test('isPublishing is set during the request and cleared after', () async {
      repository.loadResult = _quiz(
        assessmentId: 7,
        questions: [_question(id: 1)],
      );
      await provider.loadQuiz(7);
      repository.publishResult = _quiz(assessmentId: 7, status: 'published');

      expect(provider.isPublishing, isFalse);
      final future = provider.publish();
      expect(provider.isPublishing, isTrue);
      await future;
      expect(provider.isPublishing, isFalse);
    });

    test(
      'an already-published quiz is blocked locally (no duplicate request)',
      () async {
        repository.loadResult = _quiz(assessmentId: 7, status: 'published');
        await provider.loadQuiz(7);

        final success = await provider.publish();

        expect(success, isFalse);
        expect(repository.publishCallCount, 0);
      },
    );

    test('a duplicate publish tap while one is in flight is blocked', () async {
      repository.loadResult = _quiz(
        assessmentId: 7,
        questions: [_question(id: 1)],
      );
      await provider.loadQuiz(7);
      repository.publishResult = _quiz(assessmentId: 7, status: 'published');

      final first = provider.publish();
      final second = provider.publish();
      final results = await Future.wait([first, second]);

      expect(repository.publishCallCount, 1);
      expect(results.where((success) => success).length, 1);
    });
  });

  test('clearActionErrors clears both action error and field errors', () async {
    repository.loadResult = _quiz(assessmentId: 7);
    await provider.loadQuiz(7);
    repository.createError = ApiException(
      'The given data was invalid.',
      statusCode: 422,
      errors: {
        'prompt': ['required'],
      },
    );
    await provider.createQuestion(_questionInput());
    expect(provider.actionErrorMessage, isNotNull);
    expect(provider.fieldErrors, isNotEmpty);

    provider.clearActionErrors();

    expect(provider.actionErrorMessage, isNull);
    expect(provider.fieldErrors, isEmpty);
  });

  test('reset clears all state (called on logout)', () async {
    repository.loadResult = _quiz(assessmentId: 7);
    await provider.loadQuiz(7);
    expect(provider.quiz, isNotNull);

    await authProvider.logout();

    expect(provider.quiz, isNull);
    expect(provider.loadedAssessmentId, isNull);
    expect(provider.isLoading, isFalse);
    expect(provider.errorMessage, isNull);
    expect(provider.actionErrorMessage, isNull);
    expect(provider.fieldErrors, isEmpty);
    expect(provider.busyQuestionIds, isEmpty);
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
