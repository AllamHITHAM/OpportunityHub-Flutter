import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import 'cv_file_open_result.dart';

/// Real Flutter Web implementation (UI Phase 6.3) — the actual root-cause
/// fix. Previously "View CV" only ever fetched the authenticated PDF
/// bytes into memory and showed a SnackBar claiming success; nothing was
/// ever done with the bytes on Web, so no tab opened and nothing appeared
/// in Chrome Downloads. This builds a client-side `Blob` (never a
/// permanent/public URL — the backend endpoint stays exactly as
/// protected as before, since this only ever wraps bytes already fetched
/// through the normal authenticated `Dio` request) and opens it via a
/// synchronous, direct user-gesture-triggered anchor click, which Chrome
/// does not treat as a popup (unlike an async `window.open` call).
Future<CvFileOpenResult> viewCvFile(Uint8List bytes, String fileName) async {
  try {
    final url = web.URL.createObjectURL(_pdfBlob(bytes));
    final anchor = web.HTMLAnchorElement()
      ..href = url
      ..target = '_blank'
      ..rel = 'noopener';
    web.document.body?.append(anchor);
    anchor.click();
    anchor.remove();
    _revokeLater(url);
    return const CvFileOpenResult(success: true);
  } catch (_) {
    return const CvFileOpenResult(
      success: false,
      errorMessage:
          "Couldn't open the CV — your browser may have blocked the new tab.",
    );
  }
}

/// Triggers a real browser download (appears in Chrome Downloads/Ctrl+J)
/// — the `download` attribute on the anchor is what forces a save rather
/// than a navigation, independent of the original response's own
/// `Content-Disposition` (irrelevant here since this is a client-synthesized
/// `blob:` URL, never a direct navigation to the authenticated endpoint).
Future<CvFileOpenResult> downloadCvFile(Uint8List bytes, String fileName) async {
  try {
    final url = web.URL.createObjectURL(_pdfBlob(bytes));
    final anchor = web.HTMLAnchorElement()
      ..href = url
      ..download = fileName;
    web.document.body?.append(anchor);
    anchor.click();
    anchor.remove();
    _revokeLater(url);
    return const CvFileOpenResult(success: true);
  } catch (_) {
    return const CvFileOpenResult(
      success: false,
      errorMessage: "Couldn't download the CV.",
    );
  }
}

web.Blob _pdfBlob(Uint8List bytes) {
  return web.Blob(
    [bytes.toJS].toJS,
    web.BlobPropertyBag(type: 'application/pdf'),
  );
}

/// Revoking immediately can break the new tab/download before it finishes
/// reading the blob — object URLs are cheap and scoped to this page's own
/// lifetime regardless, so a bounded delay is enough to avoid leaking one
/// indefinitely without risking a broken open/download.
void _revokeLater(String url) {
  Future.delayed(const Duration(seconds: 30), () => web.URL.revokeObjectURL(url));
}
