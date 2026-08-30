import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

/// An image file the user has selected but not yet uploaded (Company
/// Profile Polish phase) — a Company Logo, or one "Updates & Achievements"
/// post image. Always carries raw [bytes] rather than a filesystem path,
/// the same reasoning [PickedCvFile] already established: the exact same
/// upload code path then works uniformly on Web, Android, and Windows dev
/// with no platform-specific branching.
class PickedImageFile {
  const PickedImageFile({required this.filename, required this.bytes});

  final String filename;
  final Uint8List bytes;

  int get sizeInBytes => bytes.length;
}

/// Opens the platform file picker restricted to the standard web-safe
/// raster formats (matching the backend's own `mimes:jpg,jpeg,png,webp`
/// validation) and returns the picked bytes, or `null` if the user
/// cancelled or the platform couldn't provide bytes. The real, default
/// implementation — overridable in tests, mirroring
/// `pickCvFileFromDevice()`'s own injectable-function convention.
Future<PickedImageFile?> pickImageFileFromDevice() async {
  final picked = await FilePicker.pickFile(
    type: FileType.custom,
    allowedExtensions: ['jpg', 'jpeg', 'png', 'webp'],
  );
  if (picked == null) return null;

  try {
    final bytes = await picked.readAsBytes();
    return PickedImageFile(filename: picked.name, bytes: bytes);
  } catch (_) {
    return null;
  }
}
