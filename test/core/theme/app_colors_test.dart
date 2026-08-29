// Direct unit tests for the AppColorsLight/AppColorsDark surface hierarchy
// — a regression guard for UI Phase O3.1's fix (AppColorsLight.inputFill
// was identical to AppColorsLight.background, the one real bug behind
// every "inputs don't stand out" / "the Light theme looks washed out"
// report).

import 'package:flutter_test/flutter_test.dart';

import 'package:opportunityhub_flutter/core/theme/app_colors.dart';

void main() {
  group('AppColorsLight — three distinct surface tiers', () {
    test('background, card, and inputFill are three genuinely different colors', () {
      expect(AppColorsLight.background, isNot(AppColorsLight.card));
      expect(AppColorsLight.background, isNot(AppColorsLight.inputFill));
      expect(AppColorsLight.card, isNot(AppColorsLight.inputFill));
    });

    test('inputFill reuses the existing surfaceVariant tone', () {
      // The fix deliberately reuses an already-designed token rather than
      // inventing a new color — see AppColorsLight.inputFill's own doc
      // comment.
      expect(AppColorsLight.inputFill, AppColorsLight.surfaceVariant);
    });
  });

  group('AppColorsDark — three distinct surface tiers (already correct)', () {
    test('background, card, and inputFill are three genuinely different colors', () {
      expect(AppColorsDark.background, isNot(AppColorsDark.card));
      expect(AppColorsDark.background, isNot(AppColorsDark.inputFill));
      expect(AppColorsDark.card, isNot(AppColorsDark.inputFill));
    });
  });
}
