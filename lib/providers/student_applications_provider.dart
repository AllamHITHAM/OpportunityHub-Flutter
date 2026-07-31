import 'package:flutter/foundation.dart';

import '../core/api/api_client.dart';
import '../features/applications/data/application_repository.dart';
import '../models/application_model.dart';
import 'auth_provider.dart';

/// Holds the authenticated student's application list, detail state, and
/// exposes the apply action to the UI.
///
/// Kept entirely separate from `StudentOpportunitiesProvider` — the two
/// serve different state shapes (browsing/search/filters vs.
/// submit/list/detail) over different backend endpoints, the same
/// separation already applied between `StudentCvProvider` and every other
/// student-side provider.
class StudentApplicationsProvider extends ChangeNotifier {
  StudentApplicationsProvider({
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

  bool isSubmitting = false;
  String? formErrorMessage;

  ApplicationModel? selectedApplication;
  bool isLoadingDetails = false;
  String? detailsErrorMessage;

  /// Opportunity IDs with an apply request currently in flight — guards
  /// against a duplicate submission for the same opportunity, exactly like
  /// `StudentCvProvider`'s per-CV busy-ID guard.
  final Set<int> _busyOpportunityIds = {};

  /// The in-flight list fetch, if any — guards against concurrent
  /// duplicate requests without preventing an explicit refresh once the
  /// previous fetch has finished.
  Future<void>? _pendingListFetch;
  Future<void>? _pendingDetailsFetch;

  bool isApplying(int opportunityId) =>
      _busyOpportunityIds.contains(opportunityId);

  /// The only source of truth on the Flutter side for whether the student
  /// has already applied to a given opportunity — derived from the loaded
  /// application list rather than a stored flag on `OpportunityModel`.
  bool hasAppliedTo(int opportunityId) => applications.any(
    (application) => application.opportunityId == opportunityId,
  );

  void _handleAuthChanged() {
    // A different user may sign in next — don't leak the previous
    // student's applications into their session.
    if (!_authProvider.isAuthenticated) {
      reset();
    }
  }

  /// Loads the student's applications. Safe to call repeatedly — a fetch
  /// already in flight is reused rather than duplicated; pass
  /// [forceRefresh] to start a fresh one regardless.
  Future<void> loadApplications({bool forceRefresh = false}) {
    if (forceRefresh) {
      _pendingListFetch = null;
    }
    return _pendingListFetch ??= _performLoad();
  }

  /// An explicit refresh — always starts a fresh fetch.
  Future<void> refresh() => loadApplications(forceRefresh: true);

  Future<void> _performLoad() async {
    isLoadingList = true;
    listErrorMessage = null;
    notifyListeners();

    try {
      applications = await repository.getStudentApplications();
    } on ApiException catch (error) {
      listErrorMessage = error.message;
    } catch (_) {
      // An unexpected parsing/runtime error (e.g. malformed backend data)
      // — never leaves the screen stuck loading, never shows raw
      // exception/stack-trace text.
      listErrorMessage = 'Something went wrong. Please try again.';
    } finally {
      isLoadingList = false;
      _pendingListFetch = null;
      notifyListeners();
    }
  }

  /// Applies to an opportunity. Returns the created application on
  /// success, or `null` on failure (or if an apply for this opportunity is
  /// already in flight).
  Future<ApplicationModel?> apply({
    required int opportunityId,
    required int cvId,
    String? coverLetter,
  }) async {
    if (_busyOpportunityIds.contains(opportunityId)) return null;

    _busyOpportunityIds.add(opportunityId);
    isSubmitting = true;
    formErrorMessage = null;
    notifyListeners();

    ApplicationModel? created;
    try {
      created = await repository.applyToOpportunity(
        opportunityId: opportunityId,
        cvId: cvId,
        coverLetter: coverLetter,
      );
      applications = [...applications, created];
    } on ApiException catch (error) {
      formErrorMessage = _bestErrorMessage(error);
    } finally {
      _busyOpportunityIds.remove(opportunityId);
      isSubmitting = false;
      notifyListeners();
    }
    return created;
  }

  /// Picks the most useful message for an [ApiException]: the first
  /// field-specific validation message when one exists, falling back to
  /// the generic top-level message otherwise (e.g. the 409 "You have
  /// already applied to this opportunity", which has no field errors).
  /// Never surfaces raw exception or stack-trace text.
  String _bestErrorMessage(ApiException error) {
    final fieldErrors = error.errors;
    if (fieldErrors != null) {
      for (final messages in fieldErrors.values) {
        if (messages.isNotEmpty) return messages.first;
      }
    }
    return error.message;
  }

  /// Loads a single application's details. Reuses an already-loaded copy
  /// from the list when available. There is no single-application GET
  /// endpoint on the backend, so when no cached copy exists this loads (or
  /// refreshes) the full list once and resolves the ID from it.
  Future<void> loadApplicationDetails(int id, {bool forceRefresh = false}) {
    if (!forceRefresh) {
      for (final application in applications) {
        if (application.id == id) {
          selectedApplication = application;
          detailsErrorMessage = null;
          notifyListeners();
          return Future.value();
        }
      }
    }
    return _pendingDetailsFetch ??= _performLoadDetails(id);
  }

  Future<void> _performLoadDetails(int id) async {
    isLoadingDetails = true;
    detailsErrorMessage = null;
    notifyListeners();

    await loadApplications(forceRefresh: true);

    if (listErrorMessage != null) {
      detailsErrorMessage = listErrorMessage;
      selectedApplication = null;
    } else {
      final match = applications.where((application) => application.id == id);
      selectedApplication = match.isEmpty ? null : match.first;
      if (selectedApplication == null) {
        detailsErrorMessage = 'Application not found';
      }
    }

    isLoadingDetails = false;
    _pendingDetailsFetch = null;
    notifyListeners();
  }

  /// Clears all application state — called when the signed-in user
  /// changes.
  void reset() {
    applications = [];
    isLoadingList = false;
    listErrorMessage = null;
    isSubmitting = false;
    formErrorMessage = null;
    selectedApplication = null;
    isLoadingDetails = false;
    detailsErrorMessage = null;
    _busyOpportunityIds.clear();
    _pendingListFetch = null;
    _pendingDetailsFetch = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _authProvider.removeListener(_handleAuthChanged);
    super.dispose();
  }
}
