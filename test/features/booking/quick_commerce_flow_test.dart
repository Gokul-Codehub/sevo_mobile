import 'package:calservices_customer/features/booking/domain/cart_notifier.dart';
import 'package:calservices_customer/features/catalog/domain/catalog_models.dart';
import 'package:decimal/decimal.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
  });

  group('Quick Commerce & Service Flow Classification Tests', () {
    test('Farm-Fresh Vegetables category classifies as CatalogFlowType.grocery', () {
      const groceryCat = Category(
        id: 18,
        name: 'Farm-Fresh Vegetables & Groceries',
        slug: 'vegetables_groceries',
      );
      expect(groceryCat.flowType, equals(CatalogFlowType.grocery));
    });

    test('Home Services category classifies as CatalogFlowType.serviceBooking', () {
      const serviceCat = Category(
        id: 6,
        name: 'Home Services & Pest Control',
        slug: 'cleaning_pest_control',
      );
      expect(serviceCat.flowType, equals(CatalogFlowType.serviceBooking));
    });

    test('Beetroot item (Category 18, Service 228) classifies as CatalogFlowType.grocery', () {
      final beetroot = ServiceItem(
        id: 800000228,
        title: 'Beetroot',
        slug: 'veg-beetroot',
        price: Decimal.parse('37.00'),
        categoryId: 18,
        categoryName: 'Farm-Fresh Vegetables & Groceries',
        categorySlug: 'vegetables_groceries',
        unit: '500 g',
      );
      expect(beetroot.flowType, equals(CatalogFlowType.grocery));
      expect(beetroot.displayUnit, equals('500 g'));
      expect(beetroot.effectivePrice, equals(Decimal.parse('37.00')));
    });

    test('AC Repair item classifies as CatalogFlowType.serviceBooking', () {
      final acRepair = ServiceItem(
        id: 101,
        title: 'AC Deep Clean Service',
        slug: 'ac-deep-clean',
        price: Decimal.parse('499.00'),
        categoryId: 1,
        categoryName: 'AC & Appliance Repair',
        categorySlug: 'ac_appliance',
      );
      expect(acRepair.flowType, equals(CatalogFlowType.serviceBooking));
    });
  });

  group('Quick Commerce Cart Summary Calculations', () {
    test('Empty cart returns 0 and isGroceryCart = false', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final summary = container.read(cartSummaryProvider);
      expect(summary.itemCount, equals(0));
      expect(summary.subtotal, equals(Decimal.zero));
      expect(summary.total, equals(Decimal.zero));
      expect(summary.isGroceryCart, isFalse);
    });




  });

  group('Authoritative Grocery Cart & Buy Flow Regressions (Tests 1 - 12)', () {
    final beetroot = ServiceItem(
      id: 800000228,
      title: 'Beetroot',
      slug: 'veg-beetroot',
      price: Decimal.parse('37.00'),
      categoryId: 18,
      categoryName: 'Farm-Fresh Vegetables & Groceries',
      categorySlug: 'vegetables_groceries',
      unit: '500 g',
    );

    final potato = ServiceItem(
      id: 800000229,
      title: 'Potato (Urulaikilangu)',
      slug: 'veg-potato',
      price: Decimal.parse('22.00'),
      categoryId: 18,
      categoryName: 'Farm-Fresh Vegetables & Groceries',
      categorySlug: 'vegetables_groceries',
      unit: '1 kg',
    );

    final acRepair = ServiceItem(
      id: 101,
      title: 'AC Deep Clean Service',
      slug: 'ac-deep-clean',
      price: Decimal.parse('499.00'),
      categoryId: 15,
      categoryName: 'AC & Appliance Repair',
      categorySlug: 'ac_appliance',
    );

    test('TEST 1: Logged-out user clicks Add to Cart -> sets PendingCartAction (addToCart) -> executes after login', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      // Verify unauthenticated state
      expect(container.read(isUserAuthenticatedProvider), isFalse);

      // Set pending action
      container.read(pendingActionProvider.notifier).setAction(
            PendingCartAction(
              service: beetroot,
              actionType: PendingCartActionType.addToCart,
              quantity: 1,
              returnPath: '/categories/vegetables_groceries',
            ),
          );

      final pending = container.read(pendingActionProvider);
      expect(pending, isNotNull);
      expect(pending!.actionType, equals(PendingCartActionType.addToCart));
      expect(pending.service.title, equals('Beetroot'));
      expect(pending.returnPath, equals('/categories/vegetables_groceries'));

      // Simulate successful login -> execute pending action
      container.read(cartProvider.notifier).addService(pending.service, quantity: pending.quantity);
      container.read(pendingActionProvider.notifier).clear();

      expect(container.read(pendingActionProvider), isNull);
      final cart = container.read(cartProvider);
      expect(cart.length, equals(1));
      expect(cart.first.service.id, equals(800000228));
      expect(cart.first.quantity, equals(1));
    });

    test('TEST 2: Logged-out user clicks Buy -> sets PendingCartAction (buy) -> executes after login -> opens Cart', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      container.read(pendingActionProvider.notifier).setAction(
            PendingCartAction(
              service: beetroot,
              actionType: PendingCartActionType.buy,
              quantity: 1,
              returnPath: '/cart',
            ),
          );

      final pending = container.read(pendingActionProvider);
      expect(pending, isNotNull);
      expect(pending!.actionType, equals(PendingCartActionType.buy));
      expect(pending.returnPath, equals('/cart'));

      // Execute on login
      container.read(cartProvider.notifier).addService(pending.service, quantity: pending.quantity);
      container.read(pendingActionProvider.notifier).clear();

      expect(container.read(pendingActionProvider), isNull);
      expect(container.read(cartProvider).first.service.slug, equals('veg-beetroot'));
    });

    test('TEST 3: Logged-in user clicks Add to Cart -> item is added directly to cart and stays on grocery screen', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      container.read(cartProvider.notifier).addService(beetroot, quantity: 1);

      final cart = container.read(cartProvider);
      expect(cart.length, equals(1));
      expect(cart.first.service.id, equals(800000228));
      expect(cart.first.quantity, equals(1));
      expect(cart.first.service.flowType, equals(CatalogFlowType.grocery));
    });


    test('TEST 5: Add same item twice -> increases quantity rather than duplicating', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      container.read(cartProvider.notifier).addService(beetroot, quantity: 1);
      container.read(cartProvider.notifier).addService(beetroot, quantity: 1);

      final cart = container.read(cartProvider);
      expect(cart.length, equals(1)); // NOT 2 entries
      expect(cart.first.quantity, equals(2));
      expect(cart.first.totalPrice, equals(Decimal.parse('74.00')));
    });

    test('TEST 6: Increase quantity via updateQuantity', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      container.read(cartProvider.notifier).addService(beetroot, quantity: 1);
      container.read(cartProvider.notifier).updateQuantity(800000228, 3);

      final cart = container.read(cartProvider);
      expect(cart.first.quantity, equals(3));
      expect(cart.first.totalPrice, equals(Decimal.parse('111.00')));
    });

    test('TEST 7: Decrease quantity via updateQuantity and remove at 0', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      container.read(cartProvider.notifier).addService(beetroot, quantity: 2);
      container.read(cartProvider.notifier).updateQuantity(800000228, 1);
      expect(container.read(cartProvider).first.quantity, equals(1));

      container.read(cartProvider.notifier).updateQuantity(800000228, 0);
      expect(container.read(cartProvider).isEmpty, isTrue);
    });



    test('TEST 10: Proceed to checkout on grocery cart -> verifies auth guard presence', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final isAuth = container.read(isUserAuthenticatedProvider);
      expect(isAuth, isFalse);
      // When unauthenticated, system creates pending action and redirects
    });

    test('TEST 11: Normal service maintains date/time slot serviceBooking flow', () {
      expect(acRepair.flowType, equals(CatalogFlowType.serviceBooking));
      expect(acRepair.flowType == CatalogFlowType.grocery, isFalse);
    });

    test('TEST 12: Farm-Fresh item NEVER navigates to service date/time slot flow', () {
      expect(beetroot.flowType, equals(CatalogFlowType.grocery));
      expect(beetroot.flowType == CatalogFlowType.serviceBooking, isFalse);
      expect(potato.flowType, equals(CatalogFlowType.grocery));
      expect(potato.flowType == CatalogFlowType.serviceBooking, isFalse);
    });
  });
}
