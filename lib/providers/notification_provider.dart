import 'package:flutter/foundation.dart';

import '../core/api/api_client.dart';
import '../features/notifications/data/notification_repository.dart';
import '../models/notification_model.dart';
import 'auth_provider.dart';

/// Holds the authenticated user's notifications and exposes the
/// mark-one/mark-all actions. Deliberately one shared provider for every
/// role — `GET /notifications` is a single role-agnostic backend endpoint
/// (unlike Assessment/Offer/Applications, which each have separate
/// Student/Organization endpoints and therefore separate providers), so
/// splitting this into per-role providers would duplicate identical logic
/// against the exact same endpoint for no reason.
///
/// `unreadCount`/`hasUnread` are derived from [notifications] itself — the
/// backend has no dedicated unread-count endpoint (Phase 7A-1/7A-2), so
/// there is nothing to fetch separately; the already-loaded list is always
/// the source of truth.
class NotificationProvider extends ChangeNotifier {
  NotificationProvider({
    required this.repository,
    required this._authProvider,
  }) {
    _authProvider.addListener(_handleAuthChanged);
  }

  final NotificationRepository repository;
  final AuthProvider _authProvider;

  List<NotificationModel> notifications = [];

  bool isLoading = false;
  String? errorMessage;

  bool isMarkingAll = false;
  String? actionErrorMessage;

  /// Notification IDs with a mark-as-read request currently in flight —
  /// guards against a duplicate submission for the same notification,
  /// exactly like every other per-ID busy-guard in this codebase (e.g.
  /// `StudentCvProvider`'s own busy-ID set).
  final Set<int> busyNotificationIds = {};

  /// The in-flight load fetch, if any — guards against concurrent
  /// duplicate requests without preventing an explicit refresh once the
  /// previous fetch has finished.
  Future<void>? _pendingLoad;

  /// A generation counter identifying the most recently *started* load —
  /// incremented only when a genuinely new [_performLoad] call is created
  /// (never on a deduplicated call that reuses [_pendingLoad]), so a
  /// slower, older `forceRefresh` call can never overwrite the result of a
  /// newer one (or a [reset]) that started after it. Mirrors
  /// `StudentAssessmentProvider._loadGeneration`.
  int _loadGeneration = 0;

  int get unreadCount => notifications.where((n) => !n.isRead).length;

  bool get hasUnread => unreadCount > 0;

  bool isBusy(int notificationId) =>
      busyNotificationIds.contains(notificationId);

  void _handleAuthChanged() {
    // A different user may sign in next — don't leak the previous
    // session's notifications into theirs.
    if (!_authProvider.isAuthenticated) {
      reset();
    }
  }

  /// Loads the current user's notifications. Safe to call repeatedly — a
  /// fetch already in flight is reused rather than duplicated; pass
  /// [forceRefresh] to start a fresh one regardless.
  Future<void> load({bool forceRefresh = false}) {
    if (forceRefresh) {
      _pendingLoad = null;
    }
    if (_pendingLoad == null) {
      final generation = ++_loadGeneration;
      _pendingLoad = _performLoad(generation);
    }
    return _pendingLoad!;
  }

  Future<void> _performLoad(int generation) async {
    isLoading = true;
    errorMessage = null;
    notifyListeners();

    // Whether this call is still the most recently started generation by
    // the time this fetch resolves — a later call (a newer `forceRefresh`,
    // or a `reset()`) may have started while this one was in flight, and
    // its (possibly stale) result must never overwrite the newer state.
    bool stillCurrent() => generation == _loadGeneration;

    try {
      final result = await repository.getNotifications();
      if (stillCurrent()) {
        notifications = result;
      }
    } on ApiException catch (error) {
      // Deliberately never touches `notifications` on failure — a refresh
      // failure must never blank out a list the user is already looking
      // at. On a genuine first load, `notifications` is already empty, so
      // this has the same effect either way.
      if (stillCurrent()) {
        errorMessage = error.message;
      }
    } catch (_) {
      // An unexpected parsing/runtime error (e.g. malformed backend data)
      // — never leaves the screen stuck loading, never shows raw
      // exception/stack-trace text.
      if (stillCurrent()) {
        errorMessage = 'Something went wrong. Please try again.';
      }
    } finally {
      if (stillCurrent()) {
        isLoading = false;
        _pendingLoad = null;
      }
      notifyListeners();
    }
  }

  /// Marks [notificationId] as read. Returns `true` only on success. A
  /// duplicate submission for the same ID while one is already in flight is
  /// ignored (returns `false` immediately, no repository call). Deliberately
  /// does not check whether the notification is already read — the caller
  /// (see `NotificationScreen`) decides whether calling this at all makes
  /// sense; this method's own job is only to make the one call it's asked
  /// to make safely.
  Future<bool> markAsRead(int notificationId) async {
    if (busyNotificationIds.contains(notificationId)) return false;

    busyNotificationIds.add(notificationId);
    actionErrorMessage = null;
    notifyListeners();

    var success = false;
    try {
      final updated = await repository.markAsRead(notificationId);
      final index = notifications.indexWhere((n) => n.id == notificationId);
      if (index != -1) {
        // A new list (not an in-place mutation) so `notifyListeners()`
        // reliably signals a real change, and only the matching item is
        // replaced — every other notification in the list is left
        // untouched.
        final updatedList = [...notifications];
        updatedList[index] = updated;
        notifications = updatedList;
      }
      success = true;
    } on ApiException catch (error) {
      // Deliberately never touches `notifications` on failure — a failed
      // mark-read must never make an already-visible notification silently
      // flip to read (or otherwise change) when it didn't actually happen.
      actionErrorMessage = error.message;
    } catch (_) {
      actionErrorMessage = 'Something went wrong. Please try again.';
    } finally {
      busyNotificationIds.remove(notificationId);
      notifyListeners();
    }
    return success;
  }

  /// Marks every currently-unread notification as read. Returns `true`
  /// only on success. A duplicate submission while one is already in
  /// flight is ignored. On success, patches every unread item in
  /// [notifications] locally (`isRead = true`) rather than reloading — the
  /// backend's own `updated_count` in the response is authoritative for
  /// *how many* changed, but the actual rows read back would be identical
  /// to just flipping every currently-unread item locally.
  Future<bool> markAllAsRead() async {
    if (isMarkingAll) return false;

    isMarkingAll = true;
    actionErrorMessage = null;
    notifyListeners();

    var success = false;
    try {
      await repository.markAllAsRead();
      final now = DateTime.now();
      notifications = [
        for (final notification in notifications)
          notification.isRead
              ? notification
              : notification.copyWithRead(readAt: now),
      ];
      success = true;
    } on ApiException catch (error) {
      // Deliberately never touches `notifications` on failure.
      actionErrorMessage = error.message;
    } catch (_) {
      actionErrorMessage = 'Something went wrong. Please try again.';
    } finally {
      isMarkingAll = false;
      notifyListeners();
    }
    return success;
  }

  void clearActionError() {
    actionErrorMessage = null;
    notifyListeners();
  }

  /// Clears all notification state — called when the signed-in user
  /// changes.
  void reset() {
    notifications = [];
    isLoading = false;
    errorMessage = null;
    isMarkingAll = false;
    actionErrorMessage = null;
    busyNotificationIds.clear();
    // Invalidates any load still in flight — a stale response arriving
    // after a logout/session change must not repopulate the next user's
    // state.
    _loadGeneration++;
    _pendingLoad = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _authProvider.removeListener(_handleAuthChanged);
    super.dispose();
  }
}
