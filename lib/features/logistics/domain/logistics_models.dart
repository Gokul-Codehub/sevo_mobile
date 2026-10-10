import 'package:equatable/equatable.dart';

import '../../../core/network/response_normalizer.dart';

/// Result of checking whether a location/pincode is serviceable.
class ServiceabilityResult extends Equatable {
  const ServiceabilityResult({
    required this.isServiceable,
    required this.message,
    this.hubName,
    this.estimatedArrivalMinutes,
    this.inZone = true,
    this.openAccess = false,
    this.availableServices = const [],
    this.serviceAllowed,
  });

  final bool isServiceable;
  final String message;
  final String? hubName;
  final int? estimatedArrivalMinutes;
  final bool inZone;
  final bool openAccess;
  final List<String> availableServices;
  final bool? serviceAllowed;

  factory ServiceabilityResult.fromJson(Map<String, dynamic> json) {
    final inZone = parseBoolOrDefault(json['in_zone'] ?? json['is_serviceable'] ?? json['serviceable'], true);
    final openAccess = parseBoolOrDefault(json['open_access'], false);
    final serviceAllowed = json['service_allowed'] is bool ? json['service_allowed'] as bool : null;

    final zone = json['zone'] is Map ? json['zone'] as Map : null;
    final hubName = zone != null ? zone['name']?.toString() : (json['hub_name']?.toString() ?? json['hub']?.toString());

    final rawServices = json['available_services'];
    final availableServices = rawServices is List
        ? rawServices.map((e) => e.toString()).toList()
        : const <String>[];

    final isServiceable = inZone && (serviceAllowed ?? true);

    return ServiceabilityResult(
      isServiceable: isServiceable,
      inZone: inZone,
      openAccess: openAccess,
      serviceAllowed: serviceAllowed,
      availableServices: availableServices,
      message: json['message']?.toString() ??
          (isServiceable
              ? 'Great! Service is available at this location.'
              : 'Sorry, this area is currently outside our service zone.'),
      hubName: hubName ?? (isServiceable ? 'Hosur Hub' : null),
      estimatedArrivalMinutes:
          parseIntOrNull(json['estimated_arrival_minutes'] ?? json['eta']),
    );
  }

  factory ServiceabilityResult.available([String? hub]) => ServiceabilityResult(
        isServiceable: true,
        inZone: true,
        message: 'Service is available at your location',
        hubName: hub ?? 'Hosur Hub',
      );

  factory ServiceabilityResult.unavailable([String? reason]) =>
      ServiceabilityResult(
        isServiceable: false,
        inZone: false,
        message: reason ?? 'Service not available in this area currently.',
      );

  @override
  List<Object?> get props => [
        isServiceable,
        message,
        hubName,
        estimatedArrivalMinutes,
        inZone,
        openAccess,
        availableServices,
        serviceAllowed,
      ];
}


// ── Goods & Transport (logistics) models ────────────────────────────────────
//
// Added 2026-09-19, REVISED 2026-09-20 once the real backend source was
// actually located and read (`backend/logistics/{models,serializers,views}.py`
// and `service_requests/services/logistics_pricing.py` on the real backend
// at `C:\Users\USER\Desktop\Cus`, cross-checked against the read-only
// `D:\sevo` mirror — both carry the same dedicated `logistics` Django app).
// The original version of this file guessed at field names because that app
// wasn't found during the first pass; it's confirmed now, so these models
// use the REAL field names directly, with only a couple of defensive
// fallbacks kept as a safety net.
//
// Two things this revision fixes, both root-caused against the real backend:
//   1. `service_category` on a booking MUST be exactly "goods_transport_truck"
//      or "goods_transport_two_wheeler" (`LOGISTICS_CATEGORIES` /
//      `DISTANCE_PRICED_CATEGORIES` in logistics_pricing.py) — never the
//      generic catalog category slug ("goods_transports"). Sending the
//      catalog slug makes the backend treat it as a non-logistics booking
//      (`service_category not in LOGISTICS_CATEGORIES` short-circuits fare
//      resolution entirely), which is not the same failure as the fare
//      error but is equally wrong.
//   2. `resolve_logistics_fare_v2` (service_requests/views.py) requires both
//      pickup (`latitude`/`longitude`) AND drop (`drop_latitude`/
//      `drop_longitude`) coordinates for any tier with `per_km_rate` set
//      (i.e. every real seeded truck/2-wheeler tier) — without a real drop
//      coordinate it raises `UnresolvedLogisticsFareError("Coordinates
//      required to calculate authoritative distance-based fare...")`, which
//      is the exact validation error blocking "Confirm Booking" today. A
//      free-text-only drop address can never satisfy this — hence the map
//      picker (`DropLocationPickerScreen`).
//
// GET /api/logistics/tiers/ is a real, documented, deployed endpoint
// (`ServiceTierListView` / `ServiceTierSerializer`) — this is no longer a
// guess.

