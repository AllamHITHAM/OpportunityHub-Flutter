// Widget tests for OpportunityFormScreen (create and edit modes), in
// isolation with a small GoRouter.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'package:opportunityhub_flutter/core/api/api_client.dart';
import 'package:opportunityhub_flutter/core/storage/token_storage_service.dart';
import 'package:opportunityhub_flutter/core/theme/app_colors.dart';
import 'package:opportunityhub_flutter/core/theme/app_theme.dart';
import 'package:opportunityhub_flutter/core/widgets/app_widgets.dart';
import 'package:opportunityhub_flutter/features/auth/data/auth_repository.dart';
import 'package:opportunityhub_flutter/features/locations/data/location_repository.dart';
import 'package:opportunityhub_flutter/features/opportunities/data/opportunity_repository.dart';
import 'package:opportunityhub_flutter/features/opportunities/presentation/opportunity_form_screen.dart';
import 'package:opportunityhub_flutter/models/location_model.dart';
import 'package:opportunityhub_flutter/models/opportunity_model.dart';
import 'package:opportunityhub_flutter/models/opportunity_skill_model.dart';
import 'package:opportunityhub_flutter/models/skill_model.dart';
import 'package:opportunityhub_flutter/providers/auth_provider.dart';
import 'package:opportunityhub_flutter/providers/location_catalog_provider.dart';
import 'package:opportunityhub_flutter/providers/organization_opportunities_provider.dart';
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

