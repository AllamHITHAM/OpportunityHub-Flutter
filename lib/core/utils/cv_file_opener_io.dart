import 'dart:typed_data';

import 'cv_file_open_result.dart';

/// Non-Web fallback (Android/iOS/Windows/macOS/Linux) — UI Phase 6.3
/// deliberately does not fake a capability this app doesn't have yet.
/// Opening a system PDF viewer or saving to the platform's real Downloads
/// location needs a platform file/share plugin this project doesn't
/// currently depend on; adding one is out of this phase's scope. Rather
/// than silently doing nothing while still claiming success (the exact
/// bug this phase fixes on Web), this honestly reports the real
/// limitation. See this phase's final report for the reasoning.
Future<CvFileOpenResult> viewCvFile(Uint8List bytes, String fileName) async {
  return const CvFileOpenResult(
    success: false,
    errorMessage: 'Viewing a CV in the app is not yet supported on this platform.',
  );
}

Future<CvFileOpenResult> downloadCvFile(Uint8List bytes, String fileName) async {
  return const CvFileOpenResult(
    success: false,
    errorMessage: 'Downloading a CV is not yet supported on this platform.',
  );
}