/// The two Goods & Transport vehicle categories a customer picks between.
/// Backend: `logistics.models.LogisticsCategory` (a third value,
/// `packers_movers`, exists on the backend but has its own separate flow —
/// out of scope here per explicit product decision to only rebuild Goods
/// Transport, not Packers & Movers).
enum LogisticsVehicleCategory {
  truck('truck', 'goods_transport_truck', 'Truck'),
  twoWheeler('two_wheeler', 'goods_transport_two_wheeler', '2-Wheeler'),
  // Added 2026-09-20 per explicit request ("packers and movers is missing")
  // — this is NOT priced like the two categories above. It has its own
  // inventory/CFT-based quote flow (`PackersMoversQuoteView` /
  // `compute_packers_movers_quote` in service_requests/services/
  // packers_movers_pricing.py), confirmed against the real backend. See
  // `PmSelectedInventory`/`PackersMoversQuote` below and the booking
  // screen's Packers & Movers section for the rest of that wiring.
  // `serviceCategoryValue` is deliberately just "packers_movers" (not
  // prefixed "goods_transport_"), matching `LOGISTICS_CATEGORIES` exactly.
  packersMovers('packers_movers', 'packers_movers', 'Packers & Movers');

  const LogisticsVehicleCategory(this.tierCategoryValue, this.serviceCategoryValue, this.label);

  /// The value ServiceTier.category / GET .../tiers/?category= expects.
  final String tierCategoryValue;

  /// The value the booking-create serializer's `service_category` field
  /// expects for this vehicle category — see file-level note above.
  final String serviceCategoryValue;
  final String label;
}

/// A vehicle/capacity tier for Goods & Transport (e.g. "Mini Truck", "Tata
/// Ace", "2 Wheeler Express"). Confirmed against the real backend's
/// `ServiceTierSerializer` (customer-facing fields only — the rate-card
/// internals like `per_km_rate` are intentionally never exposed publicly).
class LogisticsTier extends Equatable {
  const LogisticsTier({
    required this.id,
    required this.category,
    required this.name,
    this.vehicleClass,
    this.city,
    this.slug,
    this.weightClass,
    this.description,
    this.capacityLabel,
    this.dimensionsLabel,
    this.iconUrl,
    this.imageUrl,
    this.startingPrice,
    this.currency = 'INR',
    this.includes = const [],
    this.maxWeightKg,
    this.maxCft,
    this.duration,
    this.isActive = true,
  });

  final int id;

  /// "truck" | "two_wheeler" | "packers_movers" — matches
  /// [LogisticsVehicleCategory.tierCategoryValue].
  final String category;
  final String name;

  /// Finer classification (two_wheeler/three_wheeler/truck/pickup/
  /// heavy_truck) — display-only here, not used for booking logic.
  final String? vehicleClass;
  final String? city;
  final String? slug;
  final String? weightClass;
  final String? description;

  /// e.g. "Up to 500 kg", "1.5 tonne" — an admin-entered label, rendered
  /// as-is, never computed from [maxWeightKg].
  final String? capacityLabel;
  final String? dimensionsLabel;
  final String? iconUrl;
  final String? imageUrl;

  /// Flat/base listed price — display context only. The real fare a
  /// customer pays comes from `POST /api/logistics/quote/`
  /// (`LogisticsRepository.getQuote`) and is re-verified server-side again
  /// at booking creation; this is never submitted as the booking total.
  final double? startingPrice;
  final String currency;
  final List<String> includes;
  final double? maxWeightKg;
  final double? maxCft;
  final String? duration;
  final bool isActive;

