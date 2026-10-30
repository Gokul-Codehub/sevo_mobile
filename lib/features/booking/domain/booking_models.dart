import 'dart:convert';

import 'package:decimal/decimal.dart';
import 'package:equatable/equatable.dart';

import '../../../core/network/response_normalizer.dart';
import '../../../core/utils/image_url_helper.dart';
import '../../addresses/domain/address_models.dart';
import '../../catalog/domain/catalog_models.dart';
import 'booking_status.dart';

export 'booking_status.dart';

/// Single item in the customer's cart.
class CartItem extends Equatable {
  const CartItem({
    required this.service,
    this.quantity = 1,
    this.customNotes,
    this.comboKey,
    this.comboTitle,
    this.comboUnitQty = 1,
  });

  final ServiceItem service;
  final int quantity;
  final String? customNotes;

  /// Set when this line is one of the products of a combo offer: every product
  /// of the same combo + selection shares the key, and the cart shows them
  /// together under [comboTitle]. [comboUnitQty] is how many of this product
  /// one combo contains (so the combo count is `quantity / comboUnitQty`).
  /// The order itself is still placed per product.
  final String? comboKey;
  final String? comboTitle;
  final int comboUnitQty;

  bool get isComboLine => comboKey != null;

  Decimal get unitPrice => service.effectivePrice;
  Decimal get totalPrice => unitPrice * Decimal.fromInt(quantity);

  CartItem copyWith({
    ServiceItem? service,
    int? quantity,
    String? customNotes,
  }) =>
      CartItem(
        service: service ?? this.service,
        quantity: quantity ?? this.quantity,
        customNotes: customNotes ?? this.customNotes,
        comboKey: comboKey,
        comboTitle: comboTitle,
        comboUnitQty: comboUnitQty,
      );

  Map<String, dynamic> toJson() => {
        'service_id': service.id,
        'service_slug': service.slug,
        'service_title': service.title,
        'quantity': quantity,
        'unit_price': unitPrice.toString(),
        'total_price': totalPrice.toString(),
        if (service.selectedOption != null) ...{
          'option_id': service.selectedOption!.id,
          'option_name': service.selectedOption!.name,
        },
        if (customNotes != null) 'notes': customNotes,
      };

  Map<String, dynamic> toStorageJson() => {
        'service': service.toJson(),
        'quantity': quantity,
        if (customNotes != null) 'custom_notes': customNotes,
        if (comboKey != null) 'combo_key': comboKey,
        if (comboTitle != null) 'combo_title': comboTitle,
        if (comboKey != null) 'combo_unit_qty': comboUnitQty,
      };

  factory CartItem.fromStorageJson(Map<String, dynamic> json) {
    final rawSrv = json['service'];
    final Map<String, dynamic> srvMap;
    if (rawSrv is Map) {
      srvMap = Map<String, dynamic>.from(rawSrv);
    } else {
      srvMap = {
        'id': json['service_id'] ?? json['id'] ?? 1,
        'title': json['title'] ?? json['service_title'] ?? 'Service',
        'slug': json['slug'] ?? json['service_slug'] ?? 'service',
        'price': json['price'] ?? json['unit_price'] ?? '0',
        if (json['unit'] != null) 'unit': json['unit'],
      };
    }
    return CartItem(
      service: ServiceItem.fromJson(srvMap),
      quantity: parseInt(json['quantity'], fallback: 1),
      customNotes: json['custom_notes']?.toString() ?? json['notes']?.toString(),
      comboKey: json['combo_key']?.toString(),
      comboTitle: json['combo_title']?.toString(),
      comboUnitQty: parseInt(json['combo_unit_qty'], fallback: 1),
    );
  }

  @override
  List<Object?> get props => [service, quantity, customNotes, comboKey, comboTitle, comboUnitQty];
}

/// Information about assigned service professional.
class TechnicianInfo extends Equatable {
  const TechnicianInfo({
    required this.id,
    required this.name,
    this.phone,
    this.profilePictureUrl,
    this.rating,
    this.completedJobsCount,
    this.currentLatitude,
    this.currentLongitude,
    this.trackingToken,
    this.vehicleNumber,
    this.vehicleType,
  });

  final int id;
  final String name;
  final String? phone;
  final String? profilePictureUrl;
  // Fixed 2026-08-27: rating/completedJobsCount previously defaulted to a
  // hardcoded 4.9 / 0 whenever the backend omitted them, so every
  // technician looked identically "4.9 stars" regardless of reality.
  // Nullable now — the UI shows these only when the backend actually sent
  // them, instead of inventing a rating no customer gave.
  final double? rating;
  final int? completedJobsCount;
  final double? currentLatitude;
  final double? currentLongitude;
  final String? trackingToken;
  // Goods-transport jobs: the assigned vehicle (Cus detail serializer).
  final String? vehicleNumber;
  final String? vehicleType;

