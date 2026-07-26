// Widget tests for StudentOpportunitiesScreen, in isolation (a small
// GoRouter with placeholder destinations, rather than the full app/router)
// — this screen's own contract is what's under test here, not the real
// details screen it navigates to.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'package:opportunityhub_flutter/core/api/api_client.dart';
import 'package:opportunityhub_flutter/core/api/paginated_result.dart';
import 'package:opportunityhub_flutter/core/storage/token_storage_service.dart';
import 'package:opportunityhub_flutter/core/theme/app_theme.dart';
import 'package:opportunityhub_flutter/features/auth/data/auth_repository.dart';
import 'package:opportunityhub_flutter/features/opportunities/data/opportunity_repository.dart';
import 'package:opportunityhub_flutter/features/opportunities/presentation/student_opportunities_screen.dart';
import 'package:opportunityhub_flutter/models/opportunity_model.dart';
import 'package:opportunityhub_flutter/models/organization_profile_model.dart';
import 'package:opportunityhub_flutter/providers/auth_provider.dart';
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

class _FakeOpportunityRepository extends OpportunityRepository {
  _FakeOpportunityRepository({
    this.listResult = const PaginatedResult(
      items: [],
      currentPage: 1,
      lastPage: 1,
      total: 0,
    ),
    this.listError,
    this.listDelay = Duration.zero,
  }) : super(apiClient: ApiClient(tokenStorageService: TokenStorageService()));

  PaginatedResult<OpportunityModel> listResult;
  ApiException? listError;
  Duration listDelay;
  int callCount = 0;
  String? lastKeyword;
  String? lastOpportunityType;

  @override
  Future<PaginatedResult<OpportunityModel>> getPublicOpportunities({
    String? opportunityType,
    String? employmentType,
    String? workMode,
    String? experienceLevel,
    String? location,
    String? fieldOfStudy,
    String? keyword,
    int page = 1,
    int perPage = 15,
  }) async {
    callCount++;
    lastKeyword = keyword;
    lastOpportunityType = opportunityType;
    if (listDelay > Duration.zero) {
      await Future<void>.delayed(listDelay);
    }
    if (listError != null) throw listError!;
    return listResult;
  }
}

OpportunityModel _opportunity({
  int id = 1,
  String title = 'Software Engineer',
  String opportunityType = 'job',
  String? location = 'Amman, Jordan',
  OrganizationProfileModel? organizationProfile,
}) {
  return OpportunityModel(
    id: id,
    title: title,
    description: 'A great opportunity.',
    opportunityType: opportunityType,
    employmentType: 'full_time',
    workMode: 'remote',
    experienceLevel: 'junior',
    positionsAvailable: 1,
    status: 'open',
    location: location,
    organizationProfile: organizationProfile,
  );
}

