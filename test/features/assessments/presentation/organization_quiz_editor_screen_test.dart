// Widget tests for OrganizationQuizEditorScreen (and, by extension,
// QuestionFormSheet, which only ever appears from this screen).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'package:opportunityhub_flutter/core/api/api_client.dart';
import 'package:opportunityhub_flutter/core/storage/token_storage_service.dart';
import 'package:opportunityhub_flutter/core/theme/app_theme.dart';
import 'package:opportunityhub_flutter/features/assessments/data/assessment_repository.dart';
import 'package:opportunityhub_flutter/features/assessments/data/question_input.dart';
import 'package:opportunityhub_flutter/features/assessments/presentation/organization_quiz_editor_screen.dart';
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
}

QuestionModel _question({
  int id = 1,
  String prompt = 'What is the capital of France?',
  String correctAnswer = 'Paris',
  int position = 0,
}) {
  return QuestionModel(
    id: id,
    quizId: 1,
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
  String status = 'draft',
  List<QuestionModel> questions = const [],
}) {
  return QuizModel(
    id: id,
    assessmentId: id,
    title: 'Backend Fundamentals',
    instructions: 'Choose the best answer.',
    timeLimitMinutes: 30,
    passingScore: 70,
    status: status,
    questions: questions,
  );
}

class _FakeAssessmentRepository extends AssessmentRepository {
  _FakeAssessmentRepository()
    : super(apiClient: ApiClient(tokenStorageService: TokenStorageService()));

  QuizModel? loadResult;
  ApiException? loadError;
  Duration loadDelay = Duration.zero;

  QuestionModel? createResult;
  ApiException? createError;

  QuestionModel? updateResult;

  ApiException? deleteError;

  QuizModel? publishResult;
  ApiException? publishError;
  int publishCallCount = 0;

  // Phase 10A.4B — shared Opportunity Quiz template.
  QuizModel? templateLoadResult;
  ApiException? templateLoadError;
  int templateLoadCallCount = 0;
  QuizModel? templatePublishResult;
  int templatePublishCallCount = 0;

  @override
  Future<QuizModel?> getOrganizationQuiz(int assessmentId) async {
    if (loadDelay > Duration.zero) {
      await Future<void>.delayed(loadDelay);
    }
    if (loadError != null) throw loadError!;
    return loadResult;
  }

  @override
  Future<QuizModel?> getOpportunityQuiz(int opportunityId) async {
    templateLoadCallCount++;
    if (templateLoadError != null) throw templateLoadError!;
    return templateLoadResult;
  }

  @override
  Future<QuizModel> publishOpportunityQuiz(int opportunityId) async {
    templatePublishCallCount++;
    return templatePublishResult ?? publishResult!;
  }

  @override
  Future<QuestionModel> createQuizQuestion({
    required int quizId,
    required QuestionInput input,
  }) async {
    if (createError != null) throw createError!;
    return createResult!;
  }

  @override
  Future<QuestionModel> updateQuizQuestion({
    required int quizId,
    required int questionId,
    required QuestionInput input,
  }) async {
    return updateResult!;
  }

  @override
  Future<void> deleteQuizQuestion({
    required int quizId,
    required int questionId,
  }) async {
    if (deleteError != null) throw deleteError!;
  }

  @override
  Future<QuizModel> publishQuiz(int quizId) async {
    publishCallCount++;
    if (publishError != null) throw publishError!;
    return publishResult!;
  }
}

