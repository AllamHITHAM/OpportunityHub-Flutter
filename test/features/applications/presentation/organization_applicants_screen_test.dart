// Widget tests for OrganizationApplicantsScreen, in isolation with a small
// GoRouter.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'package:opportunityhub_flutter/core/api/api_client.dart';
import 'package:opportunityhub_flutter/core/storage/token_storage_service.dart';
import 'package:opportunityhub_flutter/core/theme/app_theme.dart';
import 'package:opportunityhub_flutter/features/applications/data/application_repository.dart';
import 'package:opportunityhub_flutter/features/applications/presentation/organization_applicants_screen.dart';
import 'package:opportunityhub_flutter/features/auth/data/auth_repository.dart';
import 'package:opportunityhub_flutter/models/applicant_summary_model.dart';
import 'package:opportunityhub_flutter/models/application_model.dart';
import 'package:opportunityhub_flutter/models/cv_model.dart';
import 'package:opportunityhub_flutter/providers/auth_provider.dart';
import 'package:opportunityhub_flutter/providers/organization_applications_provider.dart';
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
  isDefault: false,
  createdByAi: false,
);

ApplicationModel _application({
  int id = 1,
  String status = 'pending',
  ApplicantSummaryModel? applicant,
  double? matchScore,
}) {
  return ApplicationModel(
    id: id,
    studentId: 1,
    opportunityId: 5,
    cvId: 2,
    status: status,
    cv: _cv,
    applicant: applicant,
    matchScore: matchScore,
    appliedAt: DateTime(2026, 7, 20),
  );
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
  Future<List<ApplicationModel>> getApplicationsForOpportunity(
    int opportunityId,
  ) async {
    callCount++;
    if (listDelay > Duration.zero) {
      await Future<void>.delayed(listDelay);
    }
    if (listError != null) throw listError!;
    return listResult;
  }
}

