import 'dart:convert';
import 'package:calservices_customer/core/network/api_client.dart';
import 'package:calservices_customer/core/storage/secure_storage.dart';
import 'package:calservices_customer/features/auth/data/auth_repository.dart';
import 'package:calservices_customer/features/auth/domain/auth_notifier.dart';
import 'package:calservices_customer/features/booking/domain/booking_models.dart';
import 'package:calservices_customer/features/booking/domain/cart_notifier.dart';
import 'package:calservices_customer/features/catalog/data/catalog_repository.dart';
import 'package:calservices_customer/features/catalog/domain/catalog_models.dart';
import 'package:decimal/decimal.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

// ── Mock Secure Storage ──────────────────────────────────────────────────────
class MockSecureStorage implements SecureStorage {
  final Map<String, String> _data = {};

  @override
  Future<String?> getAccessToken() async => _data['access_token'];

  @override
  Future<void> setAccessToken(String token) async => _data['access_token'] = token;

  @override
  Future<String?> getRefreshToken() async => _data['refresh_token'];

  @override
  Future<void> setRefreshToken(String token) async => _data['refresh_token'] = token;

  @override
  Future<String?> getUserJson() async => _data['user_json'];

  @override
  Future<void> setUserJson(String json) async => _data['user_json'] = json;

  @override
  Future<String?> getCartJson() async => _data['calservices_persistent_cart'];

  @override
  Future<void> setCartJson(String json) async =>
      _data['calservices_persistent_cart'] = json;

  @override
  Future<void> clearCartStorage() async =>
      _data.remove('calservices_persistent_cart');

  @override
  Future<String?> getSelectedAddressJson() async =>
      _data['calservices_selected_address'];

  @override
  Future<void> setSelectedAddressJson(String json) async =>
      _data['calservices_selected_address'] = json;

  @override
  Future<void> clearSelectedAddress() async =>
      _data.remove('calservices_selected_address');

  @override
  Future<void> clearAll() async => _data.clear();

  @override
  Future<bool> hasAccessToken() async {
    final token = await getAccessToken();
    return token != null && token.isNotEmpty;
  }
}

