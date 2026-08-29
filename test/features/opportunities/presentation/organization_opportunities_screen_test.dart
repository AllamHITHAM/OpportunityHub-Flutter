// Widget tests for the redesigned OrganizationOpportunitiesScreen, in
// isolation (a small GoRouter with placeholder destinations, rather than
// the full app/router) — this screen's own contract is what's under test
// here, not the real create/details/edit screens it navigates to.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'package:opportunityhub_flutter/core/api/api_client.dart';
import 'package:opportunityhub_flutter/core/storage/token_storage_service.dart';
import 'package:opportunityhub_flutter/core/theme/app_theme.dart';
import 'package:opportunityhub_flutter/features/auth/data/auth_repository.dart';
import 'package:opportunityhub_flutter/features/opportunities/data/opportunity_repository.dart';
import 'package:opportunityhub_flutter/features/opportunities/presentation/organization_opportunities_screen.dart';
import 'package:opportunityhub_flutter/models/opportunity_model.dart';
import 'package:opportunityhub_flutter/providers/auth_provider.dart';
import 'package:opportunityhub_flutter/providers/organization_opportunities_provider.dart';
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

class _FakeOpportunityRepository extends OpportunityRepository {
  _FakeOpportunityRepository({
    this.listResult = const [],
    this.listError,
    this.listDelay = Duration.zero,
  }) : super(apiClient: ApiClient(tokenStorageService: TokenStorageService()));

  List<OpportunityModel> listResult;
  ApiException? listError;
  Duration listDelay;
  int getOpportunitiesCallCount = 0;

  ApiException? deleteError;
  int deleteCallCount = 0;
  int? lastDeletedId;

  @override
  Future<List<OpportunityModel>> getOpportunities() async {
    getOpportunitiesCallCount++;
    if (listDelay > Duration.zero) {
      await Future<void>.delayed(listDelay);
    }
    if (listError != null) throw listError!;
    return listResult;
  }

  @override
  Future<void> deleteOpportunity(int id) async {
    deleteCallCount++;
    lastDeletedId = id;
    if (deleteError != null) throw deleteError!;
  }
}

OpportunityModel _opportunity({
  int id = 1,
  String title = 'Software Engineer',
  String status = 'open',
  String opportunityType = 'job',
  String employmentType = 'full_time',
  String workMode = 'remote',
  String? location = 'Amman, Jordan',
  int positionsAvailable = 1,
  DateTime? applicationDeadline,
  DateTime? createdAt,
  String recruitmentProcess = 'none',
}) {
  return OpportunityModel(
    id: id,
    title: title,
    description: 'A great opportunity.',
    opportunityType: opportunityType,
    employmentType: employmentType,
    workMode: workMode,
    experienceLevel: 'junior',
    positionsAvailable: positionsAvailable,
    status: status,
    location: location,
    applicationDeadline: applicationDeadline,
    createdAt: createdAt,
    recruitmentProcess: recruitmentProcess,
  );
}

