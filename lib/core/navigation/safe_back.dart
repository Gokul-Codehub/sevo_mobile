import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

/// Linear "previous page" navigation used by every back arrow in the app.
///
/// Screens opened with `context.push` simply pop. When a screen was reached
/// with `context.go` (bottom-bar tabs, deep links, notification taps) there is
/// no history to pop — `context.pop()` would throw — so we fall back to Home
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
