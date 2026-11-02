import 'package:decimal/decimal.dart';

import 'booking_models.dart';

/// What a combo offer in the cart remembers, kept inside its `comboKey` (the string that already groups the combo's
/// product lines):
///
///   `<basketId>:<productIds>`                       - what older versions saved
///   `<basketId>:<productIds>|b=<bundlePrice>|s=<slotId>-<productId>,...`
///
/// - the bundle price, because a combo is sold at ONE all-in price (cheaper than its parts) and the cart must show -
///   and the server charges - that price, not the sum of the parts;
/// - the customer's pick for each slot, which the server needs to know what to pack.
class ComboKey {
  const ComboKey({required this.basketId, this.bundlePrice, this.selections = const []});

  final int basketId;
  final Decimal? bundlePrice;
  final List<({int slotId, int productId})> selections;

  static String build({required int basketId, required List<int> productIds, Decimal? bundlePrice, List<({int slotId, int productId})> selections = const []}) {
    final ids = [...productIds]..sort();
    return [
      '$basketId:${ids.join(',')}',
      if (bundlePrice != null) 'b=$bundlePrice',
      if (selections.isNotEmpty) 's=${selections.map((s) => '${s.slotId}-${s.productId}').join(',')}',
    ].join('|');
  }

  static ComboKey? parse(String? key) {
    if (key == null || key.isEmpty) return null;
    final parts = key.split('|');
    final basketId = int.tryParse(parts.first.split(':').first);
    if (basketId == null) return null;
    Decimal? price;
    final selections = <({int slotId, int productId})>[];
    for (final p in parts.skip(1)) {
      if (p.startsWith('b=')) {
        price = Decimal.tryParse(p.substring(2));
      } else if (p.startsWith('s=')) {
        for (final pair in p.substring(2).split(',')) {
          final ab = pair.split('-');
          final slot = ab.length == 2 ? int.tryParse(ab[0]) : null;
          final prod = ab.length == 2 ? int.tryParse(ab[1]) : null;
          if (slot != null && prod != null) selections.add((slotId: slot, productId: prod));
        }
      }
    }
    return ComboKey(basketId: basketId, bundlePrice: price, selections: selections);
  }
}

/// How many of the combo these lines are (each product's quantity follows the combo count).
int comboCountOf(List<CartItem> members) {
  if (members.isEmpty) return 0;
  final unit = members.first.comboUnitQty <= 0 ? 1 : members.first.comboUnitQty;
  return (members.first.quantity / unit).round();
}

/// What a combo costs: its bundle price times how many were taken, or - for a combo saved without a bundle price -
/// the sum of its parts.
Decimal comboGroupTotal(List<CartItem> members) {
  if (members.isEmpty) return Decimal.zero;
  final bundle = ComboKey.parse(members.first.comboKey)?.bundlePrice;
  if (bundle == null) return members.fold<Decimal>(Decimal.zero, (s, m) => s + m.totalPrice);
  return bundle * Decimal.fromInt(comboCountOf(members));
}
