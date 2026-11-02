import 'package:calservices_customer/core/navigation/web_link_mapper.dart';
import 'package:calservices_customer/core/network/api_client.dart';
import 'package:calservices_customer/core/push/push_manager.dart';
import 'package:calservices_customer/features/orders/data/grocery_orders_repository.dart';
import 'package:calservices_customer/features/orders/presentation/grocery_orders_screens.dart';
import 'package:calservices_customer/core/errors/api_error.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

class _Repo extends GroceryOrdersRepository {
  _Repo(this.order) : super(api: ApiClient.withDio(Dio()));
  final GroceryOrder order;
  @override
  Future<Result<GroceryOrder>> detail(String orderNumber) async => Success(order);
}

Future<void> pump(WidgetTester tester, String status, {String? otp}) async {
  tester.view.physicalSize = const Size(800, 2600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final order = GroceryOrder.tryParse({
    'order_number': 'MKT00164',
    'status': status,
    'total_amount': '45.00',
    'delivery_slot': '5:00 PM - 6:00 PM',
    'delivery_otp': otp,
    'items': [
      {'product_title': 'Bread', 'quantity': 1, 'unit_price_snapshot': '45', 'line_amount': '45'},
    ],
    'live_tracking': status == 'OUT_FOR_DELIVERY' ? {'freshness': 'LIVE', 'technician': {'name': 'Ravi'}} : null,
  })!;
  await tester.pumpWidget(ProviderScope(
    overrides: [groceryOrdersRepositoryProvider.overrideWithValue(_Repo(order))],
    child: MaterialApp.router(routerConfig: GoRouter(routes: [GoRoute(path: '/', builder: (_, __) => const GroceryOrderDetailScreen(orderNumber: 'MKT00164'))])),
  ));
  await tester.pumpAndSettle();
}

void main() {
  group('order tracker', () {
    testWidgets('one tracker only - the vertical timeline - with an icon on each step', (tester) async {
      await pump(tester, 'CONFIRMED');
      expect(find.text('Delivery progress'), findsOneWidget);
      expect(find.text('Delivery slot: 5:00 PM - 6:00 PM'), findsOneWidget);
      // no second, horizontal tracker with its own short labels
      expect(find.text('Packing'), findsNothing);
      expect(find.text('Ready'), findsNothing);
      // step icons (the first step is current, so it is not yet a tick)
      for (final icon in [Icons.check_circle_outline, Icons.inventory_2_outlined, Icons.local_shipping_outlined, Icons.delivery_dining_outlined, Icons.home_outlined]) {
        expect(find.byIcon(icon), findsWidgets, reason: '$icon');
      }
      // no numbered circles
      expect(find.text('2'), findsNothing);
    });

    testWidgets('finished steps turn into ticks', (tester) async {
      await pump(tester, 'READY_FOR_PICKUP');
      expect(find.byIcon(Icons.check_rounded), findsNWidgets(2)); // confirmed + packing are done
    });
  });

  group('delivery OTP on the order page', () {
    testWidgets('shown once the order is on the way and the rider has requested it', (tester) async {
      await pump(tester, 'OUT_FOR_DELIVERY', otp: '582914');
      expect(find.text('582914'), findsOneWidget);
      expect(find.textContaining('Share this code'), findsOneWidget);
    });

    testWidgets('not shown before the order is on the way, even if a code exists', (tester) async {
      await pump(tester, 'PACKING', otp: '582914');
      expect(find.text('582914'), findsNothing);
    });

    testWidgets('on the way but the rider has not requested a code yet: no empty card', (tester) async {
      await pump(tester, 'OUT_FOR_DELIVERY');
      expect(find.textContaining('Share this code'), findsNothing);
    });
  });

  group('the delivery-OTP notification opens the order', () {
    test('an inbox tap goes to the order page, not the website', () {
      final link = resolveWebLink('/grocery-orders/MKT00164');
      expect(link.route, '/grocery-orders/MKT00164');
      expect(link.external, isNull);
    });

    test('a push tap goes to the order page', () {
      expect(PushManager.appRouteFor('/grocery-orders/MKT00164'), '/grocery-orders/MKT00164');
    });

    test('odd paths are not treated as order pages', () {
      expect(resolveWebLink('/grocery-orders/../x').route, isNot(startsWith('/grocery-orders')));
      expect(resolveWebLink('/grocery-orders/').route, isNot(startsWith('/grocery-orders/')));
    });
  });
}
