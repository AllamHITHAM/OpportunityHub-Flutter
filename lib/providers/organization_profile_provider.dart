import 'package:flutter/foundation.dart';

import '../core/api/api_client.dart';
import '../features/organization/data/organization_profile_repository.dart';
import '../models/organization_profile_model.dart';
import 'auth_provider.dart';

/// Holds the authenticated organization's profile-completion state.
///
/// Unlike [StudentProfileProvider], there's no `createProfile` action here —
/// an organization's profile is created atomically with the account by
/// `AuthProvider.registerOrganization`, not as a separate later step. This
/// provider exists to answer one question for the router: does the
/// authenticated organization have a profile?
///
/// [hasChecked] means an attempt was made — successful or not. Whether that
/// attempt actually produced a definitive answer is a separate question
/// ([isProfileStatusKnown]): a failed check (network error, 401, 500, ...)
/// still counts as "attempted", so the router never retries it on every
/// navigation, but it does *not* count as "known", so the router never
/// guesses at completion state from a failed check either. This mirrors
/// StudentProfileProvider's proven pattern exactly, including the
/// in-flight-request guard that prevents the router-driven check from
/// re-entering itself (see `checkProfileStatus`).
class OrganizationProfileProvider extends ChangeNotifier {
  OrganizationProfileProvider({
    required this.repository,
    required this._authProvider,
  }) {
    _authProvider.addListener(_handleAuthChanged);
  }

  final OrganizationProfileRepository repository;
  final AuthProvider _authProvider;

  OrganizationProfileModel? profile;
  bool hasChecked = false;
  bool _checkSucceeded = false;

  /// The in-flight [checkProfileStatus] call, if any. See
  /// StudentProfileProvider for why this guard is required: without it, a
  /// router redirect awaiting this check would re-enter itself via its own
  /// notifyListeners() before hasChecked becomes true, looping forever.
  Future<void>? _pendingCheck;

  bool get hasProfile => profile != null;

  /// True only once the backend has actually given a definitive 200/404
  /// answer. False both before checking and after a failed check attempt
  /// — in either case nothing should be inferred about completion state.
  bool get isProfileStatusKnown => hasChecked && _checkSucceeded;

  void _handleAuthChanged() {
    // A different user may sign in next — don't leak the previous one's
    // profile-completion state into their session.
    if (!_authProvider.isAuthenticated && hasChecked) {
      reset();
    }
  }

  /// Asks the backend whether the current organization has a profile, via
  /// the documented 200 (has one) / 404 (doesn't) response of
  /// `GET /api/organization/profile`.
  ///
  /// Sets [hasChecked] regardless of outcome, so the router only attempts
  /// this once per sign-in rather than retrying on every navigation — a
  /// failure leaves [isProfileStatusKnown] `false`, so callers still treat
  /// completion as unknown rather than assuming either outcome.
  Future<void> checkProfileStatus() {
    return _pendingCheck ??= _performCheck();
  }

  Future<void> _performCheck() async {
    try {
      profile = await repository.getProfile();
      _checkSucceeded = true;
    } on ApiException {
      _checkSucceeded = false;
    }
    hasChecked = true;

    _pendingCheck = null;
    notifyListeners();
  }

  /// Clears all profile state — called when the signed-in user changes.
  void reset() {
    profile = null;
    hasChecked = false;
    _checkSucceeded = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _authProvider.removeListener(_handleAuthChanged);
    super.dispose();
  }
}
