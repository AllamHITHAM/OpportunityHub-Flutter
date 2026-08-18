import 'package:flutter/foundation.dart';

import '../core/api/api_client.dart';
import '../features/applications/data/application_repository.dart';
import '../models/application_model.dart';
import 'auth_provider.dart';

/// Statuses this phase's Flutter UI is allowed to set. The backend's
/// `PUT .../status` endpoint technically accepts a broader set
/// (`interview_scheduled`, `accepted`) — this provider deliberately never
/// exposes a way to reach those from here; only [markReviewed], [shortlist],
/// and [reject] exist publicly, each hard-coded to one literal value.
enum _AllowedStatus { reviewed, shortlisted, rejected }

extension on _AllowedStatus {
  String get wireValue => switch (this) {
    _AllowedStatus.reviewed => 'reviewed',
    _AllowedStatus.shortlisted => 'shortlisted',
    _AllowedStatus.rejected => 'rejected',
  };
}

/// A focused content comparison for [ApplicationModel], used by
/// [OrganizationApplicationsProvider.patchApplication]. [ApplicationModel]
/// has no `==` override, and two separately-parsed responses for the same
/// underlying row are never `identical()`, so patching needs this instead
/// of relying on object identity. Compares every field that can
/// meaningfully change from an organization-facing action (status
/// review/shortlist/reject, or Assessment creation's `reviewed_at`/status
/// side effect); nested relations are compared by their own identifying ID
/// rather than deep field-by-field, which is enough to detect the only
/// kind of nested change these actions actually produce (nothing here
/// ever changes which opportunity/CV/applicant an application belongs to).
bool _sameApplicationData(ApplicationModel a, ApplicationModel b) {
  return a.id == b.id &&
      a.studentId == b.studentId &&
      a.opportunityId == b.opportunityId &&
      a.cvId == b.cvId &&
      a.status == b.status &&
      a.matchScore == b.matchScore &&
      a.coverLetter == b.coverLetter &&
      a.appliedAt == b.appliedAt &&
      a.reviewedAt == b.reviewedAt &&
      a.createdAt == b.createdAt &&
      a.updatedAt == b.updatedAt &&
      a.opportunity?.id == b.opportunity?.id &&
      a.applicant?.id == b.applicant?.id;
}

/// Holds the authenticated organization's applicant list (for one
/// opportunity at a time) and application-detail state, and exposes the
/// reviewed/shortlist/reject actions to the UI.
///
/// Kept entirely separate from `StudentApplicationsProvider` and
/// `OrganizationOpportunitiesProvider` — different state shapes (applicant
/// review vs. student's own applications vs. opportunity CRUD) over
/// different concerns, the same separation already applied throughout this
/// app's other student/organization provider pairs.
class OrganizationApplicationsProvider extends ChangeNotifier {
  OrganizationApplicationsProvider({
    required this.repository,
    required this._authProvider,
  }) {
    _authProvider.addListener(_handleAuthChanged);
  }

  final ApplicationRepository repository;
  final AuthProvider _authProvider;

  List<ApplicationModel> applications = [];
  bool isLoadingList = false;
  String? listErrorMessage;

  ApplicationModel? selectedApplication;
  bool isLoadingDetails = false;
  String? detailsErrorMessage;

  /// Application IDs with a status-update request currently in flight —
  /// guards against a duplicate status change for the same application,
  /// exactly like `StudentCvProvider`'s per-CV busy-ID guard.
  final Set<int> busyApplicationIds = {};
  String? actionErrorMessage;

  /// The in-flight list fetch, if any — guards against concurrent
  /// duplicate requests for the *same* opportunity, without preventing an
  /// explicit refresh once the previous fetch has finished.
  Future<void>? _pendingListFetch;

  /// Which opportunity [_pendingListFetch] (or the most recent completed
  /// fetch) is for. A request for a different opportunity ID must never
  /// reuse this future, and a stale response for an old ID must never
  /// overwrite [applications] once a newer opportunity has been requested
  /// — both are checked against this field.
  int? _pendingListOpportunityId;

  Future<void>? _pendingDetailsFetch;

  bool isUpdating(int applicationId) =>
      busyApplicationIds.contains(applicationId);

