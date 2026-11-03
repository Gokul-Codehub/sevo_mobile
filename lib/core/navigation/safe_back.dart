import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

/// Linear "previous page" navigation used by every back arrow in the app.
///
/// Screens opened with `context.push` simply pop. When a screen was reached
/// with `context.go` (a deep link, a notification tap, the end of a booking) there is
/// no history to pop - `context.pop()` would throw - so we fall back to Home
/// instead of leaving the user stranded or closing the app.
extension SafeBack on BuildContext {
  void goBack() {
    if (canPop()) {
      pop();
    } else {
      go('/');
    }
  }
}

/// The four bottom-bar destinations (see `AppShell`). Kept here, not in the shell, so any screen can use [openTab].
const Set<String> kTabRoots = {'/', '/bookings', '/cart', '/profile'};

/// Moving between the bottom-bar tabs and "view cart" style shortcuts, without losing where the customer has been.
///
/// `context.go(tab)` REPLACES the whole stack, so after Home > Category > Service > Cart the back button could
/// not retrace the path; it dropped the customer on Home. This keeps the history the way they built it:
///  * from a screen that is deeper than a tab (a category, a service, a product ...) the tab is PUSHED on top, so
///    back returns to exactly that screen, then the one before it, and so on;
///  * from a tab's own page the new tab REPLACES it, so hopping Home > Bookings > Profile > Cart does not pile up
///    pages, and back from the last one still has one clear answer (the page underneath, or Home when there is none).
extension TabNavigation on BuildContext {
  void openTab(String route, {bool replace = false}) {
    final router = GoRouter.of(this);
    String here;
    try {
      here = GoRouterState.of(this).uri.path;
    } catch (_) {
      here = router.routerDelegate.currentConfiguration.uri.path;
    }
    if (here == route) return;
    try {
      if (replace || kTabRoots.contains(here)) {
        router.pushReplacement(route);
      } else {
        router.push(route);
      }
    } catch (_) {
      // A push from outside the shell cannot reach a shell route (go_router 14): fall back to a plain jump.
      router.go(route);
    }
  }
}
