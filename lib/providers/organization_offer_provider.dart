import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/api/api_client.dart';
import '../features/offers/data/offer_repository.dart';
import '../features/offers/data/send_offer_input.dart';
import '../models/offer_model.dart';
import 'auth_provider.dart';

/// Holds the currently-viewed application's Offer state (organization
/// side) and exposes the "send an Offer" action.
///
/// Kept entirely separate from `OrganizationApplicationsProvider` — Offer
/// is a structurally distinct concern from recruitment-status review, the
/// same separation already applied throughout this app's other provider
/// pairs (see `OrganizationAssessmentProvider`'s own doc comment). Never
/// references `OrganizationApplicationsProvider` directly; the screen
/// layer is responsible for bridging the two (mirrors how
/// `ScheduleInterviewScreen` bridges `OrganizationAssessmentProvider`/
/// `OrganizationApplicationsProvider`).
///
/// Read-only plus one write action — no student response (accept/decline)
/// belongs here; that's a future `StudentOfferProvider`.
class OrganizationOfferProvider extends ChangeNotifier {
  OrganizationOfferProvider({
    required this.repository,
    required this._authProvider,
  }) {
    _authProvider.addListener(_handleAuthChanged);
  }

  final OfferRepository repository;
  final AuthProvider _authProvider;

  OfferModel? offer;

  /// Which application [offer] (or the in-flight fetch) belongs to —
  /// mirrors `OrganizationAssessmentProvider.loadedApplicationId`'s dual
  /// role: it identifies both the currently in-flight load and the most
  /// recently completed one, so a request for a different application
  /// never reuses this application's in-flight future, and a stale
  /// response for an old application can never overwrite state once a
  /// newer application has been requested.
  int? loadedApplicationId;

  bool isLoading = false;
  String? errorMessage;

  bool isSending = false;
  String? actionErrorMessage;

  /// Raw field-validation errors from the most recent failed send attempt,
  /// keyed exactly as the backend sent them — never renamed/stripped here;
  /// mapping a key back to a specific form field is the form's job, not
  /// this provider's.
  Map<String, List<String>> fieldErrors = {};

  /// The in-flight load fetch, if any — guards against concurrent
  /// duplicate requests for the *same* application, without preventing an
  /// explicit refresh once the previous fetch has finished.
  Future<void>? _pendingLoadFetch;

  /// A generation counter identifying the most recently *started* load —
  /// incremented only when a genuinely new [_performLoad] call is created
  /// (never on a deduplicated call that reuses [_pendingLoadFetch]), so two
  /// racing `forceRefresh` calls for the same application can be told
  /// apart even though [loadedApplicationId] is identical for both.
  /// Mirrors `StudentAssessmentProvider._loadGeneration`.
  int _loadGeneration = 0;

  bool hasOfferFor(int applicationId) =>
      loadedApplicationId == applicationId && offer != null;

  void _handleAuthChanged() {
    // A different user may sign in next — don't leak the previous
    // organization's Offer data into their session.
    if (!_authProvider.isAuthenticated) {
      reset();
    }
  }

  /// Loads the Offer (if any) for [applicationId]. Safe to call repeatedly
  /// — a fetch already in flight *for the same application* is reused
  /// rather than duplicated; a request for a different application always
  /// starts its own fresh fetch. Pass [forceRefresh] to start a fresh one
  /// regardless of application.
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
      final result = await repository.getOrganizationOffer(applicationId);
      if (stillCurrent()) {
        offer = result;
      }
    } on ApiException catch (error) {
      if (stillCurrent()) {
        if (error.statusCode == 404) {
          // Genuinely no Offer yet — an expected, normal state (see
          // OfferRepository.getOrganizationOffer's own doc comment), never
          // surfaced as a section-level error.
          offer = null;
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
        _pendingLoadFetch = null;
      }
      notifyListeners();
    }
  }

  /// Sends an Offer for [applicationId]. Returns `true` only on success. A
  /// duplicate submission while one is already in flight is ignored
  /// (returns `false` immediately, no second repository call).
  Future<bool> sendOffer({
    required int applicationId,
    required SendOfferInput input,
  }) async {
    if (isSending) return false;

    isSending = true;
    actionErrorMessage = null;
    fieldErrors = {};
    notifyListeners();

    var success = false;
    try {
      final sent = await repository.sendOrganizationOffer(
        applicationId: applicationId,
        input: input,
      );
      offer = sent;
      loadedApplicationId = applicationId;
      success = true;
    } on ApiException catch (error) {
      // Deliberately never touches `offer` on failure — a failed send must
      // never make an already-visible Offer (or lack thereof) disappear.
      actionErrorMessage = error.message;
      fieldErrors = error.errors ?? {};
      if (error.statusCode == 409) {
        // A duplicate-Offer conflict means an Offer may already exist for
        // this application (e.g. a race from another session/tab) —
        // refresh in the background so the UI picks up the real state
        // instead of staying stuck showing a stale "no Offer" view.
        unawaited(loadForApplication(applicationId, forceRefresh: true));
      }
    } catch (_) {
      actionErrorMessage = 'Something went wrong. Please try again.';
    } finally {
      isSending = false;
      notifyListeners();
    }
    return success;
  }

  void clearActionErrors() {
    actionErrorMessage = null;
    fieldErrors = {};
    notifyListeners();
  }

  /// Clears all Offer state — called when the signed-in user changes.
  void reset() {
    offer = null;
    loadedApplicationId = null;
    isLoading = false;
    errorMessage = null;
    isSending = false;
    actionErrorMessage = null;
    fieldErrors = {};
    // Invalidates any load still in flight — a stale response arriving
    // after a logout/session change must not repopulate the next
    // organization's state. `loadedApplicationId` is already reset above,
    // which alone makes `stillCurrent()` false for any in-flight fetch;
    // incrementing the generation too is redundant defense-in-depth for
    // the same reason.
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
