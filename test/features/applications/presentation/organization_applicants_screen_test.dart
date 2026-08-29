// Widget tests for OrganizationApplicantsScreen, in isolation with a small
// GoRouter.

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
import 'package:opportunityhub_flutter/features/applications/data/application_repository.dart';
import 'package:opportunityhub_flutter/features/applications/presentation/organization_applicants_screen.dart';
import 'package:opportunityhub_flutter/features/auth/data/auth_repository.dart';
import 'package:opportunityhub_flutter/models/applicant_summary_model.dart';
import 'package:opportunityhub_flutter/models/application_model.dart';
import 'package:opportunityhub_flutter/models/cv_model.dart';
import 'package:opportunityhub_flutter/providers/auth_provider.dart';
import 'package:opportunityhub_flutter/providers/organization_applications_provider.dart';
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

const _cv = CvModel(
  id: 2,
  studentId: 1,
  title: 'Main CV',
  filePath: 'uploads/cv.pdf',
  version: 1,
  isDefault: false,
  createdByAi: false,
);

ApplicationModel _application({
  int id = 1,
  String status = 'pending',
  ApplicantSummaryModel? applicant,
  double? matchScore,
}) {
  return ApplicationModel(
    id: id,
    studentId: 1,
    opportunityId: 5,
    cvId: 2,
    status: status,
    cv: _cv,
    applicant: applicant,
    matchScore: matchScore,
    appliedAt: DateTime(2026, 7, 20),
  );
}

class _FakeApplicationRepository extends ApplicationRepository {
  _FakeApplicationRepository({
    this.listResult = const [],
    this.listError,
    this.listDelay = Duration.zero,
  }) : super(apiClient: ApiClient(tokenStorageService: TokenStorageService()));

  List<ApplicationModel> listResult;
  ApiException? listError;
  Duration listDelay;
  int callCount = 0;

  @override
  Future<List<ApplicationModel>> getApplicationsForOpportunity(
    int opportunityId,
  ) async {
    callCount++;
    if (listDelay > Duration.zero) {
      await Future<void>.delayed(listDelay);
    }
    if (listError != null) throw listError!;
    return listResult;
  }
}

