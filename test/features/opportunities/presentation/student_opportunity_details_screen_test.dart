// Widget tests for StudentOpportunityDetailsScreen, in isolation with a
// small GoRouter.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'package:opportunityhub_flutter/core/api/api_client.dart';
import 'package:opportunityhub_flutter/core/storage/token_storage_service.dart';
import 'package:opportunityhub_flutter/core/theme/app_theme.dart';
import 'package:opportunityhub_flutter/core/widgets/app_skeleton.dart';
import 'package:opportunityhub_flutter/core/widgets/secondary_button.dart';
import 'package:opportunityhub_flutter/core/widgets/status_chip.dart';
import 'package:opportunityhub_flutter/core/widgets/theme_toggle_button.dart';
import 'package:opportunityhub_flutter/features/applications/data/application_repository.dart';
import 'package:opportunityhub_flutter/features/auth/data/auth_repository.dart';
import 'package:opportunityhub_flutter/features/cv/data/cv_repository.dart';
import 'package:opportunityhub_flutter/features/opportunities/data/opportunity_repository.dart';
import 'package:opportunityhub_flutter/features/opportunities/presentation/student_opportunity_details_screen.dart';
import 'package:opportunityhub_flutter/features/skills/data/student_skill_repository.dart';
import 'package:opportunityhub_flutter/features/student/data/student_profile_repository.dart';
import 'package:opportunityhub_flutter/models/application_model.dart';
import 'package:opportunityhub_flutter/models/cv_model.dart';
import 'package:opportunityhub_flutter/models/opportunity_model.dart';
import 'package:opportunityhub_flutter/models/opportunity_skill_model.dart';
import 'package:opportunityhub_flutter/models/organization_profile_model.dart';
import 'package:opportunityhub_flutter/models/skill_model.dart';
import 'package:opportunityhub_flutter/models/student_profile_model.dart';
import 'package:opportunityhub_flutter/providers/auth_provider.dart';
import 'package:opportunityhub_flutter/providers/student_applications_provider.dart';
import 'package:opportunityhub_flutter/providers/student_cv_provider.dart';
import 'package:opportunityhub_flutter/providers/student_opportunities_provider.dart';
import 'package:opportunityhub_flutter/providers/student_profile_provider.dart';
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
  _FakeOpportunityRepository({
    this.getResult,
    this.getError,
    this.getDelay = Duration.zero,
  }) : super(apiClient: ApiClient(tokenStorageService: TokenStorageService()));

  OpportunityModel? getResult;
  ApiException? getError;
  Duration getDelay;

  @override
  Future<OpportunityModel> getPublicOpportunity(int id) async {
    if (getDelay > Duration.zero) {
      await Future<void>.delayed(getDelay);
    }
    if (getError != null) throw getError!;
    return getResult!;
  }
}

class _FakeStudentProfileRepository extends StudentProfileRepository {
  _FakeStudentProfileRepository({this.major})
    : super(apiClient: ApiClient(tokenStorageService: TokenStorageService()));

  final String? major;

  @override
  Future<StudentProfileModel?> getProfile() async => StudentProfileModel(
    id: 1,
    university: 'State University',
    major: major,
    graduationYear: 2027,
  );
}

class _FakeCvRepository extends CvRepository {
  _FakeCvRepository({this.listResult = const []})
    : super(apiClient: ApiClient(tokenStorageService: TokenStorageService()));

  List<CvModel> listResult;

  @override
  Future<List<CvModel>> getStudentCvs() async => listResult;
}

class _FakeApplicationRepository extends ApplicationRepository {
  _FakeApplicationRepository({this.listResult = const [], this.applyResult})
    : super(apiClient: ApiClient(tokenStorageService: TokenStorageService()));

  List<ApplicationModel> listResult;
  ApplicationModel? applyResult;

  @override
  Future<List<ApplicationModel>> getStudentApplications() async => listResult;

  @override
  Future<ApplicationModel> applyToOpportunity({
    required int opportunityId,
    required int cvId,
    String? coverLetter,
  }) async => applyResult!;
}

