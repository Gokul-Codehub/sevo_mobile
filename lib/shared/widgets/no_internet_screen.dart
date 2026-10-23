import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/services/connectivity_service.dart';
import 'status_page.dart';

/// Full-screen "You're Offline" state.
///
/// Shown automatically by [ConnectivityGate] the instant the device's
/// network link drops, over whatever screen the customer was already on,
/// and dismissed automatically the instant it's restored — this screen is
/// never pushed/popped and is intentionally NOT registered in
/// app_router.dart; it is a transient overlay, not a route.
class NoInternetScreen extends ConsumerWidget {
  const NoInternetScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return StatusScreen(
      page: StatusPage(
        kind: StatusKind.noInternet,
        title: 'No internet connection',
        message: 'Please check your network',
        actionLabel: 'Try again',
        // The stream already re-emits on its own the moment connectivity
        // changes - this forces an immediate re-check so a manual tap gives
        // instant feedback.
        onAction: () => ref.invalidate(connectivityStatusProvider),
      ),
    );
  }
}
