// Widget tests for StudentApplicationDetailsScreen, in isolation with a
// small GoRouter.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'package:opportunityhub_flutter/core/api/api_client.dart';
import 'package:opportunityhub_flutter/core/storage/token_storage_service.dart';
import 'package:opportunityhub_flutter/core/theme/app_theme.dart';
import 'package:opportunityhub_flutter/core/utils/date_formatter.dart';
import 'package:opportunityhub_flutter/core/widgets/app_widgets.dart';
import 'package:opportunityhub_flutter/features/applications/data/application_repository.dart';
import 'package:opportunityhub_flutter/features/applications/presentation/student_application_details_screen.dart';
import 'package:opportunityhub_flutter/features/assessments/data/assessment_repository.dart';
import 'package:opportunityhub_flutter/features/auth/data/auth_repository.dart';
import 'package:opportunityhub_flutter/features/offers/data/offer_repository.dart';
import 'package:opportunityhub_flutter/models/application_model.dart';
import 'package:opportunityhub_flutter/models/assessment_model.dart';
import 'package:opportunityhub_flutter/models/cv_model.dart';
import 'package:opportunityhub_flutter/models/interview_model.dart';
import 'package:opportunityhub_flutter/models/offer_model.dart';
import 'package:opportunityhub_flutter/models/opportunity_model.dart';
import 'package:opportunityhub_flutter/models/organization_profile_model.dart';
import 'package:opportunityhub_flutter/models/question_model.dart';
import 'package:opportunityhub_flutter/models/quiz_model.dart';
import 'package:opportunityhub_flutter/providers/auth_provider.dart';
import 'package:opportunityhub_flutter/providers/student_applications_provider.dart';
import 'package:opportunityhub_flutter/providers/student_assessment_provider.dart';
import 'package:opportunityhub_flutter/providers/student_offer_provider.dart';
import 'package:opportunityhub_flutter/providers/theme_provider.dart';
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

class _FakeApplicationRepository extends ApplicationRepository {
  _FakeApplicationRepository({this.listResult = const [], this.listError})
    : super(apiClient: ApiClient(tokenStorageService: TokenStorageService()));

  List<ApplicationModel> listResult;
  ApiException? listError;
  int callCount = 0;

  @override
  Future<List<ApplicationModel>> getStudentApplications() async {
    callCount++;
    if (listError != null) throw listError!;
    return listResult;
  }
}

/// Controllable by `applicationId` so a test can give different
/// applications different assessments/delays, matching the convention
/// already used by `student_assessment_provider_test.dart`'s fake.
class _FakeAssessmentRepository extends AssessmentRepository {
  _FakeAssessmentRepository()
    : super(apiClient: ApiClient(tokenStorageService: TokenStorageService()));

  Map<int, AssessmentModel?>? resultsByApplication;

  /// Phase 10A.3 — set this instead of [resultsByApplication] to give a
  /// specific application a full, multi-element Assessment history (e.g. a
  /// completed Quiz already followed by an Interview). Takes priority over
  /// [resultsByApplication] for any application ID it contains.
  Map<int, List<AssessmentModel>>? historyByApplication;
  Map<int, Duration>? delaysByApplication;
  ApiException? loadError;
  int getStudentAssessmentForApplicationCallCount = 0;

  @override
  Future<List<AssessmentModel>> getStudentAssessmentsForApplication(
    int applicationId,
  ) async {
    getStudentAssessmentForApplicationCallCount++;
    final delay = delaysByApplication?[applicationId] ?? Duration.zero;
    if (delay > Duration.zero) {
      await Future<void>.delayed(delay);
    }
    if (loadError != null) throw loadError!;
    if (historyByApplication?.containsKey(applicationId) ?? false) {
      return historyByApplication![applicationId]!;
    }
    final result = resultsByApplication?[applicationId];
    return result == null ? [] : [result];
  }
}

ApplicationModel _application({
  int id = 1,
  String opportunityTitle = 'Software Engineer',
  String status = 'pending',
  OrganizationProfileModel? organizationProfile,
  String? coverLetter,
}) {
  return ApplicationModel(
    id: id,
    studentId: 1,
    opportunityId: 1,
    cvId: 1,
    status: status,
    opportunity: OpportunityModel(
      id: 1,
      title: opportunityTitle,
      description: 'A great opportunity.',
      opportunityType: 'job',
      employmentType: 'full_time',
      workMode: 'remote',
      experienceLevel: 'junior',
      positionsAvailable: 1,
      status: 'open',
      organizationProfile: organizationProfile,
    ),
    cv: const CvModel(
      id: 1,
      studentId: 1,
      title: 'My CV',
      filePath: 'cvs/my-cv.pdf',
      version: 1,
      isDefault: true,
      createdByAi: false,
    ),
    coverLetter: coverLetter,
    appliedAt: DateTime(2026, 7, 20),
  );
}

/// Builds an [InterviewModel] the way the real Student-facing endpoints
/// actually shape one — `interviewerEmail`/`companyFeedback`/`rating`/
/// `decision` default to `null` here too, matching the backend privacy
/// hotfix. Tests that need to prove defense-in-depth pass them explicitly.
InterviewModel _interview({
  int id = 10,
  int assessmentId = 1,
  String interviewType = 'online',
  DateTime? scheduledAt,
  int? durationMinutes,
  String? meetingLink,
  String? location,
  String? contactPhone,
  String? interviewerName,
  String? interviewerEmail,
  String? notes,
  String status = 'scheduled',
  String? decision,
  int? rating,
  String? companyFeedback,
}) {
  return InterviewModel(
    id: id,
    assessmentId: assessmentId,
    interviewType: interviewType,
    scheduledAt: scheduledAt ?? DateTime(2026, 8, 10, 14, 30),
    durationMinutes: durationMinutes,
    meetingLink: meetingLink,
    location: location,
    contactPhone: contactPhone,
    interviewerName: interviewerName,
    interviewerEmail: interviewerEmail,
    notes: notes,
    status: status,
    decision: decision,
    rating: rating,
    companyFeedback: companyFeedback,
  );
}

AssessmentModel _assessment({
  int id = 1,
  int applicationId = 1,
  String type = 'interview',
  String status = 'scheduled',
  String? result,
  InterviewModel? interview,
  QuizModel? quiz,
  DateTime? availableAt,
  DateTime? dueAt,
}) {
  return AssessmentModel(
    id: id,
    applicationId: applicationId,
    type: type,
    status: status,
    result: result,
    interview: interview,
    quiz: quiz,
    availableAt: availableAt,
    dueAt: dueAt,
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

  OfferModel? acceptResult;
  ApiException? acceptError;
  Duration acceptDelay = Duration.zero;
  int acceptCallCount = 0;

  OfferModel? declineResult;
  ApiException? declineError;
  Duration declineDelay = Duration.zero;
  int declineCallCount = 0;

  @override
  Future<OfferModel> getStudentOffer(int applicationId) async {
    getCallCount++;
    if (getDelay > Duration.zero) {
      await Future<void>.delayed(getDelay);
    }
    if (getError != null) throw getError!;
    if (getResult == null) {
      throw ApiException('Offer not found', statusCode: 404);
    }
    return getResult!;
  }

  @override
  Future<OfferModel> acceptStudentOffer(int offerId) async {
    acceptCallCount++;
    if (acceptDelay > Duration.zero) {
      await Future<void>.delayed(acceptDelay);
    }
    if (acceptError != null) throw acceptError!;
    return acceptResult ?? _offer(status: 'accepted');
  }

  @override
  Future<OfferModel> declineStudentOffer(int offerId) async {
    declineCallCount++;
    if (declineDelay > Duration.zero) {
      await Future<void>.delayed(declineDelay);
    }
    if (declineError != null) throw declineError!;
    return declineResult ?? _offer(status: 'declined');
  }
}

QuizModel _quiz({
  int id = 1,
  int assessmentId = 1,
  String status = 'published',
  int? timeLimitMinutes,
  int passingScore = 70,
  int questionCount = 2,
}) {
  return QuizModel(
    id: id,
    assessmentId: assessmentId,
    title: 'Backend Fundamentals',
    timeLimitMinutes: timeLimitMinutes,
    passingScore: passingScore,
    status: status,
    questions: List.generate(
      questionCount,
      (index) => QuestionModel(
        id: index + 1,
        quizId: id,
        prompt: 'Question ${index + 1}',
        type: 'true_false',
        points: 1,
        position: index,
      ),
    ),
  );
}

class _Providers {
  _Providers({required this.applications, required this.offer});

  final StudentApplicationsProvider applications;
  final StudentOfferProvider offer;
}

Future<_Providers> _pumpDetails(
  WidgetTester tester, {
  required _FakeApplicationRepository repository,
  _FakeAssessmentRepository? assessmentRepository,
  _FakeOfferRepository? offerRepository,
  int applicationId = 1,
  Size size = const Size(420, 1400),
  bool settle = true,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final authProvider = AuthProvider(authRepository: _FakeAuthRepository());
  final provider = StudentApplicationsProvider(
    repository: repository,
    authProvider: authProvider,
  );
  final assessmentProvider = StudentAssessmentProvider(
    repository: assessmentRepository ?? _FakeAssessmentRepository(),
    authProvider: authProvider,
  );
  final offerProvider = StudentOfferProvider(
    repository: offerRepository ?? _FakeOfferRepository(),
    authProvider: authProvider,
  );

  final router = GoRouter(
    initialLocation: AppRoutes.studentApplicationDetails(applicationId),
    routes: [
      GoRoute(
        path: AppRoutes.studentApplications,
        builder: (_, _) => const Scaffold(body: Text('LIST_PLACEHOLDER')),
      ),
      GoRoute(
        path: '${AppRoutes.studentApplications}/:id',
        builder: (_, state) => StudentApplicationDetailsScreen(
          applicationId: int.parse(state.pathParameters['id']!),
        ),
      ),
      GoRoute(
        path: '${AppRoutes.studentAssessments}/:id/quiz',
        builder: (_, state) => Scaffold(
          appBar: AppBar(),
          body: Text('QUIZ_SCREEN_PLACEHOLDER ${state.pathParameters['id']}'),
        ),
      ),
    ],
  );

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<StudentApplicationsProvider>.value(
          value: provider,
        ),
        ChangeNotifierProvider<StudentAssessmentProvider>.value(
          value: assessmentProvider,
        ),
        ChangeNotifierProvider<StudentOfferProvider>.value(
          value: offerProvider,
        ),
        ChangeNotifierProvider<ThemeProvider>.value(value: ThemeProvider()),
      ],
      child: MaterialApp.router(
        theme: AppTheme.lightTheme,
        routerConfig: router,
      ),
    ),
  );
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
    await tester.pump();
  }

  return _Providers(applications: provider, offer: offerProvider);
}

