import 'package:flutter/foundation.dart';

import '../core/api/api_client.dart';
import '../features/organization_profile/data/picked_image_file.dart';
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

  bool isSubmitting = false;
  String? submitErrorMessage;
  Map<String, List<String>> fieldErrors = {};

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
    isUploadingPhoto = false;
    photoErrorMessage = null;
    notifyListeners();
  }

  Future<bool> createProfile({
    required String university,
    required String major,
    required int graduationYear,
    required List<String> interestedIn,
    int? currentLocationId,
    List<int>? availableLocationIds,
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
        interestedIn: interestedIn,
        currentLocationId: currentLocationId,
        availableLocationIds: availableLocationIds,
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

  /// Updates the student's already-existing profile via `PUT
  /// /api/student/profile`. Returns `true` only once the backend has
  /// confirmed the write — [profile] becomes that canonical response, never
  /// an optimistic guess at what was submitted. A duplicate submission
  /// while one is already in flight is ignored (returns `false`
  /// immediately, no second repository call), mirroring
  /// `StudentCvProvider`'s busy-guard convention.
  Future<bool> updateProfile({
    required String university,
    required String major,
    required int graduationYear,
    required List<String> interestedIn,
    String? phone,
    String? bio,
    int? currentLocationId,
    List<int> availableLocationIds = const [],
  }) async {
    if (isSubmitting) return false;

    isSubmitting = true;
    submitErrorMessage = null;
    fieldErrors = {};
    notifyListeners();

    var success = false;
    try {
      profile = await repository.updateProfile(
        university: university,
        major: major,
        graduationYear: graduationYear,
        interestedIn: interestedIn,
        phone: phone,
        bio: bio,
        currentLocationId: currentLocationId,
        availableLocationIds: availableLocationIds,
      );
      success = true;
    } on ApiException catch (error) {
      submitErrorMessage = error.message;
      fieldErrors = error.errors ?? {};
    } catch (_) {
      submitErrorMessage = 'Something went wrong. Please try again.';
    } finally {
      isSubmitting = false;
      notifyListeners();
    }
    return success;
  }

  // -----------------------------------------------------------------
  // Profile Photo
  // -----------------------------------------------------------------
  //
  // Mirrors `OrganizationProfileProvider.uploadLogo`/`removeLogo`
  // exactly: one busy flag shared by upload+remove, one error string, a
  // busy-guard that ignores a duplicate submission rather than queuing
  // it, and [profile] only ever replaced with the real backend response
  // on success -- never touched on failure, so a failed upload can never
  // make the screen believe a new photo actually persisted or lose the
  // previously-displayed one.

  bool isUploadingPhoto = false;
  String? photoErrorMessage;

  Future<bool> uploadPhoto(PickedImageFile file) async {
    if (isUploadingPhoto) return false;

    isUploadingPhoto = true;
    photoErrorMessage = null;
    notifyListeners();

    var success = false;
    try {
      profile = await repository.uploadPhoto(file);
      success = true;
    } on ApiException catch (error) {
      photoErrorMessage = error.message;
    } catch (_) {
      photoErrorMessage = 'Something went wrong. Please try again.';
    } finally {
      isUploadingPhoto = false;
      notifyListeners();
    }
    return success;
  }

  Future<bool> removePhoto() async {
    if (isUploadingPhoto) return false;

    isUploadingPhoto = true;
    photoErrorMessage = null;
    notifyListeners();

    var success = false;
    try {
      profile = await repository.removePhoto();
      success = true;
    } on ApiException catch (error) {
      photoErrorMessage = error.message;
    } catch (_) {
      photoErrorMessage = 'Something went wrong. Please try again.';
    } finally {
      isUploadingPhoto = false;
      notifyListeners();
    }
    return success;
  }

  void clearPhotoError() {
    photoErrorMessage = null;
    notifyListeners();
  }

  void clearError() {
    errorMessage = null;
    notifyListeners();
  }

  void clearSubmitError() {
    submitErrorMessage = null;
    fieldErrors = {};
    notifyListeners();
  }

  @override
  void dispose() {
    _authProvider.removeListener(_handleAuthChanged);
    super.dispose();
  }
}
