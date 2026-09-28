import 'package:calservices_customer/core/errors/api_error.dart';
import 'package:calservices_customer/core/network/api_client.dart';
import 'package:calservices_customer/features/booking/domain/cart_notifier.dart';
import 'package:calservices_customer/features/catalog/data/catalog_repository.dart';
import 'package:calservices_customer/features/catalog/domain/catalog_models.dart';
import 'package:calservices_customer/features/catalog/presentation/screens/category_detail_screen.dart';
import 'package:decimal/decimal.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

class MockCatalogRepo extends CatalogRepository {
  MockCatalogRepo(this.services, this.categories, this.subcategories)
      : super(api: ApiClient.withDio(Dio()));

  final List<ServiceItem> services;
  final List<Category> categories;
  final List<Subcategory> subcategories;

  @override
  Future<Result<List<Category>>> getCategories() async {
    return Success(categories);
  }

  @override
  Future<Result<List<Subcategory>>> getSubServicesByCategory({required String categorySlug}) async {
    return Success(subcategories);
  }

  @override
  Future<Result<List<ServiceItem>>> getServicesByCategory({
    int? categoryId,
    String? categorySlug,
    String? subcategorySlug,
  }) async {
    return Success(services);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
  });

  final amla = ServiceItem(
    id: 244,
    categoryId: 18,
    title: 'Amlaa (Nellikaai)',
    slug: 'veg-amla',
    price: Decimal.fromInt(64),
    categorySlug: 'vegetables_groceries',
    categoryName: 'Farm-Fresh Vegetables & Groceries',
  );

  final beetroot = ServiceItem(
    id: 228,
    categoryId: 18,
    title: 'Beetroot',
    slug: 'veg-beetroot',
    price: Decimal.fromInt(37),
    categorySlug: 'vegetables_groceries',
    categoryName: 'Farm-Fresh Vegetables & Groceries',
  );

  final bitterGourd = ServiceItem(
    id: 224,
    categoryId: 18,
    title: 'Bitter Gourd (Pavakkai)',
    slug: 'veg-bitter-gourd',
    price: Decimal.fromInt(17),
    categorySlug: 'vegetables_groceries',
    categoryName: 'Farm-Fresh Vegetables & Groceries',
  );

  final bottleGourd = ServiceItem(
    id: 225,
    categoryId: 18,
    title: 'Bottle Gourd (Suraikkai)',
    slug: 'veg-bottle-gourd',
    price: Decimal.fromInt(25),
    categorySlug: 'vegetables_groceries',
    categoryName: 'Farm-Fresh Vegetables & Groceries',
  );

  final allProducts = [amla, beetroot, bitterGourd, bottleGourd];

  final vegCategory = Category(
    id: 18,
    name: 'Farm-Fresh Vegetables & Groceries',
    slug: 'vegetables_groceries',
  );

  final subcats = [
    const Subcategory(id: 50, name: 'Farm-Fresh Vegetable', slug: 'vegetables'),
    const Subcategory(id: 51, name: 'Groceries', slug: 'groceries'),
  ];

  testWidgets('STEP-BY-STEP REPRODUCTION: Multi-item ADD and category re-entry with active cart', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final mockRepo = MockCatalogRepo(allProducts, [vegCategory], subcats);

    final container = ProviderContainer(
      overrides: [
        catalogRepositoryProvider.overrideWithValue(mockRepo),
      ],
    );
    addTearDown(container.dispose);

    // Step 1: Open Farm-Fresh Vegetables & Groceries
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: CategoryDetailScreen(
            categorySlug: 'vegetables_groceries',
          ),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // Step 2: Press ADD on Amlaa
    final addButtons = find.text('ADD');
    expect(addButtons, findsNWidgets(4));

    // Tap first ADD (Amlaa)
    await tester.tap(addButtons.first);
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));

    // Amlaa should now show quantity stepper '1'
    expect(container.read(cartProvider).length, equals(1));
    expect(container.read(cartProvider).first.service.id, equals(244));
    expect(container.read(cartProvider).first.quantity, equals(1));

    // Step 3: Press ADD on Beetroot (now first 'ADD' button in remaining 3)
    final remainingAddButtons = find.text('ADD');
    expect(remainingAddButtons, findsNWidgets(3));

    await tester.tap(remainingAddButtons.first); // Beetroot
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));

    // Verify both Amlaa and Beetroot are in cart
    final cartAfterSecondAdd = container.read(cartProvider);
    expect(cartAfterSecondAdd.length, equals(2));
    expect(cartAfterSecondAdd.map((i) => i.service.id).toList(), containsAll([244, 228]));

    // Step 4 & 5: Simulate Navigate away to Home and back to CategoryDetailScreen
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: CategoryDetailScreen(
            categorySlug: 'vegetables_groceries',
          ),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // Verify all 4 products ARE STILL VISIBLE
    expect(find.text('Amlaa (Nellikaai)'), findsOneWidget);
    expect(find.text('Beetroot'), findsOneWidget);
    expect(find.text('Bitter Gourd (Pavakkai)'), findsOneWidget);
    expect(find.text('Bottle Gourd (Suraikkai)'), findsOneWidget);

    // Bottom cart bar should show 2 ITEMS
    expect(find.text('2 ITEMS'), findsOneWidget);
    expect(find.text('Go to Cart'), findsOneWidget);
  });
}
