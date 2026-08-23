import 'package:flutter/material.dart';

/// Centralized color tokens for the OpportunityHub design system.
///
/// Every color used in the app should come from here — widgets should never
/// hardcode a raw [Color] value directly.
///
/// UI Phase 1: "Modern Professional Recruitment Platform" — a deep
/// professional blue identity (cool neutral backgrounds, clean white
/// surfaces, dark slate text) with a single reserved purple accent for
/// AI-attributed content ([aiAccent]) that appears nowhere else in the app.
///
/// UI Phase 1.3: every field below is a `static Color get` that resolves to
/// either [AppColorsLight] or [AppColorsDark] depending on [isDark] — never
/// a naive inversion, each dark value was chosen for its own contrast and
/// legibility on a dark surface. [AppTheme]'s `ThemeData` construction
/// references [AppColorsLight]/[AppColorsDark] directly (real `const`
/// values, since a `ThemeData` needs one fixed palette per mode) — this
/// class exists for the ad-hoc `AppColors.x` references used throughout
/// existing widgets/screens, which is why it deliberately keeps the exact
/// same public API (`AppColors.primary`, `AppColors.textSecondary`, ...)
/// rather than requiring every call site to be rewritten to pass a
/// `BuildContext`. [updateBrightness] is called once by `ThemeProvider`
/// whenever the resolved app theme changes; because nearly every widget in
/// this app already calls `Theme.of(context)` for its `TextTheme` (which
/// *does* register a real `InheritedWidget` dependency), those widgets
/// naturally rebuild the moment `MaterialApp`'s `themeMode` changes — and
/// since these are plain getters (not `const`), that rebuild re-evaluates
/// them and picks up the new palette automatically.
class AppColors {
  AppColors._();

  static Brightness _brightness = Brightness.light;

  /// True once [updateBrightness] has been called with [Brightness.dark].
  static bool get isDark => _brightness == Brightness.dark;

  /// Called by `ThemeProvider` whenever the app's resolved theme changes
  /// (including on startup, before the first frame, and in response to a
  /// system-brightness change while following System mode).
  static void updateBrightness(Brightness brightness) {
    _brightness = brightness;
  }

  // Primary (deep professional blue) ----------------------------------------
  static Color get primary => isDark ? AppColorsDark.primary : AppColorsLight.primary;
  static Color get primaryDark => isDark ? AppColorsDark.primaryDark : AppColorsLight.primaryDark;
  static Color get primaryLight => isDark ? AppColorsDark.primaryLight : AppColorsLight.primaryLight;
  static Color get primaryContainer =>
      isDark ? AppColorsDark.primaryContainer : AppColorsLight.primaryContainer;
  static Color get onPrimary => isDark ? AppColorsDark.onPrimary : AppColorsLight.onPrimary;

  // Secondary (neutral slate) ------------------------------------------------
  static Color get secondary => isDark ? AppColorsDark.secondary : AppColorsLight.secondary;
  static Color get secondaryLight =>
      isDark ? AppColorsDark.secondaryLight : AppColorsLight.secondaryLight;

  // AI accent (purple) — reserved exclusively for AI-attributed content.
  static Color get aiAccent => isDark ? AppColorsDark.aiAccent : AppColorsLight.aiAccent;
  static Color get aiAccentBackground =>
      isDark ? AppColorsDark.aiAccentBackground : AppColorsLight.aiAccentBackground;
  static Color get aiAccentDark => isDark ? AppColorsDark.aiAccentDark : AppColorsLight.aiAccentDark;

  // Surfaces & backgrounds --------------------------------------------------
  static Color get background => isDark ? AppColorsDark.background : AppColorsLight.background;
  static Color get surface => isDark ? AppColorsDark.surface : AppColorsLight.surface;
  static Color get surfaceVariant =>
      isDark ? AppColorsDark.surfaceVariant : AppColorsLight.surfaceVariant;
  static Color get card => isDark ? AppColorsDark.card : AppColorsLight.card;
  static Color get inputFill => isDark ? AppColorsDark.inputFill : AppColorsLight.inputFill;

  // Text ---------------------------------------------------------------------
  static Color get textPrimary => isDark ? AppColorsDark.textPrimary : AppColorsLight.textPrimary;
  static Color get textSecondary =>
      isDark ? AppColorsDark.textSecondary : AppColorsLight.textSecondary;
  static Color get textMuted => isDark ? AppColorsDark.textMuted : AppColorsLight.textMuted;
  static Color get textOnPrimary =>
      isDark ? AppColorsDark.textOnPrimary : AppColorsLight.textOnPrimary;

  // Borders & dividers ---------------------------------------------------------
  static Color get border => isDark ? AppColorsDark.border : AppColorsLight.border;
  static Color get divider => isDark ? AppColorsDark.divider : AppColorsLight.divider;
  static Color get disabled => isDark ? AppColorsDark.disabled : AppColorsLight.disabled;
  static Color get disabledText =>
      isDark ? AppColorsDark.disabledText : AppColorsLight.disabledText;

  // Status colors -----------------------------------------------------------
  static Color get success => isDark ? AppColorsDark.success : AppColorsLight.success;
  static Color get successBackground =>
      isDark ? AppColorsDark.successBackground : AppColorsLight.successBackground;
  static Color get warning => isDark ? AppColorsDark.warning : AppColorsLight.warning;
  static Color get warningBackground =>
      isDark ? AppColorsDark.warningBackground : AppColorsLight.warningBackground;
  static Color get error => isDark ? AppColorsDark.error : AppColorsLight.error;
  static Color get errorBackground =>
      isDark ? AppColorsDark.errorBackground : AppColorsLight.errorBackground;
  static Color get info => isDark ? AppColorsDark.info : AppColorsLight.info;
  static Color get infoBackground =>
      isDark ? AppColorsDark.infoBackground : AppColorsLight.infoBackground;

