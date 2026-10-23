import 'dart:math' as math;

import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';

/// Shared motion helpers so the whole app moves the same way: soft entrances,
/// a gentle press response and a bounce when a number changes.

/// Scroll feel for every list: a soft overscroll bounce on all platforms
/// (no stretch/glow), and drag-to-scroll with mouse / trackpad too.
class AppScrollBehavior extends MaterialScrollBehavior {
  const AppScrollBehavior();

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) =>
      const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics());

  @override
  Widget buildOverscrollIndicator(BuildContext context, Widget child, ScrollableDetails details) => child;

  @override
  Set<PointerDeviceKind> get dragDevices => {
        PointerDeviceKind.touch,
        PointerDeviceKind.mouse,
        PointerDeviceKind.trackpad,
        PointerDeviceKind.stylus,
      };
}

/// Fades a child in while it slides up a few pixels. Give list items their
/// [index] so they arrive one after another (capped, so long lists never feel
/// slow). Plays once, when the widget is first built.
class FadeSlideIn extends StatefulWidget {
  const FadeSlideIn({
    super.key,
    required this.child,
    this.index = 0,
    this.offset = 14,
    this.duration = const Duration(milliseconds: 380),
  });

  final Widget child;
  final int index;
  final double offset;
  final Duration duration;

  @override
  State<FadeSlideIn> createState() => _FadeSlideInState();
}

class _FadeSlideInState extends State<FadeSlideIn> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: widget.duration);
  late final Animation<double> _curve = CurvedAnimation(parent: _c, curve: Curves.easeOutCubic);

  @override
  void initState() {
    super.initState();
    final delay = Duration(milliseconds: 45 * math.min(widget.index, 8));
    if (delay == Duration.zero) {
      _c.forward();
    } else {
      Future.delayed(delay, () {
        if (mounted) _c.forward();
      });
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _curve,
      child: widget.child,
      builder: (context, child) => Opacity(
        opacity: _curve.value,
        child: Transform.translate(offset: Offset(0, (1 - _curve.value) * widget.offset), child: child),
      ),
    );
  }
}

/// Shrinks its child slightly while a finger is down on it and springs back.
/// It only listens to raw pointer events, so taps still reach the child.
class PressScale extends StatefulWidget {
  const PressScale({super.key, required this.child, this.scale = 0.97});

  final Widget child;
  final double scale;

  @override
  State<PressScale> createState() => _PressScaleState();
}

class _PressScaleState extends State<PressScale> {
  bool _down = false;

  void _set(bool v) {
    if (_down != v && mounted) setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (_) => _set(true),
      onPointerUp: (_) => _set(false),
      onPointerCancel: (_) => _set(false),
      child: AnimatedScale(
        scale: _down ? widget.scale : 1.0,
        duration: const Duration(milliseconds: 110),
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );
  }
}

/// Pops (scales up then settles) whenever [value] changes - for cart / unread
/// count badges.
class BounceOnChange extends StatefulWidget {
  const BounceOnChange({super.key, required this.value, required this.child});

  final Object? value;
  final Widget child;

  @override
  State<BounceOnChange> createState() => _BounceOnChangeState();
}

class _BounceOnChangeState extends State<BounceOnChange> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 420));

  @override
  void didUpdateWidget(covariant BounceOnChange old) {
    super.didUpdateWidget(old);
    if (old.value != widget.value) _c.forward(from: 0);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      child: widget.child,
      builder: (context, child) {
        // 1 -> 1.35 -> 1 with a little overshoot.
        final t = _c.value;
        final s = 1 + 0.35 * math.sin(t * math.pi) * (1 - t * 0.3);
        return Transform.scale(scale: s, child: child);
      },
    );
  }
}

/// Rings (a short left-right swing that fades out) each time [trigger] changes
/// to a bigger number - used for the notification bell.
class RingOnIncrease extends StatefulWidget {
  const RingOnIncrease({super.key, required this.count, required this.child});

  final int count;
  final Widget child;

  @override
  State<RingOnIncrease> createState() => _RingOnIncreaseState();
}

class _RingOnIncreaseState extends State<RingOnIncrease> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));

  @override
  void didUpdateWidget(covariant RingOnIncrease old) {
    super.didUpdateWidget(old);
    if (widget.count > old.count) _c.forward(from: 0);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      child: widget.child,
      builder: (context, child) {
        final t = _c.value;
        final angle = math.sin(t * math.pi * 6) * 0.35 * (1 - t);
        return Transform.rotate(angle: angle, alignment: Alignment.topCenter, child: child);
      },
    );
  }
}

/// A "searching" animation: soft rings spread out from a centre badge, like a
/// radar. Used while the app is waiting for something to be found (e.g. a
/// technician being assigned).
class SearchingPulse extends StatefulWidget {
  const SearchingPulse({
    super.key,
    this.size = 120,
    this.icon = Icons.person_search_rounded,
    this.color = const Color(0xFF05A357),
  });

  final double size;
  final IconData icon;
  final Color color;

  @override
  State<SearchingPulse> createState() => _SearchingPulseState();
}

class _SearchingPulseState extends State<SearchingPulse> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 2400))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final core = widget.size * 0.38;
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          return Stack(
            alignment: Alignment.center,
            children: [
              for (var i = 0; i < 3; i++)
                () {
                  final t = (_c.value + i / 3) % 1.0;
                  final d = core + (widget.size - core) * Curves.easeOut.transform(t);
                  return Container(
                    width: d,
                    height: d,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: widget.color.withValues(alpha: 0.18 * (1 - t)),
                      border: Border.all(color: widget.color.withValues(alpha: 0.35 * (1 - t)), width: 1.2),
                    ),
                  );
                }(),
              Container(
                width: core,
                height: core,
                decoration: BoxDecoration(
                  color: widget.color,
                  shape: BoxShape.circle,
                  boxShadow: [BoxShadow(color: widget.color.withValues(alpha: 0.35), blurRadius: 12, offset: const Offset(0, 4))],
                ),
                child: Icon(widget.icon, color: Colors.white, size: core * 0.55),
              ),
            ],
          );
        },
      ),
    );
  }
}
