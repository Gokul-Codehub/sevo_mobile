import 'package:calservices_customer/features/payment/domain/payment_failure.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  PaymentFailureKind kind({int? code, String? message}) => classifyPaymentFailure(code: code, message: message).kind;

  test('cancelled by the customer', () {
    expect(kind(code: 0), PaymentFailureKind.userCancelled);
    expect(kind(message: 'Payment cancelled by user'), PaymentFailureKind.userCancelled);
  });

  test('bank / card problems', () {
    expect(kind(message: 'Your card was declined'), PaymentFailureKind.bankDeclined);
    expect(kind(message: 'Insufficient funds'), PaymentFailureKind.bankDeclined);
  });

  test('timeouts and lost connection are told apart', () {
    expect(kind(message: 'Request timed out'), PaymentFailureKind.timeout);
    expect(kind(code: 2), PaymentFailureKind.networkLost);
    expect(kind(message: 'No internet connection'), PaymentFailureKind.networkLost);
  });

  test('gateway problems', () {
    expect(kind(code: 1), PaymentFailureKind.gatewayError);
    expect(kind(message: 'Unable to launch Razorpay checkout'), PaymentFailureKind.gatewayError);
  });

  test('anything else is unknown, with a safe next step', () {
    final info = classifyPaymentFailure(message: 'weird');
    expect(info.kind, PaymentFailureKind.unknown);
    expect(info.nextStep, contains('support'));
    expect(classifyPaymentFailure().kind, PaymentFailureKind.unknown);
  });

  test('every outcome has a title, message and next step, and never exposes raw error text', () {
    for (final input in [(0, null), (2, null), (1, null), (null, 'declined'), (null, 'timeout'), (null, 'SOME_INTERNAL_CODE_XYZ')]) {
      final i = classifyPaymentFailure(code: input.$1, message: input.$2);
      expect(i.title, isNotEmpty);
      expect(i.message, isNotEmpty);
      expect(i.nextStep, isNotEmpty);
      expect(i.message.contains('SOME_INTERNAL_CODE_XYZ'), isFalse);
    }
  });
}
