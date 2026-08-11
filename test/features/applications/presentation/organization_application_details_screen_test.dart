// Widget tests for OrganizationApplicationDetailsScreen, in isolation with
// a small GoRouter.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'package:opportunityhub_flutter/core/api/api_client.dart';
import 'package:opportunityhub_flutter/core/storage/token_storage_service.dart';
import 'package:opportunityhub_flutter/core/theme/app_theme.dart';
import 'package:opportunityhub_flutter/features/applications/data/application_repository.dart';
import 'package:opportunityhub_flutter/features/applications/presentation/organization_application_details_screen.dart';
import 'package:opportunityhub_flutter/features/assessments/data/assessment_repository.dart';
import 'package:opportunityhub_flutter/features/assessments/data/interview_create_input.dart';
import 'package:opportunityhub_flutter/features/assessments/data/quiz_create_input.dart';
import 'package:opportunityhub_flutter/features/assessments/presentation/organization_quiz_editor_screen.dart';
import 'package:opportunityhub_flutter/features/assessments/presentation/schedule_interview_screen.dart';
import 'package:opportunityhub_flutter/features/auth/data/auth_repository.dart';
import 'package:opportunityhub_flutter/features/offers/data/offer_repository.dart';
import 'package:opportunityhub_flutter/features/offers/data/send_offer_input.dart';
import 'package:opportunityhub_flutter/models/applicant_summary_model.dart';
import 'package:opportunityhub_flutter/models/application_model.dart';
import 'package:opportunityhub_flutter/models/assessment_model.dart';
import 'package:opportunityhub_flutter/models/cv_model.dart';
import 'package:opportunityhub_flutter/models/interview_model.dart';
import 'package:opportunityhub_flutter/models/offer_model.dart';
import 'package:opportunityhub_flutter/models/opportunity_model.dart';
import 'package:opportunityhub_flutter/models/quiz_model.dart';
import 'package:opportunityhub_flutter/providers/organization_quiz_provider.dart';
import 'package:opportunityhub_flutter/providers/auth_provider.dart';
import 'package:opportunityhub_flutter/providers/organization_applications_provider.dart';
import 'package:opportunityhub_flutter/providers/organization_assessment_provider.dart';
import 'package:opportunityhub_flutter/providers/organization_offer_provider.dart';
import 'package:opportunityhub_flutter/routes/app_routes.dart';

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
  isDefault: true,
  createdByAi: true,
);

const _applicant = ApplicantSummaryModel(
  id: 1,
  userId: 10,
  name: 'Jane Student',
  email: 'jane@example.com',
  phone: '0599111111',
  university: 'State University',
  major: 'Computer Science',
  graduationYear: 2027,
  bio: 'Backend developer.',
);

OpportunityModel _opportunity() {
  return const OpportunityModel(
    id: 5,
    title: 'Backend Developer',
    description: 'Great role.',
    opportunityType: 'job',
    employmentType: 'full_time',
    workMode: 'remote',
    experienceLevel: 'junior',
    positionsAvailable: 1,
    status: 'open',
  );
}

ApplicationModel _application({
  int id = 1,
  String status = 'pending',
  String? coverLetter,
  ApplicantSummaryModel? applicant = _applicant,
}) {
  return ApplicationModel(
    id: id,
    studentId: 1,
    opportunityId: 5,
    cvId: 2,
    status: status,
    cv: _cv,
    opportunity: _opportunity(),
    applicant: applicant,
    coverLetter: coverLetter,
    appliedAt: DateTime(2026, 7, 20),
  );
}

AssessmentModel _assessment({
  int id = 1,
  int applicationId = 1,
  String status = 'scheduled',
  String? result,
}) {
  return AssessmentModel(
    id: id,
    applicationId: applicationId,
    type: 'interview',
    status: status,
    result: result,
    interview: InterviewModel(
      id: 1,
      assessmentId: id,
      interviewType: 'online',
      status: 'scheduled',
      decision: 'pending',
      scheduledAt: DateTime(2026, 9, 1, 14, 30),
      meetingLink: 'https://meet.example.com/room',
    ),
  );
}

AssessmentModel _quizAssessment({
  int id = 1,
  int applicationId = 1,
  String quizStatus = 'draft',
}) {
  return AssessmentModel(
    id: id,
    applicationId: applicationId,
    type: 'quiz',
    status: quizStatus == 'published' ? 'scheduled' : 'pending',
    quiz: QuizModel(
      id: id,
      assessmentId: id,
      title: 'Backend Fundamentals',
      passingScore: 70,
      status: quizStatus,
    ),
  );
}

OfferModel _offer({
  int id = 1,
  int applicationId = 1,
  String status = 'sent',
  String? title,
  String? salaryAmount,
  String? salaryCurrency,
  String? salaryPeriod,
  DateTime? startDate,
  String? message,
  DateTime? respondedAt,
}) {
  return OfferModel(
    id: id,
    applicationId: applicationId,
    title: title,
    salaryAmount: salaryAmount,
    salaryCurrency: salaryCurrency,
    salaryPeriod: salaryPeriod,
    startDate: startDate,
    message: message,
    status: status,
    sentAt: DateTime(2026, 8, 10, 9),
    respondedAt: respondedAt,
  );
}

class _FakeOfferRepository extends OfferRepository {
  _FakeOfferRepository({
    this.getResult,
    this.getError,
    this.getDelay = Duration.zero,
  }) : super(apiClient: ApiClient(tokenStorageService: TokenStorageService()));

  OfferModel? getResult;
  ApiException? getError;
  Duration getDelay;
  int getCallCount = 0;

  OfferModel? sendResult;
  ApiException? sendError;
  int sendCallCount = 0;
  SendOfferInput? lastSendInput;

  @override
  Future<OfferModel> getOrganizationOffer(int applicationId) async {
    getCallCount++;
    if (getDelay > Duration.zero) {
      await Future<void>.delayed(getDelay);
    }
    if (getError != null) throw getError!;
    if (getResult == null) {
      throw ApiException('This application has no offer yet', statusCode: 404);
    }
    return getResult!;
  }

  @override
  Future<OfferModel> sendOrganizationOffer({
    required int applicationId,
    required SendOfferInput input,
  }) async {
    sendCallCount++;
    lastSendInput = input;
    if (sendError != null) throw sendError!;
    return sendResult ?? _offer(applicationId: applicationId);
  }
}

class _FakeAssessmentRepository extends AssessmentRepository {
  _FakeAssessmentRepository({
    this.getResult,
    this.getError,
    this.getDelay = Duration.zero,
    this.createResult,
  }) : super(apiClient: ApiClient(tokenStorageService: TokenStorageService()));

