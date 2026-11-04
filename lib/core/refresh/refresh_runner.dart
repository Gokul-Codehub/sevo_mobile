import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../shared/utils/app_toast.dart';

/// One place for "pull to refresh" behaviour, so every screen behaves the same way:
///
/// * The jobs run IN PARALLEL and the pull spinner ends when they all finish OR after [limit]
///   (8 s by default), whichever comes first - a slow request never keeps the spinner up for a minute.
///   Jobs that are still running carry on in the background and update the screen when they land.
/// * Nothing is cleared first: the screen keeps showing the last data while it refreshes.
/// * If something failed or was too slow, the customer is told ("showing your last data") instead of the
///   refresh silently doing nothing.
class RefreshRunner {
  const RefreshRunner._();

  static const Duration defaultLimit = Duration(seconds: 8);
  static const String failedMessage = "Couldn't refresh fully. Showing your last data.";

  /// Returns true when every job finished successfully inside [limit].
  static Future<bool> run(
    BuildContext context,
    List<Future<void> Function()> jobs, {
    Duration limit = defaultLimit,
    bool quiet = false,
  }) async {
    var failed = false;
    var timedOut = false;
    final running = [
      for (final job in jobs)
        () async {
          try {
            await job();
          } catch (_) {
            failed = true;
          }
        }(),
    ];
    try {
      await Future.wait(running).timeout(limit);
    } on TimeoutException {
      timedOut = true;
    }
    final ok = !failed && !timedOut;
    if (!ok && !quiet && context.mounted) {
      AppToast.show(context, failedMessage, type: AppToastType.info);
    }
    return ok;
  }
}

/// Calls [onStale] when the app comes back to the foreground after at least [after] in the background
/// (the way shopping and delivery apps reload on return, but not on every quick app switch).
class ResumeRefresh with WidgetsBindingObserver {
  ResumeRefresh({required this.onStale, this.after = const Duration(minutes: 5), DateTime Function()? clock})
      : _now = clock ?? DateTime.now;

  final void Function() onStale;
  final Duration after;
  final DateTime Function() _now;
  DateTime? _pausedAt;

  void attach() => WidgetsBinding.instance.addObserver(this);
  void detach() => WidgetsBinding.instance.removeObserver(this);

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden) {
      _pausedAt ??= _now();
    } else if (state == AppLifecycleState.resumed) {
      final since = _pausedAt;
      _pausedAt = null;
      if (since != null && _now().difference(since) >= after) onStale();
    }
  }
}
