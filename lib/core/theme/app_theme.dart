import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'app_radius.dart';
import 'app_spacing.dart';

/// Builds the Material 3 [ThemeData] used across the whole app — both
/// [lightTheme] and [darkTheme] (UI Phase 1.3).
///
/// Every visual choice here should come from [AppColorsLight]/
/// [AppColorsDark] (via [_Palette]) rather than raw values, so the look
/// stays centralized. Deliberately built from real, fixed `const`-friendly
/// palette values (not [AppColors]'s dynamic getters) — a `ThemeData`
/// needs one definite set of colors per mode, not a runtime-branching one.
class AppTheme {
  AppTheme._();

  static ThemeData get lightTheme => _build(Brightness.light, _lightPalette);
  static ThemeData get darkTheme => _build(Brightness.dark, _darkPalette);

  static ThemeData _build(Brightness brightness, _Palette c) {
    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      scaffoldBackgroundColor: c.background,
      colorScheme: ColorScheme(
        brightness: brightness,
        primary: c.primary,
        onPrimary: c.onPrimary,
        primaryContainer: c.primaryContainer,
        onPrimaryContainer: c.textPrimary,
        secondary: c.secondary,
        onSecondary: c.onPrimary,
        secondaryContainer: c.secondaryLight,
        onSecondaryContainer: c.textPrimary,
        surface: c.surface,
        onSurface: c.textPrimary,
        surfaceContainerHighest: c.surfaceVariant,
        error: c.error,
        onError: c.onPrimary,
        errorContainer: c.errorBackground,
        onErrorContainer: c.error,
        outline: c.border,
        outlineVariant: c.divider,
      ),
      textTheme: _textTheme(c),
      appBarTheme: AppBarThemeData(
        backgroundColor: c.surface,
        foregroundColor: c.textPrimary,
        surfaceTintColor: AppColors.transparent,
        elevation: 0,
        scrolledUnderElevation: 1,
        centerTitle: true,
        titleTextStyle: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: c.textPrimary,
        ),
        iconTheme: IconThemeData(color: c.textPrimary),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: c.primary,
          foregroundColor: c.onPrimary,
          disabledBackgroundColor: c.disabled,
          disabledForegroundColor: c.disabledText,
          minimumSize: const Size(64, 48),
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          elevation: 0,
          shape: const RoundedRectangleBorder(
            borderRadius: AppRadius.mediumRadius,
          ),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: c.primary,
          disabledForegroundColor: c.disabledText,
          side: BorderSide(color: c.primary),
          minimumSize: const Size(64, 48),
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          shape: const RoundedRectangleBorder(
            borderRadius: AppRadius.mediumRadius,
          ),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: c.primary,
          disabledForegroundColor: c.disabledText,
          minimumSize: const Size(48, 44),
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
          shape: const RoundedRectangleBorder(borderRadius: AppRadius.smallRadius),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: c.inputFill,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm + 2,
        ),
        hintStyle: TextStyle(fontSize: 14, color: c.textMuted),
        labelStyle: TextStyle(fontSize: 14, color: c.textSecondary),
        helperStyle: TextStyle(fontSize: 12, color: c.textMuted),
        errorStyle: TextStyle(fontSize: 12, color: c.error),
        border: OutlineInputBorder(
          borderRadius: AppRadius.mediumRadius,
          borderSide: BorderSide(color: c.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: AppRadius.mediumRadius,
          borderSide: BorderSide(color: c.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: AppRadius.mediumRadius,
          borderSide: BorderSide(color: c.primary, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: AppRadius.mediumRadius,
          borderSide: BorderSide(color: c.error),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: AppRadius.mediumRadius,
          borderSide: BorderSide(color: c.error, width: 1.5),
        ),
        disabledBorder: OutlineInputBorder(
          borderRadius: AppRadius.mediumRadius,
          borderSide: BorderSide(color: c.disabled),
        ),
      ),
      cardTheme: CardThemeData(
        color: c.card,
        surfaceTintColor: AppColors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.largeRadius,
          side: BorderSide(color: c.border),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: c.divider,
        thickness: 1,
        space: 1,
      ),
      chipTheme: ChipThemeData(
        backgroundColor: c.surfaceVariant,
        selectedColor: c.primaryContainer,
        disabledColor: c.disabled,
        labelStyle: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w500,
          color: c.textPrimary,
        ),
        secondaryLabelStyle: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w500,
          color: c.primary,
        ),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.xxs,
        ),
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.pillRadius),
        side: BorderSide(color: c.border),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: c.surface,
        surfaceTintColor: AppColors.transparent,
        elevation: 4,
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.largeRadius),
        titleTextStyle: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: c.textPrimary,
        ),
        contentTextStyle: TextStyle(fontSize: 14, color: c.textSecondary),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: c.surface,
        indicatorColor: c.primaryContainer,
        elevation: 1,
        height: 64,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return IconThemeData(
            color: selected ? c.primary : c.textSecondary,
            size: 24,
          );
        }),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return TextStyle(
            fontSize: 12,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
            color: selected ? c.primary : c.textSecondary,
          );
        }),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: c.textPrimary,
        contentTextStyle: TextStyle(fontSize: 14, color: c.surface),
        behavior: SnackBarBehavior.floating,
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.mediumRadius),
        insetPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: c.primary,
        linearTrackColor: c.primaryContainer,
        circularTrackColor: c.primaryContainer,
      ),
      iconTheme: IconThemeData(color: c.textSecondary, size: 24),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.disabled)) return c.disabled;
          if (states.contains(WidgetState.selected)) return c.primary;
          return c.surface;
        }),
        checkColor: WidgetStatePropertyAll(c.onPrimary),
        side: BorderSide(color: c.border, width: 1.5),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.disabled)) return c.disabledText;
          if (states.contains(WidgetState.selected)) return c.primary;
          return c.surface;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.disabled)) return c.disabled;
          if (states.contains(WidgetState.selected)) return c.primaryContainer;
          return c.surfaceVariant;
        }),
        trackOutlineColor: WidgetStatePropertyAll(c.border),
      ),
    );
  }

  // Typography ----------------------------------------------------------
  //
  // A conservative, mobile-first type scale. No custom font family is set,
  // so the app uses Flutter's default platform-safe typeface — deliberately
  // avoiding a new font dependency.
  static TextTheme _textTheme(_Palette c) {
    return TextTheme(
      displayLarge: TextStyle(
        fontSize: 32,
        fontWeight: FontWeight.w700,
        color: c.textPrimary,
      ),
      displayMedium: TextStyle(
        fontSize: 28,
        fontWeight: FontWeight.w700,
        color: c.textPrimary,
      ),
      displaySmall: TextStyle(
        fontSize: 24,
        fontWeight: FontWeight.w700,
        color: c.textPrimary,
      ),
      // Section headings.
      headlineLarge: TextStyle(
        fontSize: 22,
        fontWeight: FontWeight.w700,
        color: c.textPrimary,
      ),
      headlineMedium: TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.w600,
        color: c.textPrimary,
      ),
      headlineSmall: TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w600,
        color: c.textPrimary,
      ),
      // Page titles / app bar titles.
      titleLarge: TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w600,
        color: c.textPrimary,
      ),
      // Card titles.
      titleMedium: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: c.textPrimary,
      ),
      titleSmall: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: c.textSecondary,
      ),
      // Body text.
      bodyLarge: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w400,
        color: c.textPrimary,
      ),
      bodyMedium: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w400,
        color: c.textPrimary,
      ),
      // Captions.
      bodySmall: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w400,
        color: c.textSecondary,
      ),
      // Labels (buttons, chips, form field labels).
      labelLarge: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: c.textPrimary,
      ),
      labelMedium: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w500,
        color: c.textSecondary,
      ),
      labelSmall: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w500,
        color: c.textMuted,
      ),
    );
  }
}

