import 'package:flutter/foundation.dart';

import '../core/api/api_client.dart';
import '../features/applications/data/application_repository.dart';
import '../models/match_analysis_model.dart';
import 'auth_provider.dart';

/// Holds the currently-viewed application's match analysis (organization
/// side) and exposes the "recalculate" action.
///
/// Kept entirely separate from `OrganizationApplicationsProvider` — match
/// analysis is a structurally distinct concern from recruitment-status
/// review, the same separation already applied throughout this app's other
/// provider pairs (see `OrganizationAssessmentProvider`/
/// `OrganizationOfferProvider`'s own doc comments). Never references
/// `OrganizationApplicationsProvider` directly; the screen layer is
/// responsible for bridging the two — after a successful [recalculate], the
/// screen refreshes the real `Application` (and its `matchScore`) from
/// `OrganizationApplicationsProvider` separately, since [analysis] alone
/// never carries a full `ApplicationModel`.
class OrganizationMatchAnalysisProvider extends ChangeNotifier {
  OrganizationMatchAnalysisProvider({
    required this.repository,
    required this._authProvider,
  }) {
    _authProvider.addListener(_handleAuthChanged);
  }

  final ApplicationRepository repository;
  final AuthProvider _authProvider;

  MatchAnalysisModel? analysis;

  /// Which application [analysis] (or the in-flight fetch) belongs to —
  /// mirrors `OrganizationOfferProvider.loadedApplicationId`'s dual role: it
  /// identifies both the currently in-flight load and the most recently
  /// completed one, so a request for a different application never reuses
  /// this application's in-flight future, and a stale response for an old
  /// application can never overwrite state once a newer application has
  /// been requested.
  int? loadedApplicationId;

  bool isLoading = false;
  bool isRecalculating = false;

  String? errorMessage;
  String? actionErrorMessage;

  /// The in-flight load fetch, if any — guards against concurrent
  /// duplicate requests for the *same* application, without preventing an
  /// explicit refresh once the previous fetch has finished.
  Future<void>? _pendingLoad;

  /// A generation counter identifying the most recently *started* load —
  /// incremented only when a genuinely new [_performLoad] call is created
  /// (never on a deduplicated call that reuses [_pendingLoad]), so two
  /// racing `forceRefresh` calls for the same application can be told apart
  /// even though [loadedApplicationId] is identical for both. Mirrors
  /// `OrganizationOfferProvider._loadGeneration`.
  int _loadGeneration = 0;

  bool hasAnalysisFor(int applicationId) =>
      loadedApplicationId == applicationId && analysis != null;

  void _handleAuthChanged() {
    // A different user may sign in next — don't leak the previous
    // organization's match analysis into their session.
    if (!_authProvider.isAuthenticated) {
      reset();
    }
  }

  /// Loads the match analysis for [applicationId]. Safe to call repeatedly
  /// — a fetch already in flight *for the same application* is reused
  /// rather than duplicated; a request for a different application always
  /// starts its own fresh fetch. Pass [forceRefresh] to start a fresh one
  /// regardless of application.
  ///
  /// A 404 (never analyzed yet, i.e. `match_score` is still `null`) is
  /// treated as a genuine "no analysis" state, not a load failure — mirrors
  /// `OrganizationOfferProvider.loadForApplication`'s treatment of its own
  /// analogous "no Offer yet" 404.
  Future<void> loadForApplication(
    int applicationId, {
    bool forceRefresh = false,
  }) {
    if (forceRefresh || loadedApplicationId != applicationId) {
      _pendingLoad = null;
    }
    loadedApplicationId = applicationId;
    if (_pendingLoad == null) {
      final generation = ++_loadGeneration;
      _pendingLoad = _performLoad(applicationId, generation);
    }
    return _pendingLoad!;
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
      final result = await repository.getApplicationAnalysis(applicationId);
      if (stillCurrent()) {
        analysis = result;
      }
    } on ApiException catch (error) {
      if (stillCurrent()) {
        if (error.statusCode == 404) {
          // Genuinely never analyzed yet — an expected, normal state, never
          // surfaced as a section-level error.
          analysis = null;
        } else {
          errorMessage = error.message;
        }
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
        _pendingLoad = null;
      }
      notifyListeners();
    }
  }

  /// Recalculates the match analysis for [applicationId]. Returns `true`
  /// only on success. A duplicate submission while one is already in
  /// flight is ignored (returns `false` immediately, no second repository
  /// call).
  ///
  /// On success, replaces [analysis] with the freshly-calculated result and
  /// sets [loadedApplicationId] — safe even if no load has happened yet.
  /// On failure, [analysis] is left completely untouched, so a
  /// previously-visible breakdown never disappears because a recalculation
  /// attempt failed.
  Future<bool> recalculate(int applicationId) async {
    if (isRecalculating) return false;

    isRecalculating = true;
    actionErrorMessage = null;
    notifyListeners();

    var success = false;
    try {
      final result = await repository.analyzeApplication(applicationId);
      analysis = result;
      loadedApplicationId = applicationId;
      success = true;
    } on ApiException catch (error) {
      actionErrorMessage = error.message;
    } catch (_) {
      actionErrorMessage = 'Something went wrong. Please try again.';
    } finally {
      isRecalculating = false;
      notifyListeners();
    }
    return success;
  }

  void clearActionError() {
    actionErrorMessage = null;
    notifyListeners();
  }

  /// Clears all match analysis state — called when the signed-in user
  /// changes.
  void reset() {
    analysis = null;
    loadedApplicationId = null;
    isLoading = false;
    errorMessage = null;
    isRecalculating = false;
    actionErrorMessage = null;
    // Invalidates any load still in flight — a stale response arriving
    // after a logout/session change must not repopulate the next
    // organization's state. `loadedApplicationId` is already reset above,
    // which alone makes `stillCurrent()` false for any in-flight fetch;
    // incrementing the generation too is redundant defense-in-depth for
    // the same reason.
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
