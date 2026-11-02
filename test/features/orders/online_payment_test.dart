import 'dart:convert';

import 'package:calservices_customer/core/errors/api_error.dart';
import 'package:calservices_customer/core/network/api_client.dart';
import 'package:calservices_customer/features/booking/domain/booking_models.dart';
import 'package:calservices_customer/features/catalog/data/marketplace_catalog_repository.dart';
import 'package:calservices_customer/features/orders/data/grocery_orders_repository.dart';
import 'package:calservices_customer/features/orders/data/marketplace_online_payment.dart';
import 'package:calservices_customer/features/payment/domain/payment_models.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

CartItem item() => CartItem(service: MarketplaceProduct.fromJson({'id': 5, 'title': 'Bread', 'selling_price': '45'}).toServiceItem(), quantity: 2);

MarketplaceCheckout checkout() => const MarketplaceCheckout(
      address: '12 Main Road',
      name: 'Asha',
      phone: '9876543210',
      email: 'a@x.com',
      instant: true,
      idempotencyKey: 'k',
      paymentMethod: 'UPI',
    );

class _Adapter implements HttpClientAdapter {
  _Adapter({this.initiate, this.verifyStatus = 201, this.verifyBody});
  final Map<String, Object?>? initiate;
  final int verifyStatus;
  final Map<String, Object?>? verifyBody;
  final List<RequestOptions> calls = [];

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<List<int>>? requestStream, Future<void>? cancelFuture) async {
    calls.add(options);
    Object body = {'success': true, 'data': {}};
    var status = 200;
    if (options.path.contains('initiate-payment')) {
      body = {'success': true, 'data': initiate ?? {'order_id': 'order_X1', 'amount': '90.00', 'provider': 'razorpay', 'key_id': 'rzp_test_1'}};
    } else if (options.path.contains('verify-payment')) {
      status = verifyStatus;
      body = verifyBody ?? {'success': true, 'data': {'order_number': 'MKT00170', 'status': 'CONFIRMED', 'total_amount': '90.00'}};
    }
    return ResponseBody.fromString(jsonEncode(body), status, headers: {
      Headers.contentTypeHeader: ['application/json'],
    });
  }

  @override
  void close({bool force = false}) {}
}

class _Launcher implements PaymentLauncher {
  _Launcher(this.result);
  final PaymentCompletion result;
  final launched = <PaymentOrder>[];
  @override
  Future<PaymentCompletion> launch(PaymentOrder order, {required String name, required String email, required String phone}) async {
    launched.add(order);
    return result;
  }
}

GroceryOrdersRepository repoFor(_Adapter a) =>
    GroceryOrdersRepository(api: ApiClient.withDio(Dio(BaseOptions(baseUrl: 'https://x.test'))..httpClientAdapter = a));

void main() {
  test('the happy path: cart to server, payment created, paid, verified, order returned - in that order', () async {
    final a = _Adapter();
    final l = _Launcher(const PaymentCompletion(askServer: true, paymentId: 'pay_1', signature: 'sig'));
    final r = await repoFor(a).payOnline([item()], checkout(), launcher: l);
    expect((r as Success<List<GroceryOrder>>).data.single.orderNumber, 'MKT00170');
    expect(a.calls.map((c) => c.path), [
      '/api/carts/marketplace/clear/',
      '/api/carts/marketplace/items/',
      '/api/orders/marketplace/checkout/initiate-payment/',
      '/api/orders/marketplace/checkout/verify-payment/',
    ]);
    expect((a.calls[2].data as Map)['payment_method'], 'UPI');
    expect(l.launched.single.orderId, 'order_X1');
    expect(l.launched.single.provider, 'razorpay');
    expect(a.calls.last.data, {'order_id': 'order_X1', 'transaction_id': 'pay_1', 'signature': 'sig'});
  });

  test('a cancelled or failed payment creates nothing and never calls verify', () async {
    final a = _Adapter();
    final r = await repoFor(a).payOnline([item()], checkout(), launcher: _Launcher(const PaymentCompletion(askServer: false, message: 'Payment cancelled')));
    expect(r, isA<Failure<List<GroceryOrder>>>());
    expect((r as Failure).error.message, 'Payment cancelled');
    expect(a.calls.any((c) => c.path.contains('verify-payment')), isFalse);
  });

  test('Paytm: the page was closed, the server is still asked to confirm with empty ids', () async {
    final a = _Adapter(initiate: {'order_id': 'SEVOMART1', 'amount': '90.00', 'provider': 'paytm', 'txn_token': 't', 'mid': 'm', 'checkout_script_url': 'https://s.paytm/x.js'});
    final l = _Launcher(const PaymentCompletion(askServer: true));
    await repoFor(a).payOnline([item()], checkout(), launcher: l);
    expect(l.launched.single.provider, 'paytm');
    expect(a.calls.last.data, {'order_id': 'SEVOMART1', 'transaction_id': '', 'signature': ''});
  });

  test('the server refusing the payment is reported; no order is claimed', () async {
    final a = _Adapter(verifyStatus: 400, verifyBody: {'success': false, 'message': 'Payment not completed.', 'code': 'PAYMENT_FAILED'});
    final r = await repoFor(a).payOnline([item()], checkout(), launcher: _Launcher(const PaymentCompletion(askServer: true, paymentId: 'p', signature: 's')));
    expect(r, isA<Failure<List<GroceryOrder>>>());
  });

  test('an empty cart never reaches the server', () async {
    final a = _Adapter();
    final r = await repoFor(a).payOnline(const [], checkout(), launcher: _Launcher(const PaymentCompletion(askServer: false)));
    expect(r, isA<Failure<List<GroceryOrder>>>());
    expect(a.calls, isEmpty);
  });

  test('an unknown gateway tells the customer to use cash on delivery', () async {
    const launcher = GatewayPaymentLauncher();
    final done = await launcher.launch(PaymentOrder.fromJson({'order_id': 'o', 'amount': '10.00', 'provider': 'mystery'}), name: '', email: '', phone: '');
    expect(done.askServer, isFalse);
    expect(done.message, contains('cash on delivery'));
  });

  test('a non-production gateway passes the server-signed completion straight through', () async {
    const launcher = GatewayPaymentLauncher();
    final done = await launcher.launch(PaymentOrder.fromJson({'order_id': 'o', 'amount': '10.00', 'provider': 'paytm_mock', 'transaction_id': 'T1', 'signature': 'S1'}), name: '', email: '', phone: '');
    expect((done.askServer, done.paymentId, done.signature), (true, 'T1', 'S1'));
  });

  test('the checkout body says UPI for online and COD for cash', () {
    expect(checkout().toJson()['payment_method'], 'UPI');
    expect(const MarketplaceCheckout(address: 'a', name: '', phone: '', email: '', instant: true, idempotencyKey: 'k').toJson()['payment_method'], 'COD');
  });
}
