import 'dart:math' as math;

import 'package:equatable/equatable.dart';

import '../../booking/domain/booking_status.dart';

/// Statuses the backend treats as final — no more position updates, OTP, or
/// cancellation will ever apply once here (mirrors
/// `_build_tracking_payload()`'s `is_terminal` set in
/// service_requests/views.py and `TERMINAL_STATUSES` in the web app's
/// useCustomerTracking.js).
const kTrackingTerminalStatuses = {
  'completed',
  'closed',
  'feedback_pending',
  'feedback_received',
  'cancelled',
  'rejected',
};

/// Arrival geofence around the customer's address, in metres — the same
/// 35 m "radar" circle the web tracker draws (CustomerTrackingMap.jsx).
const double kArrivalRadiusMeters = 35.0;

/// Statuses in which the technician/driver is travelling to the customer.
const kTrackingTransitStatuses = {
  'accepted',
  'on_the_way',
  'en_route',
  'technician_on_the_way',
};

/// Server statuses arrive in several spellings ("ON_THE_WAY", "On the way",
/// "on-the-way"). Every status comparison in the app goes through this.
String normalizeTrackingStatus(Object? raw) => normalizeBookingStatus(raw);

/// Great-circle distance in metres.
double haversineMeters(double lat1, double lng1, double lat2, double lng2) {
  const r = 6371000.0;
  double rad(double d) => d * math.pi / 180.0;
  final dLat = rad(lat2 - lat1);
  final dLng = rad(lng2 - lng1);
  final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(rad(lat1)) * math.cos(rad(lat2)) * math.sin(dLng / 2) * math.sin(dLng / 2);
  return 2 * r * math.atan2(math.sqrt(a), math.sqrt(1 - a));
}

double? _asDouble(dynamic v) {
  if (v == null) return null;
  if (v is num) return v.toDouble();
  return double.tryParse(v.toString());
}

int? _asInt(dynamic v) {
  if (v == null) return null;
  if (v is int) return v;
  if (v is num) return v.round();
  return int.tryParse(v.toString());
}

/// `_build_tracking_payload` fills an unknown technician rating with 4.9 and
/// an unknown job count with 12 (views.py: `tech_rating or 4.9`,
/// `tech_jobs or 12`). That pair is a placeholder, not a review anyone gave,
/// so it is dropped; the UI then shows no rating instead of an invented one.
bool _isPlaceholderRating(Map<String, dynamic> tech, Map<String, dynamic> json) =>
    _asDouble(tech['rating'] ?? json['technician_rating']) == 4.9 &&
    (_asInt(tech['jobs_completed']) ?? 12) == 12;

double? _realRating(Map<String, dynamic> tech, Map<String, dynamic> json) =>
    _isPlaceholderRating(tech, json) ? null : _asDouble(tech['rating'] ?? json['technician_rating']);

int? _realJobs(Map<String, dynamic> tech, Map<String, dynamic> json) =>
    _isPlaceholderRating(tech, json) ? null : _asInt(tech['jobs_completed']);

String? _asNonEmptyString(dynamic v) {
  final s = v?.toString().trim();
  return (s == null || s.isEmpty) ? null : s;
}

