import 'package:calservices_customer/core/errors/api_error.dart';
import 'package:calservices_customer/core/network/api_client.dart';
import 'package:calservices_customer/features/booking/domain/cart_notifier.dart';
import 'package:calservices_customer/features/catalog/data/catalog_repository.dart';
import 'package:calservices_customer/features/catalog/domain/catalog_models.dart';
import 'package:calservices_customer/features/catalog/domain/catalog_providers.dart';
import 'package:decimal/decimal.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

class MockCatalogRepository extends CatalogRepository {
  MockCatalogRepository(this.services, this.categories, this.subcategories)
      : super(api: ApiClient.withDio(Dio()));

  final List<ServiceItem> services;
  final List<Category> categories;
  final List<Subcategory> subcategories;

  @override
  Future<Result<List<Category>>> getCategories() async => Success(categories);

  @override
  Future<Result<List<Subcategory>>> getSubServicesByCategory({required String categorySlug}) async =>
      Success(subcategories);

  @override
  Future<Result<List<ServiceItem>>> getServicesByCategory({
    int? categoryId,
    String? categorySlug,
    String? subcategorySlug,
  }) async =>
      Success(services);
}

ServiceItem _makeProduct(int id, String name, String slug, int price) {
  return ServiceItem(
    id: id,
    categoryId: 18,
    title: name,
    slug: slug,
    price: Decimal.fromInt(price),
    categorySlug: 'vegetables_groceries',
    categoryName: 'Farm-Fresh Vegetables & Groceries',
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
  });

  group('P0 Mandatory Regression Suite: Catalog and Cart Independence (Tests A through F)', () {
    final amla = _makeProduct(244, 'Amlaa (Nellikaai)', 'veg-amla', 64);
    final beetroot = _makeProduct(228, 'Beetroot', 'veg-beetroot', 37);
    final bitterGourd = _makeProduct(224, 'Bitter Gourd (Pavakkai)', 'veg-bitter-gourd', 17);
    final bottleGourd = _makeProduct(225, 'Bottle Gourd (Suraikkai)', 'veg-bottle-gourd', 25);

    final catalogProducts = [amla, beetroot, bitterGourd, bottleGourd];

    final vegCat = Category(
      id: 18,
      name: 'Farm-Fresh Vegetables & Groceries',
      slug: 'vegetables_groceries',
    );

    final subcats = [
      const Subcategory(id: 50, name: 'Farm-Fresh Vegetable', slug: 'vegetables'),
      const Subcategory(id: 51, name: 'Groceries', slug: 'groceries'),
    ];

    test('TEST A & B: Multi-item addition, appending without replacement, and quantity incrementing', () {
      final mockRepo = MockCatalogRepository(catalogProducts, [vegCat], subcats);
      final container = ProviderContainer(
        overrides: [
          catalogRepositoryProvider.overrideWithValue(mockRepo),
        ],
      );
      addTearDown(container.dispose);

      final notifier = container.read(cartProvider.notifier);

      // Initial state: Cart empty, catalog intact
      expect(container.read(cartProvider).isEmpty, isTrue);

      // Step 1: Add first item (Amlaa)
      notifier.addService(amla);
      var cart = container.read(cartProvider);
      expect(cart.length, equals(1));
      expect(cart[0].service.id, equals(244));
      expect(cart[0].quantity, equals(1));

      // Step 2: Add second item (Beetroot) -> MUST APPEND, not replace
      notifier.addService(beetroot);
      cart = container.read(cartProvider);
      expect(cart.length, equals(2));
      expect(cart.map((i) => i.service.id).toList(), equals([244, 228]));
      expect(cart.firstWhere((i) => i.service.id == 244).quantity, equals(1));
      expect(cart.firstWhere((i) => i.service.id == 228).quantity, equals(1));

      // Step 3: Add third item (Bitter Gourd)
      notifier.addService(bitterGourd);
      cart = container.read(cartProvider);
      expect(cart.length, equals(3));
      expect(cart.map((i) => i.service.id).toList(), equals([244, 228, 224]));

      // Step 4: Add fourth item (Bottle Gourd)
      notifier.addService(bottleGourd);
      cart = container.read(cartProvider);
      expect(cart.length, equals(4));
      expect(cart.map((i) => i.service.id).toList(), equals([244, 228, 224, 225]));

      // TEST B: Increase quantities: Amlaa -> x3, Beetroot -> x2
      notifier.updateQuantity(amla.id, 3);
      notifier.updateQuantity(beetroot.id, 2);

      cart = container.read(cartProvider);
      expect(cart.length, equals(4));
      expect(cart.firstWhere((i) => i.service.id == amla.id).quantity, equals(3));
      expect(cart.firstWhere((i) => i.service.id == beetroot.id).quantity, equals(2));
      expect(cart.firstWhere((i) => i.service.id == bitterGourd.id).quantity, equals(1));
      expect(cart.firstWhere((i) => i.service.id == bottleGourd.id).quantity, equals(1));

      // Total summary validation
      final summary = container.read(cartSummaryProvider);
      expect(summary.itemCount, equals(7)); // 3 + 2 + 1 + 1
      expect(
        summary.subtotal,
        equals(
          (Decimal.fromInt(64) * Decimal.fromInt(3)) +
          (Decimal.fromInt(37) * Decimal.fromInt(2)) +
          (Decimal.fromInt(17) * Decimal.fromInt(1)) +
          (Decimal.fromInt(25) * Decimal.fromInt(1)),
        ),
      );
    });

    test('TEST C & D: Category services provider retains full product list regardless of cart state', () async {
      final mockRepo = MockCatalogRepository(catalogProducts, [vegCat], subcats);
      final container = ProviderContainer(
        overrides: [
          catalogRepositoryProvider.overrideWithValue(mockRepo),
        ],
      );
      addTearDown(container.dispose);

      const param = CategoryServicesParam(
        categoryId: 18,
        categorySlug: 'vegetables_groceries',
      );

      // Load category services
      final servicesInitial = await container.read(categoryServicesProvider(param).future);
      expect(servicesInitial.length, equals(4));
      expect(servicesInitial.map((i) => i.id).toList(), equals([244, 228, 224, 225]));

      // Add items to cart
      container.read(cartProvider.notifier).addService(amla, quantity: 2);
      container.read(cartProvider.notifier).addService(beetroot, quantity: 1);

      // Verify category provider still returns full 4 items
      final servicesAfterAdd = await container.read(categoryServicesProvider(param).future);
      expect(servicesAfterAdd.length, equals(4));
      expect(servicesAfterAdd.map((i) => i.id).toList(), equals([244, 228, 224, 225]));
      expect(servicesAfterAdd.length, isNot(equals(container.read(cartProvider).length)));
    });

    test('TEST E & F: Removing items or clearing cart preserves category catalog', () async {
      final mockRepo = MockCatalogRepository(catalogProducts, [vegCat], subcats);
      final container = ProviderContainer(
        overrides: [
          catalogRepositoryProvider.overrideWithValue(mockRepo),
        ],
      );
      addTearDown(container.dispose);

      const param = CategoryServicesParam(
        categoryId: 18,
        categorySlug: 'vegetables_groceries',
      );

      final notifier = container.read(cartProvider.notifier);
      notifier.addService(amla);
      notifier.addService(beetroot);
      notifier.addService(bitterGourd);
      notifier.addService(bottleGourd);

      expect(container.read(cartProvider).length, equals(4));

      // TEST E: Remove Amlaa
      notifier.removeService(amla.id);
      var cart = container.read(cartProvider);
      expect(cart.length, equals(3));
      expect(cart.any((i) => i.service.id == amla.id), isFalse);

      // Catalog remains fully intact
      var catalog = await container.read(categoryServicesProvider(param).future);
      expect(catalog.length, equals(4));

      // TEST F: Remove ALL items (clear cart)
      notifier.clearCart();
      cart = container.read(cartProvider);
      expect(cart.isEmpty, isTrue);

      // Empty cart MUST NOT mean empty catalog
      catalog = await container.read(categoryServicesProvider(param).future);
      expect(catalog.length, equals(4));
      expect(catalog.map((i) => i.id).toList(), containsAll([244, 228, 224, 225]));
    });

    test('CATEGORY ID STABILITY: Category ID 18 remains constant across all transitions', () {
      expect(CatalogRepository.resolveCategoryId(18, 'vegetables_groceries'), equals(18));
      expect(CatalogRepository.resolveCategoryId(null, 'vegetables_groceries'), equals(18));
      expect(CatalogRepository.resolveCategoryId(null, 'farm-fresh-vegetables-groceries'), equals(18));
      expect(CatalogRepository.getCanonicalCategoryId('vegetables_groceries'), equals(18));
    });
  });
}
