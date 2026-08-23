import 'package:flutter/material.dart';

/// Centralized motion tokens — durations and curves — for the app's
/// "smart micro-interactions" (UI Phase 1).
///
/// Every custom animation added in this phase should use these instead of
/// a locally hardcoded `Duration`/`Curve`, so motion feels consistent
/// across screens. Kept intentionally small: three durations and two
/// curves cover every use case introduced in this phase (button/status
/// transitions, card hover, entrance fades, success reveals).
class AppMotion {
  AppMotion._();

  /// Small, frequent state changes — a focus ring, a hover shadow, a
  /// button's disabled/enabled swap.
  static const Duration fast = Duration(milliseconds: 150);

  /// The default for most transitions — status chip changes, card
  /// hover/press, skeleton-to-content crossfades.
  static const Duration normal = Duration(milliseconds: 250);

  /// Reserved for the few deliberately slower reveals — a splash entrance,
  /// a success icon, a Match Score fill.
  static const Duration slow = Duration(milliseconds: 350);

  /// Entrances — content appearing on screen for the first time.
  static const Curve entrance = Curves.easeOutCubic;

  /// Ordinary two-way transitions — hover, selection, value changes.
  static const Curve standard = Curves.easeInOut;

  /// Whether the platform/user has requested reduced motion — every custom
  /// animation in this phase should shorten to near-zero (not skip
  /// entirely, since an instant `AnimatedSwitcher`/`AnimatedContainer` swap
  /// still needs a duration to resolve correctly) when this is true, via
  /// [reduced].
  static bool isReduced(BuildContext context) =>
      MediaQuery.maybeOf(context)?.disableAnimations ?? false;

  /// Returns [duration] unchanged, or a near-instant duration when the
  /// current [context] has reduced motion enabled.
  static Duration reduced(BuildContext context, Duration duration) {
    return isReduced(context) ? const Duration(milliseconds: 1) : duration;
  }
}
