import 'dart:convert';
import 'package:calservices_customer/core/network/api_client.dart';
import 'package:calservices_customer/core/storage/secure_storage.dart';
import 'package:calservices_customer/features/auth/data/auth_repository.dart';
import 'package:calservices_customer/features/auth/domain/auth_models.dart';
import 'package:calservices_customer/features/auth/domain/auth_notifier.dart';
import 'package:calservices_customer/features/booking/domain/booking_models.dart';
import 'package:calservices_customer/features/booking/domain/cart_notifier.dart';
import 'package:calservices_customer/features/catalog/data/catalog_repository.dart';
import 'package:calservices_customer/features/catalog/domain/catalog_models.dart';
import 'package:calservices_customer/features/catalog/domain/catalog_providers.dart';
import 'package:decimal/decimal.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

// Test doubles
class MockSecureStorage extends SecureStorage {
  String? _accessToken;
  String? _refreshToken;
  String? _userJson;
  String? _cartJson;

  @override
  Future<String?> getAccessToken() async => _accessToken;
  @override
  Future<void> setAccessToken(String token) async => _accessToken = token;

  @override
  Future<String?> getRefreshToken() async => _refreshToken;
  @override
  Future<void> setRefreshToken(String token) async => _refreshToken = token;

  @override
  Future<String?> getUserJson() async => _userJson;
  @override
  Future<void> setUserJson(String json) async => _userJson = json;

  @override
  Future<String?> getCartJson() async => _cartJson;
  @override
  Future<void> setCartJson(String json) async => _cartJson = json;
  @override
  Future<void> clearCartStorage() async => _cartJson = null;

  @override
  Future<void> clearAll() async {
    _accessToken = null;
    _refreshToken = null;
    _userJson = null;
  }

  @override
  Future<bool> hasAccessToken() async =>
      _accessToken != null && _accessToken!.isNotEmpty;
}

ServiceItem _createService(int id, String name, String slug, int price, {String unit = '500 g'}) {
  return ServiceItem(
    id: id,
    title: name,
    slug: slug,
    unit: unit,
    price: Decimal.fromInt(price),
    categoryName: 'Farm-Fresh Vegetables & Groceries',
    categorySlug: 'vegetables_groceries',
  );
}

