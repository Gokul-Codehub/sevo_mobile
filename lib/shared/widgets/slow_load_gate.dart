import 'dart:async';

import 'package:flutter/material.dart';

import 'branded_loading_screen.dart';

/// Escalates a screen's normal loading UI to the full-screen
/// [BrandedLoadingScreen] once a load has been running longer than
/// [slowThreshold] — otherwise stays on the caller's own skeleton the
/// entire time.
///
/// Added 2026-09-30 per explicit request ("For entire page redirection
/// during the loading of data show a splash screen like uploaded image..
/// Note only for more delay/large loading otherwise use skeleton
/// loading"): drop this into any `.when(loading: () => ...)` branch (or
/// anywhere else a screen currently shows a skeleton/shimmer while an
/// initial fetch is in flight) in place of the bare skeleton widget —
/// most loads finish well under [slowThreshold] and this never shows
/// anything but the skeleton passed in; only a genuinely slow/large fetch
/// ever reaches the branded screen. See [ServiceDetailScreen] for the
/// first wired-up example — the same pattern applies to any other
/// screen's initial-load skeleton.
class SlowLoadGate extends StatefulWidget {
  const SlowLoadGate({
    super.key,
    required this.skeleton,
    this.slowThreshold = const Duration(seconds: 3),
    this.tagline,
  });

  /// The screen's own normal loading UI (a shimmer/skeleton widget),
  /// shown immediately and for as long as the load stays under
  /// [slowThreshold].
  final Widget skeleton;

  /// How long a load must run before this swaps to [BrandedLoadingScreen].
  /// Deliberately generous — this is an escalation for an unusually slow
  /// load, not a replacement for the skeleton on an ordinary one.
  final Duration slowThreshold;

  /// Optional contextual tagline passed through to [BrandedLoadingScreen].
  final String? tagline;

  @override
  State<SlowLoadGate> createState() => _SlowLoadGateState();
}

class _SlowLoadGateState extends State<SlowLoadGate> {
  bool _isSlow = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer(widget.slowThreshold, () {
      if (mounted) setState(() => _isSlow = true);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      child: _isSlow
          ? BrandedLoadingScreen(
              key: const ValueKey('slow'),
              tagline: widget.tagline ?? 'Good things, on the way',
            )
          : KeyedSubtree(
              key: const ValueKey('skeleton'),
              child: widget.skeleton,
            ),
    );
  }
}
