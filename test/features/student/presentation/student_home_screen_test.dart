// Widget tests for the redesigned StudentHomeScreen (UI Phase 1.3 —
// visual polish, media-ready cards, navigation wording, and light/dark
// theme). Covers: the compact greeting (real name, page identity copy),
// the prominent search bar, nav tabs (Discover active, My
// Applications/Invitations navigate, real applications-count badge), the
// Profile avatar entry, the theme toggle (light<->dark, reflected in
// MaterialApp's resolved theme), real colored+media-ready opportunity
// cards (fields, deterministic/stable tone, cover band, organization
// initials fallback -- never a fake logo/photo, Apply vs. Applied state),
// loading/error/empty states, search debounce, the persistent sidebar
// filters on wide layouts and the Filters button/sheet on narrow ones,
// absence of personal/profile content and dead/fake reference features
// from the main body, and responsive behavior at narrow/tablet/wide
// viewports.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'package:opportunityhub_flutter/core/api/api_client.dart';
import 'package:opportunityhub_flutter/core/api/paginated_result.dart';
import 'package:opportunityhub_flutter/core/storage/theme_preference_storage.dart';
import 'package:opportunityhub_flutter/core/storage/token_storage_service.dart';
import 'package:opportunityhub_flutter/core/theme/app_colors.dart';
import 'package:opportunityhub_flutter/core/theme/app_theme.dart';
import 'package:opportunityhub_flutter/core/widgets/app_widgets.dart';
import 'package:opportunityhub_flutter/features/applications/data/application_repository.dart';
import 'package:opportunityhub_flutter/features/auth/data/auth_repository.dart';
import 'package:opportunityhub_flutter/features/cv/data/cv_repository.dart';
import 'package:opportunityhub_flutter/features/notifications/data/notification_repository.dart';
import 'package:opportunityhub_flutter/features/opportunities/data/opportunity_repository.dart';
import 'package:opportunityhub_flutter/features/skills/data/student_skill_repository.dart';
import 'package:opportunityhub_flutter/features/student/presentation/student_home_screen.dart';
import 'package:opportunityhub_flutter/models/application_model.dart';
import 'package:opportunityhub_flutter/models/cv_model.dart';
import 'package:opportunityhub_flutter/models/notification_model.dart';
import 'package:opportunityhub_flutter/models/opportunity_model.dart';
import 'package:opportunityhub_flutter/models/opportunity_skill_model.dart';
import 'package:opportunityhub_flutter/models/organization_profile_model.dart';
import 'package:opportunityhub_flutter/models/skill_model.dart';
import 'package:opportunityhub_flutter/models/student_skill_model.dart';
import 'package:opportunityhub_flutter/models/user_model.dart';
import 'package:opportunityhub_flutter/providers/auth_provider.dart';
import 'package:opportunityhub_flutter/providers/notification_provider.dart';
import 'package:opportunityhub_flutter/providers/student_applications_provider.dart';
import 'package:opportunityhub_flutter/providers/student_cv_provider.dart';
import 'package:opportunityhub_flutter/providers/student_opportunities_provider.dart';
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

class _FakeNotificationRepository extends NotificationRepository {
  _FakeNotificationRepository()
    : super(apiClient: ApiClient(tokenStorageService: TokenStorageService()));

  @override
  Future<List<NotificationModel>> getNotifications() async => [];
}

class _FakeApplicationRepository extends ApplicationRepository {
  _FakeApplicationRepository({this.listResult = const []})
    : super(apiClient: ApiClient(tokenStorageService: TokenStorageService()));

  List<ApplicationModel> listResult;

  @override
  Future<List<ApplicationModel>> getStudentApplications() async => listResult;
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
  }) : super(apiClient: ApiClient(tokenStorageService: TokenStorageService()));

  PaginatedResult<OpportunityModel> listResult;
  ApiException? listError;
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
    if (listError != null) throw listError!;
    return listResult;
  }
}

class _FakeCvRepository extends CvRepository {
  _FakeCvRepository({this.listResult = const []})
    : super(apiClient: ApiClient(tokenStorageService: TokenStorageService()));

