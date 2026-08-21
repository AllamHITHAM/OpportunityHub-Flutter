import 'package:flutter/foundation.dart';

import '../core/api/api_client.dart';
import '../features/cv/data/picked_cv_file.dart';
import '../features/education_verification/data/education_verification_repository.dart';
import '../models/education_verification_model.dart';
import 'auth_provider.dart';

/// Holds the authenticated student's own education-verification state and
/// exposes submit/resubmit and document-download actions. Mirrors
/// `StudentCvProvider`'s split loading-state shape (list load vs. submit
/// vs. download, each independent).
class StudentEducationVerificationProvider extends ChangeNotifier {
  StudentEducationVerificationProvider({
    required this.repository,
    required this._authProvider,
  }) {
    _authProvider.addListener(_handleAuthChanged);
  }

  final EducationVerificationRepository repository;
  final AuthProvider _authProvider;

  EducationVerificationModel? verification;
  bool isLoading = false;
  String? errorMessage;

  bool isSubmitting = false;
  String? formErrorMessage;

  bool isDownloading = false;
  String? downloadErrorMessage;

  /// The in-flight status fetch, if any — guards against concurrent
  /// duplicate requests. Mirrors `StudentCvProvider._pendingListFetch`.
  Future<void>? _pendingFetch;

  void _handleAuthChanged() {
    if (!_authProvider.isAuthenticated) {
      reset();
    }
  }

  Future<void> load({bool forceRefresh = false}) {
    if (forceRefresh) {
      _pendingFetch = null;
    }
    return _pendingFetch ??= _performLoad();
  }

  Future<void> _performLoad() async {
    isLoading = true;
    errorMessage = null;
    notifyListeners();

    try {
      verification = await repository.getStatus();
    } on ApiException catch (error) {
      errorMessage = error.message;
    } catch (_) {
      errorMessage = 'Something went wrong. Please try again.';
    } finally {
      isLoading = false;
      _pendingFetch = null;
      notifyListeners();
    }
  }

  /// Submits (first time) or resubmits (after a rejection) the education
  /// document. Returns `true` only on success, in which case
  /// [verification] is updated immediately from the response -- no
  /// separate reload needed. On failure, the previous [verification] is
  /// left untouched (see [formErrorMessage]).
  Future<bool> submit({
    required String institutionName,
    required String degreeOrProgram,
    required PickedCvFile file,
  }) async {
    isSubmitting = true;
    formErrorMessage = null;
    notifyListeners();

    var success = false;
    try {
      verification = await repository.submit(
        institutionName: institutionName,
        degreeOrProgram: degreeOrProgram,
        file: file,
      );
      success = true;
    } on ApiException catch (error) {
      formErrorMessage = _bestErrorMessage(error);
    } catch (_) {
      formErrorMessage = 'Something went wrong. Please try again.';
    } finally {
      isSubmitting = false;
      notifyListeners();
    }
    return success;
  }

  /// Picks the most useful message for an [ApiException] -- the first
  /// field-specific validation message when one exists, falling back to
  /// the generic top-level message (e.g. the 409 "already verified")
  /// otherwise. Mirrors `StudentCvProvider._bestErrorMessage`.
  String _bestErrorMessage(ApiException error) {
    final fieldErrors = error.errors;
    if (fieldErrors != null) {
      for (final messages in fieldErrors.values) {
        if (messages.isNotEmpty) return messages.first;
      }
    }
    return error.message;
  }

  /// Downloads the student's own document. Returns `null` on failure (see
  /// [downloadErrorMessage]) -- a duplicate call while one is already in
  /// flight is ignored, returning `null` immediately.
  Future<Uint8List?> downloadDocument() async {
    if (isDownloading) return null;

    isDownloading = true;
    downloadErrorMessage = null;
    notifyListeners();

    Uint8List? bytes;
    try {
      bytes = await repository.downloadDocument();
    } on ApiException catch (error) {
      downloadErrorMessage = error.message;
    } catch (_) {
      downloadErrorMessage = 'Something went wrong. Please try again.';
    } finally {
      isDownloading = false;
      notifyListeners();
    }
    return bytes;
  }

  void reset() {
    verification = null;
    isLoading = false;
    errorMessage = null;
    isSubmitting = false;
    formErrorMessage = null;
    isDownloading = false;
    downloadErrorMessage = null;
    _pendingFetch = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _authProvider.removeListener(_handleAuthChanged);
    super.dispose();
  }
}
