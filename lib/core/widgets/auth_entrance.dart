import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../theme/app_motion.dart';

/// A restrained staggered entrance for a vertical list of sections (UI
/// Phase 1.5) — each child fades and slides up slightly, one after
/// another, instead of the whole screen appearing at once.
///
/// A drop-in replacement for a `Column` wherever a screen wants this
/// entrance treatment: pass the same children (spacing `SizedBox`es
/// included) that would otherwise go directly into a `Column` --
/// `AuthEntrance` builds that `Column` itself.
///
/// One [AnimationController] drives every child via staggered [Interval]s,
/// rather than one controller per child, so screens with several sections
/// don't accumulate extra tickers. Never delays interactivity -- the
/// controller starts immediately in [initState] and every field stays
/// hit-testable throughout (only opacity/position animate).
///
/// Reduced motion collapses this to a single, fast, un-staggered fade with
/// no slide -- content still appears, just without the choreography.
class AuthEntrance extends StatefulWidget {
  const AuthEntrance({
    super.key,
    required this.children,
    this.mainAxisAlignment = MainAxisAlignment.start,
    this.mainAxisSize = MainAxisSize.min,
  });

  final List<Widget> children;
  final MainAxisAlignment mainAxisAlignment;

  /// Defaults to [MainAxisSize.min], the only safe choice when this sits
  /// inside a scrollable (unbounded height) -- the common case for every
  /// registration/auth form. Pass [MainAxisSize.max] only when the parent
  /// genuinely bounds the height (e.g. an `Expanded` panel) and
  /// [mainAxisAlignment] needs real extra space to center within.
  final MainAxisSize mainAxisSize;

  @override
  State<AuthEntrance> createState() => _AuthEntranceState();
}

class _AuthEntranceState extends State<AuthEntrance>
    with SingleTickerProviderStateMixin {
  static const _perItem = AppMotion.normal;
  static const _stagger = Duration(milliseconds: 60);

  late final AnimationController _controller;
  late final bool _reducedMotion;
  late final int _totalMs;

  @override
  void initState() {
    super.initState();
    _reducedMotion = SchedulerBinding
        .instance
        .platformDispatcher
        .accessibilityFeatures
        .disableAnimations;

    final staggeredSpan =
        _stagger.inMilliseconds * (widget.children.length - 1).clamp(0, 1 << 30);
    _totalMs = _reducedMotion
        ? 1
        : _perItem.inMilliseconds + staggeredSpan;

    _controller = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: _totalMs),
    )..forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Widget _buildItem(int index, Widget child) {
    if (_reducedMotion) {
      return FadeTransition(opacity: _controller, child: child);
    }

    final startMs = index * _stagger.inMilliseconds;
    final endMs = startMs + _perItem.inMilliseconds;
    final start = startMs / _totalMs;
    final end = (endMs / _totalMs).clamp(start, 1.0);

    final curved = CurvedAnimation(
      parent: _controller,
      curve: Interval(start, end, curve: AppMotion.entrance),
    );

    return FadeTransition(
      opacity: curved,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.05),
          end: Offset.zero,
        ).animate(curved),
        child: child,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.children.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: widget.mainAxisSize,
      mainAxisAlignment: widget.mainAxisAlignment,
      children: [
        for (var i = 0; i < widget.children.length; i++)
          _buildItem(i, widget.children[i]),
      ],
    );
  }
}
