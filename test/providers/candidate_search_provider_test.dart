// Direct unit tests for CandidateSearchProvider, using fake repositories
// (no real network). Mirrors the fake-repository-extends-real conventions
// used throughout this app's other provider tests.

import 'package:flutter_test/flutter_test.dart';

import 'package:opportunityhub_flutter/core/api/api_client.dart';
import 'package:opportunityhub_flutter/core/storage/token_storage_service.dart';
import 'package:opportunityhub_flutter/features/auth/data/auth_repository.dart';
import 'package:opportunityhub_flutter/features/candidates/data/candidate_repository.dart';
import 'package:opportunityhub_flutter/features/invitations/data/invitation_repository.dart';
import 'package:opportunityhub_flutter/models/candidate_model.dart';
import 'package:opportunityhub_flutter/providers/auth_provider.dart';
import 'package:opportunityhub_flutter/providers/candidate_search_provider.dart';

class _FakeAuthRepository extends AuthRepository {
  _FakeAuthRepository()
    : super(
        apiClient: ApiClient(tokenStorageService: TokenStorageService()),
        tokenStorageService: TokenStorageService(),
      );

  @override
  Future<String?> getSavedToken() async => null;
}

CandidateModel _candidate({int id = 1, String name = 'Omar Hassan'}) {
  return CandidateModel(
    id: id,
    name: name,
    university: 'State University',
    major: 'Computer Science',
    graduationYear: 2026,
    educationVerificationStatus: 'verified',
    skills: const [],
  );
}

class _FakeCandidateRepository extends CandidateRepository {
  _FakeCandidateRepository()
    : super(apiClient: ApiClient(tokenStorageService: TokenStorageService()));

  List<CandidateModel> results = [];
  ApiException? searchError;
  int searchCallCount = 0;
  String? lastName;
  int? lastOpportunityId;

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
    lastOpportunityId = opportunityId;
    if (searchError != null) throw searchError!;
    return results;
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
  late CandidateSearchProvider provider;

  setUp(() {
    candidateRepository = _FakeCandidateRepository();
    invitationRepository = _FakeInvitationRepository();
    authProvider = AuthProvider(authRepository: _FakeAuthRepository());
    provider = CandidateSearchProvider(
      repository: candidateRepository,
      invitationRepository: invitationRepository,
      authProvider: authProvider,
    );
  });

  group('search', () {
    test('populates candidates on success', () async {
      candidateRepository.results = [_candidate()];

      await provider.search(name: 'Omar');

      expect(provider.candidates, hasLength(1));
      expect(provider.searchErrorMessage, isNull);
      expect(provider.isSearching, isFalse);
      expect(candidateRepository.lastName, 'Omar');
    });

    test('sets searchErrorMessage on failure', () async {
      candidateRepository.searchError = ApiException('Server error.');

      await provider.search();

      expect(provider.candidates, isEmpty);
      expect(provider.searchErrorMessage, 'Server error.');
    });

    test('passes opportunityId through', () async {
      await provider.search(opportunityId: 7);

      expect(candidateRepository.lastOpportunityId, 7);
    });
  });

  group('sendInvitation', () {
    test('sets lastInvitedCandidateId on success', () async {
      await provider.sendInvitation(studentId: 3, opportunityId: 5);

      expect(provider.lastInvitedCandidateId, 3);
      expect(provider.inviteErrorMessage, isNull);
      expect(provider.isSendingInvite, isFalse);
      expect(invitationRepository.lastStudentId, 3);
      expect(invitationRepository.lastOpportunityId, 5);
    });

    test('forwards an optional message', () async {
      await provider.sendInvitation(
        studentId: 3,
        opportunityId: 5,
        message: 'Great fit!',
      );

      expect(invitationRepository.lastMessage, 'Great fit!');
    });

    test('sets inviteErrorMessage on failure, not lastInvitedCandidateId', () async {
      invitationRepository.sendError = ApiException(
        'An invitation already exists for this student and opportunity',
        statusCode: 409,
      );

      await provider.sendInvitation(studentId: 3, opportunityId: 5);

      expect(provider.lastInvitedCandidateId, isNull);
      expect(
        provider.inviteErrorMessage,
        'An invitation already exists for this student and opportunity',
      );
    });

    test('a duplicate submission while one is in flight is ignored', () async {
      invitationRepository.sendDelay = const Duration(milliseconds: 50);

      await Future.wait([
        provider.sendInvitation(studentId: 3, opportunityId: 5),
        provider.sendInvitation(studentId: 3, opportunityId: 5),
      ]);

      expect(invitationRepository.sendCallCount, 1);
    });

    test('a new attempt clears the previous error/success state', () async {
      invitationRepository.sendError = ApiException('Server error.');
      await provider.sendInvitation(studentId: 3, opportunityId: 5);
      expect(provider.inviteErrorMessage, isNotNull);

      invitationRepository.sendError = null;
      await provider.sendInvitation(studentId: 3, opportunityId: 5);

      expect(provider.inviteErrorMessage, isNull);
      expect(provider.lastInvitedCandidateId, 3);
    });
  });

  test('reset clears every field', () async {
    candidateRepository.results = [_candidate()];
    await provider.search();
    await provider.sendInvitation(studentId: 3, opportunityId: 5);

    provider.reset();

    expect(provider.candidates, isEmpty);
    expect(provider.searchErrorMessage, isNull);
    expect(provider.inviteErrorMessage, isNull);
    expect(provider.lastInvitedCandidateId, isNull);
  });
}
