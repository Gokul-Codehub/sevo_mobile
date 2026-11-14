import 'package:calservices_customer/shared/theme/app_colors.dart';
import 'dart:math' as math;

import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

/// Shared motion helpers so the whole app moves the same way: soft entrances,
/// a gentle press response and a bounce when a number changes.

/// True when the OS accessibility setting asks for reduced motion.
bool prefersReducedMotion(BuildContext context) =>
    MediaQuery.maybeOf(context)?.disableAnimations ?? false;

/// Light tactile feedback for conversion actions. Safe to call without a
/// context; never throws if the platform ignores haptics.
class AppHaptics {
  const AppHaptics._();

  static void selection() {
    HapticFeedback.selectionClick();
  }

  static void light() {
    HapticFeedback.lightImpact();
  }

  static void success() {
    HapticFeedback.mediumImpact();
  }
}

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
    // Delay start until first frame so MediaQuery is available for reduce-motion.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (prefersReducedMotion(context)) {
        _c.value = 1;
        return;
      }
      final delay = Duration(milliseconds: 45 * math.min(widget.index, 8));
      if (delay == Duration.zero) {
        _c.forward();
      } else {
        Future.delayed(delay, () {
          if (mounted) _c.forward();
        });
      }
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (prefersReducedMotion(context)) return widget.child;
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
    if (prefersReducedMotion(context)) return widget.child;
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
    if (old.value != widget.value && !prefersReducedMotion(context)) {
      _c.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (prefersReducedMotion(context)) return widget.child;
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
    if (widget.count > old.count && !prefersReducedMotion(context)) {
      _c.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (prefersReducedMotion(context)) return widget.child;
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

/// Soft fade + slight vertical slide whenever [child] is swapped (by [key] or
/// type). Use for step pages, status headlines and empty→content swaps.
class FadeThrough extends StatelessWidget {
  const FadeThrough({
    super.key,
    required this.child,
    this.duration = const Duration(milliseconds: 280),
    this.offset = 10,
  });

  final Widget child;
  final Duration duration;
  final double offset;

  @override
  Widget build(BuildContext context) {
    if (prefersReducedMotion(context)) return child;
    return AnimatedSwitcher(
      duration: duration,
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      // Top-align so step content in an Expanded parent doesn't float in the
      // middle of empty space (default Stack alignment is center).
      layoutBuilder: (currentChild, previousChildren) => Stack(
        alignment: Alignment.topCenter,
        fit: StackFit.passthrough,
        children: <Widget>[
          ...previousChildren,
          if (currentChild != null) currentChild,
        ],
      ),
      transitionBuilder: (child, anim) {
        final slide = Tween<Offset>(
          begin: Offset(0, offset / 80),
          end: Offset.zero,
        ).animate(anim);
        return FadeTransition(
          opacity: anim,
          child: SlideTransition(position: slide, child: child),
        );
      },
      child: child,
    );
  }
}

/// Soft breathing dot — LIVE GPS / syncing badges.
class PulseDot extends StatefulWidget {
  const PulseDot({
    super.key,
    this.size = 7,
    this.color = AppColors.swatch0B2337,
  });

  final double size;
  final Color color;

  @override
  State<PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<PulseDot> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1100));

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (!prefersReducedMotion(context)) _c.repeat(reverse: true);
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (prefersReducedMotion(context)) {
      return Container(
        width: widget.size,
        height: widget.size,
        decoration: BoxDecoration(shape: BoxShape.circle, color: widget.color),
      );
    }
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final t = Curves.easeInOut.transform(_c.value);
        return Container(
          width: widget.size,
          height: widget.size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: widget.color,
            boxShadow: [
              BoxShadow(
                color: widget.color.withValues(alpha: 0.35 + 0.35 * t),
                blurRadius: 4 + 6 * t,
                spreadRadius: t * 1.5,
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Progress bar that eases to the new [value] instead of jumping.
class SmoothProgressBar extends StatelessWidget {
  const SmoothProgressBar({
    super.key,
    required this.value,
    this.minHeight = 7,
    this.backgroundColor,
    this.color,
    this.borderRadius = 10,
  });

  final double value;
  final double minHeight;
  final Color? backgroundColor;
  final Color? color;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    final clamped = value.clamp(0.0, 1.0);
    final bg = backgroundColor ?? const Color(0xFFE8EDF3);
    final fg = color ?? Theme.of(context).colorScheme.primary;
    final reduce = prefersReducedMotion(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: SizedBox(
        height: minHeight,
        child: TweenAnimationBuilder<double>(
          tween: Tween(end: clamped),
          duration: reduce ? Duration.zero : const Duration(milliseconds: 420),
          curve: Curves.easeOutCubic,
          builder: (context, v, _) => LinearProgressIndicator(
            value: v,
            minHeight: minHeight,
            backgroundColor: bg,
            valueColor: AlwaysStoppedAnimation<Color>(fg),
          ),
        ),
      ),
    );
  }
}

/// Short celebratory burst of soft dots around a success badge.
class CelebrationBurst extends StatefulWidget {
  const CelebrationBurst({
    super.key,
    required this.child,
    this.color = const Color(0xFF05A357),
    this.size = 160,
  });

  final Widget child;
  final Color color;
  final double size;

  @override
  State<CelebrationBurst> createState() => _CelebrationBurstState();
}

class _CelebrationBurstState extends State<CelebrationBurst>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1100));

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (prefersReducedMotion(context)) {
        _c.value = 1;
      } else {
        _c.forward();
      }
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (prefersReducedMotion(context)) {
      return SizedBox(
        width: widget.size,
        height: widget.size,
        child: Center(child: widget.child),
      );
    }
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, child) {
          final t = Curves.easeOutCubic.transform(_c.value);
          return Stack(
            alignment: Alignment.center,
            children: [
              for (var i = 0; i < 8; i++)
                Transform.translate(
                  offset: Offset(
                    math.cos(i * math.pi / 4) * (18 + 36 * t),
                    math.sin(i * math.pi / 4) * (18 + 36 * t),
                  ),
                  child: Opacity(
                    opacity: (1 - t).clamp(0.0, 1.0),
                    child: Container(
                      width: 7 - 2 * t,
                      height: 7 - 2 * t,
                      decoration: BoxDecoration(
                        color: i.isEven ? widget.color : AppColors.swatch0B2337,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                ),
              child!,
            ],
          );
        },
        child: widget.child,
      ),
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
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 2400));

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (!prefersReducedMotion(context)) _c.repeat();
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (prefersReducedMotion(context)) {
      final core = widget.size * 0.38;
      return SizedBox(
        width: widget.size,
        height: widget.size,
        child: Center(
          child: Container(
            width: core,
            height: core,
            decoration: BoxDecoration(
              color: widget.color,
              shape: BoxShape.circle,
            ),
            child: Icon(widget.icon, color: Colors.white, size: core * 0.55),
          ),
        ),
      );
    }
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

