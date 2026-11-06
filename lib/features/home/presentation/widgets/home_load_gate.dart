import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/network_state.dart';
import '../../../../shared/theme/app_colors.dart';
import '../../../../shared/widgets/branded_loading_screen.dart';
import '../../../catalog/domain/catalog_providers.dart';
import '../../data/homepage_repository.dart' show homepageConfigProvider;

/// How long Home may sit on the full-screen loader before it says it is still trying and offers Retry.
const Duration homeSlowLoadAfter = Duration(seconds: 20);

/// Whether Home has nothing at all to show yet: no homepage settings and no categories.
bool homeHasNothingLoaded({required bool hasHomepageConfig, required bool hasCategories}) => !hasHomepageConfig && !hasCategories;

/// Home's loading rule:
///  * NOTHING loaded yet  -> the branded splash loader fills the whole screen;
///  * PART loaded          -> the page shows, and each section that is still waiting shows its own skeleton.
/// If nothing has loaded after [homeSlowLoadAfter] the splash says it is still trying and offers Retry (and the
/// top "could not reach SEVO" banner stays out of the way, because the splash already says it).
class HomeLoadGate extends ConsumerStatefulWidget {
  const HomeLoadGate({super.key, required this.child, this.slowAfter = homeSlowLoadAfter});
  final Widget child;
  final Duration slowAfter;

  @override
  ConsumerState<HomeLoadGate> createState() => _HomeLoadGateState();
}

class _HomeLoadGateState extends ConsumerState<HomeLoadGate> {
  late final ProviderContainer _container = ProviderScope.containerOf(context, listen: false);
  bool _active = false;
  bool _slow = false;
  Timer? _slowTimer;

  void _setActive(bool value) {
    if (value == _active) return;
    _active = value;
    _slowTimer?.cancel();
    if (value) {
      _slowTimer = Timer(widget.slowAfter, () {
        if (mounted) setState(() => _slow = true);
      });
    } else {
      _slow = false;
    }
    // Tell the app shell (so it can hold the unreachable banner back); never during build.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      try {
        _container.read(fullScreenLoaderActiveProvider.notifier).state = value;
      } catch (_) {}
    });
  }

  @override
  void dispose() {
    _slowTimer?.cancel();
    final container = _container;
    Future.microtask(() {
      try {
        container.read(fullScreenLoaderActiveProvider.notifier).state = false;
      } catch (_) {
        // The whole app scope is being torn down (nothing left to tell).
      }
    });
    super.dispose();
  }

  void _retry() {
    ref.invalidate(homepageConfigProvider);
    ref.invalidate(categoriesProvider);
    setState(() => _slow = false);
    _slowTimer?.cancel();
    _slowTimer = Timer(widget.slowAfter, () {
      if (mounted) setState(() => _slow = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    final hasConfig = ref.watch(homepageConfigProvider.select((a) => a.valueOrNull != null));
    final hasCategories = ref.watch(categoriesProvider.select((a) => (a.valueOrNull ?? const []).isNotEmpty));
    final nothing = homeHasNothingLoaded(hasHomepageConfig: hasConfig, hasCategories: hasCategories);
    _setActive(nothing);
    return Stack(
      children: [
        widget.child,
        if (nothing)
          Positioned.fill(
            child: Material(
              color: Colors.white,
              child: SafeArea(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Flexible(
                      child: BrandedLoader(tagline: _slow ? 'Still trying to reach SEVONIQ…\nPlease check your connection.' : BrandedLoader.defaultTagline),
                    ),
                    if (_slow)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 80),
                        child: FilledButton.icon(
                          style: FilledButton.styleFrom(backgroundColor: AppColors.navy, minimumSize: const Size(0, 46), padding: const EdgeInsets.symmetric(horizontal: 24)),
                          onPressed: _retry,
                          icon: const Icon(Icons.refresh_rounded, size: 18),
                          label: const Text('Try again'),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}
