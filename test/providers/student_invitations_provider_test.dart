// Direct unit tests for StudentInvitationsProvider, using a fake
// repository (no real network).

import 'package:flutter_test/flutter_test.dart';

import 'package:opportunityhub_flutter/core/api/api_client.dart';
import 'package:opportunityhub_flutter/core/storage/token_storage_service.dart';
import 'package:opportunityhub_flutter/features/auth/data/auth_repository.dart';
import 'package:opportunityhub_flutter/features/invitations/data/invitation_repository.dart';
import 'package:opportunityhub_flutter/models/invitation_model.dart';
import 'package:opportunityhub_flutter/providers/auth_provider.dart';
import 'package:opportunityhub_flutter/providers/student_invitations_provider.dart';

class _FakeAuthRepository extends AuthRepository {
  _FakeAuthRepository()
    : super(
        apiClient: ApiClient(tokenStorageService: TokenStorageService()),
        tokenStorageService: TokenStorageService(),
      );

  @override
  Future<String?> getSavedToken() async => null;
}

InvitationModel _invitation({int id = 1, String status = 'pending'}) {
  return InvitationModel(
    id: id,
    opportunityId: 5,
    status: status,
    opportunityTitle: 'Backend Developer',
    organizationName: 'Hiring Co',
  );
}

class _FakeInvitationRepository extends InvitationRepository {
  _FakeInvitationRepository()
    : super(apiClient: ApiClient(tokenStorageService: TokenStorageService()));

  List<InvitationModel> invitations = [];
  ApiException? listError;
  int getCallCount = 0;

  ApiException? acceptError;
  ApiException? declineError;
  int? lastAcceptedId;
  int? lastDeclinedId;

  @override
  Future<List<InvitationModel>> getInvitations() async {
    getCallCount++;
    if (listError != null) throw listError!;
    return invitations;
  }

  @override
  Future<void> acceptInvitation(int invitationId) async {
    lastAcceptedId = invitationId;
    if (acceptError != null) throw acceptError!;
    invitations = [
      for (final invitation in invitations)
        if (invitation.id == invitationId)
          _invitation(id: invitation.id, status: 'accepted')
        else
          invitation,
    ];
  }

  @override
  Future<void> declineInvitation(int invitationId) async {
    lastDeclinedId = invitationId;
    if (declineError != null) throw declineError!;
    invitations = [
      for (final invitation in invitations)
        if (invitation.id == invitationId)
          _invitation(id: invitation.id, status: 'declined')
        else
          invitation,
    ];
  }
}

void main() {
  late _FakeInvitationRepository repository;
  late StudentInvitationsProvider provider;

  setUp(() {
    repository = _FakeInvitationRepository();
    provider = StudentInvitationsProvider(
      repository: repository,
      authProvider: AuthProvider(authRepository: _FakeAuthRepository()),
    );
  });

  group('loadInvitations', () {
    test('populates invitations on success', () async {
      repository.invitations = [_invitation()];

      await provider.loadInvitations();

      expect(provider.invitations, hasLength(1));
      expect(provider.listErrorMessage, isNull);
      expect(provider.isLoading, isFalse);
    });

    test('sets listErrorMessage on failure', () async {
      repository.listError = ApiException('Server error.');

      await provider.loadInvitations();

      expect(provider.invitations, isEmpty);
      expect(provider.listErrorMessage, 'Server error.');
    });
  });

  group('accept', () {
    test('reloads the list, reflecting the confirmed accepted status', () async {
      repository.invitations = [_invitation()];
      await provider.loadInvitations();

      await provider.accept(1);

      expect(provider.invitations.single.status, 'accepted');
      expect(repository.lastAcceptedId, 1);
      expect(repository.getCallCount, 2);
    });

    test('sets respondErrorMessage on failure, leaves the list untouched', () async {
      repository.invitations = [_invitation()];
      await provider.loadInvitations();
      repository.acceptError = ApiException(
        'This invitation has already been responded to',
        statusCode: 409,
      );

      await provider.accept(1);

      expect(
        provider.respondErrorMessage,
        'This invitation has already been responded to',
      );
      expect(provider.invitations.single.status, 'pending');
    });

    test('isRespondingTo is true only while the action is in flight', () async {
      repository.invitations = [_invitation()];
      await provider.loadInvitations();

      final future = provider.accept(1);
      expect(provider.isRespondingTo(1), isTrue);
      await future;
      expect(provider.isRespondingTo(1), isFalse);
    });
  });

  group('decline', () {
    test('reloads the list, reflecting the confirmed declined status', () async {
      repository.invitations = [_invitation()];
      await provider.loadInvitations();

      await provider.decline(1);

      expect(provider.invitations.single.status, 'declined');
      expect(repository.lastDeclinedId, 1);
    });

    test('sets respondErrorMessage on failure', () async {
      repository.invitations = [_invitation()];
      await provider.loadInvitations();
      repository.declineError = ApiException('Invitation not found', statusCode: 404);

      await provider.decline(1);

      expect(provider.respondErrorMessage, 'Invitation not found');
    });
  });

  test('reset clears every field', () async {
    repository.invitations = [_invitation()];
    await provider.loadInvitations();

    provider.reset();

    expect(provider.invitations, isEmpty);
    expect(provider.listErrorMessage, isNull);
    expect(provider.respondErrorMessage, isNull);
  });
}
