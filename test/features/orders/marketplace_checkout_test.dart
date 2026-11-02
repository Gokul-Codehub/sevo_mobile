import 'dart:convert';

import 'package:calservices_customer/core/errors/api_error.dart';
import 'package:calservices_customer/core/network/api_client.dart';
import 'package:calservices_customer/features/booking/domain/booking_models.dart';
import 'package:calservices_customer/features/booking/domain/cart_notifier.dart';
import 'package:calservices_customer/features/booking/domain/marketplace_cart.dart';
import 'package:calservices_customer/features/catalog/data/marketplace_catalog_repository.dart';
import 'package:calservices_customer/features/catalog/domain/catalog_models.dart';
import 'package:calservices_customer/features/orders/data/grocery_orders_repository.dart';
import 'package:decimal/decimal.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

CartItem product(int id, int qty, {String price = '40.00'}) => CartItem(
      service: MarketplaceProduct.fromJson({'id': id, 'title': 'P$id', 'selling_price': price}).toServiceItem(),
      quantity: qty,
    );

CartItem comboLine(int id, int qty, {required String key, int unit = 1}) => CartItem(
      service: MarketplaceProduct.fromJson({'id': id, 'title': 'C$id', 'selling_price': '10'}).toServiceItem(),
      quantity: qty,
      comboKey: key,
      comboTitle: 'Combo',
      comboUnitQty: unit,
    );

class _Adapter implements HttpClientAdapter {
  _Adapter({this.checkoutStatus = 200, Map<String, Object?>? checkoutBody})
      : checkoutBody = checkoutBody ??
            {
              'success': true,
              'data': {'order_number': 'MKT00170', 'status': 'CONFIRMED', 'total_amount': '80.00'},
            };
  final int checkoutStatus;
  final Map<String, Object?> checkoutBody;
  final List<RequestOptions> calls = [];

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<List<int>>? requestStream, Future<void>? cancelFuture) async {
    calls.add(options);
    final isCheckout = options.path.contains('/orders/marketplace/checkout/');
    final body = isCheckout ? checkoutBody : {'success': true, 'data': {}};
    return ResponseBody.fromString(jsonEncode(body), isCheckout ? checkoutStatus : 200, headers: {
      Headers.contentTypeHeader: ['application/json'],
    });
  }

  @override
  void close({bool force = false}) {}
}

GroceryOrdersRepository repoFor(_Adapter a) =>
    GroceryOrdersRepository(api: ApiClient.withDio(Dio(BaseOptions(baseUrl: 'https://example.test'))..httpClientAdapter = a));

MarketplaceCheckout checkout({bool instant = true, String key = 'k1'}) => MarketplaceCheckout(
      address: '12 Main Road, Hosur',
      name: 'Asha',
      phone: '9876543210',
      email: 'a@x.com',
      lat: 12.7409123456,
      lng: 77.8253,
      instant: instant,
      slotId: 7,
      slotLabel: '2:00 PM - 3:00 PM',
      slotDate: '2026-11-03',
      slotStart: '14:00',
      slotEnd: '15:00',
      idempotencyKey: key,
    );

