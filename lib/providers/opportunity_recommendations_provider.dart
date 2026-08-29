import 'package:flutter/foundation.dart';

import '../core/api/api_client.dart';
import '../features/candidates/data/candidate_repository.dart';
import '../features/invitations/data/invitation_repository.dart';
import '../models/recommended_candidate_model.dart';
import 'auth_provider.dart';

/// Holds the ranked Recommended Candidates for one Opportunity, plus the
/// invite-sending state for that same context (Phase O8.1). Depends on
/// both [CandidateRepository] (recommendations) and [InvitationRepository]
/// (send) -- the same two-repository shape [CandidateSearchProvider]
/// already uses, since sending an invitation is an Invitation concern, not
/// a Candidate one, but this one screen/provider needs both.
class OpportunityRecommendationsProvider extends ChangeNotifier {
  OpportunityRecommendationsProvider({
    required this.repository,
    required this.invitationRepository,
    required this._authProvider,
  }) {
    _authProvider.addListener(_handleAuthChanged);
  }

  final CandidateRepository repository;
  final InvitationRepository invitationRepository;
  final AuthProvider _authProvider;

  /// The Opportunity ID [candidates] was actually loaded for -- lets the
  /// screen tell "results genuinely belong to this Opportunity" apart from
  /// "still loading" or "stale results from a previous Opportunity".
  int? loadedOpportunityId;

  List<RecommendedCandidateModel> candidates = [];

  /// The real Opportunity context the last successful load returned (Phase
  /// O8.2) -- `null` until a load succeeds. Used to render a truthful
  /// explanation of what was actually filtered/ranked; [workMode] in
  /// particular is what stops the UI from ever claiming location was
  /// considered for a Remote opportunity.
  String? workMode;
  String? locationName;

  /// The canonical Opportunity Type (Candidate Opportunity Preferences
  /// patch) -- every listed candidate already has this exact value in
  /// their own `interested_in` preference. Used to render real, dynamic
  /// "these candidates are interested in X opportunities" copy.
  String? opportunityType;

  bool isLoading = false;
  String? errorMessage;

  bool isSendingInvite = false;
  String? inviteErrorMessage;

  /// The candidate ID an invitation was just successfully sent to this
  /// session -- used by the UI to show "Invited" for that one candidate
  /// immediately, the same real-state-surfacing pattern
  /// [CandidateSearchProvider.lastInvitedCandidateId] already established.
  int? lastInvitedCandidateId;

  Future<void>? _pendingLoad;

  void _handleAuthChanged() {
    if (!_authProvider.isAuthenticated) reset();
  }

  /// Loads recommendations for [opportunityId]. Safe to call repeatedly --
  /// a load already in flight for the same Opportunity is reused rather
  /// than duplicated.
  Future<void> loadForOpportunity(
    int opportunityId, {
    bool forceRefresh = false,
  }) {
    if (!forceRefresh &&
        loadedOpportunityId == opportunityId &&
        candidates.isNotEmpty) {
      return Future.value();
    }

    return _pendingLoad ??= _performLoad(opportunityId);
  }

  Future<void> _performLoad(int opportunityId) async {
    isLoading = true;
    errorMessage = null;
    notifyListeners();

    try {
      final result = await repository.getRecommendedCandidates(opportunityId);
      candidates = result.candidates;
      workMode = result.workMode;
      locationName = result.locationName;
      opportunityType = result.opportunityType;
      loadedOpportunityId = opportunityId;
    } on ApiException catch (error) {
      errorMessage = error.message;
    }

    isLoading = false;
    _pendingLoad = null;
    notifyListeners();
  }

  /// Sends a real invitation for [opportunityId] -- the same
  /// `InvitationRepository.sendInvitation()` the Talent Directory's own
  /// invite flow already calls, so duplicate-protection and every other
  /// backend rule apply identically. Returns `true` only on success. A
  /// duplicate submission while one is already in flight is ignored.
  Future<bool> sendInvitation({
    required int studentId,
    required int opportunityId,
    String? message,
  }) async {
    if (isSendingInvite) return false;

    isSendingInvite = true;
    inviteErrorMessage = null;
    lastInvitedCandidateId = null;
    notifyListeners();

    var success = false;
    try {
      await invitationRepository.sendInvitation(
        studentId: studentId,
        opportunityId: opportunityId,
        message: message,
      );
      lastInvitedCandidateId = studentId;
      success = true;
    } on ApiException catch (error) {
      inviteErrorMessage = error.message;
    }

    isSendingInvite = false;
    notifyListeners();
    return success;
  }

  void clearInviteError() {
    inviteErrorMessage = null;
    notifyListeners();
  }

  /// Clears all recommendation state -- called when the signed-in user
  /// changes.
  void reset() {
    loadedOpportunityId = null;
    candidates = [];
    workMode = null;
    locationName = null;
    opportunityType = null;
    isLoading = false;
    errorMessage = null;
    isSendingInvite = false;
    inviteErrorMessage = null;
    lastInvitedCandidateId = null;
    _pendingLoad = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _authProvider.removeListener(_handleAuthChanged);
    super.dispose();
  }
}