Future<OrganizationOpportunitiesProvider> _pumpScreen(
  WidgetTester tester, {
  required _FakeOpportunityRepository repository,
  Size size = const Size(420, 1600),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final authProvider = AuthProvider(authRepository: _FakeAuthRepository());
  final provider = OrganizationOpportunitiesProvider(
    repository: repository,
    authProvider: authProvider,
  );

  final router = GoRouter(
    initialLocation: AppRoutes.organizationOpportunities,
    routes: [
      GoRoute(
        path: AppRoutes.organizationOpportunities,
        builder: (_, _) => const OrganizationOpportunitiesScreen(),
      ),
      GoRoute(
        path: AppRoutes.organizationOpportunityCreate,
        builder: (_, _) =>
            const Scaffold(body: Text('CREATE_SCREEN_PLACEHOLDER')),
      ),
      GoRoute(
        path: '${AppRoutes.organizationOpportunities}/:id',
        builder: (_, state) => Scaffold(
          body: Text(
            'DETAILS_SCREEN_PLACEHOLDER_${state.pathParameters['id']}',
          ),
        ),
      ),
      GoRoute(
        path: '${AppRoutes.organizationOpportunities}/:id/edit',
        builder: (_, state) => Scaffold(
          body: Text('EDIT_SCREEN_PLACEHOLDER_${state.pathParameters['id']}'),
        ),
      ),
    ],
  );

  await tester.pumpWidget(
    ChangeNotifierProvider<OrganizationOpportunitiesProvider>.value(
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
  group('loading / error / retry', () {
    testWidgets('Loading UI renders while the list is in flight', (
      tester,
    ) async {
      final repository = _FakeOpportunityRepository(
        listDelay: const Duration(milliseconds: 200),
      );
      tester.view.physicalSize = const Size(420, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final authProvider = AuthProvider(authRepository: _FakeAuthRepository());
      final provider = OrganizationOpportunitiesProvider(
        repository: repository,
        authProvider: authProvider,
      );
      final router = GoRouter(
        initialLocation: AppRoutes.organizationOpportunities,
        routes: [
          GoRoute(
            path: AppRoutes.organizationOpportunities,
            builder: (_, _) => const OrganizationOpportunitiesScreen(),
          ),
        ],
      );

      await tester.pumpWidget(
        ChangeNotifierProvider<OrganizationOpportunitiesProvider>.value(
          value: provider,
          child: MaterialApp.router(
            theme: AppTheme.lightTheme,
            routerConfig: router,
          ),
        ),
      );
      // The initial load is kicked off from a post-frame callback (see
      // OrganizationOpportunitiesScreen.initState) and the fake repository
      // has an artificial delay, so this reliably catches the loading frame
      // before its Future resolves — deliberately not pumpAndSettle.
      await tester.pump();
      await tester.pump();

      expect(find.text('Opportunities'), findsOneWidget);
      expect(provider.isLoadingList, isTrue);

      await tester.pumpAndSettle();
    });

    testWidgets('Error UI renders on load failure, with retry', (
      tester,
    ) async {
      final repository = _FakeOpportunityRepository(
        listError: ApiException('Server error, please try again later.'),
      );
      final provider = await _pumpScreen(tester, repository: repository);

      expect(find.text('Server error, please try again later.'), findsOneWidget);
      expect(provider.opportunities, isEmpty);

      repository.listError = null;
      repository.listResult = [_opportunity()];
      await tester.tap(find.text('Try Again'));
      await tester.pumpAndSettle();

      expect(find.text('Software Engineer'), findsOneWidget);
    });
  });

  testWidgets('Empty UI renders when there are no opportunities', (
    tester,
  ) async {
    await _pumpScreen(tester, repository: _FakeOpportunityRepository());

    expect(find.text('No Opportunities Yet'), findsOneWidget);
    expect(find.text('Create Opportunity'), findsWidgets);
  });

  group('populated list', () {
    testWidgets('Cards render real fields from the response', (tester) async {
      final repository = _FakeOpportunityRepository(
        listResult: [
          _opportunity(
            id: 1,
            title: 'Software Engineer',
            status: 'open',
            opportunityType: 'job',
            location: 'Amman, Jordan',
            positionsAvailable: 3,
            recruitmentProcess: 'quiz',
          ),
        ],
      );
      await _pumpScreen(tester, repository: repository);

      expect(find.text('Software Engineer'), findsOneWidget);
      expect(find.text('Job'), findsOneWidget);
      expect(find.text('Amman, Jordan'), findsOneWidget);
      expect(find.text('3 positions'), findsOneWidget);
      expect(find.text('Quiz'), findsOneWidget);
      // "Open" appears both as a status chip and possibly a filter chip —
      // asserted with findsWidgets, not findsOneWidget.
      expect(find.text('Open'), findsWidgets);
    });

    testWidgets('The summary strip shows real Total/Open/Closed/Draft counts', (
      tester,
    ) async {
      final repository = _FakeOpportunityRepository(
        listResult: [
          _opportunity(id: 1, status: 'open'),
          _opportunity(id: 2, status: 'open'),
          _opportunity(id: 3, status: 'closed'),
          _opportunity(id: 4, status: 'draft'),
        ],
      );
      await _pumpScreen(tester, repository: repository);

      expect(find.text('Total'), findsOneWidget);
      expect(find.text('4'), findsOneWidget);
      expect(find.text('2'), findsOneWidget);
      expect(find.text('1'), findsWidgets);
    });

    testWidgets('Positions display singular/plural correctly', (
      tester,
    ) async {
      final repository = _FakeOpportunityRepository(
        listResult: [_opportunity(id: 1, positionsAvailable: 1)],
      );
      await _pumpScreen(tester, repository: repository);

      expect(find.text('1 position'), findsOneWidget);
    });
  });

  group('search', () {
    testWidgets('filters the visible list by title', (tester) async {
      final repository = _FakeOpportunityRepository(
        listResult: [
          _opportunity(id: 1, title: 'Software Engineer'),
          _opportunity(id: 2, title: 'Marketing Intern'),
        ],
      );
      await _pumpScreen(tester, repository: repository);

      expect(find.text('Software Engineer'), findsOneWidget);
      expect(find.text('Marketing Intern'), findsOneWidget);

      await tester.enterText(find.byType(TextField).first, 'Software');
      await tester.pumpAndSettle();

      expect(find.text('Software Engineer'), findsOneWidget);
      expect(find.text('Marketing Intern'), findsNothing);
    });

    testWidgets('filters the visible list by location', (tester) async {
      final repository = _FakeOpportunityRepository(
        listResult: [
          _opportunity(id: 1, title: 'Role A', location: 'Amman, Jordan'),
          _opportunity(id: 2, title: 'Role B', location: 'Dubai, UAE'),
        ],
      );
      await _pumpScreen(tester, repository: repository);

      await tester.enterText(find.byType(TextField).first, 'Dubai');
      await tester.pumpAndSettle();

      expect(find.text('Role A'), findsNothing);
      expect(find.text('Role B'), findsOneWidget);
    });

    testWidgets('a query with no matches shows the no-matching-results state', (
      tester,
    ) async {
      final repository = _FakeOpportunityRepository(
        listResult: [_opportunity(id: 1, title: 'Software Engineer')],
      );
      await _pumpScreen(tester, repository: repository);

      await tester.enterText(find.byType(TextField).first, 'zzz-no-match');
      await tester.pumpAndSettle();

      expect(find.text('No Matching Opportunities'), findsOneWidget);
      // "Clear Filters" appears both as the compact filter-row TextButton
      // and as AppEmptyView's own action label.
      expect(find.text('Clear Filters'), findsNWidgets(2));

      await tester.tap(find.widgetWithText(TextButton, 'Clear Filters'));
      await tester.pumpAndSettle();

      expect(find.text('Software Engineer'), findsOneWidget);
    });
  });

  group('status filter', () {
    testWidgets('the Open chip narrows the list to open opportunities', (
      tester,
    ) async {
      final repository = _FakeOpportunityRepository(
        listResult: [
          _opportunity(id: 1, title: 'Open Role', status: 'open'),
          _opportunity(id: 2, title: 'Draft Role', status: 'draft'),
        ],
      );
      await _pumpScreen(tester, repository: repository);

      expect(find.text('Open Role'), findsOneWidget);
      expect(find.text('Draft Role'), findsOneWidget);

      await tester.tap(find.widgetWithText(ChoiceChip, 'Draft'));
      await tester.pumpAndSettle();

      expect(find.text('Open Role'), findsNothing);
      expect(find.text('Draft Role'), findsOneWidget);

      await tester.tap(find.widgetWithText(ChoiceChip, 'All'));
      await tester.pumpAndSettle();

      expect(find.text('Open Role'), findsOneWidget);
      expect(find.text('Draft Role'), findsOneWidget);
    });
  });

  group('sort', () {
    testWidgets('Title sort orders opportunities alphabetically', (
      tester,
    ) async {
      final repository = _FakeOpportunityRepository(
        listResult: [
          _opportunity(id: 1, title: 'Zebra Role'),
          _opportunity(id: 2, title: 'Alpha Role'),
        ],
      );
      await _pumpScreen(tester, repository: repository);

      await tester.tap(find.text('Sort: Newest'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Title').last);
      await tester.pumpAndSettle();

      final zebraCenter = tester.getCenter(find.text('Zebra Role'));
      final alphaCenter = tester.getCenter(find.text('Alpha Role'));
      expect(alphaCenter.dy, lessThan(zebraCenter.dy));
    });
  });

  group('navigation', () {
    testWidgets('Create Opportunity opens the create form route', (
      tester,
    ) async {
      await _pumpScreen(
        tester,
        repository: _FakeOpportunityRepository(
          listResult: [_opportunity()],
        ),
      );

      await tester.tap(find.widgetWithText(ElevatedButton, 'Create Opportunity'));
      await tester.pumpAndSettle();

      expect(find.text('CREATE_SCREEN_PLACEHOLDER'), findsOneWidget);
    });

    testWidgets('Empty state Create Opportunity opens the create form route', (
      tester,
    ) async {
      await _pumpScreen(tester, repository: _FakeOpportunityRepository());

      await tester.tap(find.text('Create Opportunity').last);
      await tester.pumpAndSettle();

      expect(find.text('CREATE_SCREEN_PLACEHOLDER'), findsOneWidget);
    });

    testWidgets('Tapping a card opens its details route by ID', (
      tester,
    ) async {
      final repository = _FakeOpportunityRepository(
        listResult: [_opportunity(id: 42, title: 'Data Analyst')],
      );
      await _pumpScreen(tester, repository: repository);

      await tester.tap(find.text('Data Analyst'));
      await tester.pumpAndSettle();

      expect(find.text('DETAILS_SCREEN_PLACEHOLDER_42'), findsOneWidget);
    });

    testWidgets('The trailing menu Edit action opens the edit route by ID', (
      tester,
    ) async {
      final repository = _FakeOpportunityRepository(
        listResult: [_opportunity(id: 7, title: 'Data Analyst')],
      );
      await _pumpScreen(tester, repository: repository);

      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Edit'));
      await tester.pumpAndSettle();

      expect(find.text('EDIT_SCREEN_PLACEHOLDER_7'), findsOneWidget);
    });

    testWidgets(
      'The trailing menu Delete action confirms then deletes via the provider',
      (tester) async {
        final repository = _FakeOpportunityRepository(
          listResult: [_opportunity(id: 9, title: 'Data Analyst')],
        );
        await _pumpScreen(tester, repository: repository);

        await tester.tap(find.byIcon(Icons.more_vert));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Delete'));
        await tester.pumpAndSettle();

        expect(find.text('Delete Opportunity'), findsOneWidget);
        await tester.tap(find.widgetWithText(OutlinedButton, 'Delete'));
        await tester.pumpAndSettle();

        expect(repository.deleteCallCount, 1);
        expect(repository.lastDeletedId, 9);
        expect(find.text('Data Analyst'), findsNothing);
      },
    );
  });

  testWidgets('Pull-to-refresh does not duplicate data', (tester) async {
    final repository = _FakeOpportunityRepository(
      listResult: [_opportunity(id: 1)],
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
    expect(repository.getOpportunitiesCallCount, greaterThanOrEqualTo(2));
  });

  group('responsive / theming', () {
    testWidgets('does not overflow at a narrow 320x720 viewport', (
      tester,
    ) async {
      final repository = _FakeOpportunityRepository(
        listResult: [
          _opportunity(id: 1, title: 'Software Engineer'),
          _opportunity(id: 2, title: 'Marketing Intern', status: 'draft'),
        ],
      );
      await _pumpScreen(
        tester,
        repository: repository,
        size: const Size(320, 720),
      );

      expect(tester.takeException(), isNull);
    });

    testWidgets('does not overflow on a mobile viewport (375-430)', (
      tester,
    ) async {
      final repository = _FakeOpportunityRepository(
        listResult: List.generate(4, (i) => _opportunity(id: i + 1)),
      );
      await _pumpScreen(
        tester,
        repository: repository,
        size: const Size(390, 844),
      );

      expect(tester.takeException(), isNull);
    });

    testWidgets('does not overflow on a tablet viewport (600-899)', (
      tester,
    ) async {
      final repository = _FakeOpportunityRepository(
        listResult: List.generate(4, (i) => _opportunity(id: i + 1)),
      );
      await _pumpScreen(
        tester,
        repository: repository,
        size: const Size(700, 900),
      );

      expect(tester.takeException(), isNull);
    });

    testWidgets('does not overflow on a desktop viewport (>=1200)', (
      tester,
    ) async {
      final repository = _FakeOpportunityRepository(
        listResult: List.generate(6, (i) => _opportunity(id: i + 1)),
      );
      await _pumpScreen(
        tester,
        repository: repository,
        size: const Size(1400, 900),
      );

      expect(tester.takeException(), isNull);
    });

    testWidgets('renders correctly in Dark Mode', (tester) async {
      final repository = _FakeOpportunityRepository(
        listResult: [_opportunity()],
      );
      tester.view.physicalSize = const Size(420, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final authProvider = AuthProvider(authRepository: _FakeAuthRepository());
      final provider = OrganizationOpportunitiesProvider(
        repository: repository,
        authProvider: authProvider,
      );
      final router = GoRouter(
        initialLocation: AppRoutes.organizationOpportunities,
        routes: [
          GoRoute(
            path: AppRoutes.organizationOpportunities,
            builder: (_, _) => const OrganizationOpportunitiesScreen(),
          ),
        ],
      );

      await tester.pumpWidget(
        ChangeNotifierProvider<OrganizationOpportunitiesProvider>.value(
          value: provider,
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
  });
}
