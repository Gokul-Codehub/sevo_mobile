import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/api_error.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/response_normalizer.dart';
import '../domain/logistics_models.dart';

/// Repository for serviceability checks and booking slot logistics.
class LogisticsRepository {
  LogisticsRepository({required this.api});

  final ApiClient api;

  // ── Check serviceability via Authoritative Service Zone Endpoint ──────────
  Future<Result<ServiceabilityResult>> checkServiceability({
    required String postalCode,
    double? latitude,
    double? longitude,
    String? serviceSlug,
  }) async {
    try {
      // Resolve coordinates (default to Hosur Central Hub if only postal code provided)
      double lat = latitude ?? 12.754598;
      double lng = longitude ?? 77.834477;
      if (latitude == null && longitude == null) {
        if (postalCode.startsWith('560')) {
          lat = 12.9716;
          lng = 77.5946;
        } else {
          lat = 12.754598;
          lng = 77.834477;
        }
      }

      final payload = <String, dynamic>{
        'lat': lat,
        'lng': lng,
        if (serviceSlug != null && serviceSlug.trim().isNotEmpty)
          'service_slug': _normalizeServiceSlug(serviceSlug),
      };

      final response = await api.post(
        '/settings/service-zones/check/',
        data: payload,
      );
      return ResponseNormalizer.extract(
        response,
        (data) => ServiceabilityResult.fromJson(
          data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{},
        ),
      );
    } on Exception {
      // Fail-open gracefully if service zone endpoint is temporarily unreachable
      // matching web reference implementation in LandingPage.jsx:1072-1075
      return const Success(
        ServiceabilityResult(
          isServiceable: true,
          inZone: true,
          openAccess: true,
          message: 'Service is available in your area',
          hubName: 'Hosur Hub',
        ),
      );
    }
  }

  static String _normalizeServiceSlug(String slug) {
    final s = slug.toLowerCase().trim().replaceAll('_', '-').replaceAll(' ', '-');
    if (s.contains('ac-')) return 'ac-service-cleaning';
    if (s.contains('veg') || s.contains('groc')) return 'vegetables';
    if (s.contains('clean')) return 'full-house-cleaning';
    if (s.contains('pest')) return 'cockroach-control';
    if (s.contains('electric')) return 'electrician';
    if (s.contains('plumb')) return 'plumbing';
    if (s.contains('carpenter')) return 'carpentry';
    if (s.contains('paint')) return 'interior-painting';
    if (s.contains('truck') || s.contains('transport')) return 'truck';
    if (s.contains('mason') || s.contains('construct')) return 'home-construction';
    return s;
  }

  // ── Get bookable time slots ──────────────────────────────────────────────
  // AUDIT BUG-003: GET /api/logistics/slots/ returns 404 on VPS (verified 2026-08-25).
  // The backend endpoint for time slots has not been deployed or is at a different path.
  // TODO: Confirm correct endpoint from Django urls.py and update this call.
  // Until resolved, _generateDefaultSlots() always activates as a temporary fallback.
  Future<Result<List<TimeSlot>>> getTimeSlots({required String date}) async {
    try {
      final response = await api.get(
        '/logistics/slots/',
        queryParameters: {'date': date},
      );
      return ResponseNormalizer.extract(response, (data) {
        final list = data is List
            ? data
            : (data is Map && data['results'] is List
                ? data['results'] as List
                : (data is Map && data['data'] is List
                    ? data['data'] as List
                    : (data is Map && data['slots'] is List ? data['slots'] as List : [])));

        final slots = list
            .whereType<Map>()
            .map((m) => TimeSlot.fromJson(Map<String, dynamic>.from(m)))
            .toList();

        return slots.isNotEmpty ? slots : _generateDefaultSlots(date);
      });
    } on Exception catch (_) {
      // Temporary fallback — activates while /logistics/slots/ returns 404 on VPS (BUG-003)
      return Success(_generateDefaultSlots(date));
    }
  }

  // ── Goods & Transport: vehicle tiers / lanes / areas ──────────────────────
  //
  // Added 2026-09-19, REVISED 2026-09-20 once the real `backend/logistics`
  // Django app was actually located and read (see logistics_models.dart's
  // file-level note) — these are confirmed real endpoints now, not a guess.
  static List<dynamic> _unwrapList(dynamic data, {List<String> keys = const []}) {
    if (data is List) return data;
    if (data is Map) {
      for (final key in [...keys, 'results', 'data', 'items']) {
        final v = data[key];
        if (v is List) return v;
      }
    }
    return const [];
  }

