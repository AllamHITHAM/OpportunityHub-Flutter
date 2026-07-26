// Widget tests for OrganizationOpportunitiesScreen, in isolation (a small
// GoRouter with placeholder destinations, rather than the full app/router)
// — this screen's own contract is what's under test here, not the real
// create/details screens it navigates to.

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

  @override
  Future<List<OpportunityModel>> getOpportunities() async {
    getOpportunitiesCallCount++;
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
  String status = 'open',
  String opportunityType = 'job',
  String? location = 'Amman, Jordan',
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
    status: status,
    location: location,
  );
}

Future<OrganizationOpportunitiesProvider> _pumpScreen(
  WidgetTester tester, {
  required _FakeOpportunityRepository repository,
  Size size = const Size(420, 800),
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
  testWidgets('Loading UI renders while the list is in flight', (tester) async {
    final repository = _FakeOpportunityRepository(
      listDelay: const Duration(milliseconds: 200),
    );
    tester.view.physicalSize = const Size(420, 800);
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

  testWidgets('Error UI renders on load failure, with retry', (tester) async {
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

  testWidgets('Empty UI renders when there are no opportunities', (
    tester,
  ) async {
    await _pumpScreen(tester, repository: _FakeOpportunityRepository());

    expect(find.text('No Opportunities Yet'), findsOneWidget);
    expect(find.text('Create Opportunity'), findsOneWidget);
  });

  testWidgets('Opportunity cards render real fields from the response', (
    tester,
  ) async {
    final repository = _FakeOpportunityRepository(
      listResult: [
        _opportunity(
          id: 1,
          title: 'Software Engineer',
          status: 'open',
          opportunityType: 'job',
          location: 'Amman, Jordan',
        ),
      ],
    );
    await _pumpScreen(tester, repository: repository);

    expect(find.text('Software Engineer'), findsOneWidget);
    expect(find.text('Open'), findsOneWidget);
    expect(find.text('Job'), findsOneWidget);
    expect(find.text('Amman, Jordan'), findsOneWidget);
  });

  testWidgets('Create action opens the create form route', (tester) async {
    await _pumpScreen(tester, repository: _FakeOpportunityRepository());

    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();

    expect(find.text('CREATE_SCREEN_PLACEHOLDER'), findsOneWidget);
  });

  testWidgets('Tapping a card opens its details route by ID', (tester) async {
    final repository = _FakeOpportunityRepository(
      listResult: [_opportunity(id: 42, title: 'Data Analyst')],
    );
    await _pumpScreen(tester, repository: repository);

    await tester.tap(find.text('Data Analyst'));
    await tester.pumpAndSettle();

    expect(find.text('DETAILS_SCREEN_PLACEHOLDER_42'), findsOneWidget);
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

  testWidgets('Does not overflow at a narrow 320x720 viewport', (tester) async {
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
}
