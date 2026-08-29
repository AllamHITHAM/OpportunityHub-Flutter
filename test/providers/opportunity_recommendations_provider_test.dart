// Direct unit tests for OpportunityRecommendationsProvider, using fake
// repositories (no real network). Mirrors the fake-repository-extends-real
// conventions used throughout this app's other provider tests (see
// candidate_search_provider_test.dart, which this provider's shape was
// itself modeled on).

import 'package:flutter_test/flutter_test.dart';

import 'package:opportunityhub_flutter/core/api/api_client.dart';
import 'package:opportunityhub_flutter/core/storage/token_storage_service.dart';
import 'package:opportunityhub_flutter/features/auth/data/auth_repository.dart';
import 'package:opportunityhub_flutter/features/candidates/data/candidate_repository.dart';
import 'package:opportunityhub_flutter/features/invitations/data/invitation_repository.dart';
import 'package:opportunityhub_flutter/models/recommended_candidate_model.dart';
import 'package:opportunityhub_flutter/providers/auth_provider.dart';
import 'package:opportunityhub_flutter/providers/opportunity_recommendations_provider.dart';

class _FakeAuthRepository extends AuthRepository {
  _FakeAuthRepository()
    : super(
        apiClient: ApiClient(tokenStorageService: TokenStorageService()),
        tokenStorageService: TokenStorageService(),
      );

  @override
  Future<String?> getSavedToken() async => null;
}

RecommendedCandidateModel _candidate({int id = 1, String name = 'Omar Hassan'}) {
  return RecommendedCandidateModel(
    id: id,
    name: name,
    university: 'State University',
    major: 'Computer Science',
    graduationYear: 2026,
    bio: null,
    educationVerificationStatus: 'verified',
    currentLocation: null,
    availableLocations: const [],
    skills: const [],
    matchScore: 80,
    alreadyApplied: false,
  );
}

class _FakeCandidateRepository extends CandidateRepository {
  _FakeCandidateRepository()
    : super(apiClient: ApiClient(tokenStorageService: TokenStorageService()));

  List<RecommendedCandidateModel> results = [];
  String workMode = 'remote';
  String opportunityType = 'job';
  String? locationName;
  ApiException? error;
  int callCount = 0;
  int? lastOpportunityId;

