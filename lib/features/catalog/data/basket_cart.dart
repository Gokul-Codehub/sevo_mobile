import '../../booking/domain/cart_notifier.dart';
import '../../booking/domain/combo_key.dart';
import '../domain/catalog_models.dart';
import 'basket_models.dart';

/// Puts a combo offer in the cart as ONE group: the product picked for each
/// slot (and any extra fixed product) is added under the combo's name, so the
/// cart shows "Family Combo offer" with its products listed beneath instead of
/// loose products. Returns how many products were added (0 = nothing available).
///
/// [pick] chooses the option for a slot (the customer's selection, or the
/// default). A basket's `items` list repeats each slot's default pick, so only
/// items that are NOT a slot's default are treated as extra fixed products —
/// otherwise every product would be added twice.
int addComboToCart(
  CartNotifier cart,
  MarketplaceBasket basket,
  BasketSlotOption? Function(BasketSlot slot) pick,
) {
  final entries = <({ServiceItem item, int qty})>[];
  final slotDefaultTitles = <String>{};
  // What the customer picked for each slot: the server needs it to know what to pack.
  final selections = <({int slotId, int productId})>[];

  for (final slot in basket.slots) {
    final defaultTitle = slot.defaultOption?.title;
    if (defaultTitle != null) slotDefaultTitles.add(defaultTitle);
    final option = pick(slot);
    final item = option?.toServiceItem();
    if (item != null) {
      entries.add((item: item, qty: slot.quantity));
      final slotId = slot.id;
      final productId = option!.productId ?? option.id ?? option.optionId;
      if (slotId != null && productId != null) selections.add((slotId: slotId, productId: productId));
    }
  }
  for (final fixed in basket.items) {
    if (slotDefaultTitles.contains(fixed.productTitle)) continue;
    final item = fixed.toServiceItem();
    if (item != null) entries.add((item: item, qty: fixed.quantity));
  }
  if (entries.isEmpty) return 0;

  final ids = entries.map((e) => e.item.id).toList()..sort();
  // Remembers the bundle price (what the combo really costs) and the customer's picks, not only which products.
  final key = ComboKey.build(basketId: basket.id, productIds: ids, bundlePrice: basket.bundlePrice, selections: selections);
  for (final e in entries) {
    cart.addComboItem(e.item, quantity: e.qty, comboKey: key, comboTitle: basket.title);
  }
  return entries.length;
}