OpportunityModel _opportunity({
  int id = 1,
  String title = 'Software Engineer',
  String status = 'open',
  List<String> eligibleMajors = const [],
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
    positionsAvailable: 1,
    status: status,
    eligibleMajors: eligibleMajors,
    opportunitySkills: opportunitySkills,
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

  // Opportunity Requirements Integrity Patch: at least one catalog skill
  // by default, so a generic successful-submission test can always add a
  // real Required Skill via `_addDefaultSkill()` without every individual
  // test having to set up its own catalog first.
  List<SkillModel> skillCatalog = [const SkillModel(id: 1, name: 'PHP')];
  Map<int, bool>? lastSkillsSync;

  @override
  Future<OpportunityModel> createOpportunity({
    required String title,
    required String description,
    required String opportunityType,
    required String employmentType,
    required String workMode,
    required String experienceLevel,
    String? educationLevel,
    int? locationId,
    double? salaryMin,
    double? salaryMax,
    DateTime? applicationDeadline,
    int? positionsAvailable,
    String? status,
    List<String>? eligibleMajors,
    Map<int, bool>? skills,
    String? recruitmentProcess,
  }) async {
    createCallCount++;
    lastPayload = {
      'title': title,
      'location_id': locationId,
      'eligible_majors': eligibleMajors,
      'skills': skills,
      'recruitment_process': recruitmentProcess,
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
    int? locationId,
    double? salaryMin,
    double? salaryMax,
    DateTime? applicationDeadline,
    int? positionsAvailable,
    String? status,
    List<String>? eligibleMajors,
    Map<int, bool>? skills,
    String? recruitmentProcess,
  }) async {
    updateCallCount++;
    lastPayload = {
      'title': title,
      'location_id': locationId,
      'eligible_majors': eligibleMajors,
      'skills': skills,
      'recruitment_process': recruitmentProcess,
    };
    return _opportunity(id: id, title: title);
  }

  @override
  Future<List<SkillModel>> getSkillCatalog() async => skillCatalog;

  @override
  Future<List<OpportunitySkillModel>> syncOpportunitySkills(
    int opportunityId,
    Map<int, bool> skillIdToIsRequired,
  ) async {
    lastSkillsSync = skillIdToIsRequired;
    return [];
  }
}

class _FakeLocationRepository extends LocationRepository {
  _FakeLocationRepository({this.locations = const []})
    : super(apiClient: ApiClient(tokenStorageService: TokenStorageService()));

  List<LocationModel> locations;

  @override
  Future<List<LocationModel>> getLocations() async => locations;
}

Future<(OrganizationOpportunitiesProvider, List<String>)> _pumpForm(
  WidgetTester tester, {
  required _FakeOpportunityRepository repository,
  int? opportunityId,
  Size size = const Size(420, 1400),
  List<LocationModel> locations = const [],
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
  final locationCatalogProvider = LocationCatalogProvider(
    repository: _FakeLocationRepository(locations: locations),
  );
  final themeProvider = ThemeProvider();

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
    MultiProvider(
      providers: [
        ChangeNotifierProvider<OrganizationOpportunitiesProvider>.value(
          value: provider,
        ),
        ChangeNotifierProvider<LocationCatalogProvider>.value(
          value: locationCatalogProvider,
        ),
        ChangeNotifierProvider<ThemeProvider>.value(value: themeProvider),
      ],
      child: Builder(
        builder: (context) {
          final mode = context.watch<ThemeProvider>().mode;
          return MaterialApp.router(
            theme: AppTheme.lightTheme,
            darkTheme: AppTheme.darkTheme,
            themeMode: mode,
            routerConfig: router,
          );
        },
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

Future<void> _selectDropdown(
  WidgetTester tester,
  String label,
  String optionText,
) async {
  final dropdown = find.widgetWithText(DropdownButtonFormField<String>, label);
  await _tapVisible(tester, dropdown);
  await tester.pumpAndSettle();
  await tester.tap(find.text(optionText).last);
  await tester.pumpAndSettle();
}

Future<void> _fillRequiredFields(
  WidgetTester tester, {
  String recruitmentProcess = 'No Assessment',
  String workMode = 'Remote',
}) async {
  await _enterText(tester, 'Title', 'Software Engineer');
  await _enterText(tester, 'Description', 'A great opportunity.');

  await _selectDropdown(tester, 'Opportunity Type', 'Job');
  await _selectDropdown(tester, 'Employment Type', 'Full Time');
  await _selectDropdown(tester, 'Work Mode', workMode);
  await _selectDropdown(tester, 'Experience Level', 'Junior');
  // Phase 10A.4B: a real, required choice on this form (the backend field
  // itself stays optional for backward compatibility with every other
  // caller -- see StoreOpportunityRequest's own doc comment).
  await _selectDropdown(tester, 'Recruitment Process', recruitmentProcess);

  // Opportunity Requirements Integrity Patch: Eligible Majors is now
  // required too -- a plain text field, so it's always safe to fill here
  // regardless of what catalog a given test's repository sets up. Adding
  // "Computer Science" a second time (a test that also adds its own major
  // explicitly) is a harmless, silently-ignored duplicate.
  await _enterText(tester, 'Add a major', 'Computer Science');
  await _tapVisible(tester, find.byTooltip('Add major'));
  await tester.pumpAndSettle();
}

/// Opportunity Requirements Integrity Patch: adds one Required Skill via
/// the real "Add a skill" catalog dropdown -- unlike Eligible Majors, this
/// is catalog-dependent, so it's a separate helper (not baked into
/// [_fillRequiredFields]) that callers invoke only when they want a
/// generic, valid Required Skill and don't care which one specifically.
/// [skillName] must exist in the pumped repository's `skillCatalog`
/// (`_FakeOpportunityRepository`'s own default is `PHP`).
Future<void> _addDefaultSkill(
  WidgetTester tester, {
  String skillName = 'PHP',
}) async {
  await _tapVisible(
    tester,
    find.widgetWithText(DropdownButtonFormField<int>, 'Add a skill'),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text(skillName).last);
  await tester.pumpAndSettle();
  await _tapVisible(tester, find.byTooltip('Add skill'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('Required field validation blocks the API call', (tester) async {
    final repository = _FakeOpportunityRepository();
    await _pumpForm(tester, repository: repository);

    await _tapVisible(
      tester,
      find.widgetWithText(ElevatedButton, 'Create Opportunity'),
    );
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
      await _addDefaultSkill(tester);
      await _tapVisible(
        tester,
        find.widgetWithText(ElevatedButton, 'Create Opportunity'),
      );
      await tester.pumpAndSettle();

      expect(repository.createCallCount, 1);
      expect(repository.lastPayload?['location_id'], isNull);
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
    await _addDefaultSkill(tester);
    await _tapVisible(
      tester,
      find.widgetWithText(ElevatedButton, 'Create Opportunity'),
    );
    await tester.pump();

    final titleField =
        tester.widget(find.widgetWithText(TextFormField, 'Title'))
            as TextFormField;
    expect(titleField.enabled, isFalse);

    await tester.tap(
      find.widgetWithText(ElevatedButton, 'Create Opportunity'),
      warnIfMissed: false,
    );
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
    await _addDefaultSkill(tester);
    await _tapVisible(
      tester,
      find.widgetWithText(ElevatedButton, 'Create Opportunity'),
    );
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
    await _addDefaultSkill(tester);
    await _tapVisible(
      tester,
      find.widgetWithText(ElevatedButton, 'Create Opportunity'),
    );
    await tester.pumpAndSettle();

    expect(find.text('No internet connection.'), findsOneWidget);
    // "Create Opportunity" now appears both as the AppBar title and as the
    // primary button's own label -- still on the form either way.
    expect(find.text('Create Opportunity'), findsNWidgets(2));
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
    await _addDefaultSkill(tester);
    await _tapVisible(
      tester,
      find.widgetWithText(ElevatedButton, 'Create Opportunity'),
    );
    await tester.pumpAndSettle();

    expect(provider.opportunities, hasLength(1));
    expect(provider.opportunities.single.id, 99);
    expect(visitedPaths, contains('details/99'));
  });

  group('Opportunity Academic Matching Cleanup', () {
    testWidgets('Create Opportunity never shows a Field of Study field', (
      tester,
    ) async {
      await _pumpForm(tester, repository: _FakeOpportunityRepository());

      expect(find.text('Field of Study (optional)'), findsNothing);
      expect(find.textContaining('Field of Study'), findsNothing);
    });

    testWidgets('Edit Opportunity never shows a Field of Study field', (
      tester,
    ) async {
      final repository = _FakeOpportunityRepository(
        getResult: _opportunity(
          id: 5,
          title: 'Existing Title',
          eligibleMajors: const ['Computer Science'],
          opportunitySkills: const [
            OpportunitySkillModel(
              id: 1,
              isRequired: true,
              skill: SkillModel(id: 1, name: 'PHP'),
            ),
          ],
        ),
      );
      await _pumpForm(tester, repository: repository, opportunityId: 5);

      expect(find.text('Field of Study (optional)'), findsNothing);
      expect(find.textContaining('Field of Study'), findsNothing);
    });

    testWidgets(
      'Eligible Majors and Required Skills remain visible and required',
      (tester) async {
        await _pumpForm(tester, repository: _FakeOpportunityRepository());

        expect(find.text('Eligible Majors *'), findsOneWidget);
        expect(find.text('Required Skills *'), findsOneWidget);
      },
    );
  });

  group('recruitment process', () {
    testWidgets('appears before the Create/Save action, not after it', (
      tester,
    ) async {
      await _pumpForm(tester, repository: _FakeOpportunityRepository());

      final recruitmentHeaderY = tester
          .getTopLeft(find.text('Recruitment Process').first)
          .dy;
      final buttonY = tester
          .getTopLeft(find.widgetWithText(ElevatedButton, 'Create Opportunity'))
          .dy;

      expect(recruitmentHeaderY, lessThan(buttonY));
    });

    testWidgets('Create/Save is the only primary action, and it is last', (
      tester,
    ) async {
      await _pumpForm(tester, repository: _FakeOpportunityRepository());

      // Exactly one ElevatedButton on the whole form -- the single
      // Create/Save action, never a second one before Recruitment Process.
      expect(find.byType(ElevatedButton), findsOneWidget);

      final buttonY = tester
          .getTopLeft(find.widgetWithText(ElevatedButton, 'Create Opportunity'))
          .dy;
      final statusHeaderY = tester.getTopLeft(find.text('Publishing')).dy;

      // Publishing (the final configuration section) still renders above
      // the button -- the button is the true final element of the form.
      expect(statusHeaderY, lessThan(buttonY));
    });

    testWidgets('selecting Quiz shows the truthful shared-quiz helper copy', (
      tester,
    ) async {
      await _pumpForm(tester, repository: _FakeOpportunityRepository());

      final dropdown = find.widgetWithText(
        DropdownButtonFormField<String>,
        'Recruitment Process',
      );
      await _tapVisible(tester, dropdown);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Quiz').last);
      await tester.pumpAndSettle();

      expect(
        find.text(
          'The quiz can be configured after the opportunity is created.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('the selected value is submitted in the create payload', (
      tester,
    ) async {
      final repository = _FakeOpportunityRepository();
      await _pumpForm(tester, repository: repository);

      await _fillRequiredFields(tester, recruitmentProcess: 'Interview Only');
      await _addDefaultSkill(tester);
      await _tapVisible(
        tester,
        find.widgetWithText(ElevatedButton, 'Create Opportunity'),
      );
      await tester.pumpAndSettle();

      expect(repository.lastPayload?['recruitment_process'], 'interview');
    });
  });

  group('theme toggle', () {
    testWidgets('is present in the AppBar and switches the resolved theme', (
      tester,
    ) async {
      await _pumpForm(tester, repository: _FakeOpportunityRepository());

      expect(find.byType(ThemeToggleButton), findsOneWidget);
      expect(
        Theme.of(tester.element(find.byType(Scaffold).first)).brightness,
        Brightness.light,
      );

      await tester.tap(find.byType(ThemeToggleButton));
      await tester.pumpAndSettle();

      expect(
        Theme.of(tester.element(find.byType(Scaffold).first)).brightness,
        Brightness.dark,
      );
    });

    testWidgets(
      'UI Phase O3.1 — sits inside a visible, comfortably-sized circular surface',
      (tester) async {
        await _pumpForm(tester, repository: _FakeOpportunityRepository());

        final container = tester.widget<Container>(
          find
              .ancestor(
                of: find.byType(ThemeToggleButton),
                matching: find.byType(Container),
              )
              .first,
        );
        final decoration = container.decoration as BoxDecoration;

        expect(decoration.shape, BoxShape.circle);
        expect(decoration.border, isNotNull);
        expect(
          container.constraints?.maxWidth ?? container.constraints?.minWidth,
          40,
        );
      },
    );

    testWidgets(
      'UI Phase O3.1 — the tooltip reflects the real toggle direction in '
      'both states',
      (tester) async {
        await _pumpForm(tester, repository: _FakeOpportunityRepository());

        expect(find.byTooltip('Switch to dark mode'), findsOneWidget);

        await tester.tap(find.byType(ThemeToggleButton));
        await tester.pumpAndSettle();

        expect(find.byTooltip('Switch to light mode'), findsOneWidget);
      },
    );

    testWidgets(
      'theme selection persists across ordinary form interaction (not '
      'reset by typing or scrolling)',
      (tester) async {
        await _pumpForm(tester, repository: _FakeOpportunityRepository());

        await tester.tap(find.byType(ThemeToggleButton));
        await tester.pumpAndSettle();
        expect(
          Theme.of(tester.element(find.byType(Scaffold).first)).brightness,
          Brightness.dark,
        );

        await _enterText(tester, 'Title', 'Software Engineer');
        await tester.pumpAndSettle();

        expect(
          Theme.of(tester.element(find.byType(Scaffold).first)).brightness,
          Brightness.dark,
        );
      },
    );
  });

  group('Light theme rendering (UI Phase O3.1)', () {
    testWidgets('renders every section with real content and no exception', (
      tester,
    ) async {
      await _pumpForm(tester, repository: _FakeOpportunityRepository());

      expect(tester.takeException(), isNull);
      expect(find.text('Opportunity Details'), findsOneWidget);
      expect(find.text('Candidate Requirements'), findsOneWidget);
      expect(find.text('Location & Compensation'), findsOneWidget);
      // "Recruitment Process" appears both as the section header and as
      // the dropdown's own label.
      expect(find.text('Recruitment Process'), findsWidgets);
      expect(find.text('Publishing'), findsOneWidget);
    });

    testWidgets(
      'section cards use a real, visible border color distinct from the '
      'page background',
      (tester) async {
        await _pumpForm(tester, repository: _FakeOpportunityRepository());

        final card = tester.widget<AppCard>(find.byType(AppCard).first);
        expect(card.borderColor, isNotNull);
        expect(card.borderColor, isNot(AppColorsLight.background));
      },
    );
  });

  group('eligible majors (Phase 8B-3.2)', () {
    testWidgets('Adding multiple majors shows them as chips', (tester) async {
      await _pumpForm(tester, repository: _FakeOpportunityRepository());

      await _enterText(tester, 'Add a major', 'Computer Science');
      await _tapVisible(tester, find.byTooltip('Add major'));
      await tester.pumpAndSettle();
      await _enterText(tester, 'Add a major', 'Software Engineering');
      await _tapVisible(tester, find.byTooltip('Add major'));
      await tester.pumpAndSettle();

      expect(find.widgetWithText(Chip, 'Computer Science'), findsOneWidget);
      expect(find.widgetWithText(Chip, 'Software Engineering'), findsOneWidget);
    });

    testWidgets('Removing a major removes its chip', (tester) async {
      await _pumpForm(tester, repository: _FakeOpportunityRepository());

      await _enterText(tester, 'Add a major', 'Computer Science');
      await _tapVisible(tester, find.byTooltip('Add major'));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(Chip, 'Computer Science'), findsOneWidget);

      await _tapVisible(
        tester,
        find.descendant(
          of: find.widgetWithText(Chip, 'Computer Science'),
          matching: find.byIcon(Icons.cancel),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.widgetWithText(Chip, 'Computer Science'), findsNothing);
    });

    testWidgets(
      'A duplicate major (case/whitespace-insensitive) is not added twice',
      (tester) async {
        await _pumpForm(tester, repository: _FakeOpportunityRepository());

        await _enterText(tester, 'Add a major', 'Computer Science');
        await _tapVisible(tester, find.byTooltip('Add major'));
        await tester.pumpAndSettle();
        await _enterText(tester, 'Add a major', '  computer   science ');
        await _tapVisible(tester, find.byTooltip('Add major'));
        await tester.pumpAndSettle();

        expect(find.widgetWithText(Chip, 'Computer Science'), findsOneWidget);
      },
    );

    testWidgets('Leaving Eligible Majors empty blocks submission (Opportunity '
        'Requirements Integrity Patch -- at least one is now required)', (
      tester,
    ) async {
      final repository = _FakeOpportunityRepository();
      await _pumpForm(tester, repository: repository);

      expect(
        find.textContaining('At least one major is required'),
        findsOneWidget,
      );

      // Every other required field filled, and a Required Skill added,
      // but Eligible Majors deliberately left empty -- _fillRequiredFields
      // is not used here since it now always adds a major itself.
      await _enterText(tester, 'Title', 'Software Engineer');
      await _enterText(tester, 'Description', 'A great opportunity.');
      await _selectDropdown(tester, 'Opportunity Type', 'Job');
      await _selectDropdown(tester, 'Employment Type', 'Full Time');
      await _selectDropdown(tester, 'Work Mode', 'Remote');
      await _selectDropdown(tester, 'Experience Level', 'Junior');
      await _selectDropdown(tester, 'Recruitment Process', 'No Assessment');
      await _addDefaultSkill(tester);

      await _tapVisible(
        tester,
        find.widgetWithText(ElevatedButton, 'Create Opportunity'),
      );
      await tester.pumpAndSettle();

      expect(find.text('Select at least one eligible major.'), findsOneWidget);
      expect(repository.createCallCount, 0);
    });

    testWidgets('Submit payload includes the eligible majors', (tester) async {
      final repository = _FakeOpportunityRepository();
      await _pumpForm(tester, repository: repository);

      // _fillRequiredFields already adds "Computer Science" -- adding it
      // again here is a harmless, silently-ignored duplicate, confirming
      // the field genuinely reflects the real selection either way.
      await _fillRequiredFields(tester);
      await _addDefaultSkill(tester);
      await _enterText(tester, 'Add a major', 'Computer Science');
      await _tapVisible(tester, find.byTooltip('Add major'));
      await tester.pumpAndSettle();
      await _tapVisible(
        tester,
        find.widgetWithText(ElevatedButton, 'Create Opportunity'),
      );
      await tester.pumpAndSettle();

      expect(repository.lastPayload?['eligible_majors'], ['Computer Science']);
    });

    testWidgets(
      'there is no Field of Study field at all on Create Opportunity '
      '(Opportunity Academic Matching Cleanup) -- the reported bug is now '
      'structurally impossible, not just guarded against',
      (tester) async {
        final repository = _FakeOpportunityRepository();
        await _pumpForm(tester, repository: repository);

        expect(find.textContaining('Field of Study'), findsNothing);

        await _fillRequiredFields(tester);
        await _addDefaultSkill(tester);
        await _tapVisible(
          tester,
          find.widgetWithText(ElevatedButton, 'Create Opportunity'),
        );
        await tester.pumpAndSettle();

        // No `fieldOfStudy` parameter exists on OpportunityRepository's
        // createOpportunity/updateOpportunity any more -- this test would
        // fail to compile if one were ever reintroduced.
        // _fillRequiredFields' own real Eligible Major ("Computer Science")
        // is present and unaffected.
        expect(repository.lastPayload?['eligible_majors'], [
          'Computer Science',
        ]);
      },
    );
  });

  group('responsive layout', () {
    testWidgets('Does not overflow at a narrow 320x720 viewport', (
      tester,
    ) async {
      await _pumpForm(
        tester,
        repository: _FakeOpportunityRepository(),
        size: const Size(320, 720),
      );

      expect(tester.takeException(), isNull);
    });

    testWidgets('Does not overflow on a mobile viewport (375-430)', (
      tester,
    ) async {
      await _pumpForm(
        tester,
        repository: _FakeOpportunityRepository(),
        size: const Size(390, 844),
      );

      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'Mobile stacks paired fields into a single column (Opportunity Type '
      'sits above, not beside, Employment Type)',
      (tester) async {
        await _pumpForm(
          tester,
          repository: _FakeOpportunityRepository(),
          size: const Size(390, 1400),
        );

        final typeY = tester
            .getTopLeft(
              find.widgetWithText(
                DropdownButtonFormField<String>,
                'Opportunity Type',
              ),
            )
            .dy;
        final employmentY = tester
            .getTopLeft(
              find.widgetWithText(
                DropdownButtonFormField<String>,
                'Employment Type',
              ),
            )
            .dy;

        expect(typeY, lessThan(employmentY));
      },
    );

    testWidgets('Does not overflow on a tablet viewport (600-899)', (
      tester,
    ) async {
      await _pumpForm(
        tester,
        repository: _FakeOpportunityRepository(),
        size: const Size(700, 1200),
      );

      expect(tester.takeException(), isNull);
    });

    testWidgets('Does not overflow on a 900-1199 viewport', (tester) async {
      await _pumpForm(
        tester,
        repository: _FakeOpportunityRepository(),
        size: const Size(1000, 1000),
      );

      expect(tester.takeException(), isNull);
    });

    testWidgets('Does not overflow on a desktop viewport (>=1200)', (
      tester,
    ) async {
      await _pumpForm(
        tester,
        repository: _FakeOpportunityRepository(),
        size: const Size(1400, 1000),
      );

      expect(tester.takeException(), isNull);
    });

    testWidgets('Desktop pairs Opportunity Type/Employment Type side by side', (
      tester,
    ) async {
      await _pumpForm(
        tester,
        repository: _FakeOpportunityRepository(),
        size: const Size(1400, 1000),
      );

      final typeTop = tester
          .getTopLeft(
            find.widgetWithText(
              DropdownButtonFormField<String>,
              'Opportunity Type',
            ),
          )
          .dy;
      final employmentTop = tester
          .getTopLeft(
            find.widgetWithText(
              DropdownButtonFormField<String>,
              'Employment Type',
            ),
          )
          .dy;

      // Side by side means the same row -- equal vertical position.
      expect(typeTop, employmentTop);
    });

    testWidgets('renders correctly in Dark Mode', (tester) async {
      tester.view.physicalSize = const Size(420, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final authProvider = AuthProvider(authRepository: _FakeAuthRepository());
      final provider = OrganizationOpportunitiesProvider(
        repository: _FakeOpportunityRepository(),
        authProvider: authProvider,
      );
      final router = GoRouter(
        initialLocation: AppRoutes.organizationOpportunityCreate,
        routes: [
          GoRoute(
            path: AppRoutes.organizationOpportunityCreate,
            builder: (_, _) => const OpportunityFormScreen(),
          ),
        ],
      );

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<OrganizationOpportunitiesProvider>.value(
              value: provider,
            ),
            ChangeNotifierProvider<LocationCatalogProvider>.value(
              value: LocationCatalogProvider(
                repository: _FakeLocationRepository(),
              ),
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
      expect(find.text('Opportunity Details'), findsOneWidget);
    });
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

    testWidgets('Edit action pre-fills existing eligible majors as chips', (
      tester,
    ) async {
      final repository = _FakeOpportunityRepository(
        getResult: _opportunity(
          id: 5,
          title: 'Existing Title',
          eligibleMajors: ['Civil Engineering', 'Architecture'],
        ),
      );
      await _pumpForm(tester, repository: repository, opportunityId: 5);

      expect(find.widgetWithText(Chip, 'Civil Engineering'), findsOneWidget);
      expect(find.widgetWithText(Chip, 'Architecture'), findsOneWidget);
    });

    testWidgets('Submits via update (PUT), not create', (tester) async {
      final repository = _FakeOpportunityRepository(
        getResult: _opportunity(
          id: 5,
          title: 'Existing Title',
          eligibleMajors: const ['Computer Science'],
          opportunitySkills: const [
            OpportunitySkillModel(
              id: 1,
              isRequired: true,
              skill: SkillModel(id: 1, name: 'PHP'),
            ),
          ],
        ),
      );
      await _pumpForm(tester, repository: repository, opportunityId: 5);

      await _enterText(tester, 'Title', 'Updated Title');
      await _tapVisible(tester, find.text('Save Changes'));
      await tester.pumpAndSettle();

      expect(repository.updateCallCount, 1);
      expect(repository.createCallCount, 0);
    });

    testWidgets('Save Changes is the only primary action and appears after '
        'Recruitment Process', (tester) async {
      final repository = _FakeOpportunityRepository(
        getResult: _opportunity(id: 5, title: 'Existing Title'),
      );
      await _pumpForm(tester, repository: repository, opportunityId: 5);

      expect(find.byType(ElevatedButton), findsOneWidget);

      final recruitmentHeaderY = tester
          .getTopLeft(find.text('Recruitment Process').first)
          .dy;
      final buttonY = tester
          .getTopLeft(find.widgetWithText(ElevatedButton, 'Save Changes'))
          .dy;

      expect(recruitmentHeaderY, lessThan(buttonY));
    });

    testWidgets('the theme toggle is present in edit mode too', (tester) async {
      final repository = _FakeOpportunityRepository(
        getResult: _opportunity(id: 5, title: 'Existing Title'),
      );
      await _pumpForm(tester, repository: repository, opportunityId: 5);

      expect(find.byType(ThemeToggleButton), findsOneWidget);
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

  group('canonical location (Phase O8.2)', () {
    testWidgets('Remote shows no location field, never claims one is needed', (
      tester,
    ) async {
      final repository = _FakeOpportunityRepository();
      await _pumpForm(
        tester,
        repository: repository,
        locations: const [LocationModel(id: 1, canonicalName: 'Nablus')],
      );

      await _fillRequiredFields(tester, workMode: 'Remote');

      expect(
        find.text('Not applicable for a Remote opportunity.'),
        findsOneWidget,
      );
      expect(
        find.widgetWithText(DropdownButtonFormField<int>, 'Location'),
        findsNothing,
      );
    });

    testWidgets('On-site shows the real catalog and submits the chosen ID', (
      tester,
    ) async {
      final repository = _FakeOpportunityRepository();
      await _pumpForm(
        tester,
        repository: repository,
        locations: const [
          LocationModel(id: 1, canonicalName: 'Nablus'),
          LocationModel(id: 2, canonicalName: 'Ramallah'),
        ],
      );

      await _fillRequiredFields(tester, workMode: 'Onsite');
      await _addDefaultSkill(tester);
      await _tapVisible(
        tester,
        find.widgetWithText(DropdownButtonFormField<int>, 'Location'),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ramallah').last);
      await tester.pumpAndSettle();

      await _tapVisible(
        tester,
        find.widgetWithText(ElevatedButton, 'Create Opportunity'),
      );
      await tester.pumpAndSettle();

      expect(repository.lastPayload?['location_id'], 2);
    });

    testWidgets('On-site with no location selected blocks submission', (
      tester,
    ) async {
      final repository = _FakeOpportunityRepository();
      await _pumpForm(
        tester,
        repository: repository,
        locations: const [LocationModel(id: 1, canonicalName: 'Nablus')],
      );

      await _fillRequiredFields(tester, workMode: 'Onsite');
      await _tapVisible(
        tester,
        find.widgetWithText(ElevatedButton, 'Create Opportunity'),
      );
      await tester.pumpAndSettle();

      expect(
        find.text('Select a location for an on-site or hybrid opportunity'),
        findsOneWidget,
      );
      expect(repository.createCallCount, 0);
    });

    testWidgets('Edit action pre-fills the existing canonical location', (
      tester,
    ) async {
      final repository = _FakeOpportunityRepository(
        getResult: OpportunityModel(
          id: 5,
          title: 'Existing Title',
          description: 'A great opportunity.',
          opportunityType: 'job',
          employmentType: 'full_time',
          workMode: 'onsite',
          experienceLevel: 'junior',
          positionsAvailable: 1,
          status: 'open',
          location: 'Nablus',
          locationId: 1,
        ),
      );
      await _pumpForm(
        tester,
        repository: repository,
        opportunityId: 5,
        locations: const [LocationModel(id: 1, canonicalName: 'Nablus')],
      );

      expect(
        find.widgetWithText(DropdownButtonFormField<int>, 'Location'),
        findsOneWidget,
      );
      final dropdown = tester.widget<DropdownButtonFormField<int>>(
        find.widgetWithText(DropdownButtonFormField<int>, 'Location'),
      );
      expect(dropdown.initialValue, 1);
    });
  });

  group('required skills (Phase O8.2)', () {
    testWidgets('Adding a catalog skill shows it as Required by default', (
      tester,
    ) async {
      final repository = _FakeOpportunityRepository()
        ..skillCatalog = [const SkillModel(id: 10, name: 'Laravel')];
      await _pumpForm(tester, repository: repository);
      await tester.pumpAndSettle();

      await _tapVisible(
        tester,
        find.widgetWithText(DropdownButtonFormField<int>, 'Add a skill'),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Laravel').last);
      await tester.pumpAndSettle();
      await _tapVisible(tester, find.byTooltip('Add skill'));
      await tester.pumpAndSettle();

      expect(find.text('Laravel (Required)'), findsOneWidget);
    });

    testWidgets('Tapping a selected skill chip toggles Required/Preferred', (
      tester,
    ) async {
      final repository = _FakeOpportunityRepository()
        ..skillCatalog = [const SkillModel(id: 10, name: 'Laravel')];
      await _pumpForm(tester, repository: repository);
      await tester.pumpAndSettle();

      await _tapVisible(
        tester,
        find.widgetWithText(DropdownButtonFormField<int>, 'Add a skill'),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Laravel').last);
      await tester.pumpAndSettle();
      await _tapVisible(tester, find.byTooltip('Add skill'));
      await tester.pumpAndSettle();

      await _tapVisible(tester, find.text('Laravel (Required)'));
      await tester.pumpAndSettle();

      expect(find.text('Laravel (Preferred)'), findsOneWidget);
    });

    testWidgets('Submit syncs the real skill IDs, never free text', (
      tester,
    ) async {
      final repository = _FakeOpportunityRepository()
        ..skillCatalog = [const SkillModel(id: 10, name: 'Laravel')];
      await _pumpForm(tester, repository: repository);
      await tester.pumpAndSettle();

      await _fillRequiredFields(tester);
      await _tapVisible(
        tester,
        find.widgetWithText(DropdownButtonFormField<int>, 'Add a skill'),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Laravel').last);
      await tester.pumpAndSettle();
      await _tapVisible(tester, find.byTooltip('Add skill'));
      await tester.pumpAndSettle();

      await _tapVisible(
        tester,
        find.widgetWithText(ElevatedButton, 'Create Opportunity'),
      );
      await tester.pumpAndSettle();

      // Opportunity Requirements Integrity Patch: Required Skills are now
      // saved atomically in the same create/update request, never via a
      // separate later syncOpportunitySkills() call.
      expect(repository.lastPayload?['skills'], {10: true});
      expect(repository.lastSkillsSync, isNull);
    });

    testWidgets('Edit action pre-fills existing required/preferred skills', (
      tester,
    ) async {
      final repository =
          _FakeOpportunityRepository(
              getResult: OpportunityModel(
                id: 5,
                title: 'Existing Title',
                description: 'A great opportunity.',
                opportunityType: 'job',
                employmentType: 'full_time',
                workMode: 'remote',
                experienceLevel: 'junior',
                positionsAvailable: 1,
                status: 'open',
                opportunitySkills: const [
                  OpportunitySkillModel(
                    id: 1,
                    isRequired: true,
                    skill: SkillModel(id: 10, name: 'Laravel'),
                  ),
                  OpportunitySkillModel(
                    id: 2,
                    isRequired: false,
                    skill: SkillModel(id: 11, name: 'Docker'),
                  ),
                ],
              ),
            )
            ..skillCatalog = [
              const SkillModel(id: 10, name: 'Laravel'),
              const SkillModel(id: 11, name: 'Docker'),
            ];
      await _pumpForm(tester, repository: repository, opportunityId: 5);
      await tester.pumpAndSettle();

      expect(find.text('Laravel (Required)'), findsOneWidget);
      expect(find.text('Docker (Preferred)'), findsOneWidget);
    });

    for (final width in [375.0, 390.0, 430.0]) {
      testWidgets(
        'mobile ${width.toInt()} — many selected skill chips wrap without '
        'overflow',
        (tester) async {
          final repository =
              _FakeOpportunityRepository(
                  getResult: OpportunityModel(
                    id: 5,
                    title: 'Existing Title',
                    description: 'A great opportunity.',
                    opportunityType: 'job',
                    employmentType: 'full_time',
                    workMode: 'onsite',
                    experienceLevel: 'junior',
                    positionsAvailable: 1,
                    status: 'open',
                    locationId: 1,
                    opportunitySkills: const [
                      OpportunitySkillModel(
                        id: 1,
                        isRequired: true,
                        skill: SkillModel(id: 10, name: 'Laravel'),
                      ),
                      OpportunitySkillModel(
                        id: 2,
                        isRequired: false,
                        skill: SkillModel(id: 11, name: 'Docker'),
                      ),
                      OpportunitySkillModel(
                        id: 3,
                        isRequired: true,
                        skill: SkillModel(id: 12, name: 'MySQL'),
                      ),
                      OpportunitySkillModel(
                        id: 4,
                        isRequired: false,
                        skill: SkillModel(id: 13, name: 'Redis'),
                      ),
                      OpportunitySkillModel(
                        id: 5,
                        isRequired: true,
                        skill: SkillModel(id: 14, name: 'Kubernetes'),
                      ),
                    ],
                  ),
                )
                ..skillCatalog = [
                  const SkillModel(id: 10, name: 'Laravel'),
                  const SkillModel(id: 11, name: 'Docker'),
                  const SkillModel(id: 12, name: 'MySQL'),
                  const SkillModel(id: 13, name: 'Redis'),
                  const SkillModel(id: 14, name: 'Kubernetes'),
                ];
          await _pumpForm(
            tester,
            repository: repository,
            opportunityId: 5,
            size: Size(width, 1600),
            locations: const [LocationModel(id: 1, canonicalName: 'Nablus')],
          );
          await tester.pumpAndSettle();

          expect(tester.takeException(), isNull);
          expect(find.text('Kubernetes (Required)'), findsOneWidget);
        },
      );
    }
  });
}
