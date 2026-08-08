import 'package:flutter/foundation.dart';

import '../core/api/api_client.dart';
import '../features/admin/data/admin_organizations_repository.dart';
import '../models/organization_profile_model.dart';
import 'auth_provider.dart';

/// Holds the Admin organization-management list and details, and exposes
/// the approve/reject actions.
///
/// Kept entirely separate from `AdminUsersProvider`/`AdminDashboardProvider`
/// and a future `AdminSkillsProvider` — the same per-resource separation
/// already applied throughout this app's other provider pairs (see
/// `OrganizationAssessmentProvider` vs `OrganizationApplicationsProvider`).
/// Never exposes a way to change an approved/rejected organization back to
/// another approval state, delete an organization, edit its profile, or
/// change its user's role — the backend has no delete/edit endpoints, and
/// those transitions are simply not wired to any UI action in this phase.
class AdminOrganizationsProvider extends ChangeNotifier {
  AdminOrganizationsProvider({
    required this.repository,
    required this._authProvider,
  }) {
    _authProvider.addListener(_handleAuthChanged);
  }

  final AdminOrganizationsRepository repository;
  final AuthProvider _authProvider;

  List<OrganizationProfileModel> organizations = [];
  bool isLoading = false;
  String? errorMessage;

  OrganizationProfileModel? selectedOrganization;
  bool isLoadingDetails = false;
  String? detailsErrorMessage;

  String? actionErrorMessage;

  /// Organization IDs with an approve/reject request currently in flight —
  /// guards against a duplicate action for the same organization, exactly
  /// like `AdminUsersProvider.busyUserIds`. Independent per organization,
  /// so acting on one organization never blocks another.
  final Set<int> busyOrganizationIds = {};

  /// The in-flight list fetch, if any — guards against concurrent
  /// duplicate requests, without preventing an explicit refresh once the
  /// previous fetch has finished.
  Future<void>? _pendingLoad;

  /// A generation counter identifying the most recently started list load
  /// — the same `forceRefresh`-vs-stale-response guard just fixed in
  /// `AdminUsersProvider.load`. `forceRefresh` deliberately discards
  /// [_pendingLoad] so a fresh fetch starts even while an old one is still
  /// in flight, which means two `getOrganizations()` calls can genuinely
  /// race; each `_performLoad` call captures its own generation and only
  /// writes `organizations`/`errorMessage`/`isLoading`/[_pendingLoad] if
  /// it's still the most recent one by the time it resolves.
  int _loadGeneration = 0;

  /// The in-flight details fetch, if any, and which organization ID it (or
  /// the most recent completed fetch) is for — mirrors
  /// `OrganizationApplicationsProvider.loadApplicationDetails`'s per-ID
  /// `stillCurrent()` guard. A request for a different organization ID
  /// never reuses this future, and a stale response for an old ID never
  /// overwrites [selectedOrganization] once a newer organization has been
  /// requested.
  Future<void>? _pendingDetailsFetch;
  int? _pendingDetailsOrganizationId;

  bool isBusy(int organizationId) =>
      busyOrganizationIds.contains(organizationId);

  void _handleAuthChanged() {
    // A different admin may sign in next — don't leak the previous
    // session's organization data into theirs.
    if (!_authProvider.isAuthenticated) {
      reset();
    }
  }