  AssessmentModel? getResult;
  ApiException? getError;
  Duration getDelay;
  int getCallCount = 0;

  AssessmentModel? createResult;
  InterviewCreateInput? lastInterviewInput;
  QuizCreateInput? lastQuizInput;

  @override
  Future<AssessmentModel?> getAssessmentForApplication(
    int applicationId,
  ) async {
    getCallCount++;
    if (getDelay > Duration.zero) {
      await Future<void>.delayed(getDelay);
    }
    if (getError != null) throw getError!;
    return getResult;
  }

  @override
  Future<AssessmentModel> createAssessment({
    required int applicationId,
    required String type,
    InterviewCreateInput? interviewInput,
    QuizCreateInput? quizInput,
  }) async {
    lastInterviewInput = interviewInput;
    lastQuizInput = quizInput;
    return createResult ?? _assessment(applicationId: applicationId);
  }

  @override
  Future<QuizModel?> getOrganizationQuiz(int assessmentId) async {
    return quizGetResult;
  }

  QuizModel? quizGetResult;
}

class _FakeApplicationRepository extends ApplicationRepository {
  _FakeApplicationRepository({
    this.detailsResult,
    this.detailsError,
    this.detailsDelay = Duration.zero,
  }) : super(apiClient: ApiClient(tokenStorageService: TokenStorageService()));

  ApplicationModel? detailsResult;
  ApiException? detailsError;
  Duration detailsDelay;
  int getOrganizationApplicationCallCount = 0;

  ApplicationModel? statusUpdateResult;
  ApiException? statusUpdateError;
  Duration statusUpdateDelay = Duration.zero;
  int updateStatusCallCount = 0;
  String? lastStatus;

  @override
  Future<ApplicationModel> getOrganizationApplication(int applicationId) async {
    getOrganizationApplicationCallCount++;
    if (detailsDelay > Duration.zero) {
      await Future<void>.delayed(detailsDelay);
    }
    if (detailsError != null) throw detailsError!;
    return detailsResult!;
  }

  @override
  Future<ApplicationModel> updateOrganizationApplicationStatus({
    required int applicationId,
    required String status,
  }) async {
    updateStatusCallCount++;
    lastStatus = status;
    if (statusUpdateDelay > Duration.zero) {
      await Future<void>.delayed(statusUpdateDelay);
    }
    if (statusUpdateError != null) throw statusUpdateError!;
    return statusUpdateResult!;
  }
}

class _Providers {
  _Providers({
    required this.applications,
    required this.assessment,
    required this.quiz,
    required this.offer,
  });

  final OrganizationApplicationsProvider applications;
  final OrganizationAssessmentProvider assessment;
  final OrganizationQuizProvider quiz;
  final OrganizationOfferProvider offer;
}

GoRouter _detailsRouter(int applicationId) {
  return GoRouter(
    initialLocation: AppRoutes.organizationApplicationDetails(applicationId),
    routes: [
      GoRoute(
        path: '${AppRoutes.organizationApplications}/:id',
        builder: (_, state) => OrganizationApplicationDetailsScreen(
          applicationId: int.parse(state.pathParameters['id']!),
        ),
      ),
      // Registered so the real "Choose Assessment" -> Interview -> Continue
      // flow can navigate all the way to the real screen in tests that
      // exercise it, exactly like AppRouter's own route table.
      GoRoute(
        path: '${AppRoutes.organizationApplications}/:id/assessment/interview',
        builder: (_, state) => ScheduleInterviewScreen(
          applicationId: int.parse(state.pathParameters['id']!),
        ),
      ),
      // Registered so the real "Manage Quiz"/"View Quiz" action can
      // navigate to the real Quiz editor screen, exactly like AppRouter's
      // own route table.
      GoRoute(
        path: '${AppRoutes.organizationAssessments}/:id/quiz',
        builder: (_, state) => OrganizationQuizEditorScreen(
          assessmentId: int.parse(state.pathParameters['id']!),
        ),
      ),
    ],
  );
}

Future<_Providers> _pumpDetails(
  WidgetTester tester, {
  required _FakeApplicationRepository repository,
  AssessmentRepository? assessmentRepository,
  OfferRepository? offerRepository,
  int applicationId = 1,
  Size size = const Size(420, 1400),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final authProvider = AuthProvider(authRepository: _FakeAuthRepository());
  final resolvedAssessmentRepository =
      assessmentRepository ?? _FakeAssessmentRepository();
  final applicationsProvider = OrganizationApplicationsProvider(
    repository: repository,
    authProvider: authProvider,
  );
  final assessmentProvider = OrganizationAssessmentProvider(
    repository: resolvedAssessmentRepository,
    authProvider: authProvider,
  );
  final quizProvider = OrganizationQuizProvider(
    repository: resolvedAssessmentRepository,
    authProvider: authProvider,
  );
  final offerProvider = OrganizationOfferProvider(
    repository: offerRepository ?? _FakeOfferRepository(),
    authProvider: authProvider,
  );

  final router = _detailsRouter(applicationId);

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<OrganizationApplicationsProvider>.value(
          value: applicationsProvider,
        ),
        ChangeNotifierProvider<OrganizationAssessmentProvider>.value(
          value: assessmentProvider,
        ),
        ChangeNotifierProvider<OrganizationQuizProvider>.value(
          value: quizProvider,
        ),
        ChangeNotifierProvider<OrganizationOfferProvider>.value(
          value: offerProvider,
        ),
      ],
      child: MaterialApp.router(
        theme: AppTheme.lightTheme,
        routerConfig: router,
      ),
    ),
  );
  await tester.pumpAndSettle();

  return _Providers(
    applications: applicationsProvider,
    assessment: assessmentProvider,
    quiz: quizProvider,
    offer: offerProvider,
  );
}