/// Tracking snapshot from either the WebSocket feed
/// (`/ws/tracking/<identifier>/`, see backend `TrackingConsumer`) or its REST
/// fallback (`GET /booking/<identifier>/live-location/`, backend
/// `CustomerBookingLiveLocationView` — both share the exact same payload
/// shape produced by `_build_tracking_payload()` in
/// service_requests/views.py).
///
/// Rewritten 2026-09-16: the previous version read flat top-level
/// `latitude`/`longitude`/`technician_name` keys that this backend never
/// sends — real coordinates live under nested `technician`/
/// `technician_location` objects, and the destination lives under
/// `destination`/`service_location`. That mismatch meant `hasLiveData` could
/// never legitimately become true, so the map never rendered. This also adds
/// the real `start_otp`/`payment_confirmation_otp`/`distance_km` fields the
/// web app's tracking card shows, which the mobile app never modeled at all.
class TrackingUpdate extends Equatable {
  const TrackingUpdate({
    required this.status,
    required this.freshness,
    required this.isAccepted,
    required this.technicianAssigned,
    this.technicianLat,
    this.technicianLng,
    this.technicianHeading,
    this.technicianSpeed,
    this.technicianName,
    this.technicianPhone,
    this.technicianPhoto,
    this.technicianRating,
    this.technicianJobsCompleted,
    this.destinationLat,
    this.destinationLng,
    this.destinationAddress,
    this.etaMinutes,
    this.distanceKm,
    this.startOtp,
    this.paymentConfirmationOtp,
    this.paymentStatus,
    this.balanceDue,
    this.extraCharges = const [],
    this.deliveryException,
    this.deliveryOtp,
    this.feedbackToken,
    this.feedbackSubmitted = false,
    this.feedbackRating,
    this.requestId,
    this.bookingId,
    this.serviceCategory,
    this.hasPtl = false,
    this.ptlRequoteEligible = false,
    this.ptlWeightKg,
    this.stops = const [],
    this.paymentMethod,
    this.totalAmount,
    this.logisticsLeg,
    required this.updatedAt,
    this.isLiveWs = false,
  });

  final String status;
  final String freshness;
  final bool isAccepted;
  final bool technicianAssigned;

  final double? technicianLat;
  final double? technicianLng;
  final double? technicianHeading;
  final double? technicianSpeed;
  final String? technicianName;
  final String? technicianPhone;
  final String? technicianPhoto;
  final double? technicianRating;
  final int? technicianJobsCompleted;

  final double? destinationLat;
  final double? destinationLng;
  final String? destinationAddress;

  final int? etaMinutes;
  final double? distanceKm;

  /// Only ever populated by the backend once the technician has accepted
  /// AND the booking is in an active status — never a client-side guess.
  final String? startOtp;

  /// Only present for cash-on-service bookings awaiting payment
  /// confirmation (see `payment_confirmation_otp` in
  /// `_build_tracking_payload`).
  final String? paymentConfirmationOtp;
  final String? paymentStatus;

  /// Goods-transport money items (server-computed, display only).
  final String? balanceDue;
  final List<TrackingExtraCharge> extraCharges;
  final TrackingDeliveryException? deliveryException;
  final String? deliveryOtp;

  /// Trip rating handed out by the server once a Goods & Transport trip is
  /// delivered (`feedback` block of the tracking payload). Null while the trip
  /// is not rateable.
  final String? feedbackToken;
  final bool feedbackSubmitted;
  final int? feedbackRating;

  final String? requestId;
  final int? bookingId;

  /// Server `service_category` slug (e.g. `goods_transport_truck`).
  final String? serviceCategory;

  /// Light PTL summary (`ptl` block): present for Part Truck Load trips.
  final bool hasPtl;
  final bool ptlRequoteEligible;
  final String? ptlWeightKg;

  /// Whole route as TripStops (PICKUP, each WAYPOINT, DROP).
  final List<TrackingStop> stops;

  final String? paymentMethod;
  final double? totalAmount;

  /// Current logistics leg (e.g. `DELIVERED`), from `logistics.leg`.
  final String? logisticsLeg;

  /// Goods Transport / Packers & Movers trip (driver wording).
  bool get isLogistics {
    final c = (serviceCategory ?? '').toLowerCase();
    return (logisticsLeg ?? '').isNotEmpty ||
        const ['goods', 'truck', 'two_wheeler', 'packers', 'transport'].any(c.contains);
  }

  /// A named technician / driver actually holds the job. The server's
  /// `technician_assigned` flag is also true while the job is only OFFERED to
  /// the pool (status `assigned` / a workforce job exists), so it must not be
  /// read as "a driver is assigned" — that produced "Driver assigned" on the
  /// banner next to "Driver not yet assigned" on the card.
  bool get hasDriver => isAccepted || (technicianName ?? '').trim().isNotEmpty;

