import 'package:equatable/equatable.dart';

import '../../../core/network/response_normalizer.dart';
import 'logistics_models.dart';

// Goods & Transport models wired to the customer backend's
// `backend/logistics` public endpoints:
//   GET  /api/logistics/goods-categories/
//   GET  /api/logistics/goods-items/?category=
//   POST /api/logistics/evaluate-cargo/
//   GET  /api/logistics/slots/?date=&category=&city=
//   GET  /api/logistics/faqs/
//   GET  /api/logistics/policies/?service_category=
//   GET  /api/logistics/insurance-terms/?declared_value=
//   GET  /api/logistics/ptl/config/   POST /api/logistics/ptl/quote/

Map<String, dynamic> _asMap(dynamic v) =>
    v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};

List<Map<String, dynamic>> _asMapList(dynamic v) => v is List
    ? v.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
    : <Map<String, dynamic>>[];

// ── Goods catalogue ─────────────────────────────────────────────────────────

class GoodsCategory extends Equatable {
  const GoodsCategory({
    required this.id,
    required this.slug,
    required this.name,
    this.icon,
    this.description,
    this.infoBanner,
    this.allowsTwoWheeler = true,
    this.isProhibited = false,
  });

  final int id;
  final String slug;
  final String name;
  final String? icon;
  final String? description;
  final String? infoBanner;
  final bool allowsTwoWheeler;
  final bool isProhibited;

  factory GoodsCategory.fromJson(Map<String, dynamic> json) => GoodsCategory(
        id: parseInt(json['id']),
        slug: (json['slug'] ?? '').toString(),
        name: (json['name'] ?? '').toString(),
        icon: json['icon']?.toString(),
        description: json['description']?.toString(),
        infoBanner: json['info_banner']?.toString(),
        allowsTwoWheeler: parseBoolOrDefault(json['allows_two_wheeler'], true),
        isProhibited: parseBoolOrDefault(json['is_prohibited'], false),
      );

  @override
  List<Object?> get props =>
      [id, slug, name, icon, description, infoBanner, allowsTwoWheeler, isProhibited];
}

class GoodsItem extends Equatable {
  const GoodsItem({
    required this.id,
    required this.name,
    this.categoryId,
    this.categoryName,
    this.categorySlug,
    this.slug,
    this.subcategory,
    this.unit,
    this.defaultWeightKg,
    this.defaultCft,
    this.isFragile = false,
    this.isHeavy = false,
    this.isOversized = false,
    this.isProhibited = false,
    this.requiresSpecialHandling = false,
    this.specialHandlingCharge,
    this.isTwoWheelerCompatible = true,
  });

  final int id;
  final String name;
  final int? categoryId;
  final String? categoryName;
  final String? categorySlug;
  final String? slug;
  final String? subcategory;
  final String? unit;
  final double? defaultWeightKg;
  final double? defaultCft;
  final bool isFragile;
  final bool isHeavy;
  final bool isOversized;
  final bool isProhibited;
  final bool requiresSpecialHandling;
  final double? specialHandlingCharge;
  final bool isTwoWheelerCompatible;

  factory GoodsItem.fromJson(Map<String, dynamic> json) => GoodsItem(
        id: parseInt(json['id']),
        name: (json['name'] ?? '').toString(),
        categoryId: parseIntOrNull(json['category']),
        categoryName: json['category_name']?.toString(),
        categorySlug: json['category_slug']?.toString(),
        slug: json['slug']?.toString(),
        subcategory: json['subcategory']?.toString(),
        unit: json['unit']?.toString(),
        defaultWeightKg: parseDoubleOrNull(json['default_weight_kg']),
        defaultCft: parseDoubleOrNull(json['default_cft']),
        isFragile: parseBoolOrDefault(json['is_fragile'], false),
        isHeavy: parseBoolOrDefault(json['is_heavy'], false),
        isOversized: parseBoolOrDefault(json['is_oversized'], false),
        isProhibited: parseBoolOrDefault(json['is_prohibited'], false),
        requiresSpecialHandling:
            parseBoolOrDefault(json['requires_special_handling'], false),
        specialHandlingCharge: parseDoubleOrNull(json['special_handling_charge']),
        isTwoWheelerCompatible:
            parseBoolOrDefault(json['is_two_wheeler_compatible'], true),
      );

