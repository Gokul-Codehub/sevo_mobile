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
    id: 800000228,
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
      expect(cart.first.service.id, equals(800000228));
      expect(find.text('Cart Screen'), findsOneWidget);
    });

  });
}
