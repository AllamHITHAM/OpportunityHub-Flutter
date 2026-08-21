// Widget tests for CandidateSearchScreen, in isolation with fake
// repositories (no real network).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:opportunityhub_flutter/core/api/api_client.dart';
import 'package:opportunityhub_flutter/core/storage/token_storage_service.dart';
import 'package:opportunityhub_flutter/core/theme/app_theme.dart';
import 'package:opportunityhub_flutter/features/auth/data/auth_repository.dart';
import 'package:opportunityhub_flutter/features/candidates/data/candidate_repository.dart';
import 'package:opportunityhub_flutter/features/candidates/presentation/candidate_search_screen.dart';
import 'package:opportunityhub_flutter/features/invitations/data/invitation_repository.dart';
import 'package:opportunityhub_flutter/features/opportunities/data/opportunity_repository.dart';
import 'package:opportunityhub_flutter/models/candidate_model.dart';
import 'package:opportunityhub_flutter/models/candidate_skill_model.dart';
import 'package:opportunityhub_flutter/models/opportunity_model.dart';
import 'package:opportunityhub_flutter/providers/auth_provider.dart';
import 'package:opportunityhub_flutter/providers/candidate_search_provider.dart';
import 'package:opportunityhub_flutter/providers/organization_opportunities_provider.dart';

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
  bool? alreadyApplied,
}) {
  return CandidateModel(
    id: id,
    name: name,
    university: 'State University',
    major: major,
    graduationYear: 2026,
    educationVerificationStatus: 'verified',
    skills: const [
      CandidateSkillModel(name: 'PHP', source: 'manual'),
    ],
    alreadyApplied: alreadyApplied,
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

  int sendCallCount = 0;
  ApiException? sendError;

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

class _FakeOpportunityRepository extends OpportunityRepository {
  _FakeOpportunityRepository({List<OpportunityModel>? opportunities})
    : opportunities =
          opportunities ?? [OpportunityModel.fromJson(_opportunityJson())],
      super(apiClient: ApiClient(tokenStorageService: TokenStorageService()));

  final List<OpportunityModel> opportunities;

  @override
  Future<List<OpportunityModel>> getOpportunities() async => opportunities;
}

Map<String, dynamic> _opportunityJson({
  int id = 9,
  String title = 'Backend Developer',
  String? fieldOfStudy,
  List<String> eligibleMajors = const [],
}) {
  return {
    'id': id,
    'title': title,
    'description': 'Great role.',
    'opportunity_type': 'job',
    'employment_type': 'full_time',
    'work_mode': 'remote',
    'experience_level': 'junior',
    'education_level': null,
    'field_of_study': fieldOfStudy,
    'location': null,
    'salary_min': null,
    'salary_max': null,
    'application_deadline': null,
    'positions_available': 1,
    'status': 'open',
    'created_at': '2026-07-01T10:00:00.000000Z',
    'updated_at': '2026-07-01T10:00:00.000000Z',
    'eligible_majors': eligibleMajors,
  };
}

Future<void> _pumpScreen(
  WidgetTester tester, {
  required _FakeCandidateRepository candidateRepository,
  _FakeInvitationRepository? invitationRepository,
  _FakeOpportunityRepository? opportunityRepository,
}) async {
  final authProvider = AuthProvider(authRepository: _FakeAuthRepository());
  final candidateProvider = CandidateSearchProvider(
    repository: candidateRepository,
    invitationRepository: invitationRepository ?? _FakeInvitationRepository(),
    authProvider: authProvider,
  );
  final opportunitiesProvider = OrganizationOpportunitiesProvider(
    repository: opportunityRepository ?? _FakeOpportunityRepository(),
    authProvider: authProvider,
  );

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthProvider>.value(value: authProvider),
        ChangeNotifierProvider<CandidateSearchProvider>.value(
          value: candidateProvider,
        ),
        ChangeNotifierProvider<OrganizationOpportunitiesProvider>.value(
          value: opportunitiesProvider,
        ),
      ],
      child: MaterialApp(
        theme: AppTheme.lightTheme,
        home: const CandidateSearchScreen(),
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

  testWidgets('Tapping Invite opens the invite sheet with the organization\'s '
      'open opportunities', (tester) async {
    await _pumpScreen(
      tester,
      candidateRepository: _FakeCandidateRepository(
        results: [_candidate(name: 'Omar Hassan')],
      ),
    );

    await tester.tap(find.text('Invite'));
    await tester.pumpAndSettle();

    expect(find.text('Invite Omar Hassan'), findsOneWidget);
    expect(find.text('Backend Developer'), findsOneWidget);
  });

  testWidgets('Sending an invitation from the sheet succeeds', (
    tester,
  ) async {
    final invitationRepository = _FakeInvitationRepository();
    await _pumpScreen(
      tester,
      candidateRepository: _FakeCandidateRepository(
        results: [_candidate(name: 'Omar Hassan')],
      ),
      invitationRepository: invitationRepository,
    );

    await tester.tap(find.text('Invite'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Backend Developer'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Send Invitation'));
    await tester.pumpAndSettle();

    expect(invitationRepository.sendCallCount, 1);
    expect(find.text('Invitation sent'), findsOneWidget);
  });

  testWidgets(
    'A candidate already applied to the opportunity cannot be invited',
    (tester) async {
      await _pumpScreen(
        tester,
        candidateRepository: _FakeCandidateRepository(
          results: [_candidate(name: 'Omar Hassan', alreadyApplied: true)],
        ),
      );

      final inviteButton = tester.widget<OutlinedButton>(
        find.ancestor(
          of: find.text('Invite'),
          matching: find.byType(OutlinedButton),
        ),
      );
      expect(inviteButton.onPressed, isNull);
      expect(find.text('Already applied to this opportunity'), findsOneWidget);
    },
  );

  group('Invite sheet eligibility (Phase 8B-3.2)', () {
    testWidgets('An eligible opportunity is selectable', (tester) async {
      final opportunityRepository = _FakeOpportunityRepository(
        opportunities: [
          OpportunityModel.fromJson(
            _opportunityJson(
              id: 1,
              title: 'Backend Developer',
              eligibleMajors: ['Computer Science'],
            ),
          ),
        ],
      );
      await _pumpScreen(
        tester,
        candidateRepository: _FakeCandidateRepository(
          results: [_candidate(name: 'Omar Hassan', major: 'Computer Science')],
        ),
        opportunityRepository: opportunityRepository,
      );

      await tester.tap(find.text('Invite'));
      await tester.pumpAndSettle();

      final tile = tester.widget<RadioListTile<int>>(
        find.widgetWithText(RadioListTile<int>, 'Backend Developer'),
      );
      expect(tile.enabled, isTrue);
    });

    testWidgets(
      'An ineligible opportunity is disabled with an explanation',
      (tester) async {
        final opportunityRepository = _FakeOpportunityRepository(
          opportunities: [
            OpportunityModel.fromJson(
              _opportunityJson(
                id: 1,
                title: 'Civil Engineering Internship',
                eligibleMajors: ['Civil Engineering'],
              ),
            ),
          ],
        );
        await _pumpScreen(
          tester,
          candidateRepository: _FakeCandidateRepository(
            results: [
              _candidate(name: 'Omar Hassan', major: 'Computer Science'),
            ],
          ),
          opportunityRepository: opportunityRepository,
        );

        await tester.tap(find.text('Invite'));
        await tester.pumpAndSettle();

        final tile = tester.widget<RadioListTile<int>>(
          find.widgetWithText(
            RadioListTile<int>,
            'Civil Engineering Internship',
          ),
        );
        expect(tile.enabled, isFalse);
        expect(
          find.text('Not eligible for Omar Hassan\'s major'),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'A mix of eligible and ineligible opportunities are shown correctly',
      (tester) async {
        final opportunityRepository = _FakeOpportunityRepository(
          opportunities: [
            OpportunityModel.fromJson(
              _opportunityJson(
                id: 1,
                title: 'Software Role',
                eligibleMajors: ['Computer Science'],
              ),
            ),
            OpportunityModel.fromJson(
              _opportunityJson(
                id: 2,
                title: 'Civil Role',
                eligibleMajors: ['Civil Engineering'],
              ),
            ),
          ],
        );
        await _pumpScreen(
          tester,
          candidateRepository: _FakeCandidateRepository(
            results: [
              _candidate(name: 'Omar Hassan', major: 'Computer Science'),
            ],
          ),
          opportunityRepository: opportunityRepository,
        );

        await tester.tap(find.text('Invite'));
        await tester.pumpAndSettle();

        final softwareTile = tester.widget<RadioListTile<int>>(
          find.widgetWithText(RadioListTile<int>, 'Software Role'),
        );
        final civilTile = tester.widget<RadioListTile<int>>(
          find.widgetWithText(RadioListTile<int>, 'Civil Role'),
        );
        expect(softwareTile.enabled, isTrue);
        expect(civilTile.enabled, isFalse);
      },
    );

    testWidgets(
      'A backend rejection is still handled safely even if the UI missed it',
      (tester) async {
        // Simulates the backend guard catching what the client-side
        // eligibility check didn't (e.g. stale Opportunity data) --
        // proves the UI never trusts itself alone.
        final invitationRepository = _FakeInvitationRepository()
          ..sendError = ApiException(
            'Student major is not eligible for this opportunity',
            statusCode: 422,
          );
        final opportunityRepository = _FakeOpportunityRepository(
          opportunities: [
            OpportunityModel.fromJson(
              _opportunityJson(id: 1, title: 'Backend Developer'),
            ),
          ],
        );
        await _pumpScreen(
          tester,
          candidateRepository: _FakeCandidateRepository(
            results: [_candidate(name: 'Omar Hassan')],
          ),
          invitationRepository: invitationRepository,
          opportunityRepository: opportunityRepository,
        );

        await tester.tap(find.text('Invite'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Backend Developer'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Send Invitation'));
        await tester.pumpAndSettle();

        expect(
          find.text('Student major is not eligible for this opportunity'),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      },
    );
  });
}