void main() {
  testWidgets('Loading state renders while details are in flight', (
    tester,
  ) async {
    final repository = _FakeApplicationRepository(
      detailsResult: _application(),
      detailsDelay: const Duration(milliseconds: 200),
    );
    tester.view.physicalSize = const Size(420, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final authProvider = AuthProvider(authRepository: _FakeAuthRepository());
    final applicationsProvider = OrganizationApplicationsProvider(
      repository: repository,
      authProvider: authProvider,
    );
    final assessmentProvider = OrganizationAssessmentProvider(
      repository: _FakeAssessmentRepository(),
      authProvider: authProvider,
    );
    final offerProvider = OrganizationOfferProvider(
      repository: _FakeOfferRepository(),
      authProvider: authProvider,
    );
    final router = _detailsRouter(1);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<OrganizationApplicationsProvider>.value(
            value: applicationsProvider,
          ),
          ChangeNotifierProvider<OrganizationAssessmentProvider>.value(
            value: assessmentProvider,
          ),
          ChangeNotifierProvider<OrganizationOfferProvider>.value(
            value: offerProvider,
          ),
        ],
        child: MaterialApp.router(
          theme: AppTheme.lightTheme,
          routerConfig: router,
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(applicationsProvider.isLoadingDetails, isTrue);

    await tester.pumpAndSettle();
  });

  testWidgets('Error state renders safely, no crash', (tester) async {
    final repository = _FakeApplicationRepository(
      detailsError: ApiException('Application not found'),
    );
    await _pumpDetails(tester, repository: repository, applicationId: 999);

    expect(find.text('Application not found'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Applicant details render', (tester) async {
    final repository = _FakeApplicationRepository(
      detailsResult: _application(),
    );
    await _pumpDetails(tester, repository: repository);

    expect(find.text('Jane Student'), findsOneWidget);
    expect(find.text('jane@example.com'), findsOneWidget);
    expect(find.text('0599111111'), findsOneWidget);
    expect(find.text('State University'), findsOneWidget);
    expect(find.text('Computer Science'), findsOneWidget);
    expect(find.text('2027'), findsOneWidget);
    expect(find.text('Backend developer.'), findsOneWidget);
  });

  testWidgets('Empty-string applicant name falls back to "Unnamed applicant"', (
    tester,
  ) async {
    final repository = _FakeApplicationRepository(
      detailsResult: _application(
        applicant: const ApplicantSummaryModel(id: 1, name: ''),
      ),
    );
    await _pumpDetails(tester, repository: repository);

    expect(find.text('Unnamed applicant'), findsOneWidget);
    expect(find.text(''), findsNothing);
  });

  testWidgets(
    'Whitespace-only applicant name falls back to "Unnamed applicant"',
    (tester) async {
      final repository = _FakeApplicationRepository(
        detailsResult: _application(
          applicant: const ApplicantSummaryModel(id: 1, name: '   '),
        ),
      );
      await _pumpDetails(tester, repository: repository);

      expect(find.text('Unnamed applicant'), findsOneWidget);
      expect(find.text('   '), findsNothing);
    },
  );

  testWidgets(
    'Empty/whitespace email, university, and major show "Not specified"',
    (tester) async {
      final repository = _FakeApplicationRepository(
        detailsResult: _application(
          applicant: const ApplicantSummaryModel(
            id: 1,
            name: 'Jane Student',
            email: '',
            phone: '0599111111',
            university: '   ',
            major: '',
            graduationYear: 2027,
          ),
        ),
      );
      await _pumpDetails(tester, repository: repository);

      expect(find.text('Not specified'), findsNWidgets(3));
      expect(find.text(''), findsNothing);
      expect(find.text('   '), findsNothing);
    },
  );

  testWidgets('Whitespace-only bio does not render a bio row', (tester) async {
    final repository = _FakeApplicationRepository(
      detailsResult: _application(
        applicant: const ApplicantSummaryModel(
          id: 1,
          name: 'Jane Student',
          bio: '   ',
        ),
      ),
    );
    await _pumpDetails(tester, repository: repository);

    expect(find.text('   '), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Cover letter renders when present', (tester) async {
    final repository = _FakeApplicationRepository(
      detailsResult: _application(coverLetter: 'I would love to join.'),
    );
    await _pumpDetails(tester, repository: repository);

    expect(find.text('Cover Letter'), findsOneWidget);
    expect(find.text('I would love to join.'), findsOneWidget);
  });

  testWidgets('No Cover Letter section renders when absent', (tester) async {
    final repository = _FakeApplicationRepository(
      detailsResult: _application(coverLetter: null),
    );
    await _pumpDetails(tester, repository: repository);

    expect(find.text('Cover Letter'), findsNothing);
  });

  testWidgets('CV details render', (tester) async {
    final repository = _FakeApplicationRepository(
      detailsResult: _application(),
    );
    await _pumpDetails(tester, repository: repository);

    expect(find.text('Main CV'), findsOneWidget);
    expect(find.text('uploads/cv.pdf'), findsOneWidget);
    expect(find.text('Version 1'), findsOneWidget);
    expect(find.text('Default'), findsOneWidget);
    expect(find.text('AI Generated'), findsOneWidget);
  });

  testWidgets('Opportunity details render', (tester) async {
    final repository = _FakeApplicationRepository(
      detailsResult: _application(),
    );
    await _pumpDetails(tester, repository: repository);

    expect(find.text('Backend Developer'), findsOneWidget);
    expect(find.text('Job'), findsOneWidget);
  });

  testWidgets('Pending status shows Mark Reviewed, Shortlist, and Reject', (
    tester,
  ) async {
    final repository = _FakeApplicationRepository(
      detailsResult: _application(status: 'pending'),
    );
    await _pumpDetails(tester, repository: repository);

    expect(find.text('Mark Reviewed'), findsOneWidget);
    expect(find.text('Shortlist'), findsOneWidget);
    expect(find.text('Reject'), findsOneWidget);
  });

  testWidgets('Reviewed status shows only Shortlist and Reject', (
    tester,
  ) async {
    final repository = _FakeApplicationRepository(
      detailsResult: _application(status: 'reviewed'),
    );
    await _pumpDetails(tester, repository: repository);

    expect(find.text('Mark Reviewed'), findsNothing);
    expect(find.text('Shortlist'), findsOneWidget);
    expect(find.text('Reject'), findsOneWidget);
  });

  testWidgets(
    'Shortlisted status shows Reject and Choose Assessment when no assessment exists',
    (tester) async {
      final repository = _FakeApplicationRepository(
        detailsResult: _application(status: 'shortlisted'),
      );
      await _pumpDetails(tester, repository: repository);

      expect(find.text('Mark Reviewed'), findsNothing);
      expect(find.text('Shortlist'), findsNothing);
      expect(find.text('Reject'), findsOneWidget);
      expect(find.text('Choose Assessment'), findsOneWidget);
    },
  );

  testWidgets(
    'Shortlisted status hides Choose Assessment when an assessment already exists',
    (tester) async {
      final repository = _FakeApplicationRepository(
        detailsResult: _application(status: 'shortlisted'),
      );
      final assessmentRepository = _FakeAssessmentRepository(
        getResult: _assessment(applicationId: 1),
      );
      await _pumpDetails(
        tester,
        repository: repository,
        assessmentRepository: assessmentRepository,
      );

      expect(find.text('Choose Assessment'), findsNothing);
      expect(find.text('Reject'), findsOneWidget);
    },
  );

  testWidgets('Rejected status shows no action buttons', (tester) async {
    final repository = _FakeApplicationRepository(
      detailsResult: _application(status: 'rejected'),
    );
    await _pumpDetails(tester, repository: repository);

    expect(find.text('Mark Reviewed'), findsNothing);
    expect(find.text('Shortlist'), findsNothing);
    expect(find.text('Reject'), findsNothing);
    expect(find.text('Rejected'), findsOneWidget);
  });

  testWidgets('Withdrawn status shows no action buttons', (tester) async {
    final repository = _FakeApplicationRepository(
      detailsResult: _application(status: 'withdrawn'),
    );
    await _pumpDetails(tester, repository: repository);

    expect(find.text('Mark Reviewed'), findsNothing);
    expect(find.text('Shortlist'), findsNothing);
    expect(find.text('Reject'), findsNothing);
  });

  testWidgets('interview_scheduled status is read-only — no Phase 3D actions', (
    tester,
  ) async {
    final repository = _FakeApplicationRepository(
      detailsResult: _application(status: 'interview_scheduled'),
    );
    await _pumpDetails(tester, repository: repository);

    expect(find.text('Mark Reviewed'), findsNothing);
    expect(find.text('Shortlist'), findsNothing);
    expect(find.text('Reject'), findsNothing);
  });

  testWidgets(
    'interview_scheduled with an assessment shows the read-only Assessment section',
    (tester) async {
      final repository = _FakeApplicationRepository(
        detailsResult: _application(status: 'interview_scheduled'),
      );
      final assessmentRepository = _FakeAssessmentRepository(
        getResult: _assessment(applicationId: 1),
      );
      await _pumpDetails(
        tester,
        repository: repository,
        assessmentRepository: assessmentRepository,
      );

      expect(find.text('Assessment'), findsOneWidget);
      expect(find.text('Online'), findsOneWidget); // interview type label
      expect(find.text('https://meet.example.com/room'), findsOneWidget);
    },
  );

  testWidgets(
    'interview_scheduled with no assessment record shows a controlled warning',
    (tester) async {
      final repository = _FakeApplicationRepository(
        detailsResult: _application(status: 'interview_scheduled'),
      );
      final assessmentRepository = _FakeAssessmentRepository(getResult: null);
      await _pumpDetails(
        tester,
        repository: repository,
        assessmentRepository: assessmentRepository,
      );

      expect(find.text('Assessment Not Found'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'in_assessment with an interview-type assessment shows the existing read-only Interview card',
    (tester) async {
      final repository = _FakeApplicationRepository(
        detailsResult: _application(status: 'in_assessment'),
      );
      final assessmentRepository = _FakeAssessmentRepository(
        getResult: _assessment(applicationId: 1),
      );
      await _pumpDetails(
        tester,
        repository: repository,
        assessmentRepository: assessmentRepository,
      );

      expect(find.text('Assessment'), findsOneWidget);
      expect(find.text('Online'), findsOneWidget);
      expect(find.text('https://meet.example.com/room'), findsOneWidget);
      expect(find.text('Manage Quiz'), findsNothing);
    },
  );

  testWidgets(
    'in_assessment with no assessment record shows a controlled warning (same as legacy)',
    (tester) async {
      final repository = _FakeApplicationRepository(
        detailsResult: _application(status: 'in_assessment'),
      );
      final assessmentRepository = _FakeAssessmentRepository(getResult: null);
      await _pumpDetails(
        tester,
        repository: repository,
        assessmentRepository: assessmentRepository,
      );

      expect(find.text('Assessment Not Found'), findsOneWidget);
      expect(find.textContaining('Under Assessment'), findsWidgets);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'in_assessment with a draft quiz-type assessment shows Manage Quiz',
    (tester) async {
      final repository = _FakeApplicationRepository(
        detailsResult: _application(status: 'in_assessment'),
      );
      final assessmentRepository = _FakeAssessmentRepository(
        getResult: _quizAssessment(applicationId: 1, quizStatus: 'draft'),
      );
      await _pumpDetails(
        tester,
        repository: repository,
        assessmentRepository: assessmentRepository,
      );

      expect(find.text('Assessment'), findsOneWidget);
      expect(find.text('Backend Fundamentals'), findsOneWidget);
      expect(find.text('Manage Quiz'), findsOneWidget);
      expect(find.text('View Quiz'), findsNothing);
    },
  );

  testWidgets(
    'in_assessment with a published quiz-type assessment shows View Quiz',
    (tester) async {
      final repository = _FakeApplicationRepository(
        detailsResult: _application(status: 'in_assessment'),
      );
      final assessmentRepository = _FakeAssessmentRepository(
        getResult: _quizAssessment(applicationId: 1, quizStatus: 'published'),
      );
      await _pumpDetails(
        tester,
        repository: repository,
        assessmentRepository: assessmentRepository,
      );

      expect(find.text('View Quiz'), findsOneWidget);
      expect(find.text('Manage Quiz'), findsNothing);
    },
  );

  testWidgets(
    'tapping Manage Quiz navigates to the Quiz editor and refreshes on return',
    (tester) async {
      final repository = _FakeApplicationRepository(
        detailsResult: _application(status: 'in_assessment'),
      );
      final assessmentRepository =
          _FakeAssessmentRepository(
              getResult: _quizAssessment(applicationId: 1, quizStatus: 'draft'),
            )
            ..quizGetResult = QuizModel(
              id: 1,
              assessmentId: 1,
              title: 'Backend Fundamentals',
              passingScore: 70,
              status: 'draft',
            );

      await _pumpDetails(
        tester,
        repository: repository,
        assessmentRepository: assessmentRepository,
      );
      expect(assessmentRepository.getCallCount, 1);

      await tester.tap(find.text('Manage Quiz'));
      await tester.pumpAndSettle();

      expect(find.text('Backend Fundamentals'), findsWidgets);

      // Navigate back to Application Details.
      await tester.pageBack();
      await tester.pumpAndSettle();

      // The Assessment is force-refreshed on return.
      expect(assessmentRepository.getCallCount, 2);
    },
  );

  testWidgets('Assessment section shows a compact spinner while loading', (
    tester,
  ) async {
    final repository = _FakeApplicationRepository(
      detailsResult: _application(status: 'interview_scheduled'),
    );
    final assessmentRepository = _FakeAssessmentRepository(
      getResult: _assessment(applicationId: 1),
      getDelay: const Duration(milliseconds: 200),
    );

    tester.view.physicalSize = const Size(420, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final authProvider = AuthProvider(authRepository: _FakeAuthRepository());
    final applicationsProvider = OrganizationApplicationsProvider(
      repository: repository,
      authProvider: authProvider,
    );
    final assessmentProvider = OrganizationAssessmentProvider(
      repository: assessmentRepository,
      authProvider: authProvider,
    );
    final offerProvider = OrganizationOfferProvider(
      repository: _FakeOfferRepository(),
      authProvider: authProvider,
    );
    final router = _detailsRouter(1);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<OrganizationApplicationsProvider>.value(
            value: applicationsProvider,
          ),
          ChangeNotifierProvider<OrganizationAssessmentProvider>.value(
            value: assessmentProvider,
          ),
          ChangeNotifierProvider<OrganizationOfferProvider>.value(
            value: offerProvider,
          ),
        ],
        child: MaterialApp.router(
          theme: AppTheme.lightTheme,
          routerConfig: router,
        ),
      ),
    );
    // Two pumps: one for the initial frame, one for the post-frame callback
    // that kicks off both loads — same pattern as the top-level "Loading
    // state" test above.
    await tester.pump();
    await tester.pump();

    expect(assessmentProvider.isLoading, isTrue);
    expect(find.byType(CircularProgressIndicator), findsWidgets);

    await tester.pumpAndSettle();
  });

  testWidgets('Assessment section shows a backend error with a working retry', (
    tester,
  ) async {
    final repository = _FakeApplicationRepository(
      detailsResult: _application(status: 'interview_scheduled'),
    );
    final assessmentRepository = _FakeAssessmentRepository(
      getError: ApiException('Could not load the assessment'),
    );
    await _pumpDetails(
      tester,
      repository: repository,
      assessmentRepository: assessmentRepository,
    );

    expect(find.text('Could not load the assessment'), findsOneWidget);
    expect(assessmentRepository.getCallCount, 1);

    assessmentRepository.getError = null;
    assessmentRepository.getResult = _assessment(applicationId: 1);
    await tester.tap(find.text('Try Again'));
    await tester.pumpAndSettle();

    expect(assessmentRepository.getCallCount, 2);
    expect(find.text('Assessment'), findsOneWidget);
    expect(find.text('Could not load the assessment'), findsNothing);
  });

  testWidgets('accepted status is read-only — no Phase 3D actions', (
    tester,
  ) async {
    final repository = _FakeApplicationRepository(
      detailsResult: _application(status: 'accepted'),
    );
    await _pumpDetails(tester, repository: repository);

    expect(find.text('Mark Reviewed'), findsNothing);
    expect(find.text('Shortlist'), findsNothing);
    expect(find.text('Reject'), findsNothing);
  });

  testWidgets(
    'Mark Reviewed succeeds and the status updates immediately without restart',
    (tester) async {
      final repository = _FakeApplicationRepository(
        detailsResult: _application(status: 'pending'),
      );
      repository.statusUpdateResult = _application(status: 'reviewed');
      await _pumpDetails(tester, repository: repository);

      await tester.tap(find.text('Mark Reviewed'));
      await tester.pumpAndSettle();

      expect(repository.lastStatus, 'reviewed');
      expect(find.text('Reviewed'), findsOneWidget);
      // The action set has updated to match the new status in the same
      // screen instance — no restart or remount required.
      expect(find.text('Mark Reviewed'), findsNothing);
      expect(find.text('Shortlist'), findsOneWidget);
    },
  );

  testWidgets(
    'Shortlist succeeds and the status updates immediately without restart',
    (tester) async {
      final repository = _FakeApplicationRepository(
        detailsResult: _application(status: 'reviewed'),
      );
      repository.statusUpdateResult = _application(status: 'shortlisted');
      await _pumpDetails(tester, repository: repository);

      await tester.tap(find.text('Shortlist'));
      await tester.pumpAndSettle();

      expect(repository.lastStatus, 'shortlisted');
      expect(find.text('Shortlisted'), findsOneWidget);
      expect(find.text('Shortlist'), findsNothing);
    },
  );

  testWidgets('Reject shows a confirmation dialog before anything happens', (
    tester,
  ) async {
    final repository = _FakeApplicationRepository(
      detailsResult: _application(status: 'pending'),
    );
    await _pumpDetails(tester, repository: repository);

    await tester.tap(find.text('Reject'));
    await tester.pumpAndSettle();

    expect(find.text('Reject Application'), findsOneWidget);
    expect(find.text('Reject this application?'), findsOneWidget);
    expect(repository.updateStatusCallCount, 0);
  });

  testWidgets('Reject cancellation performs no status change', (tester) async {
    final repository = _FakeApplicationRepository(
      detailsResult: _application(status: 'pending'),
    );
    await _pumpDetails(tester, repository: repository);

    await tester.tap(find.text('Reject'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(repository.updateStatusCallCount, 0);
    expect(find.text('Pending'), findsOneWidget);
  });

  testWidgets('Reject success updates the status immediately without restart', (
    tester,
  ) async {
    final repository = _FakeApplicationRepository(
      detailsResult: _application(status: 'pending'),
    );
    repository.statusUpdateResult = _application(status: 'rejected');
    await _pumpDetails(tester, repository: repository);

    await tester.tap(find.text('Reject'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reject').last);
    await tester.pumpAndSettle();

    expect(repository.updateStatusCallCount, 1);
    expect(repository.lastStatus, 'rejected');
    expect(find.text('Rejected'), findsOneWidget);
  });

  testWidgets('Action failure shows the backend error and keeps the status', (
    tester,
  ) async {
    final repository = _FakeApplicationRepository(
      detailsResult: _application(status: 'pending'),
    );
    repository.statusUpdateError = ApiException(
      'Cannot change the status of a withdrawn application',
      statusCode: 409,
    );
    await _pumpDetails(tester, repository: repository);

    await tester.tap(find.text('Mark Reviewed'));
    await tester.pumpAndSettle();

    expect(
      find.text('Cannot change the status of a withdrawn application'),
      findsOneWidget,
    );
    expect(find.text('Pending'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Buttons are disabled while an update is in flight', (
    tester,
  ) async {
    final repository = _FakeApplicationRepository(
      detailsResult: _application(status: 'pending'),
    );
    repository.statusUpdateResult = _application(status: 'reviewed');
    repository.statusUpdateDelay = const Duration(milliseconds: 200);
    await _pumpDetails(tester, repository: repository);

    await tester.tap(find.text('Mark Reviewed'));
    await tester.pump();

    final shortlistButton = tester.widget<ElevatedButton>(
      find.widgetWithText(ElevatedButton, 'Shortlist'),
    );
    expect(shortlistButton.onPressed, isNull);

    await tester.pumpAndSettle();
  });

  testWidgets(
    'Choosing Interview, scheduling it, and returning updates status and '
    'Assessment display immediately, without a details reload',
    (tester) async {
      final application = _application(id: 1, status: 'shortlisted');
      final repository = _FakeApplicationRepository(detailsResult: application);
      final assessmentRepository = _FakeAssessmentRepository(
        createResult: AssessmentModel(
          id: 9,
          applicationId: 1,
          type: 'interview',
          status: 'scheduled',
          application: _application(id: 1, status: 'interview_scheduled'),
          interview: InterviewModel(
            id: 9,
            assessmentId: 9,
            interviewType: 'online',
            status: 'scheduled',
            decision: 'pending',
          ),
        ),
      );

      await _pumpDetails(
        tester,
        repository: repository,
        assessmentRepository: assessmentRepository,
      );
      expect(repository.getOrganizationApplicationCallCount, 1);

      await tester.tap(find.text('Choose Assessment'));
      await tester.pumpAndSettle();

      // Interview is preselected by ChooseAssessmentTypeSheet -- Continue
      // navigates straight to the real Schedule Interview screen.
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();

      expect(find.text('Schedule Interview'), findsWidgets);

      await tester.tap(find.byKey(const Key('scheduledDateField')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('scheduledTimeField')));
      await tester.pumpAndSettle();
      final timeFields = find.descendant(
        of: find.byType(Dialog),
        matching: find.byType(TextField),
      );
      await tester.enterText(timeFields.at(0), '11');
      await tester.enterText(timeFields.at(1), '59');
      await tester.pumpAndSettle();
      final pm = find.text('PM');
      if (pm.evaluate().isNotEmpty) {
        await tester.tap(pm.first);
        await tester.pumpAndSettle();
      }
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Meeting Link'),
        'https://meet.example.com/room',
      );
      await tester.tap(
        find.widgetWithText(ElevatedButton, 'Schedule Interview'),
      );
      await tester.pumpAndSettle();

      // Back on Application Details -- updated in place from the created
      // Assessment's own application payload, not a fresh network fetch.
      expect(find.text('Assessment created successfully'), findsOneWidget);
      expect(find.text('Interview Scheduled'), findsOneWidget);
      expect(find.text('Assessment'), findsOneWidget);
      expect(find.text('Choose Assessment'), findsNothing);
      expect(repository.getOrganizationApplicationCallCount, 1);
    },
  );

  group('Offer — Send Offer eligibility (Phase 6C-2)', () {
    testWidgets(
      'in_assessment with a completed assessment and no Offer shows Send Offer',
      (tester) async {
        final repository = _FakeApplicationRepository(
          detailsResult: _application(status: 'in_assessment'),
        );
        final assessmentRepository = _FakeAssessmentRepository(
          getResult: _assessment(status: 'completed', result: 'passed'),
        );
        await _pumpDetails(
          tester,
          repository: repository,
          assessmentRepository: assessmentRepository,
        );

        expect(find.text('Send Offer'), findsOneWidget);
      },
    );

    for (final result in ['passed', 'failed', 'waiting']) {
      testWidgets(
        'Send Offer appears when the completed assessment result is $result',
        (tester) async {
          final repository = _FakeApplicationRepository(
            detailsResult: _application(status: 'in_assessment'),
          );
          final assessmentRepository = _FakeAssessmentRepository(
            getResult: _assessment(status: 'completed', result: result),
          );
          await _pumpDetails(
            tester,
            repository: repository,
            assessmentRepository: assessmentRepository,
          );

          expect(find.text('Send Offer'), findsOneWidget);
        },
      );
    }

    testWidgets(
      'Send Offer appears when the completed assessment has no result yet',
      (tester) async {
        final repository = _FakeApplicationRepository(
          detailsResult: _application(status: 'in_assessment'),
        );
        final assessmentRepository = _FakeAssessmentRepository(
          getResult: _assessment(status: 'completed', result: null),
        );
        await _pumpDetails(
          tester,
          repository: repository,
          assessmentRepository: assessmentRepository,
        );

        expect(find.text('Send Offer'), findsOneWidget);
      },
    );

    testWidgets('a non-completed assessment hides Send Offer', (tester) async {
      final repository = _FakeApplicationRepository(
        detailsResult: _application(status: 'in_assessment'),
      );
      final assessmentRepository = _FakeAssessmentRepository(
        getResult: _assessment(status: 'scheduled'),
      );
      await _pumpDetails(
        tester,
        repository: repository,
        assessmentRepository: assessmentRepository,
      );

      expect(find.text('Send Offer'), findsNothing);
      expect(find.text('Reject'), findsOneWidget);
    });

    testWidgets(
      'a wrong application status never shows Send Offer, even with a completed assessment on record',
      (tester) async {
        final repository = _FakeApplicationRepository(
          detailsResult: _application(status: 'shortlisted'),
        );
        final assessmentRepository = _FakeAssessmentRepository(
          getResult: _assessment(status: 'completed', result: 'passed'),
        );
        await _pumpDetails(
          tester,
          repository: repository,
          assessmentRepository: assessmentRepository,
        );

        expect(find.text('Send Offer'), findsNothing);
      },
    );

    testWidgets('in_assessment still allows Reject alongside Send Offer', (
      tester,
    ) async {
      final repository = _FakeApplicationRepository(
        detailsResult: _application(status: 'in_assessment'),
      );
      final assessmentRepository = _FakeAssessmentRepository(
        getResult: _assessment(status: 'completed', result: 'passed'),
      );
      await _pumpDetails(
        tester,
        repository: repository,
        assessmentRepository: assessmentRepository,
      );

      expect(find.text('Send Offer'), findsOneWidget);
      expect(find.text('Reject'), findsOneWidget);
    });

    testWidgets(
      'in_assessment with a non-completed assessment still allows Reject',
      (tester) async {
        final repository = _FakeApplicationRepository(
          detailsResult: _application(status: 'in_assessment'),
        );
        final assessmentRepository = _FakeAssessmentRepository(
          getResult: _assessment(status: 'in_progress'),
        );
        await _pumpDetails(
          tester,
          repository: repository,
          assessmentRepository: assessmentRepository,
        );

        expect(find.text('Reject'), findsOneWidget);
      },
    );

    testWidgets(
      'an existing Offer hides Send Offer even while application.status still reads in_assessment',
      (tester) async {
        final repository = _FakeApplicationRepository(
          detailsResult: _application(status: 'in_assessment'),
        );
        final assessmentRepository = _FakeAssessmentRepository(
          getResult: _assessment(status: 'completed', result: 'passed'),
        );
        final offerRepository = _FakeOfferRepository(
          getResult: _offer(status: 'sent'),
        );
        await _pumpDetails(
          tester,
          repository: repository,
          assessmentRepository: assessmentRepository,
          offerRepository: offerRepository,
        );

        expect(find.text('Send Offer'), findsNothing);
        // The real Offer data is still shown even though the Application
        // status hasn't caught up yet — see _OfferSection's own doc
        // comment on never inferring from application.status alone.
        expect(find.text('Offer'), findsOneWidget);
      },
    );

    testWidgets(
      'an existing Offer hides Reject too, even while application.status '
      'still reads in_assessment (Phase 6C-4)',
      (tester) async {
        final repository = _FakeApplicationRepository(
          detailsResult: _application(status: 'in_assessment'),
        );
        final assessmentRepository = _FakeAssessmentRepository(
          getResult: _assessment(status: 'completed', result: 'passed'),
        );
        final offerRepository = _FakeOfferRepository(
          getResult: _offer(status: 'sent'),
        );
        await _pumpDetails(
          tester,
          repository: repository,
          assessmentRepository: assessmentRepository,
          offerRepository: offerRepository,
        );

        // The backend now hard-blocks the generic status endpoint once an
        // Offer exists (Phase 6C-4) -- Reject must never be offered here,
        // the same way Send Offer already isn't.
        expect(find.text('Reject'), findsNothing);
        expect(find.text('Send Offer'), findsNothing);
        expect(find.text('Offer'), findsOneWidget);
      },
    );
  });

  group('Offer — summary card (Phase 6C-2)', () {
    testWidgets('offer_sent with a real Offer shows the read-only Offer card', (
      tester,
    ) async {
      final repository = _FakeApplicationRepository(
        detailsResult: _application(status: 'offer_sent'),
      );
      final offerRepository = _FakeOfferRepository(
        getResult: _offer(title: 'Backend Engineer', status: 'sent'),
      );
      await _pumpDetails(
        tester,
        repository: repository,
        offerRepository: offerRepository,
      );

      expect(find.text('Offer'), findsOneWidget);
      expect(find.text('Backend Engineer'), findsOneWidget);
      expect(find.text('Sent'), findsOneWidget);
      expect(find.text('Send Offer'), findsNothing);
      expect(find.text('Reject'), findsNothing);
    });

    testWidgets(
      'offer_sent with no Offer record shows a controlled inconsistency warning, not a fake card',
      (tester) async {
        final repository = _FakeApplicationRepository(
          detailsResult: _application(status: 'offer_sent'),
        );
        final offerRepository = _FakeOfferRepository(getResult: null);
        await _pumpDetails(
          tester,
          repository: repository,
          offerRepository: offerRepository,
        );

        expect(find.text('Offer Not Found'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('the Offer section shows a compact spinner while loading', (
      tester,
    ) async {
      final repository = _FakeApplicationRepository(
        detailsResult: _application(status: 'offer_sent'),
      );
      final offerRepository = _FakeOfferRepository(
        getResult: _offer(status: 'sent'),
        getDelay: const Duration(milliseconds: 200),
      );

      tester.view.physicalSize = const Size(420, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final authProvider = AuthProvider(authRepository: _FakeAuthRepository());
      final applicationsProvider = OrganizationApplicationsProvider(
        repository: repository,
        authProvider: authProvider,
      );
      final assessmentProvider = OrganizationAssessmentProvider(
        repository: _FakeAssessmentRepository(),
        authProvider: authProvider,
      );
      // Delay is simulated by overriding getOrganizationOffer via a tiny
      // subclass would be overkill here -- instead this reuses the same
      // "two pumps catch the loading frame" pattern the Assessment section
      // spinner test already establishes, relying on the fact that a real
      // (zero-delay) fetch still takes at least one microtask turn.
      final offerProvider = OrganizationOfferProvider(
        repository: offerRepository,
        authProvider: authProvider,
      );
      final router = _detailsRouter(1);

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<OrganizationApplicationsProvider>.value(
              value: applicationsProvider,
            ),
            ChangeNotifierProvider<OrganizationAssessmentProvider>.value(
              value: assessmentProvider,
            ),
            ChangeNotifierProvider<OrganizationOfferProvider>.value(
              value: offerProvider,
            ),
          ],
          child: MaterialApp.router(
            theme: AppTheme.lightTheme,
            routerConfig: router,
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(offerProvider.isLoading, isTrue);

      await tester.pumpAndSettle();
      expect(find.text('Offer'), findsOneWidget);
    });

    testWidgets(
      'the Offer section shows a backend error with a working retry',
      (tester) async {
        final repository = _FakeApplicationRepository(
          detailsResult: _application(status: 'offer_sent'),
        );
        final offerRepository = _FakeOfferRepository(
          getError: ApiException('Could not load the offer'),
        );
        await _pumpDetails(
          tester,
          repository: repository,
          offerRepository: offerRepository,
        );

        expect(find.text('Could not load the offer'), findsOneWidget);
        expect(offerRepository.getCallCount, 1);

        offerRepository.getError = null;
        offerRepository.getResult = _offer(title: 'Backend Engineer');
        await tester.tap(find.text('Try Again'));
        await tester.pumpAndSettle();

        expect(offerRepository.getCallCount, 2);
        expect(find.text('Backend Engineer'), findsOneWidget);
        expect(find.text('Could not load the offer'), findsNothing);
      },
    );

    testWidgets(
      'an accepted Offer renders read-only with no organization action',
      (tester) async {
        final repository = _FakeApplicationRepository(
          detailsResult: _application(status: 'accepted'),
        );
        final offerRepository = _FakeOfferRepository(
          getResult: _offer(
            status: 'accepted',
            respondedAt: DateTime(2026, 8, 12),
          ),
        );
        await _pumpDetails(
          tester,
          repository: repository,
          offerRepository: offerRepository,
        );

        expect(find.text('Accepted'), findsWidgets);
        expect(find.text('Responded At'), findsOneWidget);
        expect(find.text('Edit'), findsNothing);
        expect(find.text('Cancel'), findsNothing);
        expect(find.text('Resend'), findsNothing);
        expect(find.byType(ElevatedButton), findsNothing);
        expect(find.byType(OutlinedButton), findsNothing);
      },
    );

    testWidgets(
      'a declined Offer renders read-only with no organization action',
      (tester) async {
        final repository = _FakeApplicationRepository(
          detailsResult: _application(status: 'rejected'),
        );
        final offerRepository = _FakeOfferRepository(
          getResult: _offer(
            status: 'declined',
            respondedAt: DateTime(2026, 8, 12),
          ),
        );
        await _pumpDetails(
          tester,
          repository: repository,
          offerRepository: offerRepository,
        );

        expect(find.text('Declined'), findsOneWidget);
        expect(find.byType(ElevatedButton), findsNothing);
        expect(find.byType(OutlinedButton), findsNothing);
      },
    );

    testWidgets(
      'Assessment history remains visible alongside an accepted Offer '
      '(Phase 6C-4)',
      (tester) async {
        final repository = _FakeApplicationRepository(
          detailsResult: _application(status: 'accepted'),
        );
        final assessmentRepository = _FakeAssessmentRepository(
          getResult: _assessment(status: 'completed', result: 'passed'),
        );
        final offerRepository = _FakeOfferRepository(
          getResult: _offer(
            status: 'accepted',
            respondedAt: DateTime(2026, 8, 12),
          ),
        );
        await _pumpDetails(
          tester,
          repository: repository,
          assessmentRepository: assessmentRepository,
          offerRepository: offerRepository,
        );

        expect(find.text('Assessment'), findsOneWidget);
        expect(find.text('Offer'), findsOneWidget);
        expect(find.byType(ElevatedButton), findsNothing);
        expect(find.byType(OutlinedButton), findsNothing);
      },
    );

    testWidgets(
      'shows formatted salary only when every salary field is present',
      (tester) async {
        final repository = _FakeApplicationRepository(
          detailsResult: _application(status: 'offer_sent'),
        );
        final offerRepository = _FakeOfferRepository(
          getResult: _offer(
            salaryAmount: '90000.00',
            salaryCurrency: 'USD',
            salaryPeriod: 'yearly',
          ),
        );
        await _pumpDetails(
          tester,
          repository: repository,
          offerRepository: offerRepository,
        );

        expect(find.text('USD 90,000.00 / year'), findsOneWidget);
      },
    );

    testWidgets('omits the Salary row entirely when no compensation was set', (
      tester,
    ) async {
      final repository = _FakeApplicationRepository(
        detailsResult: _application(status: 'offer_sent'),
      );
      final offerRepository = _FakeOfferRepository(getResult: _offer());
      await _pumpDetails(
        tester,
        repository: repository,
        offerRepository: offerRepository,
      );

      expect(find.text('Salary'), findsNothing);
    });
  });

  group('Offer — sending (Phase 6C-2)', () {
    testWidgets(
      'sending an Offer closes the sheet, shows a success SnackBar, refreshes '
      'the Application, and swaps Send Offer for the Offer card',
      (tester) async {
        final repository = _FakeApplicationRepository(
          detailsResult: _application(status: 'in_assessment'),
        );
        final assessmentRepository = _FakeAssessmentRepository(
          getResult: _assessment(status: 'completed', result: 'passed'),
        );
        final offerRepository = _FakeOfferRepository()
          ..sendResult = _offer(title: 'Backend Engineer', status: 'sent');
        await _pumpDetails(
          tester,
          repository: repository,
          assessmentRepository: assessmentRepository,
          offerRepository: offerRepository,
        );
        expect(repository.getOrganizationApplicationCallCount, 1);

        await tester.tap(find.text('Send Offer'));
        await tester.pumpAndSettle();

        // Once the Offer is actually sent, the next details fetch must
        // reflect the real new status.
        repository.detailsResult = _application(status: 'offer_sent');

        await tester.tap(
          find.widgetWithText(ElevatedButton, 'Send Offer').last,
        );
        await tester.pumpAndSettle();

        expect(
          find.text(
            'Are you sure you want to send this offer? The candidate will '
            'be able to accept or decline it.',
          ),
          findsOneWidget,
        );

        await tester.tap(
          find.widgetWithText(ElevatedButton, 'Send Offer').last,
        );
        await tester.pumpAndSettle();

        expect(offerRepository.sendCallCount, 1);
        expect(find.text('Offer sent successfully'), findsOneWidget);
        expect(find.text('Backend Engineer'), findsOneWidget);
        expect(find.text('Offer Sent'), findsOneWidget);
        expect(find.text('Send Offer'), findsNothing);
        expect(repository.getOrganizationApplicationCallCount, 2);
      },
    );

    testWidgets('cancelling the confirmation does not send the Offer', (
      tester,
    ) async {
      final repository = _FakeApplicationRepository(
        detailsResult: _application(status: 'in_assessment'),
      );
      final assessmentRepository = _FakeAssessmentRepository(
        getResult: _assessment(status: 'completed', result: 'passed'),
      );
      final offerRepository = _FakeOfferRepository();
      await _pumpDetails(
        tester,
        repository: repository,
        assessmentRepository: assessmentRepository,
        offerRepository: offerRepository,
      );

      await tester.tap(find.text('Send Offer'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ElevatedButton, 'Send Offer').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(offerRepository.sendCallCount, 0);
      // Still on the sheet -- cancelling the confirmation only dismisses
      // the dialog, not the sheet itself.
      expect(find.text('Send Offer'), findsWidgets);
    });
  });

  testWidgets('narrow viewport does not overflow with Send Offer visible', (
    tester,
  ) async {
    final repository = _FakeApplicationRepository(
      detailsResult: _application(status: 'in_assessment'),
    );
    final assessmentRepository = _FakeAssessmentRepository(
      getResult: _assessment(status: 'completed', result: 'passed'),
    );
    await _pumpDetails(
      tester,
      repository: repository,
      assessmentRepository: assessmentRepository,
      size: const Size(320, 700),
    );

    expect(tester.takeException(), isNull);
  });

  testWidgets('narrow viewport does not overflow with an Offer card visible', (
    tester,
  ) async {
    final repository = _FakeApplicationRepository(
      detailsResult: _application(status: 'offer_sent'),
    );
    final offerRepository = _FakeOfferRepository(
      getResult: _offer(
        title: 'A Very Long Offer Title That Might Wrap Or Overflow',
        salaryAmount: '125000.00',
        salaryCurrency: 'USD',
        salaryPeriod: 'yearly',
        message:
            'We are excited to extend this offer and look forward to you '
            'joining the team on the agreed start date.',
      ),
    );
    await _pumpDetails(
      tester,
      repository: repository,
      offerRepository: offerRepository,
      size: const Size(320, 700),
    );

    expect(tester.takeException(), isNull);
  });
}