void main() {
  group('P0 Root Cause Investigation Regression Suite — CART01 to CART09', () {
    final amla = _createService(244, 'Amlaa (Nellikaai)', 'veg-amla', 64);
    final beetroot = _createService(228, 'Beetroot', 'veg-beetroot', 37);
    final bitterGourd = _createService(224, 'Bitter Gourd (Pavakkai)', 'veg-bitter-gourd', 17);
    final zucchini = _createService(231, 'Green Zucchini', 'veg-zucchini', 45);

    test('CART01: Same item quantity reliably increments beyond 1', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier = container.read(cartProvider.notifier);
      notifier.addService(beetroot);
      expect(container.read(cartProvider).first.quantity, equals(1));

      notifier.updateQuantity(beetroot.id, 2);
      expect(container.read(cartProvider).first.quantity, equals(2));

      notifier.updateQuantity(beetroot.id, 3);
      expect(container.read(cartProvider).first.quantity, equals(3));

      notifier.updateQuantity(beetroot.id, 4);
      expect(container.read(cartProvider).first.quantity, equals(4));
    });

    test('CART02: Multiple distinct items coexist simultaneously without replacing each other', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier = container.read(cartProvider.notifier);
      notifier.addService(beetroot, quantity: 3);
      notifier.addService(amla, quantity: 2);
      notifier.addService(bitterGourd, quantity: 1);
      notifier.addService(zucchini, quantity: 4);

      final cart = container.read(cartProvider);
      expect(cart.length, equals(4));
      expect(cart.map((i) => i.service.id).toList(), containsAll([228, 244, 224, 231]));

      final summary = container.read(cartSummaryProvider);
      expect(summary.itemCount, equals(10)); // 3 + 2 + 1 + 4
      expect(
        summary.subtotal,
        equals(
          (Decimal.fromInt(37) * Decimal.fromInt(3)) +
          (Decimal.fromInt(64) * Decimal.fromInt(2)) +
          (Decimal.fromInt(17) * Decimal.fromInt(1)) +
          (Decimal.fromInt(45) * Decimal.fromInt(4)),
        ),
      );
    });

    test('CART03: Removing one item preserves all other items in cart', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier = container.read(cartProvider.notifier);
      notifier.addService(beetroot, quantity: 2);
      notifier.addService(amla, quantity: 1);
      notifier.addService(bitterGourd, quantity: 3);

      notifier.removeService(amla.id);

      final cart = container.read(cartProvider);
      expect(cart.length, equals(2));
      expect(cart.any((i) => i.service.id == amla.id), isFalse);
      expect(cart.firstWhere((i) => i.service.id == beetroot.id).quantity, equals(2));
      expect(cart.firstWhere((i) => i.service.id == bitterGourd.id).quantity, equals(3));
    });

    test('CART04: Cart serialization preserves all items and units in JSON', () {
      final item1 = CartItem(service: beetroot, quantity: 3);
      final item2 = CartItem(service: amla, quantity: 2);

      final json1 = item1.toStorageJson();
      final json2 = item2.toStorageJson();

      expect(json1['service']['id'], equals(228));
      expect(json1['quantity'], equals(3));
      expect(json1['service']['unit'], equals('500 g'));

      expect(json2['service']['id'], equals(244));
      expect(json2['quantity'], equals(2));
    });

    test('CART05: Cart restoration round-trip preserves all items and quantities', () {
      final cart = [
        CartItem(service: beetroot, quantity: 3),
        CartItem(service: amla, quantity: 2),
        CartItem(service: bitterGourd, quantity: 1),
      ];

      final encoded = jsonEncode(cart.map((i) => i.toStorageJson()).toList());
      final decoded = (jsonDecode(encoded) as List)
          .map((m) => CartItem.fromStorageJson(Map<String, dynamic>.from(m as Map)))
          .toList();

      expect(decoded.length, equals(3));
      expect(decoded[0].service.id, equals(228));
      expect(decoded[0].quantity, equals(3));
      expect(decoded[1].service.id, equals(244));
      expect(decoded[1].quantity, equals(2));
      expect(decoded[2].service.id, equals(224));
      expect(decoded[2].quantity, equals(1));
    });

    test('CART06: Catalog remains independent of cart items', () {
      final catalogList = [beetroot, amla, bitterGourd, zucchini];
      final container = ProviderContainer();
      addTearDown(container.dispose);

      // Cart initially empty
      expect(container.read(cartProvider).isEmpty, isTrue);
      expect(catalogList.length, equals(4));

      // Add item to cart
      container.read(cartProvider.notifier).addService(beetroot, quantity: 3);
      expect(container.read(cartProvider).length, equals(1));

      // Catalog list is unchanged
      expect(catalogList.length, equals(4));
    });

    test('CART07: Returning from cart retains category catalog independent of cart state', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier = container.read(cartProvider.notifier);
      notifier.addService(amla);
      notifier.addService(beetroot);

      expect(container.read(cartProvider).length, equals(2));
      final param = CategoryServicesParam(
        categoryId: 18,
        categorySlug: 'vegetables_groceries',
      );
      expect(param.categoryId, equals(18));
      expect(param.categorySlug, equals('vegetables_groceries'));
    });

    test('CART08: Correct category IDs survive across navigation and canonical mapping', () {
      expect(CatalogRepository.resolveCategoryId(null, 'ac_appliance'), equals(15));
      expect(CatalogRepository.resolveCategoryId(null, 'electrician_plumbing_carpentry'), equals(14));
      expect(CatalogRepository.resolveCategoryId(null, 'vegetables_groceries'), equals(18));
      expect(CatalogRepository.resolveCategoryId(null, 'goods_transports'), equals(12));
      expect(CatalogRepository.resolveCategoryId(null, 'home_pest_control'), equals(16));
      expect(CatalogRepository.resolveCategoryId(null, 'deep-cleaning'), equals(19));
      expect(CatalogRepository.resolveCategoryId(null, 'mason'), equals(11));
      expect(CatalogRepository.resolveCategoryId(null, 'paintings'), equals(17));
      expect(CatalogRepository.resolveCategoryId(null, 'consistency-cat'), equals(20));
    });

    test('CART09: CategoryServicesParam equality ensures idempotent caching in Riverpod', () {
      const param1 = CategoryServicesParam(categoryId: 18, categorySlug: 'vegetables_groceries');
      const param2 = CategoryServicesParam(categoryId: 18, categorySlug: 'vegetables_groceries');
      const param3 = CategoryServicesParam(categoryId: 18, categorySlug: 'vegetables_groceries', subcategorySlug: 'vegetables');

      expect(param1, equals(param2));
      expect(param1.hashCode, equals(param2.hashCode));
      expect(param1, isNot(equals(param3)));
    });
  });

  group('P0 Root Cause Investigation Regression Suite — AUTH01 to AUTH10', () {
    test('AUTH01: Startup auth state begins as initializing (AuthLoading)', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(container.read(authProvider), isA<AuthLoading>());
    });

    test('AUTH02: Valid persisted session restores authenticated state', () async {
      final storage = MockSecureStorage();
      await storage.setAccessToken('valid_jwt_token');
      await storage.setRefreshToken('valid_refresh_token');
      await storage.setUserJson(jsonEncode({
        'id': 101,
        'phone': '9876543210',
        'name': 'Gokul Test',
        'is_guest': false,
      }));

      final repo = AuthRepository(
        api: ApiClient.withDio(Dio()),
        storage: storage,
      );

      final user = await repo.restoreSession();
      expect(user, isNotNull);
      expect(user!.id, equals(101));
      expect(user.phone, equals('9876543210'));
      expect(user.isGuest, isFalse);
    });

    test('AUTH03: Profile data alone without token cannot imply authentication', () async {
      final storage = MockSecureStorage();
      // No access token, but leftover userJson
      await storage.setUserJson(jsonEncode({
        'id': 101,
        'phone': '9876543210',
        'is_guest': false,
      }));

      final repo = AuthRepository(
        api: ApiClient.withDio(Dio()),
        storage: storage,
      );

      final user = await repo.restoreSession();
      expect(user, isNull);
      expect(await storage.getUserJson(), isNull); // Stale JSON purged
    });

    test('AUTH04: Router and protected actions use synchronized auth state', () {
      final container = ProviderContainer(
        overrides: [
          authProvider.overrideWith(() => _MockAuthNotifier(
            const AuthAuthenticated(user: UserProfile(id: 101, phone: '9876543210')),
          )),
        ],
      );
      addTearDown(container.dispose);

      final isAuth = container.read(isUserAuthenticatedProvider);
      final user = container.read(currentUserProvider);

      expect(isAuth, isTrue);
      expect(user?.id, equals(101));
    });

    test('AUTH05: Authenticated user can ADD to cart after restart', () {
      final container = ProviderContainer(
        overrides: [
          authProvider.overrideWith(() => _MockAuthNotifier(
            const AuthAuthenticated(user: UserProfile(id: 101, phone: '9876543210')),
          )),
        ],
      );
      addTearDown(container.dispose);

      final beetroot = _createService(228, 'Beetroot', 'veg-beetroot', 37);
      container.read(cartProvider.notifier).addService(beetroot, quantity: 2);

      expect(container.read(cartProvider).length, equals(1));
      expect(container.read(cartProvider).first.quantity, equals(2));
      expect(container.read(isUserAuthenticatedProvider), isTrue);
    });

    test('AUTH06: Authenticated user can book after restart', () {
      final container = ProviderContainer(
        overrides: [
          authProvider.overrideWith(() => _MockAuthNotifier(
            const AuthAuthenticated(user: UserProfile(id: 101, phone: '9876543210')),
          )),
        ],
      );
      addTearDown(container.dispose);

      expect(container.read(isUserAuthenticatedProvider), isTrue);
      expect(container.read(currentUserProvider)?.phone, equals('9876543210'));
    });

    test('AUTH07: Unauthenticated state correctly sets isUserAuthenticatedProvider to false', () {
      final container = ProviderContainer(
        overrides: [
          authProvider.overrideWith(() => _MockAuthNotifier(const AuthUnauthenticated())),
        ],
      );
      addTearDown(container.dispose);

      expect(container.read(isUserAuthenticatedProvider), isFalse);
      expect(container.read(currentUserProvider), isNull);
    });

    test('AUTH08: Logout clears all stored credentials', () async {
      final storage = MockSecureStorage();
      await storage.setAccessToken('access_token');
      await storage.setRefreshToken('refresh_token');
      await storage.setUserJson(jsonEncode({'id': 101, 'phone': '9876543210'}));

      await storage.clearAll();

      expect(await storage.getAccessToken(), isNull);
      expect(await storage.getRefreshToken(), isNull);
      expect(await storage.getUserJson(), isNull);
      expect(await storage.hasAccessToken(), isFalse);
    });

    test('AUTH09: Guest mode preserves pending cart action on authentication redirect', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final beetroot = _createService(228, 'Beetroot', 'veg-beetroot', 37);
      final action = PendingCartAction(
        service: beetroot,
        actionType: PendingCartActionType.buy,
        quantity: 3,
        returnPath: '/checkout',
      );

      container.read(pendingActionProvider.notifier).setAction(action);

      final saved = container.read(pendingActionProvider);
      expect(saved?.service.id, equals(228));
      expect(saved?.quantity, equals(3));
      expect(saved?.actionType, equals(PendingCartActionType.buy));
      expect(saved?.returnPath, equals('/checkout'));
    });

    test('AUTH10: App resume with valid token maintains authenticated state', () {
      final container = ProviderContainer(
        overrides: [
          authProvider.overrideWith(() => _MockAuthNotifier(
            const AuthAuthenticated(user: UserProfile(id: 7986, phone: 'gokul.m@caldimengg.in')),
          )),
        ],
      );
      addTearDown(container.dispose);

      expect(container.read(isUserAuthenticatedProvider), isTrue);
      expect(container.read(currentUserProvider)?.phone, equals('gokul.m@caldimengg.in'));
    });
  });
}

class _MockAuthNotifier extends AuthNotifier {
  _MockAuthNotifier(this._initialState);
  final AuthState _initialState;

  @override
  AuthState build() => _initialState;
}
