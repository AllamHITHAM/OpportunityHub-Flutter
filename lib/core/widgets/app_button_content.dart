import 'package:flutter/material.dart';

import '../theme/app_motion.dart';
import '../theme/app_spacing.dart';

/// Shared label/icon/spinner layout used by [PrimaryButton], [SecondaryButton],
/// and [DangerButton].
///
/// Not part of the public design-system API on its own — it exists only so
/// the three buttons don't each repeat the same loading-state layout.
class AppButtonContent extends StatelessWidget {
  const AppButtonContent({
    super.key,
    required this.label,
    required this.isLoading,
    required this.spinnerColor,
    this.icon,
  });

  final String label;
  final bool isLoading;
  final Color spinnerColor;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final labelChild = icon == null
        ? Text(label)
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18),
              const SizedBox(width: AppSpacing.xs),
              // Flexible (not a bare Text) so a long label ellipsizes
              // instead of overflowing the Row when this button is placed
              // in a narrower parent than usual — a real, previously
              // latent bug, not a style change for any button that
              // already fits.
              Flexible(
                child: Text(label, overflow: TextOverflow.ellipsis, maxLines: 1),
              ),
            ],
          );

    return Stack(
      alignment: Alignment.center,
      children: [
        // Keeping the label in the tree (just invisible) while loading
        // means the button keeps its natural size instead of shrinking
        // down to fit the spinner alone.
        Opacity(opacity: isLoading ? 0 : 1, child: labelChild),
        if (isLoading)
          SizedBox(
            height: 20,
            width: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2.5,
              color: spinnerColor,
            ),
          ),
      ],
    );
  }
}

/// Shared Web-hover-lift + press-scale wrapper for [PrimaryButton],
/// [SecondaryButton], and [DangerButton] (UI Phase 1.5).
///
/// Purely decorative -- it wraps the real button (still the thing that's
/// hit-tested, focused, and carries `onPressed`/loading state) in a
/// [MouseRegion]/[Listener] pair driving two implicit animations, exactly
/// the pattern [AppCard]'s interactive surface already uses. No
/// [AnimationController] of its own, so it doesn't add a ticker per
/// button on screen.
class ButtonInteractionSurface extends StatefulWidget {
  const ButtonInteractionSurface({super.key, required this.child});

  final Widget child;

  @override
  State<ButtonInteractionSurface> createState() =>
      _ButtonInteractionSurfaceState();
}

class _ButtonInteractionSurfaceState extends State<ButtonInteractionSurface> {
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
    final scale = _isPressed ? 0.97 : (_isHovered ? 1.015 : 1.0);

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
          child: widget.child,
        ),
      ),
    );
  }
}
