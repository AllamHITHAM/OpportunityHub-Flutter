// Widget tests for OrganizationQuizResultsScreen (Phase 10A.4B).

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
import 'package:opportunityhub_flutter/features/assessments/presentation/organization_quiz_results_screen.dart';
import 'package:opportunityhub_flutter/features/auth/data/auth_repository.dart';
import 'package:opportunityhub_flutter/models/quiz_candidate_result_model.dart';
import 'package:opportunityhub_flutter/models/quiz_model.dart';
import 'package:opportunityhub_flutter/providers/auth_provider.dart';
import 'package:opportunityhub_flutter/providers/organization_quiz_provider.dart';
import 'package:opportunityhub_flutter/providers/theme_provider.dart';

class _FakeAuthRepository extends AuthRepository {
  _FakeAuthRepository()
    : super(
        apiClient: ApiClient(tokenStorageService: TokenStorageService()),
        tokenStorageService: TokenStorageService(),
      );

  @override
  Future<String?> getSavedToken() async => null;
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

class _FakeAssessmentRepository extends AssessmentRepository {
  _FakeAssessmentRepository()
    : super(apiClient: ApiClient(tokenStorageService: TokenStorageService()));

  QuizResultsModel? resultsResult;
  ApiException? resultsError;
  Duration resultsDelay = Duration.zero;
  int resultsCallCount = 0;

