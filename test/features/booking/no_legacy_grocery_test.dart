import 'dart:convert';

import 'package:calservices_customer/core/storage/secure_storage.dart';
import 'package:calservices_customer/features/booking/domain/booking_models.dart';
import 'package:calservices_customer/features/booking/domain/cart_notifier.dart';
import 'package:calservices_customer/features/booking/domain/marketplace_cart.dart';
import 'package:calservices_customer/features/catalog/data/marketplace_catalog_repository.dart';
import 'package:calservices_customer/features/catalog/domain/catalog_models.dart';
import 'package:calservices_customer/routing/app_router.dart' show legacyGroceryCategoryRoute;
import 'package:decimal/decimal.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

ServiceItem sellerHub(int id) => MarketplaceProduct.fromJson({'id': id, 'title': 'Bread', 'selling_price': '45'}).toServiceItem();

/// An item from the old in-house catalog: grocery by category, small id (no Seller Hub offset).
ServiceItem oldCatalogGrocery() => ServiceItem(id: 12, title: 'Tomato', slug: 'veg-tomato', price: Decimal.parse('30'), categoryName: 'Vegetables & Groceries', categorySlug: 'vegetables_groceries');

ServiceItem acService() => ServiceItem(id: 3, title: 'AC Service', slug: 'ac-service', price: Decimal.parse('499'), categoryName: 'AC', categorySlug: 'ac_appliance');

class _Storage extends SecureStorage {
  _Storage(this.saved);
  String? saved;
  @override
  Future<String?> getCartJson() async => saved;
  @override
  Future<void> setCartJson(String json) async => saved = json;
  @override
  Future<void> clearCartStorage() async => saved = null;
}

void main() {
  test('what counts as an old-catalog grocery item', () {
    expect(isLegacyGroceryItem(oldCatalogGrocery()), isTrue);
    expect(isLegacyGroceryItem(sellerHub(5)), isFalse);
    expect(isLegacyGroceryItem(acService()), isFalse); // services are untouched
  });

  test('old-catalog groceries cannot be added; Seller Hub products and services can', () {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final n = c.read(cartProvider.notifier);
    n.addService(oldCatalogGrocery());
    expect(c.read(cartProvider), isEmpty);
    n.addService(sellerHub(5));
    n.addService(acService());
    expect(c.read(cartProvider).map((i) => i.service.title), ['Bread', 'AC Service']);
  });

  test('an old-catalog combo line is refused too', () {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    c.read(cartProvider.notifier).addComboItem(oldCatalogGrocery(), quantity: 1, comboKey: '1:12', comboTitle: 'Old combo');
    expect(c.read(cartProvider), isEmpty);
  });

  test('after a grocery order the grocery lines go and a service in the cart stays', () {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final n = c.read(cartProvider.notifier);
    n.addService(sellerHub(5));
    n.addService(acService());
    n.removeMarketplaceLines();
    expect(c.read(cartProvider).map((i) => i.service.title), ['AC Service']);
  });

  test('marketplaceLines picks only the Seller Hub groceries', () {
    final lines = marketplaceLines([
      CartItem(service: sellerHub(5), quantity: 1),
      CartItem(service: acService(), quantity: 1),
    ]);
    expect(lines.single.service.title, 'Bread');
  });

  test('a cart with a service and a grocery still prices the grocery without fees', () {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final n = c.read(cartProvider.notifier);
    n.addService(sellerHub(5));
    final s = c.read(cartSummaryProvider);
    expect((s.deliveryFee, s.handlingFee), (Decimal.zero, Decimal.zero));
  });

  group('old grocery links lead to the Seller Hub store', () {
    test('vegetable and grocery categories are redirected', () {
      expect(legacyGroceryCategoryRoute('vegetables-groceries'), '/vegetables/seller-hub');
      expect(legacyGroceryCategoryRoute('fresh-fruits'), '/vegetables/seller-hub');
      expect(legacyGroceryCategoryRoute('farm_fresh'), '/groceries/seller-hub');
      expect(legacyGroceryCategoryRoute('grocery'), '/groceries/seller-hub');
    });

    test('service categories are not', () {
      for (final slug in ['ac_appliance', 'electrician', 'cleaning', 'goods_transports']) {
        expect(legacyGroceryCategoryRoute(slug), isNull, reason: slug);
      }
    });
  });

  test('a cart saved by an older version loses its old-catalog groceries when it is loaded', () async {
    final stored = jsonEncode([
      CartItem(service: oldCatalogGrocery(), quantity: 2).toStorageJson(),
      CartItem(service: sellerHub(5), quantity: 1).toStorageJson(),
      CartItem(service: acService(), quantity: 1).toStorageJson(),
    ]);
    final storage = _Storage(stored);
    final c = ProviderContainer(overrides: [secureStorageProvider.overrideWithValue(storage)]);
    addTearDown(c.dispose);
    c.read(cartProvider); // builds the notifier, which loads the saved cart
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(c.read(cartProvider).map((i) => i.service.title), ['Bread', 'AC Service']);
    expect(jsonDecode(storage.saved!) as List, hasLength(2)); // and the cleaned cart is what is saved
  });
}
