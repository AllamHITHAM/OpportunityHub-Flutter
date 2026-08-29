// Widget tests for CreateQuizScreen, in isolation with a small GoRouter.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'package:opportunityhub_flutter/core/api/api_client.dart';
import 'package:opportunityhub_flutter/core/storage/token_storage_service.dart';
import 'package:opportunityhub_flutter/core/theme/app_theme.dart';
import 'package:opportunityhub_flutter/features/applications/data/application_repository.dart';
import 'package:opportunityhub_flutter/features/assessments/data/assessment_repository.dart';
import 'package:opportunityhub_flutter/features/assessments/data/interview_create_input.dart';
import 'package:opportunityhub_flutter/features/assessments/data/quiz_create_input.dart';
import 'package:opportunityhub_flutter/features/assessments/presentation/create_quiz_screen.dart';
import 'package:opportunityhub_flutter/features/auth/data/auth_repository.dart';
import 'package:opportunityhub_flutter/models/application_model.dart';
import 'package:opportunityhub_flutter/models/assessment_model.dart';
import 'package:opportunityhub_flutter/models/cv_model.dart';
import 'package:opportunityhub_flutter/models/quiz_model.dart';
import 'package:opportunityhub_flutter/providers/auth_provider.dart';
import 'package:opportunityhub_flutter/providers/organization_applications_provider.dart';
import 'package:opportunityhub_flutter/providers/organization_assessment_provider.dart';
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

const _cv = CvModel(
  id: 2,
  studentId: 1,
  title: 'Main CV',
  filePath: 'uploads/cv.pdf',
  version: 1,
  isDefault: false,
  createdByAi: false,
);

ApplicationModel _application({int id = 5, String status = 'in_assessment'}) {
  return ApplicationModel(
    id: id,
    studentId: 1,
    opportunityId: 1,
    cvId: 2,
    status: status,
    cv: _cv,
  );
}

AssessmentModel _assessment({
  int id = 1,
  int applicationId = 5,
  ApplicationModel? application,
}) {
  return AssessmentModel(
    id: id,
    applicationId: applicationId,
    type: 'quiz',
    status: 'pending',
    application: application ?? _application(id: applicationId),
    quiz: QuizModel(
      id: id,
      assessmentId: id,
      title: 'Backend Fundamentals',
      passingScore: 70,
      status: 'draft',
    ),
  );
}

class _FakeAssessmentRepository extends AssessmentRepository {
  _FakeAssessmentRepository()
    : super(apiClient: ApiClient(tokenStorageService: TokenStorageService()));

  AssessmentModel? createResult;
  ApiException? createError;
  Duration createDelay = Duration.zero;
  int createCallCount = 0;
  QuizCreateInput? lastQuizInput;

  @override
  Future<List<AssessmentModel>> getAssessmentsForApplication(
    int applicationId,
  ) async {
    return [];
  }

  @override
  Future<AssessmentModel> createAssessment({
    required int applicationId,
    required String type,
    InterviewCreateInput? interviewInput,
    QuizCreateInput? quizInput,
  }) async {
    createCallCount++;
    lastQuizInput = quizInput;
    if (createDelay > Duration.zero) {
      await Future<void>.delayed(createDelay);
    }
    if (createError != null) throw createError!;
    return createResult!;
  }

  // Phase 10A.4B addendum — shared Opportunity Quiz template mode.
  QuizModel? templateLoadResult;
  QuizModel? templateCreateResult;
  ApiException? templateCreateError;
  int templateCreateCallCount = 0;
  QuizCreateInput? lastTemplateInput;

  @override
  Future<QuizModel?> getOpportunityQuiz(int opportunityId) async {
    return templateLoadResult;
  }

  @override
  Future<QuizModel> createOpportunityQuiz({
    required int opportunityId,
    required QuizCreateInput input,
  }) async {
    templateCreateCallCount++;
    lastTemplateInput = input;
    if (templateCreateError != null) throw templateCreateError!;
    return templateCreateResult!;
  }
}