  factory TechnicianInfo.fromJson(Map<String, dynamic> json) {
    return TechnicianInfo(
      id: parseInt(json['id']),
      name: (json['name'] ?? json['full_name'] ?? 'Assigned Professional').toString(),
      phone: json['phone']?.toString() ?? json['phone_number']?.toString(),
      profilePictureUrl: ImageUrlHelper.resolve(
        json['profile_picture']?.toString() ?? json['avatar']?.toString(),
      ),
      rating: parseDoubleOrNull(json['rating']),
      completedJobsCount: parseIntOrNull(json['completed_jobs_count']),
      currentLatitude: parseDoubleOrNull(json['latitude'] ?? json['current_lat']),
      currentLongitude: parseDoubleOrNull(json['longitude'] ?? json['current_lng']),
      trackingToken: json['tracking_token']?.toString() ?? json['token']?.toString(),
      vehicleNumber: _nonEmpty(json['vehicle_number']),
      vehicleType: _nonEmpty(json['vehicle_type']),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        if (phone != null) 'phone': phone,
        if (profilePictureUrl != null) 'profile_picture': profilePictureUrl,
        if (rating != null) 'rating': rating,
        if (completedJobsCount != null) 'completed_jobs_count': completedJobsCount,
        if (currentLatitude != null) 'latitude': currentLatitude,
        if (currentLongitude != null) 'longitude': currentLongitude,
        if (trackingToken != null) 'tracking_token': trackingToken,
        if (vehicleNumber != null) 'vehicle_number': vehicleNumber,
        if (vehicleType != null) 'vehicle_type': vehicleType,
      };

  @override
  List<Object?> get props => [
        id,
        name,
        phone,
        profilePictureUrl,
        rating,
        completedJobsCount,
        currentLatitude,
        currentLongitude,
        trackingToken,
        vehicleNumber,
        vehicleType,
      ];
}

String? _nonEmpty(Object? v) {
  final t = v?.toString().trim();
  return (t == null || t.isEmpty) ? null : t;
}

/// One line item on a Painting/Masonry/AC-Inspection quotation
/// (`PaintingQuoteItemSerializer` / the vendor `workforce_quote_item` shape).
/// Field names are read defensively across both sources since they don't
/// share a serializer.
class QuoteLineItem extends Equatable {
  const QuoteLineItem({
    required this.description,
    this.category,
    this.quantity = 1,
    this.rate,
    this.amount,
  });

  final String description;
  final String? category;
  final num quantity;
  final Decimal? rate;
  final Decimal? amount;

  factory QuoteLineItem.fromJson(Map<String, dynamic> json) {
    return QuoteLineItem(
      description: (json['description'] ??
              json['name'] ??
              json['title'] ??
              json['item'] ??
              'Item')
          .toString(),
      category: json['category']?.toString() ?? json['categoryName']?.toString(),
      quantity: num.tryParse(json['quantity']?.toString() ?? '') ?? 1,
      rate: parseMoneyOrNull(json['rate'] ?? json['final_rate'] ?? json['unit_price']),
      amount: parseMoneyOrNull(json['amount'] ?? json['total'] ?? json['price']),
    );
  }

  @override
  List<Object?> get props => [description, category, quantity, rate, amount];
}

/// A quotation attached to an ESTIMATION/inspection booking — Painting,
/// Masonry, and AC Inspection all funnel through this same shape on the
/// booking detail/list payload (`ServiceRequestSerializer.get_quote()` /
/// `get_quotation_history()` on the CUS backend), sourced from either the
/// backend's own `PaintingQuote` table or a cross-database read of the
/// vendor's `workforce_quote` table — this app never needs to know which.
///
/// [decisionToken] is what `QuoteRepository` uses against
/// `/api/workforce/quotes/decision/<token>/` (`WorkforceQuoteDecisionBridgeView`
/// — built explicitly for "the Customer Quotation Decision Page", the exact
/// endpoint the web app's own quote card already calls) to re-fetch the
/// latest state or record Accept/Decline/Request Changes. Per the backend
/// integration prompt this app was audited against: the socket/notification
/// is only ever a signal to refetch — this object (and a fresh GET) is the
/// only thing ever treated as authoritative.
class QuoteSummary extends Equatable {
  const QuoteSummary({
    required this.status,
    this.id,
    this.quoteNumber,
    this.quoteVersion,
    this.decisionToken,
    this.statusDisplay,
    this.canDecide = false,
    this.validUntil,
    this.subtotal,
    this.discountAmount,
    this.taxAmount,
    this.totalAmount,
    this.netPayable,
    this.advanceAmount,
    this.balanceAmount,
    this.inspectionFee,
    this.declineReason,
    this.customerNotes,
    this.items = const [],
  });

