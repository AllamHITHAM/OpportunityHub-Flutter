// Unit tests for ThemeProvider (UI Phase 1.3) — default System mode,
// toggle behavior (Light -> Dark, Dark -> Light), persistence (via an
// in-memory fake standing in for the real, `flutter_secure_storage`-backed
// ThemePreferenceStorage, which needs a real platform channel this test
// environment doesn't provide), and that it keeps AppColors.isDark in sync.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:opportunityhub_flutter/core/storage/theme_preference_storage.dart';
import 'package:opportunityhub_flutter/core/theme/app_colors.dart';
import 'package:opportunityhub_flutter/providers/theme_provider.dart';

class _FakeThemePreferenceStorage extends ThemePreferenceStorage {
  ThemeMode? saved;

  @override
  Future<void> saveThemeMode(ThemeMode mode) async {
    saved = mode;
  }

  @override
  Future<ThemeMode> readThemeMode() async => saved ?? ThemeMode.system;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    // AppColors.updateBrightness is a global -- reset it so one test's
    // theme choice never leaks into the next.
    AppColors.updateBrightness(Brightness.light);
  });

  test('defaults to System mode before any preference is saved', () async {
    final provider = ThemeProvider(storage: _FakeThemePreferenceStorage());
    await provider.initialize();

    expect(provider.mode, ThemeMode.system);
    expect(provider.isInitialized, isTrue);
  });

  test('toggle flips from the resolved System brightness to its opposite, and persists it', () async {
    final storage = _FakeThemePreferenceStorage();
    final provider = ThemeProvider(storage: storage);
    await provider.initialize();

    final wasDark = provider.isDark;
    await provider.toggle();

    expect(provider.isDark, !wasDark);
    expect(provider.mode, wasDark ? ThemeMode.light : ThemeMode.dark);
    expect(storage.saved, provider.mode);

    // A second provider reading the same storage picks up the persisted
    // choice -- proving it survives (e.g.) an app restart.
    final reloaded = ThemeProvider(storage: storage);
    await reloaded.initialize();
    expect(reloaded.mode, provider.mode);
  });

  test('toggle: Dark -> Light -> Dark always lands on an explicit choice, never System', () async {
    final provider = ThemeProvider(storage: _FakeThemePreferenceStorage());
    await provider.initialize();

    await provider.toggle();
    final first = provider.mode;
    expect(first, isNot(ThemeMode.system));

    await provider.toggle();
    final second = provider.mode;
    expect(second, isNot(ThemeMode.system));
    expect(second, isNot(first));
  });

  test('keeps AppColors.isDark in sync with the resolved theme', () async {
    final provider = ThemeProvider(storage: _FakeThemePreferenceStorage());
    await provider.initialize();

    await provider.toggle();
    expect(AppColors.isDark, provider.isDark);

    await provider.toggle();
    expect(AppColors.isDark, provider.isDark);
  });

  test('notifies listeners on toggle', () async {
    final provider = ThemeProvider(storage: _FakeThemePreferenceStorage());
    await provider.initialize();

    var notifyCount = 0;
    provider.addListener(() => notifyCount++);

    await provider.toggle();

    expect(notifyCount, greaterThanOrEqualTo(1));
  });
}
