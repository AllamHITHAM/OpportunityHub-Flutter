import 'package:flutter/foundation.dart';

import '../core/api/api_client.dart';
import '../features/admin/data/admin_users_repository.dart';
import '../models/user_model.dart';
import 'auth_provider.dart';

/// Holds the Admin user-management list and exposes the "suspend/reactivate
/// a user" action.
///
/// Kept entirely separate from `AdminDashboardProvider` and a future
/// `AdminOrganizationsProvider`/`AdminSkillsProvider` — the same
/// per-resource separation already applied throughout this app's other
/// provider pairs (see `OrganizationAssessmentProvider` vs
/// `OrganizationApplicationsProvider`). Never exposes a way to change a
/// user's role or delete a user — the backend has no such endpoints.
class AdminUsersProvider extends ChangeNotifier {
  AdminUsersProvider({required this.repository, required this._authProvider}) {
    _authProvider.addListener(_handleAuthChanged);
  }

  final AdminUsersRepository repository;
  final AuthProvider _authProvider;

  List<UserModel> users = [];
  bool isLoading = false;
  String? errorMessage;

  String? actionErrorMessage;

  /// User IDs with a status-update request currently in flight — guards
  /// against a duplicate status change for the same user, exactly like
  /// `OrganizationApplicationsProvider.busyApplicationIds`. Independent
  /// per user, so updating one user never blocks another.
  final Set<int> busyUserIds = {};

  /// The in-flight list fetch, if any — guards against concurrent
  /// duplicate requests, without preventing an explicit refresh once the
  /// previous fetch has finished.
  Future<void>? _pendingLoad;

  /// A generation counter identifying the most recently started load.
  ///
  /// `forceRefresh` deliberately discards `_pendingLoad` so a fresh fetch
  /// starts even while an old one is still in flight — but that means two
  /// `getUsers()` calls can genuinely race. Without this, whichever one
  /// happens to resolve *last* would win and overwrite `users`/
  /// `errorMessage`, even if it was the older (now-stale) request. Each
  /// `_performLoad` call captures its own token and only ever writes
  /// state if it's still the most recent one by the time it resolves —
  /// the same `stillCurrent()` pattern
  /// `OrganizationApplicationsProvider`/`OrganizationAssessmentProvider`
  /// key by ID; this provider has no per-item ID to key by (it loads one
  /// flat list), so a monotonically increasing generation number plays
  /// the same role.
  int _loadGeneration = 0;

  bool isBusy(int userId) => busyUserIds.contains(userId);

  void _handleAuthChanged() {
    // A different admin may sign in next — don't leak the previous
    // session's user list into theirs.
    if (!_authProvider.isAuthenticated) {
      reset();
    }
  }

  /// Loads every user. Safe to call repeatedly — a fetch already in
  /// flight is reused rather than duplicated. Pass [forceRefresh] to start
  /// a fresh one regardless.
  Future<void> load({bool forceRefresh = false}) {
    if (forceRefresh) {
      _pendingLoad = null;
    }
    return _pendingLoad ??= _performLoad(++_loadGeneration);
  }

  Future<void> _performLoad(int generation) async {
    isLoading = true;
    errorMessage = null;
    notifyListeners();

    try {
      final result = await repository.getUsers();
      // A forceRefresh started a newer load while this one was still in
      // flight — that newer call already owns `users`/`errorMessage`, so
      // this now-stale response must not overwrite it.
      if (generation != _loadGeneration) return;
      users = result;
    } on ApiException catch (error) {
      if (generation != _loadGeneration) return;
      // Deliberately never touches `users` — a refresh failure must never
      // blank out a list the admin is already looking at.
      errorMessage = error.message;
    } catch (_) {
      if (generation != _loadGeneration) return;
      // An unexpected parsing/runtime error (e.g. malformed backend data)
      // — never leaves the list stuck loading, never shows raw
      // exception/stack-trace text, and never touches `users`.
      errorMessage = 'Something went wrong. Please try again.';
    } finally {
      // Only the current generation may clear isLoading/_pendingLoad — a
      // stale call's finally must not clear `_pendingLoad` out from under
      // a newer load that's still genuinely in flight.
      if (generation == _loadGeneration) {
        isLoading = false;
        _pendingLoad = null;
      }
      notifyListeners();
    }
  }

  /// Updates [userId]'s status to [status] (`active` or `suspended`).
  /// Returns `true` only on success. A duplicate submission for the same
  /// user while one is already in flight is ignored (returns `false`
  /// immediately, no second repository call) — a different user's update
  /// is entirely unaffected.
  Future<bool> updateStatus({
    required int userId,
    required String status,
  }) async {
    if (busyUserIds.contains(userId)) return false;

    busyUserIds.add(userId);
    actionErrorMessage = null;
    notifyListeners();

    var success = false;
    try {
      final updated = await repository.updateUserStatus(
        userId: userId,
        status: status,
      );
      users = [
        for (final user in users)
          if (user.id == userId) updated else user,
      ];
      success = true;
    } on ApiException catch (error) {
      // Covers the backend's "You cannot change your own account status"
      // 403, a 404 for a since-deleted... well, users can't be deleted,
      // but a stale/nonexistent ID either way, and 422 validation — never
      // touches `users`, so the old status is preserved exactly as it was
      // before this attempt.
      actionErrorMessage = error.message;
    } catch (_) {
      actionErrorMessage = 'Something went wrong. Please try again.';
    } finally {
      busyUserIds.remove(userId);
      notifyListeners();
    }
    return success;
  }

  void clearActionError() {
    actionErrorMessage = null;
    notifyListeners();
  }

  /// Clears all user-management state — called when the signed-in admin
  /// changes.
  void reset() {
    users = [];
    isLoading = false;
    errorMessage = null;
    actionErrorMessage = null;
    busyUserIds.clear();
    _pendingLoad = null;
    // Invalidates any load still in flight — a stale response arriving
    // after a logout/session change must not repopulate the next admin's
    // list with the previous session's data.
    _loadGeneration++;
    notifyListeners();
  }

  @override
  void dispose() {
    _authProvider.removeListener(_handleAuthChanged);
    super.dispose();
  }
}
