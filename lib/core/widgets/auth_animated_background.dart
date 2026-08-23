import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../theme/app_colors.dart';

/// A very subtle, slowly-drifting soft glow behind Auth/Onboarding screens
/// (UI Phase 1.5) — fills the large empty background areas on those
/// screens without ever competing with form readability.
///
/// Two blurred, low-opacity circles drift gently into place, once, as the
/// screen first appears — a slow one-shot settle, not a perpetual loop.
/// Built once and reused across every Auth/Onboarding screen rather than
/// duplicated per screen.
///
/// Deliberately one-shot rather than repeating: a `repeat()`-driven
/// controller never finishes, which would leave every screen using this
/// background permanently "still animating" as far as `pumpAndSettle` is
/// concerned, hanging every widget test that renders it (this app's whole
/// test suite leans on `pumpAndSettle`, so that's not a corner it's safe
/// to cut). A single slow drift keeps the ambient feel on arrival, avoids
/// an indefinite repaint loop while the user sits on the screen, and
/// settles cleanly.
///
/// Deliberately conservative in other ways too:
/// - stays entirely within the blue brand family (never the app's reserved
///   AI-accent purple, which [AppColors.aiAccent] documents as exclusive
///   to AI-attributed content elsewhere in the app).
/// - wrapped in [IgnorePointer] so it never intercepts taps.
/// - wrapped in [RepaintBoundary] so its repaints never dirty the form
///   content painted on top of it.
/// - starts at its settled end position directly — no motion at all —
///   under reduced-motion, matching the convention already established by
///   [AppAnimatedStatusIcon] and `LoginScreen`'s entrance controller.
///
/// Usage: place as the first child of a [Stack], behind the screen's real
/// content, e.g.:
/// ```dart
/// Stack(
///   children: [
///     const Positioned.fill(child: AuthAnimatedBackground()),
///     /* real content */
///   ],
/// )
/// ```
class AuthAnimatedBackground extends StatefulWidget {
  const AuthAnimatedBackground({super.key});

  @override
  State<AuthAnimatedBackground> createState() =>
      _AuthAnimatedBackgroundState();
}

class _AuthAnimatedBackgroundState extends State<AuthAnimatedBackground>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  bool _reducedMotion = false;

  /// Deliberately much longer than any token in `AppMotion` (those cover
  /// discrete UI transitions, not this one ambient settle) — slow enough
  /// that the drift is felt rather than seen moving.
  static const Duration _driftDuration = Duration(seconds: 7);

  @override
  void initState() {
    super.initState();
    _reducedMotion = SchedulerBinding
        .instance
        .platformDispatcher
        .accessibilityFeatures
        .disableAnimations;

    _controller = AnimationController(
      vsync: this,
      duration: _reducedMotion ? const Duration(milliseconds: 1) : _driftDuration,
    )..forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Kept intentionally faint -- this is ambience, not decoration that
    // asks to be noticed. Same low alpha in both themes; the underlying
    // color already resolves per-theme via AppColors.
    const glowAlpha = 0.10;

    return IgnorePointer(
      child: RepaintBoundary(
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            final t = _reducedMotion
                ? 1.0
                : Curves.easeInOut.transform(_controller.value);

            return Stack(
              clipBehavior: Clip.none,
              children: [
                _Blob(
                  alignment: Alignment.lerp(
                    const Alignment(-1.3, -1.1),
                    const Alignment(-0.9, -0.75),
                    t,
                  )!,
                  diameter: 420,
                  color: AppColors.primary.withValues(alpha: glowAlpha),
                ),
                _Blob(
                  alignment: Alignment.lerp(
                    const Alignment(1.2, 1.05),
                    const Alignment(0.85, 0.7),
                    t,
                  )!,
                  diameter: 360,
                  color: AppColors.primaryDark.withValues(alpha: glowAlpha),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _Blob extends StatelessWidget {
  const _Blob({
    required this.alignment,
    required this.diameter,
    required this.color,
  });

  final Alignment alignment;
  final double diameter;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: alignment,
      child: ImageFiltered(
        imageFilter: ImageFilter.blur(sigmaX: 80, sigmaY: 80),
        child: Container(
          width: diameter,
          height: diameter,
          decoration: BoxDecoration(shape: BoxShape.circle, color: color),
        ),
      ),
    );
  }
}
