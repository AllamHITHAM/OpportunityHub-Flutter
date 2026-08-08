import 'package:flutter/foundation.dart';

import '../core/api/api_client.dart';
import '../features/assessments/data/assessment_repository.dart';
import '../models/assessment_model.dart';
import 'auth_provider.dart';

/// Holds the currently-viewed application's Assessment state for the
/// student side — read-only.
///
/// Kept entirely separate from `OrganizationAssessmentProvider` — different
/// role, different endpoints (`/student/*` vs `/organization/*`), and
/// critically, the organization provider carries create/busy-ID/field-error
/// write-path state that a read-only student provider must never expose.
/// Never references `OrganizationAssessmentProvider`. Mirrors its
/// `loadForApplication`/`loadedApplicationId`/`stillCurrent()` stale-guard
/// pattern for cross-application staleness, plus one addition: a
/// generation counter (see [_loadGeneration]) so two racing `forceRefresh`
/// calls for the *same* application can't let the older one win either —
/// `loadedApplicationId` alone can't detect that case, since it's identical
/// for both calls.
class StudentAssessmentProvider extends ChangeNotifier {
  StudentAssessmentProvider({
    required this.repository,
    required this._authProvider,
  }) {
    _authProvider.addListener(_handleAuthChanged);
  }

  final AssessmentRepository repository;
  final AuthProvider _authProvider;

  AssessmentModel? assessment;

  /// Which application [assessment] (or the in-flight fetch) belongs to —
  /// mirrors `OrganizationAssessmentProvider.loadedApplicationId`'s dual
  /// role: it identifies both the currently in-flight load and the most
  /// recently completed one, so a request for a different application
  /// never reuses this application's in-flight future, and a stale
  /// response for an old application can never overwrite state once a
  /// newer application has been requested.
  int? loadedApplicationId;

  bool isLoading = false;
  String? errorMessage;

  /// The in-flight load fetch, if any — guards against concurrent
  /// duplicate requests for the *same* application, without preventing an
  /// explicit refresh once the previous fetch has finished.
  Future<void>? _pendingLoadFetch;

  /// A generation counter identifying the most recently *started* load —
  /// incremented only when a genuinely new [_performLoad] call is created
  /// (never on a deduplicated call that reuses [_pendingLoadFetch]), so two
  /// racing `forceRefresh` calls for the same application can be told
  /// apart even though [loadedApplicationId] is identical for both.
  int _loadGeneration = 0;

  bool hasAssessmentFor(int applicationId) =>
      loadedApplicationId == applicationId && assessment != null;

  void _handleAuthChanged() {
    // A different student may sign in next — don't leak the previous
    // session's assessment data into theirs.
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
    if (_pendingLoadFetch == null) {
      final generation = ++_loadGeneration;
      _pendingLoadFetch = _performLoad(applicationId, generation);
    }
    return _pendingLoadFetch!;
  }

  Future<void> _performLoad(int applicationId, int generation) async {
    isLoading = true;
    errorMessage = null;
    notifyListeners();

    // Whether this call is still both the current application *and* the
    // most recently started generation for it by the time this fetch
    // resolves — a later call (for a different application, or a newer
    // `forceRefresh` for this same one) may have started while this one
    // was in flight, and its (possibly stale) result must never overwrite
    // the newer request's state.
    bool stillCurrent() =>
        loadedApplicationId == applicationId && generation == _loadGeneration;

    try {
      final result = await repository.getStudentAssessmentForApplication(
        applicationId,
      );
      // `result` is `null` both when the application genuinely has no
      // assessment yet and is treated identically either way — there's no
      // separate "not found" error for this read, matching
      // `getAssessmentForApplication`'s own "no assessment yet" contract.
      if (stillCurrent()) {
        assessment = result;
      }
    } on ApiException catch (error) {
      // Deliberately never touches `assessment` on a *refresh* — a refresh
      // failure must never blank out an assessment the student is already
      // looking at. On a genuinely first load, `assessment` is already
      // `null`, so this has the same effect either way.
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

  /// Clears all assessment state — called when the signed-in student
  /// changes.
  void reset() {
    assessment = null;
    loadedApplicationId = null;
    isLoading = false;
    errorMessage = null;
    // Invalidates any load still in flight — a stale response arriving
    // after a logout/session change must not repopulate the next
    // student's state. `loadedApplicationId` is already reset above, which
    // alone makes `stillCurrent()` false for any in-flight fetch;
    // incrementing the generation too is redundant defense-in-depth for
    // the same reason. Clearing `_pendingLoadFetch` here just means a
    // subsequent `loadForApplication` call starts a genuinely fresh fetch.
    _loadGeneration++;
    _pendingLoadFetch = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _authProvider.removeListener(_handleAuthChanged);
    super.dispose();
  }
}
