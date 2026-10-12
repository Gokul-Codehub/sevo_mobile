import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/storage/secure_storage.dart';
import '../../../../routing/app_router.dart';
import '../../../addresses/domain/address_notifier.dart';
import '../../../catalog/domain/catalog_providers.dart';
import '../../../home/data/homepage_repository.dart';

/// Screen 1: Splash Screen
///
/// This is the FIRST thing a user sees on every cold start — AppRoutes.splash
/// is the router's initialLocation (see app_router.dart) specifically so
/// nothing else can render before this does.
///
/// Fixed 2026-08-27: the image fills the entire device width and height
/// (BoxFit.cover, no letterboxing/contained sizing), matching the original
/// full-bleed splash design — the earlier revision shrank it into a
/// centered logo on a plain gradient, which wasn't the intent. A
/// three-dot pulsing loader sits inside the bottom of that same image
/// (via a Stack + Positioned, not a separate area below it) so the screen
/// reads as "loading" instead of a static picture, without changing how
/// the image itself is displayed.
class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animController;
  late final Animation<double> _fadeAnim;
  Timer? _navTimer;

  static const _splashAsset = 'assets/images/sevo_splash.webp';
  /// The brand splash image always stays up this long (the original 2.2 s) ...
  static const _minDisplay = Duration(milliseconds: 2200);

  /// ... and, if Home's first data is still loading after that, a little
  /// longer — never more than this in total — so Home opens filled in.
  static const _maxWait = Duration(seconds: 6);

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _fadeAnim = CurvedAnimation(parent: _animController, curve: Curves.easeIn);
    _animController.forward();
    // Added 2026-10-07 ("while loading the splash screen load the entire
    // application fastly atleast home page"): before this, Home's own
    // `ref.watch(homepageConfigProvider)`/`ref.watch(categoriesProvider)`
    // calls in home_screen.dart's build() were the EARLIEST point either
    // ever got read — meaning their network fetch only started AFTER this
    // screen's fixed _displayDuration had already elapsed and navigation
    // to Home had happened, wasting the ~2.2s this screen is shown for
    // anyway. Both are plain (non-`.autoDispose`) FutureProviders, so
    // merely reading them — not awaiting the result — starts their fetch
    // immediately and keeps it cached; doing that here runs the fetch in
    // parallel with the branding timer below, so by the time Home actually
    // builds, its own `ref.watch` calls usually just reuse an
    // already-finished (or much further along) Future instead of starting
    // a fresh one ~2.2s late. Deliberately fire-and-forget: a failure here
    // is not handled specially, since home_screen.dart's own `.when()`
    // error/retry handling already covers it the moment Home itself reads
    // the same provider.
    ref.read(homepageConfigProvider);
    ref.read(categoriesProvider);
    // Fixed 2026-10-08 ("the saved address has cleared automatically...
    // that should be stored in that account"): the address itself was
    // never actually lost on the backend — `selectedAddressProvider`
    // (address_notifier.dart) is a plain in-memory `StateProvider` that
    // always starts `null` on every cold start, and the ONLY code that
    // ever re-populates it from the account's saved addresses is
    // `AddressListNotifier.build()`'s auto-select-default logic — which
    // only runs once something actually reads/watches `addressListProvider`.
    // Nothing did that early: Home and Checkout both only ever watched
    // `selectedAddressProvider` itself, never `addressListProvider`, so
    // unless the customer happened to open the Addresses list screen
    // first, the saved default address never got loaded back in for the
    // rest of the session — reading as "my saved address disappeared"
    // even though it was sitting untouched in their account the whole
    // time. Reading it here (same fire-and-forget pattern as
    // homepageConfigProvider/categoriesProvider just above — a guest
    // session's `build()` returns `const []` immediately and does nothing
    // further) starts that fetch-and-auto-select as early as possible on
    // every cold start, so the account's saved address is back in
    // `selectedAddressProvider` by the time Home/Checkout need it.
    ref.read(addressListProvider);
    _navTimer = Timer(_minDisplay, () async {
      if (!mounted) return;
      // Hold the splash until the data Home needs has arrived, so the
      // customer lands on a filled-in page instead of a wall of skeletons.
      // Errors/timeouts are ignored here — Home handles those itself.
      try {
        await Future.wait<Object?>([
          ref.read(homepageConfigProvider.future),
          ref.read(categoriesProvider.future),
        ]).timeout(_maxWait - _minDisplay);
      } catch (_) {}
      if (!mounted) return;
      // Fixed 2026-09-19 — this used to go straight to Home on every cold
      // start, which meant OnboardingScreen and LocationAccessScreen
      // (both fully built, both registered routes) were never actually
      // reachable. First launch now goes through them; every launch after
      // that (the flag is set once onboarding finishes) goes straight to
      // Home same as before — this app still supports guest browsing, so
      // there's no login wall added here.
      final hasSeenOnboarding =
          await ref.read(secureStorageProvider).hasSeenOnboarding();
      if (!mounted) return;
      context.go(hasSeenOnboarding ? AppRoutes.home : AppRoutes.onboarding);
    });
  }

  @override
  void dispose() {
    _navTimer?.cancel();
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: FadeTransition(
        opacity: _fadeAnim,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Full-bleed splash image — covers the entire device width and
            // height, same as the original design.
            Image.asset(
              _splashAsset,
              fit: BoxFit.cover,
              // If the asset is ever missing (e.g. a build that hasn't
              // picked up the asset yet), fail safe to a plain white
              // screen for the same duration rather than crashing — the
              // timer above still fires and takes the user in.
              errorBuilder: (context, error, stackTrace) =>
                  const ColoredBox(color: Colors.white),
            ),
            // Loader sits inside the bottom of the image itself, not in a
            // separate area below it.
            Positioned(
              left: 0,
              right: 0,
              bottom: 56,
              child: SafeArea(
                top: false,
                child: Center(child: _ThreeDotLoader()),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Three dots that pulse in a staggered sequence, looping continuously for
/// as long as the splash screen is on screen — the honest "still loading"
/// signal a plain static image can't give. Respects the system's reduced
/// -motion setting by holding the dots at a fixed, even brightness instead
/// of animating them.
class _ThreeDotLoader extends StatefulWidget {
  const _ThreeDotLoader();

  @override
  State<_ThreeDotLoader> createState() => _ThreeDotLoaderState();
}

class _ThreeDotLoaderState extends State<_ThreeDotLoader>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.of(context).disableAnimations;

    if (reduceMotion) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(
          3,
          (i) => const Padding(
            padding: EdgeInsets.symmetric(horizontal: 4),
            child: _Dot(scale: 0.85, opacity: 0.85),
          ),
        ),
      );
    }

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (i) {
            // Each dot's pulse is offset by a third of the cycle so they
            // rise and fall in a rolling wave rather than all together.
            final phase = (_controller.value + (i * 0.33)) % 1.0;
            final wave = 1 - (2 * phase - 1).abs(); // 0 -> 1 -> 0 triangle
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: _Dot(
                scale: 0.55 + 0.45 * wave,
                opacity: 0.45 + 0.55 * wave,
              ),
            );
          }),
        );
      },
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot({required this.scale, required this.opacity});

  final double scale;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    return Transform.scale(
      scale: scale,
      child: Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: opacity),
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.25),
              blurRadius: 4,
            ),
          ],
        ),
      ),
    );
  }
}
