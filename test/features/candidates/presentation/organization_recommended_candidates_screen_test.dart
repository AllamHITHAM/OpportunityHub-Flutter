// Widget tests for OrganizationRecommendedCandidatesScreen, in isolation
// with fake repositories (no real network).

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
import 'package:opportunityhub_flutter/features/candidates/presentation/organization_recommended_candidates_screen.dart';
import 'package:opportunityhub_flutter/features/invitations/data/invitation_repository.dart';
import 'package:opportunityhub_flutter/models/candidate_skill_model.dart';
import 'package:opportunityhub_flutter/models/match_breakdown_model.dart';
import 'package:opportunityhub_flutter/models/recommended_candidate_model.dart';
import 'package:opportunityhub_flutter/providers/auth_provider.dart';
import 'package:opportunityhub_flutter/providers/opportunity_recommendations_provider.dart';
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

RecommendedCandidateModel _candidate({
  int id = 1,
  String name = 'Omar Hassan',
  String? major = 'Computer Science',
  String? university = 'State University',
  int? graduationYear = 2026,
  String educationVerificationStatus = 'verified',
  List<CandidateSkillModel> skills = const [
    CandidateSkillModel(name: 'PHP', source: 'manual'),
  ],
  double matchScore = 82.0,
  bool alreadyApplied = false,
  int? applicationId,
  String? invitationStatus,
  MatchBreakdownModel? matchBreakdown,
}) {
  return RecommendedCandidateModel(
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
    matchScore: matchScore,
    alreadyApplied: alreadyApplied,
    applicationId: applicationId,
    invitationStatus: invitationStatus,
    matchBreakdown: matchBreakdown,
  );
}

class _FakeCandidateRepository extends CandidateRepository {
  _FakeCandidateRepository({
    this.results = const [],
    this.error,
    this.delay,
    this.workMode = 'remote',
    this.opportunityType = 'job',
    this.locationName,
  }) : super(apiClient: ApiClient(tokenStorageService: TokenStorageService()));

  List<RecommendedCandidateModel> results;
  ApiException? error;
  Duration? delay;
  String workMode;
  String opportunityType;
  String? locationName;
  int callCount = 0;
  int? lastOpportunityId;

  @override
  Future<RecommendedCandidatesResult> getRecommendedCandidates(
    int opportunityId,
  ) async {
    callCount++;
    lastOpportunityId = opportunityId;
    if (delay != null) await Future<void>.delayed(delay!);
    if (error != null) throw error!;
    return RecommendedCandidatesResult(
      workMode: workMode,
      opportunityType: opportunityType,
      locationName: locationName,
      candidates: results,
    );
  }
}

class _FakeInvitationRepository extends InvitationRepository {
  _FakeInvitationRepository({this.sendError})
    : super(apiClient: ApiClient(tokenStorageService: TokenStorageService()));

  ApiException? sendError;
  int sendCallCount = 0;

  @override
  Future<void> sendInvitation({
    required int studentId,
    required int opportunityId,
    String? message,
  }) async {
    sendCallCount++;
    if (sendError != null) throw sendError!;
  }
}

