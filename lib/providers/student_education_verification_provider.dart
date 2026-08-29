import 'package:flutter/foundation.dart';

import '../core/api/api_client.dart';
import '../core/utils/cv_file_open_result.dart';
import '../core/utils/cv_file_opener.dart' as file_opener;
import '../features/cv/data/picked_cv_file.dart';
import '../features/education_verification/data/education_verification_repository.dart';
import '../models/education_verification_model.dart';
import 'auth_provider.dart';

/// A real platform action (view or download an already-fetched PDF) --
/// reuses the exact same platform-resolved implementation
/// `StudentCvProvider` uses (`core/utils/cv_file_opener.dart` is a generic
/// bytes-in/real-outcome-out helper despite its CV-era name; nothing about
/// it is CV-specific). Injectable so tests can exercise the full
/// orchestration without a real browser.
typedef DocumentFileAction =
    Future<CvFileOpenResult> Function(Uint8List bytes, String fileName);

/// Holds the authenticated student's own education-verification state and
/// exposes submit/resubmit and real View/Download document actions.
/// Mirrors `StudentCvProvider`'s split loading-state shape (status load vs.
/// submit vs. view vs. download, each independent).
class StudentEducationVerificationProvider extends ChangeNotifier {
  StudentEducationVerificationProvider({
    required this.repository,
    required this._authProvider,
    DocumentFileAction? viewDocumentFile,
    DocumentFileAction? downloadDocumentFile,
  }) : _viewDocumentFile = viewDocumentFile ?? file_opener.viewCvFile,
       _downloadDocumentFile = downloadDocumentFile ?? file_opener.downloadCvFile {
    _authProvider.addListener(_handleAuthChanged);
  }

  final EducationVerificationRepository repository;
  final AuthProvider _authProvider;
  final DocumentFileAction _viewDocumentFile;
  final DocumentFileAction _downloadDocumentFile;

  EducationVerificationModel? verification;
  bool isLoading = false;
  String? errorMessage;

  bool isSubmitting = false;
  String? formErrorMessage;

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

  // -----------------------------------------------------------------
  // View / Download document (Phase 8)
  // -----------------------------------------------------------------
  //
  // Root cause fixed here: the previous single `downloadDocument()`
  // action only ever fetched the authenticated PDF bytes into memory and
  // the screen reported "downloaded" on that alone -- nothing was ever
  // opened or saved. View and Download are now two real, separate
  // actions, both still fetching bytes through the exact same secure
  // `EducationVerificationRepository.downloadDocument` endpoint, then
  // handing off to the platform-resolved opener. Real success means the
  // viewer/tab or the browser download was actually triggered (see
  // [CvFileOpenResult]), never merely that bytes arrived.

  bool isViewingDocument = false;
  String? viewErrorMessage;

  bool isDownloading = false;
  String? downloadErrorMessage;

  /// Opens the student's own document for viewing. [fileName] should be a
  /// real, honest name derived from already-loaded data (e.g. the
  /// institution name) -- never invented metadata like an original
  /// filename the backend doesn't actually store.
  Future<bool> viewDocument(String fileName) => _openFile(
    fileName,
    () => isViewingDocument,
    (value) => isViewingDocument = value,
    _viewDocumentFile,
    (msg) => viewErrorMessage = msg,
  );

  /// Triggers a real browser download of the student's own document.
  Future<bool> downloadDocumentFile(String fileName) => _openFile(
    fileName,
    () => isDownloading,
    (value) => isDownloading = value,
    _downloadDocumentFile,
    (msg) => downloadErrorMessage = msg,
  );

  Future<bool> _openFile(
    String fileName,
    bool Function() isInFlight,
    void Function(bool) setInFlight,
    DocumentFileAction action,
    void Function(String?) setError,
  ) async {
    if (isInFlight()) return false;

    setInFlight(true);
    setError(null);
    notifyListeners();

    var success = false;
    try {
      final bytes = await repository.downloadDocument();
      final result = await action(bytes, fileName);
      success = result.success;
      if (!success) {
        setError(result.errorMessage ?? 'Something went wrong. Please try again.');
      }
    } on ApiException catch (error) {
      setError(error.message);
    } catch (_) {
      setError('Something went wrong. Please try again.');
    } finally {
      setInFlight(false);
      notifyListeners();
    }
    return success;
  }

  void reset() {
    verification = null;
    isLoading = false;
    errorMessage = null;
    isSubmitting = false;
    formErrorMessage = null;
    isViewingDocument = false;
    viewErrorMessage = null;
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
