/// How an Education Verification proof document (or any similarly
/// server-served document) should be presented to the Admin, derived from
/// the response's real `Content-Type` header -- never from a file
/// extension or an assumption, since the backend infers this from actual
/// file bytes (see `Storage::disk('local')->response(...)` on the Laravel
/// side).
enum DocumentPreviewKind { pdf, image, unsupported }

/// Classifies [contentType] (e.g. `"application/pdf"`,
/// `"image/jpeg; charset=binary"`) into a [DocumentPreviewKind]. Only the
/// MIME type before any `;` parameter is considered, case-insensitively.
DocumentPreviewKind previewKindForContentType(String contentType) {
  switch (_normalized(contentType)) {
    case 'application/pdf':
      return DocumentPreviewKind.pdf;
    case 'image/jpeg':
    case 'image/jpg':
    case 'image/png':
      return DocumentPreviewKind.image;
    default:
      return DocumentPreviewKind.unsupported;
  }
}

/// A safe local filename extension for [contentType] — used when writing
/// the document to a temp file (native platforms) or naming a browser
/// download (Web). Falls back to `.bin` for anything unrecognized, which
/// should only ever matter for the "Download Document" fallback path,
/// since [previewKindForContentType] already routes unrecognized types
/// there rather than attempting to preview them.
String fileExtensionForContentType(String contentType) {
  switch (_normalized(contentType)) {
    case 'application/pdf':
      return 'pdf';
    case 'image/png':
      return 'png';
    case 'image/jpeg':
    case 'image/jpg':
      return 'jpg';
    default:
      return 'bin';
  }
}

String _normalized(String contentType) =>
    contentType.split(';').first.trim().toLowerCase();
