import '../../core/navigation/safe_back.dart';
import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../features/ai_assistant/presentation/widgets/ai_chat_sheet.dart';
import '../../core/services/customer_live_updates.dart';
import '../../features/auth/domain/auth_notifier.dart';
import '../../features/booking/domain/cart_notifier.dart';
import '../../routing/app_router.dart';
import '../layout/responsive.dart';
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
  static const _navy = AppColors.swatch0B2337;

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
          ring: AppColors.swatchE3E8EE,
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

    // Pages that are not a tab themselves (Notification settings, Your devices, saved addresses, payments, categories,
    // product pages ...) keep the tab the customer came from highlighted instead of jumping to Home.
    final strict = appShellStrictTabIndex(location);
    if (strict != null) {
      _lastTabIndex = strict;
      return strict;
    }
    return _lastTabIndex;
  }

  /// The tab that was active the last time the location was one of the tab roots.
  int _lastTabIndex = 0;

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
    // Live order/booking updates over WebSocket while a customer is signed in (polling stays as fallback).
    ref.watch(customerLiveUpdatesProvider);
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
            // heightFactor + opacity tuck the bar down in one motion (no
            // hard size snap / desynced fade).
            : TweenAnimationBuilder<double>(
                tween: Tween<double>(end: navVisible ? 1.0 : 0.0),
                duration: const Duration(milliseconds: 320),
                curve: navVisible
                    ? Curves.easeOutCubic
                    : Curves.easeInCubic,
                builder: (context, t, child) {
                  final v = t.clamp(0.0, 1.0);
                  return ClipRect(
                    child: Align(
                      alignment: Alignment.topCenter,
                      heightFactor: v,
                      child: Opacity(
                        opacity: v,
                        child: Transform.translate(
                          offset: Offset(0, (1 - v) * 18),
                          child: IgnorePointer(
                            ignoring: v < 0.05,
                            child: child,
                          ),
                        ),
                      ),
                    ),
                  );
                },
                child: SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                    child: AdaptiveWidth(
                      maxWidth: AppResponsive.navMaxWidth(context),
                      alignment: Alignment.bottomCenter,
                      // The nav sits in Scaffold.bottomNavigationBar, which allows
                      // the full screen height; keep the bar's own 60px height.
                      fillHeight: false,
                      child: ValueListenableBuilder<bool>(
                        valueListenable: aiChatOpen,
                        builder: (context, aiOpen, _) {
                          final aiIndex =
                              AppShell._tabs.indexWhere((t) => t.isAiTab);
                          return _buildNavBar(
                            context,
                            aiOpen && aiIndex >= 0
                                ? aiIndex
                                : currentIndex,
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

  /// Floating nav: expanding active pill (icon + label) with smooth slide.
  Widget _buildNavBar(BuildContext context, int currentIndex, int cartCount) {
    const tabs = AppShell._tabs;
    const barPad = 6.0;
    const duration = Duration(milliseconds: 300);
    const curve = Curves.easeOutCubic;
    final user = ref.watch(currentUserProvider);

    return Container(
      height: 60,
      padding: const EdgeInsets.symmetric(horizontal: barPad),
      decoration: BoxDecoration(
        color: _pal.bar,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: const Color(0xFFE2E8F0), width: 1),
        boxShadow: [
          BoxShadow(
            color: AppColors.navy.withValues(alpha: 0.10),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: LayoutBuilder(
        builder: (context, c) {
          final w = c.maxWidth;
          final activeW = (w * 0.32).clamp(92.0, 118.0);
          final otherW = (w - activeW) / (tabs.length - 1);
          double left(int i) =>
              i <= currentIndex ? i * otherW : i * otherW + (activeW - otherW);
          double widthOf(int i) => i == currentIndex ? activeW : otherW;

          return Stack(
            alignment: Alignment.centerLeft,
            children: [
              AnimatedPositioned(
                duration: duration,
                curve: curve,
                left: left(currentIndex),
                top: 7,
                bottom: 7,
                width: activeW,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: _pal.pill,
                    borderRadius: BorderRadius.circular(22),
                    boxShadow: [
                      BoxShadow(
                        color: _pal.pill.withValues(alpha: 0.28),
                        blurRadius: 10,
                        offset: const Offset(0, 3),
                      ),
                    ],
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
    );
  }

  Widget _navItem(
    BuildContext context,
    _TabItem tab,
    bool selected,
    int cartCount,
    String? avatarUrl,
  ) {
    final idle = _pal.idle;
    final on = selected ? _pal.onPill : idle;

    Widget icon;
    if (tab.isAiTab) {
      // The AI Mitra robot animation instead of the sparkle glyph (falls back to the sparkle if it cannot load).
      icon = SizedBox(
        width: 30,
        height: 30,
        child: ClipRect(
          child: Transform.scale(
            scale: 1.3,
            child: Lottie.asset(
              'assets/animations/ai_mitra_robot.json',
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => Icon(
                selected ? Icons.auto_awesome_rounded : Icons.auto_awesome_outlined,
                size: 22,
                color: on,
              ),
            ),
          ),
        ),
      );
    } else if (tab.route == AppRoutes.profile &&
        avatarUrl != null &&
        avatarUrl.isNotEmpty) {
      icon = Container(
        width: 24,
        height: 24,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: selected ? _pal.onPill.withValues(alpha: 0.85) : const Color(0xFFCBD5E1),
            width: 1.4,
          ),
        ),
        child: ClipOval(
          child: Image.network(
            avatarUrl,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => Icon(
              Icons.person_outline_rounded,
              size: 16,
              color: on,
            ),
          ),
        ),
      );
    } else {
      icon = Icon(
        selected ? tab.activeIcon : tab.icon,
        size: 22,
        color: on,
      );
    }

    if (tab.isCartTab && cartCount > 0) {
      icon = Stack(
        clipBehavior: Clip.none,
        children: [
          icon,
          Positioned(
            top: -5,
            right: -7,
            child: BounceOnChange(
              value: cartCount,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                constraints: const BoxConstraints(minWidth: 15, minHeight: 15),
                decoration: BoxDecoration(
                  color: AppColors.error,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: selected ? _pal.pill : _pal.bar,
                    width: 1.5,
                  ),
                ),
                child: Text(
                  cartCount > 99 ? '99+' : '$cartCount',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                    height: 1.1,
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
        if (tab.route == AppRoutes.home &&
            GoRouterState.of(context).uri.path == AppRoutes.home) {
          ref.read(homeTabTapProvider.notifier).state++;
          return;
        }
        context.openTab(tab.route);
      },
      child: Center(
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              BounceOnChange(
                value: selected,
                child: AnimatedScale(
                  scale: selected ? 1.05 : 1.0,
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeOutCubic,
                  child: icon,
                ),
              ),
              AnimatedSize(
                duration: const Duration(milliseconds: 240),
                curve: Curves.easeOutCubic,
                child: selected
                    ? Padding(
                        padding: const EdgeInsets.only(left: 6),
                        child: Text(
                          tab.label,
                          maxLines: 1,
                          style: TextStyle(
                            color: _pal.onPill,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.2,
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

/// Which bottom-bar tab a route belongs to. Pages that open from a tab without being a tab themselves count as part
/// of it - a grocery order (and its return page) belongs to Bookings. Anything unknown falls back to Home.
@visibleForTesting
int appShellTabIndexForLocation(String location) => appShellStrictTabIndex(location) ?? 0;

/// The tab a location belongs to, or null when it is a pushed page that is not part of any tab.
int? appShellStrictTabIndex(String location) {
  if (location == AppRoutes.groceryOrders || location.startsWith('${AppRoutes.groceryOrders}/')) {
    return AppShell._tabs.indexWhere((t) => t.route == AppRoutes.myBookings);
  }
  for (int i = 0; i < AppShell._tabs.length; i++) {
    final tab = AppShell._tabs[i];
    if (tab.isAiTab) continue;
    if (location == tab.route || (i > 0 && location.startsWith(tab.route))) {
      return i;
    }
  }
  return null;
}