  final String status; // upper-cased: SENT_TO_CUSTOMER, CUSTOMER_ACCEPTED, DECLINED, CHANGE_REQUESTED, EXPIRED, SUPERSEDED, CONVERTED, DRAFT...
  final int? id;
  final String? quoteNumber;
  final int? quoteVersion;
  final String? decisionToken;
  final String? statusDisplay;
  final bool canDecide;
  final DateTime? validUntil;
  final Decimal? subtotal;
  final Decimal? discountAmount;
  final Decimal? taxAmount;
  final Decimal? totalAmount;
  final Decimal? netPayable;
  final Decimal? advanceAmount;
  final Decimal? balanceAmount;
  final Decimal? inspectionFee;
  final String? declineReason;
  final String? customerNotes;
  final List<QuoteLineItem> items;

  /// Never trust a client-computed total — this only exists as a fallback
  /// display when the backend genuinely omitted every total field.
  Decimal get displayTotal => netPayable ?? totalAmount ?? subtotal ?? Decimal.zero;

  bool get isSentToCustomer =>
      canDecide ||
      const {'SENT_TO_CUSTOMER', 'SENT', 'PENDING', 'PENDING_APPROVAL', 'PENDING_REVIEW', 'NEW'}
          .contains(status);
  bool get isAccepted =>
      const {'CUSTOMER_ACCEPTED', 'APPROVED', 'ADMIN_APPROVED', 'CONVERTED'}.contains(status);
  bool get isDeclined => status.contains('DECLIN');
  bool get isChangesRequested => status.contains('CHANGE');
  bool get isExpired => status == 'EXPIRED';
  bool get isSuperseded => status == 'SUPERSEDED';
  bool get isConversionPending => status == 'CONVERSION_PENDING';

  factory QuoteSummary.fromJson(Map<String, dynamic> json) {
    final rawItems = json['items'];
    final items = rawItems is List
        ? rawItems
            .whereType<Map>()
            .map((m) => QuoteLineItem.fromJson(Map<String, dynamic>.from(m)))
            .toList()
        : <QuoteLineItem>[];
    return QuoteSummary(
      id: parseIntOrNull(json['id'] ?? json['quote_id']),
      quoteNumber: json['quote_number']?.toString(),
      quoteVersion: parseIntOrNull(json['quote_version']),
      decisionToken: json['decision_token']?.toString() ?? json['customer_decision_token']?.toString(),
      status: (json['status'] ?? 'DRAFT').toString().trim().toUpperCase(),
      statusDisplay: json['status_display']?.toString(),
      canDecide: json['can_decide'] == true,
      validUntil: json['valid_until'] != null ? DateTime.tryParse(json['valid_until'].toString()) : null,
      subtotal: parseMoneyOrNull(json['subtotal'] ?? json['subtotal_amount']),
      discountAmount: parseMoneyOrNull(json['discount_amount'] ?? json['discount']),
      taxAmount: parseMoneyOrNull(json['tax_amount'] ?? json['tax']),
      totalAmount: parseMoneyOrNull(json['total_amount'] ?? json['grand_total']),
      netPayable: parseMoneyOrNull(json['net_payable']),
      advanceAmount: parseMoneyOrNull(json['advance_amount']),
      balanceAmount: parseMoneyOrNull(json['balance_amount']),
      inspectionFee: parseMoneyOrNull(json['inspection_fee']),
      declineReason: json['decline_reason']?.toString(),
      customerNotes: json['customer_notes']?.toString(),
      items: items,
    );
  }

  @override
  List<Object?> get props => [
        status,
        id,
        quoteNumber,
        quoteVersion,
        decisionToken,
        canDecide,
        validUntil,
        subtotal,
        discountAmount,
        taxAmount,
        totalAmount,
        netPayable,
        items,
      ];
}

/// Full Booking / Service Request model driven by `available_actions`.
class Booking extends Equatable {
  const Booking({
    required this.id,
    required this.requestId,
    required this.status,
    required this.totalAmount,
    required this.advanceAmount,
    required this.balanceAmount,
    this.paymentStatus = 'pending',
    this.paymentOrderId,
    this.availableActions = const [],
    this.hasServerActions = false,
    this.items = const [],
    this.address,
    required this.scheduledDate,
    required this.scheduledTimeSlot,
    this.specialInstructions,
    this.technician,
    this.cancellationReason,
    this.createdAt,
    this.trackingIdentifier,
    this.requestKind,
    this.parentRequestId,
    this.quoteNumber,
    this.quote,
    this.quotationHistory = const [],
    this.serviceCategory,
    this.paymentMethod,
    this.startOtp,
    this.deliveryOtp,
    this.paymentConfirmationOtp,
    this.dropAddress,
    this.fareBreakdown,
    this.logisticsTierName,
    this.logisticsLaneName,
  });