  void _handleAuthChanged() {
    // A different user may sign in next — don't leak the previous
    // organization's applicants into their session.
    if (!_authProvider.isAuthenticated) {
      reset();
    }
  }

  /// Loads the applicants for [opportunityId]. Safe to call repeatedly —
  /// a fetch already in flight *for the same opportunity* is reused
  /// rather than duplicated; a request for a different opportunity always
  /// starts its own fresh fetch. Pass [forceRefresh] to start a fresh one
  /// regardless of opportunity.
  Future<void> loadApplicationsForOpportunity(
    int opportunityId, {
    bool forceRefresh = false,
  }) {
    if (forceRefresh || _pendingListOpportunityId != opportunityId) {
      _pendingListFetch = null;
    }
    _pendingListOpportunityId = opportunityId;
    return _pendingListFetch ??= _performLoad(opportunityId);
  }

  Future<void> _performLoad(int opportunityId) async {
    isLoadingList = true;
    listErrorMessage = null;
    notifyListeners();

    // Whether [opportunityId] is still the one currently being requested
    // by the time this fetch resolves — a later call for a *different*
    // opportunity may have started while this one was in flight, and its
    // (possibly stale) result must never overwrite the newer request's
    // state.
    bool stillCurrent() => _pendingListOpportunityId == opportunityId;

    try {
      final result = await repository.getApplicationsForOpportunity(
        opportunityId,
      );
      if (stillCurrent()) {
        applications = result;
      }
    } on ApiException catch (error) {
      if (stillCurrent()) {
        listErrorMessage = error.message;
      }
    } catch (_) {
      // An unexpected parsing/runtime error (e.g. malformed backend data)
      // — never leaves the screen stuck loading, never shows raw
      // exception/stack-trace text.
      if (stillCurrent()) {
        listErrorMessage = 'Something went wrong. Please try again.';
      }
    } finally {
      if (stillCurrent()) {
        isLoadingList = false;
        _pendingListFetch = null;
      }
      notifyListeners();
    }
  }

  /// An application fetched via the applicants list doesn't include
  /// `opportunity` (the backend doesn't eager-load it there — the caller
  /// already knows it from the opportunity ID) — so it's not a complete
  /// substitute for a real details fetch, which does include it.
  bool _hasFullDetails(ApplicationModel application) =>
      application.opportunity != null;

  /// Loads a single application's details. Reuses an already-loaded copy
  /// only when that copy actually has everything the details screen needs
  /// (i.e. came from a real details/status-update fetch, not the
  /// applicants list); otherwise calls the detail endpoint.
  Future<void> loadApplicationDetails(
    int applicationId, {
    bool forceRefresh = false,
  }) {
    if (!forceRefresh) {
      for (final application in applications) {
        if (application.id == applicationId && _hasFullDetails(application)) {
          selectedApplication = application;
          detailsErrorMessage = null;
          notifyListeners();
          return Future.value();
        }
      }
    }
    return _pendingDetailsFetch ??= _performLoadDetails(applicationId);
  }

  Future<void> _performLoadDetails(int applicationId) async {
    isLoadingDetails = true;
    detailsErrorMessage = null;
    notifyListeners();

    try {
      selectedApplication = await repository.getOrganizationApplication(
        applicationId,
      );
    } on ApiException catch (error) {
      detailsErrorMessage = error.message;
      selectedApplication = null;
    } catch (_) {
      detailsErrorMessage = 'Something went wrong. Please try again.';
      selectedApplication = null;
    } finally {
      isLoadingDetails = false;
      _pendingDetailsFetch = null;
      notifyListeners();
    }
  }

  Future<bool> markReviewed(int applicationId) =>
      _updateStatus(applicationId, _AllowedStatus.reviewed);

  Future<bool> shortlist(int applicationId) =>
      _updateStatus(applicationId, _AllowedStatus.shortlisted);

  Future<bool> reject(int applicationId) =>
      _updateStatus(applicationId, _AllowedStatus.rejected);

