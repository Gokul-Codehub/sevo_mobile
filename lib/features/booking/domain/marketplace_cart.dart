import '../../catalog/domain/catalog_models.dart' show ServiceItem;
import 'booking_models.dart';
import 'combo_key.dart';

// Seller Hub product ids are offset by this much when used as cart ids (see MarketplaceProduct).
const int _offset = 800000000;
const int _offsetEnd = 899999999;

/// The Seller Hub product id behind a cart line, or null when the line is not a Seller Hub product.
int? marketplaceProductIdOf(CartItem item) {
  final id = item.service.id;
  return id > _offset && id <= _offsetEnd ? id - _offset : null;
}

/// A grocery / vegetable item from the OLD in-house catalog (not the Seller Hub). The web store no longer sells these,
/// they never reach a seller, and the app no longer lets them into the cart.
bool isLegacyGroceryItem(ServiceItem s) => s.isGroceryFlow && !(s.id > _offset && s.id <= _offsetEnd);

/// The Seller Hub grocery lines of a cart (services, if any are in it, are not groceries).
List<CartItem> marketplaceLines(List<CartItem> items) => [for (final i in items) if (marketplaceProductIdOf(i) != null) i];

/// True when EVERY line is a Seller Hub product (single products or combo offers). Only such a cart can be ordered
/// through the marketplace checkout - the same one the web store uses - which sends the order to the seller to pack
/// and reserves Seller Hub stock.
bool isMarketplaceCart(List<CartItem> items) => items.isNotEmpty && items.every((i) => marketplaceProductIdOf(i) != null);

/// What to put in the server-side marketplace cart: one entry per single product, one per combo offer.
class MarketplaceCartEntry {
  const MarketplaceCartEntry.product(int this.productId, this.quantity)
      : basketId = null,
        customization = null;
  const MarketplaceCartEntry.basket(int this.basketId, this.quantity, {this.customization}) : productId = null;

  final int? productId;
  final int? basketId;
  final int quantity;

  /// A combo's chosen options (`slot_selections`, `live_mrp`), exactly as the web sends them.
  final Map<String, Object>? customization;

  Map<String, Object> toJson() => {
        if (productId != null) 'seller_product_id': productId!,
        if (basketId != null) 'basket_id': basketId!,
        'quantity': quantity,
        if (customization != null && customization!.isNotEmpty) 'customization': customization!,
      };
}

/// Turns the app's cart into server-cart entries. A combo's products are many cart lines sharing one `comboKey`
/// (`<basketId>:<productIds>`); they go to the server as ONE basket line, with the combo's count.
List<MarketplaceCartEntry> marketplaceCartEntries(List<CartItem> items) {
  final entries = <MarketplaceCartEntry>[];
  final seenCombos = <String>{};
  for (final item in items) {
    final key = item.comboKey;
    if (key != null) {
      if (!seenCombos.add(key)) continue;
      final parsed = ComboKey.parse(key);
      final members = [for (final i in items) if (i.comboKey == key) i];
      final count = comboCountOf(members);
      if (parsed != null && count > 0) {
        // Regular price of one combo's parts - shown by the server as the "was" price next to the bundle price.
        final mrpOfOne = members.fold<double>(0, (s, m) => s + m.service.price.toDouble() * (m.comboUnitQty <= 0 ? 1 : m.comboUnitQty));
        entries.add(MarketplaceCartEntry.basket(
          parsed.basketId,
          count,
          customization: parsed.selections.isEmpty
              ? null
              : {
                  'slot_selections': [for (final s in parsed.selections) {'slot_id': s.slotId, 'product_id': s.productId}],
                  'live_mrp': mrpOfOne,
                },
        ));
      }
      continue;
    }
    final id = marketplaceProductIdOf(item);
    if (id != null && item.quantity > 0) entries.add(MarketplaceCartEntry.product(id, item.quantity));
  }
  return entries;
}