ApplicationModel _application({required int opportunityId}) {
  return ApplicationModel(
    id: 1,
    studentId: 1,
    opportunityId: opportunityId,
    cvId: 1,
    status: 'pending',
    opportunity: _opportunity(id: opportunityId),
    cv: const CvModel(
      id: 1,
      studentId: 1,
      title: 'My CV',
      filePath: 'cvs/my-cv.pdf',
      version: 1,
      isDefault: true,
      createdByAi: false,
    ),
  );
}

Future<StudentOpportunitiesProvider> _pumpDetails(
  WidgetTester tester, {
  required _FakeOpportunityRepository repository,
  _FakeCvRepository? cvRepository,
  _FakeApplicationRepository? applicationRepository,
  String? studentMajor = 'Computer Science',
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
  final cvProvider = StudentCvProvider(
    repository: cvRepository ?? _FakeCvRepository(),
    studentSkillRepository: StudentSkillRepository(
      apiClient: ApiClient(tokenStorageService: TokenStorageService()),
    ),
    authProvider: authProvider,
  );
  final applicationsProvider = StudentApplicationsProvider(
    repository: applicationRepository ?? _FakeApplicationRepository(),
    authProvider: authProvider,
  );
  // Set directly rather than via `checkProfileStatus()` -- the redirect
  // logic that normally triggers that call doesn't exist in this test's
  // minimal router, and a student can only ever reach this screen with an
  // already-known-complete profile in the real app anyway.
  final studentProfileProvider = StudentProfileProvider(
    repository: _FakeStudentProfileRepository(major: studentMajor),
    authProvider: authProvider,
  )..profile = StudentProfileModel(
    id: 1,
    university: 'State University',
    major: studentMajor,
    graduationYear: 2027,
  );

  final router = GoRouter(
    initialLocation: AppRoutes.studentOpportunityDetails(opportunityId),
    routes: [
      GoRoute(
        path: AppRoutes.studentOpportunities,
        builder: (_, _) => const Scaffold(body: Text('LIST_PLACEHOLDER')),
      ),
      GoRoute(
        path: AppRoutes.studentCvs,
        builder: (_, _) => const Scaffold(body: Text('CVS_PLACEHOLDER')),
      ),
      GoRoute(
        path: '${AppRoutes.studentOpportunities}/:id',
        builder: (_, state) => StudentOpportunityDetailsScreen(
          opportunityId: int.parse(state.pathParameters['id']!),
        ),
      ),
      // Organization Public Profile phase -- the real destination the
      // organization identity (hero row and `_OrganizationCard`) links
      // to.
      GoRoute(
        path: '/organizations/:id',
        builder: (_, state) => Scaffold(
          body: Text('COMPANY_PROFILE_${state.pathParameters['id']}'),
        ),
      ),
    ],
  );

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<StudentOpportunitiesProvider>.value(
          value: provider,
        ),
        ChangeNotifierProvider<StudentCvProvider>.value(value: cvProvider),
        ChangeNotifierProvider<StudentApplicationsProvider>.value(
          value: applicationsProvider,
        ),
        ChangeNotifierProvider<StudentProfileProvider>.value(
          value: studentProfileProvider,
        ),
        ChangeNotifierProvider<ThemeProvider>.value(value: ThemeProvider()),
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
    // Once in the hero subtitle, once more in the "About the Organization"
    // card (UI Phase 2) -- the same real name shown in two places, not a
    // duplicate render of one.
    expect(find.text('Acme Corp'), findsNWidgets(2));
    expect(find.text('Job'), findsOneWidget);
    expect(find.text('Full Time'), findsOneWidget);
    expect(find.text('Remote'), findsOneWidget);
    expect(find.text('Junior'), findsOneWidget);
    expect(find.text('A great opportunity.'), findsOneWidget);
    // Once as a hero location chip, once more in the Details facts grid
    // (UI Phase 2) -- the same real value shown in two places.
    expect(find.text('Amman, Jordan'), findsNWidgets(2));
  });

  testWidgets(
    'Tapping the organization identity card opens its real public '
    'Company Profile (Organization Public Profile phase)',
    (tester) async {
      final repository = _FakeOpportunityRepository(
        getResult: _opportunity(
          organizationProfile: const OrganizationProfileModel(
            id: 3,
            organizationName: 'Acme Corp',
            organizationType: 'company',
            approvalStatus: 'approved',
          ),
        ),
      );
      await _pumpDetails(tester, repository: repository);

      await tester.tap(find.text('About the Organization'));
      await tester.pumpAndSettle();

      expect(find.text('COMPANY_PROFILE_3'), findsOneWidget);
    },
  );

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

  testWidgets(
    'the required-skill chip uses AppStatusType.info, never the '
    'low-dark-mode-contrast primary type (Opportunity Type Clarity)',
    (tester) async {
      final repository = _FakeOpportunityRepository(
        getResult: _opportunity(
          opportunitySkills: const [
            OpportunitySkillModel(
              id: 1,
              isRequired: true,
              skill: SkillModel(id: 1, name: 'Flutter'),
            ),
          ],
        ),
      );
      await _pumpDetails(tester, repository: repository);

      final chip = tester.widget<StatusChip>(
        find.widgetWithText(StatusChip, 'Flutter (Required)'),
      );
      expect(chip.type, AppStatusType.info);
    },
  );

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

  testWidgets(
    'No save/edit/delete/applicant/interview/quiz UI appears anywhere',
    (tester) async {
      final repository = _FakeOpportunityRepository(getResult: _opportunity());
      await _pumpDetails(tester, repository: repository);

      expect(find.textContaining('Save'), findsNothing);
      expect(find.byIcon(Icons.edit_outlined), findsNothing);
      expect(find.byIcon(Icons.delete_outline), findsNothing);
      expect(find.textContaining('Applicant'), findsNothing);
      expect(find.textContaining('Interview'), findsNothing);
      expect(find.textContaining('Quiz'), findsNothing);
    },
  );

  testWidgets('Apply Now renders when the student has not applied yet', (
    tester,
  ) async {
    final repository = _FakeOpportunityRepository(
      getResult: _opportunity(id: 1),
    );
    await _pumpDetails(tester, repository: repository, opportunityId: 1);

    expect(find.text('Apply Now'), findsOneWidget);
    expect(find.text('Already Applied'), findsNothing);
  });

  testWidgets(
    'Already Applied renders instead of Apply Now when hasAppliedTo is true',
    (tester) async {
      final repository = _FakeOpportunityRepository(
        getResult: _opportunity(id: 1),
      );
      await _pumpDetails(
        tester,
        repository: repository,
        opportunityId: 1,
        applicationRepository: _FakeApplicationRepository(
          listResult: [_application(opportunityId: 1)],
        ),
      );

      expect(find.text('Already Applied'), findsOneWidget);
      expect(find.text('Apply Now'), findsNothing);
    },
  );

  testWidgets('Tapping Apply Now opens the apply bottom sheet', (tester) async {
    final repository = _FakeOpportunityRepository(
      getResult: _opportunity(id: 1, title: 'Software Engineer'),
    );
    await _pumpDetails(
      tester,
      repository: repository,
      opportunityId: 1,
      cvRepository: _FakeCvRepository(
        listResult: [
          const CvModel(
            id: 1,
            studentId: 1,
            title: 'My CV',
            filePath: 'cvs/my-cv.pdf',
            version: 1,
            isDefault: true,
            createdByAi: false,
          ),
        ],
      ),
    );

    await tester.tap(find.text('Apply Now'));
    await tester.pumpAndSettle();

    expect(find.text('Apply to Software Engineer'), findsOneWidget);
    expect(find.text('Submit Application'), findsOneWidget);
  });

  testWidgets(
    'Full apply flow: Apply Now -> select CV -> submit -> sheet closes -> '
    'this same screen immediately shows Already Applied, no restart',
    (tester) async {
      const cv = CvModel(
        id: 1,
        studentId: 1,
        title: 'My CV',
        filePath: 'cvs/my-cv.pdf',
        version: 1,
        isDefault: true,
        createdByAi: false,
      );
      final repository = _FakeOpportunityRepository(
        getResult: _opportunity(id: 1, title: 'Software Engineer'),
      );
      final applicationRepository = _FakeApplicationRepository(
        applyResult: ApplicationModel(
          id: 99,
          studentId: 1,
          opportunityId: 1,
          cvId: 1,
          status: 'pending',
          opportunity: _opportunity(id: 1, title: 'Software Engineer'),
          cv: cv,
        ),
      );

      await _pumpDetails(
        tester,
        repository: repository,
        opportunityId: 1,
        cvRepository: _FakeCvRepository(listResult: [cv]),
        applicationRepository: applicationRepository,
      );

      // Starting state: not yet applied.
      expect(find.text('Apply Now'), findsOneWidget);
      expect(find.text('Already Applied'), findsNothing);

      // Tap Apply.
      await tester.tap(find.text('Apply Now'));
      await tester.pumpAndSettle();
      expect(find.text('Submit Application'), findsOneWidget);

      // The default (only) CV is already pre-selected — submit.
      await tester.tap(find.text('Submit Application'));
      await tester.pumpAndSettle();

      // The sheet closed and a success snackbar appeared.
      expect(find.text('Submit Application'), findsNothing);
      expect(find.text('Application submitted successfully'), findsOneWidget);

      // The very same StudentOpportunityDetailsScreen instance — never
      // rebuilt/remounted/restarted — now shows Already Applied instead
      // of Apply Now.
      expect(find.text('Already Applied'), findsOneWidget);
      expect(find.text('Apply Now'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'On a wide desktop viewport, the side panel keeps Apply reachable '
    'without a bottom bar, and no overflow occurs',
    (tester) async {
      final repository = _FakeOpportunityRepository(
        getResult: _opportunity(
          id: 1,
          organizationProfile: const OrganizationProfileModel(
            id: 3,
            organizationName: 'Acme Corp',
            organizationType: 'company',
            approvalStatus: 'approved',
          ),
        ),
      );
      await _pumpDetails(
        tester,
        repository: repository,
        opportunityId: 1,
        size: const Size(1280, 900),
      );

      expect(find.text('Apply Now'), findsOneWidget);
      expect(find.byType(BottomNavigationBar), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'A near deadline shows a closing-soon warning badge',
    (tester) async {
      final repository = _FakeOpportunityRepository(
        getResult: OpportunityModel(
          id: 1,
          title: 'Software Engineer',
          description: 'A great opportunity.',
          opportunityType: 'job',
          employmentType: 'full_time',
          workMode: 'remote',
          experienceLevel: 'junior',
          positionsAvailable: 2,
          status: 'open',
          applicationDeadline: DateTime.now().add(const Duration(days: 2)),
        ),
      );
      await _pumpDetails(tester, repository: repository, opportunityId: 1);

      expect(find.textContaining('closing soon'), findsOneWidget);
    },
  );

  testWidgets(
    'A far-off deadline shows a plain apply-by date, not a warning',
    (tester) async {
      final repository = _FakeOpportunityRepository(
        getResult: OpportunityModel(
          id: 1,
          title: 'Software Engineer',
          description: 'A great opportunity.',
          opportunityType: 'job',
          employmentType: 'full_time',
          workMode: 'remote',
          experienceLevel: 'junior',
          positionsAvailable: 2,
          status: 'open',
          applicationDeadline: DateTime.now().add(const Duration(days: 30)),
        ),
      );
      await _pumpDetails(tester, repository: repository, opportunityId: 1);

      expect(find.textContaining('closing soon'), findsNothing);
      expect(find.textContaining('Apply by'), findsOneWidget);
    },
  );

  testWidgets('No deadline badge renders when none is set', (tester) async {
    final repository = _FakeOpportunityRepository(getResult: _opportunity());
    await _pumpDetails(tester, repository: repository);

    expect(find.textContaining('Apply by'), findsNothing);
    expect(find.textContaining('deadline'), findsNothing);
  });

  testWidgets(
    'The theme toggle is reachable and switches the resolved theme',
    (tester) async {
      final repository = _FakeOpportunityRepository(getResult: _opportunity());
      await _pumpDetails(tester, repository: repository);

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
    },
  );

  testWidgets(
    'Reduced motion renders content immediately, without waiting through '
    'the staged entrance',
    (tester) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);

      final repository = _FakeOpportunityRepository(
        getResult: _opportunity(title: 'Software Engineer'),
      );
      await _pumpDetails(tester, repository: repository);

      expect(find.text('Software Engineer'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Does not overflow at a narrow 320x720 viewport', (
    tester,
  ) async {
    final repository = _FakeOpportunityRepository(
      getResult: _opportunity(
        opportunitySkills: const [
          OpportunitySkillModel(
            id: 1,
            isRequired: true,
            skill: SkillModel(id: 1, name: 'Flutter'),
          ),
        ],
        organizationProfile: const OrganizationProfileModel(
          id: 3,
          organizationName: 'Acme Corp',
          organizationType: 'company',
          approvalStatus: 'approved',
        ),
      ),
    );
    await _pumpDetails(
      tester,
      repository: repository,
      size: const Size(320, 720),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('Apply Now'), findsOneWidget);
  });

  testWidgets('The loading skeleton renders before details arrive', (
    tester,
  ) async {
    final repository = _FakeOpportunityRepository(
      getResult: _opportunity(),
      getDelay: const Duration(milliseconds: 200),
    );
    tester.view.physicalSize = const Size(420, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final authProvider = AuthProvider(authRepository: _FakeAuthRepository());
    final provider = StudentOpportunitiesProvider(
      repository: repository,
      authProvider: authProvider,
    );
    final cvProvider = StudentCvProvider(
      repository: _FakeCvRepository(),
      studentSkillRepository: StudentSkillRepository(
        apiClient: ApiClient(tokenStorageService: TokenStorageService()),
      ),
      authProvider: authProvider,
    );
    final applicationsProvider = StudentApplicationsProvider(
      repository: _FakeApplicationRepository(),
      authProvider: authProvider,
    );
    final studentProfileProvider =
        StudentProfileProvider(
            repository: _FakeStudentProfileRepository(),
            authProvider: authProvider,
          )
          ..profile = const StudentProfileModel(
            id: 1,
            university: 'State University',
            major: 'Computer Science',
            graduationYear: 2027,
          );

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<StudentOpportunitiesProvider>.value(
            value: provider,
          ),
          ChangeNotifierProvider<StudentCvProvider>.value(value: cvProvider),
          ChangeNotifierProvider<StudentApplicationsProvider>.value(
            value: applicationsProvider,
          ),
          ChangeNotifierProvider<StudentProfileProvider>.value(
            value: studentProfileProvider,
          ),
          ChangeNotifierProvider<ThemeProvider>.value(value: ThemeProvider()),
        ],
        child: MaterialApp(
          theme: AppTheme.lightTheme,
          home: const StudentOpportunityDetailsScreen(opportunityId: 1),
        ),
      ),
    );

    // Before the post-frame callback's load even resolves, the skeleton
    // (not a crash, not the real content) is what's on screen.
    await tester.pump();
    await tester.pump();

    expect(find.byType(AppSkeleton), findsWidgets);
    expect(find.text('Software Engineer'), findsNothing);
    expect(tester.takeException(), isNull);

    await tester.pumpAndSettle();
  });

  testWidgets(
    'Eligible Majors renders as chips, and an eligible student sees a '
    'positive eligibility confirmation',
    (tester) async {
      final repository = _FakeOpportunityRepository(
        getResult: OpportunityModel(
          id: 1,
          title: 'Software Engineer',
          description: 'A great opportunity.',
          opportunityType: 'job',
          employmentType: 'full_time',
          workMode: 'remote',
          experienceLevel: 'junior',
          positionsAvailable: 2,
          status: 'open',
          eligibleMajors: const ['Computer Science', 'Computer Engineering'],
        ),
      );
      await _pumpDetails(
        tester,
        repository: repository,
        studentMajor: 'Computer Science',
      );

      expect(find.text('Eligible Majors'), findsOneWidget);
      expect(find.text('Computer Science'), findsOneWidget);
      expect(find.text('Computer Engineering'), findsOneWidget);
      expect(
        find.text('Your major is eligible for this opportunity.'),
        findsOneWidget,
      );
      expect(find.text('Apply Now'), findsOneWidget);
      // With a real restriction in place, the fact-tile "All majors
      // welcome" line must never also appear -- that's exclusively for
      // the unrestricted case, never shown alongside real chips.
      expect(find.text('All majors welcome'), findsNothing);
    },
  );

  testWidgets(
    'A student whose major is not eligible sees Apply blocked with an '
    'explanation, not a silent failure later',
    (tester) async {
      final repository = _FakeOpportunityRepository(
        getResult: OpportunityModel(
          id: 1,
          title: 'Software Engineer',
          description: 'A great opportunity.',
          opportunityType: 'job',
          employmentType: 'full_time',
          workMode: 'remote',
          experienceLevel: 'junior',
          positionsAvailable: 2,
          status: 'open',
          eligibleMajors: const ['Computer Science'],
        ),
      );
      await _pumpDetails(
        tester,
        repository: repository,
        studentMajor: 'Fine Arts',
      );

      expect(find.text('Not Eligible'), findsOneWidget);
      expect(find.text('Apply Now'), findsNothing);
      expect(
        find.text('Your major is not eligible for this opportunity.'),
        findsOneWidget,
      );

      final button = tester.widget<SecondaryButton>(
        find.widgetWithText(SecondaryButton, 'Not Eligible'),
      );
      expect(button.onPressed, isNull);
    },
  );

  testWidgets(
    'An unrestricted opportunity shows a truthful "All majors welcome" '
    'fact, not a chip section or an eligibility confirmation line',
    (tester) async {
      final repository = _FakeOpportunityRepository(getResult: _opportunity());
      await _pumpDetails(tester, repository: repository);

      // Exactly one render -- the fact-tile row, never the prominent
      // chip-card section (which only ever renders for a real, explicit
      // restriction).
      expect(find.text('Eligible Majors'), findsOneWidget);
      expect(find.text('All majors welcome'), findsOneWidget);
      expect(
        find.text('Your major is eligible for this opportunity.'),
        findsNothing,
      );
      expect(find.text('Apply Now'), findsOneWidget);
    },
  );

  testWidgets(
    'no eligible majors configured never restricts Apply, and Field of '
    'Study is never displayed at all -- Opportunity Academic Matching '
    'Cleanup',
    (tester) async {
      final repository = _FakeOpportunityRepository(
        getResult: OpportunityModel(
          id: 1,
          title: 'Junior Mobile App Developer Intern',
          description: 'A great opportunity.',
          opportunityType: 'job',
          employmentType: 'full_time',
          workMode: 'remote',
          experienceLevel: 'junior',
          positionsAvailable: 2,
          status: 'open',
          eligibleMajors: const [],
        ),
      );
      await _pumpDetails(
        tester,
        repository: repository,
        studentMajor: 'Fine Arts',
      );

      // Truthfully says "All majors welcome" -- no explicit restriction.
      expect(find.text('Eligible Majors'), findsOneWidget);
      expect(find.text('All majors welcome'), findsOneWidget);
      // Field of Study (legacy, deprecated) is never shown anywhere.
      expect(find.text('Field of Study'), findsNothing);
      // The student must not be blocked.
      expect(find.text('Not Eligible'), findsNothing);
      expect(
        find.text('Your major is not eligible for this opportunity.'),
        findsNothing,
      );
      expect(find.text('Apply Now'), findsOneWidget);
    },
  );

  testWidgets(
    'A closed opportunity blocks Apply with an explanation',
    (tester) async {
      final repository = _FakeOpportunityRepository(
        getResult: OpportunityModel(
          id: 1,
          title: 'Software Engineer',
          description: 'A great opportunity.',
          opportunityType: 'job',
          employmentType: 'full_time',
          workMode: 'remote',
          experienceLevel: 'junior',
          positionsAvailable: 2,
          status: 'closed',
        ),
      );
      await _pumpDetails(tester, repository: repository);

      expect(find.text('Opportunity Closed'), findsOneWidget);
      expect(find.text('Apply Now'), findsNothing);
      expect(
        find.text('This opportunity is no longer accepting applications.'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'A passed deadline blocks Apply with an explanation, distinct from a '
    'closed opportunity',
    (tester) async {
      final repository = _FakeOpportunityRepository(
        getResult: OpportunityModel(
          id: 1,
          title: 'Software Engineer',
          description: 'A great opportunity.',
          opportunityType: 'job',
          employmentType: 'full_time',
          workMode: 'remote',
          experienceLevel: 'junior',
          positionsAvailable: 2,
          status: 'open',
          applicationDeadline: DateTime.now().subtract(
            const Duration(days: 3),
          ),
        ),
      );
      await _pumpDetails(tester, repository: repository);

      expect(find.text('Deadline Passed'), findsOneWidget);
      expect(find.text('Apply Now'), findsNothing);
      expect(
        find.text('The application deadline has passed.'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'Applied always shows Already Applied, even for an opportunity that '
    'would otherwise be blocked (already succeeded once, not re-litigated)',
    (tester) async {
      final repository = _FakeOpportunityRepository(
        getResult: OpportunityModel(
          id: 1,
          title: 'Software Engineer',
          description: 'A great opportunity.',
          opportunityType: 'job',
          employmentType: 'full_time',
          workMode: 'remote',
          experienceLevel: 'junior',
          positionsAvailable: 2,
          status: 'closed',
        ),
      );
      await _pumpDetails(
        tester,
        repository: repository,
        applicationRepository: _FakeApplicationRepository(
          listResult: [_application(opportunityId: 1)],
        ),
      );

      expect(find.text('Already Applied'), findsOneWidget);
      expect(find.text('Opportunity Closed'), findsNothing);
    },
  );

  testWidgets(
    'Back to Discover pops back to the opportunities list, exactly like '
    'the browser/system back action would',
    (tester) async {
      tester.view.physicalSize = const Size(420, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final authProvider = AuthProvider(authRepository: _FakeAuthRepository());
      final repository = _FakeOpportunityRepository(getResult: _opportunity());
      final provider = StudentOpportunitiesProvider(
        repository: repository,
        authProvider: authProvider,
      );
      final cvProvider = StudentCvProvider(
        repository: _FakeCvRepository(),
        studentSkillRepository: StudentSkillRepository(
          apiClient: ApiClient(tokenStorageService: TokenStorageService()),
        ),
        authProvider: authProvider,
      );
      final applicationsProvider = StudentApplicationsProvider(
        repository: _FakeApplicationRepository(),
        authProvider: authProvider,
      );
      final studentProfileProvider =
          StudentProfileProvider(
              repository: _FakeStudentProfileRepository(),
              authProvider: authProvider,
            )
            ..profile = const StudentProfileModel(
              id: 1,
              university: 'State University',
              major: 'Computer Science',
              graduationYear: 2027,
            );

      // Starts on the list (matching a real user's actual navigation
      // history), then pushes to Details -- unlike `_pumpDetails`'s router
      // (which starts *at* the details URL directly, modeling a fresh
      // direct visit/refresh with no history to pop), this one has a real
      // back stack for "Back to Discover" to pop.
      final router = GoRouter(
        initialLocation: AppRoutes.studentOpportunities,
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
        MultiProvider(
          providers: [
            ChangeNotifierProvider<StudentOpportunitiesProvider>.value(
              value: provider,
            ),
            ChangeNotifierProvider<StudentCvProvider>.value(value: cvProvider),
            ChangeNotifierProvider<StudentApplicationsProvider>.value(
              value: applicationsProvider,
            ),
            ChangeNotifierProvider<StudentProfileProvider>.value(
              value: studentProfileProvider,
            ),
            ChangeNotifierProvider<ThemeProvider>.value(value: ThemeProvider()),
          ],
          child: MaterialApp.router(
            theme: AppTheme.lightTheme,
            routerConfig: router,
          ),
        ),
      );
      await tester.pumpAndSettle();

      router.push(AppRoutes.studentOpportunityDetails(1));
      await tester.pumpAndSettle();

      expect(find.text('Back to Discover'), findsOneWidget);
      await tester.tap(find.text('Back to Discover'));
      await tester.pumpAndSettle();

      expect(find.text('LIST_PLACEHOLDER'), findsOneWidget);
    },
  );

  testWidgets(
    'On a 900-1199px viewport, the desktop side panel still applies with '
    'no overflow',
    (tester) async {
      final repository = _FakeOpportunityRepository(getResult: _opportunity());
      await _pumpDetails(
        tester,
        repository: repository,
        size: const Size(1024, 800),
      );

      expect(find.text('Apply Now'), findsOneWidget);
      expect(find.byType(BottomNavigationBar), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'On a 600-899px tablet viewport, Apply is an in-flow block, not a '
    'sticky bottom bar or a squeezed two-column layout',
    (tester) async {
      final repository = _FakeOpportunityRepository(
        getResult: _opportunity(
          organizationProfile: const OrganizationProfileModel(
            id: 3,
            organizationName: 'Acme Corp',
            organizationType: 'company',
            approvalStatus: 'approved',
          ),
        ),
      );
      await _pumpDetails(
        tester,
        repository: repository,
        size: const Size(720, 1000),
      );

      expect(find.text('Apply Now'), findsOneWidget);
      expect(find.byType(BottomNavigationBar), findsNothing);
      // Organization identity appears exactly once here (unlike desktop,
      // the tablet tier has no side panel to duplicate it into).
      expect(find.text('Acme Corp'), findsNWidgets(2));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'An organization with no logo field falls back to a designed initials '
    'avatar, not a broken image',
    (tester) async {
      final repository = _FakeOpportunityRepository(
        getResult: _opportunity(
          organizationProfile: const OrganizationProfileModel(
            id: 3,
            organizationName: 'Acme Corp',
            organizationType: 'company',
            approvalStatus: 'approved',
          ),
        ),
      );
      await _pumpDetails(tester, repository: repository);

      expect(find.text('AC'), findsWidgets);
      expect(find.byType(Image), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'An approved organization shows a real, backend-driven verified badge',
    (tester) async {
      final repository = _FakeOpportunityRepository(
        getResult: _opportunity(
          organizationProfile: const OrganizationProfileModel(
            id: 3,
            organizationName: 'Acme Corp',
            organizationType: 'company',
            approvalStatus: 'approved',
          ),
        ),
      );
      await _pumpDetails(tester, repository: repository);

      expect(find.byIcon(Icons.verified_rounded), findsOneWidget);
    },
  );

  testWidgets(
    'A pending (not yet approved) organization shows no verified badge',
    (tester) async {
      final repository = _FakeOpportunityRepository(
        getResult: _opportunity(
          organizationProfile: const OrganizationProfileModel(
            id: 3,
            organizationName: 'Acme Corp',
            organizationType: 'company',
            approvalStatus: 'pending',
          ),
        ),
      );
      await _pumpDetails(tester, repository: repository);

      expect(find.byIcon(Icons.verified_rounded), findsNothing);
    },
  );

  testWidgets(
    'The dominant Apply panel shows an arrow icon and the truthful '
    'supporting line, on desktop where Apply Now is unblocked',
    (tester) async {
      final repository = _FakeOpportunityRepository(getResult: _opportunity());
      await _pumpDetails(
        tester,
        repository: repository,
        size: const Size(1280, 900),
      );

      expect(find.byIcon(Icons.arrow_forward_rounded), findsOneWidget);
      expect(
        find.text('Your application goes directly to the organization.'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'The supporting line and arrow disappear once applied -- the panel '
    'shows a real confirmation instead',
    (tester) async {
      final repository = _FakeOpportunityRepository(getResult: _opportunity());
      await _pumpDetails(
        tester,
        repository: repository,
        size: const Size(1280, 900),
        applicationRepository: _FakeApplicationRepository(
          listResult: [_application(opportunityId: 1)],
        ),
      );

      expect(find.byIcon(Icons.arrow_forward_rounded), findsNothing);
      expect(
        find.text('Your application goes directly to the organization.'),
        findsNothing,
      );
      expect(find.text('Application Submitted'), findsOneWidget);
    },
  );
}
