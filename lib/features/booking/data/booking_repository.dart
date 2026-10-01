import 'package:decimal/decimal.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/api_error.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/response_normalizer.dart';
import '../domain/booking_models.dart';

/// Repository for booking creation, lifecycle management, and actions.
class BookingRepository {
  BookingRepository({required this.api});

  final ApiClient api;

  // ── Create booking ────────────────────────────────────────────────────────
  Future<Result<Booking>> createBooking({
    required List<CartItem> items,
    required int addressId,
    // Fixed 2026-09-24: `address` is a free-text field on the backend's
    // ServiceRequest model (service_requests/models.py) -- it is what the
    // vendor app, its technician, and CalServices staff actually read to
    // find the customer, and it is NOT auto-resolved server-side from
    // `address_id`. This used to be omitted, so the payload below sent the
    // numeric address ID itself as the address text (see the old
    // `'address': addressId` line this replaces) -- the vendor/technician
    // side would have seen a bare number like "42" instead of a street
    // address. Callers now pass the full formatted address string (see
    // Address.formattedAddress) so the real destination is what gets sent.
    String? fullAddress,
    required String scheduledDate,
    required String scheduledTimeSlot,
    required Decimal totalAmount,
    String? specialInstructions,
    String? contactPhone,
    String? customerName,
    double? latitude,
    double? longitude,
    // ── Goods & Transport (logistics) fields ──────────────────────────────
    // Added 2026-09-19. Verified against the real backend serializer
    // (`ServiceRequestPublicCreateSerializer`, serializers.py:218-243): all
    // optional/nullable, so a non-logistics booking omits them entirely and
    // this method's behavior for every existing caller is unchanged.
    String? dropAddress,
    double? dropLatitude,
    double? dropLongitude,
    int? logisticsTier,
    int? logisticsLane,
    Decimal? declaredValue,
    String? consigneeRelationship,
    String? dropContactName,
    String? dropContactPhone,
    String? dropContactEmail,
    bool? insuranceOptedIn,
    String? jobType,
    // Added 2026-09-20: for Goods & Transport bookings, `service_category`
    // must be exactly "goods_transport_truck" / "goods_transport_two_wheeler"
    // (backend's `LOGISTICS_CATEGORIES` / `DISTANCE_PRICED_CATEGORIES` in
    // service_requests/services/logistics_pricing.py) — never the generic
    // catalog category slug. Sending the catalog slug instead made the
    // backend treat the booking as non-logistics entirely (silently
    // skipping fare/tier resolution), which is likely why "Confirm Booking"
    // was failing validation. When set, this replaces the slug-based
    // `categorySlugForZoneCheck` below; every other (non-logistics) caller
    // leaves this null and keeps the existing slug behavior unchanged.
    String? serviceCategoryOverride,
    // Added 2026-09-20 for Packers & Movers: the backend's booking-time fare
    // verification (`resolve_logistics_fare_v2` → the `service_category ==
    // "packers_movers"` branch in service_requests/services/
    // logistics_pricing.py) reads `cart_data[0]` directly for `quote_id`,
    // `tier_id`, `city`, `inventory`, `packing_tier`, floor/lift and
    // dismantling/unpacking flags — an exact match against what the prior
    // `POST /logistics/packers-movers/quote/` call was given, or the
    // booking is rejected. That is a completely different shape from the
    // generic `[{id, name, price, quantity, categoryName}, ...]` cart_data
    // built below for every other booking, so when provided this replaces
    // the auto-built cart_data entirely rather than being merged with it.
    List<Map<String, dynamic>>? cartDataOverride,
  }) async {
    try {
      // Fixed 2026-10-01: these two checks used to be `assert()`s. An
      // `assert` is stripped entirely in release builds (so it protects
      // nothing in production), and even in debug/profile builds it throws
      // an `AssertionError` — which is NOT an `Exception`, so the
      // `on Exception catch (e)` below this block never caught it. That let
      // an uncaught `AssertionError` escape this method, skip
      // `BookingActionController.createBooking`'s (equally unguarded) call
      // site, and land directly inside `checkout_screen.dart`'s
      // `_handlePlaceOrder()` — crashing past the line that resets
      // `_isLoading = false` and shows the result. A booking attempt that
      // hits this (e.g. a catalog item whose `service.id` never resolved to
      // a real positive ID) would silently die mid-request in debug/profile
      // builds instead of showing any error at all. Real, always-on checks
      // that return a normal [Failure] instead — same as every other
      // validation failure in this method — fix both problems.
      if (items.isEmpty) {
        return const Failure(ValidationError('Please select a service first.'));
      }
      for (final item in items) {
        if (item.service.id <= 0) {
          return const Failure(ValidationError(
            'This service could not be identified. Please go back and select it again.',
          ));
        }
        debugPrint(
            '[BookingRepository] Preparing booking item -> ID: ${item.service.id}, title: "${item.service.title}", slug: "${item.service.slug}", qty: ${item.quantity}, price: ${item.unitPrice}');
      }

      final firstItem = items.first;
      final categoryId = firstItem.service.categoryId ?? 18;
      // Fixed 2026-09-16: this used to send the numeric category ID (e.g.
      // "15") as `service_category`. The backend's server-side service-area
      // gate (settings_hub/service_zone_engine.py:_matches_service_slug,
      // called from BookingCreateView via check_booking_eligibility) treats
      // `service_category` as a SLUG and matches it against the admin's
      // configured ServiceZoneService.service_slug alias table (e.g.
      // "vegetables", "plumbing", "ac-service-cleaning") — a bare integer
      // never matches any of those, so for any zone the admin has attached
      // per-service restrictions to, every single booking attempt failed
      // with "The selected service is not available at your location."
      // regardless of which service or category was actually booked. This
      // is the exact root cause of that error appearing for every service
      // and every grocery item. Sending the real category slug (already
      // resolved from the live catalog, never guessed) is what the zone
      // engine actually expects.
      final categorySlugForZoneCheck =
          (firstItem.service.categorySlug ?? '').trim();
      final payload = <String, dynamic>{
        'address_id': addressId,
        'address': (fullAddress != null && fullAddress.isNotEmpty) ? fullAddress : addressId,
        'scheduled_date': scheduledDate,
        'preferred_date': scheduledDate,
        'scheduled_time_slot': scheduledTimeSlot,
        'preferred_time_slot': scheduledTimeSlot,
        // Fixed 2026-10-01: the backend's ServiceRequestPublicCreateSerializer
        // and BookingCreateView.post() only ever read the key `preferred_time`
        // (service_requests/serializers.py, service_requests/views.py ->
        // validate_slot_availability_for_booking(preferred_time=...)). This
        // app never sent that exact key, so the backend always resolved it to
        // None, parse_slot_time(None) returned None, and every single booking
        // failed with "Invalid or unparseable time slot." regardless of the
        // slot actually picked. Sending the real key fixes that for all
        // home-service bookings.
        'preferred_time': scheduledTimeSlot,
        'service_id': firstItem.service.id,
        'issue_title': firstItem.service.title,
        'service_category': (serviceCategoryOverride != null && serviceCategoryOverride.isNotEmpty)
            ? serviceCategoryOverride
            : (categorySlugForZoneCheck.isNotEmpty ? categorySlugForZoneCheck : categoryId),
        // The backend's create serializer stores whatever total_amount is
        // submitted directly — it does NOT recompute it from cart_data at
        // create time (that recompute only happens on the list/detail
        // endpoints). Omitting this field is what was making the amount
        // show as 0 right after booking.
        'total_amount': totalAmount.toString(),
        if (contactPhone != null && contactPhone.isNotEmpty) ...{
          'phone': contactPhone,
          'contact_phone': contactPhone,
        },
        if (customerName != null && customerName.isNotEmpty) 'customer_name': customerName,
        if (specialInstructions != null && specialInstructions.isNotEmpty) ...{
          'special_instructions': specialInstructions,
          'description': specialInstructions,
          'notes': specialInstructions,
        },
        // Fixed 2026-08-27: the booking-create call never sent coordinates at
        // all. Confirmed against the live backend that ServiceRequest has its
        // own dedicated latitude/longitude columns (separate from the
        // technician's own lat/lng) which the create serializer accepts and
        // stores directly — without this, every booking's location was
        // silently stored as null, which would break proximity-based vendor
        // allocation, initial map pin placement, and tracking ETA.
        'latitude': ?latitude,
        'longitude': ?longitude,
        // Goods & Transport fields — see the ServiceRequestPublicCreateSerializer
        // field list cited above. Sent only when actually provided, so this
        // is a no-op for every non-logistics booking.
        if (dropAddress != null && dropAddress.isNotEmpty) 'drop_address': dropAddress,
        'drop_latitude': ?dropLatitude,
        'drop_longitude': ?dropLongitude,
        if (logisticsTier != null) 'logistics_tier': logisticsTier,
        if (logisticsLane != null) 'logistics_lane': logisticsLane,
        if (declaredValue != null) 'declared_value': declaredValue.toString(),
        if (consigneeRelationship != null && consigneeRelationship.isNotEmpty)
          'consignee_relationship': consigneeRelationship,
        if (dropContactName != null && dropContactName.isNotEmpty)
          'drop_contact_name': dropContactName,
        if (dropContactPhone != null && dropContactPhone.isNotEmpty)
          'drop_contact_phone': dropContactPhone,
        if (dropContactEmail != null && dropContactEmail.isNotEmpty)
          'drop_contact_email': dropContactEmail,
        if (insuranceOptedIn != null) 'insurance_opted_in': insuranceOptedIn,
        if (jobType != null && jobType.isNotEmpty) 'job_type': jobType,
        'items': items.map((i) => i.toJson()).toList(),
        'cart_data': (cartDataOverride != null && cartDataOverride.isNotEmpty)
            ? cartDataOverride
            : items
                .map((i) => {
                      'id': i.service.id,
                      'name': i.service.title,
                      'price': i.unitPrice.toDouble(),
                      'quantity': i.quantity,
                      'categoryName': i.service.categoryName ?? '',
                    })
                .toList(),
      };

      debugPrint(
          '[BookingRepository] POST /booking/ payload: categoryId=$categoryId, serviceId=${firstItem.service.id}, addressId=$addressId, date=$scheduledDate, slot=$scheduledTimeSlot, itemsCount=${items.length}, totalAmount=$totalAmount');
      final response = await api.post('/booking/', data: payload);
      final createResult = ResponseNormalizer.extract(
        response,
        (data) => Booking.fromJson(
          data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{},
        ),
      );

      switch (createResult) {
        case Success(:final data):
          // The create endpoint's own response is sparse (id / request_id /
          // payment fields only) — total_amount, items and status are only
          // authoritative from the list/detail endpoints. Fetch the full
          // record so the success screen never shows a stale or zero
          // amount.
          final detailResult = await getBookingDetail(data.id);
          if (detailResult is Success<Booking> &&
              detailResult.data.totalAmount > Decimal.zero) {
            return detailResult;
          }
          // Detail fetch failed or is itself still zero — patch the sparse
          // create response with the client-computed total so the amount
          // shown is never a bare zero.
          if (data.totalAmount <= Decimal.zero) {
            return Success(Booking(
              id: data.id,
              requestId: data.requestId,
              status: data.status,
              totalAmount: totalAmount,
              advanceAmount:
                  data.advanceAmount > Decimal.zero ? data.advanceAmount : totalAmount,
              balanceAmount: data.balanceAmount,
              paymentStatus: data.paymentStatus,
              paymentOrderId: data.paymentOrderId,
              availableActions: data.availableActions,
              items: data.items.isNotEmpty ? data.items : items,
              address: data.address,
              scheduledDate:
                  data.scheduledDate.isEmpty ? scheduledDate : data.scheduledDate,
              scheduledTimeSlot: data.scheduledTimeSlot.isEmpty
                  ? scheduledTimeSlot
                  : data.scheduledTimeSlot,
              specialInstructions: data.specialInstructions ?? specialInstructions,
              technician: data.technician,
              cancellationReason: data.cancellationReason,
              createdAt: data.createdAt,
              trackingIdentifier: data.trackingIdentifier,
            ));
          }
          return createResult;
        case Failure():
          return createResult;
      }
    } on Exception catch (e) {
      return Failure(_toError(e));
    }
  }

