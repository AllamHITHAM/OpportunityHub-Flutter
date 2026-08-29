import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import 'document_file_open_result.dart';

/// Real Flutter Web implementation. Builds a client-side `Blob` from
/// already-fetched, already-authenticated bytes (never a permanent/public
/// URL — the backend endpoint stays exactly as protected as before, since
/// this only ever wraps bytes already fetched through the normal
/// authenticated `Dio` request) and opens it via a synchronous, direct
/// user-gesture-triggered anchor click, which Chrome does not treat as a
/// popup (unlike an async `window.open` call). No `download` attribute is
/// set here, so the browser renders the blob inline in the new tab —
/// PDFs preview natively; a browser without an image mime handler would
/// still just display the image directly, since `<img>`-style rendering
/// is how browsers natively handle a blob URL navigation for image types.
Future<DocumentFileOpenResult> viewDocumentFile(
  Uint8List bytes,
  String fileName,
  String mimeType,
) async {
  try {
    final url = web.URL.createObjectURL(_blob(bytes, mimeType));
    final anchor = web.HTMLAnchorElement()
      ..href = url
      ..target = '_blank'
      ..rel = 'noopener';
    web.document.body?.append(anchor);
    anchor.click();
    anchor.remove();
    _revokeLater(url);
    return const DocumentFileOpenResult(success: true);
  } catch (_) {
    return const DocumentFileOpenResult(
      success: false,
      errorMessage:
          "Couldn't open the document — your browser may have blocked the new tab.",
    );
  }
}

/// Triggers a real browser download (appears in Chrome Downloads/Ctrl+J)
/// — the `download` attribute on the anchor is what forces a save rather
/// than a navigation, independent of the original response's own
/// `Content-Disposition` (irrelevant here since this is a client-synthesized
/// `blob:` URL, never a direct navigation to the authenticated endpoint).
/// Used as the explicit fallback for a file type this app can't preview.
Future<DocumentFileOpenResult> downloadDocumentFile(
  Uint8List bytes,
  String fileName,
  String mimeType,
) async {
  try {
    final url = web.URL.createObjectURL(_blob(bytes, mimeType));
    final anchor = web.HTMLAnchorElement()
      ..href = url
      ..download = fileName;
    web.document.body?.append(anchor);
    anchor.click();
    anchor.remove();
    _revokeLater(url);
    return const DocumentFileOpenResult(success: true);
  } catch (_) {
    return const DocumentFileOpenResult(
      success: false,
      errorMessage: "Couldn't download the document.",
    );
  }
}

web.Blob _blob(Uint8List bytes, String mimeType) {
  return web.Blob(
    [bytes.toJS].toJS,
    web.BlobPropertyBag(type: mimeType),
  );
}

/// Revoking immediately can break the new tab/download before it finishes
/// reading the blob — object URLs are cheap and scoped to this page's own
/// lifetime regardless, so a bounded delay is enough to avoid leaking one
/// indefinitely without risking a broken open/download.
void _revokeLater(String url) {
  Future.delayed(
    const Duration(seconds: 30),
    () => web.URL.revokeObjectURL(url),
  );
}