  factory LogisticsTier.fromJson(Map<String, dynamic> json) {
    final rawIncludes = json['includes'];
    return LogisticsTier(
      id: parseInt(json['id']),
      category: (json['category'] ?? '').toString(),
      name: (json['name'] ?? 'Vehicle').toString(),
      vehicleClass: json['vehicle_class']?.toString(),
      city: json['city']?.toString(),
      slug: json['slug']?.toString(),
      weightClass: json['weight_class']?.toString(),
      description: json['description']?.toString(),
      capacityLabel: json['capacity_label']?.toString(),
      dimensionsLabel: json['dimensions_label']?.toString(),
      iconUrl: json['icon']?.toString(),
      imageUrl: json['image']?.toString(),
      startingPrice: parseDoubleOrNull(json['starting_price']),
      currency: (json['currency'] ?? 'INR').toString(),
      includes: rawIncludes is List
          ? rawIncludes.map((e) => e.toString()).toList()
          : const [],
      maxWeightKg: parseDoubleOrNull(json['max_weight_kg']),
      maxCft: parseDoubleOrNull(json['max_cft']),
      duration: json['duration']?.toString(),
      isActive: parseBoolOrDefault(json['is_active'], true),
    );
  }

  @override
  List<Object?> get props => [
        id,
        category,
        name,
        vehicleClass,
        city,
        slug,
        weightClass,
        description,
        capacityLabel,
        dimensionsLabel,
        iconUrl,
        imageUrl,
        startingPrice,
        currency,
        includes,
        maxWeightKg,
        maxCft,
        duration,
        isActive,
      ];
}

/// The authoritative fare for a proposed Goods & Transport trip, from
/// `POST /api/logistics/quote/` (`LogisticsQuoteView` /
/// `quote_logistics_fare`). "The frontend never determines the fare. It
/// renders what this returns." — direct from the backend view's own doc
/// comment. This is display-only: the booking-create call independently
/// re-resolves the same fare server-side from the same tier + coordinates
/// (`resolve_logistics_fare_v2`), so nothing here is submitted as a locked
/// price token.
class LogisticsQuote extends Equatable {
  const LogisticsQuote({
    required this.quotable,
    required this.pricingMode,
    required this.total,
    this.currency = 'INR',
    this.tierId,
    this.tierName,
    this.isAuthoritative = false,
    this.isEstimate = false,
    this.estimateNotice,
    this.breakdown,
    this.quoteId,
    this.quoteHash,
    this.createdAt,
    this.expiresAt,
    this.laneId,
    this.supplyStatus,
    this.supplyMessage,
    this.cargoSummary,
  });

  final bool quotable;

  /// Quote lock fields. The booking must echo `quote_id` / `quote_hash` /
  /// `expires_at` in `cart_data[0]` together with this exact [total] —
  /// `resolve_logistics_fare_v2` verifies them against the cached quote.
  final String? quoteId;
  final String? quoteHash;
  final String? createdAt;
  final String? expiresAt;

  /// Lane this quote was priced for (null = plain distance fare).
  final int? laneId;

  /// Live supply hint: "AVAILABLE" | "NONE_FREE_NEARBY" | "UNKNOWN".
  /// Informational only — never blocks a booking.
  final String? supplyStatus;
  final String? supplyMessage;

  /// Server-resolved cargo summary (weight/CFT/risk) when cargo was sent.
  final Map<String, dynamic>? cargoSummary;

  bool get hasQuoteLock => (quoteId ?? '').isNotEmpty;

  bool get isExpired {
    final dt = expiresAt == null ? null : DateTime.tryParse(expiresAt!);
    return dt != null && DateTime.now().isAfter(dt);
  }

  bool get noVehicleNearby => supplyStatus == 'NONE_FREE_NEARBY';

  /// The three keys the backend reads from `cart_data[0]`.
  Map<String, dynamic> toCartEcho() => {
        if ((quoteId ?? '').isNotEmpty) 'quote_id': quoteId,
        if ((quoteHash ?? '').isNotEmpty) 'quote_hash': quoteHash,
        if ((expiresAt ?? '').isNotEmpty) 'expires_at': expiresAt,
      };

  /// "flat" | "distance"
  final String pricingMode;
  final double total;
  final String currency;
  final int? tierId;
  final String? tierName;
  final bool isAuthoritative;
  final bool isEstimate;
  final String? estimateNotice;

  /// Raw per-component breakdown (base fare, distance charge, loading
  /// charge, surge, etc.) exactly as the server sent it — rendered
  /// key-by-key rather than modeled field-by-field, since the component set
  /// varies by pricing mode and the server is the only source of truth for
  /// what a component means.
  final Map<String, dynamic>? breakdown;

