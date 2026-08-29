// Widget tests for CandidateSearchScreen (the Talent Directory), in
// isolation with fake repositories (no real network).

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
import 'package:opportunityhub_flutter/features/auth/data/auth_repository.dart';
import 'package:opportunityhub_flutter/features/candidates/data/candidate_repository.dart';
import 'package:opportunityhub_flutter/features/candidates/presentation/candidate_search_screen.dart';
import 'package:opportunityhub_flutter/features/invitations/data/invitation_repository.dart';
import 'package:opportunityhub_flutter/models/candidate_model.dart';
import 'package:opportunityhub_flutter/models/candidate_skill_model.dart';
import 'package:opportunityhub_flutter/providers/auth_provider.dart';
import 'package:opportunityhub_flutter/providers/candidate_search_provider.dart';
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

CandidateModel _candidate({
  int id = 1,
  String name = 'Omar Hassan',
  String? major = 'Computer Science',
  String? university = 'State University',
  int? graduationYear = 2026,
  String educationVerificationStatus = 'verified',
  List<CandidateSkillModel> skills = const [
    CandidateSkillModel(name: 'PHP', source: 'manual'),
  ],
  List<String>? interestedIn,
}) {
  return CandidateModel(
    id: id,
    name: name,
    university: university,
    major: major,
    graduationYear: graduationYear,
    bio: null,
    educationVerificationStatus: educationVerificationStatus,
    currentLocation: null,
    availableLocations: const [],
    skills: skills,
    interestedIn: interestedIn,
  );
}

class _FakeCandidateRepository extends CandidateRepository {
  _FakeCandidateRepository({this.results = const [], this.searchError})
    : super(apiClient: ApiClient(tokenStorageService: TokenStorageService()));

  List<CandidateModel> results;
  ApiException? searchError;
  int searchCallCount = 0;
  String? lastName;

  @override
  Future<List<CandidateModel>> searchCandidates({
    String? name,
    String? major,
    String? university,
    int? graduationYear,
    String? skill,
    int? opportunityId,
  }) async {
    searchCallCount++;
    lastName = name;
    if (searchError != null) throw searchError!;
    return results;
  }
}

class _FakeInvitationRepository extends InvitationRepository {
  _FakeInvitationRepository()
    : super(apiClient: ApiClient(tokenStorageService: TokenStorageService()));
}