  @override
  List<Object?> get props => [id, name, categoryId, slug, isProhibited];
}

/// One cargo line sent to quote / evaluate-cargo / booking.
class CargoLine extends Equatable {
  const CargoLine({required this.itemId, required this.quantity});

  final int itemId;
  final int quantity;

  Map<String, dynamic> toJson() => {'item_id': itemId, 'quantity': quantity};

  @override
  List<Object?> get props => [itemId, quantity];
}

/// What the customer declared about the load. All parts are optional; the
/// backend resolves whatever is present (`resolve_cargo_payload`).
class CargoDeclaration extends Equatable {
  const CargoDeclaration({
    this.items = const [],
    this.goodsCategoryId,
    this.declaredWeightKg,
    this.declaredCft,
  });

  final List<CargoLine> items;
  final int? goodsCategoryId;
  final double? declaredWeightKg;
  final double? declaredCft;

  CargoDeclaration copyWith({
    List<CargoLine>? items,
    int? goodsCategoryId,
    double? declaredWeightKg,
    double? declaredCft,
    bool clearGoodsCategory = false,
    bool clearWeight = false,
  }) =>
      CargoDeclaration(
        items: items ?? this.items,
        goodsCategoryId:
            clearGoodsCategory ? null : (goodsCategoryId ?? this.goodsCategoryId),
        declaredWeightKg:
            clearWeight ? null : (declaredWeightKg ?? this.declaredWeightKg),
        declaredCft: declaredCft ?? this.declaredCft,
      );

  bool get isEmpty =>
      items.isEmpty &&
      goodsCategoryId == null &&
      declaredWeightKg == null &&
      declaredCft == null;

  /// Top-level fields shared by `/logistics/quote/`, `/evaluate-cargo/` and
  /// the booking-create payload (same keys on all three).
  Map<String, dynamic> toPayload() => {
        if (items.isNotEmpty) 'cargo_items': items.map((e) => e.toJson()).toList(),
        if (goodsCategoryId != null) 'goods_category_id': goodsCategoryId,
        if (declaredWeightKg != null) 'declared_weight_kg': declaredWeightKg,
        if (declaredCft != null) 'declared_cft': declaredCft,
      };

  @override
  List<Object?> get props => [items, goodsCategoryId, declaredWeightKg, declaredCft];
}

/// Result of `POST /logistics/evaluate-cargo/`.
class CargoFitment extends Equatable {
  const CargoFitment({
    required this.cargoSummary,
    required this.suitableTiers,
    required this.incompatibleTiers,
    this.recommendedTier,
    this.hasSuitableVehicle = true,
    this.requiresSurvey = false,
    this.reason,
    this.errorCode,
  });

  final Map<String, dynamic> cargoSummary;
  final Map<String, dynamic>? recommendedTier;
  final List<Map<String, dynamic>> suitableTiers;
  final List<Map<String, dynamic>> incompatibleTiers;
  final bool hasSuitableVehicle;
  final bool requiresSurvey;
  final String? reason;
  final String? errorCode;

  int? get recommendedTierId => parseIntOrNull(recommendedTier?['id']);

  Set<int> get suitableTierIds => suitableTiers
      .map((t) => parseIntOrNull(t['id']))
      .whereType<int>()
      .toSet();

  /// Fitment reason for an incompatible tier id, if the server gave one.
  String? incompatibleReason(int tierId) {
    for (final t in incompatibleTiers) {
      if (parseIntOrNull(t['id']) == tierId) {
        return (t['fitment_reason'] ?? t['reason'])?.toString();
      }
    }
    return null;
  }