// ── Helper Test Fixtures ─────────────────────────────────────────────────────
ServiceItem createProduce({
  required int id,
  required String name,
  required String slug,
  required String price,
  String unit = '500g',
}) {
  return ServiceItem(
    id: id,
    title: name,
    slug: slug,
    price: Decimal.parse(price),
    unit: unit,
    categoryId: 18,
    categoryName: 'Farm-Fresh Vegetables & Groceries',
    categorySlug: 'vegetables_groceries',
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('P0 Bug #1: Grocery Cart & Category State Regression Tests', () {
    late MockSecureStorage mockStorage;
    late ProviderContainer container;

    final amla = createProduce(id: 227, name: 'Amla', slug: 'veg-amla', price: '45.00', unit: '250g');
    final beetroot = createProduce(id: 228, name: 'Beetroot', slug: 'veg-beetroot', price: '37.00', unit: '500g');
    final bitterGourd = createProduce(id: 229, name: 'Bitter Gourd', slug: 'veg-bitter-gourd', price: '42.00', unit: '500g');
    final greenZucchini = createProduce(id: 230, name: 'Green Zucchini', slug: 'veg-green-zucchini', price: '65.00', unit: '500g');

    setUp(() {
      mockStorage = MockSecureStorage();
      container = ProviderContainer(
        overrides: [
          secureStorageProvider.overrideWithValue(mockStorage),
        ],
      );
    });

    tearDown(() {
      container.dispose();
    });

    test('CART01: Add single grocery item to cart initializes with quantity 1', () {
      final notifier = container.read(cartProvider.notifier);
      notifier.addService(beetroot);

      final items = container.read(cartProvider);
      expect(items.length, 1);
      expect(items.first.service.id, 228);
      expect(items.first.service.title, 'Beetroot');
      expect(items.first.quantity, 1);
      expect(items.first.unitPrice, Decimal.parse('37.00'));
      expect(items.first.totalPrice, Decimal.parse('37.00'));
    });

    test('CART02: Increment quantity of existing grocery item (+ button) increases to 2, 3, etc.', () {
      final notifier = container.read(cartProvider.notifier);
      notifier.addService(beetroot);

      // Tap + button -> quantity becomes 2
      notifier.updateQuantity(beetroot.id, 2);
      expect(container.read(cartProvider).first.quantity, 2);
      expect(container.read(cartProvider).first.totalPrice, Decimal.parse('74.00'));

      // Tap + button -> quantity becomes 3
      notifier.updateQuantity(beetroot.id, 3);
      expect(container.read(cartProvider).first.quantity, 3);
      expect(container.read(cartProvider).first.totalPrice, Decimal.parse('111.00'));
    });

    test('CART03: Decrement quantity (- button) reduces quantity and removes at 0', () {
      final notifier = container.read(cartProvider.notifier);
      notifier.addService(beetroot, quantity: 3);
      expect(container.read(cartProvider).first.quantity, 3);

      // Decrement to 2
      notifier.updateQuantity(beetroot.id, 2);
      expect(container.read(cartProvider).first.quantity, 2);

      // Decrement to 1
      notifier.updateQuantity(beetroot.id, 1);
      expect(container.read(cartProvider).first.quantity, 1);

      // Decrement to 0 removes the item
      notifier.updateQuantity(beetroot.id, 0);
      expect(container.read(cartProvider).isEmpty, isTrue);
    });

    test('CART04: Multiple DIFFERENT products from same category coexist simultaneously in cart', () {
      final notifier = container.read(cartProvider.notifier);

      // Add Amla (qty: 1)
      notifier.addService(amla);
      // Add Beetroot (qty: 1)
      notifier.addService(beetroot);
      // Add Bitter Gourd (qty: 1)
      notifier.addService(bitterGourd);
      // Add Green Zucchini (qty: 1) and then increment to 2
      notifier.addService(greenZucchini);
      notifier.updateQuantity(greenZucchini.id, 2);

      final items = container.read(cartProvider);
      expect(items.length, 4, reason: 'All 4 distinct produce items must coexist in cart');

      expect(items[0].service.id, 227);
      expect(items[0].quantity, 1);
      expect(items[0].totalPrice, Decimal.parse('45.00'));

      expect(items[1].service.id, 228);
      expect(items[1].quantity, 1);
      expect(items[1].totalPrice, Decimal.parse('37.00'));

      expect(items[2].service.id, 229);
      expect(items[2].quantity, 1);
      expect(items[2].totalPrice, Decimal.parse('42.00'));

      expect(items[3].service.id, 230);
      expect(items[3].quantity, 2);
      expect(items[3].totalPrice, Decimal.parse('130.00'));

      final summary = container.read(cartSummaryProvider);
      expect(summary.itemCount, 5, reason: 'Total item units = 1 + 1 + 1 + 2 = 5');
      // Subtotal = 45 + 37 + 42 + 130 = 254
      expect(summary.subtotal, Decimal.parse('254.00'));
    });

    test('CART05: Cart multi-item persistence round-trip across local storage', () async {
      final item1 = CartItem(service: beetroot, quantity: 2);
      final item2 = CartItem(service: greenZucchini, quantity: 3);

      final serializedList = [item1.toStorageJson(), item2.toStorageJson()];
      final jsonString = jsonEncode(serializedList);

      await mockStorage.setCartJson(jsonString);

      final storedJson = await mockStorage.getCartJson();
      expect(storedJson, isNotNull);

      final decoded = jsonDecode(storedJson!) as List;
      final restoredItems = decoded
          .whereType<Map>()
          .map((m) => CartItem.fromStorageJson(Map<String, dynamic>.from(m)))
          .toList();

      expect(restoredItems.length, 2);
      expect(restoredItems[0].service.id, 228);
      expect(restoredItems[0].service.title, 'Beetroot');
      expect(restoredItems[0].service.unit, '500g');
      expect(restoredItems[0].service.flowType, CatalogFlowType.grocery);
      expect(restoredItems[0].quantity, 2);

      expect(restoredItems[1].service.id, 230);
      expect(restoredItems[1].service.title, 'Green Zucchini');
      expect(restoredItems[1].service.unit, '500g');
      expect(restoredItems[1].quantity, 3);
    });

    test('CART06: Quick Commerce fee rules (Delivery, Handling, Small Cart) calculate accurately', () {
      final notifier = container.read(cartProvider.notifier);

      // Scenario A: Small subtotal < 100 (e.g. Beetroot ₹37 x 1 = ₹37)
      notifier.addService(beetroot); // ₹37
      var summary = container.read(cartSummaryProvider);
      expect(summary.subtotal, Decimal.parse('37.00'));
      expect(summary.deliveryFee, Decimal.parse('15.00'), reason: 'Subtotal < 200 -> ₹15 delivery');
      expect(summary.handlingFee, Decimal.parse('2.00'));
      expect(summary.smallCartFee, Decimal.parse('5.00'), reason: 'Subtotal < 100 -> ₹5 small cart fee');
      // Total = 37 + 15 + 2 + 5 = 59
      expect(summary.total, Decimal.parse('59.00'));
      expect(summary.advancePayable, Decimal.parse('59.00'), reason: 'Grocery orders are 100% advance');
      expect(summary.balancePayable, Decimal.zero);

      // Scenario B: Medium subtotal between 100 and 200 (e.g. Beetroot x 3 = ₹111)
      notifier.updateQuantity(beetroot.id, 3); // ₹111
      summary = container.read(cartSummaryProvider);
      expect(summary.subtotal, Decimal.parse('111.00'));
      expect(summary.deliveryFee, Decimal.parse('15.00'));
      expect(summary.handlingFee, Decimal.parse('2.00'));
      expect(summary.smallCartFee, Decimal.zero, reason: 'Subtotal >= 100 -> ₹0 small cart fee');
      // Total = 111 + 15 + 2 = 128
      expect(summary.total, Decimal.parse('128.00'));

      // Scenario C: Free delivery subtotal >= 200 (e.g. Beetroot x 3 [₹111] + Green Zucchini x 2 [₹130] = ₹241)
      notifier.addService(greenZucchini, quantity: 2);
      summary = container.read(cartSummaryProvider);
      expect(summary.subtotal, Decimal.parse('241.00'));
      expect(summary.deliveryFee, Decimal.zero, reason: 'Subtotal >= 200 -> FREE delivery');
      expect(summary.handlingFee, Decimal.parse('2.00'));
      expect(summary.smallCartFee, Decimal.zero);
      // Total = 241 + 0 + 2 = 243
      expect(summary.total, Decimal.parse('243.00'));
    });

    test('CART07: Unique service.id identity prevents collisions between different services', () {
      final notifier = container.read(cartProvider.notifier);
      notifier.addService(amla);
      notifier.addService(beetroot);

      // Updating Beetroot must NOT affect Amla
      notifier.updateQuantity(beetroot.id, 4);

      final items = container.read(cartProvider);
      final amlaItem = items.firstWhere((i) => i.service.id == amla.id);
      final beetItem = items.firstWhere((i) => i.service.id == beetroot.id);

      expect(amlaItem.quantity, 1);
      expect(beetItem.quantity, 4);
    });

    test('CART08: Catalog repository category ID resolution is accurate and resilient', () {
      expect(CatalogRepository.resolveCategoryId(null, 'vegetables_groceries'), 18);
      expect(CatalogRepository.resolveCategoryId(null, 'farm-fresh-vegetables-groceries'), 18);
      expect(CatalogRepository.resolveCategoryId(null, 'farm_fresh'), 18);
      expect(CatalogRepository.resolveCategoryId(null, 'produce'), 18);
      expect(CatalogRepository.resolveCategoryId(null, 'ac_appliance'), 15);
      expect(CatalogRepository.resolveCategoryId(null, 'electrician_plumber_carpenter'), 16);
      expect(CatalogRepository.resolveCategoryId(null, 'home_cleaning'), 13);
      expect(CatalogRepository.resolveCategoryId(null, 'pest_control'), 14);
    });
  });

  group('P0 Bug #2: Authentication State Consistency Regression Tests', () {
    late MockSecureStorage mockStorage;

    setUp(() {
      mockStorage = MockSecureStorage();
    });

    test('AUTH01: Startup restoration with valid access token establishes AuthAuthenticated', () async {
      await mockStorage.setAccessToken('valid_test_token_jwt_xyz');
      await mockStorage.setUserJson(jsonEncode({
        'id': 101,
        'phone': '9876543210',
        'name': 'Praveen',
        'email': 'praveen@example.com',
        'is_guest': false,
      }));

      final repo = AuthRepository(
        api: ApiClient.withDio(Dio()),
        storage: mockStorage,
      );

      final restored = await repo.restoreSession();
      expect(restored, isNotNull);
      expect(restored!.id, 101);
      expect(restored.phone, '9876543210');
      expect(restored.name, 'Praveen');
      expect(restored.isGuest, isFalse);
    });

    test('AUTH02: Startup restoration without access token purges stale profile and returns null', () async {
      // Stale user JSON in storage from old session, but NO access token
      await mockStorage.setUserJson(jsonEncode({
        'id': 999,
        'phone': '9999999999',
        'name': 'Stale User',
      }));

      final repo = AuthRepository(
        api: ApiClient.withDio(Dio()),
        storage: mockStorage,
      );

      final restored = await repo.restoreSession();
      expect(restored, isNull, reason: 'Without access token, session must be null');

      final cachedUser = await mockStorage.getUserJson();
      expect(cachedUser, isNull, reason: 'Stale user profile must be purged from storage');
    });

    test('AUTH03: currentUserProvider and isUserAuthenticatedProvider reflect AuthState', () {
      final container = ProviderContainer();

      // Initial state: AuthLoading -> not authenticated
      expect(container.read(isUserAuthenticatedProvider), isFalse);
      expect(container.read(currentUserProvider), isNull);

      container.dispose();
    });

    test('AUTH04: Logout clears all stored credentials', () async {
      await mockStorage.setAccessToken('test_access');
      await mockStorage.setRefreshToken('test_refresh');
      await mockStorage.setUserJson(jsonEncode({'id': 1, 'phone': '9876543210'}));

      final repo = AuthRepository(
        api: ApiClient.withDio(Dio()),
        storage: mockStorage,
      );

      await repo.logout();

      expect(await mockStorage.getAccessToken(), isNull);
      expect(await mockStorage.getRefreshToken(), isNull);
      expect(await mockStorage.getUserJson(), isNull);
      expect(await mockStorage.hasAccessToken(), isFalse);
    });

    test('AUTH05: Guest PendingCartAction preserves both addToCart and buy action types', () {
      final container = ProviderContainer();
      final produce = createProduce(id: 228, name: 'Beetroot', slug: 'veg-beetroot', price: '37.00');

      // Test PendingCartAction for ADD
      final addAction = PendingCartAction(
        service: produce,
        actionType: PendingCartActionType.addToCart,
        quantity: 2,
        returnPath: '/categories/vegetables_groceries',
      );
      container.read(pendingActionProvider.notifier).setAction(addAction);

      final pending = container.read(pendingActionProvider);
      expect(pending, isNotNull);
      expect(pending!.service.id, 228);
      expect(pending.actionType, PendingCartActionType.addToCart);
      expect(pending.quantity, 2);
      expect(pending.returnPath, '/categories/vegetables_groceries');

      // Fulfill action
      container.read(pendingActionProvider.notifier).clear();
      expect(container.read(pendingActionProvider), isNull);

      // Test PendingCartAction for BUY
      final buyAction = PendingCartAction(
        service: produce,
        actionType: PendingCartActionType.buy,
        quantity: 1,
        returnPath: '/cart',
      );
      container.read(pendingActionProvider.notifier).setAction(buyAction);
      expect(container.read(pendingActionProvider)!.actionType, PendingCartActionType.buy);

      container.dispose();
    });
  });
}