  @override
  Future<RecommendedCandidatesResult> getRecommendedCandidates(
    int opportunityId,
  ) async {
    callCount++;
    lastOpportunityId = opportunityId;
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
  _FakeInvitationRepository()
    : super(apiClient: ApiClient(tokenStorageService: TokenStorageService()));

  ApiException? sendError;
  Duration sendDelay = Duration.zero;
  int sendCallCount = 0;
  int? lastStudentId;
  int? lastOpportunityId;
  String? lastMessage;

  @override
  Future<void> sendInvitation({
    required int studentId,
    required int opportunityId,
    String? message,
  }) async {
    sendCallCount++;
    lastStudentId = studentId;
    lastOpportunityId = opportunityId;
    lastMessage = message;
    if (sendDelay > Duration.zero) await Future<void>.delayed(sendDelay);
    if (sendError != null) throw sendError!;
  }
}

void main() {
  late _FakeCandidateRepository candidateRepository;
  late _FakeInvitationRepository invitationRepository;
  late AuthProvider authProvider;
  late OpportunityRecommendationsProvider provider;

  setUp(() {
    candidateRepository = _FakeCandidateRepository();
    invitationRepository = _FakeInvitationRepository();
    authProvider = AuthProvider(authRepository: _FakeAuthRepository());
    provider = OpportunityRecommendationsProvider(
      repository: candidateRepository,
      invitationRepository: invitationRepository,
      authProvider: authProvider,
    );
  });

  group('loadForOpportunity', () {
    test('populates candidates and loadedOpportunityId on success', () async {
      candidateRepository.results = [_candidate()];

      await provider.loadForOpportunity(9);

      expect(provider.candidates, hasLength(1));
      expect(provider.loadedOpportunityId, 9);
      expect(provider.errorMessage, isNull);
      expect(provider.isLoading, isFalse);
      expect(candidateRepository.lastOpportunityId, 9);
    });

    test('sets errorMessage on failure, leaving loadedOpportunityId unset', () async {
      candidateRepository.error = ApiException('Server error.');

      await provider.loadForOpportunity(9);

      expect(provider.candidates, isEmpty);
      expect(provider.errorMessage, 'Server error.');
      expect(provider.loadedOpportunityId, isNull);
    });

    test('a repeat call for the same opportunity with results already '
        'loaded is not re-fetched unless forced', () async {
      candidateRepository.results = [_candidate()];
      await provider.loadForOpportunity(9);
      expect(candidateRepository.callCount, 1);

      await provider.loadForOpportunity(9);
      expect(candidateRepository.callCount, 1);

      await provider.loadForOpportunity(9, forceRefresh: true);
      expect(candidateRepository.callCount, 2);
    });

    test('switching to a different opportunity always re-fetches', () async {
      candidateRepository.results = [_candidate()];
      await provider.loadForOpportunity(9);
      await provider.loadForOpportunity(10);

      expect(candidateRepository.callCount, 2);
      expect(candidateRepository.lastOpportunityId, 10);
      expect(provider.loadedOpportunityId, 10);
    });

    test(
      'populates the real workMode/locationName context (Phase O8.2)',
      () async {
        candidateRepository
          ..results = [_candidate()]
          ..workMode = 'onsite'
          ..locationName = 'Nablus';

        await provider.loadForOpportunity(9);

        expect(provider.workMode, 'onsite');
        expect(provider.locationName, 'Nablus');
      },
    );

    test('a Remote opportunity never carries a location name', () async {
      candidateRepository
        ..results = [_candidate()]
        ..workMode = 'remote'
        ..locationName = null;

      await provider.loadForOpportunity(9);

      expect(provider.workMode, 'remote');
      expect(provider.locationName, isNull);
    });
  });

  group('sendInvitation', () {
    test('returns true and sets lastInvitedCandidateId on success', () async {
      final success = await provider.sendInvitation(
        studentId: 3,
        opportunityId: 9,
      );

      expect(success, isTrue);
      expect(provider.lastInvitedCandidateId, 3);
      expect(provider.inviteErrorMessage, isNull);
      expect(provider.isSendingInvite, isFalse);
      expect(invitationRepository.lastStudentId, 3);
      expect(invitationRepository.lastOpportunityId, 9);
    });

    test('forwards an optional message', () async {
      await provider.sendInvitation(
        studentId: 3,
        opportunityId: 9,
        message: 'Great fit!',
      );

      expect(invitationRepository.lastMessage, 'Great fit!');
    });

    test('returns false and sets inviteErrorMessage on failure, never '
        'lastInvitedCandidateId', () async {
      invitationRepository.sendError = ApiException(
        'An invitation already exists for this student and opportunity',
        statusCode: 409,
      );

      final success = await provider.sendInvitation(
        studentId: 3,
        opportunityId: 9,
      );

      expect(success, isFalse);
      expect(provider.lastInvitedCandidateId, isNull);
      expect(
        provider.inviteErrorMessage,
        'An invitation already exists for this student and opportunity',
      );
    });

    test('a duplicate submission while one is in flight is ignored', () async {
      invitationRepository.sendDelay = const Duration(milliseconds: 50);

      final results = await Future.wait([
        provider.sendInvitation(studentId: 3, opportunityId: 9),
        provider.sendInvitation(studentId: 3, opportunityId: 9),
      ]);

      expect(invitationRepository.sendCallCount, 1);
      expect(results.where((success) => success), hasLength(1));
    });

    test('a new attempt clears the previous error/success state', () async {
      invitationRepository.sendError = ApiException('Server error.');
      await provider.sendInvitation(studentId: 3, opportunityId: 9);
      expect(provider.inviteErrorMessage, isNotNull);

      invitationRepository.sendError = null;
      await provider.sendInvitation(studentId: 3, opportunityId: 9);

      expect(provider.inviteErrorMessage, isNull);
      expect(provider.lastInvitedCandidateId, 3);
    });
  });

  test('reset clears every field', () async {
    candidateRepository
      ..results = [_candidate()]
      ..workMode = 'onsite'
      ..locationName = 'Nablus';
    await provider.loadForOpportunity(9);
    await provider.sendInvitation(studentId: 3, opportunityId: 9);

    provider.reset();

    expect(provider.candidates, isEmpty);
    expect(provider.loadedOpportunityId, isNull);
    expect(provider.workMode, isNull);
    expect(provider.locationName, isNull);
    expect(provider.errorMessage, isNull);
    expect(provider.inviteErrorMessage, isNull);
    expect(provider.lastInvitedCandidateId, isNull);
  });
}
