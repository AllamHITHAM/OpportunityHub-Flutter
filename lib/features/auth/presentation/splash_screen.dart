import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_motion.dart';
import '../../../core/theme/app_spacing.dart';

/// The splash visuals stay on screen for at least this long, measured
/// from construction, so a true cold start where the saved-session check
/// resolves almost instantly doesn't read as a jarring flash. Real
/// initialization is never delayed by this -- only the visuals linger a
/// little longer, via [_holdMinimumVisibleDuration] below, when they'd
/// otherwise disappear too quickly.
const _minimumVisibleDuration = Duration(milliseconds: 600);

/// Shown briefly at startup while [AuthProvider] checks for a saved
/// session. The router moves away from here automatically once that
/// check finishes — this screen has no timing logic that affects real
/// initialization or navigation; the entrance animation below is purely
/// decorative and simply gets interrupted (harmlessly) if the real
/// redirect happens before it finishes. The only timing this screen
/// controls is its own minimum visible duration (see
/// [_holdMinimumVisibleDuration]).
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _logoOpacity;
  late final Animation<double> _logoScale;
  late final Animation<double> _wordmarkOpacity;
  final DateTime _visibleSince = DateTime.now();

  @override
  void initState() {
    super.initState();
    // Read directly from the platform dispatcher (not `MediaQuery`, which
    // isn't reliably available this early) so a reduced-motion user gets
    // a simple, near-instant fade instead of the scale entrance.
    final reducedMotion = SchedulerBinding
        .instance
        .platformDispatcher
        .accessibilityFeatures
        .disableAnimations;

    _controller = AnimationController(
      vsync: this,
      duration: reducedMotion ? const Duration(milliseconds: 1) : AppMotion.slow,
    );
    _logoOpacity = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.0, 0.6, curve: AppMotion.entrance),
    );
    _logoScale = Tween<double>(begin: reducedMotion ? 1.0 : 0.85, end: 1.0)
        .animate(
          CurvedAnimation(
            parent: _controller,
            curve: const Interval(0.0, 0.6, curve: AppMotion.entrance),
          ),
        );
    _wordmarkOpacity = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.35, 1.0, curve: AppMotion.entrance),
    );
    _controller.forward();

    // The router can navigate away from `/splash` as soon as the real
    // session check resolves, which can happen before these visuals have
    // been on screen long enough to register as anything more than a
    // flash. Rather than delaying that real navigation, this holds an
    // identical copy of the (by-then-settled) splash visuals on the root
    // Overlay -- above whatever the router mounts next -- until
    // `_minimumVisibleDuration` has elapsed.
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _holdMinimumVisibleDuration(),
    );
  }

  void _holdMinimumVisibleDuration() {
    if (!mounted) return;
    final overlayState = Overlay.maybeOf(context, rootOverlay: true);
    if (overlayState == null) return;

    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => const Positioned.fill(
        child: Material(color: Colors.transparent, child: _SplashVisual()),
      ),
    );
    overlayState.insert(entry);

    final remaining =
        _minimumVisibleDuration - DateTime.now().difference(_visibleSince);
    Future.delayed(remaining.isNegative ? Duration.zero : remaining, entry.remove);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) => _SplashVisual(
          logoOpacity: _logoOpacity.value,
          logoScale: _logoScale.value,
          wordmarkOpacity: _wordmarkOpacity.value,
        ),
      ),
    );
  }
}

/// The gradient background, logo, wordmark, and progress indicator that
/// make up the splash screen's content. Used both by [SplashScreen]'s own
/// `build()` (animated, via the opacity/scale parameters) and by the
/// minimum-visible-duration overlay in [_SplashScreenState] (settled at
/// its defaults, since by the time that overlay is the only thing showing
/// this content, the entrance animation has already finished or was
/// interrupted).
class _SplashVisual extends StatelessWidget {
  const _SplashVisual({
    this.logoOpacity = 1.0,
    this.logoScale = 1.0,
    this.wordmarkOpacity = 1.0,
  });

  final double logoOpacity;
  final double logoScale;
  final double wordmarkOpacity;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.textPrimary,
            AppColors.primaryDark,
            AppColors.primary,
          ],
        ),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Opacity(
              opacity: logoOpacity,
              child: Transform.scale(scale: logoScale, child: const _LogoMark()),
            ),
            const SizedBox(height: AppSpacing.lg),
            Opacity(opacity: wordmarkOpacity, child: const _Wordmark()),
            const SizedBox(height: AppSpacing.xxl),
            Opacity(
              opacity: wordmarkOpacity,
              child: const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: Colors.white70,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LogoMark extends StatelessWidget {
  const _LogoMark();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 88,
      height: 88,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.24)),
      ),
      child: const Icon(
        Icons.work_outline_rounded,
        size: 44,
        color: Colors.white,
      ),
    );
  }
}

class _Wordmark extends StatelessWidget {
  const _Wordmark();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          'OpportunityHub',
          style: Theme.of(context).textTheme.headlineLarge?.copyWith(
            color: Colors.white,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: AppSpacing.xxs),
        Text(
          'Find. Match. Grow.',
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(color: Colors.white70),
        ),
      ],
    );
  }
}