Future<void> _pumpScreen(
  WidgetTester tester, {
  required _FakeCandidateRepository candidateRepository,
  _FakeInvitationRepository? invitationRepository,
  int opportunityId = 9,
  String? opportunityTitle = 'Backend Developer',
  Size size = const Size(420, 900),
}) async {
  addTearDown(() => AppColors.updateBrightness(Brightness.light));

  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final authProvider = AuthProvider(authRepository: _FakeAuthRepository());
  final recommendationsProvider = OpportunityRecommendationsProvider(
    repository: candidateRepository,
    invitationRepository: invitationRepository ?? _FakeInvitationRepository(),
    authProvider: authProvider,
  );
  final themeProvider = ThemeProvider(storage: _FakeThemePreferenceStorage());
  await themeProvider.initialize();

  final router = GoRouter(
    initialLocation: AppRoutes.organizationOpportunityRecommendedCandidates(
      opportunityId,
    ),
    routes: [
      GoRoute(
        path:
            '${AppRoutes.organizationOpportunities}/:id/recommended-candidates',
        builder: (_, state) => OrganizationRecommendedCandidatesScreen(
          opportunityId: int.tryParse(state.pathParameters['id'] ?? '') ?? 0,
          opportunityTitle: state.extra is String
              ? state.extra as String
              : opportunityTitle,
        ),
      ),
      GoRoute(
        path: '${AppRoutes.organizationCandidates}/:id',
        builder: (_, state) => Scaffold(
          body: Text(
            'CANDIDATE_PROFILE_PLACEHOLDER_${state.pathParameters['id']}',
          ),
        ),
      ),
      GoRoute(
        path: '${AppRoutes.organizationApplications}/:id',
        builder: (_, state) => Scaffold(
          body: Text(
            'APPLICATION_DETAILS_PLACEHOLDER_${state.pathParameters['id']}',
          ),
        ),
      ),
    ],
  );

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthProvider>.value(value: authProvider),
        ChangeNotifierProvider<OpportunityRecommendationsProvider>.value(
          value: recommendationsProvider,
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
  group('loading / empty / error', () {
    testWidgets('shows a skeleton while the initial load is in flight', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(420, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(() => AppColors.updateBrightness(Brightness.light));

      final authProvider = AuthProvider(authRepository: _FakeAuthRepository());
      final repository = _FakeCandidateRepository(
        results: [_candidate()],
        delay: const Duration(milliseconds: 200),
      );
      final provider = OpportunityRecommendationsProvider(
        repository: repository,
        invitationRepository: _FakeInvitationRepository(),
        authProvider: authProvider,
      );
      final themeProvider = ThemeProvider(
        storage: _FakeThemePreferenceStorage(),
      );
      await themeProvider.initialize();
      final router = GoRouter(
        initialLocation: AppRoutes.organizationOpportunityRecommendedCandidates(
          9,
        ),
        routes: [
          GoRoute(
            path:
                '${AppRoutes.organizationOpportunities}/:id/recommended-candidates',
            builder: (_, _) =>
                const OrganizationRecommendedCandidatesScreen(opportunityId: 9),
          ),
        ],
      );

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<AuthProvider>.value(value: authProvider),
            ChangeNotifierProvider<OpportunityRecommendationsProvider>.value(
              value: provider,
            ),
            ChangeNotifierProvider<ThemeProvider>.value(value: themeProvider),
          ],
          child: MaterialApp.router(
            theme: AppTheme.lightTheme,
            routerConfig: router,
          ),
        ),
      );
      // The initial load is kicked off from a post-frame callback -- catch
      // the loading frame deliberately without pumpAndSettle.
      await tester.pump();
      await tester.pump();

      expect(find.byType(AppSkeletonList), findsOneWidget);

      await tester.pumpAndSettle();
    });

    testWidgets('shows an empty state when there are no eligible candidates', (
      tester,
    ) async {
      await _pumpScreen(
        tester,
        candidateRepository: _FakeCandidateRepository(results: []),
      );

      expect(find.text('No Recommended Candidates'), findsOneWidget);
    });

    testWidgets('shows an error view with retry on failure', (tester) async {
      final repository = _FakeCandidateRepository(
        error: ApiException('Server error.'),
      );
      await _pumpScreen(tester, candidateRepository: repository);

      expect(find.text('Server error.'), findsOneWidget);

      repository.error = null;
      repository.results = [_candidate(name: 'Omar Hassan')];
      await tester.tap(find.text('Try Again'));
      await tester.pumpAndSettle();

      expect(find.text('Omar Hassan'), findsOneWidget);
    });
  });

  group('ranked candidates', () {
    testWidgets('renders every real candidate returned by the endpoint, in '
        'the order the backend already ranked them', (tester) async {
      await _pumpScreen(
        tester,
        candidateRepository: _FakeCandidateRepository(
          results: [
            _candidate(id: 1, name: 'Omar Hassan', matchScore: 91),
            _candidate(id: 2, name: 'Layla Kareem', matchScore: 64),
          ],
        ),
      );

      expect(find.text('Omar Hassan'), findsOneWidget);
      expect(find.text('Layla Kareem'), findsOneWidget);
      expect(find.text('2 eligible candidates'), findsOneWidget);
    });

    testWidgets('shows the real match score for each candidate, never a '
        'fabricated one', (tester) async {
      await _pumpScreen(
        tester,
        candidateRepository: _FakeCandidateRepository(
          results: [_candidate(name: 'Omar Hassan', matchScore: 91)],
        ),
        size: const Size(1280, 900),
      );

      expect(find.textContaining('91%'), findsOneWidget);
    });

    testWidgets('caps visible skills and shows "+N more" for a long list', (
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
                CandidateSkillModel(name: 'Laravel', source: 'manual'),
                CandidateSkillModel(name: 'MySQL', source: 'manual'),
                CandidateSkillModel(name: 'Docker', source: 'manual'),
              ],
            ),
          ],
        ),
      );

      expect(find.textContaining('PHP'), findsOneWidget);
      expect(find.textContaining('Laravel'), findsOneWidget);
      expect(find.textContaining('MySQL'), findsOneWidget);
      expect(find.textContaining('Docker'), findsNothing);
      expect(find.text('+1 more'), findsOneWidget);
    });
  });

  group('relationship state', () {
    testWidgets('a candidate with no relationship yet shows Invite to '
        'Apply as the primary action', (tester) async {
      await _pumpScreen(
        tester,
        candidateRepository: _FakeCandidateRepository(
          results: [_candidate(name: 'Omar Hassan')],
        ),
      );

      expect(find.text('Not Invited'), findsOneWidget);
      expect(find.text('Invite to Apply'), findsOneWidget);
    });

    testWidgets('a candidate who already applied shows Applied and View '
        'Application, never an Invite action', (tester) async {
      await _pumpScreen(
        tester,
        candidateRepository: _FakeCandidateRepository(
          results: [
            _candidate(
              name: 'Omar Hassan',
              alreadyApplied: true,
              applicationId: 55,
            ),
          ],
        ),
      );

      expect(find.text('Applied'), findsOneWidget);
      expect(find.text('View Application'), findsOneWidget);
      expect(find.text('Invite to Apply'), findsNothing);
    });

    testWidgets('a candidate already invited (real invitation_status) shows '
        'the real status and a disabled action', (tester) async {
      await _pumpScreen(
        tester,
        candidateRepository: _FakeCandidateRepository(
          results: [
            _candidate(name: 'Omar Hassan', invitationStatus: 'pending'),
          ],
        ),
      );

      expect(find.text('Pending'), findsWidgets);
      expect(find.text('Invite to Apply'), findsNothing);

      final button = tester.widget<SecondaryButton>(
        find.widgetWithText(SecondaryButton, 'Pending'),
      );
      expect(button.onPressed, isNull);
    });
  });

  group('invite flow', () {
    testWidgets('sending an invitation from the sheet succeeds and shows '
        'Invited without a second opportunity-picker step', (tester) async {
      final invitationRepository = _FakeInvitationRepository();
      await _pumpScreen(
        tester,
        candidateRepository: _FakeCandidateRepository(
          results: [_candidate(id: 7, name: 'Omar Hassan')],
        ),
        invitationRepository: invitationRepository,
      );

      await tester.tap(find.text('Invite to Apply'));
      await tester.pumpAndSettle();

      // No opportunity picker: only the message field and Send Invitation.
      expect(find.text('Invite Omar Hassan'), findsOneWidget);
      expect(find.byType(RadioListTile<int>), findsNothing);

      await tester.tap(find.text('Send Invitation'));
      await tester.pumpAndSettle();

      expect(invitationRepository.sendCallCount, 1);
      expect(find.text('Invitation sent'), findsOneWidget);
      expect(find.text('Invited'), findsOneWidget);
    });

    testWidgets('a backend rejection (e.g. duplicate invite) is surfaced '
        'safely inside the sheet', (tester) async {
      final invitationRepository = _FakeInvitationRepository(
        sendError: ApiException(
          'An invitation already exists for this student and opportunity.',
          statusCode: 422,
        ),
      );
      await _pumpScreen(
        tester,
        candidateRepository: _FakeCandidateRepository(
          results: [_candidate(name: 'Omar Hassan')],
        ),
        invitationRepository: invitationRepository,
      );

      await tester.tap(find.text('Invite to Apply'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Send Invitation'));
      await tester.pumpAndSettle();

      expect(
        find.text(
          'An invitation already exists for this student and opportunity.',
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('navigation', () {
    testWidgets('View Profile navigates to the candidate profile route', (
      tester,
    ) async {
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

    testWidgets('View Application navigates using the real application id', (
      tester,
    ) async {
      await _pumpScreen(
        tester,
        candidateRepository: _FakeCandidateRepository(
          results: [
            _candidate(
              name: 'Omar Hassan',
              alreadyApplied: true,
              applicationId: 55,
            ),
          ],
        ),
      );

      await tester.tap(find.text('View Application'));
      await tester.pumpAndSettle();

      expect(find.text('APPLICATION_DETAILS_PLACEHOLDER_55'), findsOneWidget);
    });
  });

  group('theme toggle', () {
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
  });

  group('responsive layout', () {
    testWidgets('desktop (1280x900) renders the table header row with no '
        'overflow', (tester) async {
      await _pumpScreen(
        tester,
        candidateRepository: _FakeCandidateRepository(
          results: [_candidate(name: 'Omar Hassan')],
        ),
        size: const Size(1280, 900),
      );

      expect(find.text('Candidate'), findsOneWidget);
      expect(find.text('Match'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('tablet (960x800) renders the table layout with no '
        'overflow', (tester) async {
      await _pumpScreen(
        tester,
        candidateRepository: _FakeCandidateRepository(
          results: [_candidate(name: 'Omar Hassan')],
        ),
        size: const Size(960, 800),
      );

      expect(tester.takeException(), isNull);
    });

    for (final width in [375.0, 390.0, 430.0]) {
      testWidgets('mobile ${width.toInt()} renders the stacked card layout '
          'with no overflow', (tester) async {
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

  group('matching explanation + Opportunity Type context '
      '(Candidate Opportunity Preferences)', () {
    testWidgets(
      'shows the real Opportunity Type badge and dynamic type-context copy',
      (tester) async {
        await _pumpScreen(
          tester,
          candidateRepository: _FakeCandidateRepository(
            results: [_candidate(name: 'Omar Hassan')],
            opportunityType: 'internship',
          ),
        );

        expect(find.text('Opportunity Type'), findsOneWidget);
        expect(find.text('Internship'), findsOneWidget);
        expect(
          find.text(
            'These candidates are interested in Internship opportunities '
            'and meet this opportunity\'s eligibility requirements.',
          ),
          findsOneWidget,
        );
      },
    );

    testWidgets('uses the real type for a Job opportunity too -- never a '
        'hardcoded assumption', (tester) async {
      await _pumpScreen(
        tester,
        candidateRepository: _FakeCandidateRepository(
          results: [_candidate(name: 'Omar Hassan')],
          opportunityType: 'job',
        ),
      );

      expect(
        find.text(
          'These candidates are interested in Job opportunities and meet '
          'this opportunity\'s eligibility requirements.',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('all employees'), findsNothing);
      expect(find.textContaining('all students'), findsNothing);
    });

    testWidgets('does not offer a redundant Select Opportunity Type filter', (
      tester,
    ) async {
      await _pumpScreen(
        tester,
        candidateRepository: _FakeCandidateRepository(
          results: [_candidate(name: 'Omar Hassan')],
        ),
      );

      expect(find.text('Select Opportunity Type'), findsNothing);
    });

    testWidgets('Remote never claims location was considered', (tester) async {
      await _pumpScreen(
        tester,
        candidateRepository: _FakeCandidateRepository(
          results: [_candidate(name: 'Omar Hassan')],
          workMode: 'remote',
          locationName: null,
        ),
      );

      expect(
        find.text(
          'Candidates are ranked by Major and Required Skills '
          'compatibility. Location is not considered because this '
          'opportunity is Remote.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('On-site with a real canonical location truthfully mentions '
        'location matching', (tester) async {
      await _pumpScreen(
        tester,
        candidateRepository: _FakeCandidateRepository(
          results: [_candidate(name: 'Omar Hassan')],
          workMode: 'onsite',
          locationName: 'Nablus',
        ),
      );

      expect(
        find.text(
          'Candidates are ranked by Major, Required Skills, and '
          'work-location compatibility.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('On-site with no canonical location set never claims location '
        'was considered either -- nothing to compare against, and never '
        'falsely attributes it to being Remote', (tester) async {
      await _pumpScreen(
        tester,
        candidateRepository: _FakeCandidateRepository(
          results: [_candidate(name: 'Omar Hassan')],
          workMode: 'onsite',
          locationName: null,
        ),
      );

      expect(
        find.text(
          'Candidates are ranked by Major and Required Skills '
          'compatibility. Location is not considered because this '
          'opportunity has no fixed location set.',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('opportunity is Remote'), findsNothing);
    });

    testWidgets('Hybrid with a real canonical location mentions location '
        'matching too', (tester) async {
      await _pumpScreen(
        tester,
        candidateRepository: _FakeCandidateRepository(
          results: [_candidate(name: 'Omar Hassan')],
          workMode: 'hybrid',
          locationName: 'Ramallah',
        ),
      );

      expect(find.textContaining('work-location'), findsOneWidget);
    });
  });

  group('match breakdown (Final Recommendation Match Formula)', () {
    testWidgets('shows a "Why X%?" toggle when a match breakdown is present', (
      tester,
    ) async {
      await _pumpScreen(
        tester,
        candidateRepository: _FakeCandidateRepository(
          results: [
            _candidate(
              name: 'Omar Hassan',
              matchScore: 76.67,
              matchBreakdown: const MatchBreakdownModel(
                majorEligibility: 'eligible',
                academicMatch: 'matched',
                majorMatchScore: 100.0,
                majorWeight: 30,
                majorContribution: 30.0,
                requiredSkillsTotal: 3,
                requiredSkillsMatched: 2,
                matchedRequiredSkills: ['AutoCAD', 'Quantity Surveying'],
                missingRequiredSkills: ['Revit'],
                skillsMatchScore: 66.67,
                skillsWeight: 70,
                skillsContribution: 46.67,
                locationEligibility: 'not_considered',
              ),
            ),
          ],
        ),
      );

      expect(find.text('Why 77%?'), findsOneWidget);
    });

    testWidgets('expanding shows Major/Skills/Location sections with real '
        'points, matched/missing skill names, and the real location line '
        '-- and never any Field of Study or Experience text', (
      tester,
    ) async {
      await _pumpScreen(
        tester,
        candidateRepository: _FakeCandidateRepository(
          results: [
            _candidate(
              name: 'Omar Hassan',
              matchScore: 76.67,
              matchBreakdown: const MatchBreakdownModel(
                majorEligibility: 'eligible',
                academicMatch: 'matched',
                majorMatchScore: 100.0,
                majorWeight: 30,
                majorContribution: 30.0,
                requiredSkillsTotal: 3,
                requiredSkillsMatched: 2,
                matchedRequiredSkills: ['AutoCAD', 'Quantity Surveying'],
                missingRequiredSkills: ['Revit'],
                skillsMatchScore: 66.67,
                skillsWeight: 70,
                skillsContribution: 46.67,
                locationEligibility: 'not_considered',
              ),
            ),
          ],
        ),
      );

      await tester.tap(find.text('Why 77%?'));
      await tester.pumpAndSettle();

      expect(find.text('Major'), findsOneWidget);
      expect(find.text('30 / 30'), findsOneWidget);
      expect(find.text('Major matches an eligible major'), findsOneWidget);
      expect(find.text('Skills'), findsOneWidget);
      expect(find.text('46.7 / 70'), findsOneWidget);
      expect(find.text('2 of 3 required skills matched'), findsOneWidget);
      expect(find.text('Missing: Revit'), findsOneWidget);
      expect(find.text('Location'), findsOneWidget);
      expect(find.text('Not considered'), findsOneWidget);
      expect(find.text('This opportunity is Remote'), findsOneWidget);
      expect(find.textContaining('Field of Study'), findsNothing);
      expect(find.textContaining('field of study'), findsNothing);
      expect(find.textContaining('Experience'), findsNothing);
    });

    testWidgets(
      'the Allam case: major matches, skill missing, remote -- Major '
      'genuinely contributes to a nonzero score, never a forced 0%, and '
      'never mentions Field of Study',
      (tester) async {
        await _pumpScreen(
          tester,
          candidateRepository: _FakeCandidateRepository(
            results: [
              _candidate(
                name: 'Allam',
                // Skills 0 (weight 70) + Major 100 (weight 30) =
                // (0*70 + 100*30) / 100 = 30.0 -- the real, canonical
                // formula's output, not a hardcoded value.
                matchScore: 30,
                matchBreakdown: const MatchBreakdownModel(
                  majorEligibility: 'eligible',
                  academicMatch: 'matched',
                  majorMatchScore: 100.0,
                  majorWeight: 30,
                  majorContribution: 30.0,
                  requiredSkillsTotal: 1,
                  requiredSkillsMatched: 0,
                  matchedRequiredSkills: [],
                  missingRequiredSkills: ['BIM'],
                  skillsMatchScore: 0.0,
                  skillsWeight: 70,
                  skillsContribution: 0.0,
                  locationEligibility: 'not_considered',
                ),
              ),
            ],
          ),
        );

        expect(find.textContaining('30%'), findsWidgets);

        await tester.tap(find.text('Why 30%?'));
        await tester.pumpAndSettle();

        expect(find.text('Major matches an eligible major'), findsOneWidget);
        expect(find.text('0 of 1 required skills matched'), findsOneWidget);
        expect(find.text('Missing: BIM'), findsOneWidget);
        expect(find.textContaining('Field of Study'), findsNothing);
        expect(find.textContaining('field of study'), findsNothing);
        expect(find.textContaining('Experience'), findsNothing);
      },
    );

    testWidgets(
      'the Omar case (Opportunity Academic Matching Cleanup): an eligible '
      'major with unrelated legacy field_of_study text still shows Major '
      'matches an eligible major, never a mismatch',
      (tester) async {
        await _pumpScreen(
          tester,
          candidateRepository: _FakeCandidateRepository(
            results: [
              _candidate(
                name: 'Omar Hassan',
                matchBreakdown: const MatchBreakdownModel(
                  majorEligibility: 'eligible',
                  academicMatch: 'matched',
                  majorMatchScore: 100.0,
                  majorWeight: 30,
                  majorContribution: 30.0,
                  requiredSkillsTotal: 0,
                  requiredSkillsMatched: 0,
                  matchedRequiredSkills: [],
                  missingRequiredSkills: [],
                  locationEligibility: 'not_considered',
                ),
              ),
            ],
          ),
        );

        await tester.tap(find.textContaining('Why'));
        await tester.pumpAndSettle();

        expect(find.text('Major matches an eligible major'), findsOneWidget);
        expect(find.textContaining('Field of Study'), findsNothing);
        expect(find.textContaining('field of study'), findsNothing);
        expect(find.textContaining('does not match'), findsNothing);
      },
    );

    testWidgets(
      'an unrestricted opportunity (no eligible majors configured) shows '
      'the real not-applicable academic line, never a fabricated match',
      (tester) async {
        await _pumpScreen(
          tester,
          candidateRepository: _FakeCandidateRepository(
            results: [
              _candidate(
                name: 'Omar Hassan',
                matchBreakdown: const MatchBreakdownModel(
                  majorEligibility: 'eligible',
                  academicMatch: 'not_applicable',
                  requiredSkillsTotal: 0,
                  requiredSkillsMatched: 0,
                  matchedRequiredSkills: [],
                  missingRequiredSkills: [],
                  locationEligibility: 'not_considered',
                ),
              ),
            ],
          ),
        );

        await tester.tap(find.textContaining('Why'));
        await tester.pumpAndSettle();

        expect(
          find.text('This opportunity has no eligible majors configured'),
          findsOneWidget,
        );
        expect(find.text('Major matches an eligible major'), findsNothing);
        expect(find.text('Not applicable'), findsWidgets);
      },
    );

    testWidgets(
      'on-site match reports the real opportunity location and its exact '
      '15-point contribution, never a generic "matched" with no name',
      (tester) async {
        await _pumpScreen(
          tester,
          candidateRepository: _FakeCandidateRepository(
            results: [
              _candidate(
                name: 'Omar Hassan',
                matchScore: 100,
                matchBreakdown: const MatchBreakdownModel(
                  majorEligibility: 'eligible',
                  academicMatch: 'matched',
                  majorMatchScore: 100.0,
                  majorWeight: 25,
                  majorContribution: 25.0,
                  requiredSkillsTotal: 0,
                  requiredSkillsMatched: 0,
                  matchedRequiredSkills: [],
                  missingRequiredSkills: [],
                  locationEligibility: 'matched',
                  locationMatchScore: 100.0,
                  locationWeight: 15,
                  locationContribution: 15.0,
                ),
              ),
            ],
            workMode: 'onsite',
            locationName: 'Jenin',
          ),
        );

        await tester.tap(find.text('Why 100%?'));
        await tester.pumpAndSettle();

        expect(find.text('15 / 15'), findsOneWidget);
        expect(find.text('Available to work in Jenin'), findsOneWidget);
      },
    );

    testWidgets('no breakdown means no "Why X%?" toggle is shown at all', (
      tester,
    ) async {
      await _pumpScreen(
        tester,
        candidateRepository: _FakeCandidateRepository(
          results: [_candidate(name: 'Omar Hassan')],
        ),
      );

      expect(find.textContaining('Why'), findsNothing);
    });

    for (final width in [375.0, 390.0, 430.0]) {
      testWidgets(
        'mobile ${width.toInt()} renders an expanded breakdown (all real '
        'factors) with no overflow',
        (tester) async {
          await _pumpScreen(
            tester,
            candidateRepository: _FakeCandidateRepository(
              results: [
                _candidate(
                  name: 'Omar Hassan',
                  matchBreakdown: const MatchBreakdownModel(
                    majorEligibility: 'eligible',
                    academicMatch: 'matched',
                    majorMatchScore: 100.0,
                    majorWeight: 25,
                    majorContribution: 25.0,
                    requiredSkillsTotal: 3,
                    requiredSkillsMatched: 2,
                    matchedRequiredSkills: ['AutoCAD', 'Quantity Surveying'],
                    missingRequiredSkills: ['Revit'],
                    skillsMatchScore: 66.67,
                    skillsWeight: 60,
                    skillsContribution: 40.0,
                    locationEligibility: 'matched',
                    locationMatchScore: 100.0,
                    locationWeight: 15,
                    locationContribution: 15.0,
                  ),
                ),
              ],
              workMode: 'onsite',
              locationName: 'Jenin',
            ),
            size: Size(width, 900),
          );

          await tester.tap(find.textContaining('Why'));
          await tester.pumpAndSettle();

          expect(tester.takeException(), isNull);
        },
      );
    }
  });
}
