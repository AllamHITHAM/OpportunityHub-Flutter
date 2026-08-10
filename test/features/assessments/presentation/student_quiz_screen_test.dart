// Widget tests for StudentQuizScreen.
//
// IMPORTANT about timers: `testWidgets` runs inside a FakeAsync zone, so
// StudentQuizProvider's `Timer.periodic` countdown is virtualized, not
// real-time. `pumpAndSettle()` keeps advancing virtual time until no more
// frames are scheduled — with a *live* (non-expired, time-limited) periodic
// timer still running, that would mean pumping through the entire quiz time
// limit, which is slow and fragile. Any test that starts a non-expired,
// time-limited attempt therefore uses plain `pump()` calls (never
// `pumpAndSettle()`) after starting, and explicitly disposes the provider
// via `addTearDown` so the timer is cancelled before the test's FakeAsync
// zone is torn down. An *already*-expired attempt never creates a periodic
// timer at all (the first synchronous tick cancels it immediately), so
// those tests remain free to use `pumpAndSettle()` throughout.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'package:opportunityhub_flutter/core/api/api_client.dart';
import 'package:opportunityhub_flutter/core/storage/token_storage_service.dart';
import 'package:opportunityhub_flutter/core/theme/app_theme.dart';
import 'package:opportunityhub_flutter/features/assessments/data/assessment_repository.dart';
import 'package:opportunityhub_flutter/features/assessments/presentation/student_quiz_screen.dart';
import 'package:opportunityhub_flutter/features/auth/data/auth_repository.dart';
import 'package:opportunityhub_flutter/models/assessment_model.dart';
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
}

QuestionModel _mcQuestion({int id = 1, int position = 0}) {
  return QuestionModel(
    id: id,
    quizId: 1,
    prompt: 'What is the capital of France?',
    type: 'multiple_choice',
    options: const ['Paris', 'London', 'Berlin'],
    points: 1,
    position: position,
  );
}

QuestionModel _tfQuestion({int id = 2, int position = 1}) {
  return QuestionModel(
    id: id,
    quizId: 1,
    prompt: 'The sky is blue.',
    type: 'true_false',
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
    instructions: 'Choose the best answer.',
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

AssessmentModel _assessment({
  int id = 1,
  int applicationId = 5,
  String status = 'completed',
  String? result,
}) {
  return AssessmentModel(
    id: id,
    applicationId: applicationId,
    type: 'quiz',
    status: status,
    result: result,
  );
}

class _FakeAssessmentRepository extends AssessmentRepository {
  _FakeAssessmentRepository()
    : super(apiClient: ApiClient(tokenStorageService: TokenStorageService()));

  QuizModel? loadResult;
  ApiException? loadError;
  Duration loadDelay = Duration.zero;

  QuizAttemptModel? startResult;
  ApiException? startError;

  QuizAttemptModel? submitResult;
  ApiException? submitError;

  AssessmentModel? assessmentResult;
  ApiException? assessmentError;
  int getStudentAssessmentCallCount = 0;

  @override
  Future<QuizModel> getStudentQuiz(int assessmentId) async {
    if (loadDelay > Duration.zero) {
      await Future<void>.delayed(loadDelay);
    }
    if (loadError != null) throw loadError!;
    return loadResult!;
  }

  @override
  Future<QuizAttemptModel> startStudentQuiz(int quizId) async {
    if (startError != null) throw startError!;
    return startResult!;
  }

  @override
  Future<QuizAttemptModel> submitStudentQuiz({
    required int quizId,
    required Map<int, String> answers,
  }) async {
    if (submitError != null) throw submitError!;
    return submitResult!;
  }

  @override
  Future<AssessmentModel> getStudentAssessment(int assessmentId) async {
    getStudentAssessmentCallCount++;
    if (assessmentError != null) throw assessmentError!;
    return assessmentResult!;
  }
}

Future<StudentQuizProvider> _pumpScreen(
  WidgetTester tester, {
  required _FakeAssessmentRepository repository,
  int assessmentId = 1,
}) async {
  tester.view.physicalSize = const Size(420, 1800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final authProvider = AuthProvider(authRepository: _FakeAuthRepository());
  final quizProvider = StudentQuizProvider(
    repository: repository,
    authProvider: authProvider,
  );

  final router = GoRouter(
    initialLocation: '/quiz',
    routes: [
      GoRoute(
        path: '/quiz',
        builder: (_, _) => StudentQuizScreen(assessmentId: assessmentId),
      ),
    ],
  );

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<StudentQuizProvider>.value(value: quizProvider),
        Provider<AssessmentRepository>.value(value: repository),
      ],
      child: MaterialApp.router(
        theme: AppTheme.lightTheme,
        routerConfig: router,
      ),
    ),
  );
  await tester.pumpAndSettle();

  return quizProvider;
}

