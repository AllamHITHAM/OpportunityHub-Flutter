/// Platform-safe document view/download (Admin Education Verification
/// document preview fix).
///
/// Exposes two top-level functions with an identical signature on every
/// platform — `viewDocumentFile(bytes, fileName, mimeType)` and
/// `downloadDocumentFile(bytes, fileName, mimeType)` — resolved via a
/// conditional export so this file (and every caller) never imports a
/// Web-only library directly. `dart.library.html` is the standard,
/// long-established Flutter platform-detection trigger for "this is a Web
/// build".
///
/// Real capability: Web opens the bytes as a blob in a new tab (true
/// in-browser preview) or forces a save, per function. Every other
/// platform (`document_file_opener_io.dart`) writes the bytes to this
/// app's own temp directory and hands the file to the device's own
/// default viewer via `open_filex` — a real, working preview/open, not a
/// fabricated success.
library;

export 'document_file_open_result.dart';
export 'document_file_opener_io.dart'
    if (dart.library.html) 'document_file_opener_web.dart';