  factory CargoFitment.fromJson(Map<String, dynamic> json) {
    final rec = json['recommended_tier'] ?? json['recommended_vehicle'];
    return CargoFitment(
      cargoSummary: _asMap(json['cargo_summary']),
      recommendedTier: rec is Map ? Map<String, dynamic>.from(rec) : null,
      suitableTiers: _asMapList(json['suitable_tiers'] ?? json['suitable_vehicles']),
      incompatibleTiers: _asMapList(json['incompatible_tiers']),
      hasSuitableVehicle: parseBoolOrDefault(json['has_suitable_vehicle'], true),
      requiresSurvey: parseBoolOrDefault(json['requires_survey'], false),
      reason: json['reason']?.toString(),
      errorCode: json['error_code']?.toString(),
    );
  }

  @override
  List<Object?> get props => [cargoSummary, recommendedTier, suitableTiers, incompatibleTiers];
}

// ── Slots (/logistics/slots/) ───────────────────────────────────────────────

class GtSlot extends Equatable {
  const GtSlot({
    required this.label,
    this.id,
    this.startTime,
    this.endTime,
    this.capacity,
    this.isAvailable = true,
    this.reason,
  });

  final int? id;
  final String label;
  final String? startTime;
  final String? endTime;
  final int? capacity;
  final bool isAvailable;
  final String? reason;

  factory GtSlot.fromJson(Map<String, dynamic> json) => GtSlot(
        id: parseIntOrNull(json['id']),
        label: (json['label'] ?? json['slot'] ?? '').toString(),
        startTime: json['start_time']?.toString(),
        endTime: json['end_time']?.toString(),
        capacity: parseIntOrNull(json['capacity']),
        isAvailable: parseBoolOrDefault(json['is_available'], true),
        reason: json['reason']?.toString(),
      );

  /// Adapter onto the existing booking plumbing, which carries a [TimeSlot]
  /// and sends its `.label` as `preferred_time` (the backend matches slot
  /// labels exactly, so the label must stay verbatim).
  TimeSlot toTimeSlot(String date) => TimeSlot(
        id: '${date}_${id ?? label}',
        date: date,
        startTime: startTime ?? '',
        endTime: endTime ?? '',
        label: label,
        isAvailable: isAvailable,
      );

  @override
  List<Object?> get props => [id, label, startTime, endTime, capacity, isAvailable, reason];
}

class GtSlotGroup extends Equatable {
  const GtSlotGroup({required this.name, required this.slots});

  final String name;
  final List<GtSlot> slots;

  @override
  List<Object?> get props => [name, slots];
}

class GtBookableDate extends Equatable {
  const GtBookableDate({
    required this.date,
    required this.label,
    required this.value,
    this.isToday = false,
  });

  final String date; // YYYY-MM-DD
  final String label; // Today / Tomorrow / Mon
  final String value; // 12 Oct
  final bool isToday;

  factory GtBookableDate.fromJson(Map<String, dynamic> json) => GtBookableDate(
        date: (json['date'] ?? '').toString(),
        label: (json['label'] ?? '').toString(),
        value: (json['value'] ?? '').toString(),
        isToday: parseBoolOrDefault(json['is_today'], false),
      );

  @override
  List<Object?> get props => [date, label, value, isToday];
}

class GtSlotsResult extends Equatable {
  const GtSlotsResult({
    required this.date,
    required this.groups,
    required this.upcomingDates,
    this.isSameDayClosed = false,
    this.cutoffLabel,
    this.nextBookableDate,
    this.firstAvailableSlot,
    this.availableSlotsCount = 0,
  });

  final String date;
  final List<GtSlotGroup> groups;
  final List<GtBookableDate> upcomingDates;
  final bool isSameDayClosed;
  final String? cutoffLabel;
  final String? nextBookableDate;
  final String? firstAvailableSlot;
  final int availableSlotsCount;