  factory LogisticsQuote.fromJson(Map<String, dynamic> json) {
    final rawBreakdown = json['breakdown'];
    final rawSupply = json['supply'];
    final rawCargo = json['cargo_summary'];
    return LogisticsQuote(
      quoteId: json['quote_id']?.toString(),
      quoteHash: json['quote_hash']?.toString(),
      createdAt: json['created_at']?.toString(),
      expiresAt: json['expires_at']?.toString(),
      laneId: parseIntOrNull(json['lane_id']),
      supplyStatus: rawSupply is Map ? rawSupply['status']?.toString() : null,
      supplyMessage: rawSupply is Map ? rawSupply['message']?.toString() : null,
      cargoSummary: rawCargo is Map ? Map<String, dynamic>.from(rawCargo) : null,
      quotable: parseBoolOrDefault(json['quotable'], true),
      pricingMode: (json['pricing_mode'] ?? 'flat').toString(),
      total: parseDoubleOrNull(json['total']) ?? 0,
      currency: (json['currency'] ?? 'INR').toString(),
      tierId: parseIntOrNull(json['tier_id']),
      tierName: json['tier_name']?.toString(),
      isAuthoritative: parseBoolOrDefault(json['is_authoritative'], false),
      isEstimate: parseBoolOrDefault(json['is_estimate'], false),
      estimateNotice: json['estimate_notice']?.toString(),
      breakdown: rawBreakdown is Map ? Map<String, dynamic>.from(rawBreakdown) : null,
    );
  }

  @override
  List<Object?> get props => [
        quotable,
        pricingMode,
        total,
        currency,
        tierId,
        tierName,
        isAuthoritative,
        isEstimate,
        estimateNotice,
        breakdown,
        quoteId,
        quoteHash,
        expiresAt,
        laneId,
        supplyStatus,
      ];
}

// ── Packers & Movers (inventory-based) models ───────────────────────────────
//
// Added 2026-09-20 once the real `PackersMoversInventoryView` /
// `PackersMoversQuoteView` / `compute_packers_movers_quote` /
// `verify_packers_movers_quote` source (backend/logistics/views.py and
// service_requests/services/packers_movers_pricing.py) was read directly —
// this is a genuinely separate pricing engine from Truck/2-Wheeler's
// distance fare: it prices by moving volume (CFT) from a room-by-room
// inventory, packing tier, floor/lift access, and dismantling/unpacking
// labor, not by route distance.

/// One item inside a Packers & Movers goods category (e.g. "Sofa (3-seater)"
/// under "Living Room"). `configured` mirrors the backend's own flag: only
/// an item with real admin-entered CFT/weight can be instantly quoted —
/// selecting an unconfigured item forces the backend into
/// requires_review/requires_survey, which blocks instant booking. The
/// booking screen only lets the customer pick quantities for configured
/// items for exactly this reason.
class PmGoodsItem extends Equatable {
  const PmGoodsItem({
    required this.id,
    required this.name,
    this.slug,
    this.cft,
    this.weightKg,
    this.configured = false,
    this.isFragile = false,
    this.canDismantle = false,
    this.dismantleCharge,
  });

  final int id;
  final String name;
  final String? slug;
  final double? cft;
  final double? weightKg;
  final bool configured;
  final bool isFragile;
  final bool canDismantle;
  final double? dismantleCharge;

  factory PmGoodsItem.fromJson(Map<String, dynamic> json) {
    return PmGoodsItem(
      id: parseInt(json['id']),
      name: (json['name'] ?? 'Item').toString(),
      slug: json['slug']?.toString(),
      cft: parseDoubleOrNull(json['cft']),
      weightKg: parseDoubleOrNull(json['weight_kg']),
      configured: parseBoolOrDefault(json['configured'], false),
      isFragile: parseBoolOrDefault(json['is_fragile'], false),
      canDismantle: parseBoolOrDefault(json['can_dismantle'], false),
      dismantleCharge: parseDoubleOrNull(json['dismantle_charge']),
    );
  }

  @override
  List<Object?> get props => [id, name, slug, cft, weightKg, configured, isFragile, canDismantle, dismantleCharge];
}

/// A room/category grouping of [PmGoodsItem] (e.g. "Living Room", "Kitchen").
class PmGoodsCategory extends Equatable {
  const PmGoodsCategory({
    required this.id,
    required this.name,
    this.slug,
    this.icon,
    this.description,
    this.items = const [],
  });