void main() {
  group('which carts go through the marketplace checkout', () {
    test('only a cart made entirely of Seller Hub products', () {
      expect(isMarketplaceCart([product(5, 1)]), isTrue);
      expect(isMarketplaceCart(const []), isFalse);
      final legacy = CartItem(service: ServiceItem(id: 12, title: 'Tomato', slug: 't', price: Decimal.parse('10')), quantity: 1);
      expect(isMarketplaceCart([product(5, 1), legacy]), isFalse);
    });

    test('single products map to server cart lines with their real Seller Hub id', () {
      final e = marketplaceCartEntries([product(5, 2), product(9, 1)]);
      expect(e.map((x) => x.toJson()), [
        {'seller_product_id': 5, 'quantity': 2},
        {'seller_product_id': 9, 'quantity': 1},
      ]);
    });

    test('a combo is ONE basket line with the combo count, not one line per product', () {
      final items = [
        comboLine(1, 4, key: '8:1,2', unit: 2), // combo bought twice (2 per combo)
        comboLine(2, 2, key: '8:1,2', unit: 1),
        product(5, 1),
      ];
      expect(marketplaceCartEntries(items).map((x) => x.toJson()), [
        {'basket_id': 8, 'quantity': 2},
        {'seller_product_id': 5, 'quantity': 1},
      ]);
    });
  });

  group('cart total matches what the server charges', () {
    test('a Seller Hub cart has no delivery, handling, small-order fee or tip', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.read(cartProvider.notifier).addService(product(5, 1, price: '44').service);
      final s = container.read(cartSummaryProvider);
      expect(s.subtotal, Decimal.parse('44'));
      expect((s.deliveryFee, s.handlingFee, s.smallCartFee, s.tipAmount), (Decimal.zero, Decimal.zero, Decimal.zero, Decimal.zero));
      expect(s.total, Decimal.parse('44'));
    });
  });

  group('placing the order', () {
    test('puts the cart on the server, then checks out - in that order - with the same fields as the web', () async {
      final a = _Adapter();
      final r = await repoFor(a).place([product(5, 2)], checkout());
      final paths = a.calls.map((c) => c.path).toList();
      expect(paths, ['/api/carts/marketplace/clear/', '/api/carts/marketplace/items/', '/api/orders/marketplace/checkout/']);
      expect(a.calls[1].data, {'seller_product_id': 5, 'quantity': 2});
      final body = a.calls[2].data as Map;
      expect(body['payment_method'], 'COD');
      expect(body['fulfilment_type'], 'DELIVERY');
      expect(body['delivery_type'], 'FAST');
      expect(body['delivery_slot'], 'Immediate');
      expect(body['delivery_address'], '12 Main Road, Hosur');
      expect(body['delivery_latitude'], 12.740912);
      expect(body.containsKey('delivery_slot_id'), isFalse); // instant: no slot, like the web
      expect(a.calls[2].headers['Idempotency-Key'], 'k1');
      expect((r as Success<List<GroceryOrder>>).data.single.orderNumber, 'MKT00170');
    });

    test('a scheduled slot sends the slot id, date and start/end times', () async {
      final a = _Adapter();
      await repoFor(a).place([product(5, 1)], checkout(instant: false));
      final body = a.calls.last.data as Map;
      expect(body['delivery_type'], 'SLOT');
      expect(body['delivery_slot'], '2:00 PM - 3:00 PM');
      expect(body['delivery_slot_id'], 7);
      expect(body['delivery_date'], '2026-11-03');
      expect(body['delivery_slot_start'], '2026-11-03T14:00:00');
      expect(body['delivery_slot_end'], '2026-11-03T15:00:00');
    });

    test('several fulfilment groups come back as several orders', () async {
      final a = _Adapter(checkoutBody: {
        'success': true,
        'data': {
          'order_number': 'MKT1',
          'orders': [
            {'order_number': 'MKT1', 'status': 'CONFIRMED'},
            {'order_number': 'MKT2', 'status': 'CONFIRMED'},
          ],
        },
      });
      final r = await repoFor(a).place([product(5, 1)], checkout());
      expect((r as Success<List<GroceryOrder>>).data.map((o) => o.orderNumber), ['MKT1', 'MKT2']);
    });

    test('a server refusal (e.g. out of stock) comes back as an error and the order is not reported placed', () async {
      final a = _Adapter(checkoutStatus: 409, checkoutBody: {'success': false, 'message': 'Only 1 left of P5.', 'code': 'INSUFFICIENT_STOCK'});
      final r = await repoFor(a).place([product(5, 3)], checkout());
      expect(r, isA<Failure<List<GroceryOrder>>>());
    });

    test('a cart with nothing orderable never calls the server', () async {
      final a = _Adapter();
      final r = await repoFor(a).place(const [], checkout());
      expect(r, isA<Failure<List<GroceryOrder>>>());
      expect(a.calls, isEmpty);
    });
  });

  test('orders from the list endpoint (fields nested under detail) parse the same as from the order endpoint', () {
    final o = GroceryOrder.tryParse({
      'order_type': 'marketplace',
      'order_number': 'MKT9',
      'status': 'PACKING',
      'total_amount': '88.00',
      'created_at': '2026-11-02T10:00:00Z',
      'detail': {
        'delivery_address': 'Hosur',
        'seller_name': 'SevoGrocery',
        'payment_method': 'COD',
        'items': [
          {'product_title': '2-Minute Masala Noodles', 'quantity': 2, 'unit_price_snapshot': '44.00', 'line_amount': '88.00'},
        ],
      },
    })!;
    expect((o.items.single.title, o.sellerName, o.deliveryAddress, o.isCod), ('2-Minute Masala Noodles', 'SevoGrocery', 'Hosur', true));
  });

  group('a server error says where it happened', () {
    GroceryOrdersRepository failing(String failPath, int status, Map<String, Object?> body) {
      final dio = Dio(BaseOptions(baseUrl: 'https://example.test'))
        ..httpClientAdapter = _PathAdapter(failPath, status, body);
      return GroceryOrdersRepository(api: ApiClient.withDio(dio));
    }

    test('a 500 while adding to the server cart names the step, the status and the server message', () async {
      final r = await failing('/carts/marketplace/items/', 500, {'message': 'Basket detail failed', 'code': 'VENDOR_DOWN'}).place([product(5, 1)], checkout());
      final msg = (r as Failure<List<GroceryOrder>>).error.message;
      expect(msg, contains('cart-add 500'));
      expect(msg, contains('VENDOR_DOWN'));
      expect(msg, contains('Basket detail failed'));
    });

    test('a 502 at checkout is named as the checkout step', () async {
      final r = await failing('/orders/marketplace/checkout/', 502, {'error': 'Seller could not accept the order'}).place([product(5, 1)], checkout());
      expect((r as Failure<List<GroceryOrder>>).error.message, contains('checkout 502'));
    });

    test('a normal refusal (409 out of stock) keeps its own message, untouched', () async {
      final r = await failing('/orders/marketplace/checkout/', 409, {'success': false, 'message': 'Only 1 left of P5.', 'code': 'INSUFFICIENT_STOCK'}).place([product(5, 3)], checkout());
      expect((r as Failure<List<GroceryOrder>>).error.message, isNot(contains('contact support')));
    });
  });
}

class _PathAdapter implements HttpClientAdapter {
  _PathAdapter(this.failPath, this.status, this.body);
  final String failPath;
  final int status;
  final Map<String, Object?> body;
  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<List<int>>? requestStream, Future<void>? cancelFuture) async {
    final fail = options.path.contains(failPath);
    return ResponseBody.fromString(jsonEncode(fail ? body : {'success': true, 'data': {}}), fail ? status : 200, headers: {
      Headers.contentTypeHeader: ['application/json'],
    });
  }

  @override
  void close({bool force = false}) {}
}
