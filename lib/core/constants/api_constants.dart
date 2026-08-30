import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb, visibleForTesting;

/// Constants used to talk to the Laravel backend API.
class ApiConstants {
  ApiConstants._();

  /// The complete Laravel API root, supplied at build time via
  /// `--dart-define=API_BASE_URL=https://<host>/api` (staging/production
  /// builds). Empty when not supplied -- the normal case for local
  /// development, where [baseUrl] falls back to the addresses below
  /// instead of requiring this define.
  ///
  /// Expected to already include `/api` when configured -- see
  /// [baseUrl]'s doc comment. Nothing in this app ever appends another
  /// `/api` to it.
  static const String _configuredBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
  );

  /// The base URL of the Laravel API.
  ///
  /// Prefers the build-time `API_BASE_URL` define when one was supplied
  /// (see [_configuredBaseUrl]), normalized via [normalizeBaseUrl] so a
  /// trailing slash on the configured value can never combine with an
  /// endpoint path's own leading slash (every path passed to
  /// `ApiClient.dio` starts with `/`, e.g. `/admin/skills`) to produce a
  /// double slash. The configured value is trusted to already be the
  /// complete API root, `/api` included -- nothing here appends or
  /// duplicates that segment, and a genuinely-supplied value is never
  /// silently replaced by the local fallback below.
  ///
  /// Falls back to the existing local-development addresses when
  /// `API_BASE_URL` isn't supplied, so local work never requires passing
  /// `--dart-define`:
  /// - Flutter Web and desktop (Windows/macOS/Linux) talk to the host
  ///   machine directly, since the server runs on the same machine.
  /// - The Android emulator maps the host machine to 10.0.2.2 instead.
  static String get baseUrl {
    if (_configuredBaseUrl.isNotEmpty) {
      return normalizeBaseUrl(_configuredBaseUrl);
    }
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      return 'http://10.0.2.2:8000/api';
    }
    return 'http://127.0.0.1:8000/api';
  }

  /// Trims surrounding whitespace and any trailing slash(es) from a
  /// configured base URL. A plain, non-compile-time-constant-dependent
  /// function -- unlike [_configuredBaseUrl] itself -- so it's directly
  /// testable with ordinary runtime strings.
  @visibleForTesting
  static String normalizeBaseUrl(String raw) {
    var result = raw.trim();
    while (result.endsWith('/')) {
      result = result.substring(0, result.length - 1);
    }
    return result;
  }

  static const Duration connectTimeout = Duration(seconds: 15);
  static const Duration receiveTimeout = Duration(seconds: 15);
}