  List<GtSlot> get allSlots => [for (final g in groups) ...g.slots];

  factory GtSlotsResult.fromJson(Map<String, dynamic> json) => GtSlotsResult(
        date: (json['date'] ?? '').toString(),
        groups: _asMapList(json['groups'])
            .map((g) => GtSlotGroup(
                  name: (g['group'] ?? g['category'] ?? '').toString(),
                  slots: _asMapList(g['slots']).map(GtSlot.fromJson).toList(),
                ))
            .toList(),
        upcomingDates:
            _asMapList(json['upcoming_dates']).map(GtBookableDate.fromJson).toList(),
        isSameDayClosed: parseBoolOrDefault(json['is_same_day_closed'], false),
        cutoffLabel: json['cutoff_label']?.toString(),
        nextBookableDate: json['next_bookable_date']?.toString(),
        firstAvailableSlot: json['first_available_slot']?.toString(),
        availableSlotsCount: parseInt(json['available_slots_count']),
      );

  @override
  List<Object?> get props => [date, groups, upcomingDates, isSameDayClosed];
}

// ── FAQs / policies / insurance ─────────────────────────────────────────────

class GtFaq extends Equatable {
  const GtFaq({required this.id, required this.question, required this.answer});

  final int id;
  final String question;
  final String answer;

  factory GtFaq.fromJson(Map<String, dynamic> json) => GtFaq(
        id: parseInt(json['id']),
        question: (json['question'] ?? '').toString(),
        answer: (json['answer'] ?? '').toString(),
      );

  @override
  List<Object?> get props => [id, question, answer];
}

/// `GET /logistics/policies/` — customer-facing terms derived from the admin
/// policy rows (cancellation fee, waiting charge, extra charges, claims, e-way
/// bill responsibility). `terms` is ready-to-render text.
class GtPolicyTerms extends Equatable {
  const GtPolicyTerms({
    required this.serviceCategory,
    required this.terms,
    this.cancellation,
    this.waiting,
    this.extraCharges,
    this.claims,
  });

  final String serviceCategory;
  final List<String> terms;
  final Map<String, dynamic>? cancellation;
  final Map<String, dynamic>? waiting;
  final Map<String, dynamic>? extraCharges;
  final Map<String, dynamic>? claims;

  factory GtPolicyTerms.fromJson(Map<String, dynamic> json) {
    Map<String, dynamic>? opt(dynamic v) => v is Map ? Map<String, dynamic>.from(v) : null;
    final rawTerms = json['terms'];
    return GtPolicyTerms(
      serviceCategory: (json['service_category'] ?? '').toString(),
      terms: rawTerms is List ? rawTerms.map((e) => e.toString()).toList() : const [],
      cancellation: opt(json['cancellation']),
      waiting: opt(json['waiting']),
      extraCharges: opt(json['extra_charges']),
      claims: opt(json['claims']),
    );
  }

  @override
  List<Object?> get props => [serviceCategory, terms];
}

/// `GET /logistics/insurance-terms/?declared_value=` — the exact premium that
/// will be billed. Insurance needs prepaid (online/wallet) payment and is not
/// offered for instant Packers & Movers.
class InsuranceTerms extends Equatable {
  const InsuranceTerms({
    required this.offered,
    this.premium,
    this.liabilityCap,
    this.ratePercent,
    this.maxLiability,
    this.requiresPrepaid = true,
  });

  final bool offered;
  final double? premium;
  final double? liabilityCap;
  final double? ratePercent;
  final double? maxLiability;
  final bool requiresPrepaid;

  factory InsuranceTerms.fromJson(Map<String, dynamic> json) => InsuranceTerms(
        offered: parseBoolOrDefault(json['offered'], false),
        premium: parseDoubleOrNull(json['premium']),
        liabilityCap: parseDoubleOrNull(json['liability_cap']),
        ratePercent: parseDoubleOrNull(json['rate_percent']),
        maxLiability: parseDoubleOrNull(json['max_liability']),
        requiresPrepaid: parseBoolOrDefault(json['requires_prepaid'], true),
      );

