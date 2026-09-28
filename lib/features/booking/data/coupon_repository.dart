import 'package:decimal/decimal.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/api_error.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/response_normalizer.dart';

/// A real, admin-configured promotional coupon.
///
/// Added 2026-09-16: the checkout coupon sheet used to show three
/// hardcoded coupons (FIRSTSEVO / SEVOPRO / FREESHIP) with made-up amounts,
/// and `_applyCode` in checkout_screen.dart accepted ANY typed text as a
/// valid code, silently applying a guessed ₹50 discount to it. The real
/// backend already has a full coupon system (service_requests/views.py:
/// CustomerCouponListView + CustomerCouponValidateView, mounted at
/// /api/customer/coupons/ and /api/customer/coupons/validate/) — this
/// repository is what actually talks to it instead of the app inventing
/// coupons and discounts client-side.
class Coupon {
  const Coupon({
    required this.id,
    required this.code,
    required this.name,
    required this.description,
    required this.discountType,
    required this.discountValue,
    required this.maxDiscount,
    required this.minBooking,
  });

  final String id;
  final String code;
  final String name;
  final String description;

  /// "flat" or "percentage" — matches the real Coupon.discount_type field.
  final String discountType;
  final Decimal discountValue;
  final Decimal maxDiscount;
  final Decimal minBooking;

  bool get isPercentage => discountType.toLowerCase() == 'percentage';

  /// Human-readable headline, e.g. "Flat ₹150 OFF" / "15% OFF up to ₹250".
  String get title {
    if (isPercentage) {
      final pct = discountValue.toString();
      if (maxDiscount > Decimal.zero) {
        return '$pct% OFF up to ₹$maxDiscount';
      }
      return '$pct% OFF';
    }
    return 'Flat ₹$discountValue OFF';
  }

  String get subtitle => 'On orders above ₹$minBooking';

  factory Coupon.fromJson(Map<String, dynamic> json) {
    return Coupon(
      id: (json['id'] ?? '').toString(),
      code: (json['code'] ?? '').toString(),
      name: (json['name'] ?? '').toString(),
      description: (json['description'] ?? '').toString(),
      discountType: (json['discountType'] ?? json['discount_type'] ?? 'flat')
          .toString(),
      discountValue:
          parseMoneyOrNull(json['discountValue'] ?? json['discount_value']) ??
              Decimal.zero,
      maxDiscount:
          parseMoneyOrNull(json['maxDiscount'] ?? json['max_discount']) ??
              Decimal.zero,
      minBooking:
          parseMoneyOrNull(json['minBooking'] ?? json['min_booking']) ??
              Decimal.zero,
    );
  }
}

/// Result of validating a coupon code against the real cart total.
class CouponValidationResult {
  const CouponValidationResult({
    required this.couponCode,
    required this.discountAmount,
    required this.finalAmount,
    this.message,
  });

  final String couponCode;
  final Decimal discountAmount;
  final Decimal finalAmount;
  final String? message;

  factory CouponValidationResult.fromJson(Map<String, dynamic> json) {
    return CouponValidationResult(
      couponCode: (json['coupon_code'] ?? json['couponCode'] ?? '').toString(),
      discountAmount:
          parseMoneyOrNull(json['discountAmount'] ?? json['discount_amount']) ??
              Decimal.zero,
      finalAmount:
          parseMoneyOrNull(json['final_amount'] ?? json['finalAmount']) ??
              Decimal.zero,
      message: json['message']?.toString(),
    );
  }
}

class CouponRepository {
  CouponRepository({required this.api});

  final ApiClient api;

  /// GET /api/customer/coupons/ — active, admin-published coupons.
  Future<Result<List<Coupon>>> getCoupons() async {
    try {
      final response = await api.get('/customer/coupons/');
      return ResponseNormalizer.extract(response, (data) {
        final list = data is List
            ? data
            : (data is Map && data['results'] is List
                ? data['results'] as List
                : (data is Map && data['data'] is List ? data['data'] as List : []));
        return list
            .whereType<Map>()
            .map((m) => Coupon.fromJson(Map<String, dynamic>.from(m)))
            .toList();
      });
    } on Exception catch (e) {
      return Failure(_toError(e));
    }
  }

  /// POST /api/customer/coupons/validate/ — the ONLY source of truth for
  /// whether a coupon code is valid and what discount it actually earns.
  /// Never computed or guessed client-side.
  Future<Result<CouponValidationResult>> validateCoupon({
    required String code,
    required Decimal cartTotal,
  }) async {
    try {
      final response = await api.post(
        '/customer/coupons/validate/',
        data: {
          'code': code,
          'cart_total': cartTotal.toDouble(),
        },
      );
      return ResponseNormalizer.extract(
        response,
        (data) => CouponValidationResult.fromJson(
          data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{},
        ),
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

final couponRepositoryProvider = Provider<CouponRepository>((ref) {
  return CouponRepository(api: ref.watch(apiClientProvider));
});

/// Live list of active, admin-published coupons.
final availableCouponsProvider = FutureProvider<List<Coupon>>((ref) async {
  final repo = ref.watch(couponRepositoryProvider);
  final result = await repo.getCoupons();
  return switch (result) {
    Success(:final data) => data,
    Failure(:final error) => throw error,
  };
});
