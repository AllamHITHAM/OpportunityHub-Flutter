/// Platform-safe CV PDF view/download (UI Phase 6.3).
///
/// Exposes two top-level functions with an identical signature on every
/// platform — `viewCvFile(bytes, fileName)` and
/// `downloadCvFile(bytes, fileName)` — resolved via a conditional export
/// so this file (and every caller) never imports a Web-only library
/// directly. `dart.library.html` is the standard, long-established
/// Flutter platform-detection trigger for "this is a Web build" (`dart:html`
/// still exists, deprecated, on Web only, even though the real
/// implementation below uses the modern `package:web` + `dart:js_interop`
/// instead of importing it).
///
/// Real capability today: Web only (see `cv_file_opener_web.dart`). Every
/// other platform (`cv_file_opener_io.dart`) returns a real, honest
/// failure rather than a fabricated success — see that file's own doc
/// comment.
library;

export 'cv_file_open_result.dart';
export 'cv_file_opener_io.dart'
    if (dart.library.html) 'cv_file_opener_web.dart';
