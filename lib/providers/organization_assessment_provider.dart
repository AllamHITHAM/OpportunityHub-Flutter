import 'package:flutter/foundation.dart';

import '../core/api/api_client.dart';
import '../features/assessments/data/assessment_repository.dart';
import '../features/assessments/data/interview_create_input.dart';
import '../models/assessment_model.dart';
import 'auth_provider.dart';

/// Holds the currently-viewed application's Assessment state and exposes
/// the "create an interview assessment" action.
///
/// Kept entirely separate from `OrganizationApplicationsProvider` and
/// `StudentApplicationsProvider` — Assessment is a structurally distinct
/// concern from recruitment-status review, the same separation already
/// applied throughout this app's other provider pairs. Never references
/// `OrganizationApplicationsProvider` directly; the screen layer is
/// responsible for bridging the two (see
/// `OrganizationApplicationsProvider.patchApplication`).
class OrganizationAssessmentProvider extends ChangeNotifier {
  OrganizationAssessmentProvider({
    required this.repository,
    required this._authProvider,
  }) {
    _authProvider.addListener(_handleAuthChanged);
  }

  final AssessmentRepository repository;
  final AuthProvider _authProvider;

  AssessmentModel? assessment;

  /// Which application [assessment] (or the in-flight fetch) belongs to —
  /// mirrors `OrganizationApplicationsProvider._pendingListOpportunityId`'s
  /// dual role: it identifies both the currently in-flight load and the
  /// most recently completed one, so a request for a different
  /// application never reuses this application's in-flight future, and a
  /// stale response for an old application can never overwrite state once
  /// a newer application has been requested.
  int? loadedApplicationId;

  bool isLoading = false;
  String? errorMessage;

  String? actionErrorMessage;

  /// Raw field-validation errors from the most recent failed create
  /// attempt, keyed exactly as the backend sent them (e.g.
  /// `interview.meeting_link`) — never renamed/stripped here, so no nested
  /// key information is lost; mapping a key back to a specific form field
  /// is the form screen's job, not this provider's.
  Map<String, List<String>> fieldErrors = {};

  /// Application IDs with a create request currently in flight — guards
  /// against a duplicate submission for the same application, exactly like
  /// `OrganizationApplicationsProvider.busyApplicationIds`.
  final Set<int> busyApplicationIds = {};

  /// The in-flight load fetch, if any — guards against concurrent
  /// duplicate requests for the *same* application, without preventing an
  /// explicit refresh once the previous fetch has finished.
  Future<void>? _pendingLoadFetch;

  bool get isCreating => busyApplicationIds.isNotEmpty;

  bool isCreatingFor(int applicationId) =>
      busyApplicationIds.contains(applicationId);

  bool hasAssessmentFor(int applicationId) =>
      loadedApplicationId == applicationId && assessment != null;

  void _handleAuthChanged() {
    // A different user may sign in next — don't leak the previous
    // organization's assessment data into their session.
    if (!_authProvider.isAuthenticated) {
      reset();
    }
  }

  /// Loads the assessment (if any) for [applicationId]. Safe to call
  /// repeatedly — a fetch already in flight *for the same application* is
  /// reused rather than duplicated; a request for a different application
  /// always starts its own fresh fetch. Pass [forceRefresh] to start a
  /// fresh one regardless of application.
  Future<void> loadForApplication(
    int applicationId, {
    bool forceRefresh = false,
  }) {
    if (forceRefresh || loadedApplicationId != applicationId) {
      _pendingLoadFetch = null;
    }
    loadedApplicationId = applicationId;
    return _pendingLoadFetch ??= _performLoad(applicationId);
  }

  Future<void> _performLoad(int applicationId) async {
    isLoading = true;
    errorMessage = null;
    notifyListeners();

    // Whether [applicationId] is still the one currently being requested
    // by the time this fetch resolves — a later call for a *different*
    // application may have started while this one was in flight, and its
    // (possibly stale) result must never overwrite the newer request's
    // state.
    bool stillCurrent() => loadedApplicationId == applicationId;

    try {
      final result = await repository.getAssessmentForApplication(
        applicationId,
      );
      if (stillCurrent()) {
        assessment = result;
      }
    } on ApiException catch (error) {
      if (stillCurrent()) {
        errorMessage = error.message;
      }
    } catch (_) {
      // An unexpected parsing/runtime error (e.g. malformed backend data)
      // — never leaves the section stuck loading, never shows raw
      // exception/stack-trace text.
      if (stillCurrent()) {
        errorMessage = 'Something went wrong. Please try again.';
      }
    } finally {
      if (stillCurrent()) {
        isLoading = false;
        _pendingLoadFetch = null;
      }
      notifyListeners();
    }
  }

  /// Creates an assessment for [applicationId]. Returns `true` only on
  /// success. A duplicate submission for the same application while one is
  /// already in flight is ignored (returns `false` immediately, no second
  /// repository call).
  Future<bool> createAssessment({
    required int applicationId,
    required String type,
    InterviewCreateInput? interviewInput,
  }) async {
    if (busyApplicationIds.contains(applicationId)) return false;

    busyApplicationIds.add(applicationId);
    actionErrorMessage = null;
    fieldErrors = {};
    notifyListeners();

    var success = false;
    try {
      final created = await repository.createAssessment(
        applicationId: applicationId,
        type: type,
        interviewInput: interviewInput,
      );
      assessment = created;
      loadedApplicationId = applicationId;
      success = true;
    } on ApiException catch (error) {
      actionErrorMessage = error.message;
      fieldErrors = error.errors ?? {};
    } catch (_) {
      // An unexpected parsing/runtime error — never propagates as a raw
      // exception, never shows raw exception/stack-trace text, and never
      // touches `assessment`, so the previous state is preserved exactly
      // as it was before this attempt.
      actionErrorMessage = 'Something went wrong. Please try again.';
    } finally {
      busyApplicationIds.remove(applicationId);
      notifyListeners();
    }
    return success;
  }

  void clearActionError() {
    actionErrorMessage = null;
    notifyListeners();
  }

  void clearFieldErrors() {
    fieldErrors = {};
    notifyListeners();
  }

  /// Clears all assessment state — called when the signed-in user changes.
  void reset() {
    assessment = null;
    loadedApplicationId = null;
    isLoading = false;
    errorMessage = null;
    actionErrorMessage = null;
    fieldErrors = {};
    busyApplicationIds.clear();
    _pendingLoadFetch = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _authProvider.removeListener(_handleAuthChanged);
    super.dispose();
  }
}