Future<StudentOpportunitiesProvider> _pumpScreen(
  WidgetTester tester, {
  required _FakeOpportunityRepository repository,
  Size size = const Size(420, 800),
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

  final router = GoRouter(
    initialLocation: AppRoutes.studentOpportunities,
    routes: [
      GoRoute(
        path: AppRoutes.studentOpportunities,
        builder: (_, _) => const StudentOpportunitiesScreen(),
      ),
      GoRoute(
        path: '${AppRoutes.studentOpportunities}/:id',
        builder: (_, state) => Scaffold(
          body: Text(
            'DETAILS_SCREEN_PLACEHOLDER_${state.pathParameters['id']}',
          ),
        ),
      ),
    ],
  );

  await tester.pumpWidget(
    ChangeNotifierProvider<StudentOpportunitiesProvider>.value(
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
  testWidgets('Loading UI renders while the list is in flight', (tester) async {
    final repository = _FakeOpportunityRepository(
      listDelay: const Duration(milliseconds: 200),
    );
    tester.view.physicalSize = const Size(420, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final authProvider = AuthProvider(authRepository: _FakeAuthRepository());
    final provider = StudentOpportunitiesProvider(
      repository: repository,
      authProvider: authProvider,
    );
    final router = GoRouter(
      initialLocation: AppRoutes.studentOpportunities,
      routes: [
        GoRoute(
          path: AppRoutes.studentOpportunities,
          builder: (_, _) => const StudentOpportunitiesScreen(),
        ),
      ],
    );

    await tester.pumpWidget(
      ChangeNotifierProvider<StudentOpportunitiesProvider>.value(
        value: provider,
        child: MaterialApp.router(
          theme: AppTheme.lightTheme,
          routerConfig: router,
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('Opportunities'), findsOneWidget);
    expect(provider.isLoadingList, isTrue);

    await tester.pumpAndSettle();
  });

  testWidgets('Error UI renders on load failure, with retry', (tester) async {
    final repository = _FakeOpportunityRepository(
      listError: ApiException('Server error, please try again later.'),
    );
    final provider = await _pumpScreen(tester, repository: repository);

    expect(find.text('Server error, please try again later.'), findsOneWidget);
    expect(provider.opportunities, isEmpty);

    repository.listError = null;
    repository.listResult = PaginatedResult(
      items: [_opportunity()],
      currentPage: 1,
      lastPage: 1,
      total: 1,
    );
    await tester.tap(find.text('Try Again'));
    await tester.pumpAndSettle();

    expect(find.text('Software Engineer'), findsOneWidget);
  });

  testWidgets('Empty UI renders when there are no opportunities', (
    tester,
  ) async {
    await _pumpScreen(tester, repository: _FakeOpportunityRepository());

    expect(find.text('No Opportunities Found'), findsOneWidget);
  });

  testWidgets(
    'Opportunity cards render real fields, including the nested organization name',
    (tester) async {
      final repository = _FakeOpportunityRepository(
        listResult: PaginatedResult(
          items: [
            _opportunity(
              id: 1,
              title: 'Software Engineer',
              opportunityType: 'job',
              location: 'Amman, Jordan',
              organizationProfile: const OrganizationProfileModel(
                id: 3,
                organizationName: 'Acme Corp',
                organizationType: 'company',
                approvalStatus: 'approved',
              ),
            ),
          ],
          currentPage: 1,
          lastPage: 1,
          total: 1,
        ),
      );
      await _pumpScreen(tester, repository: repository);

      expect(find.text('Software Engineer'), findsOneWidget);
      expect(find.text('Acme Corp'), findsOneWidget);
      expect(find.text('Job'), findsOneWidget);
      expect(find.text('Amman, Jordan'), findsOneWidget);
    },
  );

  testWidgets('No organization name renders when the relation is absent', (
    tester,
  ) async {
    final repository = _FakeOpportunityRepository(
      listResult: PaginatedResult(
        items: [_opportunity(id: 1)],
        currentPage: 1,
        lastPage: 1,
        total: 1,
      ),
    );
    await _pumpScreen(tester, repository: repository);

    expect(find.text('Acme Corp'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Tapping a card opens its details route by ID', (tester) async {
    final repository = _FakeOpportunityRepository(
      listResult: PaginatedResult(
        items: [_opportunity(id: 42, title: 'Data Analyst')],
        currentPage: 1,
        lastPage: 1,
        total: 1,
      ),
    );
    await _pumpScreen(tester, repository: repository);

    await tester.tap(find.text('Data Analyst'));
    await tester.pumpAndSettle();

    expect(find.text('DETAILS_SCREEN_PLACEHOLDER_42'), findsOneWidget);
  });

  testWidgets('Typing in search debounces then refetches with the keyword', (
    tester,
  ) async {
    final repository = _FakeOpportunityRepository(
      listResult: PaginatedResult(
        items: [_opportunity()],
        currentPage: 1,
        lastPage: 1,
        total: 1,
      ),
    );
    await _pumpScreen(tester, repository: repository);
    final callsBeforeSearch = repository.callCount;

    await tester.enterText(find.byType(TextFormField), 'engineer');
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();

    expect(repository.callCount, greaterThan(callsBeforeSearch));
    expect(repository.lastKeyword, 'engineer');
  });

  testWidgets('Load More button appears when more pages remain', (
    tester,
  ) async {
    final repository = _FakeOpportunityRepository(
      listResult: PaginatedResult(
        items: [_opportunity(id: 1)],
        currentPage: 1,
        lastPage: 2,
        total: 2,
      ),
    );
    await _pumpScreen(tester, repository: repository);

    expect(find.text('Load More'), findsOneWidget);

    repository.listResult = PaginatedResult(
      items: [_opportunity(id: 2, title: 'Marketing Intern')],
      currentPage: 2,
      lastPage: 2,
      total: 2,
    );
    await tester.tap(find.text('Load More'));
    await tester.pumpAndSettle();

    expect(find.text('Software Engineer'), findsOneWidget);
    expect(find.text('Marketing Intern'), findsOneWidget);
    expect(find.text('Load More'), findsNothing);
  });

  testWidgets('Filter sheet applies a filter and refetches', (tester) async {
    final repository = _FakeOpportunityRepository(
      listResult: PaginatedResult(
        items: [_opportunity()],
        currentPage: 1,
        lastPage: 1,
        total: 1,
      ),
    );
    await _pumpScreen(tester, repository: repository);

    await tester.tap(find.byIcon(Icons.filter_alt_outlined));
    await tester.pumpAndSettle();

    final dropdown = find.widgetWithText(
      DropdownButtonFormField<String>,
      'Opportunity Type',
    );
    await tester.tap(dropdown);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Job').last);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Apply Filters'));
    await tester.pumpAndSettle();

    expect(repository.lastOpportunityType, 'job');
    expect(find.byIcon(Icons.filter_alt), findsOneWidget);
  });

  testWidgets('Does not overflow at a narrow 320x720 viewport', (tester) async {
    final repository = _FakeOpportunityRepository(
      listResult: PaginatedResult(
        items: [
          _opportunity(id: 1, title: 'Software Engineer'),
          _opportunity(id: 2, title: 'Marketing Intern'),
        ],
        currentPage: 1,
        lastPage: 1,
        total: 2,
      ),
    );
    await _pumpScreen(
      tester,
      repository: repository,
      size: const Size(320, 720),
    );

    expect(tester.takeException(), isNull);
  });
}
