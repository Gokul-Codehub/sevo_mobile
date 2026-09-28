import 'package:calservices_customer/features/payment/domain/payment_models.dart';
import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Payment Domain & Amount Calculations', () {
    test('converts Decimal rupee amounts to integer paise for Razorpay SDK', () {
      final order1 = PaymentOrder(
        orderId: 'order_123',
        amount: Decimal.parse('599.00'),
      );
      expect(order1.amountInPaise, 59900);

      final order2 = PaymentOrder(
        orderId: 'order_456',
        amount: Decimal.parse('149.50'),
      );
      expect(order2.amountInPaise, 14950);
    });

    test('serializes verification payload correctly for backend HMAC verification', () {
      const payload = PaymentVerificationPayload(
        paymentId: 'pay_987654',
        orderId: 'order_123456',
        signature: 'sig_abcdef123456',
        bookingId: 42,
      );

      final json = payload.toJson();
      expect(json['razorpay_payment_id'], 'pay_987654');
      expect(json['razorpay_order_id'], 'order_123456');
      expect(json['razorpay_signature'], 'sig_abcdef123456');
      expect(json['booking_id'], 42);
    });

    test('parses direct Paise integer amount from backend (Bible §4.5) without double multiplication', () {
      final jsonFromBackend = {
        'order_id': 'order_Qz918kals810',
        'amount': 49800, // 49800 Paise returned by backend
        'currency': 'INR',
        'razorpay_key_id': 'rzp_live_caldimservices',
      };

      final order = PaymentOrder.fromJson(jsonFromBackend);
      expect(order.amountInPaise, 49800);
      expect(order.amount, Decimal.parse('498.00'));
    });
  });
}
