import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../addresses/domain/address_notifier.dart';
import '../../auth/domain/auth_notifier.dart' show authLoadingProvider;
import '../../booking/domain/cart_notifier.dart' show isUserAuthenticatedProvider;
import '../../catalog/data/marketplace_catalog_repository.dart' show deliveryPointProvider;
import '../../home/domain/home_flow_mode.dart';
import '../domain/coverage.dart';
import '../domain/location_settle.dart';
import 'not_served_view.dart';

/// Blinkit / Flipkart-style access rule for the whole app (wraps the bottom-nav shell, so every tab and every page
/// opened from it, including deep links and notification taps):
///  * the "where should we deliver?" page appears ONLY when it is a proven fact that there is no location: nothing
///    remembered on the phone, no saved address (the list has loaded and is empty or failed) and no GPS. Anything
///    still loading (the stored session, the address list, the pick of the last used address) shows a plain white
///    screen instead, never Home and never a wrong page;
///  * a safety cap (12 s) stops that wait from lasting forever on a dead network;
///  * if we are SURE neither groceries nor services is served at the location, the same page says so.
/// An unknown coverage answer (check still running, network down) never blocks.
class AppAccessGate extends ConsumerStatefulWidget {
  const AppAccessGate({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<AppAccessGate> createState() => _AppAccessGateState();
}

class _AppAccessGateState extends ConsumerState<AppAccessGate> {
  bool _capped = false;
  Timer? _cap;

  @override
  void initState() {
    super.initState();
    _cap = Timer(const Duration(seconds: 12), () {
      if (mounted) setState(() => _capped = true);
    });
  }

  @override
  void dispose() {
    _cap?.cancel();
    super.dispose();
  }

  /// True while something that could still produce a location is in flight.
  bool _stillResolving(WidgetRef ref) {
    if (!ref.watch(appLocationSettledProvider).hasValue) return true;
    if (ref.watch(authLoadingProvider)) return true;
    if (!ref.watch(isUserAuthenticatedProvider)) return false;
    final list = ref.watch(addressListProvider);
    if (list.isLoading) return true;
    // The list is in but the last used address has not been picked yet (it is read from storage a moment later).
    return list.hasValue && (list.value ?? const []).isNotEmpty;
  }

  @override
  Widget build(BuildContext context) {
    final point = ref.watch(deliveryPointProvider);
    if (point.label.isEmpty) {
      if (!_capped && _stillResolving(ref)) {
        return const Scaffold(backgroundColor: Colors.white, body: SizedBox.expand());
      }
      final mode = ref.watch(homeFlowModeProvider);
      return NotServedView(key: const ValueKey('no-location'), info: NotServed(mode: mode), noLocation: true);
    }
    final c = ref.watch(areaCoverageProvider);
    if (c.services == Coverage.no && c.groceries == Coverage.no) {
      final mode = ref.watch(homeFlowModeProvider);
      return NotServedView(key: ValueKey('blocked|${point.key}'), info: NotServed(mode: mode, message: c.messageOf(mode)));
    }
    return widget.child;
  }
}