  /// Server `service_category` slug (e.g. `goods_transport_truck`, `plumbing`).
  final String? serviceCategory;
  final String? paymentMethod; // 'COD' | 'ONLINE'

  /// Owner-only codes from the booking detail endpoint: the job/pickup start
  /// OTP, the goods Delivery OTP (only while a trip is at the drop) and the
  /// cash-collection confirmation code. Null whenever the server omits them.
  final String? startOtp;
  final String? deliveryOtp;
  final String? paymentConfirmationOtp;

  /// Goods Transport / Packers & Movers: where the goods go (`drop_address`).
  final String? dropAddress;

  /// Server fare breakdown of a logistics booking (`fare_breakdown`, a JSON
  /// object — sometimes sent as a JSON string). Null for other bookings.
  final Map<String, dynamic>? fareBreakdown;

  /// Goods Transport: the vehicle tier and lane the server priced
  /// (`logistics_tier_name` / `logistics_lane_name`, Cus 2026-10-28).
  final String? logisticsTierName;
  final String? logisticsLaneName;

  /// Truck / two-wheeler fares are quoted GST-inclusive with no platform
  /// fee (web 2026-10-27): GST is shown as "included", never added on top.
  bool get isGtFareInclusive => const {
        'goods_transport_truck',
        'goods_transport_two_wheeler',
      }.contains((serviceCategory ?? '').toLowerCase());

  static double _fbNum(dynamic v) =>
      v is num ? v.toDouble() : (double.tryParse(v?.toString() ?? '') ?? 0);

  /// Nested Packers & Movers / PTL quote pricing (`fare_breakdown.pricing`).
  Map<String, dynamic>? get _fbPricing {
    final p = fareBreakdown?['pricing'];
    return p is Map ? Map<String, dynamic>.from(p) : null;
  }

  /// Route length of the trip in km (0 when unknown). Web gtTripSummary
  /// (Cus 2026-10-28): falls back to `route.distance_km`, then the
  /// chargeable km.
  double get tripDistanceKm {
    final f = fareBreakdown;
    if (f == null) return 0;
    final route = f['route'] is Map ? f['route'] as Map : const {};
    for (final v in [f['distance_km'], route['distance_km'], f['chargeable_km']]) {
      final n = _fbNum(v);
      if (n > 0) return n;
    }
    return 0;
  }

  /// Stops on the way. A vehicle fare's `stops` counts pickup + drop too; a
  /// P&M / PTL quote's `pricing.additional_stops` is already the extra ones.
  int get tripExtraStops {
    final p = _fbPricing;
    if (p != null) {
      return _fbNum(fareBreakdown?['stops'] ?? p['additional_stops']).round();
    }
    final n = _fbNum(fareBreakdown?['stops']).round();
    return n > 2 ? n - 2 : 0;
  }

  /// GST already included in a GST-inclusive goods fare (0 when none).
  double get gstIncluded => _fbNum(fareBreakdown?['gst_included']);

  /// Vehicle tier / lane the server priced (Cus 2026-10-28 serializers).
  String? get vehicleLabel => logisticsTierName ?? technician?.vehicleType;