  // ── Get list of customer bookings ─────────────────────────────────────────
  Future<Result<List<Booking>>> getMyBookings({String? statusFilter}) async {
    try {
      final query = <String, dynamic>{};
      if (statusFilter != null && statusFilter.isNotEmpty) {
        query['status'] = statusFilter;
      }

      final response = await api.get('/booking/my-bookings/', queryParameters: query);
      final dynamic body = response.data;

      // 1. Check for envelope error response
      if (body is Map) {
        if (body.containsKey('success') && body['success'] == false) {
          final msg = body['message']?.toString() ?? 'Failed to load bookings.';
          return Failure(ValidationError(msg));
        }
      }

      // 2. Extract list according to proven production contract:
      // Primary: {success: true, data: [ ... ], message: ""}
      // Secondary: [ ... ] or {results: [ ... ]} or {data: {items: [ ... ]}}
      final dynamic listPayload;
      if (body is Map) {
        final d = body['data'];
        if (d is List) {
          listPayload = d;
        } else if (d is Map && d['results'] is List) {
          listPayload = d['results'];
        } else if (d is Map && d['items'] is List) {
          listPayload = d['items'];
        } else if (d is Map && d['bookings'] is List) {
          listPayload = d['bookings'];
        } else if (body['results'] is List) {
          listPayload = body['results'];
        } else if (body['bookings'] is List) {
          listPayload = body['bookings'];
        } else if (body['items'] is List) {
          listPayload = body['items'];
        } else if (d == null && !body.containsKey('data')) {
          return const Failure(ApiContractError(
            endpoint: 'GET /api/booking/my-bookings/',
            expected: 'Object with "data" or "results" list field',
            actual: 'Object without data/results fields',
          ));
        } else if (d == null) {
          listPayload = const [];
        } else {
          listPayload = d;
        }
      } else if (body is List) {
        listPayload = body;
      } else {
        return Failure(ApiContractError(
          endpoint: 'GET /api/booking/my-bookings/',
          expected: 'JSON Object with "data" list or JSON Array',
          actual: '${body.runtimeType}',
        ));
      }

      // 3. Ensure listPayload is strictly a List
      if (listPayload is! List) {
        return Failure(ApiContractError(
          endpoint: 'GET /api/booking/my-bookings/',
          expected: 'data = List',
          actual: 'data = ${listPayload.runtimeType}',
        ));
      }

      // 4. Parse each booking item strictly
      final bookings = <Booking>[];
      for (final item in listPayload) {
        if (item is! Map) {
          return Failure(ApiContractError(
            endpoint: 'GET /api/booking/my-bookings/',
            expected: 'booking item = Map',
            actual: 'booking item = ${item.runtimeType}',
          ));
        }
        bookings.add(Booking.fromJson(Map<String, dynamic>.from(item)));
      }

      return Success(bookings);
    } on Exception catch (e) {
      return Failure(_toError(e));
    }
  }