  /// GET /api/logistics/tiers/?category=truck|two_wheeler
  ///
  /// [category] should be [LogisticsVehicleCategory.tierCategoryValue]
  /// ("truck" / "two_wheeler") — confirmed against `ServiceTierListView`.
  Future<Result<List<LogisticsTier>>> getTiers({String? category}) async {
    try {
      final response = await api.get(
        '/logistics/tiers/',
        queryParameters: {
          if (category != null && category.isNotEmpty) 'category': category,
        },
      );
      return ResponseNormalizer.extract(response, (data) {
        final list = _unwrapList(data, keys: const ['tiers', 'vehicle_tiers']);
        if (kDebugMode && list.isNotEmpty && list.first is Map) {
          debugPrint(
              '[LogisticsRepository] /logistics/tiers/ raw item keys: ${(list.first as Map).keys.toList()}');
        }
        return list
            .whereType<Map>()
            .map((m) => LogisticsTier.fromJson(Map<String, dynamic>.from(m)))
            .where((t) => t.isActive)
            .toList();
      });
    } on Exception catch (e) {
      return Failure(_toError(e));
    }
  }

  /// POST /api/logistics/quote/ — the authoritative fare for a proposed
  /// Goods & Transport trip, computed server-side (`LogisticsQuoteView` /
  /// `quote_logistics_fare`). See `LogisticsQuote`'s doc comment: the
  /// frontend never computes this number, only renders it.
  ///
  /// [serviceCategory] must be [LogisticsVehicleCategory.serviceCategoryValue]
  /// ("goods_transport_truck" / "goods_transport_two_wheeler") — the
  /// backend's `LOGISTICS_CATEGORIES` / `DISTANCE_PRICED_CATEGORIES` gate on
  /// exactly these strings, never the catalog's "goods_transports" slug.
  Future<Result<LogisticsQuote>> getQuote({
    required int tierId,
    required String serviceCategory,
    required double pickupLatitude,
    required double pickupLongitude,
    required double dropLatitude,
    required double dropLongitude,
  }) async {
    try {
      final response = await api.post(
        '/logistics/quote/',
        data: {
          'tier_id': tierId,
          'service_category': serviceCategory,
          'pickup_latitude': pickupLatitude,
          'pickup_longitude': pickupLongitude,
          'drop_latitude': dropLatitude,
          'drop_longitude': dropLongitude,
          'stop_count': 2,
        },
      );
      return ResponseNormalizer.extract(
        response,
        (data) => LogisticsQuote.fromJson(
          data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{},
        ),
      );
    } on Exception catch (e) {
      // The quote endpoint returns structured 4xx error bodies
      // ({success:false, error_code, message}) for expected failures
      // (TIER_NOT_FOUND, COORDINATES_REQUIRED, VEHICLE_CAPACITY_EXCEEDED,
      // etc.) — ResponseNormalizer already surfaces `message` as the
      // Failure's error text via the existing success:false handling, so no
      // special-case parsing is needed here.
      return Failure(_toError(e));
    }
  }

  // ── Packers & Movers: inventory catalog + inventory-based quote ──────────
  //
  // Added 2026-09-20 — a genuinely separate pricing engine from the tier +
  // distance quote above (see logistics_models.dart's file-level note on
  // [PackersMoversQuote]).

  /// GET /api/logistics/packers-movers/inventory/ — the room-by-room goods
  /// catalog for the inventory builder.
  Future<Result<List<PmGoodsCategory>>> getPackersMoversInventory() async {
    try {
      final response = await api.get('/logistics/packers-movers/inventory/');
      return ResponseNormalizer.extract(response, (data) {
        final map = data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{};
        final rawCategories = map['categories'];
        if (rawCategories is! List) return const <PmGoodsCategory>[];
        return rawCategories
            .whereType<Map>()
            .map((m) => PmGoodsCategory.fromJson(Map<String, dynamic>.from(m)))
            .toList();
      });
    } on Exception catch (e) {
      return Failure(_toError(e));
    }
  }