  /// "How this fare was calculated" lines (label, rupees), only the
  /// non-zero ones — same rows and order as the web booking card.
  // Updated 2026-10-28 to the web's new gtFareLineRows: the distance label
  // copes with a missing km/rate, and Packers & Movers / PTL quotes (nested
  // `pricing`) are itemised too (packing, labour, dismantling, surcharges).
  List<(String, double)> get gtFareLines {
    final f = fareBreakdown;
    if (f == null) return const [];
    final rows = <(String, double)>[];
    void add(String label, dynamic v) {
      final n = _fbNum(v);
      if (n > 0) rows.add((label, n));
    }

    // Fixed lane fare (Cus 2026-10-29) comes first when the route has one.
    if (_fbNum(f['lane_fixed_fare']) > 0) {
      final lane = _bkText(f['lane_label']) ?? '';
      add(lane.isEmpty ? 'Route fixed fare' : 'Lane fixed fare ($lane)', f['lane_fixed_fare']);
    }
    add('Base fare', f['base_fare']);
    if (_fbNum(f['distance_charge']) > 0) {
      final km = _fbNum(f['chargeable_km'] ?? f['distance_km']);
      final rate = _fbNum(f['rate_per_km']);
      add(
        km > 0 && rate > 0
            ? 'Distance (${km.toStringAsFixed(1)} km chargeable × ₹${rate.toStringAsFixed(rate % 1 == 0 ? 0 : 2)}/km)'
            : 'Distance charge',
        f['distance_charge'],
      );
    }
    add('Additional stops (${_fbNum(f['additional_stops']).round()})', f['additional_stop_charge']);
    add('Loading / unloading', f['loading_unloading']);
    add('Special handling', f['special_handling_charge'] ?? f['special_handling']);

    final p = _fbPricing;
    if (p != null) {
      final hasBase = _fbNum(f['base_fare']) > 0;
      final hasDistance = _fbNum(f['distance_charge']) > 0;
      if (!hasBase) add('Transport base fare', p['transport_base_fare']);
      if (!hasDistance) add('Transport distance charge', p['transport_distance_charge']);
      if (!hasBase && !hasDistance && _fbNum(p['transport_base_fare']) <= 0) {
        add('Transport charge', p['transport_total']);
      }
      add('Packing (${p['packing_label'] ?? p['packing_tier'] ?? 'Standard'})', p['packing_charge']);
      add('Base labor charge', p['base_labor_charge']);
      add('Floor / stairs labor charge', p['floor_labor_charge']);
      if (_fbNum(p['base_labor_charge']) <= 0 && _fbNum(p['floor_labor_charge']) <= 0) {
        add('Labor & handling', p['labor_total']);
      }
      add('Furniture dismantling & reassembly', p['dismantling_charge']);
      add('Unpacking charge', p['unpacking_charge']);
      if (_fbNum(f['additional_stop_charge']) <= 0) {
        add('Additional stops (${_fbNum(p['additional_stops']).round()})', p['additional_stops_charge']);
      }
      add('Date / weekend surcharge', p['date_surcharge']);
      add('Intercity permit / fee', p['intercity_fee']);
      add('Toll allowance', p['toll_allowance']);
    }
    if (rows.isEmpty) {
      final total = _fbNum(f['total'] ?? f['subtotal']);
      if (total > 0) rows.add(('Standard transport fare', total));
    }
    return rows;
  }

  bool get minimumFareApplied => fareBreakdown?['minimum_fare_applied'] == true;

  /// Goods Transport / Packers & Movers booking (driver wording, trip OTPs).
  /// Same broad match as the web's isGtVehicleCategory (Cus 2026-10-28):
  /// any goods / truck / two-wheeler / packers / movers / PTL category.
  bool get isLogistics {
    final c = (serviceCategory ?? '').trim().toLowerCase();
    return c.startsWith('goods') ||
        c.startsWith('gt') ||
        c == 'ptl' ||
        c == 'logistics' ||
        c.contains('truck') ||
        c.contains('wheeler') ||
        c.contains('packer') ||
        c.contains('mover') ||
        c.contains('relocation');
  }

  final int id;
  final String requestId; // e.g. "CAL-20260822-104"
  final String status; // 'new_request' | 'confirmed' | 'assigned' | 'in_progress' | 'completed' | 'cancelled' | 'refund_requested'
  final Decimal totalAmount;
  final Decimal advanceAmount;
  final Decimal balanceAmount;
  final String paymentStatus; // 'pending' | 'partially_paid' | 'paid' | 'refunded'
  final String? paymentOrderId; // Razorpay order ID
  final List<String> availableActions; // 'cancel', 'reschedule', 'pay', 'track', 'give_feedback', 'request_refund'

  /// The server sent an `available_actions` block (even if every flag was
  /// false). When it did, it is the only authority for action buttons.
  final bool hasServerActions;
  final List<CartItem> items;
  final Address? address;
  final String scheduledDate;
  final String scheduledTimeSlot;
  final String? specialInstructions;
  final TechnicianInfo? technician;
  final String? cancellationReason;
  final DateTime? createdAt;
  final String? trackingIdentifier;

  // ── Quotation / multi-stage booking fields ──────────────────────────────
  // Added 2026-09-26 to consume `ServiceRequestSerializer`'s `request_kind`,
  // `parent_request`, `quote_number`, `quote` and `quotation_history` fields
  // — already returned by the existing booking detail/list endpoints and,
  // until now, completely unread by this app. See QuoteSummary's doc
  // comment for the full backend contract this was audited against
  // (Painting/Masonry/AC-Inspection quotation flow).
  final String? requestKind; // 'standard' | 'inspection' | 'estimation' | 'quoted_work'
  final int? parentRequestId; // set on a Stage-2 "quoted_work" booking, points back to its Stage-1 inspection booking
  final String? quoteNumber;
  final QuoteSummary? quote; // the currently-active quote for this booking, if any
  final List<QuoteSummary> quotationHistory; // superseded/older versions, newest first

  bool get isEstimationBooking {
    final k = (requestKind ?? '').toLowerCase();
    return k == 'estimation' || k == 'inspection';
  }

  bool get isQuotedWorkBooking => (requestKind ?? '').toLowerCase() == 'quoted_work';
  bool get hasActiveQuote => quote != null;

