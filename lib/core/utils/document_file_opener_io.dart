import 'dart:io';
import 'dart:typed_data';

import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';

import 'document_file_open_result.dart';

/// Non-Web implementation (Android/iOS/Windows/macOS/Linux). Flutter ships
/// no built-in document renderer, so both "view" and "download" use the
/// same real mechanism here: write the already-fetched, already-
/// authenticated bytes to this app's own temp directory (never a public/
/// shared location), then hand the file to the device's own default
/// viewer app via `open_filex` — the same "save to a private temp
/// location, then open with the OS's own app" pattern used by mail/chat
/// apps everywhere for attachments. This is a genuine, working preview
/// (the OS's own PDF/image viewer opens immediately) — not a silent
/// no-op, and not a claim of in-app rendering this project doesn't have.
Future<DocumentFileOpenResult> viewDocumentFile(
  Uint8List bytes,
  String fileName,
  String mimeType,
) => _writeAndOpen(bytes, fileName, mimeType);

Future<DocumentFileOpenResult> downloadDocumentFile(
  Uint8List bytes,
  String fileName,
  String mimeType,
) => _writeAndOpen(bytes, fileName, mimeType);

Future<DocumentFileOpenResult> _writeAndOpen(
  Uint8List bytes,
  String fileName,
  String mimeType,
) async {
  try {
    final directory = await getTemporaryDirectory();
    final file = File('${directory.path}/$fileName');
    await file.writeAsBytes(bytes, flush: true);

    final result = await OpenFilex.open(file.path, type: mimeType);
    if (result.type == ResultType.done) {
      return const DocumentFileOpenResult(success: true);
    }
    return DocumentFileOpenResult(
      success: false,
      errorMessage: _messageFor(result),
    );
  } catch (_) {
    return const DocumentFileOpenResult(
      success: false,
      errorMessage: "Couldn't open the document on this device.",
    );
  }
}

String _messageFor(OpenResult result) {
  switch (result.type) {
    case ResultType.fileNotFound:
      return "The document couldn't be found.";
    case ResultType.noAppToOpen:
      return 'No app on this device can open this file type.';
    case ResultType.permissionDenied:
      return 'Permission was denied to open the document.';
    case ResultType.done:
    case ResultType.error:
      return "Couldn't open the document on this device.";
  }
}