  List<CvModel> listResult;

  @override
  Future<List<CvModel>> getStudentCvs() async => listResult;
}

class _FakeStudentSkillRepository extends StudentSkillRepository {
  _FakeStudentSkillRepository()
    : super(apiClient: ApiClient(tokenStorageService: TokenStorageService()));

  @override
  Future<List<StudentSkillModel>> getStudentSkills() async => [];
}

class _FakeThemePreferenceStorage extends ThemePreferenceStorage {
  ThemeMode? saved;

  @override
  Future<void> saveThemeMode(ThemeMode mode) async {
    saved = mode;
  }

  @override
  Future<ThemeMode> readThemeMode() async => saved ?? ThemeMode.system;
}

ApplicationModel _application({int id = 1, int opportunityId = 5, String status = 'pending'}) {
  return ApplicationModel(
    id: id,
    studentId: 1,
    opportunityId: opportunityId,
    cvId: 2,
    status: status,
    cv: const CvModel(
      id: 2,
      studentId: 1,
      title: 'Main CV',
      filePath: 'uploads/cv.pdf',
      version: 1,
      isDefault: true,
      createdByAi: false,
    ),
  );
}

OpportunityModel _opportunity({
  int id = 1,
  String title = 'Backend Developer',
  String description = 'A great role building real things.',
  String? location = 'Amman, Jordan',
  DateTime? applicationDeadline,
  List<String> eligibleMajors = const [],
  List<OpportunitySkillModel> opportunitySkills = const [],
  OrganizationProfileModel? organizationProfile,
}) {
  return OpportunityModel(
    id: id,
    title: title,
    description: description,
    opportunityType: 'internship',
    employmentType: 'full_time',
    workMode: 'remote',
    experienceLevel: 'junior',
    positionsAvailable: 1,
    status: 'open',
    location: location,
    applicationDeadline: applicationDeadline,
    eligibleMajors: eligibleMajors,
    opportunitySkills: opportunitySkills,
    organizationProfile:
        organizationProfile ??
        const OrganizationProfileModel(
          id: 1,
          organizationName: 'Acme Corp',
          organizationType: 'company',
          approvalStatus: 'approved',
        ),
  );
}

Future<
  (
    AuthProvider,
    StudentOpportunitiesProvider,
    StudentApplicationsProvider,
    ThemeProvider,
  )