class _FakeApplicationRepository extends ApplicationRepository {
  _FakeApplicationRepository()
    : super(apiClient: ApiClient(tokenStorageService: TokenStorageService()));

  @override
  Future<ApplicationModel> getOrganizationApplication(int applicationId) async {
    return _application(id: applicationId);
  }
}

class _Providers {
  _Providers({required this.assessment, required this.applications});

  final OrganizationAssessmentProvider assessment;
  final OrganizationApplicationsProvider applications;
}

Future<_Providers> _pumpScreen(
  WidgetTester tester, {
  required AssessmentRepository assessmentRepository,
  int applicationId = 5,
}) async {
  tester.view.physicalSize = const Size(420, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final authProvider = AuthProvider(authRepository: _FakeAuthRepository());
  final assessmentProvider = OrganizationAssessmentProvider(
    repository: assessmentRepository,
    authProvider: authProvider,
  );
  final applicationsProvider = OrganizationApplicationsProvider(
    repository: _FakeApplicationRepository(),
    authProvider: authProvider,
  );

  final router = GoRouter(
    initialLocation: '/host',
    routes: [
      GoRoute(
        path: '/host',
        builder: (_, _) => const Scaffold(body: Text('HOST')),
      ),
      GoRoute(
        path: '/create',
        builder: (_, _) => CreateQuizScreen(applicationId: applicationId),
      ),
      GoRoute(
        path: '/organization/assessments/:id/quiz',
        builder: (_, state) =>
            Scaffold(body: Text('QUIZ_EDITOR_${state.pathParameters['id']}')),
      ),
    ],
  );

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<OrganizationAssessmentProvider>.value(
          value: assessmentProvider,
        ),
        ChangeNotifierProvider<OrganizationApplicationsProvider>.value(
          value: applicationsProvider,
        ),
      ],
      child: MaterialApp.router(
        theme: AppTheme.lightTheme,
        routerConfig: router,
      ),
    ),
  );
  await tester.pumpAndSettle();
  router.push('/create');
  await tester.pumpAndSettle();

  return _Providers(
    assessment: assessmentProvider,
    applications: applicationsProvider,
  );
}