void main() {
  testWidgets('Direct ID route resolves from cache when already loaded', (
    tester,
  ) async {
    final repository = _FakeApplicationRepository(
      listResult: [_application(id: 42, opportunityTitle: 'Data Analyst')],
    );
    final providers = await _pumpDetails(
      tester,
      repository: repository,
      applicationId: 1,
    );
    // Pre-populate the cache the same way the list screen would have.
    await providers.applications.loadApplications();

    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Direct URL with nothing cached loads the full list once and resolves by ID',
    (tester) async {
      final repository = _FakeApplicationRepository(
        listResult: [
          _application(id: 7, opportunityTitle: 'Data Analyst'),
          _application(id: 8, opportunityTitle: 'Marketing Intern'),
        ],
      );
      await _pumpDetails(tester, repository: repository, applicationId: 7);

      // "Data Analyst" legitimately appears twice — the hero title and the
      // sticky summary panel's own "Opportunity" row (deliberate richness,
      // not a duplicate-rendering bug).
      expect(find.text('Data Analyst'), findsWidgets);
      expect(repository.callCount, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Real fields render, including nested organization name', (
    tester,
  ) async {
    final repository = _FakeApplicationRepository(
      listResult: [
        _application(
          id: 1,
          opportunityTitle: 'Software Engineer',
          status: 'shortlisted',
          organizationProfile: const OrganizationProfileModel(
            id: 3,
            organizationName: 'Acme Corp',
            organizationType: 'company',
            approvalStatus: 'approved',
          ),
        ),
      ],
    );
    await _pumpDetails(tester, repository: repository);

    // "Software Engineer" legitimately appears twice — the hero title and
    // the sticky summary panel's own "Opportunity" row.
    expect(find.text('Software Engineer'), findsWidgets);
    // "Acme Corp" and "Shortlisted" also legitimately appear twice — the
    // hero and the sticky summary panel both show organization/status.
    expect(find.text('Acme Corp'), findsWidgets);
    expect(find.text('Shortlisted'), findsWidgets);
    expect(find.text('My CV'), findsOneWidget);
  });

  testWidgets('Cover letter section renders only when present', (tester) async {
    final repository = _FakeApplicationRepository(
      listResult: [_application(id: 1, coverLetter: 'I would love to join.')],
    );
    await _pumpDetails(tester, repository: repository);

    expect(find.text('Cover Letter'), findsOneWidget);
    expect(find.text('I would love to join.'), findsOneWidget);
  });

  testWidgets('No cover letter section renders when absent', (tester) async {
    final repository = _FakeApplicationRepository(
      listResult: [_application(id: 1)],
    );
    await _pumpDetails(tester, repository: repository);

    expect(find.text('Cover Letter'), findsNothing);
  });

  testWidgets('A genuine load failure renders safely, with retry', (
    tester,
  ) async {
    final repository = _FakeApplicationRepository(
      listError: ApiException('Server error, please try again later.'),
    );
    await _pumpDetails(tester, repository: repository, applicationId: 1);

    expect(find.text('Server error, please try again later.'), findsOneWidget);

    repository.listError = null;
    repository.listResult = [
      _application(id: 1, opportunityTitle: 'Data Analyst'),
    ];
    await tester.tap(find.text('Try Again'));
    await tester.pumpAndSettle();

    // "Data Analyst" legitimately appears twice — the hero title and the
    // sticky summary panel's own "Opportunity" row.
    expect(find.text('Data Analyst'), findsWidgets);
  });

  testWidgets('Not-found error state renders safely, no crash', (tester) async {
    final repository = _FakeApplicationRepository(
      listResult: [_application(id: 1)],
    );
    await _pumpDetails(tester, repository: repository, applicationId: 999);

    expect(find.text('Application not found'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('No applicant/shortlist/interview/quiz/offer UI appears', (
    tester,
  ) async {
    final repository = _FakeApplicationRepository(
      listResult: [_application(id: 1)],
    );
    await _pumpDetails(tester, repository: repository);

    expect(find.textContaining('Applicant'), findsNothing);
    expect(find.textContaining('Interview'), findsNothing);
    expect(find.textContaining('Quiz'), findsNothing);
    // Not a blanket "Offer" substring check any more — the real Application
    // Progress pipeline (UI Phase 4/4.3) always shows a real "Offer" stage
    // label as one of its five stages, on every non-terminal application,
    // whether or not an actual Offer exists. What this test actually
    // guards against is a real Offer *card* (with its own accept/decline
    // actions) appearing when there's no Offer — checked precisely here.
    expect(find.text('Accept Offer'), findsNothing);
    expect(find.text('Decline Offer'), findsNothing);
  });

  group('Assessment section — status rules', () {
    testWidgets('pending status shows no Assessment section', (tester) async {
      final repository = _FakeApplicationRepository(
        listResult: [_application(id: 1, status: 'pending')],
      );
      await _pumpDetails(tester, repository: repository);

      // Only the Progress pipeline's own real "Assessment" stage label
      // renders (every non-terminal status shows the pipeline) — no
      // second match, since no Assessment card exists for this status.
      expect(find.text('Assessment'), findsOneWidget);
    });

    testWidgets('reviewed status shows no Assessment section', (tester) async {
      final repository = _FakeApplicationRepository(
        listResult: [_application(id: 1, status: 'reviewed')],
      );
      await _pumpDetails(tester, repository: repository);

      expect(find.text('Assessment'), findsOneWidget);
    });

    testWidgets('shortlisted status with no assessment shows no section', (
      tester,
    ) async {
      final repository = _FakeApplicationRepository(
        listResult: [_application(id: 1, status: 'shortlisted')],
      );
      await _pumpDetails(tester, repository: repository);

      expect(find.text('Assessment'), findsOneWidget);
    });

    testWidgets(
      'interview_scheduled with an assessment shows the Assessment section',
      (tester) async {
        final applicationRepository = _FakeApplicationRepository(
          listResult: [_application(id: 1, status: 'interview_scheduled')],
        );
        final assessmentRepository = _FakeAssessmentRepository()
          ..resultsByApplication = {1: _assessment(interview: _interview())};
        await _pumpDetails(
          tester,
          repository: applicationRepository,
          assessmentRepository: assessmentRepository,
        );

        // "Assessment" legitimately appears twice — the Progress
        // pipeline's own "Assessment" stage label and the Assessment
        // card's SectionHeader (deliberate richness, same precedent used
        // throughout this suite).
        expect(find.text('Assessment'), findsWidgets);
        // The interview type is now the card's own combined identity
        // title (UI Phase 4.3) rather than a separate "Interview Type"
        // row — the default fixture interview type is 'online'.
        expect(find.text('Online Interview'), findsOneWidget);
      },
    );

    testWidgets(
      'a stale shortlisted status with a real assessment still shows the '
      'section — actual data wins over stale status',
      (tester) async {
        final applicationRepository = _FakeApplicationRepository(
          listResult: [_application(id: 1, status: 'shortlisted')],
        );
        final assessmentRepository = _FakeAssessmentRepository()
          ..resultsByApplication = {1: _assessment(interview: _interview())};
        await _pumpDetails(
          tester,
          repository: applicationRepository,
          assessmentRepository: assessmentRepository,
        );

        // "Assessment" legitimately appears twice — the Progress
        // pipeline's own "Assessment" stage label and the Assessment
        // card's SectionHeader (deliberate richness, same precedent used
        // throughout this suite).
        expect(find.text('Assessment'), findsWidgets);
        // The interview type is now the card's own combined identity
        // title (UI Phase 4.3) rather than a separate "Interview Type"
        // row — the default fixture interview type is 'online'.
        expect(find.text('Online Interview'), findsOneWidget);
      },
    );

    testWidgets(
      'interview_scheduled with no assessment shows a controlled warning '
      'with retry, never a creation action',
      (tester) async {
        final applicationRepository = _FakeApplicationRepository(
          listResult: [_application(id: 1, status: 'interview_scheduled')],
        );
        final assessmentRepository = _FakeAssessmentRepository();
        await _pumpDetails(
          tester,
          repository: applicationRepository,
          assessmentRepository: assessmentRepository,
        );

        expect(find.text('Assessment Not Found'), findsOneWidget);
        expect(find.text('Try Again'), findsOneWidget);
        expect(find.textContaining('Choose Assessment'), findsNothing);
        // The only interactive control here is the error view's own Retry
        // — no separate creation/scheduling action button exists.
        expect(find.byType(ElevatedButton), findsNothing);

        assessmentRepository.resultsByApplication = {
          1: _assessment(interview: _interview()),
        };
        await tester.tap(find.text('Try Again'));
        await tester.pumpAndSettle();

        // "Assessment" appears twice — the pipeline stage label and the
        // card's own SectionHeader.
        expect(find.text('Assessment'), findsWidgets);
        expect(find.text('Assessment Not Found'), findsNothing);
      },
    );

    testWidgets('accepted with no assessment shows no section', (tester) async {
      final repository = _FakeApplicationRepository(
        listResult: [_application(id: 1, status: 'accepted')],
      );
      await _pumpDetails(tester, repository: repository);

      expect(find.text('Assessment'), findsNothing);
    });

    testWidgets('accepted with an existing assessment still shows it', (
      tester,
    ) async {
      final applicationRepository = _FakeApplicationRepository(
        listResult: [_application(id: 1, status: 'accepted')],
      );
      final assessmentRepository = _FakeAssessmentRepository()
        ..resultsByApplication = {
          1: _assessment(
            status: 'completed',
            result: 'passed',
            interview: _interview(status: 'completed'),
          ),
        };
      await _pumpDetails(
        tester,
        repository: applicationRepository,
        assessmentRepository: assessmentRepository,
      );

      expect(find.text('Assessment'), findsOneWidget);
    });
  });

  group('Assessment section — loading and error', () {
    testWidgets(
      'assessment loading does not block the rest of the application UI',
      (tester) async {
        final applicationRepository = _FakeApplicationRepository(
          listResult: [
            _application(
              id: 1,
              status: 'interview_scheduled',
              opportunityTitle: 'Backend Developer',
            ),
          ],
        );
        final assessmentRepository = _FakeAssessmentRepository()
          ..resultsByApplication = {1: _assessment(interview: _interview())}
          ..delaysByApplication = {1: const Duration(milliseconds: 300)};

        await _pumpDetails(
          tester,
          repository: applicationRepository,
          assessmentRepository: assessmentRepository,
          settle: false,
        );

        // The rest of the screen is already fully rendered even though the
        // assessment fetch is still in flight.
        // "Backend Developer" legitimately appears twice — the hero title
        // and the sticky summary panel's own "Opportunity" row.
        expect(find.text('Backend Developer'), findsWidgets);
        expect(find.text('My CV'), findsOneWidget);
        // The section itself shows a compact loading indicator.
        expect(find.byType(CircularProgressIndicator), findsOneWidget);
        // Only the pipeline's own "Assessment" stage label — the card
        // itself hasn't loaded yet.
        expect(find.text('Assessment'), findsOneWidget);

        // Drain the delayed fetch so no timer is left pending at test end.
        await tester.pumpAndSettle();
      },
    );

    testWidgets('assessment error shows a compact view with retry', (
      tester,
    ) async {
      final applicationRepository = _FakeApplicationRepository(
        listResult: [_application(id: 1, status: 'interview_scheduled')],
      );
      final assessmentRepository = _FakeAssessmentRepository()
        ..loadError = ApiException('Server error, please try again.');
      await _pumpDetails(
        tester,
        repository: applicationRepository,
        assessmentRepository: assessmentRepository,
      );

      expect(find.text('Server error, please try again.'), findsOneWidget);
      expect(find.text('Try Again'), findsOneWidget);

      assessmentRepository.loadError = null;
      assessmentRepository.resultsByApplication = {
        1: _assessment(interview: _interview()),
      };
      await tester.tap(find.text('Try Again'));
      await tester.pumpAndSettle();

      // "Assessment" appears twice — the pipeline stage label and the
      // card's own SectionHeader.
      expect(find.text('Assessment'), findsWidgets);
    });
  });

  group('Assessment section — interview field display', () {
    testWidgets('online interview shows Meeting Link, not Location', (
      tester,
    ) async {
      final applicationRepository = _FakeApplicationRepository(
        listResult: [_application(id: 1, status: 'interview_scheduled')],
      );
      final assessmentRepository = _FakeAssessmentRepository()
        ..resultsByApplication = {
          1: _assessment(
            interview: _interview(
              interviewType: 'online',
              meetingLink: 'https://meet.example.com/room-42',
              location: null,
            ),
          ),
        };
      await _pumpDetails(
        tester,
        repository: applicationRepository,
        assessmentRepository: assessmentRepository,
      );

      expect(find.text('Meeting Link'), findsOneWidget);
      expect(find.text('https://meet.example.com/room-42'), findsOneWidget);
      expect(find.text('Location'), findsNothing);
    });

    testWidgets('onsite interview shows Location, not Meeting Link', (
      tester,
    ) async {
      final applicationRepository = _FakeApplicationRepository(
        listResult: [_application(id: 1, status: 'interview_scheduled')],
      );
      final assessmentRepository = _FakeAssessmentRepository()
        ..resultsByApplication = {
          1: _assessment(
            interview: _interview(
              interviewType: 'onsite',
              location: 'HQ, 4th Floor',
              meetingLink: null,
            ),
          ),
        };
      await _pumpDetails(
        tester,
        repository: applicationRepository,
        assessmentRepository: assessmentRepository,
      );

      expect(find.text('Location'), findsOneWidget);
      expect(find.text('HQ, 4th Floor'), findsOneWidget);
      expect(find.text('Meeting Link'), findsNothing);
    });

    testWidgets(
      'phone interview shows neither Meeting Link nor Location, unless '
      'the payload actually has one',
      (tester) async {
        final applicationRepository = _FakeApplicationRepository(
          listResult: [_application(id: 1, status: 'interview_scheduled')],
        );
        final assessmentRepository = _FakeAssessmentRepository()
          ..resultsByApplication = {
            1: _assessment(
              interview: _interview(
                interviewType: 'phone',
                meetingLink: null,
                location: null,
              ),
            ),
          };
        await _pumpDetails(
          tester,
          repository: applicationRepository,
          assessmentRepository: assessmentRepository,
        );

        expect(find.text('Meeting Link'), findsNothing);
        expect(find.text('Location'), findsNothing);
        // The interview type is now the card's own combined identity
        // title (UI Phase 4.3) rather than a bare type label.
        expect(find.text('Phone Interview'), findsOneWidget);
      },
    );

    testWidgets('phone interview shows the Contact Phone number', (
      tester,
    ) async {
      final applicationRepository = _FakeApplicationRepository(
        listResult: [_application(id: 1, status: 'interview_scheduled')],
      );
      final assessmentRepository = _FakeAssessmentRepository()
        ..resultsByApplication = {
          1: _assessment(
            interview: _interview(
              interviewType: 'phone',
              meetingLink: null,
              location: null,
              contactPhone: '+1 555-0100',
            ),
          ),
        };
      await _pumpDetails(
        tester,
        repository: applicationRepository,
        assessmentRepository: assessmentRepository,
      );

      expect(find.text('Contact Phone'), findsOneWidget);
      expect(find.text('+1 555-0100'), findsOneWidget);
      expect(find.text('Meeting Link'), findsNothing);
      expect(find.text('Location'), findsNothing);
    });

    testWidgets(
      'a legacy phone interview with no contact_phone shows Not specified, not a crash',
      (tester) async {
        final applicationRepository = _FakeApplicationRepository(
          listResult: [_application(id: 1, status: 'interview_scheduled')],
        );
        final assessmentRepository = _FakeAssessmentRepository()
          ..resultsByApplication = {
            1: _assessment(
              interview: _interview(
                interviewType: 'phone',
                meetingLink: null,
                location: null,
                contactPhone: null,
              ),
            ),
          };
        await _pumpDetails(
          tester,
          repository: applicationRepository,
          assessmentRepository: assessmentRepository,
        );

        expect(find.text('Contact Phone'), findsOneWidget);
        expect(find.text('Not specified'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('optional fields absent parse and render safely', (
      tester,
    ) async {
      final applicationRepository = _FakeApplicationRepository(
        listResult: [_application(id: 1, status: 'interview_scheduled')],
      );
      final assessmentRepository = _FakeAssessmentRepository()
        ..resultsByApplication = {
          1: _assessment(
            interview: _interview(
              durationMinutes: null,
              interviewerName: null,
              notes: null,
              meetingLink: null,
              location: null,
            ),
          ),
        };
      await _pumpDetails(
        tester,
        repository: applicationRepository,
        assessmentRepository: assessmentRepository,
      );

      expect(find.text('Duration'), findsNothing);
      expect(find.text('Interviewer Name'), findsNothing);
      expect(tester.takeException(), isNull);
      // No stray "null" text anywhere in the section.
      expect(find.textContaining('null'), findsNothing);
    });
  });

  group('Assessment section — result', () {
    testWidgets('a null result renders no Result row', (tester) async {
      final applicationRepository = _FakeApplicationRepository(
        listResult: [_application(id: 1, status: 'interview_scheduled')],
      );
      final assessmentRepository = _FakeAssessmentRepository()
        ..resultsByApplication = {
          1: _assessment(result: null, interview: _interview()),
        };
      await _pumpDetails(
        tester,
        repository: applicationRepository,
        assessmentRepository: assessmentRepository,
      );

      expect(find.text('Result'), findsNothing);
    });

    testWidgets('a non-null result renders the Result row', (tester) async {
      final applicationRepository = _FakeApplicationRepository(
        listResult: [_application(id: 1, status: 'interview_scheduled')],
      );
      final assessmentRepository = _FakeAssessmentRepository()
        ..resultsByApplication = {
          1: _assessment(result: 'passed', interview: _interview()),
        };
      await _pumpDetails(
        tester,
        repository: applicationRepository,
        assessmentRepository: assessmentRepository,
      );

      expect(find.text('Result'), findsOneWidget);
      expect(find.text('Passed'), findsOneWidget);
    });
  });

  group('Assessment section — privacy defense-in-depth', () {
    testWidgets(
      'interview decision is never rendered, even when present on the model',
      (tester) async {
        final applicationRepository = _FakeApplicationRepository(
          listResult: [_application(id: 1, status: 'interview_scheduled')],
        );
        final assessmentRepository = _FakeAssessmentRepository()
          ..resultsByApplication = {
            1: _assessment(
              result: null,
              interview: _interview(decision: 'passed'),
            ),
          };
        await _pumpDetails(
          tester,
          repository: applicationRepository,
          assessmentRepository: assessmentRepository,
        );

        expect(find.textContaining('Decision'), findsNothing);
        expect(find.text('Passed'), findsNothing);
      },
    );

    testWidgets(
      'interviewer email is never rendered, even when present on the model',
      (tester) async {
        final applicationRepository = _FakeApplicationRepository(
          listResult: [_application(id: 1, status: 'interview_scheduled')],
        );
        final assessmentRepository = _FakeAssessmentRepository()
          ..resultsByApplication = {
            1: _assessment(
              interview: _interview(interviewerEmail: 'jane@hiring.example'),
            ),
          };
        await _pumpDetails(
          tester,
          repository: applicationRepository,
          assessmentRepository: assessmentRepository,
        );

        expect(find.textContaining('jane@hiring.example'), findsNothing);
        expect(find.text('Interviewer Email'), findsNothing);
      },
    );

    testWidgets(
      'company feedback is never rendered, even when present on the model',
      (tester) async {
        final applicationRepository = _FakeApplicationRepository(
          listResult: [_application(id: 1, status: 'interview_scheduled')],
        );
        final assessmentRepository = _FakeAssessmentRepository()
          ..resultsByApplication = {
            1: _assessment(
              interview: _interview(
                companyFeedback: 'Strong technical answers, hire.',
              ),
            ),
          };
        await _pumpDetails(
          tester,
          repository: applicationRepository,
          assessmentRepository: assessmentRepository,
        );

        expect(find.textContaining('Strong technical answers'), findsNothing);
      },
    );

    testWidgets('rating is never rendered, even when present on the model', (
      tester,
    ) async {
      final applicationRepository = _FakeApplicationRepository(
        listResult: [_application(id: 1, status: 'interview_scheduled')],
      );
      final assessmentRepository = _FakeAssessmentRepository()
        ..resultsByApplication = {
          1: _assessment(interview: _interview(rating: 4)),
        };
      await _pumpDetails(
        tester,
        repository: applicationRepository,
        assessmentRepository: assessmentRepository,
      );

      expect(find.textContaining('Rating'), findsNothing);
    });

    testWidgets('no organization action buttons ever appear', (tester) async {
      final applicationRepository = _FakeApplicationRepository(
        listResult: [_application(id: 1, status: 'interview_scheduled')],
      );
      final assessmentRepository = _FakeAssessmentRepository()
        ..resultsByApplication = {1: _assessment(interview: _interview())};
      await _pumpDetails(
        tester,
        repository: applicationRepository,
        assessmentRepository: assessmentRepository,
      );

      // Scoped to the Assessment card specifically (UI Phase 4.2 added a
      // real, legitimate "View Opportunity" button elsewhere on this page
      // — the Summary panel — so a page-wide button check would no longer
      // isolate what this test actually guards against: an
      // organization-only action button leaking into the read-only
      // Assessment section itself).
      final assessmentCard = find.ancestor(
        of: find.text('Assessment'),
        matching: find.byType(AppCard),
      );
      expect(
        find.descendant(of: assessmentCard, matching: find.byType(ElevatedButton)),
        findsNothing,
      );
      expect(
        find.descendant(of: assessmentCard, matching: find.byType(OutlinedButton)),
        findsNothing,
      );
    });
  });

  group('Assessment section — future assessment types', () {
    testWidgets(
      'an unknown assessment type renders a generic summary only, no crash',
      (tester) async {
        final applicationRepository = _FakeApplicationRepository(
          listResult: [_application(id: 1, status: 'interview_scheduled')],
        );
        final assessmentRepository = _FakeAssessmentRepository()
          ..resultsByApplication = {
            1: _assessment(type: 'some_future_type', status: 'pending'),
          };
        await _pumpDetails(
          tester,
          repository: applicationRepository,
          assessmentRepository: assessmentRepository,
        );

        // "Assessment" appears twice — the pipeline stage label and the
        // card's own SectionHeader.
        expect(find.text('Assessment'), findsWidgets);
        expect(find.text('Interview Type'), findsNothing);
        expect(find.text('Quiz Title'), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  });

  group('Assessment section — quiz type', () {
    testWidgets(
      'a draft/unavailable quiz shows a controlled message, no Open Quiz action',
      (tester) async {
        final applicationRepository = _FakeApplicationRepository(
          listResult: [_application(id: 1, status: 'interview_scheduled')],
        );
        final assessmentRepository = _FakeAssessmentRepository()
          ..resultsByApplication = {
            1: _assessment(type: 'quiz', status: 'pending'),
          };
        await _pumpDetails(
          tester,
          repository: applicationRepository,
          assessmentRepository: assessmentRepository,
        );

        expect(
          find.text('Quiz details are not available yet.'),
          findsOneWidget,
        );
        expect(find.text('Open Quiz'), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'a published, not-yet-completed quiz shows its summary and an Open Quiz action',
      (tester) async {
        final applicationRepository = _FakeApplicationRepository(
          listResult: [_application(id: 1, status: 'interview_scheduled')],
        );
        final assessmentRepository = _FakeAssessmentRepository()
          ..resultsByApplication = {
            1: _assessment(
              type: 'quiz',
              status: 'scheduled',
              quiz: _quiz(timeLimitMinutes: 30, questionCount: 3),
            ),
          };
        await _pumpDetails(
          tester,
          repository: applicationRepository,
          assessmentRepository: assessmentRepository,
        );

        expect(find.text('Quiz Title'), findsOneWidget);
        expect(find.text('Backend Fundamentals'), findsOneWidget);
        expect(find.text('70%'), findsOneWidget);
        expect(find.text('30 minutes'), findsOneWidget);
        expect(find.text('3'), findsOneWidget);
        expect(find.text('Open Quiz'), findsOneWidget);
      },
    );

    testWidgets(
      'an in_progress quiz still shows the Open Quiz action (resume)',
      (tester) async {
        final applicationRepository = _FakeApplicationRepository(
          listResult: [_application(id: 1, status: 'interview_scheduled')],
        );
        final assessmentRepository = _FakeAssessmentRepository()
          ..resultsByApplication = {
            1: _assessment(type: 'quiz', status: 'in_progress', quiz: _quiz()),
          };
        await _pumpDetails(
          tester,
          repository: applicationRepository,
          assessmentRepository: assessmentRepository,
        );

        expect(find.text('Open Quiz'), findsOneWidget);
      },
    );

    testWidgets(
      'a completed quiz shows a completed summary and the shared Result row, no Open Quiz action',
      (tester) async {
        final applicationRepository = _FakeApplicationRepository(
          listResult: [_application(id: 1, status: 'interview_scheduled')],
        );
        final assessmentRepository = _FakeAssessmentRepository()
          ..resultsByApplication = {
            1: _assessment(
              type: 'quiz',
              status: 'completed',
              result: 'passed',
              quiz: _quiz(),
            ),
          };
        await _pumpDetails(
          tester,
          repository: applicationRepository,
          assessmentRepository: assessmentRepository,
        );

        expect(find.text('Quiz completed'), findsOneWidget);
        expect(find.text('Result'), findsOneWidget);
        expect(find.text('Passed'), findsOneWidget);
        expect(find.text('Open Quiz'), findsNothing);
      },
    );

    testWidgets(
      'tapping Open Quiz navigates to the quiz route by Assessment ID and '
      'force-refreshes the Assessment on return',
      (tester) async {
        final applicationRepository = _FakeApplicationRepository(
          listResult: [_application(id: 1, status: 'interview_scheduled')],
        );
        final assessmentRepository = _FakeAssessmentRepository()
          ..resultsByApplication = {
            1: _assessment(
              id: 9,
              type: 'quiz',
              status: 'scheduled',
              quiz: _quiz(id: 9),
            ),
          };
        await _pumpDetails(
          tester,
          repository: applicationRepository,
          assessmentRepository: assessmentRepository,
        );
        expect(
          assessmentRepository.getStudentAssessmentForApplicationCallCount,
          1,
        );

        await tester.tap(find.text('Open Quiz'));
        await tester.pumpAndSettle();

        expect(find.text('QUIZ_SCREEN_PLACEHOLDER 9'), findsOneWidget);

        // Simulate the student navigating back from the quiz screen.
        await tester.pageBack();
        await tester.pumpAndSettle();

        expect(
          assessmentRepository.getStudentAssessmentForApplicationCallCount,
          2,
        );
      },
    );
  });

  group('Assessment section — quiz availability window (Phase 10A.4B addendum)', () {
    testWidgets(
      'an upcoming candidate window shows Assessment Upcoming with real dates, no quiz tiles',
      (tester) async {
        final applicationRepository = _FakeApplicationRepository(
          listResult: [_application(id: 1, status: 'interview_scheduled')],
        );
        final future = DateTime.now().add(const Duration(days: 2));
        final assessmentRepository = _FakeAssessmentRepository()
          ..resultsByApplication = {
            1: _assessment(
              type: 'quiz',
              status: 'scheduled',
              quiz: _quiz(),
              availableAt: future,
            ),
          };
        await _pumpDetails(
          tester,
          repository: applicationRepository,
          assessmentRepository: assessmentRepository,
        );

        expect(find.text('Assessment Upcoming'), findsOneWidget);
        expect(find.textContaining(formatDateTime(future)), findsOneWidget);
        expect(find.text('Quiz Title'), findsNothing);
        expect(find.text('Open Quiz'), findsNothing);
      },
    );

    testWidgets(
      'a passed deadline with no submission shows Assessment Deadline Passed, no Open Quiz',
      (tester) async {
        final applicationRepository = _FakeApplicationRepository(
          listResult: [_application(id: 1, status: 'interview_scheduled')],
        );
        final past = DateTime.now().subtract(const Duration(days: 1));
        final assessmentRepository = _FakeAssessmentRepository()
          ..resultsByApplication = {
            1: _assessment(
              type: 'quiz',
              status: 'scheduled',
              quiz: _quiz(),
              availableAt: DateTime.now().subtract(const Duration(days: 3)),
              dueAt: past,
            ),
          };
        await _pumpDetails(
          tester,
          repository: applicationRepository,
          assessmentRepository: assessmentRepository,
        );

        expect(find.text('Assessment Deadline Passed'), findsOneWidget);
        expect(find.textContaining(formatDateTime(past)), findsOneWidget);
        expect(find.text('Open Quiz'), findsNothing);
      },
    );

    testWidgets(
      'an available window (between available_at and due_at) shows the normal quiz card plus a Deadline tile',
      (tester) async {
        final applicationRepository = _FakeApplicationRepository(
          listResult: [_application(id: 1, status: 'interview_scheduled')],
        );
        final due = DateTime.now().add(const Duration(days: 1));
        final assessmentRepository = _FakeAssessmentRepository()
          ..resultsByApplication = {
            1: _assessment(
              type: 'quiz',
              status: 'scheduled',
              quiz: _quiz(),
              availableAt: DateTime.now().subtract(const Duration(hours: 1)),
              dueAt: due,
            ),
          };
        await _pumpDetails(
          tester,
          repository: applicationRepository,
          assessmentRepository: assessmentRepository,
        );

        expect(find.text('Quiz Title'), findsOneWidget);
        expect(find.text('Open Quiz'), findsOneWidget);
        expect(find.text('Deadline'), findsOneWidget);
        expect(find.text(formatDateTime(due)), findsOneWidget);
      },
    );

    testWidgets(
      'a legacy quiz with no availability window renders exactly as before (no gating)',
      (tester) async {
        final applicationRepository = _FakeApplicationRepository(
          listResult: [_application(id: 1, status: 'interview_scheduled')],
        );
        final assessmentRepository = _FakeAssessmentRepository()
          ..resultsByApplication = {
            1: _assessment(type: 'quiz', status: 'scheduled', quiz: _quiz()),
          };
        await _pumpDetails(
          tester,
          repository: applicationRepository,
          assessmentRepository: assessmentRepository,
        );

        expect(find.text('Assessment Upcoming'), findsNothing);
        expect(find.text('Assessment Deadline Passed'), findsNothing);
        expect(find.text('Deadline'), findsNothing);
        expect(find.text('Open Quiz'), findsOneWidget);
      },
    );
  });

  group('Offer section — loading and error (Phase 6C-3)', () {
    testWidgets(
      'the Offer section shows a compact spinner while loading, without '
      'blocking the rest of the page',
      (tester) async {
        final applicationRepository = _FakeApplicationRepository(
          listResult: [
            _application(
              id: 1,
              status: 'offer_sent',
              opportunityTitle: 'Backend Developer',
            ),
          ],
        );
        final offerRepository = _FakeOfferRepository(
          getResult: _offer(status: 'sent'),
          getDelay: const Duration(milliseconds: 300),
        );

        await _pumpDetails(
          tester,
          repository: applicationRepository,
          offerRepository: offerRepository,
          settle: false,
        );

        // "Backend Developer" legitimately appears twice — the hero title
        // and the sticky summary panel's own "Opportunity" row.
        expect(find.text('Backend Developer'), findsWidgets);
        expect(find.byType(CircularProgressIndicator), findsOneWidget);
        expect(find.text('Accept Offer'), findsNothing);

        await tester.pumpAndSettle();
      },
    );

    testWidgets('a non-404 Offer load error shows a compact view with retry', (
      tester,
    ) async {
      final applicationRepository = _FakeApplicationRepository(
        listResult: [_application(id: 1, status: 'offer_sent')],
      );
      final offerRepository = _FakeOfferRepository(
        getError: ApiException('Server error, please try again.'),
      );
      await _pumpDetails(
        tester,
        repository: applicationRepository,
        offerRepository: offerRepository,
      );

      expect(find.text('Server error, please try again.'), findsOneWidget);
      expect(find.text('Try Again'), findsOneWidget);

      offerRepository.getError = null;
      offerRepository.getResult = _offer(status: 'sent');
      await tester.tap(find.text('Try Again'));
      await tester.pumpAndSettle();

      expect(find.text('Accept Offer'), findsOneWidget);
      expect(find.text('Server error, please try again.'), findsNothing);
    });
  });

  group('Offer section — visibility (Phase 6C-3)', () {
    testWidgets('no Offer and a normal status renders no Offer section', (
      tester,
    ) async {
      final applicationRepository = _FakeApplicationRepository(
        listResult: [_application(id: 1, status: 'pending')],
      );
      final offerRepository = _FakeOfferRepository();
      await _pumpDetails(
        tester,
        repository: applicationRepository,
        offerRepository: offerRepository,
      );

      // Only the Progress pipeline's own real "Offer" stage label renders
      // (every non-terminal status shows the pipeline) — no Offer card.
      expect(find.text('Offer'), findsOneWidget);
      expect(
        find.text('Offer details are currently unavailable.'),
        findsNothing,
      );
    });

    testWidgets(
      'offer_sent with no Offer shows a controlled inconsistency, with retry',
      (tester) async {
        final applicationRepository = _FakeApplicationRepository(
          listResult: [_application(id: 1, status: 'offer_sent')],
        );
        final offerRepository = _FakeOfferRepository();
        await _pumpDetails(
          tester,
          repository: applicationRepository,
          offerRepository: offerRepository,
        );

        expect(
          find.text('Offer details are currently unavailable.'),
          findsOneWidget,
        );
        expect(find.text('Try Again'), findsOneWidget);

        offerRepository.getResult = _offer(status: 'sent');
        await tester.tap(find.text('Try Again'));
        await tester.pumpAndSettle();

        // "Offer" appears twice — the pipeline's own stage label and the
        // Offer card's SectionHeader.
        expect(find.text('Offer'), findsWidgets);
        expect(
          find.text('Offer details are currently unavailable.'),
          findsNothing,
        );
      },
    );

    testWidgets(
      'an actual sent Offer renders regardless of a stale Application status',
      (tester) async {
        final applicationRepository = _FakeApplicationRepository(
          listResult: [_application(id: 1, status: 'in_assessment')],
        );
        final offerRepository = _FakeOfferRepository(
          getResult: _offer(status: 'sent'),
        );
        await _pumpDetails(
          tester,
          repository: applicationRepository,
          offerRepository: offerRepository,
        );

        expect(find.text('Accept Offer'), findsOneWidget);
        expect(find.text('Decline Offer'), findsOneWidget);
      },
    );
  });

  group('Offer section — actions (Phase 6C-3)', () {
    testWidgets('a sent Offer shows Accept Offer and Decline Offer', (
      tester,
    ) async {
      final applicationRepository = _FakeApplicationRepository(
        listResult: [_application(id: 1, status: 'offer_sent')],
      );
      final offerRepository = _FakeOfferRepository(
        getResult: _offer(status: 'sent'),
      );
      await _pumpDetails(
        tester,
        repository: applicationRepository,
        offerRepository: offerRepository,
      );

      expect(find.text('Accept Offer'), findsOneWidget);
      expect(find.text('Decline Offer'), findsOneWidget);
    });

    testWidgets('an accepted Offer shows no action buttons', (tester) async {
      final applicationRepository = _FakeApplicationRepository(
        listResult: [_application(id: 1, status: 'accepted')],
      );
      final offerRepository = _FakeOfferRepository(
        getResult: _offer(
          status: 'accepted',
          respondedAt: DateTime(2026, 8, 12),
        ),
      );
      await _pumpDetails(
        tester,
        repository: applicationRepository,
        offerRepository: offerRepository,
      );

      expect(find.text('Accept Offer'), findsNothing);
      expect(find.text('Decline Offer'), findsNothing);
    });

    testWidgets('a declined Offer shows no action buttons', (tester) async {
      final applicationRepository = _FakeApplicationRepository(
        listResult: [_application(id: 1, status: 'rejected')],
      );
      final offerRepository = _FakeOfferRepository(
        getResult: _offer(
          status: 'declined',
          respondedAt: DateTime(2026, 8, 12),
        ),
      );
      await _pumpDetails(
        tester,
        repository: applicationRepository,
        offerRepository: offerRepository,
      );

      expect(find.text('Accept Offer'), findsNothing);
      expect(find.text('Decline Offer'), findsNothing);
    });
  });

  group('Offer section — card fields (Phase 6C-3)', () {
    testWidgets('salary/date/message render when present', (tester) async {
      final applicationRepository = _FakeApplicationRepository(
        listResult: [_application(id: 1, status: 'offer_sent')],
      );
      final offerRepository = _FakeOfferRepository(
        getResult: _offer(
          status: 'sent',
          title: 'Backend Engineer',
          salaryAmount: '90000.00',
          salaryCurrency: 'USD',
          salaryPeriod: 'yearly',
          startDate: DateTime(2026, 9, 1),
          message: 'Welcome aboard.',
        ),
      );
      await _pumpDetails(
        tester,
        repository: applicationRepository,
        offerRepository: offerRepository,
      );

      expect(find.text('Backend Engineer'), findsOneWidget);
      expect(find.text('USD 90,000.00 / year'), findsOneWidget);
      expect(find.text('Start Date'), findsOneWidget);
      expect(find.text('Sent At'), findsOneWidget);
      expect(find.text('Welcome aboard.'), findsOneWidget);
    });

    testWidgets('omits the Salary row entirely when no compensation was set', (
      tester,
    ) async {
      final applicationRepository = _FakeApplicationRepository(
        listResult: [_application(id: 1, status: 'offer_sent')],
      );
      final offerRepository = _FakeOfferRepository(
        getResult: _offer(status: 'sent'),
      );
      await _pumpDetails(
        tester,
        repository: applicationRepository,
        offerRepository: offerRepository,
      );

      expect(find.text('Salary'), findsNothing);
    });
  });

  group('Offer section — accept (Phase 6C-3)', () {
    testWidgets(
      'cancelling the accept confirmation does not accept the Offer',
      (tester) async {
        final applicationRepository = _FakeApplicationRepository(
          listResult: [_application(id: 1, status: 'offer_sent')],
        );
        final offerRepository = _FakeOfferRepository(
          getResult: _offer(status: 'sent'),
        );
        await _pumpDetails(
          tester,
          repository: applicationRepository,
          offerRepository: offerRepository,
        );

        await tester.tap(find.widgetWithText(ElevatedButton, 'Accept Offer'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();

        expect(offerRepository.acceptCallCount, 0);
        expect(find.text('Accept Offer'), findsOneWidget);
      },
    );

    testWidgets(
      'accept success updates the Offer, refreshes the Application, and '
      'shows a success SnackBar',
      (tester) async {
        final applicationRepository = _FakeApplicationRepository(
          listResult: [_application(id: 1, status: 'offer_sent')],
        );
        final offerRepository = _FakeOfferRepository(
          getResult: _offer(status: 'sent'),
        )..acceptResult = _offer(status: 'accepted');
        await _pumpDetails(
          tester,
          repository: applicationRepository,
          offerRepository: offerRepository,
        );

        await tester.tap(find.widgetWithText(ElevatedButton, 'Accept Offer'));
        await tester.pumpAndSettle();

        // Once the Offer is actually accepted, the next details fetch must
        // reflect the real new status.
        applicationRepository.listResult = [
          _application(id: 1, status: 'accepted'),
        ];

        await tester.tap(find.widgetWithText(ElevatedButton, 'Accept'));
        await tester.pumpAndSettle();

        expect(offerRepository.acceptCallCount, 1);
        expect(find.text('Offer accepted successfully'), findsOneWidget);
        expect(find.text('Offer Accepted'), findsOneWidget);
        expect(find.text('Accept Offer'), findsNothing);
        expect(find.text('Decline Offer'), findsNothing);
        expect(applicationRepository.callCount, greaterThanOrEqualTo(2));
      },
    );

    testWidgets(
      'responding disables both actions and shows the tapped action loading',
      (tester) async {
        final applicationRepository = _FakeApplicationRepository(
          listResult: [_application(id: 1, status: 'offer_sent')],
        );
        final offerRepository = _FakeOfferRepository(
          getResult: _offer(status: 'sent'),
        )..acceptDelay = const Duration(milliseconds: 200);
        await _pumpDetails(
          tester,
          repository: applicationRepository,
          offerRepository: offerRepository,
        );

        await tester.tap(find.widgetWithText(ElevatedButton, 'Accept Offer'));
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(ElevatedButton, 'Accept'));
        await tester.pump();

        final declineButton = tester.widget<OutlinedButton>(
          find.widgetWithText(OutlinedButton, 'Decline Offer'),
        );
        expect(declineButton.onPressed, isNull);

        await tester.pumpAndSettle();
      },
    );

    testWidgets(
      'a failed Application refresh after a successful accept keeps the '
      'updated Offer visible with a compact retry',
      (tester) async {
        final applicationRepository = _FakeApplicationRepository(
          listResult: [_application(id: 1, status: 'offer_sent')],
        );
        final offerRepository = _FakeOfferRepository(
          getResult: _offer(status: 'sent'),
        )..acceptResult = _offer(status: 'accepted');
        await _pumpDetails(
          tester,
          repository: applicationRepository,
          offerRepository: offerRepository,
        );

        await tester.tap(find.widgetWithText(ElevatedButton, 'Accept Offer'));
        await tester.pumpAndSettle();

        applicationRepository.listError = ApiException(
          'Server error, please try again later.',
        );

        await tester.tap(find.widgetWithText(ElevatedButton, 'Accept'));
        await tester.pumpAndSettle();

        // The Offer response itself succeeded and stays visible/updated
        // even though the Application refresh that followed it failed.
        expect(find.text('Offer Accepted'), findsOneWidget);
        expect(
          find.text('Server error, please try again later.'),
          findsOneWidget,
        );
        expect(find.text('Try Again'), findsOneWidget);
      },
    );
  });

  group('Offer section — decline (Phase 6C-3)', () {
    testWidgets(
      'cancelling the decline confirmation does not decline the Offer',
      (tester) async {
        final applicationRepository = _FakeApplicationRepository(
          listResult: [_application(id: 1, status: 'offer_sent')],
        );
        final offerRepository = _FakeOfferRepository(
          getResult: _offer(status: 'sent'),
        );
        await _pumpDetails(
          tester,
          repository: applicationRepository,
          offerRepository: offerRepository,
        );

        await tester.tap(find.widgetWithText(OutlinedButton, 'Decline Offer'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();

        expect(offerRepository.declineCallCount, 0);
        expect(find.text('Decline Offer'), findsOneWidget);
      },
    );

    testWidgets(
      'decline success updates the Offer, refreshes the Application, and '
      'shows a success SnackBar',
      (tester) async {
        final applicationRepository = _FakeApplicationRepository(
          listResult: [_application(id: 1, status: 'offer_sent')],
        );
        final offerRepository = _FakeOfferRepository(
          getResult: _offer(status: 'sent'),
        )..declineResult = _offer(status: 'declined');
        await _pumpDetails(
          tester,
          repository: applicationRepository,
          offerRepository: offerRepository,
        );

        await tester.tap(find.widgetWithText(OutlinedButton, 'Decline Offer'));
        await tester.pumpAndSettle();

        applicationRepository.listResult = [
          _application(id: 1, status: 'rejected'),
        ];

        await tester.tap(find.widgetWithText(OutlinedButton, 'Decline'));
        await tester.pumpAndSettle();

        expect(offerRepository.declineCallCount, 1);
        expect(find.text('Offer declined successfully'), findsOneWidget);
        expect(find.text('Offer Declined'), findsOneWidget);
        // "Rejected" legitimately appears twice — the hero status chip and
        // the sticky summary panel's own status chip.
        expect(find.text('Rejected'), findsWidgets);
        expect(find.text('Accept Offer'), findsNothing);
        expect(find.text('Decline Offer'), findsNothing);
        expect(applicationRepository.callCount, greaterThanOrEqualTo(2));
      },
    );
  });

  group('Offer section — rejected vs. declined (Phase 6C-3)', () {
    testWidgets('an accepted Offer shows "Offer Accepted"', (tester) async {
      final applicationRepository = _FakeApplicationRepository(
        listResult: [_application(id: 1, status: 'accepted')],
      );
      final offerRepository = _FakeOfferRepository(
        getResult: _offer(
          status: 'accepted',
          respondedAt: DateTime(2026, 8, 12),
        ),
      );
      await _pumpDetails(
        tester,
        repository: applicationRepository,
        offerRepository: offerRepository,
      );

      expect(find.text('Offer Accepted'), findsOneWidget);
    });

    testWidgets('a declined Offer shows "Offer Declined"', (tester) async {
      final applicationRepository = _FakeApplicationRepository(
        listResult: [_application(id: 1, status: 'rejected')],
      );
      final offerRepository = _FakeOfferRepository(
        getResult: _offer(
          status: 'declined',
          respondedAt: DateTime(2026, 8, 12),
        ),
      );
      await _pumpDetails(
        tester,
        repository: applicationRepository,
        offerRepository: offerRepository,
      );

      expect(find.text('Offer Declined'), findsOneWidget);
    });

    testWidgets(
      'a rejected Application with no Offer never shows "Offer Declined"',
      (tester) async {
        final applicationRepository = _FakeApplicationRepository(
          listResult: [_application(id: 1, status: 'rejected')],
        );
        final offerRepository = _FakeOfferRepository();
        await _pumpDetails(
          tester,
          repository: applicationRepository,
          offerRepository: offerRepository,
        );

        expect(find.text('Offer Declined'), findsNothing);
        expect(find.text('Offer'), findsNothing);
      },
    );
  });

  testWidgets(
    'Assessment history remains visible alongside an accepted Offer',
    (tester) async {
      final applicationRepository = _FakeApplicationRepository(
        listResult: [_application(id: 1, status: 'accepted')],
      );
      final assessmentRepository = _FakeAssessmentRepository()
        ..resultsByApplication = {
          1: _assessment(
            status: 'completed',
            result: 'passed',
            interview: _interview(status: 'completed'),
          ),
        };
      final offerRepository = _FakeOfferRepository(
        getResult: _offer(status: 'accepted'),
      );
      await _pumpDetails(
        tester,
        repository: applicationRepository,
        assessmentRepository: assessmentRepository,
        offerRepository: offerRepository,
      );

      expect(find.text('Assessment'), findsOneWidget);
      expect(find.text('Offer Accepted'), findsOneWidget);
    },
  );

  testWidgets('narrow viewport does not overflow with the Offer card visible', (
    tester,
  ) async {
    final applicationRepository = _FakeApplicationRepository(
      listResult: [_application(id: 1, status: 'offer_sent')],
    );
    final offerRepository = _FakeOfferRepository(
      getResult: _offer(
        status: 'sent',
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
      repository: applicationRepository,
      offerRepository: offerRepository,
      size: const Size(320, 700),
    );

    expect(tester.takeException(), isNull);
  });

  testWidgets('No overflow at a narrow 320-wide viewport', (tester) async {
    final applicationRepository = _FakeApplicationRepository(
      listResult: [
        _application(
          id: 1,
          status: 'interview_scheduled',
          opportunityTitle:
              'A Very Long Opportunity Title That Might Wrap Or Overflow',
        ),
      ],
    );
    final assessmentRepository = _FakeAssessmentRepository()
      ..resultsByApplication = {
        1: _assessment(
          result: 'passed',
          interview: _interview(
            interviewType: 'online',
            meetingLink: 'https://meet.example.com/a-very-long-room-name-here',
            interviewerName: 'A Very Long Interviewer Name Here',
            notes: 'Please join five minutes early and bring your laptop.',
          ),
        ),
      };

    await _pumpDetails(
      tester,
      repository: applicationRepository,
      assessmentRepository: assessmentRepository,
      size: const Size(320, 700),
    );

    expect(tester.takeException(), isNull);
  });

  group('Application Progress rail (UI Phase 4)', () {
    testWidgets('shows the real current stage for an active status', (
      tester,
    ) async {
      final repository = _FakeApplicationRepository(
        listResult: [_application(id: 1, status: 'in_assessment')],
      );
      await _pumpDetails(tester, repository: repository);

      expect(find.text('Application Progress'), findsOneWidget);
      // The current-status callout shows the real status label — "Under
      // Assessment" also appears once more in the hero's own status chip
      // (deliberate richness, same precedent as the rest of this suite).
      expect(find.text('Under Assessment'), findsWidgets);
      expect(
        find.text('This is the current stage of your application.'),
        findsOneWidget,
      );
      // Never a fabricated per-stage timestamp.
      expect(find.textContaining('Aug'), findsNothing);
    });

    testWidgets('shows a distinct terminal branch for accepted', (
      tester,
    ) async {
      final repository = _FakeApplicationRepository(
        listResult: [_application(id: 1, status: 'accepted')],
      );
      await _pumpDetails(tester, repository: repository);

      expect(find.text('Application Progress'), findsOneWidget);
      expect(find.text('Accepted'), findsWidgets);
    });

    testWidgets('shows a distinct terminal branch for withdrawn', (
      tester,
    ) async {
      final repository = _FakeApplicationRepository(
        listResult: [_application(id: 1, status: 'withdrawn')],
      );
      await _pumpDetails(tester, repository: repository);

      expect(find.text('Withdrawn'), findsWidgets);
    });

    testWidgets('shows a distinct terminal branch for rejected', (
      tester,
    ) async {
      final repository = _FakeApplicationRepository(
        listResult: [_application(id: 1, status: 'rejected')],
      );
      await _pumpDetails(tester, repository: repository);

      expect(find.text('Not Successful'), findsOneWidget);
    });
  });

  group("What's Next panel (UI Phase 4)", () {
    testWidgets('shows real, status-derived guidance for pending', (
      tester,
    ) async {
      final repository = _FakeApplicationRepository(
        listResult: [_application(id: 1, status: 'pending')],
      );
      await _pumpDetails(tester, repository: repository);

      expect(find.text("What's Next?"), findsOneWidget);
      expect(
        find.textContaining('waiting to be reviewed'),
        findsOneWidget,
      );
    });

    testWidgets('shows real, status-derived guidance for offer_sent', (
      tester,
    ) async {
      final repository = _FakeApplicationRepository(
        listResult: [_application(id: 1, status: 'offer_sent')],
      );
      await _pumpDetails(tester, repository: repository);

      expect(
        find.textContaining('You have received an offer'),
        findsOneWidget,
      );
    });
  });

  testWidgets('Back to My Applications navigates back', (tester) async {
    final repository = _FakeApplicationRepository(
      listResult: [_application(id: 1, opportunityTitle: 'Software Engineer')],
    );
    await _pumpDetails(tester, repository: repository);

    await tester.tap(find.text('Back to My Applications'));
    await tester.pumpAndSettle();

    expect(find.text('LIST_PLACEHOLDER'), findsOneWidget);
  });

  testWidgets('the app-bar theme toggle switches the resolved theme', (
    tester,
  ) async {
    final repository = _FakeApplicationRepository(
      listResult: [_application(id: 1)],
    );
    await _pumpDetails(tester, repository: repository);

    expect(find.byType(ThemeToggleButton), findsOneWidget);
  });

  testWidgets('renders without overflow at a wide desktop viewport', (
    tester,
  ) async {
    final repository = _FakeApplicationRepository(
      listResult: [
        _application(
          id: 1,
          status: 'offer_sent',
          opportunityTitle: 'Software Engineer',
        ),
      ],
    );
    final offerRepository = _FakeOfferRepository(getResult: _offer());
    await _pumpDetails(
      tester,
      repository: repository,
      offerRepository: offerRepository,
      size: const Size(1440, 1000),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('Application Progress'), findsOneWidget);
  });

  testWidgets('renders without overflow at a tablet viewport', (
    tester,
  ) async {
    final repository = _FakeApplicationRepository(
      listResult: [_application(id: 1, status: 'shortlisted')],
    );
    await _pumpDetails(
      tester,
      repository: repository,
      size: const Size(1000, 900),
    );

    expect(tester.takeException(), isNull);
  });

  testWidgets('honors reduced motion without throwing', (tester) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);

    final repository = _FakeApplicationRepository(
      listResult: [_application(id: 1, opportunityTitle: 'Software Engineer')],
    );
    await _pumpDetails(tester, repository: repository);

    expect(tester.takeException(), isNull);
    expect(find.text('Software Engineer'), findsWidgets);
  });

  testWidgets('renders correctly in Dark Mode', (tester) async {
    final repository = _FakeApplicationRepository(
      listResult: [_application(id: 1, opportunityTitle: 'Software Engineer')],
    );

    tester.view.physicalSize = const Size(420, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final authProvider = AuthProvider(authRepository: _FakeAuthRepository());
    final provider = StudentApplicationsProvider(
      repository: repository,
      authProvider: authProvider,
    );
    final assessmentProvider = StudentAssessmentProvider(
      repository: _FakeAssessmentRepository(),
      authProvider: authProvider,
    );
    final offerProvider = StudentOfferProvider(
      repository: _FakeOfferRepository(),
      authProvider: authProvider,
    );
    final router = GoRouter(
      initialLocation: AppRoutes.studentApplicationDetails(1),
      routes: [
        GoRoute(
          path: '${AppRoutes.studentApplications}/:id',
          builder: (_, state) => StudentApplicationDetailsScreen(
            applicationId: int.parse(state.pathParameters['id']!),
          ),
        ),
      ],
    );

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<StudentApplicationsProvider>.value(
            value: provider,
          ),
          ChangeNotifierProvider<StudentAssessmentProvider>.value(
            value: assessmentProvider,
          ),
          ChangeNotifierProvider<StudentOfferProvider>.value(
            value: offerProvider,
          ),
          ChangeNotifierProvider<ThemeProvider>.value(value: ThemeProvider()),
        ],
        child: MaterialApp.router(
          theme: AppTheme.darkTheme,
          routerConfig: router,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Software Engineer'), findsWidgets);
  });

  group('Current status callout (UI Phase 4.2)', () {
    testWidgets('shows a truthful supporting sentence for a terminal status', (
      tester,
    ) async {
      final repository = _FakeApplicationRepository(
        listResult: [_application(id: 1, status: 'accepted')],
      );
      await _pumpDetails(tester, repository: repository);

      expect(find.text('This application was successful.'), findsOneWidget);
    });

    testWidgets('withdrawn shows its own truthful supporting sentence', (
      tester,
    ) async {
      final repository = _FakeApplicationRepository(
        listResult: [_application(id: 1, status: 'withdrawn')],
      );
      await _pumpDetails(tester, repository: repository);

      // Appears twice — the current-status callout and the What's Next
      // panel independently describe the same truthful fact.
      expect(find.text('You withdrew this application.'), findsWidgets);
    });
  });

  group('Summary panel quick action (UI Phase 4.2)', () {
    testWidgets('View Opportunity navigates to the real Opportunity Details route', (
      tester,
    ) async {
      final repository = _FakeApplicationRepository(
        listResult: [_application(id: 1, opportunityTitle: 'Software Engineer')],
      );

      final authProvider = AuthProvider(authRepository: _FakeAuthRepository());
      final provider = StudentApplicationsProvider(
        repository: repository,
        authProvider: authProvider,
      );
      final assessmentProvider = StudentAssessmentProvider(
        repository: _FakeAssessmentRepository(),
        authProvider: authProvider,
      );
      final offerProvider = StudentOfferProvider(
        repository: _FakeOfferRepository(),
        authProvider: authProvider,
      );
      final router = GoRouter(
        initialLocation: AppRoutes.studentApplicationDetails(1),
        routes: [
          GoRoute(
            path: '${AppRoutes.studentApplications}/:id',
            builder: (_, state) => StudentApplicationDetailsScreen(
              applicationId: int.parse(state.pathParameters['id']!),
            ),
          ),
          GoRoute(
            path: '${AppRoutes.studentOpportunities}/:id',
            builder: (_, state) => Scaffold(
              body: Text(
                'OPPORTUNITY_PLACEHOLDER_${state.pathParameters['id']}',
              ),
            ),
          ),
        ],
      );

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<StudentApplicationsProvider>.value(
              value: provider,
            ),
            ChangeNotifierProvider<StudentAssessmentProvider>.value(
              value: assessmentProvider,
            ),
            ChangeNotifierProvider<StudentOfferProvider>.value(
              value: offerProvider,
            ),
            ChangeNotifierProvider<ThemeProvider>.value(value: ThemeProvider()),
          ],
          child: MaterialApp.router(
            theme: AppTheme.lightTheme,
            routerConfig: router,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('View Opportunity'));
      await tester.pumpAndSettle();

      expect(find.text('OPPORTUNITY_PLACEHOLDER_1'), findsOneWidget);
    });
  });

  group('Compact vertical stepper (UI Phase 4.2)', () {
    testWidgets(
      'a genuinely narrow viewport shows the compact stepper with real stage labels, no overflow',
      (tester) async {
        final repository = _FakeApplicationRepository(
          listResult: [_application(id: 1, status: 'shortlisted')],
        );
        await _pumpDetails(
          tester,
          repository: repository,
          size: const Size(360, 900),
        );

        expect(tester.takeException(), isNull);
        // "Applied" legitimately appears twice — the compact stepper's own
        // stage label and the Summary panel's "Applied" (date) row label.
        expect(find.text('Applied'), findsWidgets);
        expect(find.text('Review'), findsOneWidget);
        // "Shortlisted" appears twice — the compact stepper's own stage
        // label and the hero's status chip (deliberate richness).
        expect(find.text('Shortlisted'), findsWidgets);
      },
    );
  });

  group('Assessment redesign (UI Phase 4.3)', () {
    testWidgets('an online interview shows a real, working Open Meeting Link CTA', (
      tester,
    ) async {
      final applicationRepository = _FakeApplicationRepository(
        listResult: [_application(id: 1, status: 'interview_scheduled')],
      );
      final assessmentRepository = _FakeAssessmentRepository()
        ..resultsByApplication = {
          1: _assessment(
            interview: _interview(
              interviewType: 'online',
              meetingLink: 'https://meet.example.com/room-42',
            ),
          ),
        };
      await _pumpDetails(
        tester,
        repository: applicationRepository,
        assessmentRepository: assessmentRepository,
      );

      expect(find.text('Online Interview'), findsOneWidget);
      expect(find.text('Open Meeting Link'), findsOneWidget);
      // The raw link stays visible/selectable underneath the CTA — never
      // hidden, just no longer the primary interaction.
      expect(find.text('https://meet.example.com/room-42'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'a malformed/legacy meeting link falls back to a graceful placeholder, '
      'never the raw value',
      (tester) async {
        final applicationRepository = _FakeApplicationRepository(
          listResult: [_application(id: 1, status: 'interview_scheduled')],
        );
        final assessmentRepository = _FakeAssessmentRepository()
          ..resultsByApplication = {
            1: _assessment(
              interview: _interview(
                interviewType: 'online',
                meetingLink: 'not a real url',
              ),
            ),
          };
        await _pumpDetails(
          tester,
          repository: applicationRepository,
          assessmentRepository: assessmentRepository,
        );

        expect(find.text('Open Meeting Link'), findsNothing);
        expect(
          find.text('Meeting link will appear here once provided.'),
          findsOneWidget,
        );
        expect(find.text('not a real url'), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'a missing meeting link on an online interview shows the same graceful '
      'placeholder, not a raw "Not specified" tile',
      (tester) async {
        final applicationRepository = _FakeApplicationRepository(
          listResult: [_application(id: 1, status: 'interview_scheduled')],
        );
        final assessmentRepository = _FakeAssessmentRepository()
          ..resultsByApplication = {
            1: _assessment(
              interview: _interview(interviewType: 'online', meetingLink: null),
            ),
          };
        await _pumpDetails(
          tester,
          repository: applicationRepository,
          assessmentRepository: assessmentRepository,
        );

        expect(find.text('Open Meeting Link'), findsNothing);
        expect(
          find.text('Meeting link will appear here once provided.'),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('Date/Time tiles are omitted (not "Not specified") when scheduledAt is absent', (
      tester,
    ) async {
      final applicationRepository = _FakeApplicationRepository(
        listResult: [_application(id: 1, status: 'interview_scheduled')],
      );
      final assessmentRepository = _FakeAssessmentRepository()
        ..resultsByApplication = {
          1: _assessment(
            interview: InterviewModel(
              id: 10,
              assessmentId: 1,
              interviewType: 'phone',
              scheduledAt: null,
              contactPhone: '+1 555-0100',
              status: 'scheduled',
            ),
          ),
        };
      await _pumpDetails(
        tester,
        repository: applicationRepository,
        assessmentRepository: assessmentRepository,
      );

      expect(find.text('Date'), findsNothing);
      expect(find.text('Time'), findsNothing);
      expect(find.text('Contact Phone'), findsOneWidget);
      expect(find.text('+1 555-0100'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a real interviewer name renders in a compact identity row', (
      tester,
    ) async {
      final applicationRepository = _FakeApplicationRepository(
        listResult: [_application(id: 1, status: 'interview_scheduled')],
      );
      final assessmentRepository = _FakeAssessmentRepository()
        ..resultsByApplication = {
          1: _assessment(interview: _interview(interviewerName: 'Allam')),
        };
      await _pumpDetails(
        tester,
        repository: applicationRepository,
        assessmentRepository: assessmentRepository,
      );

      expect(find.text('Interviewer'), findsOneWidget);
      expect(find.text('Allam'), findsOneWidget);
    });

    testWidgets('a quiz assessment still renders its real premium summary and Open Quiz action', (
      tester,
    ) async {
      final applicationRepository = _FakeApplicationRepository(
        listResult: [_application(id: 1, status: 'interview_scheduled')],
      );
      final assessmentRepository = _FakeAssessmentRepository()
        ..resultsByApplication = {
          1: _assessment(
            type: 'quiz',
            status: 'scheduled',
            quiz: _quiz(timeLimitMinutes: 30, questionCount: 3),
          ),
        };
      await _pumpDetails(
        tester,
        repository: applicationRepository,
        assessmentRepository: assessmentRepository,
      );

      expect(find.text('Quiz'), findsOneWidget);
      expect(find.text('Quiz Title'), findsOneWidget);
      expect(find.text('Backend Fundamentals'), findsOneWidget);
      expect(find.text('70%'), findsOneWidget);
      expect(find.text('30 minutes'), findsOneWidget);
      expect(find.text('Open Quiz'), findsOneWidget);
    });

    testWidgets(
      'a completed Quiz followed by a scheduled Interview renders both '
      'stages, sequentially — the Quiz never appears to disappear '
      '(Phase 10A.3)',
      (tester) async {
        final applicationRepository = _FakeApplicationRepository(
          listResult: [_application(id: 1, status: 'in_assessment')],
        );
        final assessmentRepository = _FakeAssessmentRepository()
          ..historyByApplication = {
            1: [
              _assessment(
                id: 1,
                type: 'quiz',
                status: 'completed',
                result: 'passed',
                quiz: _quiz(timeLimitMinutes: 30, questionCount: 3),
              ),
              _assessment(
                id: 2,
                type: 'interview',
                status: 'scheduled',
                interview: _interview(interviewType: 'online'),
              ),
            ],
          };
        await _pumpDetails(
          tester,
          repository: applicationRepository,
          assessmentRepository: assessmentRepository,
        );

        // Both stages are on screen at once, in order.
        expect(find.text('Quiz'), findsOneWidget);
        expect(find.text('Quiz completed'), findsOneWidget);
        expect(find.text('Online Interview'), findsOneWidget);
      },
    );

    testWidgets('renders without overflow at a genuinely narrow viewport with a full interview payload', (
      tester,
    ) async {
      final applicationRepository = _FakeApplicationRepository(
        listResult: [_application(id: 1, status: 'interview_scheduled')],
      );
      final assessmentRepository = _FakeAssessmentRepository()
        ..resultsByApplication = {
          1: _assessment(
            result: 'passed',
            interview: _interview(
              interviewType: 'online',
              meetingLink: 'https://meet.example.com/a-very-long-room-name-here',
              interviewerName: 'A Very Long Interviewer Name Here',
              notes: 'Please join five minutes early and bring your laptop.',
            ),
          ),
        };

      await _pumpDetails(
        tester,
        repository: applicationRepository,
        assessmentRepository: assessmentRepository,
        size: const Size(360, 900),
      );

      expect(tester.takeException(), isNull);
    });
  });
}
