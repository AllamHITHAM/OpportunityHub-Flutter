import 'dart:typed_data';

/// A PDF file the student has selected but not yet uploaded.
///
/// Always carries raw [bytes] rather than a filesystem path, so the exact
/// same upload code path works uniformly on Web (which has no real
/// filesystem path to give), Android, and Windows dev — no
/// platform-specific branching needed in [CvRepository]/[StudentCvProvider].
class PickedCvFile {
  const PickedCvFile({required this.filename, required this.bytes});

  final String filename;
  final Uint8List bytes;

  int get sizeInBytes => bytes.length;
}
