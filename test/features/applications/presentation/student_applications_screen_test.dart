// Widget tests for StudentApplicationsScreen, in isolation with a small
// GoRouter.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'package:opportunityhub_flutter/core/api/api_client.dart';
import 'package:opportunityhub_flutter/core/storage/token_storage_service.dart';
import 'package:opportunityhub_flutter/core/theme/app_theme.dart';
import 'package:opportunityhub_flutter/features/applications/data/application_repository.dart';
import 'package:opportunityhub_flutter/features/applications/presentation/student_applications_screen.dart';
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
  _FakeApplicationRepository({
    this.listResult = const [],
    this.listError,
    this.listDelay = Duration.zero,
  }) : super(apiClient: ApiClient(tokenStorageService: TokenStorageService()));

  List<ApplicationModel> listResult;
  ApiException? listError;
  Duration listDelay;
  int callCount = 0;

  @override
  Future<List<ApplicationModel>> getStudentApplications() async {
    callCount++;
    if (listDelay > Duration.zero) {
      await Future<void>.delayed(listDelay);
    }
    if (listError != null) throw listError!;
    return listResult;
  }
}

ApplicationModel _application({
  int id = 1,
  int opportunityId = 1,
  String status = 'pending',
  String opportunityTitle = 'Software Engineer',
  OrganizationProfileModel? organizationProfile,
}) {
  return ApplicationModel(
    id: id,
    studentId: 1,
    opportunityId: opportunityId,
    cvId: 1,
    status: status,
    opportunity: OpportunityModel(
      id: opportunityId,
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
    appliedAt: DateTime(2026, 7, 20),
  );
}

Future<StudentApplicationsProvider> _pumpScreen(
  WidgetTester tester, {
  required _FakeApplicationRepository repository,
  Size size = const Size(420, 800),
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
    initialLocation: AppRoutes.studentApplications,
    routes: [
      GoRoute(
        path: AppRoutes.studentApplications,
        builder: (_, _) => const StudentApplicationsScreen(),
      ),
      GoRoute(
        path: '${AppRoutes.studentApplications}/:id',
        builder: (_, state) => Scaffold(
          body: Text(
            'DETAILS_SCREEN_PLACEHOLDER_${state.pathParameters['id']}',
          ),
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
  testWidgets('Loading state renders while the list is in flight', (
    tester,
  ) async {
    final repository = _FakeApplicationRepository(
      listDelay: const Duration(milliseconds: 200),
    );
    tester.view.physicalSize = const Size(420, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final authProvider = AuthProvider(authRepository: _FakeAuthRepository());
    final provider = StudentApplicationsProvider(
      repository: repository,
      authProvider: authProvider,
    );
    final router = GoRouter(
      initialLocation: AppRoutes.studentApplications,
      routes: [
        GoRoute(
          path: AppRoutes.studentApplications,
          builder: (_, _) => const StudentApplicationsScreen(),
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
    await tester.pump();
    await tester.pump();

    expect(find.text('My Applications'), findsOneWidget);
    expect(provider.isLoadingList, isTrue);

    await tester.pumpAndSettle();
  });

  testWidgets('Empty state renders when there are no applications', (
    tester,
  ) async {
    await _pumpScreen(tester, repository: _FakeApplicationRepository());

    expect(find.text('No Applications Yet'), findsOneWidget);
  });

  testWidgets('Error state renders on load failure, with retry', (
    tester,
  ) async {
    final repository = _FakeApplicationRepository(
      listError: ApiException('Server error, please try again later.'),
    );
    await _pumpScreen(tester, repository: repository);

    expect(find.text('Server error, please try again later.'), findsOneWidget);

    repository.listError = null;
    repository.listResult = [_application()];
    await tester.tap(find.text('Try Again'));
    await tester.pumpAndSettle();

    expect(find.text('Software Engineer'), findsOneWidget);
  });

  testWidgets(
    'Populated list shows opportunity, organization, status, CV title, and applied date',
    (tester) async {
      final repository = _FakeApplicationRepository(
        listResult: [
          _application(
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
      await _pumpScreen(tester, repository: repository);

      expect(find.text('Software Engineer'), findsOneWidget);
      expect(find.text('Acme Corp'), findsOneWidget);
      expect(find.text('Shortlisted'), findsOneWidget);
      expect(find.text('CV: My CV'), findsOneWidget);
      expect(find.textContaining('Applied'), findsOneWidget);
    },
  );

  testWidgets('No organization line renders when the relation is absent', (
    tester,
  ) async {
    final repository = _FakeApplicationRepository(listResult: [_application()]);
    await _pumpScreen(tester, repository: repository);

    expect(find.text('Acme Corp'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Tapping a card opens its details route by ID', (tester) async {
    final repository = _FakeApplicationRepository(
      listResult: [_application(id: 42)],
    );
    await _pumpScreen(tester, repository: repository);

    await tester.tap(find.text('Software Engineer'));
    await tester.pumpAndSettle();

    expect(find.text('DETAILS_SCREEN_PLACEHOLDER_42'), findsOneWidget);
  });

  testWidgets('Pull-to-refresh does not duplicate data', (tester) async {
    final repository = _FakeApplicationRepository(
      listResult: [_application(id: 1)],
    );
    await _pumpScreen(tester, repository: repository);

    expect(find.text('Software Engineer'), findsOneWidget);

    await tester.fling(
      find.byType(RefreshIndicator),
      const Offset(0, 300),
      1000,
    );
    await tester.pumpAndSettle();

    expect(find.text('Software Engineer'), findsOneWidget);
    expect(repository.callCount, greaterThanOrEqualTo(2));
  });

  testWidgets('Does not overflow at a narrow 320x720 viewport', (tester) async {
    final repository = _FakeApplicationRepository(
      listResult: [
        _application(id: 1, opportunityTitle: 'Software Engineer'),
        _application(id: 2, opportunityTitle: 'Marketing Intern'),
      ],
    );
    await _pumpScreen(
      tester,
      repository: repository,
      size: const Size(320, 720),
    );

    expect(tester.takeException(), isNull);
  });
}