  /// The driver has finished: live distance / ETA no longer apply.
  bool get isPostDelivery => const {
        'proof_submitted',
        'cash_pending',
        'waiting_for_payment',
        'payment_pending',
        'completed',
        'closed',
        'feedback_pending',
        'feedback_received',
      }.contains(status.toLowerCase());

  /// Customer-facing payment line for a goods trip (web `gtPaymentLabel`).
  String? get gtPaymentLabel {
    final method = (paymentMethod ?? '').toUpperCase();
    final pay = (paymentStatus ?? '').toLowerCase();
    if (method != 'COD' && method != 'CASH') return method.isEmpty ? null : 'Paid online';
    if (pay == 'paid' || pay == 'cash_collected') return 'Cash on delivery - paid to driver';
    if (pay == 'cash_pending') return 'Cash on delivery - awaiting your confirmation code';
    return 'Cash on delivery - pay the driver at delivery';
  }

  /// Intermediate stops only (pickup and drop have their own rows).
  List<TrackingStop> get intermediateStops => stops
      .where((s) => s.stopType != 'PICKUP' && s.stopType != 'DROP')
      .toList();

  final DateTime updatedAt;

  /// True when this snapshot arrived via the live WebSocket feed rather
  /// than the REST polling fallback.
  final bool isLiveWs;

  /// A real GPS fix has been received from the backend — never true for a
  /// synthetic/placeholder position. Gates whether the map renders a
  /// technician marker at all.
  bool get hasLiveData => technicianLat != null && technicianLng != null;

  /// The server reports the live position as lost / unavailable (it then
  /// also withholds the coordinates — backend 2026-10-27), so the map shows
  /// no moving marker instead of a stale one.
  bool get locationLost => const {'LOCATION_LOST', 'UNAVAILABLE'}
      .contains(freshness.toUpperCase());

  bool get isTerminal => kTrackingTerminalStatuses.contains(status.toLowerCase());

  /// Straight-line distance from the live technician position to the
  /// customer's address, or null while either point is unknown.
  double? get distanceToDestinationMeters {
    if (technicianLat == null || technicianLng == null) return null;
    if (destinationLat == null || destinationLng == null) return null;
    return haversineMeters(technicianLat!, technicianLng!, destinationLat!, destinationLng!);
  }

  /// The technician/driver is at the customer's address: either the server
  /// says so, or a live position is inside the 35 m arrival radius while the
  /// job is still in transit (the server status can lag a few seconds behind
  /// the GPS, and some technicians never tap "Arrived").
  bool get hasArrived {
    final s = normalizeTrackingStatus(status);
    if (s == 'arrived' || s == 'technician_arrived') return true;
    if (!kTrackingTransitStatuses.contains(s)) return false;
    if (locationLost) return false;
    final d = distanceToDestinationMeters;
    return d != null && d <= kArrivalRadiusMeters;
  }

