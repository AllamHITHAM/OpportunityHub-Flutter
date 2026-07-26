import 'package:flutter/material.dart';

/// Centralized color tokens for the OpportunityHub design system.
///
/// Every color used in the app should come from here — widgets should never
/// hardcode a raw [Color] value directly.
///
/// This palette is built around a soft sage-green identity for a
/// professional recruitment platform: warm neutral backgrounds, clean white
/// surfaces, and dark readable text, rather than the earlier blue/teal set.
class AppColors {
  AppColors._();

  // Primary (sage green) --------------------------------------------------
  static const Color primary = Color(0xFF4F7A5C);
  static const Color primaryDark = Color(0xFF3A5C44);
  static const Color primaryLight = Color(0xFF8FB89B);
  static const Color primaryContainer = Color(0xFFE1EDE3);
  static const Color onPrimary = Color(0xFFFFFFFF);

  // Secondary (warm amber accent) ------------------------------------------
  static const Color secondary = Color(0xFFC98A4B);
  static const Color secondaryLight = Color(0xFFEBCBA0);

  // Surfaces & backgrounds --------------------------------------------------
  static const Color background = Color(0xFFF7F5F0);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color surfaceVariant = Color(0xFFEFEDE6);
  static const Color card = Color(0xFFFFFFFF);
  static const Color inputFill = Color(0xFFF3F1EC);

  // Text ---------------------------------------------------------------------
  static const Color textPrimary = Color(0xFF1F2421);
  static const Color textSecondary = Color(0xFF5B645D);
  static const Color textMuted = Color(0xFF8B948C);
  static const Color textOnPrimary = Color(0xFFFFFFFF);

  // Borders & dividers ---------------------------------------------------------
  static const Color border = Color(0xFFDDD9D0);
  static const Color divider = Color(0xFFE7E4DC);
  static const Color disabled = Color(0xFFE3E1DA);
  static const Color disabledText = Color(0xFFA9A9A2);

  // Status colors -----------------------------------------------------------
  static const Color success = Color(0xFF2E9E5B);
  static const Color successBackground = Color(0xFFE6F4EA);
  static const Color warning = Color(0xFFD79A2C);
  static const Color warningBackground = Color(0xFFFBF0DD);
  static const Color error = Color(0xFFC0392B);
  static const Color errorBackground = Color(0xFFFAEAE8);
  static const Color info = Color(0xFF3B78B0);
  static const Color infoBackground = Color(0xFFE8F1F8);

  // Utility -------------------------------------------------------------------
  static const Color transparent = Color(0x00000000);

  /// Base neutral used to build the soft shadows in [AppShadows]. Kept
  /// fully opaque here; individual shadow strengths apply their own alpha.
  static const Color shadow = Color(0xFF1F2421);
}