  // Utility -------------------------------------------------------------------
  static const Color transparent = Color(0x00000000);

  /// Base neutral used to build the soft shadows in [AppShadows]. Kept
  /// identical across both themes on purpose — the shadows this builds are
  /// already very low-opacity, and unlike every other token here this one
  /// backs a `static final` (evaluated once, not re-read per build), so it
  /// deliberately doesn't need to vary by theme to look correct in either.
  static const Color shadow = Color(0xFF000000);
}

/// The light palette — identical values to UI Phase 1's original
/// `AppColors`. Referenced directly (not through [AppColors]'s getters) by
/// `AppTheme.lightTheme`, which needs real `const`-friendly fixed values.
class AppColorsLight {
  AppColorsLight._();

  static const Color primary = Color(0xFF1A56DB);
  static const Color primaryDark = Color(0xFF1E3A8A);
  static const Color primaryLight = Color(0xFF93C5FD);
  static const Color primaryContainer = Color(0xFFDBEAFE);
  static const Color onPrimary = Color(0xFFFFFFFF);

  static const Color secondary = Color(0xFF64748B);
  static const Color secondaryLight = Color(0xFFCBD5E1);

  static const Color aiAccent = Color(0xFF7C3AED);
  static const Color aiAccentBackground = Color(0xFFF5F3FF);
  static const Color aiAccentDark = Color(0xFF5B21B6);

  static const Color background = Color(0xFFF8FAFC);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color surfaceVariant = Color(0xFFF1F5F9);
  static const Color card = Color(0xFFFFFFFF);
  static const Color inputFill = Color(0xFFF8FAFC);

  static const Color textPrimary = Color(0xFF0F172A);
  static const Color textSecondary = Color(0xFF64748B);
  static const Color textMuted = Color(0xFF94A3B8);
  static const Color textOnPrimary = Color(0xFFFFFFFF);

  static const Color border = Color(0xFFE5E7EB);
  static const Color divider = Color(0xFFE5E7EB);
  static const Color disabled = Color(0xFFE2E8F0);
  static const Color disabledText = Color(0xFF94A3B8);

  static const Color success = Color(0xFF22C55E);
  static const Color successBackground = Color(0xFFEAFBEF);
  static const Color warning = Color(0xFFF59E0B);
  static const Color warningBackground = Color(0xFFFEF6E7);
  static const Color error = Color(0xFFEF4444);
  static const Color errorBackground = Color(0xFFFDEEEE);
  static const Color info = Color(0xFF0EA5E9);
  static const Color infoBackground = Color(0xFFE0F2FE);
}

/// The dark palette (UI Phase 1.3) — deep navy/slate backgrounds (never
/// pure black), high-contrast near-white text, and every accent/status
/// color individually re-tuned for legibility on a dark surface rather
/// than a naive inversion of the light values. Referenced directly (not
/// through [AppColors]'s getters) by `AppTheme.darkTheme`.
class AppColorsDark {
  AppColorsDark._();

  // Lightened from the light theme's #1A56DB so it still pops against a
  // dark navy background — the same blue family, just brighter.
  static const Color primary = Color(0xFF3B82F6);
  static const Color primaryDark = Color(0xFF1E3A8A);
  static const Color primaryLight = Color(0xFF93C5FD);
  // A muted dark navy-blue container (not the light theme's pale #DBEAFE)
  // so text sitting on it stays readable.
  static const Color primaryContainer = Color(0xFF1E3A5F);
  static const Color onPrimary = Color(0xFFFFFFFF);

  static const Color secondary = Color(0xFF94A3B8);
  static const Color secondaryLight = Color(0xFF334155);

  // Lightened purple, same reasoning as primary.
  static const Color aiAccent = Color(0xFFA78BFA);
  static const Color aiAccentBackground = Color(0xFF2E1F4D);
  // In light mode this is a *darker* purple used as text on a *light*
  // container; in dark mode the roles invert, so this needs to be *light*
  // purple text on a *dark* container — never a blind color inversion.
  static const Color aiAccentDark = Color(0xFFC4B5FD);

  static const Color background = Color(0xFF0B1220);
  static const Color surface = Color(0xFF131C2E);
  static const Color surfaceVariant = Color(0xFF1C2740);
  static const Color card = Color(0xFF131C2E);
  static const Color inputFill = Color(0xFF1C2740);

  static const Color textPrimary = Color(0xFFF1F5F9);
  static const Color textSecondary = Color(0xFF94A3B8);
  static const Color textMuted = Color(0xFF64748B);
  static const Color textOnPrimary = Color(0xFFFFFFFF);

  static const Color border = Color(0xFF263349);
  static const Color divider = Color(0xFF263349);
  static const Color disabled = Color(0xFF1C2740);
  static const Color disabledText = Color(0xFF64748B);

  static const Color success = Color(0xFF4ADE80);
  static const Color successBackground = Color(0xFF14291D);
  static const Color warning = Color(0xFFFBBF24);
  static const Color warningBackground = Color(0xFF2E2410);
  static const Color error = Color(0xFFF87171);
  static const Color errorBackground = Color(0xFF2E1616);
  static const Color info = Color(0xFF38BDF8);
  static const Color infoBackground = Color(0xFF132A38);
}
