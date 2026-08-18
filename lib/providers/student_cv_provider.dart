import 'package:flutter/foundation.dart';

import '../core/api/api_client.dart';
import '../features/cv/data/cv_repository.dart';
import '../features/cv/data/picked_cv_file.dart';
import '../models/cv_model.dart';
import 'auth_provider.dart';

/// Holds the authenticated student's CV list and exposes create/delete/
/// set-default actions to the UI.
///
/// Loading state is split into independent flags (list, submitting,
/// per-item busy) rather than one shared `isLoading`, so e.g. deleting one
/// card doesn't visually lock the whole screen or an unrelated action.
class StudentCvProvider extends ChangeNotifier {
  StudentCvProvider({required this.repository, required this._authProvider}) {
    _authProvider.addListener(_handleAuthChanged);
  }

  final CvRepository repository;
  final AuthProvider _authProvider;

  List<CvModel> cvs = [];
  bool isLoadingList = false;
  String? listErrorMessage;

  bool isSubmitting = false;
  String? formErrorMessage;

  final Set<int> _busyIds = {};
  String? actionErrorMessage;

  /// The in-flight list fetch, if any — guards against concurrent duplicate
  /// requests (e.g. a rebuild triggering another `loadCvs()` call while one
  /// is already running) without preventing an explicit refresh once the
  /// previous fetch has finished.
  Future<void>? _pendingListFetch;

  bool isBusy(int id) => _busyIds.contains(id);

  /// The student's current default CV, if any — exposed for the future
  /// Student Applications apply flow to pre-select without re-deriving
  /// this search itself.
  CvModel? get defaultCv {
    for (final cv in cvs) {
      if (cv.isDefault) return cv;
    }
    return null;
  }

  void _handleAuthChanged() {
    // A different user may sign in next — don't leak the previous
    // student's CVs into their session.
    if (!_authProvider.isAuthenticated) {
      reset();
    }
  }

  /// Loads the student's CVs. Safe to call repeatedly (e.g. from
  /// `initState` and pull-to-refresh) — a fetch already in flight is
  /// reused rather than duplicated; pass [forceRefresh] to start a fresh
  /// one regardless.
  Future<void> loadCvs({bool forceRefresh = false}) {
    if (forceRefresh) {
      _pendingListFetch = null;
    }
    return _pendingListFetch ??= _performLoad();
  }

  Future<void> _performLoad() async {
    isLoadingList = true;
    listErrorMessage = null;
    notifyListeners();

    try {
      cvs = await repository.getStudentCvs();
    } on ApiException catch (error) {
      listErrorMessage = error.message;
    } catch (_) {
      // An unexpected parsing/runtime error (e.g. malformed backend data) —
      // never leaves the screen stuck loading, and never shows raw
      // exception/stack-trace text to the user.
      listErrorMessage = 'Something went wrong. Please try again.';
    } finally {
      isLoadingList = false;
      _pendingListFetch = null;
      notifyListeners();
    }
  }

  Future<CvModel?> createCv({
    required String title,
    required PickedCvFile file,
  }) async {
    isSubmitting = true;
    formErrorMessage = null;
    notifyListeners();

    CvModel? created;
    try {
      created = await repository.createCv(title: title, file: file);
      cvs = [...cvs, created];
    } on ApiException catch (error) {
      formErrorMessage = _bestErrorMessage(error);
    }

    isSubmitting = false;
    notifyListeners();
    return created;
  }

  /// Picks the most useful message for an [ApiException]: the first
  /// field-specific validation message when one exists (e.g. "The title
  /// field must not be greater than 255 characters."), falling back to the
  /// generic top-level message otherwise. Never surfaces raw exception or
  /// stack-trace text — both sources here are always human-readable
  /// strings the backend itself produced.
  String _bestErrorMessage(ApiException error) {
    final fieldErrors = error.errors;
    if (fieldErrors != null) {
      for (final messages in fieldErrors.values) {
        if (messages.isNotEmpty) return messages.first;
      }
    }
    return error.message;
  }

  /// Application IDs currently in flight -- CV IDs, actually -- guards
  /// against a duplicate "View CV" tap for the same CV, exactly like
  /// [_busyIds] does for delete/set-default.
  final Set<int> _downloadingIds = {};
  String? downloadErrorMessage;

  bool isDownloading(int cvId) => _downloadingIds.contains(cvId);

  /// Downloads the raw PDF bytes for [cvId] via the secure backend
  /// endpoint. Returns `null` on failure (see [downloadErrorMessage]) — a
  /// duplicate call for the same CV while one is already in flight is
  /// ignored, returning `null` immediately without a second request.
  Future<Uint8List?> downloadCv(int cvId) async {
    if (_downloadingIds.contains(cvId)) return null;

    _downloadingIds.add(cvId);
    downloadErrorMessage = null;
    notifyListeners();

    Uint8List? bytes;
    try {
      bytes = await repository.downloadCv(cvId);
    } on ApiException catch (error) {
      downloadErrorMessage = error.message;
    } catch (_) {
      downloadErrorMessage = 'Something went wrong. Please try again.';
    } finally {
      _downloadingIds.remove(cvId);
      notifyListeners();
    }
    return bytes;
  }

  Future<bool> deleteCv(int id) async {
    // Blocks a duplicate delete for the same CV, and also blocks a
    // conflicting set-default on the same CV while one is already in
    // flight — both actions share `_busyIds`, checked before either starts
    // any work.
    if (_busyIds.contains(id)) return false;

    _busyIds.add(id);
    actionErrorMessage = null;
    notifyListeners();

    var success = false;
    try {
      await repository.deleteCv(id);
      cvs = cvs.where((cv) => cv.id != id).toList();
      success = true;
    } on ApiException catch (error) {
      actionErrorMessage = error.message;
    } finally {
      _busyIds.remove(id);
      notifyListeners();
    }
    return success;
  }

  Future<bool> setDefaultCv(int id) async {
    // See deleteCv — the same `_busyIds` guard blocks a duplicate
    // set-default and a conflicting delete on the same CV.
    if (_busyIds.contains(id)) return false;

    _busyIds.add(id);
    actionErrorMessage = null;
    notifyListeners();

    var success = false;
    try {
      final updated = await repository.setDefaultCv(id);
      cvs = [
        for (final cv in cvs)
          if (cv.id == updated.id) updated else cv.copyWith(isDefault: false),
      ];
      success = true;
    } on ApiException catch (error) {
      actionErrorMessage = error.message;
    } finally {
      _busyIds.remove(id);
      notifyListeners();
    }
    return success;
  }

  /// Clears all CV state — called when the signed-in user changes.
  void reset() {
    cvs = [];
    isLoadingList = false;
    listErrorMessage = null;
    isSubmitting = false;
    formErrorMessage = null;
    _busyIds.clear();
    actionErrorMessage = null;
    _pendingListFetch = null;
    _downloadingIds.clear();
    downloadErrorMessage = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _authProvider.removeListener(_handleAuthChanged);
    super.dispose();
  }
}
