import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Full-screen branded loading state, styled after Blinkit's: a clean white
/// screen, a small animated illustration in the middle and one friendly line
/// under it.
///
/// Shown for unusually slow loads only — see [SlowLoadGate], which keeps the
/// screen's own skeleton for ordinary waits and escalates to this one when a
/// load drags on.
class BrandedLoadingScreen extends StatelessWidget {
  const BrandedLoadingScreen({
    super.key,
    this.tagline = BrandedLoader.defaultTagline,
  });

  /// The line under the illustration. Callers can pass something contextual
  /// ("Finding the best technicians near you").
  final String tagline;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(child: BrandedLoader(tagline: tagline)),
    );
  }
}

/// The illustration + tagline on their own (no Scaffold), so it can sit
/// inside another screen — under an app bar, over the splash, etc.
class BrandedLoader extends StatefulWidget {
  const BrandedLoader({super.key, this.tagline = defaultTagline});

  static const defaultTagline = 'Everything you need, delivered at your doorstep';

  final String tagline;

  @override
  State<BrandedLoader> createState() => _BrandedLoaderState();
}

class _BrandedLoaderState extends State<BrandedLoader>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2400),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 150,
            height: 130,
            child: reduceMotion
                ? const _Illustration(t: 0.25)
                : AnimatedBuilder(
                    animation: _controller,
                    builder: (context, _) => _Illustration(t: _controller.value),
                  ),
          ),
          const SizedBox(height: 18),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 48),
            child: Text(
              widget.tagline,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 14.5,
                height: 1.4,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A basket that bobs up and down while a leaf, a bolt and a tool float
/// around it — "groceries, quick delivery and home services" in one glance.
class _Illustration extends StatelessWidget {
  const _Illustration({required this.t});

  /// 0..1 loop position.
  final double t;

  @override
  Widget build(BuildContext context) {
    final angle = t * 2 * math.pi;
    final bob = math.sin(angle) * 5;
    final pulse = 1 + math.sin(angle) * 0.04;

    Widget floater(IconData icon, Color color, double phase, Offset base) {
      final a = angle + phase;
      return Positioned(
        left: 75 + base.dx + math.cos(a) * 4 - 15,
        top: 65 + base.dy + math.sin(a) * 5 - 15,
        child: Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.14),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, size: 17, color: color),
        ),
      );
    }

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned.fill(
          child: Center(
            child: Transform.scale(
              scale: pulse,
              child: Container(
                width: 92,
                height: 92,
                decoration: const BoxDecoration(
                  color: AppColors.primaryLight,
                  shape: BoxShape.circle,
                ),
              ),
            ),
          ),
        ),
        floater(Icons.eco_rounded, AppColors.groceryGreen, 0.0, const Offset(-56, -30)),
        floater(Icons.bolt_rounded, const Color(0xFFF59E0B), 2.1, const Offset(58, -26)),
        floater(Icons.home_repair_service_rounded, AppColors.serviceBlue, 4.2, const Offset(46, 38)),
        Positioned.fill(
          child: Transform.translate(
            offset: Offset(0, bob),
            child: const Center(
              child: Icon(Icons.shopping_basket_rounded, size: 46, color: AppColors.primary),
            ),
          ),
        ),
      ],
    );
  }
}
