import 'package:flutter/foundation.dart';

import '../core/api/api_client.dart';
import '../core/utils/document_file_open_result.dart';
import '../core/utils/document_file_opener.dart' as file_opener;
import '../core/utils/document_preview_kind.dart';
import '../features/admin/data/admin_education_verifications_repository.dart';
import '../models/admin_education_verification_model.dart';
import 'auth_provider.dart';

typedef DocumentFileAction =
    Future<DocumentFileOpenResult> Function(
      Uint8List bytes,
      String fileName,
      String mimeType,
    );

/// The outcome of [AdminEducationVerificationsProvider.viewDocument] — the
/// screen branches on this rather than assuming "bytes arrived" means
/// "the Admin can now see the document" (that assumption was the exact
/// root cause of the original bug: bytes were fetched and silently
/// dropped).
class EducationDocumentViewResult {
  /// The document is an image — the screen should push an in-app preview
  /// with [imageBytes] (works identically on every platform, no plugin
  /// needed).
  const EducationDocumentViewResult.image(this.imageBytes)
    : success = true,
      unsupportedContentType = null,
      errorMessage = null;

  /// The document is a PDF and the platform opener already handed it to
  /// a real viewer (a new browser tab on Web, the device's own PDF app on
  /// native platforms) — there's nothing further for the screen to do.
  const EducationDocumentViewResult.opened()
    : success = true,
      imageBytes = null,
      unsupportedContentType = null,
      errorMessage = null;

  /// The document's real content-type isn't one this app can preview —
  /// the screen should offer an explicit "Download Document" fallback
  /// rather than attempting (and silently failing) a preview.
  const EducationDocumentViewResult.unsupported(this.unsupportedContentType)
    : success = false,
      imageBytes = null,
      errorMessage = null;

  /// A real failure — missing document, forbidden, corrupt, or a server
  /// error. [errorMessage] is always safe to show directly.
  const EducationDocumentViewResult.failed(this.errorMessage)
    : success = false,
      imageBytes = null,
      unsupportedContentType = null;

  /// A duplicate call while one is already in flight for this row — the
  /// screen does nothing with this (the row's own busy state already
  /// reflects the in-flight request).
  const EducationDocumentViewResult.noop()
    : success = false,
      imageBytes = null,
      unsupportedContentType = null,
      errorMessage = null;

  final bool success;
  final Uint8List? imageBytes;
  final String? unsupportedContentType;
  final String? errorMessage;
}

/// Holds the Admin education-verification review list and exposes the
/// verify/reject actions (Phase 8B-1). Mirrors
/// `AdminSkillSuggestionsProvider`'s shape.
class AdminEducationVerificationsProvider extends ChangeNotifier {
  AdminEducationVerificationsProvider({
    required this.repository,
    required this._authProvider,
    DocumentFileAction? viewDocumentFile,
    DocumentFileAction? downloadDocumentFile,
  }) : _viewDocumentFile = viewDocumentFile ?? file_opener.viewDocumentFile,
       _downloadDocumentFile =
           downloadDocumentFile ?? file_opener.downloadDocumentFile {
    _authProvider.addListener(_handleAuthChanged);
  }

  final AdminEducationVerificationsRepository repository;
  final AuthProvider _authProvider;

  /// The real platform action for view/download — injectable so tests can
  /// exercise the full orchestration (fetch bytes → classify → hand off →
  /// real success/failure) without a real browser or device. Defaults to
  /// the real, platform-resolved implementation
  /// (`document_file_opener.dart`).
  final DocumentFileAction _viewDocumentFile;
  final DocumentFileAction _downloadDocumentFile;

  List<AdminEducationVerificationModel> verifications = [];
  bool isLoading = false;
  String? errorMessage;

  String? actionErrorMessage;

  /// Verification ids with a verify/reject/document request currently in
  /// flight — guards against a duplicate action for the same row.
  final Set<int> busyIds = {};

  Future<void>? _pendingLoad;

  bool isBusy(int verificationId) => busyIds.contains(verificationId);

  void _handleAuthChanged() {
    if (!_authProvider.isAuthenticated) {
      reset();
    }
  }

  Future<void> load({bool forceRefresh = false}) {
    if (forceRefresh) {
      _pendingLoad = null;
    }
    return _pendingLoad ??= _performLoad();
  }

  Future<void> _performLoad() async {
    isLoading = true;
    errorMessage = null;
    notifyListeners();

    try {
      verifications = await repository.getVerifications();
    } on ApiException catch (error) {
      errorMessage = error.message;
    } catch (_) {
      errorMessage = 'Something went wrong. Please try again.';
    } finally {
      isLoading = false;
      _pendingLoad = null;
      notifyListeners();
    }
  }