/// Gentle scale pulse used to draw attention to a ready CTA (e.g. Confirm).
class AttentionPulse extends StatefulWidget {
  const AttentionPulse({
    super.key,
    required this.child,
    this.enabled = true,
    this.minScale = 1.0,
    this.maxScale = 1.03,
  });

  final Widget child;
  final bool enabled;
  final double minScale;
  final double maxScale;

  @override
  State<AttentionPulse> createState() => _AttentionPulseState();
}

class _AttentionPulseState extends State<AttentionPulse>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (widget.enabled && !prefersReducedMotion(context)) {
        _c.repeat(reverse: true);
      }
    });
  }

  @override
  void didUpdateWidget(covariant AttentionPulse oldWidget) {
    super.didUpdateWidget(oldWidget);
    final reduce = prefersReducedMotion(context);
    if (widget.enabled && !reduce && !_c.isAnimating) {
      _c.repeat(reverse: true);
    } else if ((!widget.enabled || reduce) && _c.isAnimating) {
      _c
        ..stop()
        ..value = 0;
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled || prefersReducedMotion(context)) return widget.child;
    return AnimatedBuilder(
      animation: _c,
      child: widget.child,
      builder: (context, child) {
        final t = Curves.easeInOut.transform(_c.value);
        final scale = widget.minScale + (widget.maxScale - widget.minScale) * t;
        return Transform.scale(scale: scale, child: child);
      },
    );
  }
}

/// Soft fade + slight slide used for major push routes (detail, checkout, success).
CustomTransitionPage<T> softFadeSlidePage<T>({
  required LocalKey key,
  required Widget child,
  Duration duration = const Duration(milliseconds: 300),
  Duration reverseDuration = const Duration(milliseconds: 240),
}) {
  return CustomTransitionPage<T>(
    key: key,
    child: child,
    transitionDuration: duration,
    reverseTransitionDuration: reverseDuration,
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      if (prefersReducedMotion(context)) return child;
      final curved = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
      return FadeTransition(
        opacity: curved,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0.04, 0),
            end: Offset.zero,
          ).animate(curved),
          child: child,
        ),
      );
    },
  );
}