  // ── Get single booking detail ─────────────────────────────────────────────
  Future<Result<Booking>> getBookingDetail(int id) async {
    try {
      // 1. Live authenticated backend returns customer bookings on /booking/my-bookings/
      final listResult = await getMyBookings();
      if (listResult is Success<List<Booking>>) {
        final match = listResult.data.where((b) => b.id == id).firstOrNull;
        if (match != null) {
          return Success(match);
        }
      }

      // 2. Direct endpoint fallback
      final response = await api.get('/booking/$id/');
      return ResponseNormalizer.extract(
        response,
        (data) {
          final map = data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{};
          final inner = map['booking'] is Map
              ? Map<String, dynamic>.from(map['booking'] as Map)
              : (map['data'] is Map ? Map<String, dynamic>.from(map['data'] as Map) : map);
          return Booking.fromJson(inner);
        },
      );
    } on Exception catch (e) {
      return Failure(_toError(e));
    }
  }

  // ── Cancel booking ────────────────────────────────────────────────────────
  Future<Result<Booking>> cancelBooking({
    required int id,
    required String reason,
  }) async {
    try {
      final response = await api.post(
        '/booking/$id/cancel/',
        data: {'reason': reason},
      );
      return ResponseNormalizer.extract(
        response,
        (data) {
          final map = data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{};
          final inner = map['booking'] is Map
              ? Map<String, dynamic>.from(map['booking'] as Map)
              : (map['data'] is Map ? Map<String, dynamic>.from(map['data'] as Map) : map);
          return Booking.fromJson(inner);
        },
      );
    } on Exception catch (e) {
      return Failure(_toError(e));
    }
  }

  // ── Reschedule booking ────────────────────────────────────────────────────
  Future<Result<Booking>> rescheduleBooking({
    required int id,
    required String date,
    required String slot,
  }) async {
    try {
      final response = await api.post(
        '/customer/reschedules/create/',
        data: {
          'booking_id': id,
          'preferred_date': date,
          'preferred_slot': slot,
        },
      );
      return ResponseNormalizer.extract(
        response,
        (data) {
          final map = data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{};
          final inner = map['booking'] is Map
              ? Map<String, dynamic>.from(map['booking'] as Map)
              : (map['data'] is Map ? Map<String, dynamic>.from(map['data'] as Map) : map);
          return Booking.fromJson(inner);
        },
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
final bookingRepositoryProvider = Provider<BookingRepository>((ref) {
  return BookingRepository(api: ref.watch(apiClientProvider));
});
