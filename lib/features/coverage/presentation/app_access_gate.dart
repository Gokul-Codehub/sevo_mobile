import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/utils/location_gate.dart' show useCurrentLocationWithHelp;
import '../../../shared/theme/app_colors.dart';
import '../../addresses/domain/address_notifier.dart';
import '../../addresses/presentation/widgets/location_sheet.dart';
import '../../auth/domain/auth_return.dart';
import '../../booking/domain/cart_notifier.dart' show isUserAuthenticatedProvider;
import '../../catalog/data/marketplace_catalog_repository.dart' show deliveryPointProvider;
import '../../home/domain/home_flow_mode.dart';
import '../domain/coverage.dart';
import 'not_served_view.dart';

/// Blinkit / Flipkart-style access rule for the whole app (wraps the bottom-nav shell, so every tab and every page
/// opened from it, including deep links and notification taps):
///  * no delivery location yet  -> only "Set your delivery location" (current location or manual search);
///  * we are SURE neither groceries nor services is served there -> "not available here yet" with change location.
/// An unknown answer (check still running, network down) never blocks, so a slow phone is not locked out.
class AppAccessGate extends ConsumerStatefulWidget {
  const AppAccessGate({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<AppAccessGate> createState() => _AppAccessGateState();
}

class _AppAccessGateState extends ConsumerState<AppAccessGate> {
  // The saved location is restored from secure storage a moment after launch; do not flash the gate before then.
  bool _armed = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer(const Duration(milliseconds: 700), () {
      if (mounted) setState(() => _armed = true);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final point = ref.watch(deliveryPointProvider);
    if (point.label.isEmpty) {
      final signedIn = ref.watch(isUserAuthenticatedProvider);
      final loadingSaved = signedIn && ref.watch(addressListProvider).isLoading;
      if (!_armed || loadingSaved) {
        return const Scaffold(backgroundColor: AppColors.background, body: Center(child: CircularProgressIndicator(strokeWidth: 2.5)));
      }
      return const LocationRequiredScreen();
    }
    final c = ref.watch(areaCoverageProvider);
    if (c.services == Coverage.no && c.groceries == Coverage.no) {
      final mode = ref.watch(homeFlowModeProvider);
      return NotServedView(
        key: ValueKey('blocked|${point.key}'),
        info: NotServed(mode: mode, message: c.messageOf(mode)),
      );
    }
    return widget.child;
  }
}

class LocationRequiredScreen extends ConsumerStatefulWidget {
  const LocationRequiredScreen({super.key});

  @override
  ConsumerState<LocationRequiredScreen> createState() => _LocationRequiredScreenState();
}

class _LocationRequiredScreenState extends ConsumerState<LocationRequiredScreen> {
  bool _busy = false;
  String? _message;

  Future<void> _useCurrent() async {
    setState(() {
      _busy = true;
      _message = null;
    });
    final ok = await useCurrentLocationWithHelp(context, ref);
    if (!mounted) return;
    if (ok) {
      await chooseDeliveryAddress(ref, null);
      return; // the gate lifts by itself as soon as the location is set
    }
    setState(() {
      _busy = false;
      _message = 'We could not get your location. Turn on location, or enter it manually.';
    });
  }

  @override
  Widget build(BuildContext context) {
    final signedIn = ref.watch(isUserAuthenticatedProvider);
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 104,
                  height: 104,
                  decoration: const BoxDecoration(color: Color(0xFFE8F5EE), shape: BoxShape.circle),
                  child: const Icon(Icons.location_on_rounded, size: 52, color: Color(0xFF059669)),
                ),
                const SizedBox(height: 22),
                const Text(
                  'Set your delivery location',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: AppColors.navy),
                ),
                const SizedBox(height: 10),
                const Text(
                  'Tell us where to deliver, so we can show what is available near you.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13.5, color: AppColors.textSecondary, height: 1.45),
                ),
                const SizedBox(height: 28),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(backgroundColor: const Color(0xFF059669), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
                    onPressed: _busy ? null : _useCurrent,
                    icon: _busy
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.my_location_rounded, size: 20),
                    label: const Text('Use current location', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.navy,
                      side: const BorderSide(color: AppColors.navy),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    onPressed: _busy ? null : () => showLocationSheet(context),
                    icon: const Icon(Icons.search_rounded, size: 20),
                    label: const Text('Enter location manually', style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700)),
                  ),
                ),
                if (_message != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(_message!, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12.5, color: AppColors.error)),
                  ),
                if (!signedIn) ...[
                  const SizedBox(height: 14),
                  TextButton(
                    onPressed: () => requireLoginWith(GoRouter.of(context), ref),
                    child: const Text('Have an account? Sign in to use saved addresses', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
