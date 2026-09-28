import 'package:calservices_customer/features/auth/domain/auth_models.dart';
import 'package:calservices_customer/features/auth/domain/auth_notifier.dart';
import 'package:calservices_customer/features/booking/domain/cart_notifier.dart';
import 'package:calservices_customer/features/catalog/domain/catalog_models.dart';
import 'package:calservices_customer/features/catalog/presentation/widgets/service_card.dart';
import 'package:calservices_customer/shared/theme/app_colors.dart';
import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

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
    durationMinutes: 8,
    categorySlug: 'vegetables_groceries',
    categoryName: 'Farm-Fresh Vegetable',
    description: '100% farm-fresh local produce',
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
      ],
    );
  }

  Widget createWidgetUnderTest({
    required Widget child,
    List<Override> overrides = const [],
  }) {
    final router = createTestRouter(child: child);
    return ProviderScope(
      overrides: overrides,
      child: MaterialApp.router(
        theme: ThemeData(primaryColor: AppColors.primary),
        routerConfig: router,
      ),
    );
  }

  group('Grocery ServiceCard Widget Tests (Off-Device Simulation)', () {
    testWidgets('Renders Beetroot grocery card with ADD and BUY buttons when cart is empty', (tester) async {
      await tester.pumpWidget(
        createWidgetUnderTest(
          child: ServiceCard(service: beetroot),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Beetroot'), findsOneWidget);
      expect(find.text('₹37'), findsOneWidget);
      expect(find.text('ADD'), findsOneWidget);
      expect(find.text('BUY'), findsOneWidget);
      expect(find.text('View Details'), findsNothing);
    });

    testWidgets('Guest tap on ADD adds item to cart directly and renders quantity stepper', (tester) async {
      final container = ProviderContainer(
        overrides: [
          currentUserProvider.overrideWithValue(null),
        ],
      );
      addTearDown(container.dispose);

      final router = createTestRouter(child: ServiceCard(service: beetroot));

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(
            routerConfig: router,
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      final addButton = find.text('ADD');
      expect(addButton, findsOneWidget);
      await tester.tap(addButton);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      final cart = container.read(cartProvider);
      expect(cart.length, equals(1));
      expect(cart.first.service.id, equals(228));
      expect(cart.first.quantity, equals(1));
      expect(find.text('1'), findsOneWidget);
    });

    testWidgets('Guest tap on BUY adds item to cart and navigates to Cart screen', (tester) async {
      final container = ProviderContainer(
        overrides: [
          currentUserProvider.overrideWithValue(null),
        ],
      );
      addTearDown(container.dispose);

      final router = createTestRouter(child: ServiceCard(service: beetroot));

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(
            routerConfig: router,
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      final buyButton = find.text('BUY');
      expect(buyButton, findsOneWidget);
      await tester.tap(buyButton);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      final cart = container.read(cartProvider);
      expect(cart.length, equals(1));
      expect(cart.first.service.id, equals(228));
      expect(find.text('Cart Screen'), findsOneWidget);
    });

    testWidgets('Tapping + and - steppers increments, decrements, and removes at 0', (tester) async {
      const testUser = UserProfile(
        id: 7988,
        phone: '9876543210',
        name: 'Gokul M',
        email: 'cust_gokul.m@example.com',
      );

      final container = ProviderContainer(
        overrides: [
          currentUserProvider.overrideWithValue(testUser),
        ],
      );
      addTearDown(container.dispose);

      final router = createTestRouter(child: ServiceCard(service: beetroot));

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(
            routerConfig: router,
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      await tester.tap(find.text('ADD'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      final cart = container.read(cartProvider);
      expect(cart.length, equals(1));
      expect(cart.first.quantity, equals(1));
      expect(cart.first.service.id, equals(228));

      expect(find.text('1'), findsOneWidget);
      expect(find.byIcon(Icons.add), findsOneWidget);
      expect(find.byIcon(Icons.remove), findsOneWidget);

      await tester.tap(find.byIcon(Icons.add));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(container.read(cartProvider).first.quantity, equals(2));
      expect(find.text('2'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.remove));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(container.read(cartProvider).first.quantity, equals(1));
      expect(find.text('1'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.remove));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(container.read(cartProvider).isEmpty, isTrue);
      expect(find.text('ADD'), findsOneWidget);
    });
  });
}
