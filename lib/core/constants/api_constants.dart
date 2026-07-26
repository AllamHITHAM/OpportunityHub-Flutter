import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;

/// Constants used to talk to the Laravel backend API.
class ApiConstants {
  ApiConstants._();

  /// The base URL of the Laravel API, for local development.
  ///
  /// This picks the right address automatically depending on where the
  /// app is running:
  /// - Flutter Web and desktop (Windows/macOS/Linux) talk to the host
  ///   machine directly, since the server runs on the same machine.
  /// - The Android emulator maps the host machine to 10.0.2.2 instead.
  static String get baseUrl {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      return 'http://10.0.2.2:8000/api';
    }
    return 'http://127.0.0.1:8000/api';
  }

  static const Duration connectTimeout = Duration(seconds: 15);
  static const Duration receiveTimeout = Duration(seconds: 15);
}
