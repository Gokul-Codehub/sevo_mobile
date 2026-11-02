import 'package:calservices_customer/features/booking/domain/booking_models.dart';
import 'package:calservices_customer/features/booking/domain/cart_notifier.dart';
import 'package:calservices_customer/features/booking/presentation/widgets/cart_zone_guard.dart';
import 'package:calservices_customer/features/catalog/data/marketplace_catalog_repository.dart';
import 'package:calservices_customer/routing/app_router.dart' show rootNavigatorKey;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

CartItem line(int? warehouse) => CartItem(
      service: MarketplaceProduct.fromJson({'id': 5, 'title': 'Tomato', 'selling_price': '40', 'warehouse_id': warehouse}).toServiceItem(),
      quantity: 1,
    );

final _testZone = StateProvider<DeliveryZone>((ref) => const DeliveryZone.serviceable(1, 'Hosur Hub'));

void main() {
  group('cartConflictsWithZone', () {
    test('only a serviceable zone served by a different warehouse conflicts', () {
      expect(cartConflictsWithZone([line(1)], const DeliveryZone.serviceable(2, 'B')), isTrue);
      expect(cartConflictsWithZone([line(1)], const DeliveryZone.serviceable(1, 'A')), isFalse);
      expect(cartConflictsWithZone([line(1)], const DeliveryZone.unserviceable('x')), isFalse);
      expect(cartConflictsWithZone([line(1)], const DeliveryZone.unknown()), isFalse);
      expect(cartConflictsWithZone(const [], const DeliveryZone.serviceable(2, 'B')), isFalse);
      expect(cartConflictsWithZone([line(null)], const DeliveryZone.serviceable(2, 'B')), isFalse);
    });
  });

  group('CartZoneGuard', () {
    late ProviderContainer container;

    Future<void> pump(WidgetTester tester) async {
      container = ProviderContainer(overrides: [
        deliveryZoneProvider.overrideWith((ref) async => ref.watch(_testZone)),
      ]);
      addTearDown(container.dispose);
      container.read(cartProvider.notifier).addService(line(1).service);
      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          navigatorKey: rootNavigatorKey,
          builder: (context, child) => CartZoneGuard(child: child!),
          home: const Scaffold(body: Text('home')),
        ),
      ));
      await tester.pumpAndSettle();
    }

    testWidgets('no question when the new address is served by the same hub', (tester) async {
      await pump(tester);
      expect(find.text('Change delivery location?'), findsNothing);
    });

    testWidgets('a different hub asks; "Clear cart & switch" empties the cart', (tester) async {
      await pump(tester);
      container.read(_testZone.notifier).state = const DeliveryZone.serviceable(2, 'Salem Hub');
      await tester.pumpAndSettle();
      expect(find.text('Change delivery location?'), findsOneWidget);
      await tester.tap(find.text('Clear cart & switch'));
      await tester.pumpAndSettle();
      expect(container.read(cartProvider), isEmpty);
    });

    testWidgets('"Keep my cart" leaves the cart alone', (tester) async {
      await pump(tester);
      container.read(_testZone.notifier).state = const DeliveryZone.serviceable(2, 'Salem Hub');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Keep my cart'));
      await tester.pumpAndSettle();
      expect(container.read(cartProvider), hasLength(1));
      expect(find.text('Change delivery location?'), findsNothing);
    });

    testWidgets('an area we do not deliver to does not touch the cart', (tester) async {
      await pump(tester);
      container.read(_testZone.notifier).state = const DeliveryZone.unserviceable('no');
      await tester.pumpAndSettle();
      expect(find.text('Change delivery location?'), findsNothing);
      expect(container.read(cartProvider), hasLength(1));
    });
  });
}
