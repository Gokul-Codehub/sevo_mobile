import 'package:calservices_customer/core/errors/api_error.dart';
import 'package:calservices_customer/core/network/api_client.dart';
import 'package:calservices_customer/features/orders/data/grocery_orders_repository.dart';
import 'package:calservices_customer/features/orders/presentation/grocery_orders_screens.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

Map<String, dynamic> orderJson(String status, {Map<String, dynamic>? extra}) => {
      'order_type': 'marketplace',
      'order_number': 'MKT00164',
      'status': status,
      'status_label': status,
      'total_amount': '45.00',
      'subtotal_amount': '45.00',
      'delivery_fee': '0.00',
      'created_at': '2026-11-02T12:22:00Z',
      'seller_name': 'SevoGrocery',
      'warehouse_name': 'Jeemangalam Hub',
      'delivery_slot': 'Immediate',
      'delivery_address': '12 Main Road, Hosur',
      'payment_method': 'COD',
      'payment_status': 'PENDING',
      'items': [
        {'product_title': '100% Whole Wheat Bread Loaf', 'quantity': 1, 'unit_price_snapshot': '45.00', 'line_amount': '45.00'},
      ],
      'events': [
        {'mapped_status': 'CONFIRMED', 'occurred_at': '2026-11-02T12:22:00Z'},
      ],
      ...?extra,
    };

class _Repo extends GroceryOrdersRepository {
  _Repo(this.order) : super(api: ApiClient.withDio(Dio()));
  GroceryOrder order;
  final cancels = <String>[];
  @override
  Future<Result<GroceryOrder>> detail(String orderNumber) async => Success(order);
  @override
  Future<Result<List<GroceryOrder>>> myOrders() async => Success([order]);
  @override
  Future<Result<void>> cancel(String orderNumber, {String reason = ''}) async {
    cancels.add(orderNumber);
    return const Success(null);
  }
}

