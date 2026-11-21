import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../addresses/domain/address_notifier.dart';
import '../../auth/domain/auth_notifier.dart' show authLoadingProvider;
import '../../booking/domain/cart_notifier.dart' show isUserAuthenticatedProvider;
import '../../catalog/data/marketplace_catalog_repository.dart' show deliveryPointProvider;
import '../../logistics/domain/logistics_providers.dart' show customerLocationProvider;

Future<void> _until(bool Function() done, Duration max) async {
  final end = DateTime.now().add(max);
  while (!done() && DateTime.now().isBefore(end)) {
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
}

/// Completes once the delivery location is KNOWN, or every quiet source has been tried. Never throws, and every step
/// is bounded so a slow phone or network never holds the app back.
///
/// Order (cheapest and most trusted first, like Blinkit / Swiggy, which open on the last used address at once and
/// only ask when they truly have nothing):
///  1. the place remembered on the phone;
///  2. signed in: the stored session, then the last used saved address;
///  3. only if there is still no location: silent GPS (permission already granted, no dialogs).
///
/// The splash waits for this, so it plays once and Home opens with the location known; the access gate uses it to tell
/// "no location" from "not loaded yet".
final appLocationSettledProvider = FutureProvider<void>((ref) async {
  bool known() => ref.read(deliveryPointProvider).label.isNotEmpty;
  try {
    await ref.read(customerLocationProvider.notifier).ready.timeout(const Duration(seconds: 3));
  } catch (_) {}
  // The stored session is read from the phone first; its answer decides whether saved addresses exist.
  await _until(() => !ref.read(authLoadingProvider), const Duration(seconds: 4));
  if (!known() && ref.read(isUserAuthenticatedProvider)) {
    try {
      await ref.read(addressListProvider.future).timeout(const Duration(seconds: 8));
    } catch (_) {}
    // The last used address is picked a moment after the list arrives (it is read from storage).
    await _until(known, const Duration(seconds: 3));
  }
  if (!known()) {
    try {
      await ref.read(customerLocationProvider.notifier).autoDetectIfNeeded().timeout(const Duration(seconds: 6));
    } catch (_) {}
  }
});
