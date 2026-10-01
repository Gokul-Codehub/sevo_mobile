import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/services/connectivity_service.dart';
import 'no_internet_screen.dart';

/// Mounted once above the entire routed app (see main.dart's
/// `MaterialApp.router(builder: ...)`), alongside [BookingNotificationWatcher].
///
/// Watches [connectivityStatusProvider] and, the instant the device goes
/// offline, overlays [NoInternetScreen] on top of whatever the customer was
/// looking at — no navigation, no route change, nothing pushed onto the
/// back stack to pop. The moment connectivity returns, the overlay is
/// removed automatically and the customer is exactly where they left off.
///
/// Deliberately does not block on the very first frame: while the initial
/// connectivity check is still in flight (`AsyncLoading`), the real app is
/// shown as-is rather than flashing a false "offline" state on cold start.
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
        if (isOffline)
          const Positioned.fill(
            child: NoInternetScreen(),
          ),
      ],
    );
  }
}