  /// POST /api/logistics/packers-movers/quote/ — the authoritative
  /// inventory-based fare. [inventory] must be a list of
  /// `{"goods_item_id": id, "name": name, "quantity": qty}` maps — exactly
  /// what gets re-sent (unchanged) as `cart_data[0].inventory` at booking
  /// time, since the backend's `verify_packers_movers_quote` requires an
  /// exact match against what was quoted.
  Future<Result<PackersMoversQuote>> getPackersMoversQuote({
    required List<Map<String, dynamic>> inventory,
    required double pickupLatitude,
    required double pickupLongitude,
    required double dropLatitude,
    required double dropLongitude,
    required String city,
    int? selectedTierId,
    String packingTier = 'standard',
    bool dismantlingRequired = true,
    bool unpackingRequired = false,
    int pickupFloor = 0,
    bool pickupHasLift = true,
    int dropFloor = 0,
    bool dropHasLift = true,
    String relocationType = 'Within City',
  }) async {
    try {
      final response = await api.post(
        '/logistics/packers-movers/quote/',
        data: {
          'pickup_latitude': pickupLatitude,
          'pickup_longitude': pickupLongitude,
          'drop_latitude': dropLatitude,
          'drop_longitude': dropLongitude,
          'inventory': inventory,
          'city': city,
          if (selectedTierId != null) 'selected_tier_id': selectedTierId,
          'packing_tier': packingTier,
          'dismantling_required': dismantlingRequired,
          'unpacking_required': unpackingRequired,
          'pickup_floor': pickupFloor,
          'pickup_has_lift': pickupHasLift,
          'drop_floor': dropFloor,
          'drop_has_lift': dropHasLift,
          'relocation_type': relocationType,
        },
      );
      return ResponseNormalizer.extract(
        response,
        (data) => PackersMoversQuote.fromJson(
          data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{},
        ),
      );
    } on Exception catch (e) {
      return Failure(_toError(e));
    }
  }

  Future<Result<List<LogisticsLane>>> getLanes() async {
    try {
      final response = await api.get('/logistics/lanes/');
      return ResponseNormalizer.extract(response, (data) {
        final list = _unwrapList(data, keys: const ['lanes']);
        if (kDebugMode && list.isNotEmpty && list.first is Map) {
          debugPrint(
              '[LogisticsRepository] /logistics/lanes/ raw item keys: ${(list.first as Map).keys.toList()}');
        }
        return list
            .whereType<Map>()
            .map((m) => LogisticsLane.fromJson(Map<String, dynamic>.from(m)))
            .where((l) => l.isActive)
            .toList();
      });
    } on Exception catch (e) {
      return Failure(_toError(e));
    }
  }

  Future<Result<List<LogisticsArea>>> getAreas() async {
    try {
      final response = await api.get('/logistics/areas/');
      return ResponseNormalizer.extract(response, (data) {
        final list = _unwrapList(data, keys: const ['areas']);
        if (kDebugMode && list.isNotEmpty && list.first is Map) {
          debugPrint(
              '[LogisticsRepository] /logistics/areas/ raw item keys: ${(list.first as Map).keys.toList()}');
        }
        return list
            .whereType<Map>()
            .map((m) => LogisticsArea.fromJson(Map<String, dynamic>.from(m)))
            .where((a) => a.isActive)
            .toList();
      });
    } on Exception catch (e) {
      return Failure(_toError(e));
    }
  }

  ApiError _toError(Object e) {
    if (e is ApiError) return e;
    return UnknownError(e.toString());
  }

  List<TimeSlot> _generateDefaultSlots(String date) {
    return [
      TimeSlot(
        id: '${date}_09-10',
        date: date,
        startTime: '09:00',
        endTime: '10:00',
        label: '09:00 AM',
      ),
      TimeSlot(
        id: '${date}_10-11',
        date: date,
        startTime: '10:00',
        endTime: '11:00',
        label: '10:00 AM',
      ),
      TimeSlot(
        id: '${date}_11-12',
        date: date,
        startTime: '11:00',
        endTime: '12:00',
        label: '11:00 AM',
      ),
      TimeSlot(
        id: '${date}_12-13',
        date: date,
        startTime: '12:00',
        endTime: '13:00',
        label: '12:00 PM',
      ),
      TimeSlot(
        id: '${date}_14-15',
        date: date,
        startTime: '14:00',
        endTime: '15:00',
        label: '02:00 PM',
      ),
      TimeSlot(
        id: '${date}_15-16',
        date: date,
        startTime: '15:00',
        endTime: '16:00',
        label: '03:00 PM',
      ),
      TimeSlot(
        id: '${date}_16-17',
        date: date,
        startTime: '16:00',
        endTime: '17:00',
        label: '04:00 PM',
      ),
      TimeSlot(
        id: '${date}_17-18',
        date: date,
        startTime: '17:00',
        endTime: '18:00',
        label: '05:00 PM',
      ),
      TimeSlot(
        id: '${date}_18-19',
        date: date,
        startTime: '18:00',
        endTime: '19:00',
        label: '06:00 PM',
      ),
    ];
  }
}


// ── Provider ─────────────────────────────────────────────────────────────────
final logisticsRepositoryProvider = Provider<LogisticsRepository>((ref) {
  return LogisticsRepository(api: ref.watch(apiClientProvider));
});