  /// Merges an incoming snapshot onto this one.
  ///
  /// WebSocket events (technician_location_updated, employee_on_the_way, …)
  /// carry only part of the payload — no OTPs, often no is_accepted — and
  /// used to replace the whole state, so the OTP cards vanished on every WS
  /// frame and came back on the next REST poll (the "blinking" OTPs). For a
  /// [partial] frame every missing field keeps its previous value. For a
  /// full REST snapshot the server is authoritative, except that an OTP is
  /// only cleared once the job is terminal (or, for the cash OTP, paid).
  TrackingUpdate mergedWith(TrackingUpdate next, {required bool partial}) {
    final status = next.status.isNotEmpty ? next.status : this.status;
    final terminal = kTrackingTerminalStatuses.contains(status);
    final pay = (next.paymentStatus ?? paymentStatus ?? '').toLowerCase();
    final paid = pay == 'paid' || pay == 'cash_collected';
    T? keep<T>(T? n, T? p) => n ?? (terminal ? null : p);
    T? pick<T>(T? n, T? p) => partial ? (n ?? p) : n;
    return TrackingUpdate(
      status: status,
      freshness: next.freshness.isNotEmpty || !partial ? next.freshness : freshness,
      isAccepted: !terminal &&
          (next.isAccepted || ((partial || next.technicianAssigned) && isAccepted)),
      technicianAssigned: next.technicianAssigned || (partial && technicianAssigned),
      technicianLat: pick(next.technicianLat, technicianLat),
      technicianLng: pick(next.technicianLng, technicianLng),
      technicianHeading: pick(next.technicianHeading, technicianHeading),
      technicianSpeed: pick(next.technicianSpeed, technicianSpeed),
      technicianName: next.technicianName ?? technicianName,
      technicianPhone: next.technicianPhone ?? technicianPhone,
      technicianPhoto: next.technicianPhoto ?? technicianPhoto,
      technicianRating: next.technicianRating ?? technicianRating,
      technicianJobsCompleted: next.technicianJobsCompleted ?? technicianJobsCompleted,
      destinationLat: next.destinationLat ?? destinationLat,
      destinationLng: next.destinationLng ?? destinationLng,
      destinationAddress: next.destinationAddress ?? destinationAddress,
      etaMinutes: pick(next.etaMinutes, etaMinutes),
      distanceKm: pick(next.distanceKm, distanceKm),
      startOtp: keep(next.startOtp, startOtp),
      paymentConfirmationOtp:
          next.paymentConfirmationOtp ?? (terminal || paid ? null : paymentConfirmationOtp),
      paymentStatus: next.paymentStatus ?? paymentStatus,
      balanceDue: pick(next.balanceDue, balanceDue),
      extraCharges: partial && next.extraCharges.isEmpty ? extraCharges : next.extraCharges,
      deliveryException: pick(next.deliveryException, deliveryException),
      deliveryOtp: keep(next.deliveryOtp, deliveryOtp),
      feedbackToken: next.feedbackToken ?? feedbackToken,
      feedbackSubmitted: next.feedbackSubmitted || feedbackSubmitted,
      feedbackRating: next.feedbackRating ?? feedbackRating,
      requestId: next.requestId ?? requestId,
      bookingId: next.bookingId ?? bookingId,
      serviceCategory: next.serviceCategory ?? serviceCategory,
      hasPtl: next.hasPtl || (partial && hasPtl),
      ptlRequoteEligible: partial ? (next.ptlRequoteEligible || ptlRequoteEligible) : next.ptlRequoteEligible,
      ptlWeightKg: next.ptlWeightKg ?? ptlWeightKg,
      stops: partial && next.stops.isEmpty ? stops : next.stops,
      paymentMethod: next.paymentMethod ?? paymentMethod,
      totalAmount: next.totalAmount ?? totalAmount,
      logisticsLeg: next.logisticsLeg ?? logisticsLeg,
      updatedAt: next.updatedAt,
      isLiveWs: next.isLiveWs,
    );
  }

  /// Human-readable placeholder shown while there is no live position yet
  /// (mirrors the web app's `getFreshnessBadge()` text, simplified).
  String get statusMessage {
    final s = status.toLowerCase();
    if (isTerminal) {
      return s == 'cancelled' || s == 'rejected'
          ? 'This booking has been cancelled.'
          : (isLogistics ? 'Goods delivered successfully.' : 'Service completed successfully.');
    }
    if (isLogistics) {
      final leg = (logisticsLeg ?? '').toUpperCase();
      if (leg == 'DELIVERED' && s == 'in_progress') {
        return 'Goods delivered - awaiting driver proof.';
      }
      if (const {'proof_submitted', 'cash_pending', 'waiting_for_payment', 'payment_pending'}
          .contains(s)) {
        return 'Goods delivered - awaiting payment confirmation.';
      }
      if (s == 'arrived') return 'Driver has arrived at the pickup.';
      if (s == 'in_progress') return 'Your goods are on the trip.';
      if (!hasDriver) {
        return technicianAssigned
            ? 'Request sent to nearby drivers - waiting for one to accept...'
            : 'Finding a driver for your trip...';
      }
      if (!isAccepted) return 'Driver assigned - waiting for confirmation...';
      if (!hasLiveData && locationLost) {
        return "Driver's live location is temporarily unavailable - it will update when the signal returns.";
      }
      if (!hasLiveData) return 'Driver assigned - waiting for live location...';
      return 'Driver is on the way.';
    }
    if (s == 'in_progress') return 'Technician is servicing your request.';
    if (s == 'arrived') return 'Technician has arrived at your location.';
    if (!hasDriver) {
      return technicianAssigned
          ? 'Request sent to nearby professionals — waiting for one to accept…'
          : 'Finding your service professional…';
    }
    if (!isAccepted) {
      return 'Technician assigned — waiting for confirmation…';
    }
    if (!hasLiveData && locationLost) {
      return "Technician's live location is temporarily unavailable — it will update when the signal returns.";
    }
    if (!hasLiveData) {
      return 'Technician assigned — waiting for live location…';
    }
    return 'Technician is on the way.';
  }