  Future<bool> _updateStatus(int applicationId, _AllowedStatus status) async {
    if (busyApplicationIds.contains(applicationId)) return false;

    busyApplicationIds.add(applicationId);
    actionErrorMessage = null;
    notifyListeners();

    var success = false;
    try {
      final updated = await repository.updateOrganizationApplicationStatus(
        applicationId: applicationId,
        status: status.wireValue,
      );
      applications = [
        for (final application in applications)
          if (application.id == applicationId) updated else application,
      ];
      if (selectedApplication?.id == applicationId) {
        selectedApplication = updated;
      }
      success = true;
    } on ApiException catch (error) {
      actionErrorMessage = error.message;
    } catch (_) {
      // An unexpected parsing/runtime error (e.g. malformed backend data)
      // — never propagates as a raw/uncaught exception, never shows raw
      // exception/stack-trace text, and never touches `applications` or
      // `selectedApplication`, so the old status is preserved exactly as
      // it was before this attempt.
      actionErrorMessage = 'Something went wrong. Please try again.';
    } finally {
      busyApplicationIds.remove(applicationId);
      notifyListeners();
    }
    return success;
  }

  /// Patches a single application's data in place — for use by other
  /// features (e.g. Assessment creation) that change an [ApplicationModel]
  /// outside this provider's own [markReviewed]/[shortlist]/[reject].
  /// Mirrors those methods' existing patch logic (replace the matching
  /// list entry, replace [selectedApplication] when it's the same one)
  /// but is additionally guarded so it never reloads data and never
  /// notifies listeners unless something about the application actually
  /// changed — [ApplicationModel] has no `==` override, and two
  /// separately-parsed responses for the same underlying row are never
  /// `identical()`, so [_sameApplicationData] is used instead of relying
  /// on object identity.
  void patchApplication(ApplicationModel updated) {
    var changed = false;

    final index = applications.indexWhere(
      (application) => application.id == updated.id,
    );
    if (index != -1 && !_sameApplicationData(applications[index], updated)) {
      applications = [
        for (final application in applications)
          if (application.id == updated.id) updated else application,
      ];
      changed = true;
    }

    if (selectedApplication?.id == updated.id &&
        !_sameApplicationData(selectedApplication!, updated)) {
      selectedApplication = updated;
      changed = true;
    }

    if (changed) {
      notifyListeners();
    }
  }

  void clearActionError() {
    actionErrorMessage = null;
    notifyListeners();
  }

  /// Application IDs with a CV download currently in flight — guards
  /// against a duplicate "View CV" tap for the same application, exactly
  /// like [busyApplicationIds] does for status updates.
  final Set<int> _downloadingCvIds = {};
  String? cvDownloadErrorMessage;

  bool isDownloadingCv(int applicationId) =>
      _downloadingCvIds.contains(applicationId);

  /// Downloads the raw PDF bytes of the CV attached to [applicationId]'s
  /// submission via the secure backend endpoint (Phase 8A-4) — only
  /// reachable through an application this organization actually owns
  /// (enforced server-side). Returns `null` on failure (see
  /// [cvDownloadErrorMessage]) — a duplicate call for the same application
  /// while one is already in flight is ignored, returning `null`
  /// immediately without a second request.
  Future<Uint8List?> downloadCv(int applicationId) async {
    if (_downloadingCvIds.contains(applicationId)) return null;

    _downloadingCvIds.add(applicationId);
    cvDownloadErrorMessage = null;
    notifyListeners();

    Uint8List? bytes;
    try {
      bytes = await repository.downloadOrganizationApplicationCv(applicationId);
    } on ApiException catch (error) {
      cvDownloadErrorMessage = error.message;
    } catch (_) {
      cvDownloadErrorMessage = 'Something went wrong. Please try again.';
    } finally {
      _downloadingCvIds.remove(applicationId);
      notifyListeners();
    }
    return bytes;
  }

  /// Clears all organization-application state — called when the signed-in
  /// user changes.
  void reset() {
    applications = [];
    isLoadingList = false;
    listErrorMessage = null;
    selectedApplication = null;
    isLoadingDetails = false;
    detailsErrorMessage = null;
    busyApplicationIds.clear();
    actionErrorMessage = null;
    _pendingListFetch = null;
    _pendingListOpportunityId = null;
    _pendingDetailsFetch = null;
    _downloadingCvIds.clear();
    cvDownloadErrorMessage = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _authProvider.removeListener(_handleAuthChanged);
    super.dispose();
  }
}
