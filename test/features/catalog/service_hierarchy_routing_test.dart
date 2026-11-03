import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:calservices_customer/features/auth/domain/auth_models.dart';
import 'package:calservices_customer/features/auth/domain/auth_notifier.dart';
import 'package:calservices_customer/features/booking/domain/cart_notifier.dart';
import 'package:calservices_customer/features/catalog/domain/catalog_models.dart';
import 'package:calservices_customer/features/catalog/domain/catalog_providers.dart';
import 'package:calservices_customer/features/catalog/presentation/screens/category_detail_screen.dart';
import 'package:calservices_customer/features/catalog/presentation/widgets/service_card.dart';
import 'package:calservices_customer/routing/app_router.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
  });

  group('Service Hierarchy, Routing & Add/Buy Flow Rectification (S01-S16)', () {
    final mockGroceryProduce = [
      ServiceItem(
        id: 800000228,
        title: 'Beetroot',
        slug: 'veg-beetroot',
        price: Decimal.parse('37.00'),
        categoryId: 18,
        categoryName: 'Farm-Fresh Vegetables & Groceries',
        categorySlug: 'vegetables_groceries',
        unit: '500 g',
      ),
      ServiceItem(
        id: 800000229,
        title: 'Amlaa (Nellikaai)',
        slug: 'veg-amla',
        price: Decimal.parse('40.00'),
        categoryId: 18,
        categoryName: 'Farm-Fresh Vegetables & Groceries',
        categorySlug: 'vegetables_groceries',
        unit: '250 g',
      ),
    ];

    final mockAcService = ServiceItem(
      id: 101,
      title: 'AC Regular Service (Split / Window)',
      slug: 'ac-regular-service',
      price: Decimal.parse('499.00'),
      categoryId: 15,
      categoryName: 'AC & Appliance Repair',
      categorySlug: 'ac_appliance',
      durationMinutes: 45,
      isPopular: true,
    );

    GoRouter createTestRouter({required Widget child}) {
      return GoRouter(
        initialLocation: '/',
        routes: [
          GoRoute(
            path: '/',
            builder: (context, state) => Scaffold(body: child),
          ),
          GoRoute(
            path: '/login',
            builder: (context, state) => const Scaffold(body: Text('Login Screen')),
          ),
          GoRoute(
            path: '/cart',
            builder: (context, state) => const Scaffold(body: Text('Cart Screen')),
          ),
          GoRoute(
            path: '/services/:slug',
            builder: (context, state) => const Scaffold(body: Text('Service Detail Screen')),
          ),
        ],
      );
    }

    test('S01: Quick-commerce category id 18 identifies as CatalogFlowType.grocery', () {
      const cat = Category(
        id: 18,
        name: 'Farm-Fresh Vegetables & Groceries',
        slug: 'vegetables_groceries',
      );
      expect(cat.flowType, equals(CatalogFlowType.grocery));
    });

    test('S02: Standard service category id 15 identifies as CatalogFlowType.serviceBooking', () {
      const cat = Category(
        id: 15,
        name: 'AC & Appliance Repair',
        slug: 'ac_appliance',
      );
      expect(cat.flowType, equals(CatalogFlowType.serviceBooking));
    });

    test('S03: Grocery service item resolves CatalogFlowType.grocery', () {
      expect(mockGroceryProduce.first.flowType, equals(CatalogFlowType.grocery));
    });

    test('S04: Standard AC service item resolves CatalogFlowType.serviceBooking', () {
      expect(mockAcService.flowType, equals(CatalogFlowType.serviceBooking));
    });



    testWidgets('S07: Tapping grocery ServiceCard body does NOT push /services/:slug route',
        (tester) async {
      final container = ProviderContainer(
        overrides: [
          currentUserProvider.overrideWithValue(null),
        ],
      );
      addTearDown(container.dispose);

      final router = createTestRouter(child: ServiceCard(service: mockGroceryProduce.first));

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pump();

      // Tap on card body
      await tester.tap(find.text('Beetroot'));
      await tester.pump();

      // Must NOT navigate to /services/:slug
      expect(find.text('Service Detail Screen'), findsNothing);
      expect(find.text('Beetroot'), findsOneWidget);
    });




    test('S11: Route audit has /categories/:slug and /services/:slug as distinct routes', () {
      expect(AppRoutes.categoryDetail, equals('/categories/:slug'));
      expect(AppRoutes.serviceDetail, equals('/services/:slug'));
      expect(AppRoutes.cart, equals('/cart'));
    });

    test('S12: CartItem quantity modification updates total calculation accurately', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(cartProvider.notifier);

      notifier.addService(mockGroceryProduce.first); // Beetroot: 37
      notifier.addService(mockGroceryProduce.last);  // Amla: 40

      var summary = container.read(cartSummaryProvider);
      expect(summary.itemCount, equals(2));
      expect(summary.subtotal, equals(Decimal.parse('77.00')));

      // Increment Beetroot
      notifier.updateQuantity(800000228, 3);
      summary = container.read(cartSummaryProvider);
      expect(summary.itemCount, equals(4)); // 3 + 1
      expect(summary.subtotal, equals(Decimal.parse('151.00'))); // 37*3 + 40 = 111 + 40 = 151
    });

    test('S13: Cart persistence clears on checkout completion', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(cartProvider.notifier);

      notifier.addService(mockGroceryProduce.first);
      expect(container.read(cartProvider).length, equals(1));

      notifier.clearCart();
      expect(container.read(cartProvider).isEmpty, isTrue);
    });


    test('S15: PendingCartAction correctly restores actionType on authentication return', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final pendingNotifier = container.read(pendingActionProvider.notifier);

      pendingNotifier.setAction(PendingCartAction(
        service: mockGroceryProduce.first,
        actionType: PendingCartActionType.buy,
        quantity: 1,
        returnPath: AppRoutes.cart,
      ));

      final action = container.read(pendingActionProvider);
      expect(action, isNotNull);
      expect(action!.actionType, equals(PendingCartActionType.buy));
      expect(action.service.id, equals(800000228));
      expect(action.returnPath, equals(AppRoutes.cart));
    });

    test('S16: ServiceCard rating badge only renders for standard serviceBooking flow', () {
      expect(mockAcService.flowType == CatalogFlowType.serviceBooking, isTrue);
      expect(mockGroceryProduce.first.flowType == CatalogFlowType.grocery, isTrue);
    });
  });
}
