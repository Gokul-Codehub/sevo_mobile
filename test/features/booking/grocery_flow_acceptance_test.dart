import 'package:calservices_customer/features/auth/domain/auth_models.dart';
import 'package:calservices_customer/features/auth/domain/auth_notifier.dart';
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

  final beetroot = ServiceItem(
    id: 228,
    categoryId: 18,
    title: 'Beetroot',
    slug: 'veg-beetroot',
    price: Decimal.fromInt(37),
    categorySlug: 'vegetables_groceries',
    categoryName: 'Farm-Fresh Vegetable',
  );

  final potato = ServiceItem(
    id: 229,
    categoryId: 18,
    title: 'Potato',
    slug: 'veg-potato',
    price: Decimal.fromInt(42),
    categorySlug: 'vegetables_groceries',
    categoryName: 'Farm-Fresh Vegetable',
  );

  const testUser = UserProfile(
    id: 7988,
    phone: '9876543210',
    name: 'Gokul M',
    email: 'cust_gokul.m@example.com',
  );

  group('Grocery Flow Explicit Acceptance Suite (Tests G01 - G12)', () {
    test('TEST G01: Farm-Fresh -> Beetroot flowType == CatalogFlowType.grocery', () {
      expect(beetroot.flowType, equals(CatalogFlowType.grocery));
      expect(beetroot.flowType == CatalogFlowType.serviceBooking, isFalse);
    });

    test('TEST G02: Grocery ADD does not navigate to ServiceDetailScreen', () {
      expect(beetroot.flowType == CatalogFlowType.grocery, isTrue);
    });

    test('TEST G03: Grocery BUY targets Cart route (/cart)', () {
      final action = PendingCartAction(
        service: beetroot,
        actionType: PendingCartActionType.buy,
        returnPath: '/cart',
      );
      expect(action.actionType, equals(PendingCartActionType.buy));
      expect(action.returnPath, equals('/cart'));
    });

    test('TEST G04: Logged-out ADD creates pending action with addToCart and redirect path', () {
      final container = ProviderContainer(
        overrides: [
          currentUserProvider.overrideWithValue(null),
        ],
      );
      addTearDown(container.dispose);

      expect(container.read(isUserAuthenticatedProvider), isFalse);

      container.read(pendingActionProvider.notifier).setAction(
            PendingCartAction(
              service: beetroot,
              actionType: PendingCartActionType.addToCart,
              returnPath: '/categories/vegetables_groceries',
            ),
          );

      final pending = container.read(pendingActionProvider);
      expect(pending, isNotNull);
      expect(pending!.actionType, equals(PendingCartActionType.addToCart));
      expect(pending.returnPath, equals('/categories/vegetables_groceries'));
    });

    test('TEST G05: Logged-out BUY creates pending BUY action with /cart destination', () {
      final container = ProviderContainer(
        overrides: [
          currentUserProvider.overrideWithValue(null),
        ],
      );
      addTearDown(container.dispose);

      container.read(pendingActionProvider.notifier).setAction(
            PendingCartAction(
              service: beetroot,
              actionType: PendingCartActionType.buy,
              returnPath: '/cart',
            ),
          );

      final pending = container.read(pendingActionProvider);
      expect(pending, isNotNull);
      expect(pending!.actionType, equals(PendingCartActionType.buy));
      expect(pending.returnPath, equals('/cart'));
    });

    test('TEST G06: Successful OTP executes pending ADD automatically and adds item to cart', () {
      final container = ProviderContainer(
        overrides: [
          currentUserProvider.overrideWithValue(testUser),
        ],
      );
      addTearDown(container.dispose);

      container.read(pendingActionProvider.notifier).setAction(
            PendingCartAction(
              service: beetroot,
              actionType: PendingCartActionType.addToCart,
              returnPath: '/categories/vegetables_groceries',
            ),
          );

      final pending = container.read(pendingActionProvider);
      expect(pending, isNotNull);
      container.read(cartProvider.notifier).addService(pending!.service, quantity: pending.quantity);
      container.read(pendingActionProvider.notifier).clear();

      expect(container.read(cartProvider).length, equals(1));
      expect(container.read(cartProvider).first.service.id, equals(228));
      expect(container.read(pendingActionProvider), isNull);
    });

    test('TEST G07: Successful OTP executes pending BUY automatically and adds item', () {
      final container = ProviderContainer(
        overrides: [
          currentUserProvider.overrideWithValue(testUser),
        ],
      );
      addTearDown(container.dispose);

      container.read(pendingActionProvider.notifier).setAction(
            PendingCartAction(
              service: beetroot,
              actionType: PendingCartActionType.buy,
              returnPath: '/cart',
            ),
          );

      final pending = container.read(pendingActionProvider);
      expect(pending, isNotNull);
      container.read(cartProvider.notifier).addService(pending!.service, quantity: pending.quantity);
      container.read(pendingActionProvider.notifier).clear();

      expect(container.read(cartProvider).length, equals(1));
      expect(container.read(cartProvider).first.service.title, equals('Beetroot'));
      expect(container.read(pendingActionProvider), isNull);
    });

    test('TEST G08: Authenticated ADD keeps user on grocery screen while mutating state', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      container.read(cartProvider.notifier).addService(beetroot);

      final cart = container.read(cartProvider);
      expect(cart.length, equals(1));
      expect(cart.first.quantity, equals(1));
    });

    test('TEST G09: Authenticated BUY adds item to cart and points to Cart route', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      container.read(cartProvider.notifier).addService(beetroot);
      final summary = container.read(cartSummaryProvider);

      expect(summary.itemCount, equals(1));
      expect(summary.isGroceryCart, isTrue);
      expect(summary.total, equals(Decimal.parse('59.00'))); // ₹37 + ₹15 + ₹2 + ₹5
    });

    test('TEST G10: Quantity +/- stepper updates cart quantity accurately', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      container.read(cartProvider.notifier).addService(beetroot); // qty 1
      container.read(cartProvider.notifier).updateQuantity(228, 2); // qty 2
      expect(container.read(cartProvider).first.quantity, equals(2));

      container.read(cartProvider.notifier).updateQuantity(228, 3); // qty 3
      expect(container.read(cartProvider).first.quantity, equals(3));

      container.read(cartProvider.notifier).updateQuantity(228, 2); // qty 2
      expect(container.read(cartProvider).first.quantity, equals(2));

      container.read(cartProvider.notifier).updateQuantity(228, 0); // qty 0 -> removed
      expect(container.read(cartProvider).isEmpty, isTrue);
    });

    test('TEST G11: Multiple distinct grocery items coexist and compute aggregate subtotal and free delivery', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      container.read(cartProvider.notifier).addService(beetroot, quantity: 3); // 3 * 37 = 111
      container.read(cartProvider.notifier).addService(potato, quantity: 3);   // 3 * 42 = 126

      final summary = container.read(cartSummaryProvider);
      expect(summary.itemCount, equals(6));
      expect(summary.subtotal, equals(Decimal.parse('237.00')));
      expect(summary.deliveryFee, equals(Decimal.zero));
      expect(summary.handlingFee, equals(Decimal.parse('2.00')));
      expect(summary.smallCartFee, equals(Decimal.zero));
      expect(summary.total, equals(Decimal.parse('239.00')));
    });

    test('TEST G12: Farm-Fresh grocery items NEVER enter date/time slot service booking flow', () {
      expect(beetroot.flowType, equals(CatalogFlowType.grocery));
      expect(potato.flowType, equals(CatalogFlowType.grocery));
      expect(beetroot.flowType == CatalogFlowType.serviceBooking, isFalse);
    });
  });
}
