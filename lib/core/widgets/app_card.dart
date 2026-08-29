import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_motion.dart';
import '../theme/app_radius.dart';
import '../theme/app_shadows.dart';
import '../theme/app_spacing.dart';

/// The shadow strength for [AppCard].
enum AppCardElevation { none, card, elevated }

/// A reusable container/card wrapper matching the app's design system.
///
/// Uses [Material]+[InkWell] (not a bare [GestureDetector]) when [onTap]
/// is provided, so taps get a proper ripple clipped to the card's rounded
/// corners.
///
/// [interactive] is opt-in and defaults to `false`, so every existing
/// call site renders exactly as before — set it `true` on a per-card
/// basis (UI Phase 1: Student Home's quick-action/opportunity cards) to
/// add a subtle Web hover lift (border + shadow) and a mobile press-scale,
/// on top of the ripple [onTap] already provides. Has no effect without
/// [onTap], since there's nothing to press.
class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.padding,
    this.margin,
    this.onTap,
    this.backgroundColor,
    this.borderColor,
    this.borderRadius,
    this.elevation = AppCardElevation.card,
    this.interactive = false,
  });

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final VoidCallback? onTap;
  final Color? backgroundColor;
  final Color? borderColor;
  final BorderRadius? borderRadius;
  final AppCardElevation elevation;
  final bool interactive;

  List<BoxShadow> get _shadow {
    switch (elevation) {
      case AppCardElevation.none:
        return const [];
      case AppCardElevation.card:
        return AppShadows.card;
      case AppCardElevation.elevated:
        return AppShadows.elevated;
    }
  }

  @override
  Widget build(BuildContext context) {
    // UI Phase O4.1: `AppColors.x` below are plain statics, not derived
    // from `Theme.of(context)` — so unlike widgets that read
    // `Theme.of(context).textTheme` (which *do* register a real rebuild
    // dependency and thus refresh immediately on a theme toggle, per
    // AppColors's own doc comment), this card had no dependency of its
    // own. A caller whose build method never happens to touch
    // `Theme.of(context)` elsewhere (e.g. no text needing textTheme in the
    // same build) kept rendering the palette from its last incidental
    // rebuild — visible as a card stuck in the old theme's color after
    // toggling. This call exists purely to register that dependency.
    Theme.of(context);

    final radius = borderRadius ?? AppRadius.largeRadius;
    final resolvedBorderColor = borderColor ?? AppColors.border;
    final resolvedBackgroundColor = backgroundColor ?? AppColors.card;

    final content = Material(
      color: AppColors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: radius,
        child: Padding(
          padding: padding ?? const EdgeInsets.all(AppSpacing.cardPadding),
          child: child,
        ),
      ),
    );

    if (interactive && onTap != null) {
      return _InteractiveCardSurface(
        margin: margin,
        radius: radius,
        backgroundColor: resolvedBackgroundColor,
        borderColor: resolvedBorderColor,
        baseShadow: _shadow,
        child: content,
      );
    }

    return Container(
      margin: margin,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: resolvedBackgroundColor,
        borderRadius: radius,
        border: Border.all(color: resolvedBorderColor),
        boxShadow: _shadow,
      ),
      child: content,
    );
  }
}

/// The hover/press-aware surface used when [AppCard.interactive] is true.
/// Purely a decoration animation — the actual tap handling/ripple still
/// comes from the [InkWell] passed in as [child], so semantics/behavior
/// are unaffected.
class _InteractiveCardSurface extends StatefulWidget {
  const _InteractiveCardSurface({
    required this.child,
    required this.margin,
    required this.radius,
    required this.backgroundColor,
    required this.borderColor,
    required this.baseShadow,
  });

  final Widget child;
  final EdgeInsetsGeometry? margin;
  final BorderRadius radius;
  final Color backgroundColor;
  final Color borderColor;
  final List<BoxShadow> baseShadow;

  @override
  State<_InteractiveCardSurface> createState() =>
      _InteractiveCardSurfaceState();
}

class _InteractiveCardSurfaceState extends State<_InteractiveCardSurface> {
  bool _isHovered = false;
  bool _isPressed = false;

  void _setHovered(bool value) {
    if (_isHovered == value) return;
    setState(() => _isHovered = value);
  }

  void _setPressed(bool value) {
    if (_isPressed == value) return;
    setState(() => _isPressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final duration = AppMotion.reduced(context, AppMotion.fast);
    final scale = _isPressed ? 0.98 : 1.0;

    return MouseRegion(
      onEnter: (_) => _setHovered(true),
      onExit: (_) => _setHovered(false),
      child: Listener(
        onPointerDown: (_) => _setPressed(true),
        onPointerUp: (_) => _setPressed(false),
        onPointerCancel: (_) => _setPressed(false),
        child: AnimatedScale(
          scale: scale,
          duration: duration,
          curve: AppMotion.standard,
          child: AnimatedContainer(
            duration: duration,
            curve: AppMotion.standard,
            margin: widget.margin,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: widget.backgroundColor,
              borderRadius: widget.radius,
              border: Border.all(
                color: _isHovered ? AppColors.primary : widget.borderColor,
                width: _isHovered ? 1.5 : 1,
              ),
              boxShadow: _isHovered ? AppShadows.elevated : widget.baseShadow,
            ),
            child: widget.child,
          ),
        ),
      ),
    );
  }
}
