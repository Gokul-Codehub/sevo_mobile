import 'package:calservices_customer/features/booking/domain/grocery_fee_split.dart';
import 'package:calservices_customer/features/pricing/domain/pricing_models.dart';
import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';

Decimal d(String s) => Decimal.parse(s);

void main() {
  final p = PricingConfig.fallback;

  test('fees are charged once per order: delivery + handling (+ small order) split out when they add up exactly', () {
    final items = d('44'); // under the free-delivery threshold
    final delivery = p.deliveryFee;
    final handling = p.handlingFee;
    final small = items < p.smallCartThreshold ? p.smallCartFee : Decimal.zero;
    final lines = splitGroceryFees(itemsTotal: items, other: delivery + handling + small, pricing: p)!;
    expect(lines.fold<Decimal>(Decimal.zero, (s, l) => s + l.amount), delivery + handling + small);
    expect(lines.map((l) => l.label), containsAll(['Delivery fee', 'Handling & packaging fee']));
  });

  test('delivery is free above the threshold, so only handling is listed', () {
    final items = p.freeDeliveryThreshold + d('50');
    final lines = splitGroceryFees(itemsTotal: items, other: p.handlingFee, pricing: p)!;
    expect(lines.map((l) => l.label), ['Handling & packaging fee']);
  });

  test('a total that does not add up (tip, coupon, changed prices) is not guessed at', () {
    expect(splitGroceryFees(itemsTotal: d('44'), other: d('36.92'), pricing: p), isNull);
  });
}
