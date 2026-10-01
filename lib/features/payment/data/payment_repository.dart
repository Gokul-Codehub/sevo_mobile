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
  // Fixed 2026-10-01 (production resolution — Payment scope): this was
  // posting to `/v1/payment/order/`, which normalizes (ApiClient._
  // normalizePath) to `/api/v1/payment/order/` — a path that does not exist
  // anywhere in the backend's urls.py. The real, already-implemented
  // endpoint is `PaymentInitiateView` at `/api/payment/initiate/`
  // (service_requests/urls.py / payment_views.py), which independently
  // computes the amount due server-side (advance/balance-aware) and
  // persists a real Payment row — the client's `amount`/`payment_type`
  // are not read by that view at all, so they're no longer sent; the
  // server decides what's owed, never the client.
  //
  // This 404 was the direct trigger for PaymentController's removed
  // "synthesize a fake order and open Razorpay anyway" fallback: every
  // real order-creation attempt failed before it ever reached the actual
  // backend logic below, which works correctly once called at the right
  // path.
  Future<Result<PaymentOrder>> createPaymentOrder({
    required int bookingId,
    Decimal? amount,
    String? paymentType, // 'advance' | 'balance' | 'full'
  }) async {
    try {
      final response = await api.post(
        '/payment/initiate/',
        data: {'booking_id': bookingId},
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