  // Action helpers driven strictly by available_actions
  bool get canCancel => availableActions.contains('cancel');
  bool get canReschedule => availableActions.contains('reschedule');
  bool get canPayAdvance => availableActions.contains('pay_advance');
  bool get canPayBalance => availableActions.contains('pay_balance');
  // Fixed 2026-10-28 (status audit): `canTrack` was `... || technician !=
  // null`, so every completed and cancelled booking that still carried its
  // technician snapshot showed a Track button. `canRate` checked for a
  // 'rate' action the server never sends (it sends `can_give_feedback`) and
  // fell back to `status == 'completed'`, so a booking already rated still
  // offered "Rate". The server flags win whenever they were sent; the status
  // fallbacks only cover payloads without an actions block.
  bool get canTrack {
    if (isBookingFinished(status)) return false;
    if (availableActions.contains('track')) return true;
    if (hasServerActions) return technician != null && isBookingTrackable(status);
    return isBookingTrackable(status);
  }

  bool get canRate {
    if (availableActions.contains('give_feedback') || availableActions.contains('rate')) {
      return true;
    }
    return !hasServerActions && bookingStageOf(status) == BookingStage.completed;
  }

  BookingStage get stage => bookingStageOf(status);
  String get statusLabel => bookingStatusLabel(status);

  bool get isUpcoming => !isBookingFinished(status);
  bool get isCompleted => stage == BookingStage.completed;

  /// Whether this booking is a grocery-supply order rather than a scheduled
  /// service (AC, electrician, plumbing, cleaning, etc). Derived from the
  /// items actually on the booking — never hardcoded per booking, so it
  /// stays correct however many item types a booking has. A booking with no
  /// items resolves to "service" (the more common case for a single
  /// scheduled visit that may not echo back cart items).
  ///
  /// Fixed 2026-10-07 ("Grocery delivery is showing as service"): this used
  /// to check `item.service.flowType == CatalogFlowType.grocery` directly.
  /// [ServiceItem.flowType] is a pure category-slug/name keyword match, and
  /// a booking's own echoed `cart_data` (the schemaless JSONField this
  /// screen's items are actually parsed from — see [Booking.fromJson]
  /// above) frequently omits `category_slug`/`category_name` entirely, so a
  /// genuine grocery item (e.g. "Green Chilli (Hari Mirch)") rebuilt from it
  /// silently resolved to [CatalogFlowType.serviceBooking] and the My
  /// Bookings list tagged it "SERVICE" instead of "GROCERY". This is the
  /// exact same class of bug already fixed for the Home screen's "Book
  /// Again" tiles and for `cartSummaryProvider`'s fee calculation
  /// (2026-10-06/07) by switching to [ServiceItem.isGroceryFlow], which
  /// falls back to the vegetable-category fields and the grocery cart-id
  /// offset when the keyword match alone is inconclusive. Using that same
  /// getter here fixes this screen too, from the one place the signal is
  /// actually derived.
  bool get isGroceryBooking =>
      items.isNotEmpty && items.every((i) => i.service.isGroceryFlow);
  bool get isCancelled => isBookingCancelled(status);

  factory Booking.fromJson(Map<String, dynamic> json) {
    // 1. Extract available_actions strictly according to Django DRF & Web reference
    final List<dynamic> rawActions;
    final actionsObj = json['available_actions'] ?? json['actions'];
    if (actionsObj is List) {
      rawActions = actionsObj;
    } else if (actionsObj is Map) {
      // Map format from get_customer_available_actions(): {"can_cancel": true, "can_reschedule": false}
      rawActions = actionsObj.entries
          .where((e) => e.value == true || e.value == 'true' || e.value == 1)
          .map((e) => e.key.replaceFirst(RegExp(r'^can_'), ''))
          .toList();
    } else if (actionsObj is String) {
      rawActions = actionsObj.split(',').map((s) => s.trim()).toList();
    } else {
      rawActions = const [];
    }

    // 2. Extract items / services / cart_items / cart_data safely
    final List<dynamic> rawItems = [];
    final itemsObj = json['items'];
    final servicesObj = json['services'] ?? json['service'];
    final cartItemsObj = json['cart_items'] ?? json['cart_data'];

    if (itemsObj is List) {
      rawItems.addAll(itemsObj);
    } else if (itemsObj is Map) {
      if (itemsObj['results'] is List) {
        rawItems.addAll(itemsObj['results'] as List);
      } else if (itemsObj['items'] is List) {
        rawItems.addAll(itemsObj['items'] as List);
      } else {
        rawItems.add(itemsObj);
      }
    }

    if (cartItemsObj is List) {
      rawItems.addAll(cartItemsObj);
    } else if (cartItemsObj is String && cartItemsObj.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(cartItemsObj);
        if (decoded is List) {
          rawItems.addAll(decoded);
        } else if (decoded is Map) {
          rawItems.add(decoded);
        }
      } catch (_) {}
    }

