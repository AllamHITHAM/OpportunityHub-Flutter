import 'package:flutter/foundation.dart';

import '../core/api/api_client.dart';
import '../features/student/data/student_profile_repository.dart';
import '../models/student_profile_model.dart';
import 'auth_provider.dart';

/// Holds the authenticated student's profile-completion state and exposes
/// profile actions to the UI.
///
/// [hasChecked] means an attempt was made — successful or not. Whether
/// that attempt actually produced a definitive answer is a separate
/// question ([isProfileStatusKnown]): a failed check (network error, 401,
/// 500, ...) still counts as "attempted", so the router never retries it
/// on every navigation, but it does *not* count as "known", so the router
/// never guesses at completion state from a failed check either.
class StudentProfileProvider extends ChangeNotifier {
  StudentProfileProvider({
    required this.repository,
    required this._authProvider,
  }) {
    _authProvider.addListener(_handleAuthChanged);
  }

  final StudentProfileRepository repository;
  final AuthProvider _authProvider;

  StudentProfileModel? profile;
  bool isLoading = false;
  String? errorMessage;
  bool hasChecked = false;
  bool _checkSucceeded = false;

  /// The in-flight [checkProfileStatus] call, if any.
  ///
  /// This provider is one of the router's `refreshListenable`s, and
  /// `checkProfileStatus` is invoked from redirect logic — so a naive
  /// implementation that calls `notifyListeners()` before [hasChecked]
  /// becomes true would cause the router to re-enter redirect, see
  /// `!hasChecked` again, and start another overlapping check, forever.
  /// Caching the pending future means every re-entrant call during the
  /// same check just awaits the one already in flight, instead of
  /// starting a new one.
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

  /// Asks the backend whether the current student already has a profile,
  /// via the documented 200 (has one) / 404 (doesn't) response of
  /// `GET /api/student/profile`.
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
    errorMessage = null;
    notifyListeners();
  }

  Future<bool> createProfile({
    required String university,
    required String major,
    required int graduationYear,
  }) async {
    isLoading = true;
    errorMessage = null;
    notifyListeners();

    var success = false;
    try {
      profile = await repository.createProfile(
        university: university,
        major: major,
        graduationYear: graduationYear,
      );
      hasChecked = true;
      _checkSucceeded = true;
      success = true;
    } on ApiException catch (error) {
      if (error.statusCode == 409) {
        // The profile may already exist from an earlier request whose
        // response was lost (e.g. a timeout) — verify with the backend
        // rather than assuming either outcome.
        try {
          final existing = await repository.getProfile();
          if (existing != null) {
            profile = existing;
            hasChecked = true;
            _checkSucceeded = true;
            success = true;
          } else {
            errorMessage = error.message;
          }
        } on ApiException catch (verifyError) {
          errorMessage = verifyError.message;
        }
      } else {
        errorMessage = error.message;
      }
    }

    isLoading = false;
    notifyListeners();
    return success;
  }

  void clearError() {
    errorMessage = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _authProvider.removeListener(_handleAuthChanged);
    super.dispose();
  }
}
