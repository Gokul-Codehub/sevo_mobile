import 'package:decimal/decimal.dart';

import '../../pricing/domain/pricing_models.dart';

/// One fee line on a grocery order's bill.
class FeeLine {
  const FeeLine(this.label, this.amount);
  final String label;
  final Decimal amount;
}

/// Splits what an order charged beyond its items into the separate fees it is made of.
///
/// Grocery fees are per ORDER, not per product: delivery (free above a threshold), handling & packaging (flat) and a
/// small-order fee (below a threshold) - the same rules the cart uses. The booking stores only the final total, so
/// the split is rebuilt from the current admin pricing and used ONLY when it adds up exactly to [other] (the total
/// minus the items). If it does not - prices changed since, a tip or a coupon was involved - null is returned and
/// the caller shows one combined line instead of guessing.
List<FeeLine>? splitGroceryFees({required Decimal itemsTotal, required Decimal other, required PricingConfig pricing}) {
  final delivery = itemsTotal >= pricing.freeDeliveryThreshold ? Decimal.zero : pricing.deliveryFee;
  final handling = pricing.handlingFee;
  final small = itemsTotal < pricing.smallCartThreshold ? pricing.smallCartFee : Decimal.zero;
  if (delivery + handling + small != other) return null;
  return [
    if (delivery > Decimal.zero) FeeLine('Delivery fee', delivery),
    if (handling > Decimal.zero) FeeLine('Handling & packaging fee', handling),
    if (small > Decimal.zero) FeeLine('Small order fee', small),
  ];
}
