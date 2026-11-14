import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/services/connectivity_service.dart';

/// Mounted once above the entire routed app (see main.dart's `MaterialApp.router(builder: ...)`).
///
/// When the device goes offline a slim banner slides in at the top and everything underneath stays usable: pages the
/// customer already loaded stay readable, and only actions that need the network fail (with their own friendly message).
/// It used to cover the whole app with a full-screen "No internet" page. The banner disappears by itself when the
/// connection returns.
///
/// It does not show on the very first frame: while the initial connectivity check is in flight the app is shown as-is,
/// so a cold start never flashes a false "offline" state.
class ConnectivityGate extends ConsumerWidget {
  const ConnectivityGate({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(connectivityStatusProvider);
    final isOffline = status.valueOrNull == false;

    return Stack(
      children: [
        child,
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: IgnorePointer(
            ignoring: !isOffline,
            child: AnimatedSlide(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOut,
              offset: isOffline ? Offset.zero : const Offset(0, -1),
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 180),
                opacity: isOffline ? 1 : 0,
                child: Material(
                  color: const Color(0xFF334155),
                  child: SafeArea(
                    bottom: false,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      child: Row(
                        children: const [
                          Icon(Icons.wifi_off_rounded, size: 16, color: Colors.white),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              "You're offline. Showing what you've already loaded; actions that need the internet will retry when you're back.",
                              style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600, height: 1.25),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
