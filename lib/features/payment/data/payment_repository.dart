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

  // ── Goods Transport / P&M payment options (web parity) ────────────────────

  /// GET /api/payment/config/ — what the server lets the booking pages offer.
  /// Fails closed (`online_available: false`) like the web client.
  Future<({bool onlineAvailable, bool walletPartPayment})> getPaymentConfig() async {
    try {
      final response = await api.get('/payment/config/');
      final res = ResponseNormalizer.extract<Map<String, dynamic>>(
        response,
        (d) => d is Map ? Map<String, dynamic>.from(d) : <String, dynamic>{},
      );
      if (res is Success<Map<String, dynamic>>) {
        return (
          onlineAvailable: parseBoolOrDefault(res.data['online_available'], false),
          walletPartPayment: parseBoolOrDefault(res.data['wallet_part_payment'], false),
        );
      }
    } on Exception {
      // fall through
    }
    return (onlineAvailable: false, walletPartPayment: false);
  }

  /// GET /api/wallet/ — the signed-in customer's SEVO wallet balance, or
  /// null (guest / unavailable).
  Future<double?> getWalletBalance() async {
    try {
      final response = await api.get('/wallet/');
      final res = ResponseNormalizer.extract<double?>(
        response,
        (d) => d is Map ? double.tryParse('${d['balance']}') : null,
      );
      return res is Success<double?> ? res.data : null;
    } on Exception {
      return null;
    }
  }

  /// POST /api/payment/wallet-pay/ — pay a GT / P&M booking from the wallet.
  /// `paid` = fully settled; `partial` = wallet spent, the remainder must be
  /// paid online (`remaining` rupees). The server decides every amount.
  Future<({bool paid, bool partial, double? remaining, String? error})> payWithWallet(
    int bookingId,
  ) async {
    try {
      final response = await api.post(
        '/payment/wallet-pay/',
        data: {'booking_id': bookingId, 'allow_partial': true},
      );
      final body = response.data;
      final data = body is Map && body['data'] is Map ? body['data'] as Map : (body is Map ? body : const {});
      final partial = data['partial'] == true;
      return (
        paid: !partial,
        partial: partial,
        remaining: double.tryParse('${data['remaining_due']}'),
        error: null,
      );
    } on DioException catch (e) {
      final d = e.response?.data;
      String? msg;
      if (d is Map) {
        msg = (d['message'] ?? d['error'] ?? d['detail'])?.toString();
        if (d['error'] is Map) msg = (d['error'] as Map)['message']?.toString() ?? msg;
      }
      return (
        paid: false,
        partial: false,
        remaining: null,
        error: msg ?? 'Wallet payment could not be completed.',
      );
    } on Exception catch (e) {
      return (paid: false, partial: false, remaining: null, error: e.toString());
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
