import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../theme/app_motion.dart';

/// A large status icon (e.g. success check, error mark) with a one-time
/// scale + fade entrance — for "big icon + title + message" result
/// screens (password reset success, email verification result, ...).
///
/// Reduced-motion falls back to an effectively instant reveal (no
/// perceptible scale/fade), matching [AppMotion]'s reduced-motion
/// convention elsewhere.
class AppAnimatedStatusIcon extends StatefulWidget {
  const AppAnimatedStatusIcon({
    super.key,
    required this.icon,
    required this.color,
    this.backgroundColor,
    this.size = 56,
  });

  final IconData icon;
  final Color color;
  final Color? backgroundColor;
  final double size;

  @override
  State<AppAnimatedStatusIcon> createState() => _AppAnimatedStatusIconState();
}

class _AppAnimatedStatusIconState extends State<AppAnimatedStatusIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scale;
  late final Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    final reducedMotion = SchedulerBinding
        .instance
        .platformDispatcher
        .accessibilityFeatures
        .disableAnimations;

    _controller = AnimationController(
      vsync: this,
      duration: reducedMotion ? const Duration(milliseconds: 1) : AppMotion.slow,
    );
    _scale = Tween<double>(begin: reducedMotion ? 1.0 : 0.6, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: AppMotion.entrance),
    );
    _opacity = CurvedAnimation(parent: _controller, curve: AppMotion.entrance);
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final boxSize = widget.size * 1.3;

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Opacity(
          opacity: _opacity.value,
          child: Transform.scale(scale: _scale.value, child: child),
        );
      },
      child: Container(
        width: boxSize,
        height: boxSize,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: widget.backgroundColor,
          shape: BoxShape.circle,
        ),
        child: Icon(widget.icon, size: widget.size, color: widget.color),
      ),
    );
  }
}