  factory TrackingUpdate.fromJson(Map<String, dynamic> json, {bool isWs = true}) {
    final tech = json['technician'] is Map
        ? Map<String, dynamic>.from(json['technician'] as Map)
        : <String, dynamic>{};
    final techLoc = json['technician_location'] is Map
        ? Map<String, dynamic>.from(json['technician_location'] as Map)
        : <String, dynamic>{};
    final dest = json['destination'] is Map
        ? Map<String, dynamic>.from(json['destination'] as Map)
        : (json['service_location'] is Map
            ? Map<String, dynamic>.from(json['service_location'] as Map)
            : <String, dynamic>{});

    final techLat = _asDouble(techLoc['latitude'] ?? tech['latitude']);
    final techLng = _asDouble(techLoc['longitude'] ?? tech['longitude']);

    return TrackingUpdate(
      // No status in the payload => '' (the screen then falls back to the
      // booking's own status) rather than a fake 'new_request', which pushed a
      // completed booking's tracker back to the first step.
      status: normalizeTrackingStatus(json['status']),
      freshness: (json['freshness'] ?? json['freshness_state'] ?? '').toString(),
      isAccepted: json['is_accepted'] == true || json['technician_accepted'] == true,
      technicianAssigned: json['technician_assigned'] == true || tech.isNotEmpty,
      technicianLat: techLat,
      technicianLng: techLng,
      technicianHeading: _asDouble(techLoc['heading'] ?? tech['heading']),
      technicianSpeed: _asDouble(techLoc['speed'] ?? tech['speed']),
      technicianName: _asNonEmptyString(tech['name'] ?? json['technician_name']),
      technicianPhone: _asNonEmptyString(tech['phone'] ?? json['technician_phone']),
      technicianPhoto: _asNonEmptyString(tech['photo'] ?? json['technician_photo']),
      technicianRating: _realRating(tech, json),
      technicianJobsCompleted: _realJobs(tech, json),
      destinationLat: _asDouble(dest['latitude']),
      destinationLng: _asDouble(dest['longitude']),
      destinationAddress: _asNonEmptyString(dest['address']),
      etaMinutes: _asInt(json['eta_minutes'] ?? tech['eta_minutes']),
      distanceKm: _asDouble(json['distance_km'] ?? tech['distance_km']),
      startOtp: _asNonEmptyString(json['start_otp']),
      paymentConfirmationOtp: _asNonEmptyString(json['payment_confirmation_otp']),
      paymentStatus: _asNonEmptyString(json['payment_status']),
      balanceDue: _parseBalanceDue(json['balance_due']),
      extraCharges: json['extra_charges'] is List
          ? (json['extra_charges'] as List)
              .whereType<Map>()
              .map((e) => TrackingExtraCharge.fromJson(Map<String, dynamic>.from(e)))
              .toList()
          : const [],
      deliveryException: json['delivery_exception'] is Map
          ? TrackingDeliveryException.fromJson(
              Map<String, dynamic>.from(json['delivery_exception'] as Map))
          : null,
      deliveryOtp: _asNonEmptyString(json['delivery_otp']),
      feedbackToken: json['feedback'] is Map
          ? _asNonEmptyString((json['feedback'] as Map)['token'])
          : null,
      feedbackSubmitted: json['feedback'] is Map &&
          ((json['feedback'] as Map)['submitted'] == true ||
              (json['feedback'] as Map)['is_submitted'] == true),
      feedbackRating: json['feedback'] is Map
          ? _asInt((json['feedback'] as Map)['rating'])
          : null,
      requestId: _asNonEmptyString(json['request_id']),
      bookingId: _asInt(json['booking_id'] ?? json['job_id']),
      serviceCategory: _asNonEmptyString(json['service_category']),
      hasPtl: json['ptl'] is Map,
      ptlRequoteEligible:
          json['ptl'] is Map && (json['ptl'] as Map)['requote_eligible'] == true,
      ptlWeightKg: json['ptl'] is Map
          ? _asNonEmptyString((json['ptl'] as Map)['declared_weight_kg'])
          : null,
      stops: json['logistics'] is Map && (json['logistics'] as Map)['stops'] is List
          ? ((json['logistics'] as Map)['stops'] as List)
              .whereType<Map>()
              .map((e) => TrackingStop.fromJson(Map<String, dynamic>.from(e)))
              .toList()
          : const [],
      paymentMethod: _asNonEmptyString(json['payment_method']),
      totalAmount: _asDouble(json['total_amount']),
      logisticsLeg: json['logistics'] is Map
          ? _asNonEmptyString((json['logistics'] as Map)['leg'])
          : _asNonEmptyString(json['logistics_leg']),
      updatedAt: DateTime.now(),
      isLiveWs: isWs,
    );
  }