>
_pumpScreen(
  WidgetTester tester, {
  _FakeNotificationRepository? notificationRepository,
  _FakeApplicationRepository? applicationRepository,
  _FakeOpportunityRepository? opportunityRepository,
  _FakeCvRepository? cvRepository,
  ThemeProvider? themeProvider,
  Size size = const Size(400, 900),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(() => AppColors.updateBrightness(Brightness.light));

  final authProvider = AuthProvider(authRepository: _FakeAuthRepository())
    ..user = const UserModel(
      id: 1,
      name: 'Sam Student',
      email: 'sam@example.com',
      role: 'student',
      status: 'active',
      emailVerified: true,
    );
  final notificationProvider = NotificationProvider(
    repository: notificationRepository ?? _FakeNotificationRepository(),
    authProvider: authProvider,
  );
  final applicationsProvider = StudentApplicationsProvider(
    repository: applicationRepository ?? _FakeApplicationRepository(),
    authProvider: authProvider,
  );
  final opportunitiesProvider = StudentOpportunitiesProvider(
    repository: opportunityRepository ?? _FakeOpportunityRepository(),
    authProvider: authProvider,
  );
  final cvProvider = StudentCvProvider(
    repository: cvRepository ?? _FakeCvRepository(),
    studentSkillRepository: _FakeStudentSkillRepository(),
    authProvider: authProvider,
  );
  final resolvedThemeProvider = themeProvider ?? ThemeProvider(storage: _FakeThemePreferenceStorage());
  if (!resolvedThemeProvider.isInitialized) {
    await resolvedThemeProvider.initialize();
  }

  final router = GoRouter(
    initialLocation: AppRoutes.studentHome,
    routes: [
      GoRoute(
        path: AppRoutes.studentHome,
        builder: (_, _) => const StudentHomeScreen(),
      ),
      GoRoute(
        path: AppRoutes.notifications,
        builder: (_, _) => const Scaffold(body: Text('NOTIFICATIONS_SCREEN')),
      ),
      GoRoute(
        path: '${AppRoutes.studentOpportunities}/:id',
        builder: (_, state) => Scaffold(
          body: Text('DETAILS_SCREEN_${state.pathParameters['id']}'),
        ),
      ),
      GoRoute(
        path: AppRoutes.studentCvs,
        builder: (_, _) => const Scaffold(body: Text('CVS_SCREEN')),
      ),
      GoRoute(
        path: AppRoutes.studentApplications,
        builder: (_, _) => const Scaffold(body: Text('APPLICATIONS_SCREEN')),
      ),
      GoRoute(
        path: AppRoutes.studentInvitations,
        builder: (_, _) => const Scaffold(body: Text('INVITATIONS_SCREEN')),
      ),
      GoRoute(
        path: AppRoutes.studentProfile,
        builder: (_, _) => const Scaffold(body: Text('PROFILE_SCREEN')),
      ),
    ],
  );

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthProvider>.value(value: authProvider),
        ChangeNotifierProvider<ThemeProvider>.value(value: resolvedThemeProvider),
        ChangeNotifierProvider<NotificationProvider>.value(
          value: notificationProvider,
        ),
        ChangeNotifierProvider<StudentApplicationsProvider>.value(
          value: applicationsProvider,
        ),
        ChangeNotifierProvider<StudentOpportunitiesProvider>.value(
          value: opportunitiesProvider,
        ),
        ChangeNotifierProvider<StudentCvProvider>.value(value: cvProvider),
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

  return (authProvider, opportunitiesProvider, applicationsProvider, resolvedThemeProvider);
}

void main() {
  group('Compact greeting and page identity', () {
    testWidgets('greets the real authenticated student by first name', (
      tester,
    ) async {
      await _pumpScreen(tester, opportunityRepository: _FakeOpportunityRepository());

      expect(find.textContaining('Sam'), findsOneWidget);
    });

    testWidgets('communicates discovering multiple opportunity types, not just "Jobs"', (
      tester,
    ) async {
      await _pumpScreen(tester, opportunityRepository: _FakeOpportunityRepository());

      expect(find.textContaining('internships'), findsOneWidget);
      expect(find.textContaining('scholarships'), findsOneWidget);
    });

    testWidgets('the discovery section uses a stronger page identity than "Explore Opportunities"', (
      tester,
    ) async {
      await _pumpScreen(tester, opportunityRepository: _FakeOpportunityRepository());

      expect(find.text('Discover Opportunities'), findsOneWidget);
      expect(find.text('Explore Opportunities'), findsNothing);
    });

    testWidgets('renders a search field', (tester) async {
      await _pumpScreen(tester, opportunityRepository: _FakeOpportunityRepository());

      expect(find.byType(TextFormField), findsOneWidget);
    });
  });

  group('Nav tabs', () {
    testWidgets('Discover is shown alongside My Applications and Invitations', (
      tester,
    ) async {
      await _pumpScreen(tester, opportunityRepository: _FakeOpportunityRepository());

      expect(find.text('Discover'), findsOneWidget);
      expect(find.text('My Applications'), findsOneWidget);
      expect(find.text('Invitations'), findsOneWidget);
    });

    testWidgets('tapping My Applications navigates to the real Applications route', (
      tester,
    ) async {
      await _pumpScreen(tester, opportunityRepository: _FakeOpportunityRepository());

      await tester.ensureVisible(find.text('My Applications'));
      await tester.tap(find.text('My Applications'));
      await tester.pumpAndSettle();

      expect(find.text('APPLICATIONS_SCREEN'), findsOneWidget);
    });

    testWidgets('tapping Invitations navigates to the real Invitations route', (
      tester,
    ) async {
      await _pumpScreen(tester, opportunityRepository: _FakeOpportunityRepository());

      await tester.ensureVisible(find.text('Invitations'));
      await tester.tap(find.text('Invitations'));
      await tester.pumpAndSettle();

      expect(find.text('INVITATIONS_SCREEN'), findsOneWidget);
    });

    testWidgets('shows a real applications count badge when applications exist', (
      tester,
    ) async {
      await _pumpScreen(
        tester,
        opportunityRepository: _FakeOpportunityRepository(),
        applicationRepository: _FakeApplicationRepository(
          listResult: [_application(id: 1), _application(id: 2)],
        ),
      );

      expect(find.text('2'), findsOneWidget);
    });
  });

  group('Profile entry', () {
    testWidgets('tapping the avatar navigates to the real Profile route', (
      tester,
    ) async {
      await _pumpScreen(tester, opportunityRepository: _FakeOpportunityRepository());

      await tester.tap(find.byType(AppAvatar));
      await tester.pumpAndSettle();

      expect(find.text('PROFILE_SCREEN'), findsOneWidget);
    });

    testWidgets(
      'no popup menu, no giant Logout button, no profile-management cards in the main content',
      (tester) async {
        await _pumpScreen(tester, opportunityRepository: _FakeOpportunityRepository());

        expect(find.text('My CVs'), findsNothing);
        expect(find.text('My Skills'), findsNothing);
        expect(find.text('Education Verification'), findsNothing);
        expect(find.text('Logout'), findsNothing);
      },
    );
  });

  group('Theme toggle', () {
    testWidgets('is reachable from Explore and switches the resolved theme', (
      tester,
    ) async {
      final (_, _, _, themeProvider) = await _pumpScreen(
        tester,
        opportunityRepository: _FakeOpportunityRepository(),
      );

      expect(find.byType(ThemeToggleButton), findsOneWidget);

      final wasDark = themeProvider.isDark;
      await tester.tap(find.byType(ThemeToggleButton));
      await tester.pumpAndSettle();

      expect(themeProvider.isDark, !wasDark);
      final materialApp = tester.widget<MaterialApp>(find.byType(MaterialApp));
      expect(
        Theme.of(tester.element(find.byType(Scaffold).first)).brightness,
        wasDark ? Brightness.light : Brightness.dark,
      );
      expect(materialApp.themeMode, wasDark ? ThemeMode.light : ThemeMode.dark);
    });

    testWidgets('dark mode renders without error and keeps text readable', (
      tester,
    ) async {
      final darkThemeProvider = ThemeProvider(storage: _FakeThemePreferenceStorage());
      await darkThemeProvider.initialize();
      await darkThemeProvider.toggle();
      expect(darkThemeProvider.isDark, isTrue);

      await _pumpScreen(
        tester,
        opportunityRepository: _FakeOpportunityRepository(
          listResult: PaginatedResult(
            items: [_opportunity()],
            currentPage: 1,
            lastPage: 1,
            total: 1,
          ),
        ),
        themeProvider: darkThemeProvider,
      );

      expect(tester.takeException(), isNull);
      expect(find.text('Backend Developer'), findsOneWidget);
    });
  });

  group('Opportunity cards', () {
    testWidgets('render real fields: title, org, type/mode/location, deadline', (
      tester,
    ) async {
      final deadline = DateTime(2026, 12, 1);
      await _pumpScreen(
        tester,
        opportunityRepository: _FakeOpportunityRepository(
          listResult: PaginatedResult(
            items: [
              _opportunity(
                id: 1,
                title: 'Backend Developer',
                location: 'Amman, Jordan',
                applicationDeadline: deadline,
              ),
            ],
            currentPage: 1,
            lastPage: 1,
            total: 1,
          ),
        ),
      );

      expect(find.text('Backend Developer'), findsOneWidget);
      expect(find.text('Acme Corp'), findsOneWidget);
      expect(find.text('Internship'), findsOneWidget);
      expect(find.text('Remote'), findsOneWidget);
      expect(find.text('Amman, Jordan'), findsOneWidget);
      expect(find.textContaining('Apply by'), findsOneWidget);
    });

    testWidgets('render a media-ready cover band with an organization initials fallback, never a fake logo', (
      tester,
    ) async {
      await _pumpScreen(
        tester,
        opportunityRepository: _FakeOpportunityRepository(
          listResult: PaginatedResult(
            items: [
              _opportunity(
                organizationProfile: const OrganizationProfileModel(
                  id: 9,
                  organizationName: 'Nova Labs',
                  organizationType: 'company',
                  approvalStatus: 'approved',
                ),
              ),
            ],
            currentPage: 1,
            lastPage: 1,
            total: 1,
          ),
        ),
      );

      // The avatar fallback renders the organization's real initials ("NL")
      // -- never a fabricated photo/logo, and no broken-image icon either.
      expect(find.byType(AppAvatar), findsWidgets);
      expect(find.text('NL'), findsOneWidget);
      expect(find.byIcon(Icons.broken_image), findsNothing);
    });

    testWidgets('have a deterministic/stable pastel tone across rebuilds', (
      tester,
    ) async {
      await _pumpScreen(
        tester,
        opportunityRepository: _FakeOpportunityRepository(
          listResult: PaginatedResult(
            items: [_opportunity(id: 7)],
            currentPage: 1,
            lastPage: 1,
            total: 1,
          ),
        ),
      );

      Color colorOf() {
        final card = tester.widget<AppCard>(find.byType(AppCard).first);
        return card.backgroundColor!;
      }

      final firstColor = colorOf();
      await tester.fling(find.byType(RefreshIndicator), const Offset(0, 300), 1000);
      await tester.pumpAndSettle();

      expect(colorOf(), firstColor);
    });

    testWidgets('show View Details and Apply when not yet applied', (
      tester,
    ) async {
      await _pumpScreen(
        tester,
        opportunityRepository: _FakeOpportunityRepository(
          listResult: PaginatedResult(
            items: [_opportunity(id: 1)],
            currentPage: 1,
            lastPage: 1,
            total: 1,
          ),
        ),
      );

      expect(find.text('View Details'), findsOneWidget);
      expect(find.text('Apply'), findsOneWidget);
      expect(find.text('Applied'), findsNothing);
    });

    testWidgets('show an Applied indicator instead of Apply when already applied', (
      tester,
    ) async {
      await _pumpScreen(
        tester,
        opportunityRepository: _FakeOpportunityRepository(
          listResult: PaginatedResult(
            items: [_opportunity(id: 5)],
            currentPage: 1,
            lastPage: 1,
            total: 1,
          ),
        ),
        applicationRepository: _FakeApplicationRepository(
          listResult: [_application(id: 1, opportunityId: 5)],
        ),
      );

      expect(find.text('Applied'), findsOneWidget);
      expect(find.text('Apply'), findsNothing);
    });

    testWidgets('tapping Apply opens the real ApplyBottomSheet flow', (
      tester,
    ) async {
      await _pumpScreen(
        tester,
        opportunityRepository: _FakeOpportunityRepository(
          listResult: PaginatedResult(
            items: [_opportunity(id: 1, title: 'Backend Developer')],
            currentPage: 1,
            lastPage: 1,
            total: 1,
          ),
        ),
        cvRepository: _FakeCvRepository(
          listResult: const [
            CvModel(
              id: 9,
              studentId: 1,
              title: 'My CV',
              filePath: 'uploads/cv.pdf',
              version: 1,
              isDefault: true,
              createdByAi: false,
            ),
          ],
        ),
      );

      await tester.tap(find.text('Apply'));
      await tester.pumpAndSettle();

      expect(find.text('Apply to Backend Developer'), findsOneWidget);
      expect(find.text('Submit Application'), findsOneWidget);
    });

    testWidgets('render real opportunity skill tags and eligible-majors summary when present', (
      tester,
    ) async {
      await _pumpScreen(
        tester,
        opportunityRepository: _FakeOpportunityRepository(
          listResult: PaginatedResult(
            items: [
              _opportunity(
                eligibleMajors: const ['Computer Science', 'Software Engineering'],
                opportunitySkills: const [
                  OpportunitySkillModel(
                    id: 1,
                    isRequired: true,
                    skill: SkillModel(id: 1, name: 'Flutter'),
                  ),
                ],
              ),
            ],
            currentPage: 1,
            lastPage: 1,
            total: 1,
          ),
        ),
      );

      expect(find.text('Flutter'), findsOneWidget);
      expect(
        find.text('Computer Science, Software Engineering'),
        findsOneWidget,
      );
    });

    testWidgets('no fabricated fields: no match %, no applicant count, no salary', (
      tester,
    ) async {
      await _pumpScreen(
        tester,
        opportunityRepository: _FakeOpportunityRepository(
          listResult: PaginatedResult(
            items: [_opportunity()],
            currentPage: 1,
            lastPage: 1,
            total: 1,
          ),
        ),
      );

      expect(find.textContaining('% match'), findsNothing);
      expect(find.textContaining('applicant'), findsNothing);
      expect(find.textContaining(r'$'), findsNothing);
      expect(find.textContaining('Recommended'), findsNothing);
    });

    testWidgets('no dead reference-only controls: no Save/heart, no three-dot menu', (
      tester,
    ) async {
      await _pumpScreen(
        tester,
        opportunityRepository: _FakeOpportunityRepository(
          listResult: PaginatedResult(
            items: [_opportunity()],
            currentPage: 1,
            lastPage: 1,
            total: 1,
          ),
        ),
      );

      expect(find.byIcon(Icons.favorite), findsNothing);
      expect(find.byIcon(Icons.favorite_border), findsNothing);
      expect(find.byIcon(Icons.more_vert), findsNothing);
    });

    testWidgets('tapping a card opens the real details route by ID', (
      tester,
    ) async {
      await _pumpScreen(
        tester,
        opportunityRepository: _FakeOpportunityRepository(
          listResult: PaginatedResult(
            items: [_opportunity(id: 42, title: 'Data Analyst')],
            currentPage: 1,
            lastPage: 1,
            total: 1,
          ),
        ),
      );

      await tester.tap(find.text('Data Analyst'));
      await tester.pumpAndSettle();

      expect(find.text('DETAILS_SCREEN_42'), findsOneWidget);
    });
  });

  group('Loading, error, and empty states', () {
    testWidgets('shows an error view with retry on failure', (tester) async {
      final repository = _FakeOpportunityRepository(
        listError: ApiException('Server error, please try again later.'),
      );
      final (_, provider, _, _) = await _pumpScreen(
        tester,
        opportunityRepository: repository,
      );

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

      expect(find.text('Backend Developer'), findsOneWidget);
    });

    testWidgets('shows an empty view when there are no opportunities', (
      tester,
    ) async {
      await _pumpScreen(tester, opportunityRepository: _FakeOpportunityRepository());

      expect(find.text('No Opportunities Found'), findsOneWidget);
      expect(find.text('Check back soon for new opportunities.'), findsOneWidget);
    });
  });

  group('Search', () {
    testWidgets('debounces then refetches with the typed keyword', (
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
      await _pumpScreen(tester, opportunityRepository: repository);
      final callsBeforeSearch = repository.callCount;

      await tester.enterText(find.byType(TextFormField), 'engineer');
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();

      expect(repository.callCount, greaterThan(callsBeforeSearch));
      expect(repository.lastKeyword, 'engineer');
    });
  });

  group('Filters — narrow layout (Filters button/sheet)', () {
    testWidgets('applying a filter refetches and shows a removable chip', (
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
      await _pumpScreen(tester, opportunityRepository: repository, size: const Size(400, 900));

      await tester.ensureVisible(find.byIcon(Icons.filter_alt_outlined));
      await tester.tap(find.byIcon(Icons.filter_alt_outlined), warnIfMissed: false);
      await tester.pumpAndSettle();

      final dropdown = find.widgetWithText(
        DropdownButtonFormField<String>,
        'Opportunity Type',
      );
      await tester.tap(dropdown);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Internship').last);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Apply Filters'));
      await tester.pumpAndSettle();

      expect(repository.lastOpportunityType, 'internship');
      expect(find.byIcon(Icons.filter_alt), findsOneWidget);
      expect(find.widgetWithText(InputChip, 'Internship'), findsOneWidget);
    });

    testWidgets('removing an active filter chip clears just that filter', (
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
      final (_, provider, _, _) = await _pumpScreen(
        tester,
        opportunityRepository: repository,
      );
      await provider.applyFilters(opportunityType: 'internship', location: 'Amman');
      await tester.pumpAndSettle();

      final chip = find.widgetWithText(InputChip, 'Internship');
      expect(chip, findsOneWidget);
      await tester.ensureVisible(chip);
      await tester.tap(find.descendant(of: chip, matching: find.byType(Icon)));
      await tester.pumpAndSettle();

      expect(provider.opportunityType, isNull);
      expect(provider.location, 'Amman');
    });
  });

  group('Filters — persistent sidebar on wide layouts', () {
    testWidgets('sidebar is visible with a Filters heading, Reset All available once active', (
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
      final (_, provider, _, _) = await _pumpScreen(
        tester,
        opportunityRepository: repository,
        size: const Size(1300, 900),
      );

      expect(find.text('Filters'), findsOneWidget);
      expect(find.byIcon(Icons.filter_alt_outlined), findsNothing);
      expect(find.text('Reset All'), findsNothing);

      await provider.applyFilters(opportunityType: 'internship');
      await tester.pumpAndSettle();

      expect(find.text('Reset All'), findsOneWidget);
    });

    testWidgets('selecting a chip in the sidebar applies that filter', (
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
      await _pumpScreen(
        tester,
        opportunityRepository: repository,
        size: const Size(1300, 900),
      );

      await tester.tap(find.widgetWithText(ChoiceChip, 'Internship'));
      await tester.pumpAndSettle();

      expect(repository.lastOpportunityType, 'internship');
    });

    testWidgets('Reset All clears every active filter', (tester) async {
      final repository = _FakeOpportunityRepository(
        listResult: PaginatedResult(
          items: [_opportunity()],
          currentPage: 1,
          lastPage: 1,
          total: 1,
        ),
      );
      final (_, provider, _, _) = await _pumpScreen(
        tester,
        opportunityRepository: repository,
        size: const Size(1300, 900),
      );
      await provider.applyFilters(opportunityType: 'internship', location: 'Amman');
      await tester.pumpAndSettle();

      await tester.tap(find.text('Reset All'));
      await tester.pumpAndSettle();

      expect(provider.hasActiveFilters, isFalse);
      expect(find.text('Reset All'), findsNothing);
    });
  });

  group('Responsive layout', () {
    for (final size in [
      Size(375, 800), // mobile
      Size(700, 900), // tablet
      Size(1000, 900), // desktop/tablet (sidebar)
      Size(1300, 900), // desktop wide (sidebar)
    ]) {
      testWidgets('renders without overflow at ${size.width.toInt()}px', (
        tester,
      ) async {
        await _pumpScreen(
          tester,
          opportunityRepository: _FakeOpportunityRepository(
            listResult: PaginatedResult(
              items: [
                _opportunity(id: 1, title: 'Backend Developer'),
                _opportunity(id: 2, title: 'Marketing Intern'),
                _opportunity(id: 3, title: 'Data Analyst'),
              ],
              currentPage: 1,
              lastPage: 1,
              total: 3,
            ),
          ),
          size: size,
        );

        expect(tester.takeException(), isNull);
        expect(find.text('Backend Developer'), findsOneWidget);
      });
    }

    testWidgets('sidebar is not shown below 900px, but theme toggle and Profile remain accessible', (
      tester,
    ) async {
      await _pumpScreen(
        tester,
        opportunityRepository: _FakeOpportunityRepository(),
        size: const Size(375, 800),
      );

      expect(find.byType(ChoiceChip), findsNothing);
      expect(find.byIcon(Icons.filter_alt_outlined), findsOneWidget);
      expect(find.byType(ThemeToggleButton), findsOneWidget);
      expect(find.byType(AppAvatar), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
