import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/theme_provider.dart';
import '../theme/app_colors.dart';
import '../theme/app_motion.dart';

/// A polished Sun/Moon theme toggle (UI Phase 1.3) — reads/drives the
/// shared [ThemeProvider], so it can be dropped into any app bar/menu and
/// stays in sync with the app's actual resolved theme. Animates between
/// the two icons with a restrained fade+rotate, respecting reduced-motion.
class ThemeToggleButton extends StatelessWidget {
  const ThemeToggleButton({super.key});

  @override
  Widget build(BuildContext context) {
    final themeProvider = context.watch<ThemeProvider>();
    final isDark = themeProvider.isDark;

    return IconButton(
      tooltip: isDark ? 'Switch to light mode' : 'Switch to dark mode',
      onPressed: themeProvider.toggle,
      icon: AnimatedSwitcher(
        duration: AppMotion.reduced(context, AppMotion.fast),
        transitionBuilder: (child, animation) => RotationTransition(
          turns: Tween<double>(begin: 0.75, end: 1).animate(animation),
          child: FadeTransition(opacity: animation, child: child),
        ),
        child: Icon(
          isDark ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
          key: ValueKey(isDark),
          color: AppColors.textSecondary,
        ),
      ),
    );
  }
}
