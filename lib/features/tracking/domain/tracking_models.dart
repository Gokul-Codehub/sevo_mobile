import 'package:equatable/equatable.dart';

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

  bool get isTerminal => kTrackingTerminalStatuses.contains(status.toLowerCase());

  /// Human-readable placeholder shown while there is no live position yet
  /// (mirrors the web app's `getFreshnessBadge()` text, simplified).
  String get statusMessage {
    final s = status.toLowerCase();
    if (isTerminal) {
      return s == 'cancelled' || s == 'rejected'
          ? 'This booking has been cancelled.'
          : 'Service completed successfully.';
    }
    if (s == 'in_progress') return 'Technician is servicing your request.';
    if (s == 'arrived') return 'Technician has arrived at your location.';
    if (!technicianAssigned) {
      return 'Finding your service professional…';
    }
    if (!isAccepted) {
      return 'Technician assigned — waiting for confirmation…';
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
      status: (json['status'] ?? '').toString(),
      freshness: (json['freshness'] ?? '').toString(),
      isAccepted: json['is_accepted'] == true || json['technician_accepted'] == true,
      technicianAssigned: json['technician_assigned'] == true || tech.isNotEmpty,
      technicianLat: techLat,
      technicianLng: techLng,
      technicianHeading: _asDouble(techLoc['heading'] ?? tech['heading']),
      technicianSpeed: _asDouble(techLoc['speed'] ?? tech['speed']),
      technicianName: _asNonEmptyString(tech['name'] ?? json['technician_name']),
      technicianPhone: _asNonEmptyString(tech['phone'] ?? json['technician_phone']),
      technicianPhoto: _asNonEmptyString(tech['photo'] ?? json['technician_photo']),
      technicianRating: _asDouble(tech['rating'] ?? json['technician_rating']),
      technicianJobsCompleted: _asInt(tech['jobs_completed']),
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