  final int id;
  final String name;
  final String? slug;
  final String? icon;
  final String? description;
  final List<PmGoodsItem> items;

  factory PmGoodsCategory.fromJson(Map<String, dynamic> json) {
    final rawItems = json['items'];
    return PmGoodsCategory(
      id: parseInt(json['id']),
      name: (json['name'] ?? '').toString(),
      slug: json['slug']?.toString(),
      icon: json['icon']?.toString(),
      description: json['description']?.toString(),
      items: rawItems is List
          ? rawItems.whereType<Map>().map((m) => PmGoodsItem.fromJson(Map<String, dynamic>.from(m))).toList()
          : const [],
    );
  }

  @override
  List<Object?> get props => [id, name, slug, icon, description, items];
}

/// The authoritative Packers & Movers quote from
/// `POST /api/logistics/packers-movers/quote/`. Unlike [LogisticsQuote],
/// this can come back non-bookable (`requiresSurvey`/`requiresReview`) when
/// the inventory includes anything the server can't price with confidence —
/// the booking screen must block "Confirm Booking" in that case rather than
/// let the submit fail with a less clear error, since the backend's own
/// booking-time verification (`verify_packers_movers_quote`) rejects exactly
/// this case too.
class PackersMoversQuote extends Equatable {
  const PackersMoversQuote({
    required this.quotable,
    this.quoteId,
    this.requiresSurvey = false,
    this.requiresReview = false,
    this.surveyStatus,
    this.isAuthoritative = false,
    this.isEstimate = false,
    this.estimateNotice,
    this.unrecognizedItems = const [],
    this.reviewReason,
    this.total,
    this.subtotal,
    this.gstAmount,
    this.currency = 'INR',
    this.validUntil,
    this.vehicle,
    this.inventorySummary,
    this.route,
    this.pricing,
  });

  final bool quotable;
  final String? quoteId;
  final bool requiresSurvey;
  final bool requiresReview;
  final String? surveyStatus;
  final bool isAuthoritative;
  final bool isEstimate;
  final String? estimateNotice;
  final List<String> unrecognizedItems;
  final String? reviewReason;
  final double? total;
  final double? subtotal;
  final double? gstAmount;
  final String currency;
  final String? validUntil;
  final Map<String, dynamic>? vehicle;
  final Map<String, dynamic>? inventorySummary;
  final Map<String, dynamic>? route;
  final Map<String, dynamic>? pricing;

  factory PackersMoversQuote.fromJson(Map<String, dynamic> json) {
    final rawUnrecognized = json['unrecognized_items'];
    Map<String, dynamic>? asMap(dynamic v) => v is Map ? Map<String, dynamic>.from(v) : null;
    return PackersMoversQuote(
      quotable: parseBoolOrDefault(json['quotable'], false),
      quoteId: json['quote_id']?.toString(),
      requiresSurvey: parseBoolOrDefault(json['requires_survey'], false),
      requiresReview: parseBoolOrDefault(json['requires_review'], false),
      surveyStatus: json['survey_status']?.toString(),
      isAuthoritative: parseBoolOrDefault(json['is_authoritative'], false),
      isEstimate: parseBoolOrDefault(json['is_estimate'], false),
      estimateNotice: json['estimate_notice']?.toString(),
      unrecognizedItems: rawUnrecognized is List ? rawUnrecognized.map((e) => e.toString()).toList() : const [],
      reviewReason: json['review_reason']?.toString(),
      total: parseDoubleOrNull(json['total']),
      subtotal: parseDoubleOrNull(json['subtotal']),
      gstAmount: parseDoubleOrNull(json['gst_amount']),
      currency: (json['currency'] ?? 'INR').toString(),
      validUntil: json['valid_until']?.toString(),
      vehicle: asMap(json['vehicle']),
      inventorySummary: asMap(json['inventory_summary']),
      route: asMap(json['route']),
      pricing: asMap(json['pricing']),
    );
  }

  @override
  List<Object?> get props => [
        quotable,
        quoteId,
        requiresSurvey,
        requiresReview,
        surveyStatus,
        isAuthoritative,
        isEstimate,
        estimateNotice,
        unrecognizedItems,
        reviewReason,
        total,
        subtotal,
        gstAmount,
        currency,
        validUntil,
      ];
}

