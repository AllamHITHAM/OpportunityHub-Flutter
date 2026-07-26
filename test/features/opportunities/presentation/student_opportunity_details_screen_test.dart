// Widget tests for StudentOpportunityDetailsScreen, in isolation with a
// small GoRouter.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'package:opportunityhub_flutter/core/api/api_client.dart';
import 'package:opportunityhub_flutter/core/storage/token_storage_service.dart';
import 'package:opportunityhub_flutter/core/theme/app_theme.dart';
import 'package:opportunityhub_flutter/features/auth/data/auth_repository.dart';
import 'package:opportunityhub_flutter/features/opportunities/data/opportunity_repository.dart';
import 'package:opportunityhub_flutter/features/opportunities/presentation/student_opportunity_details_screen.dart';
import 'package:opportunityhub_flutter/models/opportunity_model.dart';
import 'package:opportunityhub_flutter/models/opportunity_skill_model.dart';
import 'package:opportunityhub_flutter/models/organization_profile_model.dart';
import 'package:opportunityhub_flutter/models/skill_model.dart';
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

Future<StudentOpportunitiesProvider> _pumpDetails(
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
  final provider = StudentOpportunitiesProvider(
    repository: repository,
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
        path: '${AppRoutes.studentOpportunities}/:id',
        builder: (_, state) => StudentOpportunityDetailsScreen(
          opportunityId: int.parse(state.pathParameters['id']!),
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

  testWidgets('No apply/save/edit/delete/applicant UI appears anywhere', (
    tester,
  ) async {
    final repository = _FakeOpportunityRepository(getResult: _opportunity());
    await _pumpDetails(tester, repository: repository);

    expect(find.textContaining('Apply'), findsNothing);
    expect(find.textContaining('Save'), findsNothing);
    expect(find.byIcon(Icons.edit_outlined), findsNothing);
    expect(find.byIcon(Icons.delete_outline), findsNothing);
    expect(find.textContaining('Applicant'), findsNothing);
    expect(find.textContaining('Interview'), findsNothing);
    expect(find.textContaining('Quiz'), findsNothing);
  });
}
