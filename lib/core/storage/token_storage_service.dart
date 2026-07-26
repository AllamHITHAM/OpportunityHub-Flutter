import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Saves, reads, and deletes the user's auth token securely on the device.
class TokenStorageService {
  TokenStorageService({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  static const String _tokenKey = 'auth_token';

  /// Saves the given [token] to secure storage.
  Future<void> saveToken(String token) {
    return _storage.write(key: _tokenKey, value: token);
  }

  /// Reads the saved token, or returns null if there isn't one.
  Future<String?> readToken() {
    return _storage.read(key: _tokenKey);
  }

  /// Deletes the saved token, for example on logout.
  Future<void> deleteToken() {
    return _storage.delete(key: _tokenKey);
  }
}
