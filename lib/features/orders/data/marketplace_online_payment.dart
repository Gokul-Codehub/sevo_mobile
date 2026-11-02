import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';

import '../../../routing/app_router.dart' show rootNavigatorKey;
import '../../payment/domain/payment_models.dart';
import '../../payment/presentation/screens/paytm_checkout_screen.dart';

/// How a gateway interaction ended. The app never decides whether money moved: [askServer] says whether the server
/// should be asked to verify (it is the only judge); [message] is shown when there is nothing to verify.
class PaymentCompletion {
  const PaymentCompletion({required this.askServer, this.paymentId = '', this.signature = '', this.message});
  final bool askServer;
  final String paymentId;
  final String signature;
  final String? message;
}

/// Opens the gateway the SERVER chose for this order and reports how it ended.
abstract class PaymentLauncher {
  Future<PaymentCompletion> launch(PaymentOrder order, {required String name, required String email, required String phone});
}

/// The real gateways: Razorpay (SDK) and Paytm (hosted checkout page), exactly as service payments already use them.
class GatewayPaymentLauncher implements PaymentLauncher {
  const GatewayPaymentLauncher();

  @override
  Future<PaymentCompletion> launch(PaymentOrder order, {required String name, required String email, required String phone}) async {
    switch (order.provider) {
      case 'paytm_mock':
      case 'sandbox':
        // Non-production: the server already signed the completion, nothing to open.
        return PaymentCompletion(askServer: true, paymentId: order.providerTransactionId ?? '', signature: order.providerSignature ?? '');
      case 'paytm':
        return _paytm(order);
      case 'razorpay':
        return _razorpay(order, name: name, email: email, phone: phone);
      default:
        return const PaymentCompletion(askServer: false, message: 'Online payment is not available right now. Please choose cash on delivery.');
    }
  }

  Future<PaymentCompletion> _paytm(PaymentOrder order) async {
    final navigator = rootNavigatorKey.currentState;
    final token = order.txnToken;
    final mid = order.mid;
    final script = order.checkoutScriptUrl;
    if (navigator == null || token == null || mid == null || script == null) {
      return const PaymentCompletion(askServer: false, message: 'Paytm checkout could not be started. Please try again.');
    }
    await navigator.push<bool>(MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => PaytmCheckoutScreen(orderId: order.orderId, mid: mid, txnToken: token, checkoutOrigin: Uri.parse(script).origin),
    ));
    // Closed by the customer or finished by Paytm: either way the server confirms with Paytm itself.
    return const PaymentCompletion(askServer: true);
  }

  Future<PaymentCompletion> _razorpay(PaymentOrder order, {required String name, required String email, required String phone}) async {
    final key = order.keyId;
    if (key == null) {
      return const PaymentCompletion(askServer: false, message: 'Online payment is not configured. Please choose cash on delivery.');
    }
    final done = Completer<PaymentCompletion>();
    final rp = Razorpay();
    rp.on(Razorpay.EVENT_PAYMENT_SUCCESS, (PaymentSuccessResponse r) {
      if (!done.isCompleted) done.complete(PaymentCompletion(askServer: true, paymentId: r.paymentId ?? '', signature: r.signature ?? ''));
    });
    rp.on(Razorpay.EVENT_PAYMENT_ERROR, (PaymentFailureResponse r) {
      if (!done.isCompleted) done.complete(PaymentCompletion(askServer: false, message: (r.message ?? '').isEmpty ? 'Payment was not completed.' : r.message));
    });
    rp.on(Razorpay.EVENT_EXTERNAL_WALLET, (ExternalWalletResponse _) {});
    try {
      rp.open({
        'key': key,
        'amount': order.amountInPaise,
        'name': 'Sevo Mart',
        'description': 'Grocery order',
        'order_id': order.orderId,
        'prefill': {if (phone.isNotEmpty) 'contact': phone, if (email.isNotEmpty) 'email': email, if (name.isNotEmpty) 'name': name},
        'theme': {'color': '#1B7F4B'},
        'retry': {'enabled': true, 'max_count': 3},
      });
      return await done.future;
    } catch (e) {
      return PaymentCompletion(askServer: false, message: 'Unable to open the payment screen: $e');
    } finally {
      rp.clear();
    }
  }
}

final paymentLauncherProvider = Provider<PaymentLauncher>((ref) => const GatewayPaymentLauncher());
