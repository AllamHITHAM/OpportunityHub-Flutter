/// The real, truthful outcome of attempting to view or download a server
/// document from already-fetched bytes (Admin Education Verification
/// document preview fix). Never assumed successful just because the bytes
/// themselves were fetched — see `document_file_opener_web.dart`/
/// `document_file_opener_io.dart` for what each platform actually does
/// with them. Mirrors `CvFileOpenResult`'s own shape, kept as a separate
/// type so this document-preview flow never depends on the unrelated CV
/// feature's files.
class DocumentFileOpenResult {
  const DocumentFileOpenResult({required this.success, this.errorMessage});

  final bool success;

  /// A safe, user-facing message — never a raw exception/stack trace.
  /// Only meaningful when [success] is false.
  final String? errorMessage;
}
