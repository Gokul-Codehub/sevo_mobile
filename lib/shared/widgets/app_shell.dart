import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lottie/lottie.dart';

import '../../features/ai_assistant/presentation/widgets/ai_chat_sheet.dart';
import '../../features/auth/domain/auth_notifier.dart';
import '../../features/booking/domain/cart_notifier.dart';
import '../../routing/app_router.dart';
import '../providers/bottom_nav_visibility_provider.dart';
import '../theme/app_colors.dart';
import 'motion.dart';

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
      // from 'AI Mitra' to 'Ask AI'").
      label: 'Ask AI',
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
  /// Navigator colour (bar fill + outline).
  static const _navy = Color(0xFF0B2337);

  /// Navigator palette. Light theme: white bar, navy active pill. Dark theme
  /// (kept for when dark mode ships): navy bar, white active pill.
  _NavPalette get _pal => Theme.of(context).brightness == Brightness.dark
      ? const _NavPalette(
          bar: _navy,
          ring: Color(0xFF1F3B54),
          pill: Colors.white,
          onPill: _navy,
          idle: Color(0xFF9FB3C8),
          outline: _navy,
        )
      : const _NavPalette(
          bar: Colors.white,
          ring: Color(0xFFE3E8EE),
          pill: _navy,
          onPill: Colors.white,
          idle: Color(0xFF8A97A6),
          outline: Colors.white,
        );

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
      ..showSnackBar(
        const SnackBar(
          content: Text('Press back again to exit'),
          duration: _exitPromptWindow,
          behavior: SnackBarBehavior.floating,
          margin: EdgeInsets.only(bottom: 72, left: 16, right: 16),
        ),
      );
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final currentIndex = _currentIndex(context);
    final isHomeTab = currentIndex == 0;
    final cartItems = ref.watch(cartProvider);
    final totalCartCount = cartItems.fold<int>(
      0,
      (sum, item) => sum + item.quantity,
    );
    // Added 2026-09-30 per explicit request ("In the Home page of both
    // Groceries and Services only the footer should show otherwise
    // hidden... make it smooth animation"): Home toggles this on its own
    // scroll direction (see home_screen.dart); every other tab ignores it
    // and always shows the nav bar, exactly as before.
    final navVisible = !isHomeTab || ref.watch(bottomNavVisibleProvider);
    // True only on the Home screen itself ('/'). _currentIndex() falls back to
    // 0 for every pushed page (categories, product / service detail, booking
    // flow ...), so isHomeTab can't be used to tell them apart.
    final onHomeScreen = GoRouterState.of(context).uri.path == AppRoutes.home;
    // Only the Home screen itself (whose nav bar hides on scroll) lets content
    // run behind the floating pill. Every other screen — including the pages
    // opened from Home (categories, products, recipes …) — is laid out ABOVE
    // the pill, so the last row of a list and its Add buttons can always be
    // scrolled clear of the footer.

    return PopScope(
      // Only Home is this shell's root with nowhere left to pop to, so
      // only Home needs the double-back-to-exit interception; every other
      // tab keeps its normal back behavior (e.g. popping a pushed detail
      // screen) untouched.
      // Updated 2026-10-14: other tabs reached with `context.go` (bottom bar,
      // Profile links) have nothing left to pop, so the system back used to
      // close the app. They now fall back to Home first; Home keeps the
      // double-back-to-exit. Pushed detail screens still pop normally
      // because their own navigator handles back before this one.
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (!isHomeTab) {
          context.go(AppRoutes.home);
          return;
        }
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
        // Home: page content runs behind the floating pill (no blank band
        // while scrolling, and the pill hides/shows without a layout jump).
        // Page content paints behind the floating pill; scroll views add the nav inset as bottom padding.
        extendBody: onHomeScreen,
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
                            child: ValueListenableBuilder<bool>(
                              valueListenable: aiChatOpen,
                              builder: (context, aiOpen, _) {
                                final aiIndex = AppShell._tabs
                                    .indexWhere((t) => t.isAiTab);
                                return _buildNavBar(
                                  context,
                                  aiOpen && aiIndex >= 0 ? aiIndex : currentIndex,
                                  totalCartCount,
                                );
                              },
                            ),
                          ),
                        ),
                      ),
              ),
      ),
    );
  }

  /// Floating pill navigator: a white bar with a double golden ring, grey
  /// outline icons, and a black pill that slides to the active tab and shows
  /// its icon + label (the other tabs stay icon-only).
  Widget _buildNavBar(BuildContext context, int currentIndex, int cartCount) {
    const tabs = AppShell._tabs;
    const barPad = 8.0;
    const duration = Duration(milliseconds: 320);
    const curve = Curves.easeOutCubic;
    final user = ref.watch(currentUserProvider);

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: _pal.bar,
        borderRadius: BorderRadius.circular(40),
        border: Border.all(color: _pal.outline, width: 1.6),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 18,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Container(
        height: 54,
        padding: const EdgeInsets.symmetric(horizontal: barPad),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(36),
          border: Border.all(color: _pal.ring, width: 1),
        ),
        child: LayoutBuilder(
          builder: (context, c) {
            final w = c.maxWidth;
            final activeW = (w * 0.35).clamp(96.0, 128.0);
            final otherW = (w - activeW) / (tabs.length - 1);
            double left(int i) => i <= currentIndex
                ? i * otherW
                : i * otherW + (activeW - otherW);
            double widthOf(int i) => i == currentIndex ? activeW : otherW;

            return Stack(
              alignment: Alignment.centerLeft,
              children: [
                // The sliding black pill behind the active tab.
                AnimatedPositioned(
                  duration: duration,
                  curve: curve,
                  left: left(currentIndex),
                  top: 6,
                  bottom: 6,
                  width: activeW,
                  child: Container(
                    decoration: BoxDecoration(
                      color: _pal.pill,
                      borderRadius: BorderRadius.circular(30),
                    ),
                  ),
                ),
                for (int i = 0; i < tabs.length; i++)
                  AnimatedPositioned(
                    duration: duration,
                    curve: curve,
                    left: left(i),
                    top: 0,
                    bottom: 0,
                    width: widthOf(i),
                    child: _navItem(
                      context,
                      tabs[i],
                      i == currentIndex,
                      cartCount,
                      user?.profilePictureUrl,
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _navItem(
    BuildContext context,
    _TabItem tab,
    bool selected,
    int cartCount,
    String? avatarUrl,
  ) {
    final grey = _pal.idle;
    Widget icon;
    if (tab.isAiTab) {
      icon = SizedBox(
        width: 30,
        height: 30,
        child: ClipRect(
          child: Transform.scale(
            scale: 1.3,
            child: Lottie.asset(
              'assets/animations/ai_mitra_robot.json',
              fit: BoxFit.contain,
            ),
          ),
        ),
      );
    } else if (tab.route == AppRoutes.profile &&
        avatarUrl != null &&
        avatarUrl.isNotEmpty) {
      icon = Container(
        width: 28,
        height: 28,
        padding: const EdgeInsets.all(1.5),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: const Color(0xFFF2C14E), width: 1.6),
        ),
        child: ClipOval(
          child: Image.network(
            avatarUrl,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => Icon(
              Icons.person_outline_rounded,
              size: 18,
              color: selected ? _pal.onPill : grey,
            ),
          ),
        ),
      );
    } else {
      icon = Icon(
        selected ? tab.activeIcon : tab.icon,
        size: 22,
        color: selected ? _pal.onPill : grey,
      );
    }

    if (tab.isCartTab && cartCount > 0) {
      icon = Stack(
        clipBehavior: Clip.none,
        children: [
          icon,
          Positioned(
            top: -6,
            right: -8,
            child: BounceOnChange(
              value: cartCount,
              child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1.5),
              constraints: const BoxConstraints(minWidth: 15, minHeight: 15),
              decoration: BoxDecoration(
                color: AppColors.error,
                shape: BoxShape.circle,
                border: Border.all(
                  color: selected ? _pal.pill : _pal.bar,
                  width: 1.4,
                ),
              ),
              child: Center(
                child: Text(
                  '$cartCount',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                    height: 1.0,
                  ),
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
        // Home tab tapped while already on Home: let Home scroll to top / reload.
        if (tab.route == AppRoutes.home &&
            GoRouterState.of(context).uri.path == AppRoutes.home) {
          ref.read(homeTabTapProvider.notifier).state++;
          return;
        }
        context.go(tab.route);
      },
      child: Center(
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              icon,
              // The label only exists on the active tab; it fades in as the
              // black pill arrives.
              AnimatedSize(
                duration: const Duration(milliseconds: 260),
                curve: Curves.easeOutCubic,
                child: selected
                    ? Padding(
                        padding: const EdgeInsets.only(left: 7),
                        child: Text(
                          tab.label,
                          maxLines: 1,
                          style: TextStyle(
                            color: _pal.onPill,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
            ],
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

class _NavPalette {
  const _NavPalette({
    required this.bar,
    required this.ring,
    required this.pill,
    required this.onPill,
    required this.idle,
    required this.outline,
  });

  final Color bar, ring, pill, onPill, idle, outline;
}
