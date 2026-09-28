import 'package:flutter/material.dart';

/// Wraps the whole app so any screen can force a full app reload — every
/// provider, every cached value, every route reset back to a cold start —
/// without actually killing and relaunching the OS process.
///
/// Added 2026-09-19 per explicit request ("In at home page only if user
/// swipe down make it reload the entire applicaiton...once"): Home's
/// pull-to-refresh calls [RestartWidget.restartApp] instead of just
/// re-fetching its own data, which is what a plain `RefreshIndicator` would
/// otherwise do. This is deliberately app-wide (not scoped to Home's own
/// providers) because "reload the entire application" was explicit and
/// literal — everything remounts from `main.dart`'s `ProviderScope` down,
/// exactly like a cold start, the next time it's needed elsewhere too.
///
/// How it works: giving a subtree a new `Key` tells Flutter to discard the
/// old Element/State tree and build a brand new one — there is no built-in
/// "restart" API in Flutter/Riverpod, so changing the key on the widget
/// wrapping [ProviderScope] is the standard, dependency-free way to get
/// one. See `main.dart` for where this wraps `ProviderScope`.
class RestartWidget extends StatefulWidget {
  const RestartWidget({super.key, required this.child});

  final Widget child;

  /// Call from anywhere under this widget (e.g. a `RefreshIndicator`'s
  /// `onRefresh`) to trigger the full reload.
  static void restartApp(BuildContext context) {
    context.findAncestorStateOfType<_RestartWidgetState>()?._restart();
  }

  @override
  State<RestartWidget> createState() => _RestartWidgetState();
}

class _RestartWidgetState extends State<RestartWidget> {
  Key _key = UniqueKey();

  void _restart() {
    setState(() {
      _key = UniqueKey();
    });
  }

  @override
  Widget build(BuildContext context) {
    return KeyedSubtree(
      key: _key,
      child: widget.child,
    );
  }
}
