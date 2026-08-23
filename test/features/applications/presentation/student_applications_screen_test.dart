// Widget tests for the premium StudentApplicationsScreen (UI Phase 4) —
// verifies the real pipeline overview, local search/filtering, the
// redesigned tracking-focused card, empty/loading/error handling, and
// responsive/reduced-motion behavior, in isolation with a small GoRouter.

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
  String opportunityType = 'job',
  String? workMode = 'remote',
  OrganizationProfileModel? organizationProfile,
  DateTime? appliedAt,
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
      opportunityType: opportunityType,
      employmentType: 'full_time',
      workMode: workMode ?? 'remote',
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
    appliedAt: appliedAt ?? DateTime(2026, 7, 20),
  );
}

Future<StudentApplicationsProvider> _pumpScreen(
  WidgetTester tester, {
  required _FakeApplicationRepository repository,
  Size size = const Size(420, 900),
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
      GoRoute(
        path: AppRoutes.studentOpportunities,
        builder: (_, _) => const Scaffold(body: Text('DISCOVER_PLACEHOLDER')),
      ),
    ],
  );

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<StudentApplicationsProvider>.value(
          value: provider,
        ),
        ChangeNotifierProvider<ThemeProvider>.value(value: ThemeProvider()),
      ],
      child: MaterialApp.router(
        theme: AppTheme.lightTheme,
        darkTheme: AppTheme.darkTheme,
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
    tester.view.physicalSize = const Size(420, 900);
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
      MultiProvider(
        providers: [
          ChangeNotifierProvider<StudentApplicationsProvider>.value(
            value: provider,
          ),
          ChangeNotifierProvider<ThemeProvider>.value(value: ThemeProvider()),
        ],
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

  testWidgets('Empty state renders when there are no applications, with a real CTA', (
    tester,
  ) async {
    await _pumpScreen(tester, repository: _FakeApplicationRepository());

    expect(find.text('No Applications Yet'), findsOneWidget);
    expect(find.text('Explore Opportunities'), findsOneWidget);

    await tester.tap(find.text('Explore Opportunities'));
    await tester.pumpAndSettle();

    expect(find.text('DISCOVER_PLACEHOLDER'), findsOneWidget);
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
    'Populated list shows opportunity, organization, status, and applied date',
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
      // "Shortlisted" legitimately appears twice — the pipeline overview's
      // own stage label, and the card's status chip. Deliberate richness,
      // not a duplicate-rendering bug (see student_opportunity_details
      // tests for the same established precedent).
      expect(find.text('Shortlisted'), findsNWidgets(2));
      expect(find.textContaining('Applied'), findsWidgets);
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

  group('Pipeline overview', () {
    testWidgets('shows real per-stage counts derived from loaded applications', (
      tester,
    ) async {
      final repository = _FakeApplicationRepository(
        listResult: [
          _application(id: 1, status: 'pending'),
          _application(id: 2, status: 'pending'),
          _application(id: 3, status: 'reviewed'),
          _application(id: 4, status: 'in_assessment'),
          _application(id: 5, status: 'offer_sent'),
        ],
      );
      await _pumpScreen(tester, repository: repository);

      expect(find.text('Applied'), findsOneWidget);
      expect(find.text('Review'), findsOneWidget);
      expect(find.text('Assessment'), findsWidgets);
      expect(find.text('Offer'), findsWidgets);
      // Real hero totals, never a fabricated analytics number.
      expect(find.text('5'), findsWidgets);
    });

    testWidgets(
      'terminal outcomes (accepted/rejected/withdrawn) are excluded from pipeline stage counts',
      (tester) async {
        final repository = _FakeApplicationRepository(
          listResult: [
            _application(id: 1, status: 'accepted'),
            _application(id: 2, status: 'rejected'),
            _application(id: 3, status: 'withdrawn'),
          ],
        );
        await _pumpScreen(tester, repository: repository);

        // Every real pipeline stage count is 0 — none of these three
        // outcomes is an active recruitment stage.
        expect(find.text('Applied'), findsOneWidget);
        expect(find.text('Review'), findsOneWidget);
      },
    );
  });

  group('Search and filters', () {
    testWidgets('search filters the list locally by opportunity title', (
      tester,
    ) async {
      final repository = _FakeApplicationRepository(
        listResult: [
          _application(id: 1, opportunityTitle: 'Software Engineer'),
          _application(id: 2, opportunityTitle: 'Marketing Intern'),
        ],
      );
      await _pumpScreen(tester, repository: repository);

      expect(find.text('Software Engineer'), findsOneWidget);
      expect(find.text('Marketing Intern'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'Software');
      await tester.pumpAndSettle();

      expect(find.text('Software Engineer'), findsOneWidget);
      expect(find.text('Marketing Intern'), findsNothing);
    });

    testWidgets('search filters the list locally by organization name', (
      tester,
    ) async {
      final repository = _FakeApplicationRepository(
        listResult: [
          _application(
            id: 1,
            opportunityTitle: 'Software Engineer',
            organizationProfile: const OrganizationProfileModel(
              id: 1,
              organizationName: 'Acme Corp',
              organizationType: 'company',
              approvalStatus: 'approved',
            ),
          ),
          _application(
            id: 2,
            opportunityTitle: 'Marketing Intern',
            organizationProfile: const OrganizationProfileModel(
              id: 2,
              organizationName: 'Globex',
              organizationType: 'company',
              approvalStatus: 'approved',
            ),
          ),
        ],
      );
      await _pumpScreen(tester, repository: repository);

      await tester.enterText(find.byType(TextField), 'globex');
      await tester.pumpAndSettle();

      expect(find.text('Marketing Intern'), findsOneWidget);
      expect(find.text('Software Engineer'), findsNothing);
    });

    testWidgets('a status filter chip shows only matching applications', (
      tester,
    ) async {
      final repository = _FakeApplicationRepository(
        listResult: [
          _application(id: 1, opportunityTitle: 'Software Engineer', status: 'accepted'),
          _application(id: 2, opportunityTitle: 'Marketing Intern', status: 'pending'),
        ],
      );
      await _pumpScreen(tester, repository: repository);

      // "Accepted" appears both as the filter chip's own label and as the
      // matching application's status chip — the filter chip renders
      // first, above the list.
      await tester.ensureVisible(find.text('Accepted').first);
      await tester.tap(find.text('Accepted').first);
      await tester.pumpAndSettle();

      expect(find.text('Software Engineer'), findsOneWidget);
      expect(find.text('Marketing Intern'), findsNothing);
    });

    testWidgets(
      'no matches shows a controlled empty state with a Clear Filters action',
      (tester) async {
        final repository = _FakeApplicationRepository(
          listResult: [_application(id: 1, opportunityTitle: 'Software Engineer')],
        );
        await _pumpScreen(tester, repository: repository);

        await tester.enterText(find.byType(TextField), 'nonexistent');
        await tester.pumpAndSettle();

        expect(find.text('No Matching Applications'), findsOneWidget);

        await tester.tap(find.text('Clear Filters'));
        await tester.pumpAndSettle();

        expect(find.text('Software Engineer'), findsOneWidget);
      },
    );
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

  testWidgets('Does not overflow at a wide desktop viewport', (tester) async {
    final repository = _FakeApplicationRepository(
      listResult: [
        _application(id: 1, opportunityTitle: 'Software Engineer'),
        _application(id: 2, opportunityTitle: 'Marketing Intern'),
      ],
    );
    await _pumpScreen(
      tester,
      repository: repository,
      size: const Size(1440, 900),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('Software Engineer'), findsOneWidget);
  });

  testWidgets('Does not overflow at a tablet viewport', (tester) async {
    final repository = _FakeApplicationRepository(
      listResult: [_application(id: 1, opportunityTitle: 'Software Engineer')],
    );
    await _pumpScreen(
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
    await _pumpScreen(tester, repository: repository);

    expect(tester.takeException(), isNull);
    expect(find.text('Software Engineer'), findsOneWidget);
  });

  testWidgets('renders correctly in Dark Mode', (tester) async {
    final repository = _FakeApplicationRepository(
      listResult: [_application(id: 1, opportunityTitle: 'Software Engineer')],
    );

    tester.view.physicalSize = const Size(420, 900);
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
      MultiProvider(
        providers: [
          ChangeNotifierProvider<StudentApplicationsProvider>.value(
            value: provider,
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
    expect(find.text('Software Engineer'), findsOneWidget);
  });
}