    if (servicesObj is List) {
      rawItems.addAll(servicesObj);
    } else if (servicesObj is Map && rawItems.isEmpty) {
      if (servicesObj['results'] is List) {
        rawItems.addAll(servicesObj['results'] as List);
      } else {
        rawItems.add(servicesObj);
      }
    }

    // Fixed 2026-08-27: this previously fell back to a hardcoded ₹599 when
    // none of total_amount/total/price were present — silently showing a
    // fake bill amount instead of reflecting what was actually charged.
    // Falls back to 0 now, which reads honestly as "amount unavailable"
    // rather than a plausible-looking wrong number.
    final total = parseMoney(
      json['total_amount'] ?? json['total'] ?? json['price'] ?? 0,
    );
    final paymentStatusValue =
        (json['payment_status'] ?? 'pending').toString().toLowerCase();
    // Fixed 2026-09-17 — this booking's real complaint: the detail screen
    // showed "Advance Paid: ₹X" for every single booking, X being a
    // fabricated 20% of the total, EVEN WHEN `payment_status` was
    // 'pending' and the customer had made no payment at all. The backend
    // has no advance/deposit concept anywhere in its API (confirmed: no
    // such field exists in the booking payload) — `advance_amount`/
    // `balance_amount` were never real fields, just this 20%-of-total
    // guess presented as if it were a real charged amount. Now this only
    // ever claims the full amount was paid when `payment_status` itself
    // says 'paid' — every other status (pending, partially_paid without an
    // explicit real figure, refunded, failed) gets an honest ₹0 advance
    // rather than an invented number, so the UI (booking_detail_screen.dart)
    // shows "Payment Pending" instead of a fake receipt. `payment_status`
    // itself (not this derived split) is still the source of truth for
    // whether a payment is partial.
    final advance = parseMoneyOrNull(json['advance_amount'] ?? json['advance']) ??
        (paymentStatusValue == 'paid' ? total : Decimal.zero);
    final balance = parseMoneyOrNull(json['balance_amount'] ?? json['balance']) ??
        (total - advance);

    var parsedItems = rawItems.whereType<Map>().map((itemJson) {
      final itemMap = Map<String, dynamic>.from(itemJson);
      final serviceJson = itemMap['service'] is Map
          ? Map<String, dynamic>.from(itemMap['service'] as Map)
          : itemMap;
      return CartItem(
        service: ServiceItem.fromJson(serviceJson),
        quantity: parseInt(itemMap['quantity'] ?? itemMap['qty'], fallback: 1),
        customNotes: itemMap['notes']?.toString() ?? itemMap['custom_notes']?.toString(),
      );
    }).toList();

    // If items list is empty, but booking has top-level service metadata (DRF single-service booking shape)
    if (parsedItems.isEmpty && (json['service_id'] != null || json['issue_title'] != null || json['service_name'] != null)) {
      parsedItems = [
        CartItem(
          service: ServiceItem(
            id: parseInt(json['service_id'] ?? json['id']),
            categoryId: parseIntOrNull(json['service_category'] ?? json['category_id']),
            title: (json['issue_title'] ?? json['service_name'] ?? json['title'] ?? 'Service').toString(),
            slug: (json['service_slug'] ?? json['slug'] ?? 'service').toString(),
            price: total,
            durationMinutes: parseInt(json['duration_minutes'] ?? json['duration'], fallback: 60),
          ),
          quantity: 1,
          customNotes: json['special_instructions']?.toString(),
        ),
      ];
    }

