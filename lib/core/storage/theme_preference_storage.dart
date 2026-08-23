import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Saves and reads the student's chosen [ThemeMode] preference.
///
/// UI Phase 1.3: reuses [FlutterSecureStorage] — already a dependency (see
/// [TokenStorageService], which this mirrors) — rather than adding a new
/// package (e.g. `shared_preferences`) just for one small preference.
/// Nothing stored here is sensitive; secure storage is used purely because
/// it's the persistence mechanism already present in this project.
class ThemePreferenceStorage {
  ThemePreferenceStorage({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  static const String _themeModeKey = 'theme_mode';
  static const String _light = 'light';
  static const String _dark = 'dark';

  /// Saves [mode]. Only [ThemeMode.light]/[ThemeMode.dark] are persisted
  /// as an explicit override — [ThemeMode.system] is represented by the
  /// *absence* of a saved value, so a fresh install (or a cleared
  /// preference) always starts by following the system theme.
  Future<void> saveThemeMode(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.light:
        return _storage.write(key: _themeModeKey, value: _light);
      case ThemeMode.dark:
        return _storage.write(key: _themeModeKey, value: _dark);
      case ThemeMode.system:
        return _storage.delete(key: _themeModeKey);
    }
  }

  /// Reads the saved preference, or [ThemeMode.system] if none was ever
  /// explicitly chosen (or the stored value is unrecognized).
  Future<ThemeMode> readThemeMode() async {
    final value = await _storage.read(key: _themeModeKey);
    switch (value) {
      case _light:
        return ThemeMode.light;
      case _dark:
        return ThemeMode.dark;
      default:
        return ThemeMode.system;
    }
  }
}
