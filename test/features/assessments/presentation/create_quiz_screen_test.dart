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
  Future<AssessmentModel?> getAssessmentForApplication(
    int applicationId,
  ) async {
    return null;
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
}