void main() {
  testWidgets('loading state shows a spinner', (tester) async {
    tester.view.physicalSize = const Size(420, 1800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final authProvider = AuthProvider(authRepository: _FakeAuthRepository());
    final repository = _FakeAssessmentRepository()
      ..loadResult = _quiz()
      ..loadDelay = const Duration(milliseconds: 100);
    final quizProvider = StudentQuizProvider(
      repository: repository,
      authProvider: authProvider,
    );

    final router = GoRouter(
      initialLocation: '/quiz',
      routes: [
        GoRoute(
          path: '/quiz',
          builder: (_, _) => const StudentQuizScreen(assessmentId: 1),
        ),
      ],
    );

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<StudentQuizProvider>.value(
            value: quizProvider,
          ),
          Provider<AssessmentRepository>.value(value: repository),
        ],
        child: MaterialApp.router(
          theme: AppTheme.lightTheme,
          routerConfig: router,
        ),
      ),
    );
    // Deliberately not pumpAndSettle -- catches the loading frame before
    // the (artificially delayed) fetch resolves.
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await tester.pumpAndSettle();
  });

  testWidgets('error state shows a retry option', (tester) async {
    final repository = _FakeAssessmentRepository()
      ..loadError = ApiException('Quiz not found');

    await _pumpScreen(tester, repository: repository);

    expect(find.text('Quiz not found'), findsOneWidget);
  });

  group('intro', () {
    testWidgets('shows quiz metadata and the one-attempt explanation', (
      tester,
    ) async {
      final repository = _FakeAssessmentRepository()
        ..loadResult = _quiz(timeLimitMinutes: 30, questions: [_mcQuestion()]);

      await _pumpScreen(tester, repository: repository);

      expect(find.text('Backend Fundamentals'), findsWidgets);
      expect(find.text('Choose the best answer.'), findsOneWidget);
      expect(find.text('1'), findsOneWidget); // Questions count.
      expect(find.text('70%'), findsOneWidget);
      expect(find.text('30 minutes'), findsOneWidget);
      expect(find.textContaining('one attempt'), findsOneWidget);
      expect(find.text('Start Quiz'), findsOneWidget);
    });

    testWidgets('shows "No time limit" when the quiz has none', (tester) async {
      final repository = _FakeAssessmentRepository()
        ..loadResult = _quiz(timeLimitMinutes: null);

      await _pumpScreen(tester, repository: repository);

      expect(find.text('No time limit'), findsOneWidget);
    });
  });

  group('starting the quiz (no time limit — safe to pumpAndSettle)', () {
    testWidgets('tapping Start Quiz shows the question form', (tester) async {
      final repository = _FakeAssessmentRepository()
        ..loadResult = _quiz(
          timeLimitMinutes: null,
          questions: [_mcQuestion(), _tfQuestion()],
        )
        ..startResult = _attempt();

      await _pumpScreen(tester, repository: repository);

      await tester.tap(find.text('Start Quiz'));
      await tester.pumpAndSettle();

      expect(find.text('What is the capital of France?'), findsOneWidget);
      expect(find.text('The sky is blue.'), findsOneWidget);
      expect(find.text('0 of 2 answered'), findsOneWidget);
      expect(find.text('Start Quiz'), findsNothing);
    });

    testWidgets('no timer chip is shown when the quiz has no time limit', (
      tester,
    ) async {
      final repository = _FakeAssessmentRepository()
        ..loadResult = _quiz(timeLimitMinutes: null, questions: [_mcQuestion()])
        ..startResult = _attempt();

      await _pumpScreen(tester, repository: repository);
      await tester.tap(find.text('Start Quiz'));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.timer_outlined), findsNothing);
    });

    testWidgets('multiple_choice renders one selectable option per choice', (
      tester,
    ) async {
      final repository = _FakeAssessmentRepository()
        ..loadResult = _quiz(timeLimitMinutes: null, questions: [_mcQuestion()])
        ..startResult = _attempt();

      await _pumpScreen(tester, repository: repository);
      await tester.tap(find.text('Start Quiz'));
      await tester.pumpAndSettle();

      expect(find.text('Paris'), findsOneWidget);
      expect(find.text('London'), findsOneWidget);
      expect(find.text('Berlin'), findsOneWidget);
      expect(find.byType(RadioListTile<String>), findsNWidgets(3));
    });

    testWidgets('true_false renders exactly True and False', (tester) async {
      final repository = _FakeAssessmentRepository()
        ..loadResult = _quiz(timeLimitMinutes: null, questions: [_tfQuestion()])
        ..startResult = _attempt();

      await _pumpScreen(tester, repository: repository);
      await tester.tap(find.text('Start Quiz'));
      await tester.pumpAndSettle();

      expect(find.text('True'), findsOneWidget);
      expect(find.text('False'), findsOneWidget);
    });

    testWidgets('selecting an answer updates the answered count', (
      tester,
    ) async {
      final repository = _FakeAssessmentRepository()
        ..loadResult = _quiz(
          timeLimitMinutes: null,
          questions: [_mcQuestion(), _tfQuestion()],
        )
        ..startResult = _attempt();

      await _pumpScreen(tester, repository: repository);
      await tester.tap(find.text('Start Quiz'));
      await tester.pumpAndSettle();

      expect(find.text('0 of 2 answered'), findsOneWidget);

      await tester.tap(find.text('Paris'));
      await tester.pumpAndSettle();

      expect(find.text('1 of 2 answered'), findsOneWidget);
    });

    testWidgets('selecting a different option changes the selection', (
      tester,
    ) async {
      final repository = _FakeAssessmentRepository()
        ..loadResult = _quiz(timeLimitMinutes: null, questions: [_mcQuestion()])
        ..startResult = _attempt();

      await _pumpScreen(tester, repository: repository);
      await tester.tap(find.text('Start Quiz'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Paris'));
      await tester.pumpAndSettle();
      expect(find.text('1 of 1 answered'), findsOneWidget);

      await tester.tap(find.text('London'));
      await tester.pumpAndSettle();
      expect(find.text('1 of 1 answered'), findsOneWidget);
    });

    testWidgets('Submit Quiz is disabled until every question is answered', (
      tester,
    ) async {
      final repository = _FakeAssessmentRepository()
        ..loadResult = _quiz(
          timeLimitMinutes: null,
          questions: [_mcQuestion(), _tfQuestion()],
        )
        ..startResult = _attempt();

      await _pumpScreen(tester, repository: repository);
      await tester.tap(find.text('Start Quiz'));
      await tester.pumpAndSettle();

      ElevatedButton submitButton() => tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, 'Submit Quiz'),
      );

      expect(submitButton().onPressed, isNull);

      await tester.tap(find.text('Paris'));
      await tester.pumpAndSettle();
      expect(submitButton().onPressed, isNull);

      await tester.tap(find.text('True'));
      await tester.pumpAndSettle();
      expect(submitButton().onPressed, isNotNull);
    });

    testWidgets('the confirmation dialog uses the documented copy', (
      tester,
    ) async {
      final repository = _FakeAssessmentRepository()
        ..loadResult = _quiz(timeLimitMinutes: null, questions: [_mcQuestion()])
        ..startResult = _attempt();

      await _pumpScreen(tester, repository: repository);
      await tester.tap(find.text('Start Quiz'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Paris'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Submit Quiz'));
      await tester.pumpAndSettle();

      expect(find.text('Submit Quiz'), findsWidgets);
      expect(
        find.text(
          'Are you sure you want to submit your answers? You cannot retake '
          'this quiz.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('cancelling the confirmation does not submit', (tester) async {
      final repository = _FakeAssessmentRepository()
        ..loadResult = _quiz(timeLimitMinutes: null, questions: [_mcQuestion()])
        ..startResult = _attempt();

      await _pumpScreen(tester, repository: repository);
      await tester.tap(find.text('Start Quiz'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Paris'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Submit Quiz'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(find.text('Quiz Completed'), findsNothing);
      expect(find.text('Paris'), findsOneWidget);
    });

    testWidgets('confirmed submit shows a loading state, then the result', (
      tester,
    ) async {
      final repository = _FakeAssessmentRepository()
        ..loadResult = _quiz(timeLimitMinutes: null, questions: [_mcQuestion()])
        ..startResult = _attempt()
        ..submitResult = _attempt(
          answers: {1: 'Paris'},
          score: 100,
          submittedAt: DateTime.now(),
        )
        ..assessmentResult = _assessment(status: 'completed', result: 'passed');

      await _pumpScreen(tester, repository: repository);
      await tester.tap(find.text('Start Quiz'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Paris'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Submit Quiz'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ElevatedButton, 'Submit'));
      await tester.pumpAndSettle();

      expect(find.text('Quiz submitted successfully'), findsOneWidget);
      expect(find.text('Quiz Completed'), findsOneWidget);
      expect(find.text('Score'), findsOneWidget);
      expect(find.text('100%'), findsOneWidget);
      expect(find.text('Passed'), findsOneWidget);
    });

    testWidgets(
      'a submit failure keeps the student on the question form with their answer intact',
      (tester) async {
        final repository = _FakeAssessmentRepository()
          ..loadResult = _quiz(
            timeLimitMinutes: null,
            questions: [_mcQuestion()],
          )
          ..startResult = _attempt()
          ..submitError = ApiException('Server error.');

        await _pumpScreen(tester, repository: repository);
        await tester.tap(find.text('Start Quiz'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Paris'));
        await tester.pumpAndSettle();

        await tester.tap(find.text('Submit Quiz'));
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(ElevatedButton, 'Submit'));
        await tester.pumpAndSettle();

        // Shown both inline (persistent) and via a SnackBar (transient) --
        // both are legitimate simultaneous renderings of the same failure.
        expect(find.text('Server error.'), findsWidgets);
        expect(find.text('Quiz Completed'), findsNothing);
        expect(find.text('1 of 1 answered'), findsOneWidget);
      },
    );

    testWidgets(
      'result view falls back to a retry option if the refreshed assessment fails to load',
      (tester) async {
        final repository = _FakeAssessmentRepository()
          ..loadResult = _quiz(
            timeLimitMinutes: null,
            questions: [_mcQuestion()],
          )
          ..startResult = _attempt()
          ..submitResult = _attempt(
            answers: {1: 'Paris'},
            score: 60,
            submittedAt: DateTime.now(),
          )
          ..assessmentError = ApiException('Something went wrong.');

        await _pumpScreen(tester, repository: repository);
        await tester.tap(find.text('Start Quiz'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Paris'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Submit Quiz'));
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(ElevatedButton, 'Submit'));
        await tester.pumpAndSettle();

        expect(find.text('Quiz Completed'), findsOneWidget);
        expect(find.text('60%'), findsOneWidget);
        expect(find.text('Something went wrong.'), findsOneWidget);
        expect(find.text('Result'), findsNothing);
      },
    );

    testWidgets('never renders correctAnswer or any organization-only text', (
      tester,
    ) async {
      final repository = _FakeAssessmentRepository()
        ..loadResult = _quiz(
          timeLimitMinutes: null,
          questions: [_mcQuestion(), _tfQuestion()],
        )
        ..startResult = _attempt();

      await _pumpScreen(tester, repository: repository);
      await tester.tap(find.text('Start Quiz'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Correct answer'), findsNothing);
      expect(find.textContaining('correct_answer'), findsNothing);
      expect(find.text('✓'), findsNothing);
    });
  });

  testWidgets('starting an already-submitted quiz shows a safe message', (
    tester,
  ) async {
    final repository = _FakeAssessmentRepository()
      ..loadResult = _quiz(timeLimitMinutes: null, questions: [_mcQuestion()])
      ..startError = ApiException(
        'Quiz has already been submitted',
        statusCode: 409,
      );

    await _pumpScreen(tester, repository: repository);
    await tester.tap(find.text('Start Quiz'));
    await tester.pumpAndSettle();

    expect(find.text('You have already completed this quiz.'), findsOneWidget);
    expect(find.text('Start Quiz'), findsNothing);
  });

  group('time limit (uses plain pump, never pumpAndSettle, after start)', () {
    testWidgets(
      'an already-expired attempt shows Time expired and disables submit',
      (tester) async {
        final repository = _FakeAssessmentRepository()
          ..loadResult = _quiz(timeLimitMinutes: 30, questions: [_mcQuestion()])
          ..startResult = _attempt(
            startedAt: DateTime.now().subtract(const Duration(minutes: 40)),
          );

        // No live periodic timer is ever created here (the very first,
        // synchronous tick already finds the deadline in the past and
        // cancels itself), so pumpAndSettle remains safe throughout.
        await _pumpScreen(tester, repository: repository);
        await tester.tap(find.text('Start Quiz'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Paris'));
        await tester.pumpAndSettle();

        expect(find.text('Time expired'), findsOneWidget);
        expect(
          find.text('Time expired. You can no longer submit this quiz.'),
          findsOneWidget,
        );
        final submitButton = tester.widget<ElevatedButton>(
          find.widgetWithText(ElevatedButton, 'Submit Quiz'),
        );
        expect(submitButton.onPressed, isNull);
      },
    );

    testWidgets('a non-expired time limit shows a live countdown', (
      tester,
    ) async {
      final repository = _FakeAssessmentRepository()
        ..loadResult = _quiz(timeLimitMinutes: 30, questions: [_mcQuestion()])
        ..startResult = _attempt(
          startedAt: DateTime.now().subtract(const Duration(minutes: 10)),
        );

      final quizProvider = await _pumpScreen(tester, repository: repository);

      await tester.tap(find.text('Start Quiz'));
      // Deliberately plain pump() calls, never pumpAndSettle(), while a
      // live countdown timer is running.
      await tester.pump();
      await tester.pump();

      expect(find.byIcon(Icons.timer_outlined), findsOneWidget);
      expect(find.textContaining(':'), findsOneWidget);
      expect(find.text('Time expired'), findsNothing);

      // Cancels the still-running periodic timer *before* this test body
      // returns -- the binding's pending-timer check runs immediately
      // after, ahead of any `addTearDown` callback, so disposal must
      // happen here rather than in a teardown hook.
      quizProvider.dispose();
    });
  });

  testWidgets('narrow viewport does not overflow', (tester) async {
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final authProvider = AuthProvider(authRepository: _FakeAuthRepository());
    final repository = _FakeAssessmentRepository()
      ..loadResult = _quiz(
        timeLimitMinutes: null,
        questions: [_mcQuestion(), _tfQuestion()],
      )
      ..startResult = _attempt();
    final quizProvider = StudentQuizProvider(
      repository: repository,
      authProvider: authProvider,
    );

    final router = GoRouter(
      initialLocation: '/quiz',
      routes: [
        GoRoute(
          path: '/quiz',
          builder: (_, _) => const StudentQuizScreen(assessmentId: 1),
        ),
      ],
    );

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<StudentQuizProvider>.value(
            value: quizProvider,
          ),
          Provider<AssessmentRepository>.value(value: repository),
        ],
        child: MaterialApp.router(
          theme: AppTheme.lightTheme,
          routerConfig: router,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Start Quiz'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });
}