Future<OrganizationApplicationsProvider> _pumpScreen(
  WidgetTester tester, {
  required _FakeApplicationRepository repository,
  Size size = const Size(420, 800),
}) async {
  // AppColors.updateBrightness is a process-global static -- reset it so
  // one test's theme choice never leaks into the next.
  addTearDown(() => AppColors.updateBrightness(Brightness.light));

  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final authProvider = AuthProvider(authRepository: _FakeAuthRepository());
  final provider = OrganizationApplicationsProvider(
    repository: repository,
    authProvider: authProvider,
  );
  final themeProvider = ThemeProvider(storage: _FakeThemePreferenceStorage());
  await themeProvider.initialize();

  final router = GoRouter(
    initialLocation: AppRoutes.organizationApplicants(5),
    routes: [
      GoRoute(
        path: '${AppRoutes.organizationOpportunities}/:id/applicants',
        builder: (_, state) => OrganizationApplicantsScreen(
          opportunityId: int.parse(state.pathParameters['id']!),
        ),
      ),
      GoRoute(
        path: '${AppRoutes.organizationApplications}/:id',
        builder: (context, state) => Scaffold(
          body: Column(
            children: [
              Text(
                'APPLICATION_DETAILS_PLACEHOLDER_${state.pathParameters['id']}',
              ),
              ElevatedButton(
                onPressed: () => context.pop(),
                child: const Text('Go Back'),
              ),
            ],
          ),
        ),
      ),
    ],
  );

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<OrganizationApplicationsProvider>.value(
          value: provider,
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

  return provider;
}

void main() {
  testWidgets('Loading state renders while the list is in flight', (
    tester,
  ) async {
    addTearDown(() => AppColors.updateBrightness(Brightness.light));

    final repository = _FakeApplicationRepository(
      listDelay: const Duration(milliseconds: 200),
    );
    tester.view.physicalSize = const Size(420, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final authProvider = AuthProvider(authRepository: _FakeAuthRepository());
    final provider = OrganizationApplicationsProvider(
      repository: repository,
      authProvider: authProvider,
    );
    final router = GoRouter(
      initialLocation: AppRoutes.organizationApplicants(5),
      routes: [
        GoRoute(
          path: '${AppRoutes.organizationOpportunities}/:id/applicants',
          builder: (_, state) => OrganizationApplicantsScreen(
            opportunityId: int.parse(state.pathParameters['id']!),
          ),
        ),
      ],
    );

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<OrganizationApplicationsProvider>.value(
            value: provider,
          ),
          ChangeNotifierProvider<ThemeProvider>.value(value: ThemeProvider()),
        ],
        child: MaterialApp.router(
          theme: AppTheme.lightTheme,
          routerConfig: router,
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(provider.isLoadingList, isTrue);

    await tester.pumpAndSettle();
  });

  testWidgets('Empty state renders', (tester) async {
    await _pumpScreen(tester, repository: _FakeApplicationRepository());

    expect(find.text('No Applicants Yet'), findsOneWidget);
  });

  testWidgets('Error state renders with retry', (tester) async {
    final repository = _FakeApplicationRepository(
      listError: ApiException('Server error, please try again later.'),
    );
    await _pumpScreen(tester, repository: repository);

    expect(find.text('Server error, please try again later.'), findsOneWidget);

    repository.listError = null;
    repository.listResult = [
      _application(
        applicant: const ApplicantSummaryModel(id: 1, name: 'Jane Student'),
      ),
    ];
    await tester.tap(find.text('Try Again'));
    await tester.pumpAndSettle();

    expect(find.text('Jane Student'), findsOneWidget);
  });

  testWidgets(
    'Applicant card renders name, email, university/major, status, and match score',
    (tester) async {
      final repository = _FakeApplicationRepository(
        listResult: [
          _application(
            status: 'shortlisted',
            matchScore: 68.75,
            applicant: const ApplicantSummaryModel(
              id: 1,
              name: 'Jane Student',
              email: 'jane@example.com',
              university: 'State University',
              major: 'Computer Science',
            ),
          ),
        ],
      );
      await _pumpScreen(tester, repository: repository);

      expect(find.text('Jane Student'), findsOneWidget);
      expect(find.text('jane@example.com'), findsOneWidget);
      expect(find.text('Computer Science, State University'), findsOneWidget);
      // "Shortlisted" also appears as a filter chip label now (UI Phase
      // O7), so this is >=1, not exactly one.
      expect(find.text('Shortlisted'), findsWidgets);
      expect(find.text('Match'), findsWidgets);
      expect(find.text('69%'), findsOneWidget);
    },
  );

  testWidgets(
    'Match score shows a truthful "Not available" when not present (null, '
    'never a misleading 0%)',
    (tester) async {
      final repository = _FakeApplicationRepository(
        listResult: [
          _application(
            applicant: const ApplicantSummaryModel(id: 1, name: 'Jane Student'),
          ),
        ],
      );
      await _pumpScreen(tester, repository: repository);

      // A never-calculated (null) score must never be confused with a
      // genuine 0% -- see ApplicationModel.matchScore's own doc comment.
      expect(find.text('Not available'), findsOneWidget);
      expect(find.text('0%'), findsNothing);
    },
  );

  testWidgets('A genuine 0 match score is shown, not treated as unavailable', (
    tester,
  ) async {
    final repository = _FakeApplicationRepository(
      listResult: [
        _application(
          matchScore: 0,
          applicant: const ApplicantSummaryModel(id: 1, name: 'Jane Student'),
        ),
      ],
    );
    await _pumpScreen(tester, repository: repository);

    expect(find.text('0%'), findsOneWidget);
    expect(find.text('Not available'), findsNothing);
  });

  testWidgets('Missing name falls back to "Unnamed applicant"', (tester) async {
    final repository = _FakeApplicationRepository(
      listResult: [_application(applicant: null)],
    );
    await _pumpScreen(tester, repository: repository);

    expect(find.text('Unnamed applicant'), findsOneWidget);
  });

  testWidgets('Missing email does not render an empty row', (tester) async {
    final repository = _FakeApplicationRepository(
      listResult: [
        _application(
          applicant: const ApplicantSummaryModel(id: 1, name: 'Jane Student'),
        ),
      ],
    );
    await _pumpScreen(tester, repository: repository);

    // find.text('') would also match the (always-present, initially
    // empty) AppSearchField's own EditableText -- scope to real blank
    // Text widgets only.
    expect(
      find.byWidgetPredicate((w) => w is Text && w.data == ''),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('Empty-string name falls back to "Unnamed applicant"', (
    tester,
  ) async {
    final repository = _FakeApplicationRepository(
      listResult: [
        _application(applicant: const ApplicantSummaryModel(id: 1, name: '')),
      ],
    );
    await _pumpScreen(tester, repository: repository);

    expect(find.text('Unnamed applicant'), findsOneWidget);
    // find.text('') would also match the (always-present, initially
    // empty) AppSearchField's own EditableText -- scope to real blank
    // Text widgets only.
    expect(
      find.byWidgetPredicate((w) => w is Text && w.data == ''),
      findsNothing,
    );
  });

  testWidgets('Whitespace-only name falls back to "Unnamed applicant"', (
    tester,
  ) async {
    final repository = _FakeApplicationRepository(
      listResult: [
        _application(
          applicant: const ApplicantSummaryModel(id: 1, name: '   '),
        ),
      ],
    );
    await _pumpScreen(tester, repository: repository);

    expect(find.text('Unnamed applicant'), findsOneWidget);
    expect(find.text('   '), findsNothing);
  });

  testWidgets('Whitespace-only email does not render an empty row', (
    tester,
  ) async {
    final repository = _FakeApplicationRepository(
      listResult: [
        _application(
          applicant: const ApplicantSummaryModel(
            id: 1,
            name: 'Jane Student',
            email: '   ',
          ),
        ),
      ],
    );
    await _pumpScreen(tester, repository: repository);

    expect(find.text('   '), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Whitespace-only university and major does not render a study line',
    (tester) async {
      final repository = _FakeApplicationRepository(
        listResult: [
          _application(
            applicant: const ApplicantSummaryModel(
              id: 1,
              name: 'Jane Student',
              university: '   ',
              major: '  ',
            ),
          ),
        ],
      );
      await _pumpScreen(tester, repository: repository);

      expect(find.text('   '), findsNothing);
      expect(find.text('  '), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'One blank field (major) and one real field (university) renders only the real one',
    (tester) async {
      final repository = _FakeApplicationRepository(
        listResult: [
          _application(
            applicant: const ApplicantSummaryModel(
              id: 1,
              name: 'Jane Student',
              university: 'State University',
              major: '   ',
            ),
          ),
        ],
      );
      await _pumpScreen(tester, repository: repository);

      expect(find.text('State University'), findsOneWidget);
      expect(find.text('   '), findsNothing);
    },
  );

  testWidgets('Tapping a card opens its details route by ID', (tester) async {
    final repository = _FakeApplicationRepository(
      listResult: [
        _application(
          id: 42,
          applicant: const ApplicantSummaryModel(id: 1, name: 'Jane Student'),
        ),
      ],
    );
    await _pumpScreen(tester, repository: repository);

    await tester.tap(find.text('Jane Student'));
    await tester.pumpAndSettle();

    expect(find.text('APPLICATION_DETAILS_PLACEHOLDER_42'), findsOneWidget);
  });

  testWidgets(
    'Returning from Application Details force-refreshes the applicant list '
    '(Phase 8A-3: picks up an updated match_score/ranking)',
    (tester) async {
      final repository = _FakeApplicationRepository(
        listResult: [
          _application(
            id: 42,
            matchScore: 40,
            applicant: const ApplicantSummaryModel(id: 1, name: 'Jane Student'),
          ),
        ],
      );
      await _pumpScreen(tester, repository: repository);
      expect(repository.callCount, 1);

      await tester.tap(find.text('Jane Student'));
      await tester.pumpAndSettle();
      expect(find.text('APPLICATION_DETAILS_PLACEHOLDER_42'), findsOneWidget);

      // Simulate the score having changed while on Details (e.g. a
      // Recalculate) -- the next list fetch should reflect it.
      repository.listResult = [
        _application(
          id: 42,
          matchScore: 95,
          applicant: const ApplicantSummaryModel(id: 1, name: 'Jane Student'),
        ),
      ];

      await tester.tap(find.text('Go Back'));
      await tester.pumpAndSettle();

      expect(repository.callCount, 2);
      expect(find.text('95%'), findsOneWidget);
    },
  );

  testWidgets('Does not overflow at a narrow 320x720 viewport', (tester) async {
    final repository = _FakeApplicationRepository(
      listResult: [
        _application(
          id: 1,
          applicant: const ApplicantSummaryModel(
            id: 1,
            name: 'Jane Student',
            email: 'jane@example.com',
            university: 'State University',
            major: 'Computer Science',
          ),
          matchScore: 80,
        ),
      ],
    );
    await _pumpScreen(
      tester,
      repository: repository,
      size: const Size(320, 720),
    );

    expect(tester.takeException(), isNull);
  });

  group('search (UI Phase O7)', () {
    List<ApplicationModel> twoApplicants() => [
      _application(
        id: 1,
        applicant: const ApplicantSummaryModel(
          id: 1,
          name: 'Jane Student',
          email: 'jane@example.com',
          major: 'Computer Science',
        ),
      ),
      _application(
        id: 2,
        applicant: const ApplicantSummaryModel(
          id: 2,
          name: 'Omar Yasin',
          email: 'omar@example.com',
          university: 'Tech Institute',
        ),
      ),
    ];

    testWidgets('filters by name', (tester) async {
      final repository = _FakeApplicationRepository(
        listResult: twoApplicants(),
      );
      await _pumpScreen(tester, repository: repository);

      await tester.enterText(find.byType(TextField), 'Omar');
      await tester.pumpAndSettle();

      expect(find.text('Omar Yasin'), findsOneWidget);
      expect(find.text('Jane Student'), findsNothing);
    });

    testWidgets('filters by email', (tester) async {
      final repository = _FakeApplicationRepository(
        listResult: twoApplicants(),
      );
      await _pumpScreen(tester, repository: repository);

      await tester.enterText(find.byType(TextField), 'jane@example.com');
      await tester.pumpAndSettle();

      expect(find.text('Jane Student'), findsOneWidget);
      expect(find.text('Omar Yasin'), findsNothing);
    });

    testWidgets('a non-matching query shows the filtered-empty state', (
      tester,
    ) async {
      final repository = _FakeApplicationRepository(
        listResult: twoApplicants(),
      );
      await _pumpScreen(tester, repository: repository);

      await tester.enterText(find.byType(TextField), 'zzz-no-match');
      await tester.pumpAndSettle();

      expect(find.text('No Matching Applicants'), findsOneWidget);
      expect(find.text('Clear Filters'), findsOneWidget);
    });
  });

  group('status filter (UI Phase O7)', () {
    testWidgets('filtering to Shortlisted hides other statuses', (
      tester,
    ) async {
      final repository = _FakeApplicationRepository(
        listResult: [
          _application(
            id: 1,
            status: 'shortlisted',
            applicant: const ApplicantSummaryModel(id: 1, name: 'Jane Student'),
          ),
          _application(
            id: 2,
            applicant: const ApplicantSummaryModel(id: 2, name: 'Omar Yasin'),
          ),
        ],
      );
      await _pumpScreen(tester, repository: repository);

      final shortlistedChip = find.widgetWithText(ChoiceChip, 'Shortlisted');
      await tester.ensureVisible(shortlistedChip);
      await tester.pumpAndSettle();
      await tester.tap(shortlistedChip);
      await tester.pumpAndSettle();

      expect(find.text('Jane Student'), findsOneWidget);
      expect(find.text('Omar Yasin'), findsNothing);
    });
  });

  group('theme toggle (UI Phase O7)', () {
    testWidgets('is present in the AppBar and switches the resolved theme', (
      tester,
    ) async {
      final repository = _FakeApplicationRepository(
        listResult: [
          _application(
            applicant: const ApplicantSummaryModel(id: 1, name: 'Jane Student'),
          ),
        ],
      );
      await _pumpScreen(tester, repository: repository);

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
      final repository = _FakeApplicationRepository(
        listResult: [
          _application(
            applicant: const ApplicantSummaryModel(id: 1, name: 'Jane Student'),
          ),
        ],
      );
      await _pumpScreen(tester, repository: repository);

      expect(find.byTooltip('Switch to dark mode'), findsOneWidget);

      await tester.tap(find.byType(ThemeToggleButton));
      await tester.pumpAndSettle();

      expect(find.byTooltip('Switch to light mode'), findsOneWidget);
    });

    testWidgets(
      'applicant cards switch surface together with the rest of the page '
      'on toggle (no stale card)',
      (tester) async {
        final repository = _FakeApplicationRepository(
          listResult: [
            _application(
              applicant: const ApplicantSummaryModel(
                id: 1,
                name: 'Jane Student',
              ),
            ),
          ],
        );
        await _pumpScreen(tester, repository: repository);

        Color cardBackground() {
          final container = tester.widget<Container>(
            find
                .descendant(
                  of: find.byType(AppCard).first,
                  matching: find.byType(Container),
                )
                .first,
          );
          return (container.decoration as BoxDecoration).color!;
        }

        final before = cardBackground();

        await tester.tap(find.byType(ThemeToggleButton));
        await tester.pumpAndSettle();

        final after = cardBackground();
        expect(after, isNot(before));
        expect(tester.takeException(), isNull);
      },
    );
  });

  group('responsive layout (UI Phase O7)', () {
    List<ApplicationModel> severalApplicants() => [
      for (var i = 1; i <= 4; i++)
        _application(
          id: i,
          status: i.isEven ? 'shortlisted' : 'pending',
          matchScore: i * 20.0,
          applicant: ApplicantSummaryModel(
            id: i,
            name: 'Candidate $i',
            email: 'candidate$i@example.com',
            major: 'Computer Science',
            university: 'State University',
          ),
        ),
    ];

    testWidgets('desktop (1280x900) renders a multi-column grid with no '
        'overflow', (tester) async {
      final repository = _FakeApplicationRepository(
        listResult: severalApplicants(),
      );
      await _pumpScreen(
        tester,
        repository: repository,
        size: const Size(1280, 900),
      );

      expect(find.text('Candidate 1'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('tablet (960x800) renders with no overflow', (tester) async {
      final repository = _FakeApplicationRepository(
        listResult: severalApplicants(),
      );
      await _pumpScreen(
        tester,
        repository: repository,
        size: const Size(960, 800),
      );

      expect(tester.takeException(), isNull);
    });

    testWidgets('narrow tablet (700x900) renders with no overflow', (
      tester,
    ) async {
      final repository = _FakeApplicationRepository(
        listResult: severalApplicants(),
      );
      await _pumpScreen(
        tester,
        repository: repository,
        size: const Size(700, 900),
      );

      expect(tester.takeException(), isNull);
    });

    testWidgets('mobile 375 renders with no overflow', (tester) async {
      final repository = _FakeApplicationRepository(
        listResult: severalApplicants(),
      );
      await _pumpScreen(
        tester,
        repository: repository,
        size: const Size(375, 812),
      );

      expect(tester.takeException(), isNull);
    });

    testWidgets('mobile 390 renders with no overflow', (tester) async {
      final repository = _FakeApplicationRepository(
        listResult: severalApplicants(),
      );
      await _pumpScreen(
        tester,
        repository: repository,
        size: const Size(390, 844),
      );

      expect(tester.takeException(), isNull);
    });

    testWidgets('mobile 430 renders with no overflow', (tester) async {
      final repository = _FakeApplicationRepository(
        listResult: severalApplicants(),
      );
      await _pumpScreen(
        tester,
        repository: repository,
        size: const Size(430, 932),
      );

      expect(tester.takeException(), isNull);
    });
  });
}