  factory TrackingUpdate.initial([String? name]) => TrackingUpdate(
        status: '',
        freshness: '',
        isAccepted: false,
        technicianAssigned: false,
        technicianName: name,
        updatedAt: DateTime.now(),
        isLiveWs: false,
      );

  TrackingUpdate copyWith({bool? isLiveWs}) => TrackingUpdate(
        status: status,
        freshness: freshness,
        isAccepted: isAccepted,
        technicianAssigned: technicianAssigned,
        technicianLat: technicianLat,
        technicianLng: technicianLng,
        technicianHeading: technicianHeading,
        technicianSpeed: technicianSpeed,
        technicianName: technicianName,
        technicianPhone: technicianPhone,
        technicianPhoto: technicianPhoto,
        technicianRating: technicianRating,
        technicianJobsCompleted: technicianJobsCompleted,
        destinationLat: destinationLat,
        destinationLng: destinationLng,
        destinationAddress: destinationAddress,
        etaMinutes: etaMinutes,
        distanceKm: distanceKm,
        startOtp: startOtp,
        paymentConfirmationOtp: paymentConfirmationOtp,
        paymentStatus: paymentStatus,
        balanceDue: balanceDue,
        extraCharges: extraCharges,
        deliveryException: deliveryException,
        deliveryOtp: deliveryOtp,
        feedbackToken: feedbackToken,
        feedbackSubmitted: feedbackSubmitted,
        feedbackRating: feedbackRating,
        requestId: requestId,
        bookingId: bookingId,
        serviceCategory: serviceCategory,
        hasPtl: hasPtl,
        ptlRequoteEligible: ptlRequoteEligible,
        ptlWeightKg: ptlWeightKg,
        stops: stops,
        paymentMethod: paymentMethod,
        totalAmount: totalAmount,
        logisticsLeg: logisticsLeg,
        updatedAt: updatedAt,
        isLiveWs: isLiveWs ?? this.isLiveWs,
      );

