import 'dart:convert';
import 'dart:typed_data';

import 'package:calservices_customer/core/errors/api_error.dart';
import 'package:calservices_customer/core/network/api_client.dart';
import 'package:calservices_customer/features/orders/data/grocery_orders_repository.dart';
import 'package:calservices_customer/features/orders/data/order_returns_repository.dart';
import 'package:calservices_customer/features/orders/presentation/order_invoices_card.dart';
import 'package:calservices_customer/features/orders/presentation/order_returns.dart';
import 'package:calservices_customer/shared/theme/app_theme.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

GroceryOrder deliveredOrder({bool canReturn = true, List<Map<String, Object?>>? lines}) => GroceryOrder.tryParse({
      'order_number': 'MKT00164',
      'status': 'DELIVERED',
      'total_amount': '129.00',
      'can_return': canReturn,
      'seller_lines': lines ?? const [],
      'items': [
        {'id': 11, 'seller_id': 1, 'product_title': 'Bread', 'quantity': 2, 'unit_price_snapshot': '45.00', 'line_amount': '90.00'},
        {'id': 12, 'seller_id': 2, 'product_title': 'Milk', 'quantity': 1, 'unit_price_snapshot': '39.00', 'line_amount': '39.00'},
      ],
    })!;

class _Adapter implements HttpClientAdapter {
  _Adapter(this.status, this.body);
  final int status;
  final Object body;
  final List<RequestOptions> calls = [];
  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<List<int>>? requestStream, Future<void>? cancelFuture) async {
    calls.add(options);
    return ResponseBody.fromString(jsonEncode(body), status, headers: {
      Headers.contentTypeHeader: ['application/json'],
    });
  }

  @override
  void close({bool force = false}) {}
}

class _Returns extends OrderReturnsRepository {
  _Returns({this.existing = const []}) : super(api: ApiClient.withDio(Dio()));
  final List<ReturnRequest> existing;
  final created = <({List<ReturnLine> lines, ReturnReason reason, String notes, int? sellerLineId})>[];
  @override
  Future<Result<ReturnRequest>> create(String orderNumber, {required List<ReturnLine> lines, required ReturnReason reason, String notes = '', int? sellerLineId}) async {
    created.add((lines: lines, reason: reason, notes: notes, sellerLineId: sellerLineId));
    return Success(ReturnRequest.tryParse({'return_number': 'RET-1', 'status': 'REQUESTED'})!);
  }

  @override
  Future<Result<List<ReturnRequest>>> forOrder(String orderNumber) async => Success(existing);
}

class _Orders extends GroceryOrdersRepository {
  _Orders(this.order, {this.issued = const []}) : super(api: ApiClient.withDio(Dio()));
  final GroceryOrder order;
  final List<OrderInvoice> issued;
  final pdfs = <(String, int)>[];
  @override
  Future<Result<GroceryOrder>> detail(String orderNumber) async => Success(order);
  @override
  Future<Result<List<OrderInvoice>>> invoices(String orderNumber) async => Success(issued);
  @override
  Future<Result<Uint8List>> invoicePdf(String orderNumber, int sellerId) async {
    pdfs.add((orderNumber, sellerId));
    return Success(Uint8List.fromList([37, 80, 68, 70]));
  }
}