Future<OrganizationApplicationsProvider> _pumpScreen(
  WidgetTester tester, {
  required _FakeApplicationRepository repository,
  Size size = const Size(420, 800),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final authProvider = AuthProvider(authRepository: _FakeAuthRepository());
  final provider = OrganizationApplicationsProvider(
    repository: repository,
    authProvider: authProvider,
  );

  final router = GoRouter(
    initialLocation: AppRoutes.organizationApplicants(5),
    routes: [
      GoRoute(
        path: '${AppRoutes.organizationOpportunities}/:id/applicants',
        builder: (_, state) => OrganizationApplicantsScreen(
          opportunityId: int.parse(state.pathParameters['id']!),
        ),
      ),
      GoRoute(
        path: '${AppRoutes.organizationApplications}/:id',
        builder: (_, state) => Scaffold(
          body: Text(
            'APPLICATION_DETAILS_PLACEHOLDER_${state.pathParameters['id']}',
          ),
        ),
      ),
    ],
  );

  await tester.pumpWidget(
    ChangeNotifierProvider<OrganizationApplicationsProvider>.value(
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
    final provider = OrganizationApplicationsProvider(
      repository: repository,
      authProvider: authProvider,
    );
    final router = GoRouter(
      initialLocation: AppRoutes.organizationApplicants(5),
      routes: [
        GoRoute(
          path: '${AppRoutes.organizationOpportunities}/:id/applicants',
          builder: (_, state) => OrganizationApplicantsScreen(
            opportunityId: int.parse(state.pathParameters['id']!),
          ),
        ),
      ],
    );

    await tester.pumpWidget(
      ChangeNotifierProvider<OrganizationApplicationsProvider>.value(
        value: provider,
        child: MaterialApp.router(
          theme: AppTheme.lightTheme,
          routerConfig: router,
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(provider.isLoadingList, isTrue);

    await tester.pumpAndSettle();
  });

  testWidgets('Empty state renders', (tester) async {
    await _pumpScreen(tester, repository: _FakeApplicationRepository());

    expect(find.text('No Applicants Yet'), findsOneWidget);
  });

  testWidgets('Error state renders with retry', (tester) async {
    final repository = _FakeApplicationRepository(
      listError: ApiException('Server error, please try again later.'),
    );
    await _pumpScreen(tester, repository: repository);

    expect(find.text('Server error, please try again later.'), findsOneWidget);

    repository.listError = null;
    repository.listResult = [
      _application(
        applicant: const ApplicantSummaryModel(id: 1, name: 'Jane Student'),
      ),
    ];
    await tester.tap(find.text('Try Again'));
    await tester.pumpAndSettle();

    expect(find.text('Jane Student'), findsOneWidget);
  });

  testWidgets(
    'Applicant card renders name, email, university/major, status, and match score',
    (tester) async {
      final repository = _FakeApplicationRepository(
        listResult: [
          _application(
            status: 'shortlisted',
            matchScore: 68.75,
            applicant: const ApplicantSummaryModel(
              id: 1,
              name: 'Jane Student',
              email: 'jane@example.com',
              university: 'State University',
              major: 'Computer Science',
            ),
          ),
        ],
      );
      await _pumpScreen(tester, repository: repository);

      expect(find.text('Jane Student'), findsOneWidget);
      expect(find.text('jane@example.com'), findsOneWidget);
      expect(find.text('Computer Science, State University'), findsOneWidget);
      expect(find.text('Shortlisted'), findsOneWidget);
      expect(find.text('Match 69%'), findsOneWidget);
    },
  );

  testWidgets('Match score is omitted when not present', (tester) async {
    final repository = _FakeApplicationRepository(
      listResult: [
        _application(
          applicant: const ApplicantSummaryModel(id: 1, name: 'Jane Student'),
        ),
      ],
    );
    await _pumpScreen(tester, repository: repository);

    expect(find.textContaining('Match'), findsNothing);
  });

  testWidgets('Missing name falls back to "Unnamed applicant"', (tester) async {
    final repository = _FakeApplicationRepository(
      listResult: [_application(applicant: null)],
    );
    await _pumpScreen(tester, repository: repository);

    expect(find.text('Unnamed applicant'), findsOneWidget);
  });

  testWidgets('Missing email does not render an empty row', (tester) async {
    final repository = _FakeApplicationRepository(
      listResult: [
        _application(
          applicant: const ApplicantSummaryModel(id: 1, name: 'Jane Student'),
        ),
      ],
    );
    await _pumpScreen(tester, repository: repository);

    expect(find.text(''), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Empty-string name falls back to "Unnamed applicant"', (
    tester,
  ) async {
    final repository = _FakeApplicationRepository(
      listResult: [
        _application(applicant: const ApplicantSummaryModel(id: 1, name: '')),
      ],
    );
    await _pumpScreen(tester, repository: repository);

    expect(find.text('Unnamed applicant'), findsOneWidget);
    expect(find.text(''), findsNothing);
  });

  testWidgets('Whitespace-only name falls back to "Unnamed applicant"', (
    tester,
  ) async {
    final repository = _FakeApplicationRepository(
      listResult: [
        _application(
          applicant: const ApplicantSummaryModel(id: 1, name: '   '),
        ),
      ],
    );
    await _pumpScreen(tester, repository: repository);

    expect(find.text('Unnamed applicant'), findsOneWidget);
    expect(find.text('   '), findsNothing);
  });

  testWidgets('Whitespace-only email does not render an empty row', (
    tester,
  ) async {
    final repository = _FakeApplicationRepository(
      listResult: [
        _application(
          applicant: const ApplicantSummaryModel(
            id: 1,
            name: 'Jane Student',
            email: '   ',
          ),
        ),
      ],
    );
    await _pumpScreen(tester, repository: repository);

    expect(find.text('   '), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Whitespace-only university and major does not render a study line',
    (tester) async {
      final repository = _FakeApplicationRepository(
        listResult: [
          _application(
            applicant: const ApplicantSummaryModel(
              id: 1,
              name: 'Jane Student',
              university: '   ',
              major: '  ',
            ),
          ),
        ],
      );
      await _pumpScreen(tester, repository: repository);

      expect(find.text('   '), findsNothing);
      expect(find.text('  '), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'One blank field (major) and one real field (university) renders only the real one',
    (tester) async {
      final repository = _FakeApplicationRepository(
        listResult: [
          _application(
            applicant: const ApplicantSummaryModel(
              id: 1,
              name: 'Jane Student',
              university: 'State University',
              major: '   ',
            ),
          ),
        ],
      );
      await _pumpScreen(tester, repository: repository);

      expect(find.text('State University'), findsOneWidget);
      expect(find.text('   '), findsNothing);
    },
  );

  testWidgets('Tapping a card opens its details route by ID', (tester) async {
    final repository = _FakeApplicationRepository(
      listResult: [
        _application(
          id: 42,
          applicant: const ApplicantSummaryModel(id: 1, name: 'Jane Student'),
        ),
      ],
    );
    await _pumpScreen(tester, repository: repository);

    await tester.tap(find.text('Jane Student'));
    await tester.pumpAndSettle();

    expect(find.text('APPLICATION_DETAILS_PLACEHOLDER_42'), findsOneWidget);
  });

  testWidgets('Does not overflow at a narrow 320x720 viewport', (tester) async {
    final repository = _FakeApplicationRepository(
      listResult: [
        _application(
          id: 1,
          applicant: const ApplicantSummaryModel(
            id: 1,
            name: 'Jane Student',
            email: 'jane@example.com',
            university: 'State University',
            major: 'Computer Science',
          ),
          matchScore: 80,
        ),
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