/// A serviceable pickup↔drop lane/corridor for Goods & Transport. Field
/// shape NOT confirmed against a live payload — see file-level note above.
class LogisticsLane extends Equatable {
  const LogisticsLane({
    required this.id,
    this.name,
    this.originAreaId,
    this.originAreaName,
    this.destinationAreaId,
    this.destinationAreaName,
    this.isActive = true,
  });

  final int id;
  final String? name;
  final int? originAreaId;
  final String? originAreaName;
  final int? destinationAreaId;
  final String? destinationAreaName;
  final bool isActive;

  factory LogisticsLane.fromJson(Map<String, dynamic> json) {
    final origin = json['origin'] ?? json['from_area'] ?? json['source'];
    final destination = json['destination'] ?? json['to_area'] ?? json['target'];

    return LogisticsLane(
      id: parseInt(json['id']),
      name: (json['name'] ?? json['label'] ?? json['lane_name'])?.toString(),
      originAreaId: parseIntOrNull(
        origin is Map ? origin['id'] : (json['origin_area_id'] ?? json['from_area_id']),
      ),
      originAreaName: (origin is Map ? origin['name']?.toString() : null) ??
          json['origin_area_name']?.toString() ??
          json['from_area_name']?.toString(),
      destinationAreaId: parseIntOrNull(
        destination is Map
            ? destination['id']
            : (json['destination_area_id'] ?? json['to_area_id']),
      ),
      destinationAreaName: (destination is Map ? destination['name']?.toString() : null) ??
          json['destination_area_name']?.toString() ??
          json['to_area_name']?.toString(),
      isActive: parseBoolOrDefault(
        json['is_active'] ?? json['active'] ?? json['enabled'],
        true,
      ),
    );
  }

  /// Best-effort display label when the backend doesn't send one directly.
  String get displayLabel {
    if (name != null && name!.trim().isNotEmpty) return name!.trim();
    if (originAreaName != null && destinationAreaName != null) {
      return '$originAreaName → $destinationAreaName';
    }
    return 'Lane #$id';
  }

  @override
  List<Object?> get props => [
        id,
        name,
        originAreaId,
        originAreaName,
        destinationAreaId,
        destinationAreaName,
        isActive,
      ];
}

/// A serviceable area/zone for Goods & Transport pickup or drop selection.
/// Field shape NOT confirmed against a live payload — see file-level note
/// above.
class LogisticsArea extends Equatable {
  const LogisticsArea({
    required this.id,
    required this.name,
    this.pincode,
    this.isActive = true,
  });

  final int id;
  final String name;
  final String? pincode;
  final bool isActive;

  factory LogisticsArea.fromJson(Map<String, dynamic> json) {
    return LogisticsArea(
      id: parseInt(json['id']),
      name: (json['name'] ?? json['area_name'] ?? json['label'] ?? '').toString(),
      pincode: (json['pincode'] ?? json['postal_code'] ?? json['zip_code'])?.toString(),
      isActive: parseBoolOrDefault(
        json['is_active'] ?? json['active'] ?? json['enabled'],
        true,
      ),
    );
  }

  @override
  List<Object?> get props => [id, name, pincode, isActive];
}

/// A bookable appointment time window.
class TimeSlot extends Equatable {
  const TimeSlot({
    required this.id,
    required this.date,
    required this.startTime,
    required this.endTime,
    required this.label,
    this.isAvailable = true,
  });

  final String id;
  final String date; // YYYY-MM-DD
  final String startTime; // e.g. "09:00"
  final String endTime; // e.g. "11:00"
  final String label; // e.g. "09:00 AM - 11:00 AM"
  final bool isAvailable;

  factory TimeSlot.fromJson(Map<String, dynamic> json) {
    final start = json['start_time']?.toString() ?? '09:00';
    final end = json['end_time']?.toString() ?? '11:00';
    return TimeSlot(
      id: (json['id'] ?? '$start-$end').toString(),
      date: json['date']?.toString() ?? '',
      startTime: start,
      endTime: end,
      label: json['label']?.toString() ?? '$start - $end',
      isAvailable: parseBoolOrDefault(json['is_available'] ?? json['available'], true),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'date': date,
        'start_time': startTime,
        'end_time': endTime,
        'label': label,
        'is_available': isAvailable,
      };

  @override
  List<Object?> get props => [id, date, startTime, endTime, label, isAvailable];
}