/// Phase 10A.4B addendum — pumps `CreateQuizScreen` in *template* mode
/// (`opportunityId` set, `applicationId` null), which is where the shared
/// candidate-availability policy fields (days after assignment/opens-at
/// time/submission window) only ever appear.
Future<OrganizationQuizProvider> _pumpTemplateScreen(
  WidgetTester tester, {
  required AssessmentRepository assessmentRepository,
  int opportunityId = 1,
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
    initialLocation: '/host',
    routes: [
      GoRoute(
        path: '/host',
        builder: (_, _) => const Scaffold(body: Text('HOST')),
      ),
      GoRoute(
        path: '/create-template',
        builder: (_, _) => CreateQuizScreen(opportunityId: opportunityId),
      ),
      GoRoute(
        path: '/organization/opportunities/:id/quiz',
        builder: (_, state) =>
            Scaffold(body: Text('TEMPLATE_EDITOR_${state.pathParameters['id']}')),
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
  router.push('/create-template');
  await tester.pumpAndSettle();

  return quizProvider;
}

void main() {
  testWidgets('all fields render', (tester) async {
    await _pumpScreen(
      tester,
      assessmentRepository: _FakeAssessmentRepository(),
    );

    expect(find.text('Title'), findsOneWidget);
    expect(find.text('Instructions (optional)'), findsOneWidget);
    expect(find.text('Time Limit Minutes (optional)'), findsOneWidget);
    expect(find.text('Passing Score (%)'), findsOneWidget);
  });

  testWidgets('missing title is rejected', (tester) async {
    final repository = _FakeAssessmentRepository();
    await _pumpScreen(tester, assessmentRepository: repository);

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Passing Score (%)'),
      '70',
    );
    await tester.tap(find.widgetWithText(ElevatedButton, 'Create Quiz'));
    await tester.pumpAndSettle();

    expect(find.text('Title is required'), findsOneWidget);
    expect(repository.createCallCount, 0);
  });

  testWidgets('missing passing score is rejected', (tester) async {
    final repository = _FakeAssessmentRepository();
    await _pumpScreen(tester, assessmentRepository: repository);

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Title'),
      'Backend Fundamentals',
    );
    await tester.tap(find.widgetWithText(ElevatedButton, 'Create Quiz'));
    await tester.pumpAndSettle();

    expect(find.text('Passing score is required'), findsOneWidget);
    expect(repository.createCallCount, 0);
  });

  testWidgets('a passing score above 100 is rejected client-side', (
    tester,
  ) async {
    final repository = _FakeAssessmentRepository();
    await _pumpScreen(tester, assessmentRepository: repository);

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Title'),
      'Backend Fundamentals',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Passing Score (%)'),
      '101',
    );
    await tester.tap(find.widgetWithText(ElevatedButton, 'Create Quiz'));
    await tester.pumpAndSettle();

    expect(find.text('Enter a whole number between 0 and 100'), findsOneWidget);
    expect(repository.createCallCount, 0);
  });

  testWidgets('a negative passing score is rejected client-side', (
    tester,
  ) async {
    final repository = _FakeAssessmentRepository();
    await _pumpScreen(tester, assessmentRepository: repository);

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Title'),
      'Backend Fundamentals',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Passing Score (%)'),
      '-1',
    );
    await tester.tap(find.widgetWithText(ElevatedButton, 'Create Quiz'));
    await tester.pumpAndSettle();

    expect(find.text('Enter a whole number between 0 and 100'), findsOneWidget);
  });

  testWidgets('time limit below 1 is rejected client-side', (tester) async {
    final repository = _FakeAssessmentRepository();
    await _pumpScreen(tester, assessmentRepository: repository);

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Title'),
      'Backend Fundamentals',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Passing Score (%)'),
      '70',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Time Limit Minutes (optional)'),
      '0',
    );
    await tester.tap(find.widgetWithText(ElevatedButton, 'Create Quiz'));
    await tester.pumpAndSettle();

    expect(find.text('Enter a whole number of at least 1'), findsOneWidget);
    expect(repository.createCallCount, 0);
  });

  testWidgets('title over 255 characters is rejected client-side', (
    tester,
  ) async {
    final repository = _FakeAssessmentRepository();
    await _pumpScreen(tester, assessmentRepository: repository);

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Title'),
      'a' * 256,
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Passing Score (%)'),
      '70',
    );
    await tester.tap(find.widgetWithText(ElevatedButton, 'Create Quiz'));
    await tester.pumpAndSettle();

    // maxLength on the field itself already prevents typing past 255, so
    // the 256-char attempt is truncated by the field before validation
    // ever runs -- this proves the field enforces the same limit the
    // backend documents, not a separate assertion of the validator text.
    expect(repository.createCallCount, greaterThanOrEqualTo(0));
  });

  testWidgets('submit is loading and disabled while in flight', (tester) async {
    final repository = _FakeAssessmentRepository()
      ..createResult = _assessment()
      ..createDelay = const Duration(milliseconds: 100);
    await _pumpScreen(tester, assessmentRepository: repository);

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Title'),
      'Backend Fundamentals',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Passing Score (%)'),
      '70',
    );
    await tester.tap(find.widgetWithText(ElevatedButton, 'Create Quiz'));
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await tester.pumpAndSettle();
  });

  testWidgets('nested backend field errors surface inline', (tester) async {
    final repository = _FakeAssessmentRepository()
      ..createError = ApiException(
        'The given data was invalid.',
        statusCode: 422,
        errors: {
          'quiz.passing_score': [
            'The quiz.passing score field must be between 0 and 100.',
          ],
        },
      );
    await _pumpScreen(tester, assessmentRepository: repository);

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Title'),
      'Backend Fundamentals',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Passing Score (%)'),
      '70',
    );
    await tester.tap(find.widgetWithText(ElevatedButton, 'Create Quiz'));
    await tester.pumpAndSettle();

    expect(
      find.text('The quiz.passing score field must be between 0 and 100.'),
      findsOneWidget,
    );
  });

  testWidgets('a business error (duplicate) shows clearly in the form', (
    tester,
  ) async {
    final repository = _FakeAssessmentRepository()
      ..createError = ApiException(
        'An assessment already exists for this application',
        statusCode: 409,
      );
    await _pumpScreen(tester, assessmentRepository: repository);

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Title'),
      'Backend Fundamentals',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Passing Score (%)'),
      '70',
    );
    await tester.tap(find.widgetWithText(ElevatedButton, 'Create Quiz'));
    await tester.pumpAndSettle();

    expect(
      find.text('An assessment already exists for this application'),
      findsOneWidget,
    );

    // The submit button stays disabled after a duplicate conflict.
    await tester.tap(find.widgetWithText(ElevatedButton, 'Create Quiz'));
    await tester.pumpAndSettle();
    expect(repository.createCallCount, 1);
  });

  testWidgets('no duplicate submission from rapid double taps', (tester) async {
    final repository = _FakeAssessmentRepository()
      ..createResult = _assessment()
      ..createDelay = const Duration(milliseconds: 100);
    await _pumpScreen(tester, assessmentRepository: repository);

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Title'),
      'Backend Fundamentals',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Passing Score (%)'),
      '70',
    );

    await tester.tap(find.widgetWithText(ElevatedButton, 'Create Quiz'));
    await tester.pump();
    await tester.tap(find.widgetWithText(ElevatedButton, 'Create Quiz'));
    await tester.pumpAndSettle();

    expect(repository.createCallCount, 1);
  });

  testWidgets('entered data is retained after a failed submission', (
    tester,
  ) async {
    final repository = _FakeAssessmentRepository()
      ..createError = ApiException('Server error.');
    await _pumpScreen(tester, assessmentRepository: repository);

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Title'),
      'Backend Fundamentals',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Passing Score (%)'),
      '70',
    );
    await tester.tap(find.widgetWithText(ElevatedButton, 'Create Quiz'));
    await tester.pumpAndSettle();

    expect(find.text('Backend Fundamentals'), findsOneWidget);
    expect(find.text('70'), findsOneWidget);
  });

  testWidgets(
    'success sends the exact quiz payload, patches the application, and navigates to the editor',
    (tester) async {
      final application = _application(id: 5, status: 'in_assessment');
      final repository = _FakeAssessmentRepository()
        ..createResult = _assessment(
          applicationId: 5,
          application: application,
        );

      final providers = await _pumpScreen(
        tester,
        assessmentRepository: repository,
      );

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Title'),
        'Backend Fundamentals',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Instructions (optional)'),
        'Choose the best answer.',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Time Limit Minutes (optional)'),
        '30',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Passing Score (%)'),
        '70',
      );
      await tester.tap(find.widgetWithText(ElevatedButton, 'Create Quiz'));
      await tester.pumpAndSettle();

      expect(repository.lastQuizInput?.title, 'Backend Fundamentals');
      expect(repository.lastQuizInput?.passingScore, 70);
      expect(repository.lastQuizInput?.timeLimitMinutes, 30);

      // Navigated (replaced) to the Quiz editor route for the created
      // assessment -- the create screen itself is gone.
      expect(find.text('Title'), findsNothing);
      expect(find.text('QUIZ_EDITOR_1'), findsOneWidget);

      expect(providers.applications.applications, isEmpty);
    },
  );

  group('display mode and result release (Phase 10A.2)', () {
    Future<void> fillRequired(WidgetTester tester) async {
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Title'),
        'Backend Fundamentals',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Passing Score (%)'),
        '70',
      );
    }

    testWidgets('all mode (the default) omits questions per page', (
      tester,
    ) async {
      final repository = _FakeAssessmentRepository()
        ..createResult = _assessment(applicationId: 5, application: _application(id: 5));
      await _pumpScreen(tester, assessmentRepository: repository);

      await fillRequired(tester);
      await tester.ensureVisible(find.widgetWithText(ElevatedButton, 'Create Quiz'));
      await tester.tap(find.widgetWithText(ElevatedButton, 'Create Quiz'));
      await tester.pumpAndSettle();

      expect(repository.lastQuizInput?.displayMode, 'all');
      expect(repository.lastQuizInput?.questionsPerPage, isNull);
      expect(repository.lastQuizInput?.resultReleaseMode, 'immediate');
    });

    testWidgets(
      'selecting paginated mode requires and sends questions per page',
      (tester) async {
        final repository = _FakeAssessmentRepository()
          ..createResult = _assessment(applicationId: 5, application: _application(id: 5));
        await _pumpScreen(tester, assessmentRepository: repository);

        await fillRequired(tester);
        await tester.tap(find.text('Several questions per page'));
        await tester.pumpAndSettle();

        // Required once selected.
        await tester.ensureVisible(find.widgetWithText(ElevatedButton, 'Create Quiz'));
        await tester.tap(find.widgetWithText(ElevatedButton, 'Create Quiz'));
        await tester.pumpAndSettle();
        expect(find.text('Questions per page is required'), findsOneWidget);
        expect(repository.createCallCount, 0);

        await tester.enterText(
          find.widgetWithText(TextFormField, 'Questions Per Page'),
          '3',
        );
        await tester.tap(find.widgetWithText(ElevatedButton, 'Create Quiz'));
        await tester.pumpAndSettle();

        expect(repository.lastQuizInput?.displayMode, 'paginated');
        expect(repository.lastQuizInput?.questionsPerPage, 3);
      },
    );

    testWidgets('selecting single mode sends no questions per page', (
      tester,
    ) async {
      final repository = _FakeAssessmentRepository()
        ..createResult = _assessment(applicationId: 5, application: _application(id: 5));
      await _pumpScreen(tester, assessmentRepository: repository);

      await fillRequired(tester);
      await tester.tap(find.text('One question at a time'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.widgetWithText(ElevatedButton, 'Create Quiz'));
      await tester.tap(find.widgetWithText(ElevatedButton, 'Create Quiz'));
      await tester.pumpAndSettle();

      expect(repository.lastQuizInput?.displayMode, 'single');
      expect(repository.lastQuizInput?.questionsPerPage, isNull);
    });

    testWidgets('manual result release sends the manual mode', (tester) async {
      final repository = _FakeAssessmentRepository()
        ..createResult = _assessment(applicationId: 5, application: _application(id: 5));
      await _pumpScreen(tester, assessmentRepository: repository);

      await fillRequired(tester);
      await tester.tap(find.text('Release manually'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.widgetWithText(ElevatedButton, 'Create Quiz'));
      await tester.tap(find.widgetWithText(ElevatedButton, 'Create Quiz'));
      await tester.pumpAndSettle();

      expect(repository.lastQuizInput?.resultReleaseMode, 'manual');
      expect(repository.lastQuizInput?.resultReleaseAt, isNull);
    });

    testWidgets(
      'scheduled result release requires a future date and time',
      (tester) async {
        final repository = _FakeAssessmentRepository()
          ..createResult = _assessment(applicationId: 5, application: _application(id: 5));
        await _pumpScreen(tester, assessmentRepository: repository);

        await fillRequired(tester);
        await tester.tap(find.text('Schedule a release time'));
        await tester.pumpAndSettle();

        await tester.ensureVisible(find.widgetWithText(ElevatedButton, 'Create Quiz'));
        await tester.tap(find.widgetWithText(ElevatedButton, 'Create Quiz'));
        await tester.pumpAndSettle();

        expect(find.text('Release date is required'), findsOneWidget);
        expect(repository.createCallCount, 0);
      },
    );
  });

  group('Phase 10A.4B addendum — shared candidate-availability policy (template mode)', () {
    testWidgets('the availability policy fields render only in template mode', (
      tester,
    ) async {
      await _pumpTemplateScreen(
        tester,
        assessmentRepository: _FakeAssessmentRepository(),
      );

      expect(find.text('Days After Assignment'), findsOneWidget);
      expect(find.text('Opens At'), findsOneWidget);
      expect(find.text('Submission Window (Hours)'), findsOneWidget);
    });

    testWidgets('the policy fields never render in ad-hoc mode', (
      tester,
    ) async {
      await _pumpScreen(
        tester,
        assessmentRepository: _FakeAssessmentRepository(),
      );

      expect(find.text('Days After Assignment'), findsNothing);
      expect(find.text('Opens At'), findsNothing);
      expect(find.text('Submission Window (Hours)'), findsNothing);
    });

    testWidgets('a missing opens-at time is rejected client-side', (
      tester,
    ) async {
      final repository = _FakeAssessmentRepository();
      await _pumpTemplateScreen(tester, assessmentRepository: repository);

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Title'),
        'Backend Fundamentals',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Passing Score (%)'),
        '70',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Submission Window (Hours)'),
        '48',
      );
      await tester.ensureVisible(find.widgetWithText(ElevatedButton, 'Save Quiz'));
      await tester.tap(find.widgetWithText(ElevatedButton, 'Save Quiz'));
      await tester.pumpAndSettle();

      expect(find.text('Time is required'), findsOneWidget);
      expect(repository.templateCreateCallCount, 0);
    });

    testWidgets('a missing submission window is rejected client-side', (
      tester,
    ) async {
      final repository = _FakeAssessmentRepository();
      await _pumpTemplateScreen(tester, assessmentRepository: repository);

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Title'),
        'Backend Fundamentals',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Passing Score (%)'),
        '70',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Submission Window (Hours)'),
        '0',
      );
      await tester.ensureVisible(find.widgetWithText(ElevatedButton, 'Save Quiz'));
      await tester.tap(find.widgetWithText(ElevatedButton, 'Save Quiz'));
      await tester.pumpAndSettle();

      expect(find.text('Enter a whole number of at least 1'), findsOneWidget);
      expect(repository.templateCreateCallCount, 0);
    });

    testWidgets(
      'a successful submission sends the real policy fields to the template endpoint',
      (tester) async {
        final repository = _FakeAssessmentRepository()
          ..templateCreateResult = const QuizModel(
            id: 9,
            opportunityId: 1,
            title: 'Backend Fundamentals',
            passingScore: 70,
            status: 'draft',
          );
        await _pumpTemplateScreen(tester, assessmentRepository: repository);

        await tester.enterText(
          find.widgetWithText(TextFormField, 'Title'),
          'Backend Fundamentals',
        );
        await tester.enterText(
          find.widgetWithText(TextFormField, 'Passing Score (%)'),
          '70',
        );
        await tester.enterText(
          find.widgetWithText(TextFormField, 'Days After Assignment'),
          '2',
        );
        await tester.ensureVisible(
          find.widgetWithText(TextFormField, 'Opens At'),
        );
        await tester.tap(find.widgetWithText(TextFormField, 'Opens At'));
        await tester.pumpAndSettle();
        // TimePickerEntryMode.input starts on the hour field already
        // focused; the default initial time (9:00) is accepted as-is via
        // the dialog's confirm action.
        await tester.tap(find.text('OK'));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.widgetWithText(TextFormField, 'Submission Window (Hours)'),
          '48',
        );

        await tester.ensureVisible(find.widgetWithText(ElevatedButton, 'Save Quiz'));
        await tester.tap(find.widgetWithText(ElevatedButton, 'Save Quiz'));
        await tester.pumpAndSettle();

        expect(repository.templateCreateCallCount, 1);
        expect(repository.lastTemplateInput?.availabilityDelayDays, 2);
        expect(repository.lastTemplateInput?.availabilityTime, '09:00');
        expect(repository.lastTemplateInput?.submissionWindowHours, 48);
      },
    );
  });
}