  @override
  List<Object?> get props => [
        status,
        freshness,
        isAccepted,
        technicianAssigned,
        technicianLat,
        technicianLng,
        technicianHeading,
        technicianSpeed,
        technicianName,
        technicianPhone,
        technicianPhoto,
        technicianRating,
        technicianJobsCompleted,
        destinationLat,
        destinationLng,
        destinationAddress,
        etaMinutes,
        distanceKm,
        startOtp,
        paymentConfirmationOtp,
        paymentStatus,
        balanceDue,
        extraCharges,
        deliveryException,
        deliveryOtp,
        feedbackToken,
        feedbackSubmitted,
        feedbackRating,
        requestId,
        bookingId,
        serviceCategory,
        hasPtl,
        ptlRequoteEligible,
        ptlWeightKg,
        stops,
        paymentMethod,
        totalAmount,
        logisticsLeg,
        updatedAt,
        isLiveWs,
      ];
}

/// Parameters identifying which booking's tracking feed to subscribe to.
/// Added 2026-09-16 alongside the WebSocket auth fix — Flutter's
/// `WebSocketChannel` cannot set an `Authorization` header (see the
/// calservices-mobile skill's guardrail #8), so the tracking token must be
/// passed as a `?token=` query parameter for `TrackingConsumer._is_authorized`
/// to accept the connection.
class TrackingArgs extends Equatable {
  const TrackingArgs({required this.identifier, this.trackingToken});

  final String identifier;
  final String? trackingToken;

  @override
  List<Object?> get props => [identifier, trackingToken];
}

/// Balance due is only meaningful when positive; the server sends a decimal
/// string (or null).
String? _parseBalanceDue(dynamic v) {
  final s = v?.toString().trim();
  if (s == null || s.isEmpty) return null;
  final n = double.tryParse(s);
  return (n != null && n > 0) ? s : null;
}

/// A toll / parking charge the driver added with a receipt (status APPLIED).
class TrackingExtraCharge extends Equatable {
  const TrackingExtraCharge({
    required this.id,
    required this.label,
    required this.amount,
    this.receiptUrl,
  });

  factory TrackingExtraCharge.fromJson(Map<String, dynamic> j) => TrackingExtraCharge(
        id: (j['charge_id'] ?? j['id'] ?? '').toString(),
        label: (j['label'] ?? 'Extra charge').toString(),
        amount: (j['amount'] ?? '0').toString(),
        receiptUrl: _asNonEmptyString(j['receipt_photo_url']),
      );

  final String id;
  final String label;
  final String amount;
  final String? receiptUrl;

  @override
  List<Object?> get props => [id, label, amount, receiptUrl];
}

/// An OPEN delivery exception reported by the driver (e.g. consignee absent).
class TrackingDeliveryException extends Equatable {
  const TrackingDeliveryException({required this.label, this.leg, this.status});

  factory TrackingDeliveryException.fromJson(Map<String, dynamic> j) =>
      TrackingDeliveryException(
        label: (j['label'] ?? 'Delivery issue reported').toString(),
        leg: _asNonEmptyString(j['leg']),
        status: _asNonEmptyString(j['status']),
      );

  final String label;
  final String? leg;
  final String? status;

  @override
  List<Object?> get props => [label, leg, status];
}

/// One stop of a logistics trip as reported by the tracking payload.
class TrackingStop extends Equatable {
  const TrackingStop({
    required this.id,
    required this.sequence,
    required this.stopType,
    required this.address,
    this.arrived = false,
    this.completed = false,
  });

  factory TrackingStop.fromJson(Map<String, dynamic> j) => TrackingStop(
        id: _asInt(j['id']) ?? 0,
        sequence: _asInt(j['sequence']) ?? 0,
        stopType: (j['stop_type'] ?? '').toString().toUpperCase(),
        address: (j['address'] ?? '').toString(),
        arrived: _asNonEmptyString(j['arrived_at']) != null,
        completed: _asNonEmptyString(j['completed_at']) != null,
      );

  final int id;
  final int sequence;
  final String stopType;
  final String address;
  final bool arrived;
  final bool completed;

  @override
  List<Object?> get props => [id, sequence, stopType, address, arrived, completed];
}