    return Booking(
      id: parseInt(json['id']),
      requestId: (json['request_id'] ?? json['booking_id'] ?? json['code'] ?? 'CAL-${json['id']}').toString(),
      // Normalised once here so every screen compares the same spelling.
      status: normalizeBookingStatus(json['status'] ?? 'new_request'),
      totalAmount: total,
      advanceAmount: advance,
      balanceAmount: balance,
      paymentStatus: paymentStatusValue,
      paymentOrderId: json['payment_order_id']?.toString() ?? json['razorpay_order_id']?.toString(),
      availableActions: rawActions.map((a) => a.toString().toLowerCase()).toList(),
      hasServerActions: actionsObj != null,
      items: parsedItems,
      address: json['address'] is Map
          ? Address.fromJson(Map<String, dynamic>.from(json['address'] as Map))
          : (json['address'] != null && json['address'].toString().trim().isNotEmpty
              ? Address(
                  id: 0,
                  addressType: 'delivery',
                  addressLine1: json['address'].toString(),
                  city: 'Hosur',
                  state: 'Tamil Nadu',
                  postalCode: '635109',
                )
              : null),
      scheduledDate: (json['scheduled_date'] ?? json['date'] ?? json['preferred_date'] ?? '').toString(),
      scheduledTimeSlot: (json['scheduled_time_slot'] ?? json['time_slot'] ?? json['preferred_time_slot'] ?? json['preferred_time'] ?? json['slot'] ?? '').toString(),
      specialInstructions: json['special_instructions']?.toString() ?? json['notes']?.toString() ?? json['description']?.toString(),
      technician: json['technician'] is Map
          ? TechnicianInfo.fromJson(Map<String, dynamic>.from(json['technician'] as Map))
          : null,
      cancellationReason: json['cancellation_reason']?.toString(),
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'].toString())
          : null,
      trackingIdentifier: json['tracking_identifier']?.toString() ??
          json['tracking_token']?.toString() ??
          json['identifier']?.toString(),
      requestKind: json['request_kind']?.toString(),
      parentRequestId: parseIntOrNull(json['parent_request']),
      quoteNumber: json['quote_number']?.toString(),
      quote: json['quote'] is Map
          ? QuoteSummary.fromJson(Map<String, dynamic>.from(json['quote'] as Map))
          : null,
      quotationHistory: json['quotation_history'] is List
          ? (json['quotation_history'] as List)
              .whereType<Map>()
              .map((m) => QuoteSummary.fromJson(Map<String, dynamic>.from(m)))
              .toList()
          : const [],
      serviceCategory: _bkStr(json['service_category']),
      paymentMethod: _bkStr(json['payment_method']),
      startOtp: _bkStr(json['start_otp']),
      deliveryOtp: _bkStr(json['delivery_otp']),
      paymentConfirmationOtp: _bkStr(json['payment_confirmation_otp']),
      dropAddress: _bkStr(json['drop_address']),
      fareBreakdown: _bkMap(json['fare_breakdown']),
      logisticsTierName: _bkText(json['logistics_tier_name']),
      logisticsLaneName: _bkText(json['logistics_lane_name']),
    );
  }

  static Map<String, dynamic>? _bkMap(dynamic v) {
    if (v is Map) return Map<String, dynamic>.from(v);
    if (v is String && v.trim().startsWith('{')) {
      try {
        final d = jsonDecode(v);
        if (d is Map) return Map<String, dynamic>.from(d);
      } catch (_) {}
    }
    return null;
  }

  static String? _bkStr(dynamic v) {
    final s = v?.toString().trim();
    return (s == null || s.isEmpty || s == 'null') ? null : s;
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'request_id': requestId,
        'status': status,
        'total_amount': totalAmount.toString(),
        'advance_amount': advanceAmount.toString(),
        'balance_amount': balanceAmount.toString(),
        'payment_status': paymentStatus,
        if (paymentOrderId != null) 'payment_order_id': paymentOrderId,
        'available_actions': availableActions,
        'items': items.map((i) => i.toJson()).toList(),
        if (address != null) 'address': address!.toJson(),
        'scheduled_date': scheduledDate,
        'scheduled_time_slot': scheduledTimeSlot,
        if (specialInstructions != null) 'special_instructions': specialInstructions,
        if (technician != null) 'technician': technician!.toJson(),
        if (cancellationReason != null) 'cancellation_reason': cancellationReason,
        if (createdAt != null) 'created_at': createdAt!.toIso8601String(),
        if (trackingIdentifier != null) 'tracking_identifier': trackingIdentifier,
        if (requestKind != null) 'request_kind': requestKind,
        if (parentRequestId != null) 'parent_request': parentRequestId,
        if (quoteNumber != null) 'quote_number': quoteNumber,
        if (serviceCategory != null) 'service_category': serviceCategory,
        if (paymentMethod != null) 'payment_method': paymentMethod,
        if (dropAddress != null) 'drop_address': dropAddress,
        if (fareBreakdown != null) 'fare_breakdown': fareBreakdown,
        if (logisticsTierName != null) 'logistics_tier_name': logisticsTierName,
        if (logisticsLaneName != null) 'logistics_lane_name': logisticsLaneName,
        // OTPs are deliberately not cached.
      };

  @override
  List<Object?> get props => [
        id,
        requestId,
        status,
        totalAmount,
        advanceAmount,
        balanceAmount,
        paymentStatus,
        paymentOrderId,
        availableActions,
        hasServerActions,
        items,
        address,
        scheduledDate,
        scheduledTimeSlot,
        specialInstructions,
        technician,
        cancellationReason,
        createdAt,
        trackingIdentifier,
        requestKind,
        parentRequestId,
        quoteNumber,
        quote,
        quotationHistory,
        serviceCategory,
        paymentMethod,
        startOtp,
        deliveryOtp,
        paymentConfirmationOtp,
        dropAddress,
        fareBreakdown,
        logisticsTierName,
        logisticsLaneName,
      ];
}

String? _bkText(Object? v) {
  final t = v?.toString().trim();
  return (t == null || t.isEmpty || t == 'null') ? null : t;
}
