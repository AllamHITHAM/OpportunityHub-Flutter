// Widget tests for OrganizationOpportunityDetailsScreen, in isolation with
// a small GoRouter.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'package:opportunityhub_flutter/core/api/api_client.dart';
import 'package:opportunityhub_flutter/core/storage/token_storage_service.dart';
import 'package:opportunityhub_flutter/core/theme/app_theme.dart';
import 'package:opportunityhub_flutter/features/auth/data/auth_repository.dart';
import 'package:opportunityhub_flutter/features/opportunities/data/opportunity_repository.dart';
import 'package:opportunityhub_flutter/features/opportunities/presentation/organization_opportunity_details_screen.dart';
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

OpportunityModel _opportunity({
  int id = 1,
  String title = 'Software Engineer',
  String status = 'open',
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
    status: status,
    location: 'Amman, Jordan',
  );
}

class _FakeOpportunityRepository extends OpportunityRepository {
  _FakeOpportunityRepository({this.getResult, this.getError, this.deleteError})
    : super(apiClient: ApiClient(tokenStorageService: TokenStorageService()));

  OpportunityModel? getResult;
  ApiException? getError;
  ApiException? deleteError;
  int deleteCallCount = 0;

  @override
  Future<OpportunityModel> getOpportunity(int id) async {
    if (getError != null) throw getError!;
    return getResult!;
  }

  @override
  Future<void> deleteOpportunity(int id) async {
    deleteCallCount++;
    if (deleteError != null) throw deleteError!;
  }
}

Future<(OrganizationOpportunitiesProvider, List<String>)> _pumpDetails(
  WidgetTester tester, {
  required _FakeOpportunityRepository repository,
  int opportunityId = 1,
  Size size = const Size(420, 1400),
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
  final visitedPaths = <String>[];

  final router = GoRouter(
    initialLocation: AppRoutes.organizationOpportunityDetails(opportunityId),
    routes: [
      GoRoute(
        path: AppRoutes.organizationOpportunities,
        builder: (_, _) {
          visitedPaths.add('list');
          return const Scaffold(body: Text('LIST_PLACEHOLDER'));
        },
      ),
      GoRoute(
        path: '${AppRoutes.organizationOpportunities}/:id/edit',
        builder: (_, state) {
          visitedPaths.add('edit/${state.pathParameters['id']}');
          return const Scaffold(body: Text('EDIT_PLACEHOLDER'));
        },
      ),
      GoRoute(
        path: '${AppRoutes.organizationOpportunities}/:id',
        builder: (_, state) => OrganizationOpportunityDetailsScreen(
          opportunityId: int.parse(state.pathParameters['id']!),
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

  return (provider, visitedPaths);
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

  testWidgets('Loading state renders, then correct fields render', (
    tester,
  ) async {
    final repository = _FakeOpportunityRepository(
      getResult: _opportunity(title: 'Software Engineer', status: 'open'),
    );
    await _pumpDetails(tester, repository: repository);

    expect(find.text('Software Engineer'), findsOneWidget);
    expect(find.text('Open'), findsOneWidget);
    expect(find.text('Job'), findsOneWidget);
    expect(find.text('Full Time'), findsOneWidget);
    expect(find.text('Remote'), findsOneWidget);
    expect(find.text('Junior'), findsOneWidget);
    expect(find.text('A great opportunity.'), findsOneWidget);
    expect(find.text('Amman, Jordan'), findsOneWidget);
  });

  testWidgets('Not-found error state renders safely, no crash', (tester) async {
    final repository = _FakeOpportunityRepository(
      getError: ApiException('Opportunity not found'),
    );
    await _pumpDetails(tester, repository: repository, opportunityId: 999);

    expect(find.text('Opportunity not found'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('No applicant/interview/quiz UI appears', (tester) async {
    final repository = _FakeOpportunityRepository(getResult: _opportunity());
    await _pumpDetails(tester, repository: repository);

    expect(find.textContaining('Applicant'), findsNothing);
    expect(find.textContaining('Interview'), findsNothing);
    expect(find.textContaining('Quiz'), findsNothing);
  });

  testWidgets('Edit action loads existing data on the edit screen', (
    tester,
  ) async {
    final repository = _FakeOpportunityRepository(
      getResult: _opportunity(id: 7),
    );
    final (_, visitedPaths) = await _pumpDetails(
      tester,
      repository: repository,
      opportunityId: 7,
    );

    await tester.tap(find.byIcon(Icons.edit_outlined));
    await tester.pumpAndSettle();

    expect(visitedPaths, contains('edit/7'));
  });

  testWidgets('Delete requires confirmation before anything happens', (
    tester,
  ) async {
    final repository = _FakeOpportunityRepository(
      getResult: _opportunity(id: 7, title: 'Software Engineer'),
    );
    await _pumpDetails(tester, repository: repository, opportunityId: 7);

    await tester.tap(find.byIcon(Icons.delete_outline));
    await tester.pumpAndSettle();

    expect(find.text('Delete Opportunity'), findsOneWidget);
    expect(find.textContaining('Software Engineer'), findsWidgets);
    expect(repository.deleteCallCount, 0);

    // Cancel: nothing should have been deleted.
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(repository.deleteCallCount, 0);
  });

  testWidgets('Delete success exits details safely to the list', (
    tester,
  ) async {
    final repository = _FakeOpportunityRepository(
      getResult: _opportunity(id: 7),
    );
    final (provider, visitedPaths) = await _pumpDetails(
      tester,
      repository: repository,
      opportunityId: 7,
    );
    provider.opportunities = [_opportunity(id: 7)];

    await tester.tap(find.byIcon(Icons.delete_outline));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();

    expect(repository.deleteCallCount, 1);
    expect(visitedPaths, contains('list'));
  });

  testWidgets('Delete failure remains on details, item still visible', (
    tester,
  ) async {
    final repository = _FakeOpportunityRepository(
      getResult: _opportunity(id: 7, title: 'Software Engineer'),
      deleteError: ApiException(
        'Cannot delete an opportunity that has applications',
        statusCode: 409,
      ),
    );
    await _pumpDetails(tester, repository: repository, opportunityId: 7);

    await tester.tap(find.byIcon(Icons.delete_outline));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();

    expect(find.text('Software Engineer'), findsOneWidget);
    expect(
      find.text('Cannot delete an opportunity that has applications'),
      findsOneWidget,
    );
  });
}
