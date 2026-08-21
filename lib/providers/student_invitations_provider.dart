import 'package:flutter/foundation.dart';

import '../core/api/api_client.dart';
import '../features/invitations/data/invitation_repository.dart';
import '../models/invitation_model.dart';
import 'auth_provider.dart';

/// Holds the authenticated student's invitations and exposes
/// accept/decline actions (Phase 8B-3, Flow B).
class StudentInvitationsProvider extends ChangeNotifier {
  StudentInvitationsProvider({
    required this.repository,
    required this._authProvider,
  }) {
    _authProvider.addListener(_handleAuthChanged);
  }

  final InvitationRepository repository;
  final AuthProvider _authProvider;

  List<InvitationModel> invitations = [];
  bool isLoading = false;
  String? listErrorMessage;

  /// The invitation ID an accept/decline is currently in flight for, if
  /// any — lets the UI disable just that invitation's actions instead of
  /// the whole list.
  int? _respondingToId;
  String? respondErrorMessage;

  Future<void>? _pendingLoad;

  void _handleAuthChanged() {
    if (!_authProvider.isAuthenticated) reset();
  }

  bool isRespondingTo(int invitationId) => _respondingToId == invitationId;

  /// Loads the student's invitations. Safe to call repeatedly — a fetch
  /// already in flight is reused rather than duplicated.
  Future<void> loadInvitations() {
    return _pendingLoad ??= _performLoad();
  }

  Future<void> _performLoad() async {
    isLoading = true;
    listErrorMessage = null;
    notifyListeners();

    try {
      invitations = await repository.getInvitations();
    } on ApiException catch (error) {
      listErrorMessage = error.message;
    }

    isLoading = false;
    _pendingLoad = null;
    notifyListeners();
  }

  /// Accepts [invitationId]. On success, reloads the list so its status
  /// reflects the real, backend-confirmed state — never guessed/optimistic
  /// locally, so a failure leaves the invitation's prior state untouched.
  Future<void> accept(int invitationId) => _respond(
    invitationId,
    () => repository.acceptInvitation(invitationId),
  );

  /// Declines [invitationId]. Same reload-on-success discipline as
  /// [accept].
  Future<void> decline(int invitationId) => _respond(
    invitationId,
    () => repository.declineInvitation(invitationId),
  );

  Future<void> _respond(int invitationId, Future<void> Function() action) async {
    if (_respondingToId != null) return;

    _respondingToId = invitationId;
    respondErrorMessage = null;
    notifyListeners();

    try {
      await action();
      invitations = await repository.getInvitations();
    } on ApiException catch (error) {
      respondErrorMessage = error.message;
    }

    _respondingToId = null;
    notifyListeners();
  }

  void clearRespondError() {
    respondErrorMessage = null;
    notifyListeners();
  }

  /// Clears all invitation state — called when the signed-in user changes.
  void reset() {
    invitations = [];
    isLoading = false;
    listErrorMessage = null;
    _respondingToId = null;
    respondErrorMessage = null;
    _pendingLoad = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _authProvider.removeListener(_handleAuthChanged);
    super.dispose();
  }
}
