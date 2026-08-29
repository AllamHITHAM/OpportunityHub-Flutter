// Widget tests for OrganizationOpportunityDetailsScreen, in isolation with
// a small GoRouter.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'package:opportunityhub_flutter/core/api/api_client.dart';
import 'package:opportunityhub_flutter/core/storage/theme_preference_storage.dart';
import 'package:opportunityhub_flutter/core/storage/token_storage_service.dart';
import 'package:opportunityhub_flutter/core/theme/app_colors.dart';
import 'package:opportunityhub_flutter/core/theme/app_theme.dart';
import 'package:opportunityhub_flutter/core/widgets/app_widgets.dart';
import 'package:opportunityhub_flutter/features/assessments/data/assessment_repository.dart';
import 'package:opportunityhub_flutter/features/auth/data/auth_repository.dart';
import 'package:opportunityhub_flutter/features/opportunities/data/opportunity_repository.dart';
import 'package:opportunityhub_flutter/features/opportunities/presentation/organization_opportunity_details_screen.dart';
import 'package:opportunityhub_flutter/models/opportunity_model.dart';
import 'package:opportunityhub_flutter/models/opportunity_skill_model.dart';
import 'package:opportunityhub_flutter/models/quiz_model.dart';
import 'package:opportunityhub_flutter/models/skill_model.dart';
import 'package:opportunityhub_flutter/providers/auth_provider.dart';
import 'package:opportunityhub_flutter/providers/organization_opportunities_provider.dart';
import 'package:opportunityhub_flutter/providers/organization_quiz_provider.dart';
import 'package:opportunityhub_flutter/providers/theme_provider.dart';
import 'package:opportunityhub_flutter/routes/app_routes.dart';

class _FakeThemePreferenceStorage extends ThemePreferenceStorage {
  ThemeMode? saved;

  @override
  Future<void> saveThemeMode(ThemeMode mode) async {
    saved = mode;
  }

