import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../core/storage/theme_preference_storage.dart';
import '../core/theme/app_colors.dart';

/// Holds the app's light/dark theme preference (UI Phase 1.3).
///
/// [mode] is what [MaterialApp.router] should use for its `themeMode`.
/// Defaults to [ThemeMode.system] — "respect system theme" — until the
/// student explicitly toggles it, at which point that explicit choice is
/// persisted (via [ThemePreferenceStorage], which reuses the
/// `flutter_secure_storage` dependency already in this project rather than
/// adding a new one) and followed from then on, surviving a restart.
///
/// Also keeps [AppColors] in sync with the *resolved* [Brightness] (never
/// just the [ThemeMode] — [ThemeMode.system] must resolve against the
/// platform's actual current brightness) so every `AppColors.x` getter
/// throughout the app reflects the current theme. Implements
/// [WidgetsBindingObserver] so that, while following System mode, an
/// in-session OS theme change (e.g. sunset-triggered dark mode) is picked
/// up immediately rather than only on the next app restart.
class ThemeProvider extends ChangeNotifier with WidgetsBindingObserver {
  ThemeProvider({ThemePreferenceStorage? storage})
    : _storage = storage ?? ThemePreferenceStorage();

  final ThemePreferenceStorage _storage;

  ThemeMode _mode = ThemeMode.system;
  ThemeMode get mode => _mode;

  bool _isInitialized = false;
  bool get isInitialized => _isInitialized;

  Brightness get resolvedBrightness {
    if (_mode == ThemeMode.light) return Brightness.light;
    if (_mode == ThemeMode.dark) return Brightness.dark;
    return SchedulerBinding.instance.platformDispatcher.platformBrightness;
  }

  bool get isDark => resolvedBrightness == Brightness.dark;

  /// Loads the persisted preference. Call once, before the first frame
  /// (see `main.dart`) so there is never a visible flash from one theme to
  /// another.
  Future<void> initialize() async {
    _mode = await _storage.readThemeMode();
    _isInitialized = true;
    AppColors.updateBrightness(resolvedBrightness);
    WidgetsBinding.instance.addObserver(this);
    notifyListeners();
  }

  /// Flips between light and dark — the toggle's only two states, per its
  /// own spec (Light → Dark, Dark → Light). Always lands on an explicit
  /// choice (never back to System) and persists it.
  Future<void> toggle() async {
    final next = isDark ? ThemeMode.light : ThemeMode.dark;
    _mode = next;
    AppColors.updateBrightness(resolvedBrightness);
    notifyListeners();
    await _storage.saveThemeMode(next);
  }

  @override
  void didChangePlatformBrightness() {
    if (_mode != ThemeMode.system) return;
    AppColors.updateBrightness(resolvedBrightness);
    notifyListeners();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}