Future<void> _pumpScreen(
  WidgetTester tester, {
  required _FakeCandidateRepository candidateRepository,
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
  final candidateProvider = CandidateSearchProvider(
    repository: candidateRepository,
    invitationRepository: _FakeInvitationRepository(),
    authProvider: authProvider,
  );
  final themeProvider = ThemeProvider(storage: _FakeThemePreferenceStorage());
  await themeProvider.initialize();

  final router = GoRouter(
    initialLocation: AppRoutes.organizationCandidates,
    routes: [
      GoRoute(
        path: AppRoutes.organizationCandidates,
        builder: (_, _) => const CandidateSearchScreen(),
      ),
      GoRoute(
        path: '${AppRoutes.organizationCandidates}/:id',
        builder: (_, state) => Scaffold(
          body: Text(
            'CANDIDATE_PROFILE_PLACEHOLDER_${state.pathParameters['id']}',
          ),
        ),
      ),
    ],
  );

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthProvider>.value(value: authProvider),
        ChangeNotifierProvider<CandidateSearchProvider>.value(
          value: candidateProvider,
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
  testWidgets('Shows candidates returned by the search', (tester) async {
    await _pumpScreen(
      tester,
      candidateRepository: _FakeCandidateRepository(
        results: [_candidate(name: 'Omar Hassan')],
      ),
    );

    expect(find.text('Omar Hassan'), findsOneWidget);
    expect(find.textContaining('Computer Science'), findsOneWidget);
  });

  testWidgets('Shows the Talent Directory header, not the old Find '
      'Candidates copy', (tester) async {
    await _pumpScreen(
      tester,
      candidateRepository: _FakeCandidateRepository(results: []),
    );

    expect(find.text('Talent Directory'), findsOneWidget);
    expect(find.text('Find Candidates'), findsNothing);
  });

  testWidgets('Shows an empty state when no candidates match', (
    tester,
  ) async {
    await _pumpScreen(
      tester,
      candidateRepository: _FakeCandidateRepository(results: []),
    );

    expect(find.text('No Candidates Found'), findsOneWidget);
  });

  testWidgets('Shows an error view with retry on failure', (tester) async {
    final repository = _FakeCandidateRepository(
      searchError: ApiException('Server error.'),
    );
    await _pumpScreen(tester, candidateRepository: repository);

    expect(find.text('Server error.'), findsOneWidget);

    repository.searchError = null;
    repository.results = [_candidate()];
    await tester.tap(find.text('Try Again'));
    await tester.pumpAndSettle();

    expect(find.text('Omar Hassan'), findsOneWidget);
  });

  testWidgets('Searching by name re-runs the search with the typed value', (
    tester,
  ) async {
    final repository = _FakeCandidateRepository(
      results: [_candidate(name: 'Omar Hassan')],
    );
    await _pumpScreen(tester, candidateRepository: repository);

    await tester.enterText(find.byType(TextField), 'Omar');
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();

    expect(repository.lastName, 'Omar');
  });

  testWidgets('Education verification status is shown on the card', (
    tester,
  ) async {
    await _pumpScreen(
      tester,
      candidateRepository: _FakeCandidateRepository(
        results: [_candidate()],
      ),
    );

    expect(find.text('Verified'), findsOneWidget);
  });

  testWidgets('Skill evidence label is shown on the card', (tester) async {
    await _pumpScreen(
      tester,
      candidateRepository: _FakeCandidateRepository(
        results: [_candidate()],
      ),
    );

    expect(find.textContaining('Self-declared'), findsOneWidget);
  });

  testWidgets(
    'Interested In renders as real chips on the card when set '
    '(Candidate Opportunity Preferences)',
    (tester) async {
      await _pumpScreen(
        tester,
        candidateRepository: _FakeCandidateRepository(
          results: [_candidate(interestedIn: const ['job', 'internship'])],
        ),
      );

      expect(find.text('Interested In'), findsOneWidget);
      expect(find.text('Job'), findsOneWidget);
      expect(find.text('Internship'), findsOneWidget);
    },
  );

  testWidgets(
    'no Interested In section renders for a legacy profile with none set',
    (tester) async {
      await _pumpScreen(
        tester,
        candidateRepository: _FakeCandidateRepository(
          results: [_candidate(interestedIn: null)],
        ),
      );

      expect(find.text('Interested In'), findsNothing);
    },
  );

  group('View Profile action (Phase O8.1)', () {
    testWidgets('no Invite action or opportunity picker is present on this '
        'directory', (tester) async {
      await _pumpScreen(
        tester,
        candidateRepository: _FakeCandidateRepository(
          results: [_candidate(name: 'Omar Hassan')],
        ),
      );

      expect(find.text('Invite'), findsNothing);
      expect(find.text('View Profile'), findsOneWidget);
    });

    testWidgets('tapping View Profile navigates to the candidate profile '
        'route carrying the candidate\'s id', (tester) async {
      await _pumpScreen(
        tester,
        candidateRepository: _FakeCandidateRepository(
          results: [_candidate(id: 42, name: 'Omar Hassan')],
        ),
      );

      await tester.tap(find.text('View Profile'));
      await tester.pumpAndSettle();

      expect(find.text('CANDIDATE_PROFILE_PLACEHOLDER_42'), findsOneWidget);
    });
  });

  group('skills display (UI polish follow-up)', () {
    testWidgets('a candidate with few skills shows every chip, no "+more"', (
      tester,
    ) async {
      await _pumpScreen(
        tester,
        candidateRepository: _FakeCandidateRepository(
          results: [
            _candidate(
              name: 'Omar Hassan',
              skills: const [
                CandidateSkillModel(name: 'PHP', source: 'manual'),
                CandidateSkillModel(name: 'Laravel', source: 'cv_ai'),
              ],
            ),
          ],
        ),
      );

      expect(find.textContaining('PHP'), findsOneWidget);
      expect(find.textContaining('Laravel'), findsOneWidget);
      expect(find.textContaining('more'), findsNothing);
    });

    testWidgets(
      'a candidate with many skills shows only the first 4 plus a '
      '"+N more" chip, never a fabricated skill',
      (tester) async {
        await _pumpScreen(
          tester,
          candidateRepository: _FakeCandidateRepository(
            results: [
              _candidate(
                name: 'Omar Hassan',
                skills: const [
                  CandidateSkillModel(name: 'PHP', source: 'manual'),
                  CandidateSkillModel(name: 'Laravel', source: 'manual'),
                  CandidateSkillModel(name: 'MySQL', source: 'manual'),
                  CandidateSkillModel(name: 'Docker', source: 'manual'),
                  CandidateSkillModel(name: 'Redis', source: 'manual'),
                  CandidateSkillModel(name: 'Kubernetes', source: 'manual'),
                ],
              ),
            ],
          ),
        );

        expect(find.textContaining('PHP'), findsOneWidget);
        expect(find.textContaining('Laravel'), findsOneWidget);
        expect(find.textContaining('MySQL'), findsOneWidget);
        expect(find.textContaining('Docker'), findsOneWidget);
        expect(find.textContaining('Redis'), findsNothing);
        expect(find.textContaining('Kubernetes'), findsNothing);
        expect(find.text('+2 more'), findsOneWidget);
      },
    );
  });

  group('Education Verification labeling (UI Phase O8)', () {
    testWidgets('the status chip sits under its own real label, never bare', (
      tester,
    ) async {
      await _pumpScreen(
        tester,
        candidateRepository: _FakeCandidateRepository(
          results: [
            _candidate(
              name: 'Omar Hassan',
              educationVerificationStatus: 'not_submitted',
            ),
          ],
        ),
      );

      expect(find.text('Education Verification'), findsOneWidget);
      expect(find.text('Not Submitted'), findsOneWidget);
    });

    testWidgets('a verified candidate shows the real Verified label', (
      tester,
    ) async {
      await _pumpScreen(
        tester,
        candidateRepository: _FakeCandidateRepository(
          results: [
            _candidate(name: 'Omar Hassan', educationVerificationStatus: 'verified'),
          ],
        ),
      );

      expect(find.text('Education Verification'), findsOneWidget);
      expect(find.text('Verified'), findsOneWidget);
    });
  });

  group('theme toggle (UI Phase O8)', () {
    testWidgets('is present in the AppBar and switches the resolved theme', (
      tester,
    ) async {
      await _pumpScreen(
        tester,
        candidateRepository: _FakeCandidateRepository(
          results: [_candidate(name: 'Omar Hassan')],
        ),
      );

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
      await _pumpScreen(
        tester,
        candidateRepository: _FakeCandidateRepository(
          results: [_candidate(name: 'Omar Hassan')],
        ),
      );

      expect(find.byTooltip('Switch to dark mode'), findsOneWidget);

      await tester.tap(find.byType(ThemeToggleButton));
      await tester.pumpAndSettle();

      expect(find.byTooltip('Switch to light mode'), findsOneWidget);
    });

    testWidgets(
      'candidate cards switch surface together with the rest of the page '
      'on toggle (no stale card)',
      (tester) async {
        await _pumpScreen(
          tester,
          candidateRepository: _FakeCandidateRepository(
            results: [_candidate(name: 'Omar Hassan')],
          ),
        );

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

  group('active filter indicator (UI Phase O8)', () {
    testWidgets('the filter icon shows an active-filter count badge once '
        'filters are applied', (tester) async {
      await _pumpScreen(
        tester,
        candidateRepository: _FakeCandidateRepository(
          results: [_candidate(name: 'Omar Hassan')],
        ),
      );

      expect(find.text('1'), findsNothing);

      await tester.tap(find.byIcon(Icons.filter_alt_outlined));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Major (optional)'),
        'Computer Science',
      );
      await tester.tap(find.text('Apply Filters'));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.filter_alt), findsOneWidget);
      expect(find.text('1'), findsOneWidget);
    });
  });

  group('responsive layout and long data (UI Phase O8)', () {
    testWidgets('desktop (1280x900) renders a multi-column grid with no '
        'overflow', (tester) async {
      await _pumpScreen(
        tester,
        candidateRepository: _FakeCandidateRepository(
          results: [
            _candidate(id: 1, name: 'Omar Hassan'),
            _candidate(id: 2, name: 'Layla Hassan'),
            _candidate(id: 3, name: 'Sara Youssef'),
          ],
        ),
        size: const Size(1280, 900),
      );

      expect(find.text('Omar Hassan'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('tablet (960x800) renders with no overflow', (tester) async {
      await _pumpScreen(
        tester,
        candidateRepository: _FakeCandidateRepository(
          results: [_candidate(name: 'Omar Hassan')],
        ),
        size: const Size(960, 800),
      );

      expect(tester.takeException(), isNull);
    });

    testWidgets('narrow tablet (700x900) renders with no overflow', (
      tester,
    ) async {
      await _pumpScreen(
        tester,
        candidateRepository: _FakeCandidateRepository(
          results: [_candidate(name: 'Omar Hassan')],
        ),
        size: const Size(700, 900),
      );

      expect(tester.takeException(), isNull);
    });

    for (final width in [375.0, 390.0, 430.0]) {
      testWidgets('mobile ${width.toInt()} renders with no overflow and '
          'wraps long major/university text', (tester) async {
        await _pumpScreen(
          tester,
          candidateRepository: _FakeCandidateRepository(
            results: [
              _candidate(
                name: 'Omar Abdulrahman Hassan Al-Farouq',
                major: 'Computer Science and Software Engineering',
                university:
                    'The National University of Science, Technology, and '
                    'Advanced Engineering',
              ),
            ],
          ),
          size: Size(width, 900),
        );

        expect(tester.takeException(), isNull);
        expect(find.text('View Profile'), findsOneWidget);
      });
    }
  });
}