/// The fixed set of tokens [AppTheme] needs to build one mode's
/// `ThemeData` — deliberately a small subset of [AppColorsLight]/
/// [AppColorsDark] (only what `ThemeData`'s own sub-themes actually
/// reference); everything else (status colors, the AI accent, ...) is
/// consumed directly via [AppColors]'s dynamic getters elsewhere.
class _Palette {
  const _Palette({
    required this.primary,
    required this.onPrimary,
    required this.primaryContainer,
    required this.secondary,
    required this.secondaryLight,
    required this.surface,
    required this.surfaceVariant,
    required this.card,
    required this.background,
    required this.error,
    required this.errorBackground,
    required this.border,
    required this.divider,
    required this.disabled,
    required this.disabledText,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
    required this.inputFill,
  });

  final Color primary;
  final Color onPrimary;
  final Color primaryContainer;
  final Color secondary;
  final Color secondaryLight;
  final Color surface;
  final Color surfaceVariant;
  final Color card;
  final Color background;
  final Color error;
  final Color errorBackground;
  final Color border;
  final Color divider;
  final Color disabled;
  final Color disabledText;
  final Color textPrimary;
  final Color textSecondary;
  final Color textMuted;
  final Color inputFill;
}

const _lightPalette = _Palette(
  primary: AppColorsLight.primary,
  onPrimary: AppColorsLight.onPrimary,
  primaryContainer: AppColorsLight.primaryContainer,
  secondary: AppColorsLight.secondary,
  secondaryLight: AppColorsLight.secondaryLight,
  surface: AppColorsLight.surface,
  surfaceVariant: AppColorsLight.surfaceVariant,
  card: AppColorsLight.card,
  background: AppColorsLight.background,
  error: AppColorsLight.error,
  errorBackground: AppColorsLight.errorBackground,
  border: AppColorsLight.border,
  divider: AppColorsLight.divider,
  disabled: AppColorsLight.disabled,
  disabledText: AppColorsLight.disabledText,
  textPrimary: AppColorsLight.textPrimary,
  textSecondary: AppColorsLight.textSecondary,
  textMuted: AppColorsLight.textMuted,
  inputFill: AppColorsLight.inputFill,
);

const _darkPalette = _Palette(
  primary: AppColorsDark.primary,
  onPrimary: AppColorsDark.onPrimary,
  primaryContainer: AppColorsDark.primaryContainer,
  secondary: AppColorsDark.secondary,
  secondaryLight: AppColorsDark.secondaryLight,
  surface: AppColorsDark.surface,
  surfaceVariant: AppColorsDark.surfaceVariant,
  card: AppColorsDark.card,
  background: AppColorsDark.background,
  error: AppColorsDark.error,
  errorBackground: AppColorsDark.errorBackground,
  border: AppColorsDark.border,
  divider: AppColorsDark.divider,
  disabled: AppColorsDark.disabled,
  disabledText: AppColorsDark.disabledText,
  textPrimary: AppColorsDark.textPrimary,
  textSecondary: AppColorsDark.textSecondary,
  textMuted: AppColorsDark.textMuted,
  inputFill: AppColorsDark.inputFill,
);
