import 'package:decimal/decimal.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/api_error.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/response_normalizer.dart';
import '../domain/payment_models.dart';

/// Repository for Razorpay order generation and cryptographic payment verification.
class PaymentRepository {
  PaymentRepository({required this.api});

  final ApiClient api;

  // ── Create payment order ──────────────────────────────────────────────────
  Future<Result<PaymentOrder>> createPaymentOrder({
    required int bookingId,
    Decimal? amount,
    String? paymentType, // 'advance' | 'balance' | 'full'
  }) async {
    try {
      final payload = <String, dynamic>{
        'booking_id': bookingId,
      };
      if (amount != null) {
        payload['amount'] = amount.toString();
      }
      if (paymentType != null) {
        payload['payment_type'] = paymentType;
      }

      final response = await api.post(
        '/v1/payment/order/',
        data: payload,
      );
      return ResponseNormalizer.extract(
        response,
        (data) => PaymentOrder.fromJson(
          data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{},
        ),
      );
    } on Exception catch (e) {
      return Failure(_toError(e));
    }
  }

  // ── Verify Razorpay payment signature on backend ──────────────────────────
  Future<Result<Map<String, dynamic>>> verifyPayment(
    PaymentVerificationPayload payload,
  ) async {
    try {
      final response = await api.post(
        '/payment/verify/',
        data: payload.toJson(),
      );
      return ResponseNormalizer.extract(
        response,
        (data) => data is Map<String, dynamic> ? data : {'status': 'verified'},
      );
    } on Exception catch (e) {
      return Failure(_toError(e));
    }
  }

  ApiError _toError(Object e) {
    if (e is ApiError) return e;
    if (e is DioException && e.error is ApiError) {
      return e.error! as ApiError;
    }
    return UnknownError(e.toString());
  }
}

// ── Provider ─────────────────────────────────────────────────────────────────
final paymentRepositoryProvider = Provider<PaymentRepository>((ref) {
  return PaymentRepository(api: ref.watch(apiClientProvider));
});