Future<void> pumpScreen(WidgetTester tester, Widget screen, List<Override> overrides) async {
  tester.view.physicalSize = const Size(800, 2600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(
    overrides: overrides,
    child: MaterialApp.router(
      theme: AppTheme.light,
      routerConfig: GoRouter(routes: [
        GoRoute(path: '/', builder: (_, __) => screen),
        GoRoute(path: '/grocery-orders/:n', builder: (_, s) => Scaffold(body: Text('order page ${s.pathParameters['n']}'))),
        GoRoute(path: '/grocery-orders/:n/return', builder: (_, s) => Scaffold(body: Text('return page ${s.pathParameters['n']}'))),
      ]),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  group('return requests', () {
    test('parse: stage, refund note and openness', () {
      final r = ReturnRequest.tryParse({'return_number': 'R1', 'status': 'APPROVED', 'refund_status': 'PENDING', 'refund_amount': '90.00', 'reason_label': 'Damaged'})!;
      expect((r.stage, r.refundAmount, r.isOpen, r.refundNote), (ReturnStage.approved, 90.0, true, 'Refund pending'));
      expect(ReturnRequest.tryParse({'return_number': 'R2', 'status': 'REFUNDED', 'refund_status': 'REFUNDED'})!.refundNote, 'Refunded');
      expect(ReturnRequest.tryParse({'return_number': 'R3', 'status': 'REJECTED', 'refund_status': 'NOT_APPLICABLE'})!.isOpen, isFalse);
      expect(ReturnRequest.tryParse({'status': 'APPROVED'}), isNull);
    });

    test('sent exactly as the web sends it', () async {
      final a = _Adapter(201, {'success': true, 'data': {'return_number': 'R9', 'status': 'REQUESTED'}});
      final repo = OrderReturnsRepository(api: ApiClient.withDio(Dio(BaseOptions(baseUrl: 'https://x.test'))..httpClientAdapter = a));
      final r = await repo.create('MKT00164', lines: const [ReturnLine(11, 1)], reason: ReturnReason.quality, notes: ' stale ', sellerLineId: 5);
      expect((r as Success<ReturnRequest>).data.returnNumber, 'R9');
      expect(a.calls.single.path, '/api/orders/marketplace/MKT00164/returns/');
      expect(a.calls.single.data, {
        'items': [
          {'order_item_id': 11, 'quantity': 1, 'reason': 'QUALITY_ISSUE'},
        ],
        'reason': 'QUALITY_ISSUE',
        'customer_notes': 'stale',
        'seller_line_id': 5,
        'resolution_type': 'REFUND_ONLY',
      });
    });

    test('nothing selected never reaches the server', () async {
      final a = _Adapter(201, {});
      final repo = OrderReturnsRepository(api: ApiClient.withDio(Dio()..httpClientAdapter = a));
      expect(await repo.create('X', lines: const [], reason: ReturnReason.damaged), isA<Failure<ReturnRequest>>());
      expect(a.calls, isEmpty);
    });
  });

  group('return screen', () {
    Future<_Returns> open(WidgetTester tester, {GroceryOrder? order}) async {
      final returns = _Returns();
      await pumpScreen(tester, const ReturnRequestScreen(orderNumber: 'MKT00164'), [
        groceryOrdersRepositoryProvider.overrideWithValue(_Orders(order ?? deliveredOrder())),
        orderReturnsRepositoryProvider.overrideWithValue(returns),
      ]);
      return returns;
    }

    testWidgets('ticking an item shows its quantity and updates the estimated refund', (tester) async {
      await open(tester);
      expect(find.text('₹0'), findsOneWidget);
      await tester.tap(find.byType(Checkbox).first);
      await tester.pumpAndSettle();
      expect(find.text('₹45'), findsOneWidget);
      await tester.tap(find.byIcon(Icons.add_circle_outline));
      await tester.pumpAndSettle();
      expect(find.text('₹90'), findsOneWidget);
      // cannot return more than was ordered
      expect(tester.widget<IconButton>(find.widgetWithIcon(IconButton, Icons.add_circle_outline)).onPressed, isNull);
    });

    testWidgets('submitting with nothing selected asks for an item and sends nothing', (tester) async {
      final returns = await open(tester);
      await tester.tap(find.text('Submit return'));
      await tester.pumpAndSettle();
      expect(returns.created, isEmpty);
    });

    testWidgets('submits the chosen items, reason and notes', (tester) async {
      final returns = await open(tester);
      await tester.tap(find.byType(Checkbox).first);
      await tester.tap(find.text('Quality issue / stale'));
      await tester.enterText(find.byType(TextField), 'smells off');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Submit return'));
      await tester.pumpAndSettle();
      final c = returns.created.single;
      expect(c.lines.single.orderItemId, 11);
      expect(c.lines.single.quantity, 1);
      expect((c.reason, c.notes, c.sellerLineId), (ReturnReason.quality, 'smells off', null));
      expect(find.text('order page MKT00164'), findsOneWidget); // back to the order after submitting
    });

    testWidgets('items from two sellers in one request are refused', (tester) async {
      final order = deliveredOrder(lines: [
        {'id': 100, 'seller_id': 1, 'seller_name': 'A', 'status': 'DELIVERED'},
        {'id': 200, 'seller_id': 2, 'seller_name': 'B', 'status': 'DELIVERED'},
      ]);
      final returns = await open(tester, order: order);
      await tester.tap(find.byType(Checkbox).at(0));
      await tester.tap(find.byType(Checkbox).at(1));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Submit return'));
      await tester.pumpAndSettle();
      expect(returns.created, isEmpty);
    });

    testWidgets('with several sellers the request carries the right seller line', (tester) async {
      final order = deliveredOrder(lines: [
        {'id': 100, 'seller_id': 1, 'seller_name': 'A', 'status': 'DELIVERED'},
        {'id': 200, 'seller_id': 2, 'seller_name': 'B', 'status': 'DELIVERED'},
      ]);
      final returns = await open(tester, order: order);
      await tester.tap(find.byType(Checkbox).at(1)); // Milk, seller 2
      await tester.pumpAndSettle();
      await tester.tap(find.text('Submit return'));
      await tester.pumpAndSettle();
      expect(returns.created.single.sellerLineId, 200);
    });
  });

  group('returns card', () {
    testWidgets('the button shows only while the order can still be returned', (tester) async {
      await pumpScreen(tester, Scaffold(body: OrderReturnsCard(order: deliveredOrder(canReturn: true))), [orderReturnsRepositoryProvider.overrideWithValue(_Returns())]);
      expect(find.text('Return items'), findsOneWidget);
      await pumpScreen(tester, Scaffold(body: OrderReturnsCard(order: deliveredOrder(canReturn: false))), [orderReturnsRepositoryProvider.overrideWithValue(_Returns())]);
      expect(find.text('Return items'), findsNothing);
      expect(find.text('Returns & refunds'), findsNothing); // nothing to show at all
    });

    testWidgets('lists existing returns with their status and refund state, even after the window closed', (tester) async {
      final existing = [ReturnRequest.tryParse({'return_number': 'R7', 'status': 'APPROVED', 'status_label': 'Approved', 'refund_status': 'PENDING', 'refund_amount': '45.00', 'reason_label': 'Damaged'})!];
      await pumpScreen(tester, Scaffold(body: OrderReturnsCard(order: deliveredOrder(canReturn: false))), [orderReturnsRepositoryProvider.overrideWithValue(_Returns(existing: existing))]);
      expect(find.text('Return #R7'), findsOneWidget);
      expect(find.text('Approved'), findsOneWidget);
      expect(find.text('Refund pending'), findsOneWidget);
    });

    testWidgets('the button opens the return page', (tester) async {
      await pumpScreen(tester, Scaffold(body: OrderReturnsCard(order: deliveredOrder())), [orderReturnsRepositoryProvider.overrideWithValue(_Returns())]);
      await tester.tap(find.text('Return items'));
      await tester.pumpAndSettle();
      expect(find.text('return page MKT00164'), findsOneWidget);
    });
  });

  group('invoices', () {
    test('parse: tax invoice vs credit note', () {
      final i = OrderInvoice.tryParse({'seller_id': 3, 'invoice_number': 'INV-1', 'document_type': 'TAX_INVOICE', 'grand_total': '88.00', 'seller_name': 'SevoGrocery'})!;
      expect((i.sellerId, i.isCreditNote, i.total), (3, false, 88.0));
      expect(OrderInvoice.tryParse({'seller_id': 3, 'invoice_number': 'CN-1', 'document_type': 'CREDIT_NOTE'})!.isCreditNote, isTrue);
      expect(OrderInvoice.tryParse({'seller_id': 3}), isNull);
    });

    testWidgets('each invoice has a download that fetches the PDF and hands it on', (tester) async {
      final repo = _Orders(deliveredOrder(), issued: const [OrderInvoice(sellerId: 3, sellerName: 'SevoGrocery', number: 'INV-1', isCreditNote: false, total: 88)]);
      final shared = <String>[];
      await pumpScreen(tester, Scaffold(body: OrderInvoicesCard(orderNumber: 'MKT00164', saveAndShare: (bytes, name) async => shared.add('$name:${bytes.length}'))), [groceryOrdersRepositoryProvider.overrideWithValue(repo)]);
      expect(find.text('Tax invoice INV-1'), findsOneWidget);
      await tester.tap(find.text('PDF'));
      await tester.pumpAndSettle();
      expect(repo.pdfs, [('MKT00164', 3)]);
      expect(shared, ['Invoice-INV-1.pdf:4']);
    });

    testWidgets('no invoices issued yet: the card is not shown', (tester) async {
      await pumpScreen(tester, Scaffold(body: OrderInvoicesCard(orderNumber: 'MKT00164')), [groceryOrdersRepositoryProvider.overrideWithValue(_Orders(deliveredOrder()))]);
      expect(find.text('Invoices'), findsNothing);
    });
  });
}
