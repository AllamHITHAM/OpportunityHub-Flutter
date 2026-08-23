/// The real, truthful outcome of attempting to view or download a CV PDF
/// from already-fetched bytes (UI Phase 6.3). Never assumed successful
/// just because the bytes themselves were fetched — see
/// `cv_file_opener_web.dart`/`cv_file_opener_io.dart` for what each
/// platform actually does with them.
class CvFileOpenResult {
  const CvFileOpenResult({required this.success, this.errorMessage});

  final bool success;

  /// A safe, user-facing message — never a raw exception/stack trace.
  /// Only meaningful when [success] is false.
  final String? errorMessage;
}
