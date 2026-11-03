import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../booking/domain/cart_notifier.dart';
import '../../catalog/data/marketplace_catalog_repository.dart';
import '../../catalog/domain/catalog_models.dart';
import '../data/grocery_orders_repository.dart';

/// Seller Hub products enter the cart with their id shifted into this range (see marketplace_cart.dart).
const int _marketplaceCartIdOffset = 800000000;

/// What "order again" will do for a past grocery order: which lines go into the cart (at TODAY's price and stock) and
/// which cannot, with a reason the customer can read.
class ReorderPlan {
  const ReorderPlan({this.adds = const [], this.skipped = const [], this.trimmed = const [], this.combos = 0});

  final List<({ServiceItem item, int quantity})> adds;

  /// "<name> is out of stock" / "<name> is no longer available".
  final List<String> skipped;

  /// "<name>: only 2 available" (added, but fewer than before).
  final List<String> trimmed;

  /// Combo-offer lines: their slot choices have to be made again, so they are not re-added blindly.
  final int combos;

  bool get isEmpty => adds.isEmpty;
  int get addedUnits => adds.fold(0, (t, a) => t + a.quantity);
}

/// Pure planning step: [live] maps a Seller Hub product id to its current record (absent = no longer sold).
ReorderPlan planReorder(List<OrderLine> lines, Map<int, ServiceItem> live) {
  final adds = <({ServiceItem item, int quantity})>[];
  final skipped = <String>[];
  final trimmed = <String>[];
  var combos = 0;
  final seen = <int>{};
  for (final line in lines) {
    if (line.basketId != null) {
      combos++;
      continue;
    }
    final id = line.productId;
    if (id == null) {
      skipped.add('${line.title} can no longer be matched');
      continue;
    }
    if (!seen.add(id)) continue; // the same product twice on one order: add it once
    final item = live[id];
    if (item == null) {
      skipped.add('${line.title} is no longer available');
      continue;
    }
    if (!item.inStock) {
      skipped.add('${line.title} is out of stock');
      continue;
    }
    // Same product on several lines (different sellers): ask for the total.
    final wanted = lines.where((l) => l.basketId == null && l.productId == id).fold<int>(0, (t, l) => t + l.quantity);
    final cap = item.maxQuantity > 0 ? item.maxQuantity : wanted;
    final qty = wanted > cap ? cap : wanted;
    if (qty <= 0) {
      skipped.add('${line.title} is out of stock');
      continue;
    }
    if (qty < wanted) trimmed.add('${line.title}: only $qty available');
    adds.add((item: item, quantity: qty));
  }
  return ReorderPlan(adds: adds, skipped: skipped, trimmed: trimmed, combos: combos);
}

/// The one line shown after a reorder.
String reorderMessage(ReorderPlan p) {
  if (p.isEmpty) {
    if (p.combos > 0 && p.skipped.isEmpty) return 'Combo offers need to be chosen again. Open the offer to pick your items.';
    return p.skipped.isEmpty ? 'Nothing from this order could be added right now.' : '${p.skipped.first}. Nothing was added.';
  }
  final parts = <String>['Added ${p.addedUnits} item${p.addedUnits == 1 ? '' : 's'} to your cart'];
  final notes = [...p.trimmed, ...p.skipped];
  if (notes.isNotEmpty) parts.add(notes.length == 1 ? notes.first : '${notes.length} items could not be added in full');
  if (p.combos > 0) parts.add('combo offers need to be chosen again');
  return parts.join('. ');
}

/// Looks the order's products up again (price, stock, availability are today's, never the old order's) and adds
/// what can be bought to the cart. Returns what happened, or null when the products could not be looked up at all.
Future<ReorderPlan?> reorderGroceryOrder(WidgetRef ref, GroceryOrder order) async {
  final ids = {for (final l in order.items) if (l.basketId == null && l.productId != null) l.productId!};
  Map<int, ServiceItem> live = {};
  if (ids.isNotEmpty) {
    try {
      final products = await ref.read(marketplaceProductsByIdsProvider(ids.join(',')).future);
      for (final p in products) {
        final item = p.toServiceItem();
        live[item.id - _marketplaceCartIdOffset] = item;
      }
    } catch (_) {
      return null;
    }
  }
  final plan = planReorder(order.items, live);
  final cart = ref.read(cartProvider.notifier);
  for (final a in plan.adds) {
    cart.addService(a.item, quantity: a.quantity);
  }
  return plan;
}
