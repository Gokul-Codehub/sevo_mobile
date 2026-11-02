import 'package:calservices_customer/features/booking/domain/booking_models.dart';
import 'package:calservices_customer/features/booking/domain/cart_notifier.dart';
import 'package:calservices_customer/features/booking/domain/combo_key.dart';
import 'package:calservices_customer/features/booking/domain/marketplace_cart.dart';
import 'package:calservices_customer/features/catalog/data/marketplace_catalog_repository.dart';
import 'package:decimal/decimal.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Decimal d(String s) => Decimal.parse(s);

CartItem part(int id, String price, int qty, String key, {int unit = 1}) => CartItem(
      service: MarketplaceProduct.fromJson({'id': id, 'title': 'P$id', 'selling_price': price}).toServiceItem(),
      quantity: qty,
      comboKey: key,
      comboTitle: 'Family combo',
      comboUnitQty: unit,
    );

void main() {
  group('combo key', () {
    test('round trip: bundle price and the picks survive', () {
      final key = ComboKey.build(basketId: 8, productIds: [900, 5], bundlePrice: d('250.00'), selections: [(slotId: 1, productId: 5), (slotId: 2, productId: 900)]);
      final k = ComboKey.parse(key)!;
      expect((k.basketId, k.bundlePrice), (8, d('250.00')));
      expect(k.selections.map((s) => (s.slotId, s.productId)), [(1, 5), (2, 900)]);
    });

    test('a key saved by an older version still parses, with no price or picks', () {
      final k = ComboKey.parse('8:800000005,800000900')!;
      expect((k.basketId, k.bundlePrice), (8, null));
      expect(k.selections, isEmpty);
    });

    test('junk is not a combo', () {
      expect(ComboKey.parse(null), isNull);
      expect(ComboKey.parse(''), isNull);
      expect(ComboKey.parse('abc'), isNull);
    });
  });

  group('what a combo costs', () {
    final key = ComboKey.build(basketId: 8, productIds: [1, 2], bundlePrice: d('250'));

    test('the bundle price times the count, not the sum of the parts', () {
      final one = [part(1, '200', 1, key), part(2, '150', 1, key)]; // parts add up to 350
      expect(comboGroupTotal(one), d('250'));
      final two = [part(1, '200', 2, key), part(2, '150', 2, key)];
      expect(comboGroupTotal(two), d('500'));
      expect(comboCountOf(two), 2);
    });

    test('a combo saved without a bundle price falls back to the parts', () {
      final old = [part(1, '200', 1, '8:1,2'), part(2, '150', 1, '8:1,2')];
      expect(comboGroupTotal(old), d('350'));
    });

    test('a part that comes 2 per combo still counts combos, not units', () {
      final lines = [part(1, '100', 4, key, unit: 2), part(2, '50', 2, key)];
      expect(comboCountOf(lines), 2);
      expect(comboGroupTotal(lines), d('500'));
    });
  });

  group('cart total', () {
    test('combo at its bundle price plus a single product, once each', () {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      final n = c.read(cartProvider.notifier);
      final key = ComboKey.build(basketId: 8, productIds: [1, 2], bundlePrice: d('250'));
      for (final p in [part(1, '200', 1, key), part(2, '150', 1, key)]) {
        n.addComboItem(p.service, quantity: p.quantity, comboKey: key, comboTitle: 'Family combo');
      }
      n.addService(MarketplaceProduct.fromJson({'id': 7, 'title': 'Bread', 'selling_price': '45'}).toServiceItem());
      final s = c.read(cartSummaryProvider);
      expect(s.subtotal, d('295')); // 250 bundle + 45 bread, NOT 350 + 45
      expect(s.total, d('295')); // and no fees on a Seller Hub cart
    });

    test('an old-format combo is still summed from its parts', () {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      final n = c.read(cartProvider.notifier);
      for (final p in [part(1, '200', 1, '8:1,2'), part(2, '150', 1, '8:1,2')]) {
        n.addComboItem(p.service, quantity: 1, comboKey: '8:1,2', comboTitle: 'Old combo');
      }
      expect(c.read(cartSummaryProvider).subtotal, d('350'));
    });
  });

  group('what is sent to the server', () {
    test('a combo is one basket line with its count and the customer\'s picks, like the web', () {
      final key = ComboKey.build(basketId: 8, productIds: [1, 2], bundlePrice: d('250'), selections: [(slotId: 11, productId: 5), (slotId: 12, productId: 9)]);
      final entries = marketplaceCartEntries([part(1, '200', 2, key), part(2, '150', 2, key)]);
      final json = entries.single.toJson();
      expect(json['basket_id'], 8);
      expect(json['quantity'], 2);
      final custom = json['customization'] as Map;
      expect(custom['slot_selections'], [
        {'slot_id': 11, 'product_id': 5},
        {'slot_id': 12, 'product_id': 9},
      ]);
      expect(custom['live_mrp'], 350.0);
    });

    test('a combo without picks (nothing to choose) sends no customization', () {
      final key = ComboKey.build(basketId: 8, productIds: [1], bundlePrice: d('99'));
      final json = marketplaceCartEntries([part(1, '120', 1, key)]).single.toJson();
      expect(json.containsKey('customization'), isFalse);
    });

    test('combos from the old key format still go to the server as a basket', () {
      final json = marketplaceCartEntries([part(1, '120', 3, '8:1')]).single.toJson();
      expect((json['basket_id'], json['quantity']), (8, 3));
    });
  });

  test('combo parts are Seller Hub items, so the old-catalog rule never blocks them', () {
    expect(isLegacyGroceryItem(part(1, '10', 1, '8:1').service), isFalse);
    final c = ProviderContainer();
    addTearDown(c.dispose);
    c.read(cartProvider.notifier).addComboItem(part(1, '10', 1, '8:1').service, quantity: 1, comboKey: '8:1', comboTitle: 'x');
    expect(c.read(cartProvider), hasLength(1));
  });
}