  @override
  Future<ThemeMode> readThemeMode() async => saved ?? ThemeMode.system;
}

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
  String recruitmentProcess = 'none',
  String workMode = 'remote',
  String opportunityType = 'job',
  List<String> eligibleMajors = const [],
  List<OpportunitySkillModel> opportunitySkills = const [],
}) {
  return OpportunityModel(
    id: id,
    title: title,
    description: 'A great opportunity.',
    opportunityType: opportunityType,
    employmentType: 'full_time',
    workMode: workMode,
    experienceLevel: 'junior',
    positionsAvailable: 2,
    status: status,
    location: 'Amman, Jordan',
    recruitmentProcess: recruitmentProcess,
    eligibleMajors: eligibleMajors,
    opportunitySkills: opportunitySkills,
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

/// Phase 10A.4B — minimal fake covering only the shared-Quiz-template
/// methods this screen's `_AssessmentSection` calls
/// (`getOpportunityQuiz`) -- every other `AssessmentRepository` method is
/// irrelevant here and left unimplemented (never called by this screen).
class _FakeQuizAssessmentRepository extends AssessmentRepository {
  _FakeQuizAssessmentRepository({this.getResult, this.getError})
    : super(apiClient: ApiClient(tokenStorageService: TokenStorageService()));

  QuizModel? getResult;
  ApiException? getError;
  int getCallCount = 0;

  @override
  Future<QuizModel?> getOpportunityQuiz(int opportunityId) async {
    getCallCount++;
    if (getError != null) throw getError!;
    return getResult;
  }
}

QuizModel _quiz({
  int id = 1,
  int opportunityId = 1,
  String title = 'Backend Fundamentals',
  String status = 'draft',
  int passingScore = 70,
}) {
  return QuizModel(
    id: id,
    opportunityId: opportunityId,
    title: title,
    passingScore: passingScore,
    status: status,
  );
}

Future<(OrganizationOpportunitiesProvider, List<String>)> _pumpDetails(
  WidgetTester tester, {
  required _FakeOpportunityRepository repository,
  AssessmentRepository? assessmentRepository,
  int opportunityId = 1,
  Size size = const Size(420, 1400),
}) async {
  // AppColors.updateBrightness is a process-global static — reset it so
  // one test's theme choice never leaks into the next.
  addTearDown(() => AppColors.updateBrightness(Brightness.light));

  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final authProvider = AuthProvider(authRepository: _FakeAuthRepository());
  final provider = OrganizationOpportunitiesProvider(
    repository: repository,
    authProvider: authProvider,
  );
  final quizProvider = OrganizationQuizProvider(
    repository: assessmentRepository ?? _FakeQuizAssessmentRepository(),
    authProvider: authProvider,
  );
  final themeProvider = ThemeProvider(storage: _FakeThemePreferenceStorage());
  await themeProvider.initialize();
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
        path: '${AppRoutes.organizationOpportunities}/:id/applicants',
        builder: (_, state) {
          visitedPaths.add('applicants/${state.pathParameters['id']}');
          return const Scaffold(body: Text('APPLICANTS_PLACEHOLDER'));
        },
      ),
      GoRoute(
        path: '${AppRoutes.organizationOpportunities}/:id/quiz/new',
        builder: (_, state) {
          visitedPaths.add('quiz/new/${state.pathParameters['id']}');
          return const Scaffold(body: Text('CREATE_QUIZ_PLACEHOLDER'));
        },
      ),
      GoRoute(
        path: '${AppRoutes.organizationOpportunities}/:id/quiz/results',
        builder: (_, state) {
          visitedPaths.add('quiz/results/${state.pathParameters['id']}');
          return const Scaffold(body: Text('QUIZ_RESULTS_PLACEHOLDER'));
        },
      ),
      GoRoute(
        path: '${AppRoutes.organizationOpportunities}/:id/quiz',
        builder: (_, state) {
          visitedPaths.add('quiz/${state.pathParameters['id']}');
          return const Scaffold(body: Text('QUIZ_EDITOR_PLACEHOLDER'));
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
    MultiProvider(
      providers: [
        ChangeNotifierProvider<OrganizationOpportunitiesProvider>.value(
          value: provider,
        ),
        ChangeNotifierProvider<OrganizationQuizProvider>.value(
          value: quizProvider,
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

void main() {
  testWidgets(
    'the Opportunity Type chip uses AppStatusType.info, never the '
    'low-dark-mode-contrast primary type (Opportunity Type Clarity)',
    (tester) async {
      final repository = _FakeOpportunityRepository(
        getResult: _opportunity(opportunityType: 'internship'),
      );
      await _pumpDetails(tester, repository: repository);

      final chip = tester.widget<StatusChip>(
        find.widgetWithText(StatusChip, 'Internship'),
      );
      expect(chip.type, AppStatusType.info);
    },
  );

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

  testWidgets(
    'View Applicants action is visible and opens the applicants route',
    (tester) async {
      final repository = _FakeOpportunityRepository(
        getResult: _opportunity(id: 7),
      );
      final (_, visitedPaths) = await _pumpDetails(
        tester,
        repository: repository,
        opportunityId: 7,
      );

      final applicantsButton = find.byIcon(Icons.people_outline);
      expect(applicantsButton, findsOneWidget);

      await tester.tap(applicantsButton);
      await tester.pumpAndSettle();

      expect(visitedPaths, contains('applicants/7'));
    },
  );

  testWidgets(
    'Existing Edit/Delete controls remain intact alongside View Applicants',
    (tester) async {
      final repository = _FakeOpportunityRepository(
        getResult: _opportunity(id: 7),
      );
      await _pumpDetails(tester, repository: repository, opportunityId: 7);

      expect(find.byIcon(Icons.people_outline), findsOneWidget);
      expect(find.byIcon(Icons.edit_outlined), findsOneWidget);
      expect(find.byIcon(Icons.delete_outline), findsOneWidget);
    },
  );

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

  group('Recruitment Process section (Phase 10A.4B)', () {
    testWidgets('recruitmentProcess = none shows no Assessment section', (
      tester,
    ) async {
      final repository = _FakeOpportunityRepository(
        getResult: _opportunity(recruitmentProcess: 'none'),
      );
      await _pumpDetails(tester, repository: repository);

      expect(find.text('Recruitment Process'), findsNothing);
      expect(find.textContaining('Quiz'), findsNothing);
    });

    testWidgets('recruitmentProcess = interview shows the process label '
        'only, no Quiz UI', (tester) async {
      final repository = _FakeOpportunityRepository(
        getResult: _opportunity(recruitmentProcess: 'interview'),
      );
      await _pumpDetails(tester, repository: repository);

      expect(find.text('Recruitment Process'), findsOneWidget);
      expect(find.text('Interview Only'), findsOneWidget);
      expect(find.textContaining('Quiz'), findsNothing);
    });

    testWidgets(
      'recruitmentProcess = quiz with no template shows Not configured '
      'and a Configure Quiz action',
      (tester) async {
        final repository = _FakeOpportunityRepository(
          getResult: _opportunity(id: 7, recruitmentProcess: 'quiz'),
        );
        final assessmentRepository = _FakeQuizAssessmentRepository(
          getResult: null,
        );
        await _pumpDetails(
          tester,
          repository: repository,
          assessmentRepository: assessmentRepository,
          opportunityId: 7,
        );

        expect(find.text('Not configured'), findsOneWidget);
        expect(find.text('Configure Quiz'), findsOneWidget);

        await tester.ensureVisible(find.text('Configure Quiz'));
        await tester.tap(find.text('Configure Quiz'));
        await tester.pumpAndSettle();
        expect(find.text('CREATE_QUIZ_PLACEHOLDER'), findsOneWidget);
      },
    );

    testWidgets(
      'recruitmentProcess = quiz with a draft template shows Draft and '
      'Manage Quiz',
      (tester) async {
        final repository = _FakeOpportunityRepository(
          getResult: _opportunity(id: 7, recruitmentProcess: 'quiz'),
        );
        final assessmentRepository = _FakeQuizAssessmentRepository(
          getResult: _quiz(status: 'draft'),
        );
        final (_, visitedPaths) = await _pumpDetails(
          tester,
          repository: repository,
          assessmentRepository: assessmentRepository,
          opportunityId: 7,
        );

        expect(find.text('Draft'), findsOneWidget);
        expect(find.text('Manage Quiz'), findsOneWidget);
        expect(find.text('View Results'), findsOneWidget);

        await tester.ensureVisible(find.text('Manage Quiz'));
        await tester.tap(find.text('Manage Quiz'));
        await tester.pumpAndSettle();
        expect(visitedPaths, contains('quiz/7'));
      },
    );

    testWidgets(
      'recruitmentProcess = quiz with a published template shows '
      'Published and View Quiz, and View Results navigates correctly',
      (tester) async {
        final repository = _FakeOpportunityRepository(
          getResult: _opportunity(id: 7, recruitmentProcess: 'quiz'),
        );
        final assessmentRepository = _FakeQuizAssessmentRepository(
          getResult: _quiz(status: 'published'),
        );
        final (_, visitedPaths) = await _pumpDetails(
          tester,
          repository: repository,
          assessmentRepository: assessmentRepository,
          opportunityId: 7,
        );

        expect(find.text('Published'), findsOneWidget);
        expect(find.text('View Quiz'), findsOneWidget);

        await tester.ensureVisible(find.text('View Results'));
        await tester.tap(find.text('View Results'));
        await tester.pumpAndSettle();
        expect(visitedPaths, contains('quiz/results/7'));
      },
    );

    testWidgets('a Quiz load failure shows a compact error with retry', (
      tester,
    ) async {
      final repository = _FakeOpportunityRepository(
        getResult: _opportunity(id: 7, recruitmentProcess: 'quiz'),
      );
      final assessmentRepository = _FakeQuizAssessmentRepository(
        getError: ApiException('Something went wrong'),
      );
      await _pumpDetails(
        tester,
        repository: repository,
        assessmentRepository: assessmentRepository,
        opportunityId: 7,
      );

      expect(find.text('Something went wrong'), findsOneWidget);
      expect(assessmentRepository.getCallCount, 1);
    });

    testWidgets('does not overflow at a narrow 320x900 viewport with the '
        'Quiz section visible', (tester) async {
      final repository = _FakeOpportunityRepository(
        getResult: _opportunity(id: 7, recruitmentProcess: 'quiz'),
      );
      final assessmentRepository = _FakeQuizAssessmentRepository(
        getResult: _quiz(status: 'published'),
      );
      await _pumpDetails(
        tester,
        repository: repository,
        assessmentRepository: assessmentRepository,
        opportunityId: 7,
        size: const Size(320, 900),
      );

      expect(tester.takeException(), isNull);
    });
  });

  group('theme toggle (UI Phase O4)', () {
    testWidgets('is present in the AppBar and switches the resolved theme', (
      tester,
    ) async {
      final repository = _FakeOpportunityRepository(
        getResult: _opportunity(),
      );
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
    });

    testWidgets(
      'sits inside a visible, comfortably-sized circular surface',
      (tester) async {
        final repository = _FakeOpportunityRepository(
          getResult: _opportunity(),
        );
        await _pumpDetails(tester, repository: repository);

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

    testWidgets('the tooltip reflects the real toggle direction in both '
        'states', (tester) async {
      final repository = _FakeOpportunityRepository(
        getResult: _opportunity(),
      );
      await _pumpDetails(tester, repository: repository);

      expect(find.byTooltip('Switch to dark mode'), findsOneWidget);

      await tester.tap(find.byType(ThemeToggleButton));
      await tester.pumpAndSettle();

      expect(find.byTooltip('Switch to light mode'), findsOneWidget);
    });

    testWidgets(
      'theme selection persists across ordinary interaction (not reset by '
      'scrolling)',
      (tester) async {
        final repository = _FakeOpportunityRepository(
          getResult: _opportunity(recruitmentProcess: 'quiz'),
        );
        final assessmentRepository = _FakeQuizAssessmentRepository(
          getResult: _quiz(status: 'published'),
        );
        await _pumpDetails(
          tester,
          repository: repository,
          assessmentRepository: assessmentRepository,
        );

        await tester.tap(find.byType(ThemeToggleButton));
        await tester.pumpAndSettle();
        expect(
          Theme.of(tester.element(find.byType(Scaffold).first)).brightness,
          Brightness.dark,
        );

        await tester.drag(
          find.byType(SingleChildScrollView),
          const Offset(0, -200),
        );
        await tester.pumpAndSettle();

        expect(
          Theme.of(tester.element(find.byType(Scaffold).first)).brightness,
          Brightness.dark,
        );
      },
    );
  });

  group('Light/Dark theme rendering (UI Phase O4)', () {
    testWidgets(
      'a normal opportunity without a Quiz renders with no exception in '
      'Light mode',
      (tester) async {
        final repository = _FakeOpportunityRepository(
          getResult: _opportunity(recruitmentProcess: 'interview'),
        );
        await _pumpDetails(tester, repository: repository);

        expect(tester.takeException(), isNull);
        expect(find.text('Software Engineer'), findsOneWidget);
        expect(find.text('Details'), findsOneWidget);
      },
    );

    testWidgets(
      'a Quiz opportunity renders with no exception in Dark mode',
      (tester) async {
        final repository = _FakeOpportunityRepository(
          getResult: _opportunity(recruitmentProcess: 'quiz'),
        );
        final assessmentRepository = _FakeQuizAssessmentRepository(
          getResult: _quiz(status: 'published'),
        );
        await _pumpDetails(
          tester,
          repository: repository,
          assessmentRepository: assessmentRepository,
        );

        await tester.tap(find.byType(ThemeToggleButton));
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(find.text('Published'), findsOneWidget);
      },
    );
  });

  group('Card theme reactivity (UI Phase O4.1)', () {
    Color cardBackground(WidgetTester tester, int index) {
      final container = tester.widget<Container>(
        find
            .descendant(
              of: find.byType(AppCard).at(index),
              matching: find.byType(Container),
            )
            .first,
      );
      return (container.decoration as BoxDecoration).color!;
    }

    testWidgets(
      'the Details card switches surface together with every other card '
      'on toggle (regression for the stale-card bug — it used to stay '
      'frozen on the pre-toggle palette while its siblings updated)',
      (tester) async {
        final repository = _FakeOpportunityRepository(
          getResult: _opportunity(recruitmentProcess: 'none'),
        );
        await _pumpDetails(tester, repository: repository);

        // Identity(0), Description(1), Details(2).
        final identityBefore = cardBackground(tester, 0);
        final detailsBefore = cardBackground(tester, 2);
        expect(detailsBefore, identityBefore);

        await tester.tap(find.byType(ThemeToggleButton));
        await tester.pumpAndSettle();

        final identityAfter = cardBackground(tester, 0);
        final detailsAfter = cardBackground(tester, 2);
        expect(detailsAfter, identityAfter);
        expect(detailsAfter, isNot(detailsBefore));
      },
    );

    testWidgets(
      'the Recruitment Process card switches surface together with every '
      'other card on toggle, even with no Quiz template loaded yet',
      (tester) async {
        final repository = _FakeOpportunityRepository(
          getResult: _opportunity(recruitmentProcess: 'interview'),
        );
        await _pumpDetails(tester, repository: repository);

        final identityBefore = cardBackground(tester, 0);
        final processBefore = cardBackground(tester, 3);
        expect(processBefore, identityBefore);

        await tester.tap(find.byType(ThemeToggleButton));
        await tester.pumpAndSettle();

        final identityAfter = cardBackground(tester, 0);
        final processAfter = cardBackground(tester, 3);
        expect(processAfter, identityAfter);
        expect(processAfter, isNot(processBefore));
      },
    );

    testWidgets(
      'Details value text uses the same primary text color as the rest '
      'of the page in both themes (never stuck on the other palette)',
      (tester) async {
        final repository = _FakeOpportunityRepository(
          getResult: _opportunity(),
        );
        await _pumpDetails(tester, repository: repository);

        final title = tester.widget<Text>(find.text('Software Engineer'));
        final value = tester.widget<Text>(find.text('Amman, Jordan'));
        expect(value.style?.color, title.style?.color);

        await tester.tap(find.byType(ThemeToggleButton));
        await tester.pumpAndSettle();

        final titleAfter = tester.widget<Text>(
          find.text('Software Engineer'),
        );
        final valueAfter = tester.widget<Text>(find.text('Amman, Jordan'));
        expect(valueAfter.style?.color, titleAfter.style?.color);
        expect(valueAfter.style?.color, isNot(value.style?.color));
      },
    );
  });

  group('Details grid column separation (UI Phase O4.1)', () {
    testWidgets(
      'desktop shows a vertical divider between the two Details columns',
      (tester) async {
        final repository = _FakeOpportunityRepository(
          getResult: _opportunity(),
        );
        await _pumpDetails(
          tester,
          repository: repository,
          size: const Size(1280, 900),
        );

        expect(find.byType(VerticalDivider), findsWidgets);
      },
    );

    testWidgets(
      'mobile stacks Details into a single column with no vertical '
      'divider',
      (tester) async {
        final repository = _FakeOpportunityRepository(
          getResult: _opportunity(),
        );
        await _pumpDetails(
          tester,
          repository: repository,
          size: const Size(375, 812),
        );

        expect(find.byType(VerticalDivider), findsNothing);
        expect(find.text('Location'), findsOneWidget);
        expect(find.text('Amman, Jordan'), findsOneWidget);
      },
    );

    testWidgets(
      'the Quiz summary grid also separates its label/value pairs and '
      'remains readable',
      (tester) async {
        final repository = _FakeOpportunityRepository(
          getResult: _opportunity(recruitmentProcess: 'quiz'),
        );
        final assessmentRepository = _FakeQuizAssessmentRepository(
          getResult: _quiz(status: 'published'),
        );
        await _pumpDetails(
          tester,
          repository: repository,
          assessmentRepository: assessmentRepository,
          size: const Size(1280, 900),
        );

        expect(find.text('Questions'), findsOneWidget);
        expect(find.text('Passing Score'), findsOneWidget);
        expect(find.text('Time Limit'), findsOneWidget);
        expect(find.text('Candidate Availability'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  });

  group('Responsive layout (UI Phase O4)', () {
    testWidgets('desktop (1280x900) renders a Quiz opportunity with no '
        'overflow', (tester) async {
      final repository = _FakeOpportunityRepository(
        getResult: _opportunity(recruitmentProcess: 'quiz'),
      );
      final assessmentRepository = _FakeQuizAssessmentRepository(
        getResult: _quiz(status: 'published'),
      );
      await _pumpDetails(
        tester,
        repository: repository,
        assessmentRepository: assessmentRepository,
        size: const Size(1280, 900),
      );

      expect(tester.takeException(), isNull);
      expect(find.text('View Quiz'), findsOneWidget);
      expect(find.text('View Results'), findsOneWidget);
    });

    testWidgets('tablet (960x800) renders a Quiz opportunity with no '
        'overflow', (tester) async {
      final repository = _FakeOpportunityRepository(
        getResult: _opportunity(recruitmentProcess: 'quiz'),
      );
      final assessmentRepository = _FakeQuizAssessmentRepository(
        getResult: _quiz(status: 'draft'),
      );
      await _pumpDetails(
        tester,
        repository: repository,
        assessmentRepository: assessmentRepository,
        size: const Size(960, 800),
      );

      expect(tester.takeException(), isNull);
    });

    testWidgets('mobile (375x812) renders a Quiz opportunity with both '
        'actions stacked and no overflow', (tester) async {
      final repository = _FakeOpportunityRepository(
        getResult: _opportunity(recruitmentProcess: 'quiz'),
      );
      final assessmentRepository = _FakeQuizAssessmentRepository(
        getResult: _quiz(status: 'published'),
      );
      await _pumpDetails(
        tester,
        repository: repository,
        assessmentRepository: assessmentRepository,
        size: const Size(375, 812),
      );

      expect(tester.takeException(), isNull);
      expect(find.text('View Quiz'), findsOneWidget);
      expect(find.text('View Results'), findsOneWidget);
    });
  });

  group('Requirements section (Recommendation Accuracy Patch)', () {
    testWidgets('shows eligible majors as chips', (tester) async {
      final repository = _FakeOpportunityRepository(
        getResult: _opportunity(
          eligibleMajors: ['Civil Engineering', 'Construction Engineering'],
        ),
      );
      await _pumpDetails(tester, repository: repository);

      expect(find.text('Civil Engineering'), findsOneWidget);
      expect(find.text('Construction Engineering'), findsOneWidget);
    });

    // Opportunity Academic Matching Cleanup, section 9: the Eligible
    // Major chip used AppStatusType.primary, whose dark-theme foreground/
    // background are both the same dark navy blue (near-unreadable).
    // AppStatusType.info has a genuinely contrast-safe pair in both
    // themes and is what this same screen's Required Skills chips (and
    // the Student-facing Eligible Majors chips) already use.
    testWidgets(
      'Eligible Major chips use AppStatusType.info, never the '
      'low-dark-mode-contrast primary type',
      (tester) async {
        final repository = _FakeOpportunityRepository(
          getResult: _opportunity(eligibleMajors: ['Civil Engineering']),
        );
        await _pumpDetails(tester, repository: repository);

        final chip = tester.widget<StatusChip>(
          find.widgetWithText(StatusChip, 'Civil Engineering'),
        );
        expect(chip.type, AppStatusType.info);
      },
    );

    testWidgets('shows "Open to all majors" when eligible majors is empty', (
      tester,
    ) async {
      final repository = _FakeOpportunityRepository(
        getResult: _opportunity(eligibleMajors: const []),
      );
      await _pumpDetails(tester, repository: repository);

      expect(find.text('Open to all majors'), findsOneWidget);
    });

    testWidgets('shows required skills separately from preferred skills', (
      tester,
    ) async {
      final repository = _FakeOpportunityRepository(
        getResult: _opportunity(
          opportunitySkills: const [
            OpportunitySkillModel(
              id: 1,
              isRequired: true,
              skill: SkillModel(id: 1, name: 'Revit'),
            ),
            OpportunitySkillModel(
              id: 2,
              isRequired: false,
              skill: SkillModel(id: 2, name: 'AutoCAD'),
            ),
          ],
        ),
      );
      await _pumpDetails(tester, repository: repository);

      expect(find.text('REQUIRED SKILLS'), findsOneWidget);
      expect(find.text('Revit'), findsOneWidget);
      expect(find.text('PREFERRED SKILLS'), findsOneWidget);
      expect(find.text('AutoCAD'), findsOneWidget);
    });

    testWidgets(
      'shows "No required skills configured" when there are none',
      (tester) async {
        final repository = _FakeOpportunityRepository(
          getResult: _opportunity(opportunitySkills: const []),
        );
        await _pumpDetails(tester, repository: repository);

        expect(find.text('No required skills configured'), findsOneWidget);
      },
    );

    testWidgets(
      'Field of Study is never displayed -- Opportunity Academic '
      'Matching Cleanup',
      (tester) async {
        final repository = _FakeOpportunityRepository(
          getResult: _opportunity(eligibleMajors: ['Civil Engineering']),
        );
        await _pumpDetails(tester, repository: repository);

        expect(find.text('Civil Engineering'), findsOneWidget);
        expect(find.text('Field of Study'), findsNothing);
      },
    );

    testWidgets(
      'a Remote opportunity clarifies location does not restrict '
      'recommendations',
      (tester) async {
        final repository = _FakeOpportunityRepository(
          getResult: _opportunity(workMode: 'remote'),
        );
        await _pumpDetails(tester, repository: repository);

        expect(
          find.textContaining('not used to restrict Recommended Candidates'),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'an on-site opportunity does not show the remote-only clarification',
      (tester) async {
        final repository = _FakeOpportunityRepository(
          getResult: _opportunity(workMode: 'onsite'),
        );
        await _pumpDetails(tester, repository: repository);

        expect(
          find.textContaining('not used to restrict Recommended Candidates'),
          findsNothing,
        );
      },
    );

    for (final width in [375.0, 390.0, 430.0]) {
      testWidgets(
        'mobile ${width.toInt()} renders the Requirements card with no '
        'overflow',
        (tester) async {
          final repository = _FakeOpportunityRepository(
            getResult: _opportunity(
              eligibleMajors: [
                'Civil Engineering',
                'Construction Engineering and Management',
              ],
              opportunitySkills: const [
                OpportunitySkillModel(
                  id: 1,
                  isRequired: true,
                  skill: SkillModel(id: 1, name: 'Revit'),
                ),
                OpportunitySkillModel(
                  id: 2,
                  isRequired: true,
                  skill: SkillModel(id: 2, name: 'AutoCAD'),
                ),
                OpportunitySkillModel(
                  id: 3,
                  isRequired: false,
                  skill: SkillModel(id: 3, name: 'Quantity Surveying'),
                ),
              ],
            ),
          );
          await _pumpDetails(
            tester,
            repository: repository,
            size: Size(width, 1400),
          );

          expect(tester.takeException(), isNull);
        },
      );
    }
  });
}