  @override
  List<Object?> get props => [offered, premium, liabilityCap, ratePercent, maxLiability];
}

// ── Light PTL (Part Truck Load, priced per kg) ──────────────────────────────

class PtlLane extends Equatable {
  const PtlLane({required this.lane, required this.ratePerKg});

  final LogisticsLane lane;
  final double ratePerKg;

  @override
  List<Object?> get props => [lane, ratePerKg];
}

class PtlConfig extends Equatable {
  const PtlConfig({
    required this.enabled,
    this.ratePerKg,
    this.minimumChargeableWeightKg,
    this.minimumFare,
    this.minAdvanceDays,
    this.loadAssistOffered = false,
    this.loadAssistFee,
    this.loadingNotice,
    this.tiers = const [],
    this.lanes = const [],
  });

  final bool enabled;
  final double? ratePerKg;
  final double? minimumChargeableWeightKg;
  final double? minimumFare;
  final int? minAdvanceDays;
  final bool loadAssistOffered;
  final double? loadAssistFee;
  final String? loadingNotice;
  final List<LogisticsTier> tiers;
  final List<PtlLane> lanes;

  factory PtlConfig.fromJson(Map<String, dynamic> json) => PtlConfig(
        enabled: parseBoolOrDefault(json['enabled'], false),
        ratePerKg: parseDoubleOrNull(json['rate_per_kg']),
        minimumChargeableWeightKg:
            parseDoubleOrNull(json['minimum_chargeable_weight_kg']),
        minimumFare: parseDoubleOrNull(json['minimum_fare']),
        minAdvanceDays: parseIntOrNull(json['min_advance_days']),
        loadAssistOffered: parseBoolOrDefault(json['load_assist_offered'], false),
        loadAssistFee: parseDoubleOrNull(json['load_assist_fee']),
        loadingNotice: json['loading_notice']?.toString(),
        tiers: _asMapList(json['tiers']).map(LogisticsTier.fromJson).toList(),
        lanes: _asMapList(json['lanes'])
            .map((m) => PtlLane(
                  lane: LogisticsLane.fromJson(m),
                  ratePerKg: parseDoubleOrNull(m['ptl_rate_per_kg']) ?? 0,
                ))
            .toList(),
      );

  @override
  List<Object?> get props => [enabled, ratePerKg, minAdvanceDays, tiers, lanes];
}

/// Server-authoritative per-kg quote. The booking must echo
/// quote_id / quote_hash / expires_at in `cart_data[0]` and the same total.
class PtlQuote extends Equatable {
  const PtlQuote({
    required this.total,
    this.quoteId,
    this.quoteHash,
    this.expiresAt,
    this.declaredWeightKg,
    this.breakdown = const {},
  });

  final double total;
  final String? quoteId;
  final String? quoteHash;
  final String? expiresAt;
  final double? declaredWeightKg;
  final Map<String, dynamic> breakdown;

  bool get isExpired {
    final dt = expiresAt == null ? null : DateTime.tryParse(expiresAt!);
    return dt != null && DateTime.now().isAfter(dt);
  }

  factory PtlQuote.fromJson(Map<String, dynamic> json) => PtlQuote(
        total: parseDoubleOrNull(json['total']) ?? 0,
        quoteId: json['quote_id']?.toString(),
        quoteHash: json['quote_hash']?.toString(),
        expiresAt: json['expires_at']?.toString(),
        declaredWeightKg: parseDoubleOrNull(json['declared_weight_kg']),
        breakdown: Map<String, dynamic>.from(json),
      );

  @override
  List<Object?> get props => [total, quoteId, quoteHash, expiresAt, declaredWeightKg];
}
