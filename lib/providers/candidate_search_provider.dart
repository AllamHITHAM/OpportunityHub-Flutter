import 'package:flutter/foundation.dart';

import '../core/api/api_client.dart';
import '../features/candidates/data/candidate_repository.dart';
import '../features/invitations/data/invitation_repository.dart';
import '../models/candidate_model.dart';
import 'auth_provider.dart';

/// Holds Candidate Search results and the invite-sending state for the
/// Organization side of Flow B (Phase 8B-3). Depends on both
/// [CandidateRepository] (search) and [InvitationRepository] (send) --
/// sending an invitation is an Invitation concern, not a Candidate one, but
/// this one screen/provider needs both.
class CandidateSearchProvider extends ChangeNotifier {
  CandidateSearchProvider({
    required this.repository,
    required this.invitationRepository,
    required this._authProvider,
  }) {
    _authProvider.addListener(_handleAuthChanged);
  }

  final CandidateRepository repository;
  final InvitationRepository invitationRepository;
  final AuthProvider _authProvider;

  List<CandidateModel> candidates = [];
  bool isSearching = false;
  String? searchErrorMessage;

  bool isSendingInvite = false;
  String? inviteErrorMessage;

  /// The candidate ID an invitation was just successfully sent to — used
  /// by the UI to disable that one candidate's Invite action rather than
  /// the whole screen, and cleared at the start of every new attempt.
  int? lastInvitedCandidateId;

  Future<void>? _pendingSearch;

  void _handleAuthChanged() {
    if (!_authProvider.isAuthenticated) reset();
  }

  /// Searches candidates. Safe to call repeatedly (e.g. re-running a
  /// search with new filters) — a search already in flight is reused
  /// rather than duplicated.
  Future<void> search({
    String? name,
    String? major,
    String? university,
    int? graduationYear,
    String? skill,
    int? opportunityId,
  }) {
    return _pendingSearch ??= _performSearch(
      name: name,
      major: major,
      university: university,
      graduationYear: graduationYear,
      skill: skill,
      opportunityId: opportunityId,
    );
  }

  Future<void> _performSearch({
    String? name,
    String? major,
    String? university,
    int? graduationYear,
    String? skill,
    int? opportunityId,
  }) async {
    isSearching = true;
    searchErrorMessage = null;
    notifyListeners();

    try {
      candidates = await repository.searchCandidates(
        name: name,
        major: major,
        university: university,
        graduationYear: graduationYear,
        skill: skill,
        opportunityId: opportunityId,
      );
    } on ApiException catch (error) {
      searchErrorMessage = error.message;
    }

    isSearching = false;
    _pendingSearch = null;
    notifyListeners();
  }

  /// Sends an invitation. A duplicate submission while one is already in
  /// flight is ignored.
  Future<void> sendInvitation({
    required int studentId,
    required int opportunityId,
    String? message,
  }) async {
    if (isSendingInvite) return;

    isSendingInvite = true;
    inviteErrorMessage = null;
    lastInvitedCandidateId = null;
    notifyListeners();

    try {
      await invitationRepository.sendInvitation(
        studentId: studentId,
        opportunityId: opportunityId,
        message: message,
      );
      lastInvitedCandidateId = studentId;
    } on ApiException catch (error) {
      inviteErrorMessage = error.message;
    }

    isSendingInvite = false;
    notifyListeners();
  }

  void clearInviteError() {
    inviteErrorMessage = null;
    notifyListeners();
  }

  /// Clears all candidate-search state — called when the signed-in user
  /// changes.
  void reset() {
    candidates = [];
    isSearching = false;
    searchErrorMessage = null;
    isSendingInvite = false;
    inviteErrorMessage = null;
    lastInvitedCandidateId = null;
    _pendingSearch = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _authProvider.removeListener(_handleAuthChanged);
    super.dispose();
  }
}
