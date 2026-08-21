// Widget tests for StudentOpportunityDetailsScreen, in isolation with a
// small GoRouter.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'package:opportunityhub_flutter/core/api/api_client.dart';
import 'package:opportunityhub_flutter/core/storage/token_storage_service.dart';
import 'package:opportunityhub_flutter/core/theme/app_theme.dart';
import 'package:opportunityhub_flutter/features/applications/data/application_repository.dart';
import 'package:opportunityhub_flutter/features/auth/data/auth_repository.dart';
import 'package:opportunityhub_flutter/features/cv/data/cv_repository.dart';
import 'package:opportunityhub_flutter/features/opportunities/data/opportunity_repository.dart';
import 'package:opportunityhub_flutter/features/opportunities/presentation/student_opportunity_details_screen.dart';
import 'package:opportunityhub_flutter/features/skills/data/student_skill_repository.dart';
import 'package:opportunityhub_flutter/models/application_model.dart';
import 'package:opportunityhub_flutter/models/cv_model.dart';
import 'package:opportunityhub_flutter/models/opportunity_model.dart';
import 'package:opportunityhub_flutter/models/opportunity_skill_model.dart';
import 'package:opportunityhub_flutter/models/organization_profile_model.dart';
import 'package:opportunityhub_flutter/models/skill_model.dart';
import 'package:opportunityhub_flutter/providers/auth_provider.dart';
import 'package:opportunityhub_flutter/providers/student_applications_provider.dart';
import 'package:opportunityhub_flutter/providers/student_cv_provider.dart';
import 'package:opportunityhub_flutter/providers/student_opportunities_provider.dart';
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

OpportunityModel _opportunity({
  int id = 1,
  String title = 'Software Engineer',
  OrganizationProfileModel? organizationProfile,
  List<OpportunitySkillModel> opportunitySkills = const [],
}) {
  return OpportunityModel(
    id: id,
    title: title,
    description: 'A great opportunity.',
    opportunityType: 'job',
    employmentType: 'full_time',
    workMode: 'remote',
    experienceLevel: 'junior',
    positionsAvailable: 2,
    status: 'open',
    location: 'Amman, Jordan',
    organizationProfile: organizationProfile,
    opportunitySkills: opportunitySkills,
  );
}

class _FakeOpportunityRepository extends OpportunityRepository {
  _FakeOpportunityRepository({this.getResult, this.getError})
    : super(apiClient: ApiClient(tokenStorageService: TokenStorageService()));

  OpportunityModel? getResult;
  ApiException? getError;

  @override
  Future<OpportunityModel> getPublicOpportunity(int id) async {
    if (getError != null) throw getError!;
    return getResult!;
  }
}

class _FakeCvRepository extends CvRepository {
  _FakeCvRepository({this.listResult = const []})
    : super(apiClient: ApiClient(tokenStorageService: TokenStorageService()));

  List<CvModel> listResult;

  @override
  Future<List<CvModel>> getStudentCvs() async => listResult;
}

class _FakeApplicationRepository extends ApplicationRepository {
  _FakeApplicationRepository({this.listResult = const [], this.applyResult})
    : super(apiClient: ApiClient(tokenStorageService: TokenStorageService()));

  List<ApplicationModel> listResult;
  ApplicationModel? applyResult;

  @override
  Future<List<ApplicationModel>> getStudentApplications() async => listResult;

  @override
  Future<ApplicationModel> applyToOpportunity({
    required int opportunityId,
    required int cvId,
    String? coverLetter,
  }) async => applyResult!;
}

ApplicationModel _application({required int opportunityId}) {
  return ApplicationModel(
    id: 1,
    studentId: 1,
    opportunityId: opportunityId,
    cvId: 1,
    status: 'pending',
    opportunity: _opportunity(id: opportunityId),
    cv: const CvModel(
      id: 1,
      studentId: 1,
      title: 'My CV',
      filePath: 'cvs/my-cv.pdf',
      version: 1,
      isDefault: true,
      createdByAi: false,
    ),
  );
}

