import 'package:calservices_customer/features/catalog/domain/catalog_models.dart';
import 'package:calservices_customer/features/orders/data/grocery_orders_repository.dart';
import 'package:calservices_customer/features/orders/domain/reorder.dart';
import 'package:calservices_customer/features/orders/presentation/buy_it_again_strip.dart';
import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';

OrderLine line(String title, {int? product, int? basket, int qty = 1}) =>
    OrderLine(title: title, quantity: qty, unitPrice: 40, amount: 40.0 * qty, productId: product, basketId: basket);

ServiceItem live(int productId, String title, {bool inStock = true, int max = 99}) => ServiceItem(
      id: 800000000 + productId,
      title: title,
      slug: 'veg-$productId',
      price: Decimal.parse('42'),
      categoryId: 1,
      categoryName: 'Vegetables',
      categorySlug: 'vegetables_groceries',
      inStock: inStock,
      maxQuantity: max,
    );

GroceryOrder order(String number, DateTime at, List<OrderLine> lines, {String status = 'DELIVERED'}) => GroceryOrder.tryParse({
      'order_number': number,
      'status': status,
      'created_at': at.toIso8601String(),
      'total_amount': '100',
      'items': [
        for (final l in lines)
          {
            'product_title': l.title,
            'quantity': l.quantity,
            'unit_price_snapshot': '40',
            'line_amount': '${40 * l.quantity}',
            'seller_product_id': l.productId,
            'basket_id': l.basketId,
          },
      ],
    })!;

void main() {
  group('order lines carry what reordering needs', () {
    test('the server\'s product id and combo id are read from each line', () {
      final o = order('SEVO-1', DateTime(2026, 11, 1), [line('Beetroot', product: 11, qty: 2), line('Festival combo', basket: 5)]);
      expect(o.items[0].productId, 11);
      expect(o.items[0].basketId, isNull);
      expect(o.items[1].basketId, 5);
    });
  });

  group('planReorder', () {
    test('adds what is in stock at today\'s record, with the old quantity', () {
      final plan = planReorder([line('Beetroot', product: 11, qty: 2), line('Carrot', product: 12)], {11: live(11, 'Beetroot'), 12: live(12, 'Carrot')});
      expect(plan.adds.map((a) => (a.item.title, a.quantity)).toList(), [('Beetroot', 2), ('Carrot', 1)]);
      expect(plan.skipped, isEmpty);
      expect(plan.addedUnits, 3);
    });

    test('skips a product that is gone or out of stock, and says why', () {
      final plan = planReorder(
        [line('Beetroot', product: 11), line('Carrot', product: 12), line('Onion', product: 13)],
        {11: live(11, 'Beetroot', inStock: false), 12: live(12, 'Carrot')},
      );
      expect(plan.adds.single.item.title, 'Carrot');
      expect(plan.skipped, ['Beetroot is out of stock', 'Onion is no longer available']);
    });

    test('adds fewer when less is available now and tells the customer', () {
      final plan = planReorder([line('Tomato', product: 14, qty: 5)], {14: live(14, 'Tomato', max: 3)});
      expect(plan.adds.single.quantity, 3);
      expect(plan.trimmed, ['Tomato: only 3 available']);
    });

    test('combo offers are never re-added blindly', () {
      final plan = planReorder([line('Festival combo', basket: 5), line('Carrot', product: 12)], {12: live(12, 'Carrot')});
      expect(plan.combos, 1);
      expect(plan.adds.single.item.title, 'Carrot');
    });

    test('the same product on two lines is added once, for the total', () {
      final plan = planReorder([line('Carrot', product: 12, qty: 1), line('Carrot', product: 12, qty: 2)], {12: live(12, 'Carrot')});
      expect(plan.adds.length, 1);
      expect(plan.adds.single.quantity, 3);
    });

    test('a line the server gave no product id for cannot be matched', () {
      final plan = planReorder([line('Mystery item')], const {});
      expect(plan.isEmpty, isTrue);
      expect(plan.skipped.single, contains('can no longer be matched'));
    });
  });

  group('reorderMessage', () {
    test('reads naturally for the usual outcomes', () {
      expect(reorderMessage(planReorder([line('Carrot', product: 12, qty: 2)], {12: live(12, 'Carrot')})), 'Added 2 items to your cart');
      expect(reorderMessage(planReorder([line('Carrot', product: 12)], const {})), 'Carrot is no longer available. Nothing was added.');
      expect(reorderMessage(planReorder([line('Combo', basket: 1)], const {})), contains('Combo offers need to be chosen again'));
      final partial = planReorder([line('Carrot', product: 12), line('Onion', product: 13)], {12: live(12, 'Carrot')});
      expect(reorderMessage(partial), 'Added 1 item to your cart. Onion is no longer available');
    });
  });

  group('buyAgainProductIds (the cart strip)', () {
    final older = order('A', DateTime(2026, 10, 1), [line('Beetroot', product: 11), line('Carrot', product: 12)]);
    final newer = order('B', DateTime(2026, 11, 1), [line('Onion', product: 13), line('Carrot', product: 12)]);

    test('newest orders first, each product once', () {
      expect(buyAgainProductIds([older, newer]), [13, 12, 11]);
    });

    test('leaves out what is already in the cart, combos, and orders that were never delivered', () {
      final cancelled = order('C', DateTime(2026, 11, 2), [line('Tomato', product: 14)], status: 'CANCELLED');
      final withCombo = order('D', DateTime(2026, 11, 3), [line('Festival combo', basket: 5)]);
      expect(buyAgainProductIds([older, newer, cancelled, withCombo], inCart: {12}), [13, 11]);
    });

    test('nothing for a first-time customer', () {
      expect(buyAgainProductIds(const []), isEmpty);
    });
  });
}
