// Widget tests for OpportunityFormScreen (create and edit modes), in
// isolation with a small GoRouter.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'package:opportunityhub_flutter/core/api/api_client.dart';
import 'package:opportunityhub_flutter/core/storage/token_storage_service.dart';
import 'package:opportunityhub_flutter/core/theme/app_theme.dart';
import 'package:opportunityhub_flutter/features/auth/data/auth_repository.dart';
import 'package:opportunityhub_flutter/features/opportunities/data/opportunity_repository.dart';
import 'package:opportunityhub_flutter/features/opportunities/presentation/opportunity_form_screen.dart';
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
    positionsAvailable: 1,
    status: status,
  );
}

class _FakeOpportunityRepository extends OpportunityRepository {
  _FakeOpportunityRepository({
    this.getResult,
    this.getError,
    this.createDelay = Duration.zero,
    this.createError,
  }) : super(apiClient: ApiClient(tokenStorageService: TokenStorageService()));

  OpportunityModel? getResult;
  ApiException? getError;
  Duration createDelay;
  ApiException? createError;
  int createCallCount = 0;
  int updateCallCount = 0;
  Map<String, dynamic>? lastPayload;

  @override
  Future<OpportunityModel> getOpportunity(int id) async {
    if (getError != null) throw getError!;
    return getResult!;
  }

  @override
  Future<OpportunityModel> createOpportunity({
    required String title,
    required String description,
    required String opportunityType,
    required String employmentType,
    required String workMode,
    required String experienceLevel,
    String? educationLevel,
    String? fieldOfStudy,
    String? location,
    double? salaryMin,
    double? salaryMax,
    DateTime? applicationDeadline,
    int? positionsAvailable,
    String? status,
  }) async {
    createCallCount++;
    lastPayload = {
      'title': title,
      'field_of_study': fieldOfStudy,
      'location': location,
    };
    if (createDelay > Duration.zero) {
      await Future<void>.delayed(createDelay);
    }
    if (createError != null) throw createError!;
    return _opportunity(id: 99, title: title);
  }

  @override
  Future<OpportunityModel> updateOpportunity({
    required int id,
    required String title,
    required String description,
    required String opportunityType,
    required String employmentType,
    required String workMode,
    required String experienceLevel,
    String? educationLevel,
    String? fieldOfStudy,
    String? location,
    double? salaryMin,
    double? salaryMax,
    DateTime? applicationDeadline,
    int? positionsAvailable,
    String? status,
  }) async {
    updateCallCount++;
    return _opportunity(id: id, title: title);
  }
}

