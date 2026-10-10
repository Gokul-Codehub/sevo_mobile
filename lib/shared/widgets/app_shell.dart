import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lottie/lottie.dart';

import '../../features/ai_assistant/presentation/widgets/ai_chat_sheet.dart';
import '../../features/booking/domain/cart_notifier.dart';
import '../../routing/app_router.dart';
import '../providers/bottom_nav_visibility_provider.dart';
import '../theme/app_colors.dart';

/// Main app shell with bottom navigation bar.
/// Wraps all primary tab destinations including dynamic Cart counter.
class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key, required this.child});

  final Widget child;

  static const _tabs = [
    _TabItem(
      label: 'Home',
      icon: Icons.home_outlined,
      activeIcon: Icons.home_rounded,
      route: AppRoutes.home,
    ),
    _TabItem(
      label: 'Bookings',
      icon: Icons.calendar_today_outlined,
      activeIcon: Icons.calendar_today_rounded,
      route: AppRoutes.myBookings,
    ),
    _TabItem(
      label: 'Cart',
      icon: Icons.shopping_cart_outlined,
      activeIcon: Icons.shopping_cart_rounded,
      route: AppRoutes.cart,
      isCartTab: true,
    ),
    // Changed 2026-09-30 per explicit request ("remove Support in there
    // replace AI module"): this tab no longer navigates anywhere — see
    // isAiTab handling below, which opens the AI chat sheet instead of
    // `context.go`. `route` is kept pointing at the old Support screen
    // only so `_currentIndex` never mis-highlights this tab as active for
    // an unrelated path; it is otherwise unused for this tab.
    _TabItem(
      // Renamed 2026-10-08 per explicit request ("Change the AI bot name
      // from 'AI Mitra' to 'Ask Apta'").
      label: 'Ask Apta',
      icon: Icons.auto_awesome_outlined,
      activeIcon: Icons.auto_awesome_rounded,
      route: AppRoutes.support,
      isAiTab: true,
    ),
    _TabItem(
      label: 'Profile',
      icon: Icons.person_outline_rounded,
      activeIcon: Icons.person_rounded,
      route: AppRoutes.profile,
    ),
  ];

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  // Fixed 2026-09-17 per explicit request ("The app should be closed using
  // back button/gesture from home page with double click back or double
  // back swipe... like Flipkart"): tracks the timestamp of the last back
  // press while on the Home tab so a second press within the window below
  // actually exits, instead of either exiting on the very first press
  // (jarring — a single accidental back-swipe would kill the app) or doing
  // nothing at all (the previous behavior, since Home is this shell's root
  // route with nothing to pop).
  DateTime? _lastHomeBackPressAt;
  static const _exitPromptWindow = Duration(seconds: 2);

  int _currentIndex(BuildContext context) {
    final location = GoRouterState.of(context).uri.path;

    // Fixed 2026-10-01: the AI Mitra tab's `route` is a leftover dummy value
    // (AppRoutes.support — see its doc comment above) since it no longer
    // navigates anywhere; it was never meant to be matched below. But
    // Profile's "Help & Customer Care" tile still does
    // `context.go('/support')` for the real Help & Support screen, and that
    // path happens to equal this dummy route exactly — so the loop below
    // used to match AI Mitra's entry first and highlight that tab instead,
    // even though tapping it does something completely different (opens the
    // chat sheet). Help & Support is only ever reached from Profile and
    // isn't a tab destination in its own right, so treat it as part of the
    // Profile tab for highlighting purposes.
    if (location == AppRoutes.support) {
      return AppShell._tabs.indexWhere((t) => t.route == AppRoutes.profile);
    }

    for (int i = 0; i < AppShell._tabs.length; i++) {
      final tab = AppShell._tabs[i];
      if (tab.isAiTab) continue;
      if (location == tab.route || (i > 0 && location.startsWith(tab.route))) {
        return i;
      }
    }
    return 0;
  }

  /// Returns true once the second back press lands inside the window,
  /// showing a "press back again to exit" prompt on the first press.
  bool _handleHomeBackPress() {
    final now = DateTime.now();
    final last = _lastHomeBackPressAt;
    if (last != null && now.difference(last) <= _exitPromptWindow) {
      return true;
    }
    _lastHomeBackPressAt = now;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(const SnackBar(
        content: Text('Press back again to exit'),
        duration: _exitPromptWindow,
        behavior: SnackBarBehavior.floating,
        margin: EdgeInsets.only(bottom: 72, left: 16, right: 16),
      ));
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final currentIndex = _currentIndex(context);
    final isHomeTab = currentIndex == 0;
    final cartItems = ref.watch(cartProvider);
    final totalCartCount =
        cartItems.fold<int>(0, (sum, item) => sum + item.quantity);
    // Added 2026-09-30 per explicit request ("In the Home page of both
    // Groceries and Services only the footer should show otherwise
    // hidden... make it smooth animation"): Home toggles this on its own
    // scroll direction (see home_screen.dart); every other tab ignores it
    // and always shows the nav bar, exactly as before.
    final navVisible = !isHomeTab || ref.watch(bottomNavVisibleProvider);

    return PopScope(
      // Only Home is this shell's root with nowhere left to pop to, so
      // only Home needs the double-back-to-exit interception; every other
      // tab keeps its normal back behavior (e.g. popping a pushed detail
      // screen) untouched.
      canPop: !isHomeTab,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop || !isHomeTab) return;
        if (_handleHomeBackPress()) {
          SystemNavigator.pop();
        }
      },
      child: Scaffold(
        // Explicitly disable the FAB geometry animation on this persistent
        // shell Scaffold. With go_router's ShellRoute nesting nearly every
        // screen inside this single Scaffold, rapid route pushes/pops (or a
        // rebuild from cartProvider changing the nav-bar badge) can land in
        // the same frame as the framework's own FAB transition animation,
        // which then tries to hit-test/lay out a RenderObject that has
        // already been disposed — surfacing as "RenderBox was not laid out"
        // / "Cannot hit test a render box that has never been laid out"
        // under _FloatingActionButtonTransition. This app never uses a FAB
        // here, so removing the animation removes the race entirely.
        floatingActionButtonAnimator: FloatingActionButtonAnimator.noAnimation,
        body: widget.child,
        bottomNavigationBar: MediaQuery.of(context).viewInsets.bottom > 0
            ? const SizedBox.shrink()
            : AnimatedSize(
                duration: const Duration(milliseconds: 260),
                curve: Curves.easeInOut,
                alignment: Alignment.bottomCenter,
                child: !navVisible
                    ? const SizedBox(width: double.infinity, height: 0)
                    : AnimatedOpacity(
                        duration: const Duration(milliseconds: 200),
                        opacity: navVisible ? 1 : 0,
                        child: SafeArea(
                          top: false,
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                            child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(36),
                      border: Border.all(color: const Color(0xFFF1F5F9), width: 1.0),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.08),
                          blurRadius: 18,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: List.generate(AppShell._tabs.length, (index) {
                        final tab = AppShell._tabs[index];
                        final isSelected = currentIndex == index;

                        // Added 2026-10-08 per explicit request ("replace
                        // this into the footer/navigator for AI Mitra"):
                        // the AI Mitra tab now renders an animated robot
                        // (assets/animations/ai_mitra_robot.json, supplied
                        // by Divya) instead of the static Icons.auto_awesome
                        // glyph every other state used. Lottie bakes its own
                        // colors into the animation, so unlike the plain
                        // Icon below this can't be recolored per
                        // selected/unselected state -- the surrounding
                        // AnimatedContainer's highlight pill background
                        // still shows which tab is active.
                        // Fixed 2026-10-08 ("still improper alignment"):
                        // the AI Mitra tab's icon slot (34x34, for the
                        // Lottie animation below) was a different size from
                        // every other tab's bare 24px Icon -- Row's default
                        // crossAxisAlignment.center then centered each
                        // tab's whole icon+label Column against the ROW's
                        // tallest column (AI Mitra's), so the other four
                        // tabs' icons and labels sat at a different
                        // vertical offset than AI Mitra's, reading as
                        // misaligned even though each one was internally
                        // centered. Every tab's icon now sits inside the
                        // exact same 34x34 slot (centered), so all 5
                        // columns are the same height and align on the Row.
                        const iconSlotSize = 34.0;
                        Widget iconWidget = SizedBox(
                          width: iconSlotSize,
                          height: iconSlotSize,
                          child: Center(
                            child: tab.isAiTab
                                ? ClipRect(
                                    // See the "white space around it" fix
                                    // below: the source animation
                                    // (assets/animations/ai_mitra_robot.json,
                                    // supplied by Divya) only ever occupies
                                    // the middle ~43%-76% of its own
                                    // 700x700 canvas, verified by rendering
                                    // it frame-by-frame and measuring the
                                    // actual drawn content -- the rest is
                                    // permanent transparent padding baked
                                    // into the file, which BoxFit.contain
                                    // alone can't crop since it just fits
                                    // the whole canvas (padding included)
                                    // into the box. Transform.scale zooms
                                    // in 1.3x on the canvas to crop most of
                                    // that padding away; ClipRect keeps the
                                    // zoomed-in edges from spilling outside
                                    // this slot. 1.3x was chosen so the
                                    // single largest moment in the whole
                                    // animation (a ~535px-tall burst at its
                                    // widest, measured the same way) still
                                    // stays just inside the slot instead of
                                    // getting clipped.
                                    child: Transform.scale(
                                      scale: 1.3,
                                      child: Lottie.asset(
                                        'assets/animations/ai_mitra_robot.json',
                                        fit: BoxFit.contain,
                                        repeat: true,
                                      ),
                                    ),
                                  )
                                : Icon(
                                    isSelected ? tab.activeIcon : tab.icon,
                                    size: 24,
                                    color: isSelected
                                        ? AppColors.primary
                                        : const Color(0xFF334155),
                                  ),
                          ),
                        );

                        if (tab.isCartTab && totalCartCount > 0) {
                          iconWidget = Stack(
                            clipBehavior: Clip.none,
                            children: [
                              iconWidget,
                              Positioned(
                                top: -4,
                                right: -8,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 4,
                                    vertical: 2,
                                  ),
                                  constraints: const BoxConstraints(
                                    minWidth: 16,
                                    minHeight: 16,
                                  ),
                                  decoration: BoxDecoration(
                                    color: AppColors.error,
                                    shape: BoxShape.circle,
                                    border: Border.all(color: Colors.white, width: 1.5),
                                  ),
                                  child: Center(
                                    child: Text(
                                      '$totalCartCount',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 9.5,
                                        fontWeight: FontWeight.w800,
                                        height: 1.0,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          );
                        }

                        return GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () {
                            HapticFeedback.selectionClick();
                            if (tab.isAiTab) {
                              showAiChatSheet(context);
                              return;
                            }
                            context.go(tab.route);
                          },
                          // Smoothed 2026-10-08 ("make the footer/navigator
                          // activate transition smoother"): the highlight
                          // pill's own fade/resize was already animated, but
                          // the label underneath switched its color and
                          // font-weight INSTANTLY the moment a tab became
                          // selected -- that abrupt snap right next to a
                          // smoothly-fading pill is what actually read as
                          // "not smooth". Swapping the plain Text for
                          // AnimatedDefaultTextStyle (same duration/curve as
                          // the pill) lets the label cross-fade into its
                          // selected color/weight instead of jumping, and a
                          // slightly longer duration + a gentler
                          // decelerating curve makes the whole tap feel less
                          // like a toggle switch and more like a transition.
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 280),
                            curve: Curves.easeOutCubic,
                            padding: EdgeInsets.symmetric(
                              horizontal: isSelected ? 16 : 10,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? AppColors.primaryLight
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(24),
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                iconWidget,
                                const SizedBox(height: 3),
                                AnimatedDefaultTextStyle(
                                  duration: const Duration(milliseconds: 280),
                                  curve: Curves.easeOutCubic,
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: isSelected
                                        ? FontWeight.w700
                                        : FontWeight.w600,
                                    color: isSelected
                                        ? AppColors.primary
                                        : AppColors.textSecondary,
                                  ),
                                  child: Text(tab.label),
                                ),
                              ],
                            ),
                          ),
                        );
                      }),
                    ),
                  ),
                ),
                        ),
                      ),
              ),
      ),
    );
  }
}

class _TabItem {
  const _TabItem({
    required this.label,
    required this.icon,
    required this.activeIcon,
    required this.route,
    this.isCartTab = false,
    this.isAiTab = false,
  });

  final String label;
  final IconData icon;
  final IconData activeIcon;
  final String route;
  final bool isCartTab;

  /// True for the "AI Assistant" tab — see its `_tabs` doc comment above.
  final bool isAiTab;
}

