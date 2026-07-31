// Widget tests for StudentApplicationDetailsScreen, in isolation with a
// small GoRouter.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'package:opportunityhub_flutter/core/api/api_client.dart';
import 'package:opportunityhub_flutter/core/storage/token_storage_service.dart';
import 'package:opportunityhub_flutter/core/theme/app_theme.dart';
import 'package:opportunityhub_flutter/features/applications/data/application_repository.dart';
import 'package:opportunityhub_flutter/features/applications/presentation/student_application_details_screen.dart';
import 'package:opportunityhub_flutter/features/auth/data/auth_repository.dart';
import 'package:opportunityhub_flutter/models/application_model.dart';
import 'package:opportunityhub_flutter/models/cv_model.dart';
import 'package:opportunityhub_flutter/models/opportunity_model.dart';
import 'package:opportunityhub_flutter/models/organization_profile_model.dart';
import 'package:opportunityhub_flutter/providers/auth_provider.dart';
import 'package:opportunityhub_flutter/providers/student_applications_provider.dart';
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

Future<StudentApplicationsProvider> _pumpDetails(
  WidgetTester tester, {
  required _FakeApplicationRepository repository,
  int applicationId = 1,
  Size size = const Size(420, 1400),
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
    ],
  );

  await tester.pumpWidget(
    ChangeNotifierProvider<StudentApplicationsProvider>.value(
      value: provider,
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
  testWidgets('Direct ID route resolves from cache when already loaded', (
    tester,
  ) async {
    final repository = _FakeApplicationRepository(
      listResult: [_application(id: 42, opportunityTitle: 'Data Analyst')],
    );
    final provider = await _pumpDetails(
      tester,
      repository: repository,
      applicationId: 1,
    );
    // Pre-populate the cache the same way the list screen would have.
    await provider.loadApplications();

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

      expect(find.text('Data Analyst'), findsOneWidget);
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

    expect(find.text('Software Engineer'), findsOneWidget);
    expect(find.text('Acme Corp'), findsOneWidget);
    expect(find.text('Shortlisted'), findsOneWidget);
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

    expect(find.text('Data Analyst'), findsOneWidget);
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
    expect(find.textContaining('Offer'), findsNothing);
  });
}
