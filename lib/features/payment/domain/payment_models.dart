import 'package:decimal/decimal.dart';
import 'package:equatable/equatable.dart';

import '../../../core/network/response_normalizer.dart';

/// Payment order details returned by backend for Razorpay checkout.
class PaymentOrder extends Equatable {
  const PaymentOrder({
    required this.orderId,
    required this.amount,
    this.amountInPaiseDirect,
    this.currency = 'INR',
    this.keyId,
    this.bookingId,
    this.receipt,
  });

  final String orderId; // Razorpay Order ID (e.g. "order_NWxxx")
  final Decimal amount; // Amount in Rupees
  final int? amountInPaiseDirect;
  final String currency;
  final String? keyId; // Razorpay public key ID
  final int? bookingId;
  final String? receipt;

  /// Amount in paise for Razorpay SDK (1 INR = 100 paise)
  int get amountInPaise =>
      amountInPaiseDirect ?? (amount * Decimal.fromInt(100)).toBigInt().toInt();

  factory PaymentOrder.fromJson(Map<String, dynamic> json) {
    final rawAmount = json['amount'] ?? json['total_amount'] ?? 0;
    final int? parsedInt = int.tryParse(rawAmount.toString());

    // If backend provided an integer amount >= 100 in Paise (e.g. 49800 paise per Bible §4.5):
    final bool isDirectPaise = rawAmount is int || (rawAmount is String && !rawAmount.contains('.'));
    final int? directPaise = (isDirectPaise && parsedInt != null && parsedInt >= 100) ? parsedInt : null;

    final Decimal amountInRupees = directPaise != null
        ? (Decimal.fromInt(directPaise) / Decimal.fromInt(100)).toDecimal()
        : parseMoney(rawAmount);

    return PaymentOrder(
      orderId: (json['order_id'] ?? json['id'] ?? json['razorpay_order_id'] ?? '').toString(),
      amount: amountInRupees,
      amountInPaiseDirect: directPaise,
      currency: (json['currency'] ?? 'INR').toString(),
      keyId: json['key_id']?.toString() ?? json['key']?.toString() ?? json['razorpay_key_id']?.toString(),
      bookingId: parseIntOrNull(json['booking_id']),
      receipt: json['receipt']?.toString(),
    );
  }

  Map<String, dynamic> toJson() => {
        'order_id': orderId,
        'amount': amount.toString(),
        'currency': currency,
        if (keyId != null) 'key_id': keyId,
        if (bookingId != null) 'booking_id': bookingId,
        if (receipt != null) 'receipt': receipt,
      };

  @override
  List<Object?> get props => [orderId, amount, amountInPaiseDirect, currency, keyId, bookingId, receipt];
}

/// Verification payload sent to backend after Razorpay payment success.
class PaymentVerificationPayload extends Equatable {
  const PaymentVerificationPayload({
    required this.paymentId,
    required this.orderId,
    required this.signature,
    required this.bookingId,
  });

  final String paymentId;
  final String orderId;
  final String signature;
  final int bookingId;

  Map<String, dynamic> toJson() => {
        'razorpay_payment_id': paymentId,
        'razorpay_order_id': orderId,
        'razorpay_signature': signature,
        'booking_id': bookingId,
      };

  @override
  List<Object?> get props => [paymentId, orderId, signature, bookingId];
}

/// State of active payment operation.
sealed class PaymentState extends Equatable {
  const PaymentState();
}

final class PaymentInitial extends PaymentState {
  const PaymentInitial();
  @override
  List<Object?> get props => [];
}

final class PaymentProcessing extends PaymentState {
  const PaymentProcessing({this.statusMessage = 'Opening secure checkout...'});
  final String statusMessage;
  @override
  List<Object?> get props => [statusMessage];
}

final class PaymentSuccess extends PaymentState {
  const PaymentSuccess({
    required this.paymentId,
    required this.orderId,
    required this.bookingId,
  });
  final String paymentId;
  final String orderId;
  final int bookingId;
  @override
  List<Object?> get props => [paymentId, orderId, bookingId];
}

final class PaymentFailed extends PaymentState {
  const PaymentFailed({required this.errorMessage, this.code});
  final String errorMessage;
  final int? code;
  @override
  List<Object?> get props => [errorMessage, code];
}
