import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../routing/app_router.dart' show rootNavigatorKey;
import '../../../addresses/domain/address_models.dart';
import '../../../addresses/domain/address_notifier.dart' show selectedAddressProvider;
import '../../../catalog/data/marketplace_catalog_repository.dart';
import '../../domain/booking_models.dart';
import '../../domain/cart_notifier.dart';

/// The warehouse the grocery lines in [cart] were added from (null when there are none, or it is not recorded).
int? cartWarehouseOf(List<CartItem> cart) {
  for (final item in cart) {
    final w = item.service.warehouseId;
    if (w != null) return w;
  }
  return null;
}

/// True when delivering to [zone] would mean fulfilling the cart from a different warehouse than it was filled from.
/// Same rule as the web store: a cart can only ship from one hub, so changing to an address served by another hub
/// has to either empty the cart or be undone.
bool cartConflictsWithZone(List<CartItem> cart, DeliveryZone zone) {
  final inCart = cartWarehouseOf(cart);
  return zone.status == DeliveryZoneStatus.serviceable && inCart != null && inCart != zone.warehouseId;
}

/// Mounted once above every screen. When the delivery address changes to one served by a different warehouse than
/// the grocery cart's, asks the customer to either clear the cart and switch, or keep the cart and go back to the
/// previous address.
class CartZoneGuard extends ConsumerStatefulWidget {
  const CartZoneGuard({super.key, required this.child});
  final Widget child;

  @override
  ConsumerState<CartZoneGuard> createState() => _CartZoneGuardState();
}

class _CartZoneGuardState extends ConsumerState<CartZoneGuard> {
  Address? _previousAddress;
  bool _asking = false;

  Future<void> _onZone(DeliveryZone zone) async {
    final cart = ref.read(cartProvider);
    if (_asking || !cartConflictsWithZone(cart, zone)) return;
    final context = rootNavigatorKey.currentContext;
    if (context == null) return;
    _asking = true;
    try {
      final clear = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          title: const Text('Change delivery location?'),
          content: Text(
            'Your cart has items from a different delivery hub than ${zone.name ?? 'the one serving this address'}. '
            'To deliver here, your cart needs to be cleared.',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Keep my cart')),
            FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Clear cart & switch')),
          ],
        ),
      );
      if (clear == true) {
        ref.read(cartProvider.notifier).clearCart();
      } else if (_previousAddress != null) {
        // Undo the address change; the zone re-resolves to the cart's hub, so this does not ask again.
        ref.read(selectedAddressProvider.notifier).state = _previousAddress;
      }
    } finally {
      _asking = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<Address?>(selectedAddressProvider, (prev, next) {
      if (!_asking) _previousAddress = prev;
    });
    ref.listen<AsyncValue<DeliveryZone>>(deliveryZoneProvider, (_, next) {
      final zone = next.valueOrNull;
      if (zone != null) _onZone(zone);
    });
    return widget.child;
  }
}