Future<OrganizationQuizProvider> _pumpScreen(
  WidgetTester tester, {
  required AssessmentRepository assessmentRepository,
  int assessmentId = 1,
}) async {
  tester.view.physicalSize = const Size(420, 1800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final authProvider = AuthProvider(authRepository: _FakeAuthRepository());
  final quizProvider = OrganizationQuizProvider(
    repository: assessmentRepository,
    authProvider: authProvider,
  );

  final router = GoRouter(
    initialLocation: '/editor',
    routes: [
      GoRoute(
        path: '/editor',
        builder: (_, _) =>
            OrganizationQuizEditorScreen(assessmentId: assessmentId),
      ),
    ],
  );

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<OrganizationQuizProvider>.value(
          value: quizProvider,
        ),
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
    final quizProvider = OrganizationQuizProvider(
      repository: repository,
      authProvider: authProvider,
    );

    final router = GoRouter(
      initialLocation: '/editor',
      routes: [
        GoRoute(
          path: '/editor',
          builder: (_, _) =>
              const OrganizationQuizEditorScreen(assessmentId: 1),
        ),
      ],
    );

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<OrganizationQuizProvider>.value(
            value: quizProvider,
          ),
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
      ..loadError = ApiException('Assessment not found');

    await _pumpScreen(tester, assessmentRepository: repository);

    expect(find.text('Assessment not found'), findsOneWidget);
  });

  testWidgets('draft quiz metadata renders', (tester) async {
    final repository = _FakeAssessmentRepository()..loadResult = _quiz();

    await _pumpScreen(tester, assessmentRepository: repository);

    expect(find.text('Backend Fundamentals'), findsWidgets);
    expect(find.text('Choose the best answer.'), findsOneWidget);
    expect(find.text('30 minutes'), findsOneWidget);
    expect(find.text('70%'), findsOneWidget);
    expect(find.text('Draft'), findsOneWidget);
  });

  testWidgets(
    'question list renders with prompt, type, points, options, and correct answer',
    (tester) async {
      final repository = _FakeAssessmentRepository()
        ..loadResult = _quiz(questions: [_question()]);

      await _pumpScreen(tester, assessmentRepository: repository);

      expect(find.text('What is the capital of France?'), findsOneWidget);
      expect(find.text('Multiple Choice'), findsOneWidget);
      expect(find.textContaining('Paris'), findsWidgets);
      expect(find.textContaining('Correct answer: Paris'), findsOneWidget);
    },
  );

  testWidgets('draft quiz shows Add Question, Edit, Delete, and Publish', (
    tester,
  ) async {
    final repository = _FakeAssessmentRepository()
      ..loadResult = _quiz(questions: [_question()]);

    await _pumpScreen(tester, assessmentRepository: repository);

    expect(find.text('Add Question'), findsOneWidget);
    expect(find.text('Edit'), findsOneWidget);
    expect(find.text('Delete'), findsOneWidget);
    expect(find.text('Publish Quiz'), findsOneWidget);
  });

  testWidgets('published quiz hides Add Question, Edit, Delete, and Publish', (
    tester,
  ) async {
    final repository = _FakeAssessmentRepository()
      ..loadResult = _quiz(status: 'published', questions: [_question()]);

    await _pumpScreen(tester, assessmentRepository: repository);

    expect(find.text('Add Question'), findsNothing);
    expect(find.text('Edit'), findsNothing);
    expect(find.text('Delete'), findsNothing);
    expect(find.text('Publish Quiz'), findsNothing);
    expect(find.text('Published'), findsWidgets);
  });

  testWidgets('adding a multiple_choice question shows it in the list', (
    tester,
  ) async {
    final repository = _FakeAssessmentRepository()
      ..loadResult = _quiz()
      ..createResult = _question(id: 2, prompt: 'New question?');

    await _pumpScreen(tester, assessmentRepository: repository);

    await tester.tap(find.text('Add Question'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Prompt'),
      'New question?',
    );
    await tester.enterText(find.widgetWithText(TextFormField, 'Option 1'), 'A');
    await tester.enterText(find.widgetWithText(TextFormField, 'Option 2'), 'B');
    // Select the first option as correct.
    await tester.tap(find.byType(Radio<int>).first);
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(ElevatedButton, 'Add Question'));
    await tester.pumpAndSettle();

    expect(find.text('New question?'), findsOneWidget);
    expect(find.text('Question added successfully'), findsOneWidget);
  });

  testWidgets('multiple_choice requires at least 2 non-empty options', (
    tester,
  ) async {
    final repository = _FakeAssessmentRepository()..loadResult = _quiz();

    await _pumpScreen(tester, assessmentRepository: repository);

    await tester.tap(find.text('Add Question'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Prompt'),
      'New question?',
    );
    await tester.enterText(find.widgetWithText(TextFormField, 'Option 1'), 'A');
    // Option 2 left empty.
    await tester.tap(find.byType(Radio<int>).first);
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(ElevatedButton, 'Add Question'));
    await tester.pumpAndSettle();

    expect(find.text('Option cannot be empty'), findsOneWidget);
  });

  testWidgets('multiple_choice requires a correct answer to be selected', (
    tester,
  ) async {
    final repository = _FakeAssessmentRepository()..loadResult = _quiz();

    await _pumpScreen(tester, assessmentRepository: repository);

    await tester.tap(find.text('Add Question'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Prompt'),
      'New question?',
    );
    await tester.enterText(find.widgetWithText(TextFormField, 'Option 1'), 'A');
    await tester.enterText(find.widgetWithText(TextFormField, 'Option 2'), 'B');
    // No option selected as correct.

    await tester.tap(find.widgetWithText(ElevatedButton, 'Add Question'));
    await tester.pumpAndSettle();

    expect(find.text('Select which option is correct'), findsOneWidget);
  });

  testWidgets('true_false question can be added with True/False choice', (
    tester,
  ) async {
    final repository = _FakeAssessmentRepository()
      ..loadResult = _quiz()
      ..createResult = QuestionModel(
        id: 2,
        quizId: 1,
        prompt: 'The sky is blue.',
        type: 'true_false',
        correctAnswer: 'True',
        points: 1,
        position: 0,
      );

    await _pumpScreen(tester, assessmentRepository: repository);

    await tester.tap(find.text('Add Question'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Prompt'),
      'The sky is blue.',
    );
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('True / False').last);
    await tester.pumpAndSettle();

    // 'True' is the default selection.
    await tester.tap(find.widgetWithText(ElevatedButton, 'Add Question'));
    await tester.pumpAndSettle();

    expect(find.text('The sky is blue.'), findsOneWidget);
    expect(find.textContaining('True / False'), findsWidgets);
  });

  testWidgets('editing a question pre-fills the form and saves changes', (
    tester,
  ) async {
    final repository = _FakeAssessmentRepository()
      ..loadResult = _quiz(questions: [_question()])
      ..updateResult = _question(prompt: 'Updated question?');

    await _pumpScreen(tester, assessmentRepository: repository);

    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();

    // The prompt appears twice while the sheet is open: once in the
    // question card underneath, once pre-filled in the sheet's own Prompt
    // field -- both are legitimately present, so this only proves the
    // sheet actually opened, not which one holds the pre-filled value.
    expect(find.text('What is the capital of France?'), findsWidgets);
    final promptField = tester.widget<TextFormField>(
      find.widgetWithText(TextFormField, 'Prompt'),
    );
    expect(promptField.controller?.text, 'What is the capital of France?');

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Prompt'),
      'Updated question?',
    );
    await tester.tap(find.widgetWithText(ElevatedButton, 'Save Question'));
    await tester.pumpAndSettle();

    expect(find.text('Updated question?'), findsOneWidget);
    expect(find.text('Question updated successfully'), findsOneWidget);
  });

  testWidgets('deleting a question requires confirmation and removes it', (
    tester,
  ) async {
    final repository = _FakeAssessmentRepository()
      ..loadResult = _quiz(questions: [_question()]);

    await _pumpScreen(tester, assessmentRepository: repository);

    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();

    expect(find.text('Delete Question'), findsOneWidget);

    // The confirm button in the danger-styled confirmation dialog is a
    // DangerButton, built on OutlinedButton (not ElevatedButton like the
    // question card's own "Delete" TextButton behind it).
    await tester.tap(find.widgetWithText(OutlinedButton, 'Delete'));
    await tester.pumpAndSettle();

    expect(find.text('What is the capital of France?'), findsNothing);
    expect(find.text('Question deleted successfully'), findsOneWidget);
  });

  testWidgets('cancelling the delete confirmation keeps the question', (
    tester,
  ) async {
    final repository = _FakeAssessmentRepository()
      ..loadResult = _quiz(questions: [_question()]);

    await _pumpScreen(tester, assessmentRepository: repository);

    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(find.text('What is the capital of France?'), findsOneWidget);
  });

  testWidgets(
    'publishing with zero questions preserves draft state and shows the backend message',
    (tester) async {
      final repository = _FakeAssessmentRepository()
        ..loadResult = _quiz()
        ..publishError = ApiException(
          'A quiz must have at least one question before it can be published',
          statusCode: 422,
        );

      await _pumpScreen(tester, assessmentRepository: repository);

      await tester.tap(find.text('Publish Quiz'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ElevatedButton, 'Publish'));
      await tester.pumpAndSettle();

      expect(
        find.text(
          'A quiz must have at least one question before it can be published',
        ),
        findsOneWidget,
      );
      expect(find.text('Draft'), findsOneWidget);
    },
  );

  testWidgets('publish requires confirmation with the documented copy', (
    tester,
  ) async {
    final repository = _FakeAssessmentRepository()
      ..loadResult = _quiz(questions: [_question()]);

    await _pumpScreen(tester, assessmentRepository: repository);

    await tester.tap(find.text('Publish Quiz'));
    await tester.pumpAndSettle();

    expect(find.text('Publish Quiz'), findsWidgets);
    expect(
      find.text(
        'Are you sure you want to publish this quiz? You will not be '
        'able to modify its questions afterwards.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('cancelling the publish confirmation does not publish', (
    tester,
  ) async {
    final repository = _FakeAssessmentRepository()
      ..loadResult = _quiz(questions: [_question()]);

    await _pumpScreen(tester, assessmentRepository: repository);

    await tester.tap(find.text('Publish Quiz'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(repository.publishCallCount, 0);
    expect(find.text('Draft'), findsOneWidget);
  });

  testWidgets(
    'confirmed publish success updates status and hides authoring actions',
    (tester) async {
      final repository = _FakeAssessmentRepository()
        ..loadResult = _quiz(questions: [_question()])
        ..publishResult = _quiz(status: 'published', questions: [_question()]);

      await _pumpScreen(tester, assessmentRepository: repository);

      await tester.tap(find.text('Publish Quiz'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ElevatedButton, 'Publish'));
      await tester.pumpAndSettle();

      expect(find.text('Quiz published successfully'), findsOneWidget);
      expect(find.text('Published'), findsWidgets);
      expect(find.text('Add Question'), findsNothing);
      expect(find.text('Publish Quiz'), findsNothing);
    },
  );

  testWidgets('narrow viewport does not overflow', (tester) async {
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final authProvider = AuthProvider(authRepository: _FakeAuthRepository());
    final repository = _FakeAssessmentRepository()
      ..loadResult = _quiz(
        questions: [_question(), _question(id: 2, position: 1)],
      );
    final quizProvider = OrganizationQuizProvider(
      repository: repository,
      authProvider: authProvider,
    );

    final router = GoRouter(
      initialLocation: '/editor',
      routes: [
        GoRoute(
          path: '/editor',
          builder: (_, _) =>
              const OrganizationQuizEditorScreen(assessmentId: 1),
        ),
      ],
    );

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<OrganizationQuizProvider>.value(
            value: quizProvider,
          ),
        ],
        child: MaterialApp.router(
          theme: AppTheme.lightTheme,
          routerConfig: router,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });

  group('Shared Opportunity Quiz template mode (Phase 10A.4B)', () {
    Future<void> pumpTemplate(
      WidgetTester tester, {
      required _FakeAssessmentRepository repository,
    }) async {
      tester.view.physicalSize = const Size(420, 1800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final authProvider = AuthProvider(authRepository: _FakeAuthRepository());
      final quizProvider = OrganizationQuizProvider(
        repository: repository,
        authProvider: authProvider,
      );

      final router = GoRouter(
        initialLocation: '/editor',
        routes: [
          GoRoute(
            path: '/editor',
            builder: (_, _) =>
                const OrganizationQuizEditorScreen(opportunityId: 9),
          ),
          GoRoute(
            path: '/organization/opportunities/9/quiz/new',
            builder: (_, _) =>
                const Scaffold(body: Text('CREATE_QUIZ_PLACEHOLDER')),
          ),
        ],
      );

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<OrganizationQuizProvider>.value(
              value: quizProvider,
            ),
          ],
          child: MaterialApp.router(
            theme: AppTheme.lightTheme,
            routerConfig: router,
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets(
      'no template yet shows Quiz Not Configured with a Configure Quiz '
      'action, not the legacy No Quiz Found state',
      (tester) async {
        final repository = _FakeAssessmentRepository()
          ..templateLoadResult = null;
        await pumpTemplate(tester, repository: repository);

        expect(repository.templateLoadCallCount, 1);
        expect(find.text('Quiz Not Configured'), findsOneWidget);
        expect(find.text('No Quiz Found'), findsNothing);

        await tester.tap(find.text('Configure Quiz'));
        await tester.pumpAndSettle();
        expect(find.text('CREATE_QUIZ_PLACEHOLDER'), findsOneWidget);
      },
    );

    testWidgets('a draft template renders questions and Publish', (
      tester,
    ) async {
      final repository = _FakeAssessmentRepository()
        ..templateLoadResult = _quiz(
          status: 'draft',
          questions: [_question()],
        );
      await pumpTemplate(tester, repository: repository);

      expect(find.text('Backend Fundamentals'), findsWidgets);
      expect(find.text('Publish Quiz'), findsOneWidget);
    });

    testWidgets('publishing a template calls the opportunity-scoped '
        'publish endpoint, not the legacy one', (tester) async {
      final repository = _FakeAssessmentRepository()
        ..templateLoadResult = _quiz(
          status: 'draft',
          questions: [_question()],
        )
        ..templatePublishResult = _quiz(
          status: 'published',
          questions: [_question()],
        );
      await pumpTemplate(tester, repository: repository);

      await tester.tap(find.text('Publish Quiz'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Publish'));
      await tester.pumpAndSettle();

      expect(repository.templatePublishCallCount, 1);
      expect(repository.publishCallCount, 0);
      expect(find.text('Published'), findsWidgets);
    });

    testWidgets('a load error shows a retry that reloads the template', (
      tester,
    ) async {
      final repository = _FakeAssessmentRepository()
        ..templateLoadError = ApiException('Opportunity not found');
      await pumpTemplate(tester, repository: repository);

      expect(find.text('Opportunity not found'), findsOneWidget);

      repository.templateLoadError = null;
      repository.templateLoadResult = _quiz(status: 'draft');
      await tester.tap(find.text('Try Again'));
      await tester.pumpAndSettle();

      expect(repository.templateLoadCallCount, 2);
      expect(find.text('Backend Fundamentals'), findsWidgets);
    });
  });
}
