// Tests for ApiConstants -- the single source of truth for the Laravel
// API base URL (Deployment Preparation: environment-driven API base URL).
//
// `normalizeBaseUrl` is a plain runtime function, tested directly with
// ordinary strings. `baseUrl`'s *configured* branch depends on
// `String.fromEnvironment('API_BASE_URL')`, a genuine compile-time
// constant -- a plain `flutter test` run (no `--dart-define`) can only
// ever exercise the *local-fallback* branch, which is exactly what these
// tests verify: local development continues to work unchanged.

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:opportunityhub_flutter/core/constants/api_constants.dart';

void main() {
  group('normalizeBaseUrl', () {
    test('leaves an already-clean URL untouched', () {
      expect(
        ApiConstants.normalizeBaseUrl('https://api.example.com/api'),
        'https://api.example.com/api',
      );
    });

    test('strips a single trailing slash', () {
      expect(
        ApiConstants.normalizeBaseUrl('https://api.example.com/api/'),
        'https://api.example.com/api',
      );
    });

    test('strips multiple trailing slashes', () {
      expect(
        ApiConstants.normalizeBaseUrl('https://api.example.com/api///'),
        'https://api.example.com/api',
      );
    });

    test('trims surrounding whitespace', () {
      expect(
        ApiConstants.normalizeBaseUrl('  https://api.example.com/api  '),
        'https://api.example.com/api',
      );
    });

    test(
      'never appends /api -- the configured value is trusted as the '
      'complete API root',
      () {
        expect(
          ApiConstants.normalizeBaseUrl('https://api.example.com'),
          'https://api.example.com',
        );
      },
    );
  });

  group('baseUrl -- local fallback (no --dart-define supplied)', () {
    tearDown(() {
      debugDefaultTargetPlatformOverride = null;
    });

    test('uses the Android emulator loopback mapping (10.0.2.2)', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      expect(ApiConstants.baseUrl, 'http://10.0.2.2:8000/api');
    });

    test('uses 127.0.0.1 on iOS', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      expect(ApiConstants.baseUrl, 'http://127.0.0.1:8000/api');
    });

    test('uses 127.0.0.1 on desktop platforms (Windows/macOS/Linux)', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      expect(ApiConstants.baseUrl, 'http://127.0.0.1:8000/api');
    });
  });
}