  /// Loads every organization. Safe to call repeatedly — a fetch already in
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
      final result = await repository.getOrganizations();
      // A forceRefresh started a newer load while this one was still in
      // flight — that newer call already owns `organizations`/
      // `errorMessage`, so this now-stale response must not overwrite it.
      if (generation != _loadGeneration) return;
      organizations = result;
    } on ApiException catch (error) {
      if (generation != _loadGeneration) return;
      // Deliberately never touches `organizations` — a refresh failure
      // must never blank out a list the admin is already looking at.
      errorMessage = error.message;
    } catch (_) {
      if (generation != _loadGeneration) return;
      // An unexpected parsing/runtime error (e.g. malformed backend data)
      // — never leaves the list stuck loading, never shows raw
      // exception/stack-trace text, and never touches `organizations`.
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

  /// Loads a single organization's details. A fetch already in flight *for
  /// the same organization* is reused rather than duplicated; a request for
  /// a different organization ID, or [forceRefresh], always starts a fresh
  /// one.
  Future<void> loadDetails(int organizationId, {bool forceRefresh = false}) {
    if (forceRefresh || _pendingDetailsOrganizationId != organizationId) {
      _pendingDetailsFetch = null;
    }
    _pendingDetailsOrganizationId = organizationId;
    return _pendingDetailsFetch ??= _performLoadDetails(organizationId);
  }

  Future<void> _performLoadDetails(int organizationId) async {
    isLoadingDetails = true;
    detailsErrorMessage = null;
    notifyListeners();

    // Whether [organizationId] is still the one currently being requested
    // by the time this fetch resolves — a later call for a *different*
    // organization may have started while this one was in flight, and its
    // (possibly stale) result must never overwrite the newer request's
    // state.
    bool stillCurrent() => _pendingDetailsOrganizationId == organizationId;

    try {
      final result = await repository.getOrganization(organizationId);
      if (stillCurrent()) {
        selectedOrganization = result;
      }
    } on ApiException catch (error) {
      if (stillCurrent()) {
        detailsErrorMessage = error.message;
        selectedOrganization = null;
      }
    } catch (_) {
      if (stillCurrent()) {
        detailsErrorMessage = 'Something went wrong. Please try again.';
        selectedOrganization = null;
      }
    } finally {
      if (stillCurrent()) {
        isLoadingDetails = false;
        _pendingDetailsFetch = null;
      }
      notifyListeners();
    }
  }

  /// Approves [organizationId]. Returns `true` only on success. A duplicate
  /// submission for the same organization while one is already in flight is
  /// ignored (returns `false` immediately, no second repository call) — a
  /// different organization's action is entirely unaffected.
  Future<bool> approve(int organizationId) =>
      _updateApproval(organizationId, repository.approveOrganization);

  /// Rejects [organizationId] — see [approve] for the shared
  /// duplicate-submission/busy-state behavior.
  Future<bool> reject(int organizationId) =>
      _updateApproval(organizationId, repository.rejectOrganization);

  Future<bool> _updateApproval(
    int organizationId,
    Future<OrganizationProfileModel> Function(int organizationId) action,
  ) async {
    if (busyOrganizationIds.contains(organizationId)) return false;

    busyOrganizationIds.add(organizationId);
    actionErrorMessage = null;
    notifyListeners();

    var success = false;
    try {
      final updated = await action(organizationId);
      organizations = [
        for (final organization in organizations)
          if (organization.id == organizationId) updated else organization,
      ];
      if (selectedOrganization?.id == organizationId) {
        selectedOrganization = updated;
      }
      success = true;
    } on ApiException catch (error) {
      // Never touches `organizations`/`selectedOrganization`, so the old
      // approval status is preserved exactly as it was before this
      // attempt.
      actionErrorMessage = error.message;
    } catch (_) {
      actionErrorMessage = 'Something went wrong. Please try again.';
    } finally {
      busyOrganizationIds.remove(organizationId);
      notifyListeners();
    }
    return success;
  }

  void clearActionError() {
    actionErrorMessage = null;
    notifyListeners();
  }

  /// Clears all organization-management state — called when the signed-in
  /// admin changes.
  void reset() {
    organizations = [];
    isLoading = false;
    errorMessage = null;
    selectedOrganization = null;
    isLoadingDetails = false;
    detailsErrorMessage = null;
    actionErrorMessage = null;
    busyOrganizationIds.clear();
    _pendingLoad = null;
    // Invalidates any list load still in flight — a stale response
    // arriving after a logout/session change must not repopulate the next
    // admin's list with the previous session's data.
    _loadGeneration++;
    _pendingDetailsFetch = null;
    _pendingDetailsOrganizationId = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _authProvider.removeListener(_handleAuthChanged);
    super.dispose();
  }
}