  @override
  Future<QuizResultsModel> getOpportunityQuizResults(int opportunityId) async {
    resultsCallCount++;
    if (resultsDelay > Duration.zero) {
      await Future<void>.delayed(resultsDelay);
    }
    if (resultsError != null) throw resultsError!;
    return resultsResult!;
  }
}

QuizModel _quiz({String title = 'Backend Fundamentals'}) {
  return QuizModel(
    id: 1,
    opportunityId: 9,
    title: title,
    passingScore: 70,
    status: 'published',
  );
}

QuizCandidateResultModel _candidate({
  int assessmentId = 1,
  int applicationId = 1,
  String studentName = 'Ahmad Ali',
  String status = 'completed',
  int? score,
  DateTime? submittedAt,
  String? timingStatus,
  String? result,
  DateTime? resultReleasedAt,
  String? nextAction,
}) {
  return QuizCandidateResultModel(
    assessmentId: assessmentId,
    applicationId: applicationId,
    studentName: studentName,
    status: status,
    score: score,
    submittedAt: submittedAt,
    timingStatus: timingStatus,
    result: result,
    resultReleasedAt: resultReleasedAt,
    nextAction: nextAction,
  );
}

Future<void> _pumpResults(
  WidgetTester tester, {
  required _FakeAssessmentRepository repository,
  int opportunityId = 9,
  Size size = const Size(420, 1400),
}) async {
  // AppColors.updateBrightness is a process-global static -- reset it so
  // one test's theme choice never leaks into the next.
  addTearDown(() => AppColors.updateBrightness(Brightness.light));

  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final authProvider = AuthProvider(authRepository: _FakeAuthRepository());
  final quizProvider = OrganizationQuizProvider(
    repository: repository,
    authProvider: authProvider,
  );
  final themeProvider = ThemeProvider(storage: _FakeThemePreferenceStorage());
  await themeProvider.initialize();

  final router = GoRouter(
    initialLocation: '/results',
    routes: [
      GoRoute(
        path: '/results',
        builder: (_, _) =>
            OrganizationQuizResultsScreen(opportunityId: opportunityId),
      ),
      GoRoute(
        path: '/organization/applications/:id',
        builder: (_, state) => Scaffold(
          body: Text('APPLICATION_${state.pathParameters['id']}'),
        ),
      ),
    ],
  );

  await tester.pumpWidget(
    MultiProvider(
      providers: [
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
}

void main() {
  testWidgets('loading state shows a spinner', (tester) async {
    tester.view.physicalSize = const Size(420, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    addTearDown(() => AppColors.updateBrightness(Brightness.light));

    final authProvider = AuthProvider(authRepository: _FakeAuthRepository());
    final repository = _FakeAssessmentRepository()
      ..resultsResult = QuizResultsModel(quiz: _quiz(), candidates: const [])
      ..resultsDelay = const Duration(milliseconds: 100);
    final quizProvider = OrganizationQuizProvider(
      repository: repository,
      authProvider: authProvider,
    );
    final themeProvider = ThemeProvider(storage: _FakeThemePreferenceStorage());
    await themeProvider.initialize();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<OrganizationQuizProvider>.value(
            value: quizProvider,
          ),
          ChangeNotifierProvider<ThemeProvider>.value(value: themeProvider),
        ],
        child: MaterialApp(
          theme: AppTheme.lightTheme,
          home: const OrganizationQuizResultsScreen(opportunityId: 9),
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    // Let the pending delayed future resolve before the test ends -- an
    // outstanding Timer at teardown fails the test binding's own
    // invariant check.
    await tester.pump(const Duration(milliseconds: 150));
  });

  testWidgets('an error shows a retry that reloads results', (tester) async {
    final repository = _FakeAssessmentRepository()
      ..resultsError = ApiException('Opportunity not found');
    await _pumpResults(tester, repository: repository);

    expect(find.text('Opportunity not found'), findsOneWidget);

    repository.resultsError = null;
    repository.resultsResult = QuizResultsModel(
      quiz: _quiz(),
      candidates: [_candidate()],
    );
    await tester.tap(find.text('Try Again'));
    await tester.pumpAndSettle();

    expect(repository.resultsCallCount, 2);
    expect(find.text('Ahmad Ali'), findsOneWidget);
  });

  testWidgets('empty results show a clear empty state', (tester) async {
    final repository = _FakeAssessmentRepository()
      ..resultsResult = QuizResultsModel(quiz: _quiz(), candidates: const []);
    await _pumpResults(tester, repository: repository);

    expect(find.text('No Results Yet'), findsOneWidget);
  });

  testWidgets(
    'renders each candidate with a prominent score, result, and decision '
    'state',
    (tester) async {
      final repository = _FakeAssessmentRepository()
        ..resultsResult = QuizResultsModel(
          quiz: _quiz(),
          candidates: [
            _candidate(
              applicationId: 101,
              studentName: 'Ahmad Ali',
              score: 94,
              result: 'passed',
              nextAction: 'interview',
              resultReleasedAt: DateTime(2026, 8, 30),
            ),
            _candidate(
              assessmentId: 2,
              applicationId: 102,
              studentName: 'Sara Youssef',
              score: 61,
              result: 'failed',
            ),
          ],
        );
      await _pumpResults(tester, repository: repository);

      expect(find.text('Ahmad Ali'), findsOneWidget);
      expect(find.text('94%'), findsOneWidget);
      // "Passed"/"Decision Required" each also appear as a filter chip
      // label -- assert presence (>=1), not an exact single-widget count.
      expect(find.text('Passed'), findsWidgets);
      expect(find.text('Next Step: Interview'), findsOneWidget);
      expect(find.text('Released'), findsWidgets);

      expect(find.text('Sara Youssef'), findsOneWidget);
      expect(find.text('61%'), findsOneWidget);
      expect(find.text('Failed'), findsWidgets);
      expect(find.text('Decision Required'), findsWidgets);
      expect(find.text('Pending'), findsWidgets);
    },
  );

  testWidgets('never exposes candidate answers or correct answers', (
    tester,
  ) async {
    final repository = _FakeAssessmentRepository()
      ..resultsResult = QuizResultsModel(
        quiz: _quiz(),
        candidates: [_candidate(score: 100, result: 'passed')],
      );
    await _pumpResults(tester, repository: repository);

    expect(find.textContaining('correct_answer'), findsNothing);
    expect(find.textContaining('answers'), findsNothing);
  });

  testWidgets('filtering to Decision Required hides other candidates', (
    tester,
  ) async {
    final repository = _FakeAssessmentRepository()
      ..resultsResult = QuizResultsModel(
        quiz: _quiz(),
        candidates: [
          _candidate(
            applicationId: 101,
            studentName: 'Ahmad Ali',
            score: 94,
            result: 'passed',
            nextAction: 'interview',
          ),
          _candidate(
            assessmentId: 2,
            applicationId: 102,
            studentName: 'Sara Youssef',
            score: 61,
            result: 'failed',
          ),
        ],
      );
    await _pumpResults(tester, repository: repository);

    final decisionRequiredChip = find.widgetWithText(
      ChoiceChip,
      'Decision Required',
    );
    await tester.ensureVisible(decisionRequiredChip);
    await tester.pumpAndSettle();
    await tester.tap(decisionRequiredChip);
    await tester.pumpAndSettle();

    expect(find.text('Sara Youssef'), findsOneWidget);
    expect(find.text('Ahmad Ali'), findsNothing);
  });

  testWidgets('Review/Decide navigates to the real Application Details '
      'screen', (tester) async {
    final repository = _FakeAssessmentRepository()
      ..resultsResult = QuizResultsModel(
        quiz: _quiz(),
        candidates: [_candidate(applicationId: 101, studentName: 'Ahmad Ali')],
      );
    await _pumpResults(tester, repository: repository);

    await tester.tap(find.text('Decide'));
    await tester.pumpAndSettle();

    expect(find.text('APPLICATION_101'), findsOneWidget);
  });

  testWidgets('summary counts reflect completed/passed/failed/decision '
      'required', (tester) async {
    final repository = _FakeAssessmentRepository()
      ..resultsResult = QuizResultsModel(
        quiz: _quiz(),
        candidates: [
          _candidate(
            applicationId: 101,
            score: 94,
            result: 'passed',
            nextAction: 'interview',
          ),
          _candidate(assessmentId: 2, applicationId: 102, score: 61, result: 'failed'),
          _candidate(assessmentId: 3, applicationId: 103, status: 'in_progress'),
        ],
      );
    await _pumpResults(tester, repository: repository);

    expect(find.text('2'), findsOneWidget); // Completed
    expect(find.text('1'), findsNWidgets(3)); // Passed, Failed, Decision Required each = 1
  });

  testWidgets('does not overflow at a narrow 320x700 viewport', (
    tester,
  ) async {
    final repository = _FakeAssessmentRepository()
      ..resultsResult = QuizResultsModel(
        quiz: _quiz(),
        candidates: [
          _candidate(studentName: 'A Very Long Candidate Name That Might Wrap'),
        ],
      );
    await _pumpResults(tester, repository: repository, size: const Size(320, 700));

    expect(tester.takeException(), isNull);
  });

  testWidgets('does not overflow at a wide desktop viewport', (tester) async {
    final repository = _FakeAssessmentRepository()
      ..resultsResult = QuizResultsModel(
        quiz: _quiz(),
        candidates: [_candidate()],
      );
    await _pumpResults(
      tester,
      repository: repository,
      size: const Size(1400, 900),
    );

    expect(tester.takeException(), isNull);
  });

  group('theme toggle (UI Phase O5)', () {
    testWidgets('is present in the AppBar and switches the resolved theme', (
      tester,
    ) async {
      final repository = _FakeAssessmentRepository()
        ..resultsResult = QuizResultsModel(
          quiz: _quiz(),
          candidates: [_candidate()],
        );
      await _pumpResults(tester, repository: repository);

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

    testWidgets('the tooltip reflects the real toggle direction in both '
        'states', (tester) async {
      final repository = _FakeAssessmentRepository()
        ..resultsResult = QuizResultsModel(
          quiz: _quiz(),
          candidates: [_candidate()],
        );
      await _pumpResults(tester, repository: repository);

      expect(find.byTooltip('Switch to dark mode'), findsOneWidget);

      await tester.tap(find.byType(ThemeToggleButton));
      await tester.pumpAndSettle();

      expect(find.byTooltip('Switch to light mode'), findsOneWidget);
    });

    testWidgets(
      'candidate rows/cards switch surface together with the rest of the '
      'page on toggle (no stale card)',
      (tester) async {
        final repository = _FakeAssessmentRepository()
          ..resultsResult = QuizResultsModel(
            quiz: _quiz(),
            candidates: [_candidate()],
          );
        await _pumpResults(tester, repository: repository);

        Color cardBackground(int index) {
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

        final before = cardBackground(0);

        await tester.tap(find.byType(ThemeToggleButton));
        await tester.pumpAndSettle();

        final after = cardBackground(0);
        expect(after, isNot(before));
      },
    );
  });

  group('desktop comparison layout (UI Phase O5)', () {
    testWidgets(
      'shows labeled columns and bare per-row values at 1280 width',
      (tester) async {
        final repository = _FakeAssessmentRepository()
          ..resultsResult = QuizResultsModel(
            quiz: _quiz(),
            candidates: [
              _candidate(
                applicationId: 101,
                studentName: 'Omar Yasin',
                score: 100,
                result: 'passed',
                nextAction: 'interview',
              ),
            ],
          );
        await _pumpResults(
          tester,
          repository: repository,
          size: const Size(1280, 900),
        );

        expect(find.text('Candidate'), findsOneWidget);
        expect(find.text('Score'), findsOneWidget);
        expect(find.text('Result'), findsOneWidget);
        expect(find.text('Next Step'), findsOneWidget);
        expect(find.text('Release'), findsOneWidget);
        expect(find.text('Submission'), findsOneWidget);

        expect(find.text('Omar Yasin'), findsOneWidget);
        expect(find.text('100%'), findsOneWidget);
        // Bare value, not "Next Step: Interview" -- the column header
        // already supplies that context on the desktop layout.
        expect(find.text('Interview'), findsOneWidget);
        expect(find.text('Next Step: Interview'), findsNothing);
        expect(find.text('Review'), findsOneWidget);
      },
    );

    testWidgets('tablet width (960) still renders the comparison layout '
        'with no overflow', (tester) async {
      final repository = _FakeAssessmentRepository()
        ..resultsResult = QuizResultsModel(
          quiz: _quiz(),
          candidates: [
            _candidate(studentName: 'Sara Youssef', score: 61, result: 'failed'),
          ],
        );
      await _pumpResults(
        tester,
        repository: repository,
        size: const Size(960, 800),
      );

      expect(find.text('Candidate'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('mobile candidate cards (UI Phase O5)', () {
    testWidgets(
      'stacks fields with explicit labels instead of desktop columns',
      (tester) async {
        final repository = _FakeAssessmentRepository()
          ..resultsResult = QuizResultsModel(
            quiz: _quiz(),
            candidates: [
              _candidate(
                applicationId: 101,
                studentName: 'Omar Yasin',
                score: 100,
                result: 'passed',
                nextAction: 'interview',
                resultReleasedAt: DateTime(2026, 8, 30),
              ),
            ],
          );
        await _pumpResults(
          tester,
          repository: repository,
          size: const Size(375, 812),
        );

        expect(find.text('Candidate'), findsNothing);
        expect(find.text('Omar Yasin'), findsOneWidget);
        expect(find.text('100%'), findsOneWidget);
        expect(find.text('Next Step: Interview'), findsOneWidget);
        expect(find.text('Release: Released'), findsOneWidget);
        expect(find.text('Submission: Submitted'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('a Decision Required candidate is labeled clearly', (
      tester,
    ) async {
      final repository = _FakeAssessmentRepository()
        ..resultsResult = QuizResultsModel(
          quiz: _quiz(),
          candidates: [
            _candidate(studentName: 'Sara Youssef', score: 61, result: 'failed'),
          ],
        );
      await _pumpResults(
        tester,
        repository: repository,
        size: const Size(375, 812),
      );

      expect(find.text('Decision: Required'), findsOneWidget);
    });
  });

  group('Submission timestamp (Submission Timestamp Fix)', () {
    testWidgets(
      'a submitted candidate with a real timestamp shows it once, muted, '
      'under "Submitted" -- no duplicate "Submitted" text',
      (tester) async {
        final repository = _FakeAssessmentRepository()
          ..resultsResult = QuizResultsModel(
            quiz: _quiz(),
            candidates: [
              _candidate(
                studentName: 'Ahmad Ali',
                score: 94,
                result: 'passed',
                timingStatus: 'submitted',
                submittedAt: DateTime(2026, 8, 27, 13, 28),
              ),
            ],
          );
        await _pumpResults(tester, repository: repository);

        expect(find.text('Submission: Submitted'), findsOneWidget);
        expect(find.text('Aug 27, 2026 at 1:28 PM'), findsOneWidget);
        expect(find.text('Submitted'), findsNothing);
      },
    );

    testWidgets(
      'the desktop table shows the real timestamp under the bare '
      '"Submitted" label',
      (tester) async {
        final repository = _FakeAssessmentRepository()
          ..resultsResult = QuizResultsModel(
            quiz: _quiz(),
            candidates: [
              _candidate(
                studentName: 'Omar Yasin',
                score: 100,
                result: 'passed',
                timingStatus: 'submitted',
                submittedAt: DateTime(2026, 8, 27, 13, 28),
              ),
            ],
          );
        await _pumpResults(
          tester,
          repository: repository,
          size: const Size(1280, 900),
        );

        expect(find.text('Submitted'), findsOneWidget);
        expect(find.text('Aug 27, 2026 at 1:28 PM'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'a submitted candidate with no real timestamp shows only "Submitted" '
      '-- reproduces the original duplicate-text bug and confirms the fix '
      '(timingStatus == submitted, no submitted_at from the backend)',
      (tester) async {
        final repository = _FakeAssessmentRepository()
          ..resultsResult = QuizResultsModel(
            quiz: _quiz(),
            candidates: [
              _candidate(
                studentName: 'Ahmad Ali',
                score: 94,
                result: 'passed',
                timingStatus: 'submitted',
              ),
            ],
          );
        await _pumpResults(tester, repository: repository);

        expect(find.text('Submission: Submitted'), findsOneWidget);
        // Exactly the one label -- no second "Submitted" line underneath,
        // and no fabricated timestamp.
        expect(find.text('Submitted'), findsNothing);
      },
    );

    testWidgets(
      'a not-yet-submitted candidate keeps its real opens/due-date line, '
      'which is not a duplicate',
      (tester) async {
        final repository = _FakeAssessmentRepository()
          ..resultsResult = QuizResultsModel(
            quiz: _quiz(),
            candidates: [
              _candidate(
                studentName: 'Layla Hassan',
                status: 'pending',
                timingStatus: 'upcoming',
              ),
            ],
          );
        await _pumpResults(tester, repository: repository);

        expect(find.text('Upcoming'), findsOneWidget);
      },
    );

    testWidgets('no overflow on mobile with a real submission timestamp', (
      tester,
    ) async {
      final repository = _FakeAssessmentRepository()
        ..resultsResult = QuizResultsModel(
          quiz: _quiz(),
          candidates: [
            _candidate(
              studentName: 'A Very Long Candidate Name That Might Wrap',
              score: 94,
              result: 'passed',
              timingStatus: 'submitted',
              submittedAt: DateTime(2026, 8, 27, 13, 28),
            ),
          ],
        );
      await _pumpResults(
        tester,
        repository: repository,
        size: const Size(320, 700),
      );

      expect(tester.takeException(), isNull);
    });

    testWidgets('renders correctly in Dark mode with a real timestamp', (
      tester,
    ) async {
      final repository = _FakeAssessmentRepository()
        ..resultsResult = QuizResultsModel(
          quiz: _quiz(),
          candidates: [
            _candidate(
              studentName: 'Ahmad Ali',
              score: 94,
              result: 'passed',
              timingStatus: 'submitted',
              submittedAt: DateTime(2026, 8, 27, 13, 28),
            ),
          ],
        );
      await _pumpResults(tester, repository: repository);

      await tester.tap(find.byType(ThemeToggleButton));
      await tester.pumpAndSettle();

      expect(find.text('Aug 27, 2026 at 1:28 PM'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