Future<StudentOpportunitiesProvider> _pumpDetails(
  WidgetTester tester, {
  required _FakeOpportunityRepository repository,
  _FakeCvRepository? cvRepository,
  _FakeApplicationRepository? applicationRepository,
  int opportunityId = 1,
  Size size = const Size(420, 1400),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final authProvider = AuthProvider(authRepository: _FakeAuthRepository());
  final provider = StudentOpportunitiesProvider(
    repository: repository,
    authProvider: authProvider,
  );
  final cvProvider = StudentCvProvider(
    repository: cvRepository ?? _FakeCvRepository(),
    studentSkillRepository: StudentSkillRepository(
      apiClient: ApiClient(tokenStorageService: TokenStorageService()),
    ),
    authProvider: authProvider,
  );
  final applicationsProvider = StudentApplicationsProvider(
    repository: applicationRepository ?? _FakeApplicationRepository(),
    authProvider: authProvider,
  );

  final router = GoRouter(
    initialLocation: AppRoutes.studentOpportunityDetails(opportunityId),
    routes: [
      GoRoute(
        path: AppRoutes.studentOpportunities,
        builder: (_, _) => const Scaffold(body: Text('LIST_PLACEHOLDER')),
      ),
      GoRoute(
        path: AppRoutes.studentCvs,
        builder: (_, _) => const Scaffold(body: Text('CVS_PLACEHOLDER')),
      ),
      GoRoute(
        path: '${AppRoutes.studentOpportunities}/:id',
        builder: (_, state) => StudentOpportunityDetailsScreen(
          opportunityId: int.parse(state.pathParameters['id']!),
        ),
      ),
    ],
  );

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<StudentOpportunitiesProvider>.value(
          value: provider,
        ),
        ChangeNotifierProvider<StudentCvProvider>.value(value: cvProvider),
        ChangeNotifierProvider<StudentApplicationsProvider>.value(
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

  return provider;
}

void main() {
  testWidgets('Direct ID route works without any extra', (tester) async {
    final repository = _FakeOpportunityRepository(
      getResult: _opportunity(id: 42, title: 'Data Analyst'),
    );
    await _pumpDetails(tester, repository: repository, opportunityId: 42);

    expect(find.text('Data Analyst'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Real fields render, including nested organization name', (
    tester,
  ) async {
    final repository = _FakeOpportunityRepository(
      getResult: _opportunity(
        title: 'Software Engineer',
        organizationProfile: const OrganizationProfileModel(
          id: 3,
          organizationName: 'Acme Corp',
          organizationType: 'company',
          approvalStatus: 'approved',
        ),
      ),
    );
    await _pumpDetails(tester, repository: repository);

    expect(find.text('Software Engineer'), findsOneWidget);
    expect(find.text('Acme Corp'), findsOneWidget);
    expect(find.text('Job'), findsOneWidget);
    expect(find.text('Full Time'), findsOneWidget);
    expect(find.text('Remote'), findsOneWidget);
    expect(find.text('Junior'), findsOneWidget);
    expect(find.text('A great opportunity.'), findsOneWidget);
    expect(find.text('Amman, Jordan'), findsOneWidget);
  });

  testWidgets('Nested skills render as chips when present', (tester) async {
    final repository = _FakeOpportunityRepository(
      getResult: _opportunity(
        opportunitySkills: const [
          OpportunitySkillModel(
            id: 1,
            isRequired: true,
            skill: SkillModel(id: 1, name: 'Flutter'),
          ),
          OpportunitySkillModel(
            id: 2,
            isRequired: false,
            skill: SkillModel(id: 2, name: 'Figma'),
          ),
        ],
      ),
    );
    await _pumpDetails(tester, repository: repository);

    expect(find.text('Flutter (Required)'), findsOneWidget);
    expect(find.text('Figma'), findsOneWidget);
  });

  testWidgets('No Skills section renders when there are none', (tester) async {
    final repository = _FakeOpportunityRepository(getResult: _opportunity());
    await _pumpDetails(tester, repository: repository);

    expect(find.text('Skills'), findsNothing);
  });

  testWidgets('Not-found error state renders safely, no crash', (tester) async {
    final repository = _FakeOpportunityRepository(
      getError: ApiException('Opportunity not found'),
    );
    await _pumpDetails(tester, repository: repository, opportunityId: 999);

    expect(find.text('Opportunity not found'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'No save/edit/delete/applicant/interview/quiz UI appears anywhere',
    (tester) async {
      final repository = _FakeOpportunityRepository(getResult: _opportunity());
      await _pumpDetails(tester, repository: repository);

      expect(find.textContaining('Save'), findsNothing);
      expect(find.byIcon(Icons.edit_outlined), findsNothing);
      expect(find.byIcon(Icons.delete_outline), findsNothing);
      expect(find.textContaining('Applicant'), findsNothing);
      expect(find.textContaining('Interview'), findsNothing);
      expect(find.textContaining('Quiz'), findsNothing);
    },
  );

  testWidgets('Apply Now renders when the student has not applied yet', (
    tester,
  ) async {
    final repository = _FakeOpportunityRepository(
      getResult: _opportunity(id: 1),
    );
    await _pumpDetails(tester, repository: repository, opportunityId: 1);

    expect(find.text('Apply Now'), findsOneWidget);
    expect(find.text('Already Applied'), findsNothing);
  });

  testWidgets(
    'Already Applied renders instead of Apply Now when hasAppliedTo is true',
    (tester) async {
      final repository = _FakeOpportunityRepository(
        getResult: _opportunity(id: 1),
      );
      await _pumpDetails(
        tester,
        repository: repository,
        opportunityId: 1,
        applicationRepository: _FakeApplicationRepository(
          listResult: [_application(opportunityId: 1)],
        ),
      );

      expect(find.text('Already Applied'), findsOneWidget);
      expect(find.text('Apply Now'), findsNothing);
    },
  );

  testWidgets('Tapping Apply Now opens the apply bottom sheet', (tester) async {
    final repository = _FakeOpportunityRepository(
      getResult: _opportunity(id: 1, title: 'Software Engineer'),
    );
    await _pumpDetails(
      tester,
      repository: repository,
      opportunityId: 1,
      cvRepository: _FakeCvRepository(
        listResult: [
          const CvModel(
            id: 1,
            studentId: 1,
            title: 'My CV',
            filePath: 'cvs/my-cv.pdf',
            version: 1,
            isDefault: true,
            createdByAi: false,
          ),
        ],
      ),
    );

    await tester.tap(find.text('Apply Now'));
    await tester.pumpAndSettle();

    expect(find.text('Apply to Software Engineer'), findsOneWidget);
    expect(find.text('Submit Application'), findsOneWidget);
  });

  testWidgets(
    'Full apply flow: Apply Now -> select CV -> submit -> sheet closes -> '
    'this same screen immediately shows Already Applied, no restart',
    (tester) async {
      const cv = CvModel(
        id: 1,
        studentId: 1,
        title: 'My CV',
        filePath: 'cvs/my-cv.pdf',
        version: 1,
        isDefault: true,
        createdByAi: false,
      );
      final repository = _FakeOpportunityRepository(
        getResult: _opportunity(id: 1, title: 'Software Engineer'),
      );
      final applicationRepository = _FakeApplicationRepository(
        applyResult: ApplicationModel(
          id: 99,
          studentId: 1,
          opportunityId: 1,
          cvId: 1,
          status: 'pending',
          opportunity: _opportunity(id: 1, title: 'Software Engineer'),
          cv: cv,
        ),
      );

      await _pumpDetails(
        tester,
        repository: repository,
        opportunityId: 1,
        cvRepository: _FakeCvRepository(listResult: [cv]),
        applicationRepository: applicationRepository,
      );

      // Starting state: not yet applied.
      expect(find.text('Apply Now'), findsOneWidget);
      expect(find.text('Already Applied'), findsNothing);

      // Tap Apply.
      await tester.tap(find.text('Apply Now'));
      await tester.pumpAndSettle();
      expect(find.text('Submit Application'), findsOneWidget);

      // The default (only) CV is already pre-selected — submit.
      await tester.tap(find.text('Submit Application'));
      await tester.pumpAndSettle();

      // The sheet closed and a success snackbar appeared.
      expect(find.text('Submit Application'), findsNothing);
      expect(find.text('Application submitted successfully'), findsOneWidget);

      // The very same StudentOpportunityDetailsScreen instance — never
      // rebuilt/remounted/restarted — now shows Already Applied instead
      // of Apply Now.
      expect(find.text('Already Applied'), findsOneWidget);
      expect(find.text('Apply Now'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