Future<_Repo> pump(WidgetTester tester, Map<String, dynamic> json, {Widget? screen}) async {
  tester.view.physicalSize = const Size(800, 2600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final repo = _Repo(GroceryOrder.tryParse(json)!);
  await tester.pumpWidget(ProviderScope(
    overrides: [groceryOrdersRepositoryProvider.overrideWithValue(repo)],
    child: MaterialApp.router(
      routerConfig: GoRouter(routes: [GoRoute(path: '/', builder: (_, __) => screen ?? const GroceryOrderDetailScreen(orderNumber: 'MKT00164'))]),
    ),
  ));
  await tester.pumpAndSettle();
  return repo;
}

void main() {
  group('parsing', () {
    test('statuses map to stages and progress', () {
      expect(stageFromStatus('PACKING'), OrderStage.packing);
      expect(stageFromStatus('OUT_FOR_DELIVERY'), OrderStage.outForDelivery);
      expect(stageFromStatus('weird'), OrderStage.confirmed);
      expect(GroceryOrder.tryParse(orderJson('CONFIRMED'))!.progress, closeTo(0.2, 1e-9));
      expect(GroceryOrder.tryParse(orderJson('DELIVERED'))!.progress, 1);
      expect(GroceryOrder.tryParse(orderJson('CANCELLED'))!.progress, 0);
    });

    test('cancel allowed only until the rider has it', () {
      for (final s in ['CONFIRMED', 'PACKING', 'READY_FOR_PICKUP']) {
        expect(GroceryOrder.tryParse(orderJson(s))!.canCancel, isTrue, reason: s);
      }
      for (final s in ['OUT_FOR_DELIVERY', 'DELIVERED', 'CANCELLED']) {
        expect(GroceryOrder.tryParse(orderJson(s))!.canCancel, isFalse, reason: s);
      }
      expect(GroceryOrder.tryParse(orderJson('PACKING', extra: {'cancellation_pending': true}))!.canCancel, isFalse);
    });

    test('OTP only while on the way; rider block parsed', () {
      final onWay = GroceryOrder.tryParse(orderJson('OUT_FOR_DELIVERY', extra: {
        'delivery_otp': '4821',
        'live_tracking': {
          'freshness': 'LIVE',
          'eta_minutes': 7,
          'technician': {'name': 'Ravi', 'phone': '9123456789'},
        },
      }))!;
      expect(onWay.showOtp, isTrue);
      expect((onWay.rider!.name, onWay.rider!.etaMinutes, onWay.rider!.live), ('Ravi', 7, true));
      expect(GroceryOrder.tryParse(orderJson('PACKING', extra: {'delivery_otp': '4821'}))!.showOtp, isFalse);
    });

    test('junk rows are dropped, not crashed on', () {
      expect(GroceryOrder.tryParse(null), isNull);
      expect(GroceryOrder.tryParse({'status': 'PACKING'}), isNull);
      expect(GroceryOrder.tryParse(orderJson('PACKING', extra: {'items': [1, null, {}]}))!.items, isEmpty);
    });
  });

  group('detail screen', () {
    testWidgets('shows the five steps, items and the Cancel button for a confirmed order', (tester) async {
      await pump(tester, orderJson('CONFIRMED'));
      expect(find.text('Order #MKT00164'), findsWidgets);
      for (final t in ['Confirmed', 'Seller is packing', 'Ready for pickup', 'On the way', 'Delivered']) {
        expect(find.text(t), findsWidgets, reason: t);
      }
      expect(find.text('100% Whole Wheat Bread Loaf'), findsOneWidget);
      expect(find.text('Amount to pay on delivery'), findsOneWidget);
      expect(find.text('Cancel order'), findsOneWidget);
      expect(find.textContaining('Share this code'), findsNothing);
    });

    testWidgets('cancelling asks first, then calls the server', (tester) async {
      final repo = await pump(tester, orderJson('PACKING'));
      await tester.tap(find.text('Cancel order'));
      await tester.pumpAndSettle();
      expect(find.text('Cancel this order?'), findsOneWidget);
      await tester.tap(find.text('Keep order'));
      await tester.pumpAndSettle();
      expect(repo.cancels, isEmpty);
      await tester.tap(find.text('Cancel order'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Cancel order'));
      await tester.pumpAndSettle();
      expect(repo.cancels, ['MKT00164']);
    });

    testWidgets('on the way: OTP and the live-tracking button show, Cancel does not', (tester) async {
      await pump(tester, orderJson('OUT_FOR_DELIVERY', extra: {
        'delivery_otp': '4821',
        'live_tracking': {
          'freshness': 'LIVE',
          'eta_minutes': 7,
          'technician': {'name': 'Ravi'},
        },
      }));
      expect(find.text('4821'), findsOneWidget);
      expect(find.text('Track live on map'), findsOneWidget);
      expect(find.text('Arriving in about 7 min'), findsOneWidget);
      expect(find.text('Cancel order'), findsNothing);
    });

    testWidgets('a cancelled order shows the cancelled note and no steps', (tester) async {
      await pump(tester, orderJson('CANCELLED'));
      expect(find.textContaining('was cancelled'), findsOneWidget);
      expect(find.text('Seller is packing'), findsNothing);
    });
  });

  group('orders list', () {
    testWidgets('an active order is under Active with its progress and total', (tester) async {
      await pump(tester, orderJson('PACKING'), screen: const GroceryOrdersScreen());
      expect(find.text('#MKT00164'), findsOneWidget);
      expect(find.text('₹45'), findsOneWidget);
      expect(find.text('Delivery slot: Immediate'), findsOneWidget);
    });

    testWidgets('a delivered order is not under Active', (tester) async {
      await pump(tester, orderJson('DELIVERED'), screen: const GroceryOrdersScreen());
      expect(find.text('No active orders'), findsOneWidget);
      await tester.tap(find.text('Delivered'));
      await tester.pumpAndSettle();
      expect(find.text('#MKT00164'), findsOneWidget);
    });
  });
}