  // -----------------------------------------------------------------
  // View / Download document (Admin Education Verification document
  // preview fix)
  // -----------------------------------------------------------------
  //
  // Root cause fixed here: "View Document" previously only ever fetched
  // the authenticated document bytes into memory and reported success on
  // that alone (a SnackBar showing the byte count) — nothing was ever
  // done with the bytes, so no preview appeared and nothing was
  // reachable. [viewDocument] now classifies the real content-type and
  // either hands image bytes back to the screen for an in-app preview, or
  // hands PDF bytes to the platform-resolved opener — real success means
  // a viewer/tab was actually opened, per [DocumentFileOpenResult], never
  // merely that bytes arrived. [downloadDocument] remains as the explicit
  // fallback action for a content-type this app can't preview.

  String? viewErrorMessage;

  /// Fetches and classifies the document for [verificationId], then either
  /// hands back image bytes for an in-app preview, opens a PDF via the
  /// platform opener, or reports the content-type is unsupported — see
  /// [EducationDocumentViewResult]. Shares [busyIds] with verify/reject/
  /// downloadDocument, so any of them in flight for a row blocks a
  /// duplicate action on that same row.
  Future<EducationDocumentViewResult> viewDocument(int verificationId) async {
    if (busyIds.contains(verificationId)) {
      return const EducationDocumentViewResult.noop();
    }

    busyIds.add(verificationId);
    viewErrorMessage = null;
    notifyListeners();

    var result = const EducationDocumentViewResult.noop();
    try {
      final document = await repository.downloadDocument(verificationId);
      switch (previewKindForContentType(document.contentType)) {
        case DocumentPreviewKind.image:
          result = EducationDocumentViewResult.image(document.bytes);
        case DocumentPreviewKind.pdf:
          final fileName = 'education-verification-$verificationId.pdf';
          final opened = await _viewDocumentFile(
            document.bytes,
            fileName,
            document.contentType,
          );
          result = opened.success
              ? const EducationDocumentViewResult.opened()
              : EducationDocumentViewResult.failed(
                  opened.errorMessage ??
                      'Something went wrong. Please try again.',
                );
        case DocumentPreviewKind.unsupported:
          result = EducationDocumentViewResult.unsupported(
            document.contentType,
          );
      }
    } on ApiException catch (error) {
      result = EducationDocumentViewResult.failed(error.message);
    } catch (_) {
      result = const EducationDocumentViewResult.failed(
        'Something went wrong. Please try again.',
      );
    } finally {
      viewErrorMessage = result.errorMessage;
      busyIds.remove(verificationId);
      notifyListeners();
    }
    return result;
  }

  String? downloadErrorMessage;

  /// The explicit "Download Document" fallback for a content-type
  /// [viewDocument] reported as unsupported (or as a manual retry after a
  /// failed view). Returns `true` only if the platform opener reports a
  /// real success (see [downloadErrorMessage] otherwise) — shares
  /// [busyIds] with verify/reject/viewDocument, so a download in flight
  /// for a row also blocks a duplicate action on that same row.
  Future<bool> downloadDocument(int verificationId) async {
    if (busyIds.contains(verificationId)) return false;

    busyIds.add(verificationId);
    downloadErrorMessage = null;
    notifyListeners();

    var success = false;
    try {
      final document = await repository.downloadDocument(verificationId);
      final extension = fileExtensionForContentType(document.contentType);
      final fileName = 'education-verification-$verificationId.$extension';
      final result = await _downloadDocumentFile(
        document.bytes,
        fileName,
        document.contentType,
      );
      success = result.success;
      if (!success) {
        downloadErrorMessage =
            result.errorMessage ?? 'Something went wrong. Please try again.';
      }
    } on ApiException catch (error) {
      downloadErrorMessage = error.message;
    } catch (_) {
      downloadErrorMessage = 'Something went wrong. Please try again.';
    } finally {
      busyIds.remove(verificationId);
      notifyListeners();
    }
    return success;
  }

  /// Approves [verificationId] and removes it from the local list on
  /// success. Returns `true` only on success.
  Future<bool> verify(int verificationId) =>
      _review(verificationId, (id) => repository.verify(id));

  /// Rejects [verificationId] with [reason] and removes it from the local
  /// list on success. Returns `true` only on success.
  Future<bool> reject(int verificationId, {required String reason}) =>
      _review(verificationId, (id) => repository.reject(id, reason: reason));

  Future<bool> _review(
    int verificationId,
    Future<void> Function(int) call,
  ) async {
    if (busyIds.contains(verificationId)) return false;

    busyIds.add(verificationId);
    actionErrorMessage = null;
    notifyListeners();

    var success = false;
    try {
      await call(verificationId);
      verifications = verifications
          .where((verification) => verification.id != verificationId)
          .toList();
      success = true;
    } on ApiException catch (error) {
      actionErrorMessage = error.message;
    } catch (_) {
      actionErrorMessage = 'Something went wrong. Please try again.';
    } finally {
      busyIds.remove(verificationId);
      notifyListeners();
    }
    return success;
  }

  void reset() {
    verifications = [];
    isLoading = false;
    errorMessage = null;
    actionErrorMessage = null;
    viewErrorMessage = null;
    downloadErrorMessage = null;
    busyIds.clear();
    _pendingLoad = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _authProvider.removeListener(_handleAuthChanged);
    super.dispose();
  }
}