Future<(OrganizationOpportunitiesProvider, List<String>)> _pumpForm(
  WidgetTester tester, {
  required _FakeOpportunityRepository repository,
  int? opportunityId,
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
    initialLocation: opportunityId == null
        ? AppRoutes.organizationOpportunityCreate
        : AppRoutes.organizationOpportunityEdit(opportunityId),
    routes: [
      GoRoute(
        path: AppRoutes.organizationOpportunityCreate,
        builder: (_, _) => const OpportunityFormScreen(),
      ),
      GoRoute(
        path: '${AppRoutes.organizationOpportunities}/:id/edit',
        builder: (_, state) => OpportunityFormScreen(
          opportunityId: int.parse(state.pathParameters['id']!),
        ),
      ),
      GoRoute(
        path: '${AppRoutes.organizationOpportunities}/:id',
        builder: (_, state) {
          visitedPaths.add('details/${state.pathParameters['id']}');
          return const Scaffold(body: Text('DETAILS_PLACEHOLDER'));
        },
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

Future<void> _enterText(WidgetTester tester, String label, String value) async {
  final field = find.widgetWithText(TextFormField, label);
  await tester.ensureVisible(field);
  await tester.enterText(field, value);
}

Future<void> _tapVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.tap(finder);
}

Future<void> _fillRequiredFields(WidgetTester tester) async {
  await _enterText(tester, 'Title', 'Software Engineer');
  await _enterText(tester, 'Description', 'A great opportunity.');

  Future<void> selectDropdown(String label, String optionText) async {
    final dropdown = find.widgetWithText(
      DropdownButtonFormField<String>,
      label,
    );
    await _tapVisible(tester, dropdown);
    await tester.pumpAndSettle();
    await tester.tap(find.text(optionText).last);
    await tester.pumpAndSettle();
  }

  await selectDropdown('Opportunity Type', 'Job');
  await selectDropdown('Employment Type', 'Full Time');
  await selectDropdown('Work Mode', 'Remote');
  await selectDropdown('Experience Level', 'Junior');
}

void main() {
  testWidgets('Required field validation blocks the API call', (tester) async {
    final repository = _FakeOpportunityRepository();
    await _pumpForm(tester, repository: repository);

    await _tapVisible(tester, find.text('Create'));
    await tester.pumpAndSettle();

    expect(find.text('Title is required'), findsOneWidget);
    expect(find.text('Description is required'), findsOneWidget);
    expect(find.text('Opportunity type is required'), findsOneWidget);
    expect(repository.createCallCount, 0);
  });

  testWidgets('Exact dropdown enums are available for Opportunity Type', (
    tester,
  ) async {
    final repository = _FakeOpportunityRepository();
    await _pumpForm(tester, repository: repository);

    final dropdown = find.widgetWithText(
      DropdownButtonFormField<String>,
      'Opportunity Type',
    );
    await _tapVisible(tester, dropdown);
    await tester.pumpAndSettle();

    for (final label in [
      'Job',
      'Internship',
      'Volunteer',
      'Scholarship',
      'Competition',
    ]) {
      expect(find.text(label), findsWidgets);
    }
  });

  testWidgets(
    'Blank optional fields are not submitted (hidden/unfilled values omitted)',
    (tester) async {
      final repository = _FakeOpportunityRepository();
      await _pumpForm(tester, repository: repository);

      await _fillRequiredFields(tester);
      await _tapVisible(tester, find.text('Create'));
      await tester.pumpAndSettle();

      expect(repository.createCallCount, 1);
      expect(repository.lastPayload?['field_of_study'], isNull);
      expect(repository.lastPayload?['location'], isNull);
    },
  );

  testWidgets('Loading disables controls and prevents double submission', (
    tester,
  ) async {
    final repository = _FakeOpportunityRepository(
      createDelay: const Duration(milliseconds: 200),
    );
    await _pumpForm(tester, repository: repository);

    await _fillRequiredFields(tester);
    await _tapVisible(tester, find.text('Create'));
    await tester.pump();

    final titleField =
        tester.widget(find.widgetWithText(TextFormField, 'Title'))
            as TextFormField;
    expect(titleField.enabled, isFalse);

    await tester.tap(find.text('Create'), warnIfMissed: false);
    await tester.pump();
    expect(repository.createCallCount, 1);

    await tester.pumpAndSettle();
  });

  testWidgets('422 preserves entered values and remains on the form', (
    tester,
  ) async {
    final repository = _FakeOpportunityRepository(
      createError: ApiException(
        'The given data was invalid.',
        statusCode: 422,
        errors: {
          'title': ['The title field is required.'],
        },
      ),
    );
    await _pumpForm(tester, repository: repository);

    await _fillRequiredFields(tester);
    await _tapVisible(tester, find.text('Create'));
    await tester.pumpAndSettle();

    expect(find.text('The given data was invalid.'), findsOneWidget);
    final titleField =
        tester.widget(find.widgetWithText(TextFormField, 'Title'))
            as TextFormField;
    expect(titleField.controller?.text, 'Software Engineer');
  });

  testWidgets('Network/500 errors remain on the form', (tester) async {
    final repository = _FakeOpportunityRepository(
      createError: ApiException('No internet connection.'),
    );
    await _pumpForm(tester, repository: repository);

    await _fillRequiredFields(tester);
    await _tapVisible(tester, find.text('Create'));
    await tester.pumpAndSettle();

    expect(find.text('No internet connection.'), findsOneWidget);
    expect(find.text('Create Opportunity'), findsOneWidget);
  });

  testWidgets('Success updates the list state and navigates to details', (
    tester,
  ) async {
    final repository = _FakeOpportunityRepository();
    final (provider, visitedPaths) = await _pumpForm(
      tester,
      repository: repository,
    );

    await _fillRequiredFields(tester);
    await _tapVisible(tester, find.text('Create'));
    await tester.pumpAndSettle();

    expect(provider.opportunities, hasLength(1));
    expect(provider.opportunities.single.id, 99);
    expect(visitedPaths, contains('details/99'));
  });

  testWidgets('Does not overflow at a narrow 320x720 viewport', (tester) async {
    await _pumpForm(
      tester,
      repository: _FakeOpportunityRepository(),
      size: const Size(320, 720),
    );

    expect(tester.takeException(), isNull);
  });

  group('edit mode', () {
    testWidgets('Edit action loads and pre-fills existing data', (
      tester,
    ) async {
      final repository = _FakeOpportunityRepository(
        getResult: _opportunity(id: 5, title: 'Existing Title'),
      );
      await _pumpForm(tester, repository: repository, opportunityId: 5);

      expect(find.text('Edit Opportunity'), findsOneWidget);
      final titleField =
          tester.widget(find.widgetWithText(TextFormField, 'Title'))
              as TextFormField;
      expect(titleField.controller?.text, 'Existing Title');
    });

    testWidgets('Submits via update (PUT), not create', (tester) async {
      final repository = _FakeOpportunityRepository(
        getResult: _opportunity(id: 5, title: 'Existing Title'),
      );
      await _pumpForm(tester, repository: repository, opportunityId: 5);

      await _enterText(tester, 'Title', 'Updated Title');
      await _tapVisible(tester, find.text('Save Changes'));
      await tester.pumpAndSettle();

      expect(repository.updateCallCount, 1);
      expect(repository.createCallCount, 0);
    });

    testWidgets('Loading/error states render for a failed details load', (
      tester,
    ) async {
      final repository = _FakeOpportunityRepository(
        getError: ApiException('Opportunity not found'),
      );
      await _pumpForm(tester, repository: repository, opportunityId: 999);

      expect(find.text('Opportunity not found'), findsOneWidget);
    });
  });
}
