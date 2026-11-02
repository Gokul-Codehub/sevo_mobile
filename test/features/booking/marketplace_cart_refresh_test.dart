import 'package:calservices_customer/core/errors/api_error.dart';
import 'package:calservices_customer/features/booking/domain/booking_models.dart';
import 'package:calservices_customer/features/booking/domain/cart_notifier.dart';
import 'package:calservices_customer/features/booking/domain/marketplace_cart_refresh.dart';
import 'package:calservices_customer/features/catalog/data/marketplace_catalog_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

MarketplaceProduct product(int id, {String price = '40', bool inStock = true, int stock = 10, Object? rating}) => MarketplaceProduct.fromJson({
      'id': id,
      'title': 'P$id',
      'selling_price': price,
      'in_stock': inStock,
      'available_stock': stock,
      if (rating != null) 'rating': rating,
    });

CartItem line(int id, int qty, {String price = '40'}) => CartItem(service: product(id, price: price).toServiceItem(), quantity: qty);

void main() {
  group('which errors mean the cart is stale', () {
    test('stock / price / availability codes do; others do not', () {
      for (final code in ['INSUFFICIENT_STOCK', 'PRICE_CHANGED', 'PRODUCT_UNAVAILABLE', 'ITEM_UNAVAILABLE', 'insufficient_stock']) {
        expect(isCartStaleError(ValidationError('x', code: code)), isTrue, reason: code);
      }
      expect(isCartStaleError(const ValidationError('x', code: 'VALIDATION_ERROR')), isFalse);
      expect(isCartStaleError(const ValidationError('x')), isFalse);
      expect(isCartStaleError(const NetworkError()), isFalse);
    });
  });

  group('refreshing a line', () {
    test('a sold-out product is dropped', () {
      expect(refreshedLine(line(5, 2), product(5, inStock: false)), isNull);
    });

    test('quantity is capped to what is in stock now', () {
      final r = refreshedLine(line(5, 8), product(5, stock: 3))!;
      expect(r.quantity, 3);
    });

    test('a new price comes through', () {
      final r = refreshedLine(line(5, 1, price: '40'), product(5, price: '45'))!;
      expect(r.service.effectivePrice.toString(), '45');
    });

    test('a failed lookup leaves the line alone', () {
      final l = line(5, 2);
      final r = refreshedLine(l, null)!;
      expect((r.service, r.quantity), (l.service, 2));
    });
  });

  test('replaceLine swaps a line in place and keeps the others', () {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final n = c.read(cartProvider.notifier);
    n.addService(line(5, 1).service);
    n.addService(line(6, 1).service);
    final fresh = product(5, price: '50').toServiceItem();
    n.replaceLine(fresh.id, fresh, 3);
    final cart = c.read(cartProvider);
    expect(cart.firstWhere((i) => i.service.id == fresh.id).quantity, 3);
    expect(cart.firstWhere((i) => i.service.id == fresh.id).service.effectivePrice.toString(), '50');
    expect(cart.length, 2);
  });

  group('product rating comes from real reviews only', () {
    test('no reviews: no rating (the star chip is hidden), not a made-up 4.8', () {
      final s = product(5).toServiceItem();
      expect((s.rating, s.reviewCount), (0.0, 0));
    });

    test('real reviews: their average and count', () {
      final s = product(5, rating: {'average': 4.3, 'count': 12}).toServiceItem();
      expect((s.rating, s.reviewCount), (4.3, 12));
    });

    test('a null rating from the server is no rating', () {
      expect(product(5, rating: null).toServiceItem().rating, 0.0);
    });
  });
}
