import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import 'theme_toggle_button.dart';

/// A more visible container around the shared [ThemeToggleButton] — first
/// introduced in UI Phase O3.1 (Create/Edit Opportunity) for "the theme
/// toggle is too small/low-emphasis", then extracted here in UI Phase O4
/// once Opportunity Details needed the exact same treatment, so both
/// screens share one real widget instead of two copies that could drift.
///
/// Deliberately opt-in rather than a change to [ThemeToggleButton] itself:
/// that widget is still used bare (no extra container) on every screen that
/// hasn't been through this polish pass yet (Dashboard, Notifications,
/// Admin, Student Home, ...) — using it changes nothing about the
/// underlying mechanism (tap target, tooltip text, icon, persisted
/// [ThemeProvider] state), only the visual frame around it on whichever
/// screen opts in.
///
/// A rounded, bordered surface (the same `AppColors.surfaceVariant`/
/// `AppColors.border` pairing already used elsewhere in this app for a
/// "chip"-like control) makes it read as a real, comfortably clickable
/// button instead of a bare icon floating in the AppBar.
class ThemeToggleSurface extends StatelessWidget {
  const ThemeToggleSurface({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: AppSpacing.xs),
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: AppColors.surfaceVariant,
          border: Border.all(color: AppColors.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: const ThemeToggleButton(),
      ),
    );
  }
}
