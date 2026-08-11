import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/api/api_client.dart';
import '../features/offers/data/offer_repository.dart';
import '../models/offer_model.dart';
import 'auth_provider.dart';

/// Holds the currently-viewed application's Offer state (student side) and
/// exposes the accept/decline response actions.
///
/// Kept entirely separate from `StudentApplicationsProvider` — Offer is a
/// structurally distinct concern from the application itself, the same
/// separation already applied on the organization side (see
/// `OrganizationOfferProvider`'s own doc comment). Never references
/// `StudentApplicationsProvider` directly; the screen layer is responsible
/// for bridging the two (mirrors how `SendOfferSheet`/
/// `OrganizationApplicationDetailsScreen` bridge `OrganizationOfferProvider`/
/// `OrganizationApplicationsProvider`).
///
/// Read-only plus the one-time accept/decline response — no send/edit/
/// cancel/resend belongs here; those are organization-only actions.
class StudentOfferProvider extends ChangeNotifier {
  StudentOfferProvider({
    required this.repository,
    required this._authProvider,
  }) {
    _authProvider.addListener(_handleAuthChanged);
  }

  final OfferRepository repository;
  final AuthProvider _authProvider;

  OfferModel? offer;

  /// Which application [offer] (or the in-flight fetch) belongs to —
  /// mirrors `OrganizationOfferProvider.loadedApplicationId`'s dual role:
  /// it identifies both the currently in-flight load and the most recently
  /// completed one, so a request for a different application never reuses
  /// this application's in-flight future, and a stale response for an old
  /// application can never overwrite state once a newer application has
  /// been requested.
  int? loadedApplicationId;

  bool isLoading = false;
  String? errorMessage;

  bool isResponding = false;
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

  bool hasOfferFor(int applicationId) =>
      loadedApplicationId == applicationId && offer != null;

  void _handleAuthChanged() {
    // A different user may sign in next — don't leak the previous
    // student's Offer data into their session.
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
      final result = await repository.getStudentOffer(applicationId);
      if (stillCurrent()) {
        offer = result;
      }
    } on ApiException catch (error) {
      if (stillCurrent()) {
        if (error.statusCode == 404) {
          // Genuinely no Offer yet — an expected, normal state (see
          // OfferRepository.getStudentOffer's own doc comment), never
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
        _pendingLoad = null;
      }
      notifyListeners();
    }
  }

  /// Accepts the currently-loaded Offer. Returns `true` only on success. A
  /// duplicate submission while one is already in flight, or when there is
  /// no Offer loaded, is ignored (returns `false` immediately, no
  /// repository call).
  Future<bool> accept() => _respond(repository.acceptStudentOffer);

  /// Declines the currently-loaded Offer. See [accept] for the shared
  /// behavior.
  Future<bool> decline() => _respond(repository.declineStudentOffer);

  Future<bool> _respond(
    Future<OfferModel> Function(int offerId) respond,
  ) async {
    final currentOffer = offer;
    if (isResponding || currentOffer == null) return false;

    final applicationId = loadedApplicationId;
    isResponding = true;
    actionErrorMessage = null;
    notifyListeners();

    var success = false;
    try {
      final responded = await respond(currentOffer.id);
      offer = responded;
      success = true;
    } on ApiException catch (error) {
      // Deliberately never touches `offer` on failure — a failed response
      // must never make the already-visible Offer disappear or appear to
      // change state it didn't actually reach.
      actionErrorMessage = error.message;
      if (error.statusCode == 409 && applicationId != null) {
        // The Offer has already been responded to (e.g. a race from
        // another session/tab) — refresh in the background so the UI
        // picks up the real state instead of staying stuck showing the
        // pre-response Offer.
        unawaited(loadForApplication(applicationId, forceRefresh: true));
      }
    } catch (_) {
      actionErrorMessage = 'Something went wrong. Please try again.';
    } finally {
      isResponding = false;
      notifyListeners();
    }
    return success;
  }

  void clearActionError() {
    actionErrorMessage = null;
    notifyListeners();
  }

  /// Clears all Offer state — called when the signed-in user changes.
  void reset() {
    offer = null;
    loadedApplicationId = null;
    isLoading = false;
    errorMessage = null;
    isResponding = false;
    actionErrorMessage = null;
    // Invalidates any load still in flight — a stale response arriving
    // after a logout/session change must not repopulate the next
    // student's state. `loadedApplicationId` is already reset above, which
    // alone makes `stillCurrent()` false for any in-flight fetch;
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
