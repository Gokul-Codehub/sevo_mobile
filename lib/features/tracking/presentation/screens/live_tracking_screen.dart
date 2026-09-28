import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../shared/theme/app_colors.dart';
import '../../../../shared/widgets/common_widgets.dart';
import '../../../booking/domain/booking_models.dart';
import '../../../booking/domain/booking_providers.dart';
import '../../data/routing_service.dart';
import '../../data/tracking_service.dart';
import '../../domain/tracking_models.dart';
import '../widgets/tracking_markers.dart';

/// Route line color — changed 2026-09-16 from AppColors.primary (the app's
/// brand green, 0xFF05A357) to a dedicated blue per explicit request, and
/// matches the technician marker's blue directional pointer.
const Color _kRouteColor = Color(0xFF2563EB);

/// Screen 18: Live Tracking Screen
/// Matches reference screen 18 with GPS route visualizer, technician profile card,
/// direct call/message buttons, real Work-Start / Cash-Payment OTP cards, a
/// server-gated cancel-booking action, and service progress timeline.
class LiveTrackingScreen extends ConsumerStatefulWidget {
  const LiveTrackingScreen({
    super.key,
    required this.identifier,
    this.booking,
  });

  final String identifier;
  // Optional — present when reached from booking detail / my bookings.
  // Supplies the real assigned technician (name/phone/rating/photo), real
  // service address, the tracking token needed to authenticate the
  // WebSocket connection, and `available_actions` for the cancel button.
  final Booking? booking;

  @override
  ConsumerState<LiveTrackingScreen> createState() => _LiveTrackingScreenState();
}

class _LiveTrackingScreenState extends ConsumerState<LiveTrackingScreen> {
  GoogleMapController? _mapController;
  bool _startOtpCopied = false;
  bool _paymentOtpCopied = false;

  // Real road-network route (see routing_service.dart) — replaces the old
  // straight line between technician and destination. Re-fetched whenever
  // the technician's position moves meaningfully, throttled the same way
  // the reference web app throttles its own OSRM calls (>=30m moved AND
  // >=10s since the last fetch) so this stays live without hammering the
  // free public OSRM mirrors into a rate-limit.
  List<LatLng> _roadRoute = const [];
  bool _hasRoadGeometry = false;
  LatLng? _lastRouteFetchPos;
  DateTime? _lastRouteFetchTime;
  bool _routeFetchInFlight = false;

  // Real road-network distance/ETA from the same OSRM route used for the
  // polyline. Fixed 2026-09-16: the backend's own distance/ETA
  // (`_build_tracking_payload` -> `get_route_eta`) silently falls back to a
  // straight-line haversine + assumed-speed estimate whenever its Google
  // Maps call fails (missing/misconfigured server-side key, network error,
  // bad status — see that function's own comment) — a straight line is
  // always shorter than the real road route, which is exactly the "shows
  // 0.8 km / 2 min instead of Google's actual 1.5 km / 4 min" gap reported.
  // OSRM computes a real routed distance/duration along actual roads, so it
  // is preferred here whenever a road route has been resolved.
  double? _roadRouteDistanceKm;
  int? _roadRouteEtaMinutes;

  // Rapido-style vehicle badge (rotates via Marker.rotation to match live
  // heading) and a "lollipop" pin for the customer's exact address —
  // rendered once and reused for every position update.
  BitmapDescriptor? _bikeIcon;
  BitmapDescriptor? _lollipopIcon;

  @override
  void initState() {
    super.initState();
    _loadMarkerIcons();
  }

  Future<void> _loadMarkerIcons() async {
    final bike = await TrackingMarkers.technicianIcon();
    final lollipop = await TrackingMarkers.destinationLollipop();
    if (!mounted) return;
    setState(() {
      _bikeIcon = bike;
      _lollipopIcon = lollipop;
    });
  }

  @override
  void dispose() {
    _mapController?.dispose();
    super.dispose();
  }

  Future<void> _maybeFetchRoute(TrackingUpdate tracking, double? destLat, double? destLng) async {
    if (!tracking.hasLiveData || destLat == null || destLng == null || tracking.isTerminal) {
      if (_hasRoadGeometry) {
        setState(() {
          _roadRoute = const [];
          _hasRoadGeometry = false;
          _roadRouteDistanceKm = null;
          _roadRouteEtaMinutes = null;
        });
      }
      return;
    }
    if (_routeFetchInFlight) return;

    final techLat = tracking.technicianLat!;
    final techLng = tracking.technicianLng!;
    final now = DateTime.now();
    final lastPos = _lastRouteFetchPos;

    var shouldFetch = lastPos == null;
    if (!shouldFetch) {
      final movedM = RoutingService.distanceMeters(lastPos.latitude, lastPos.longitude, techLat, techLng);
      final elapsedS = _lastRouteFetchTime == null
          ? 999.0
          : now.difference(_lastRouteFetchTime!).inMilliseconds / 1000.0;
      if (movedM >= 30 && elapsedS >= 10) shouldFetch = true;
    }
    if (!shouldFetch) return;

    _routeFetchInFlight = true;
    _lastRouteFetchPos = LatLng(techLat, techLng);
    _lastRouteFetchTime = now;
    try {
      final route = await RoutingService.fetchRoadRoute(
        originLat: techLat,
        originLng: techLng,
        destLat: destLat,
        destLng: destLng,
      );
      if (!mounted) return;
      if (route != null && route.points.length > 1) {
        setState(() {
          _roadRoute = route.points;
          _hasRoadGeometry = true;
          _roadRouteDistanceKm = route.distanceKm;
          _roadRouteEtaMinutes = route.etaMinutes;
        });
      } else if (_hasRoadGeometry) {
        setState(() {
          _hasRoadGeometry = false;
          _roadRouteDistanceKm = null;
          _roadRouteEtaMinutes = null;
        });
      }
    } finally {
      _routeFetchInFlight = false;
    }
  }

  TrackingArgs get _trackingArgs => TrackingArgs(
        identifier: widget.identifier,
        // Booking.trackingIdentifier reads the backend's `tracking_token`
        // (see Booking.fromJson) — TechnicianInfo has its own unrelated
        // `trackingToken` field that isn't populated from this endpoint.
        trackingToken: widget.booking?.trackingIdentifier,
      );

  @override
  Widget build(BuildContext context) {
    final tracking = ref.watch(trackingProvider(_trackingArgs));
    final hasLiveData = tracking.hasLiveData;
    final techPos = hasLiveData
        ? LatLng(tracking.technicianLat!, tracking.technicianLng!)
        : null;

    // Real service-address coordinates — prefer the live tracking payload's
    // own destination (authoritative, and correct for multi-stop logistics
    // jobs — see `_build_tracking_payload`'s TripStop handling), falling
    // back to the booking's saved address when the feed hasn't sent one yet.
    final bookingAddress = widget.booking?.address;
    final destLat = tracking.destinationLat ?? bookingAddress?.latitude;
    final destLng = tracking.destinationLng ?? bookingAddress?.longitude;
    final destPos = (destLat != null && destLng != null) ? LatLng(destLat, destLng) : null;

    // Re-fetch the real road route whenever a new tracking snapshot arrives
    // (throttled inside _maybeFetchRoute) — this is what keeps the drawn
    // route live as the technician actually moves, instead of a route
    // computed once at screen-open.
    ref.listen<TrackingUpdate>(trackingProvider(_trackingArgs), (previous, next) {
      _maybeFetchRoute(next, destLat, destLng);
    });
    // Also kick off a fetch for the very first frame using the current
    // snapshot, since ref.listen only fires on subsequent changes.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _maybeFetchRoute(tracking, destLat, destLng);
    });

    // Technician identity/contact/rating prefer the live tracking feed
    // (authoritative, current) and fall back to the Booking snapshot passed
    // in via navigation.
    final technician = widget.booking?.technician;
    final technicianName = tracking.technicianName ?? technician?.name;
    final technicianPhone = tracking.technicianPhone ?? technician?.phone;
    final technicianRating = tracking.technicianRating ?? technician?.rating;
    final technicianJobsCount = tracking.technicianJobsCompleted ?? technician?.completedJobsCount;
    final technicianPhoto = tracking.technicianPhoto ?? technician?.profilePictureUrl;

    if (hasLiveData && techPos != null) {
      _mapController?.animateCamera(CameraUpdate.newLatLng(techPos));
    }

    final effectiveStatus = tracking.status.isNotEmpty
        ? tracking.status
        : (widget.booking?.status ?? 'new_request');
    final currentStep = switch (effectiveStatus) {
      'draft' ||
      'new_request' ||
      'pending_payment' ||
      'waiting_for_payment' ||
      'unassigned' ||
      'rescheduled' =>
        0,
      'confirmed' || 'reviewed' => 1,
      'assigned' || 'received' || 'accepted' => 1,
      'on_the_way' || 'arrived' || 'en_route' => 2,
      'in_progress' ||
      'awaiting_verification' ||
      'verified' ||
      'feedback_pending' ||
      'feedback_received' ||
      'rework_requested' ||
      'follow_up_required' =>
        3,
      'completed' || 'closed' => 4,
      _ => 0,
    };

    // Cancel visibility is driven strictly by the server's `available_actions`
    // on the Booking passed into this screen (calservices-mobile skill
    // guardrail #9) — never derived from status here, and only offered when
    // a real Booking (with a real numeric id) is available.
    final canCancel = widget.booking != null && widget.booking!.canCancel;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text(
          'Live Tracking',
          style: TextStyle(
            color: AppColors.navy,
            fontWeight: FontWeight.w800,
            fontSize: 18,
          ),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: AppColors.navy),
          onPressed: () => context.pop(),
        ),
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 16),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: tracking.isLiveWs
                  ? const Color(0xFFF0FDF4)
                  : const Color(0xFFFEF3C7),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: tracking.isLiveWs
                    ? AppColors.primary
                    : const Color(0xFFF59E0B),
                width: 0.8,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: tracking.isLiveWs
                        ? AppColors.primary
                        : const Color(0xFFF59E0B),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  tracking.isLiveWs ? 'LIVE GPS' : 'SYNCING',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: tracking.isLiveWs
                        ? AppColors.primary
                        : const Color(0xFF92400E),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          // ── 1. Map Visualizer Canvas ──
          Expanded(
            flex: 4,
            child: Stack(
              children: [
                if (!hasLiveData || techPos == null)
                  // No real position has arrived yet — show an honest
                  // waiting state rather than a fake pin.
                  Container(
                    color: const Color(0xFFF1F5F9),
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const ShimmerCircle(size: 40),
                          const SizedBox(height: 16),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 32),
                            child: Text(
                              tracking.statusMessage,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                else
                  GoogleMap(
                    initialCameraPosition: CameraPosition(
                      target: techPos,
                      zoom: 15.0,
                    ),
                    onMapCreated: (controller) {
                      _mapController = controller;
                    },
                    markers: {
                      Marker(
                        markerId: const MarkerId('technician'),
                        position: techPos,
                        // Rapido-style vehicle badge that rotates to face the
                        // real live heading; `flat: true` also tilts it with
                        // the camera like a real ground-facing vehicle icon.
                        icon: _bikeIcon ??
                            BitmapDescriptor.defaultMarkerWithHue(
                              BitmapDescriptor.hueOrange,
                            ),
                        rotation: tracking.technicianHeading ?? 0,
                        anchor: const Offset(0.5, 0.5),
                        flat: true,
                        infoWindow: InfoWindow(
                          title: technicianName ?? 'Technician',
                          snippet: (_roadRouteEtaMinutes ?? tracking.etaMinutes) != null
                              ? '${_roadRouteEtaMinutes ?? tracking.etaMinutes} mins away'
                              : 'On the way',
                        ),
                      ),
                      if (destPos != null)
                        Marker(
                          markerId: const MarkerId('destination'),
                          position: destPos,
                          // "Lollipop" drop-pin for the exact service
                          // address — a circle-on-a-stem marker, not a
                          // generic teardrop pin.
                          icon: _lollipopIcon ??
                              BitmapDescriptor.defaultMarkerWithHue(
                                BitmapDescriptor.hueGreen,
                              ),
                          anchor: const Offset(0.5, 0.9),
                          infoWindow: const InfoWindow(
                            title: 'Service Address',
                            snippet: 'Your scheduled service location',
                          ),
                        ),
                    },
                    polylines: {
                      // Real road-network route, refetched live as the
                      // technician moves (see _maybeFetchRoute) — falls back
                      // to a dashed straight line only while no route has
                      // been resolved yet (first few seconds, or if every
                      // routing mirror is unreachable).
                      if (_hasRoadGeometry && _roadRoute.length > 1)
                        Polyline(
                          polylineId: const PolylineId('road-route'),
                          points: _roadRoute,
                          // Changed 2026-09-16 from AppColors.primary (green,
                          // 0xFF05A357) to a dedicated route blue per
                          // explicit request — matches the blue accent
                          // already used on the technician marker's pointer.
                          color: _kRouteColor,
                          width: 5,
                          jointType: JointType.round,
                          startCap: Cap.roundCap,
                          endCap: Cap.roundCap,
                        )
                      else if (destPos != null)
                        Polyline(
                          polylineId: const PolylineId('fallback-route'),
                          points: [techPos, destPos],
                          color: _kRouteColor,
                          width: 4,
                          patterns: [PatternItem.dash(20), PatternItem.gap(12)],
                        ),
                    },
                    myLocationButtonEnabled: false,
                    zoomControlsEnabled: false,
                  ),

                // Floating ETA / Distance Banner. Prefers the OSRM
                // road-route's own distance/ETA (real road-network figures,
                // matching what Google Maps would show) over the backend's
                // `tracking.distanceKm`/`etaMinutes` — fixed 2026-09-16: the
                // backend value silently falls back to a straight-line
                // haversine estimate whenever its own Google Maps call
                // fails, which is always shorter than the real route (e.g.
                // showing "0.8 km / 2 min" when the actual road distance is
                // "1.5 km / 4 min"). Falls back to the backend figures only
                // until a road route has been resolved.
                if (hasLiveData &&
                    ((_roadRouteDistanceKm ?? tracking.distanceKm) != null ||
                        (_roadRouteEtaMinutes ?? tracking.etaMinutes) != null))
                  Positioned(
                    top: 14,
                    left: 20,
                    right: 20,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(8),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.08),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: _kRouteColor.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Icon(
                              Icons.schedule_rounded,
                              color: _kRouteColor,
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Estimated Arrival',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: AppColors.textSecondary,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                Text(
                                  [
                                    if ((_roadRouteDistanceKm ?? tracking.distanceKm) != null)
                                      '${(_roadRouteDistanceKm ?? tracking.distanceKm)!.toStringAsFixed(1)} km',
                                    if ((_roadRouteEtaMinutes ?? tracking.etaMinutes) != null)
                                      '${_roadRouteEtaMinutes ?? tracking.etaMinutes} mins away',
                                  ].join(' · '),
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w900,
                                    color: AppColors.navy,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),

          // ── 2. Technician Card & Timeline Bottom Sheet ──
          Expanded(
            flex: 6,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius:
                    BorderRadius.vertical(top: Radius.circular(10)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black12,
                    blurRadius: 16,
                    offset: Offset(0, -6),
                  ),
                ],
              ),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Work Start OTP — the real value from the backend,
                    // only ever populated once the technician has accepted
                    // AND the booking is active (never a client-side guess;
                    // see TrackingUpdate.fromJson / _build_tracking_payload).
                    if (tracking.startOtp != null) ...[
                      _OtpCard(
                        label: 'WORK START OTP',
                        hint: 'Share this code with the technician to begin service',
                        otp: tracking.startOtp!,
                        color: const Color(0xFF92400E),
                        background: const Color(0xFFFEF3C7),
                        border: const Color(0xFFFDE68A),
                        copied: _startOtpCopied,
                        onCopy: () => _copyOtp(tracking.startOtp!, isPayment: false),
                      ),
                      const SizedBox(height: 12),
                    ],

                    // Cash Payment Confirmation OTP — only for cash-on-
                    // service bookings awaiting collection confirmation.
                    if (tracking.paymentConfirmationOtp != null) ...[
                      _OtpCard(
                        label: 'CASH PAYMENT OTP',
                        hint: 'Share with technician to confirm cash collection',
                        otp: tracking.paymentConfirmationOtp!,
                        color: const Color(0xFF065F46),
                        background: const Color(0xFFECFDF5),
                        border: const Color(0xFF10B981),
                        copied: _paymentOtpCopied,
                        onCopy: () => _copyOtp(tracking.paymentConfirmationOtp!, isPayment: true),
                      ),
                      const SizedBox(height: 12),
                    ],

                    if (tracking.startOtp == null && tracking.paymentConfirmationOtp == null)
                      const SizedBox.shrink()
                    else
                      const SizedBox(height: 4),

                    // Technician Card
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(8),
                        border:
                            Border.all(color: AppColors.border, width: 0.8),
                      ),
                      child: Row(
                        children: [
                          ClipOval(
                            child: (technicianPhoto != null && technicianPhoto.isNotEmpty)
                                ? CachedNetworkImage(
                                    imageUrl: technicianPhoto,
                                    width: 48,
                                    height: 48,
                                    fit: BoxFit.cover,
                                    placeholder: (context, url) => _TechAvatarFallback(
                                        name: technicianName),
                                    errorWidget: (context, url, error) =>
                                        _TechAvatarFallback(name: technicianName),
                                  )
                                : _TechAvatarFallback(name: technicianName),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  technicianName ?? 'Technician not yet assigned',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 14.5,
                                    color: AppColors.navy,
                                  ),
                                ),
                                // Only shown when the backend actually sent a
                                // rating — never a hardcoded placeholder.
                                if (technicianRating != null) ...[
                                  const SizedBox(height: 2),
                                  Row(
                                    children: [
                                      const Icon(Icons.star_rounded,
                                          size: 15, color: AppColors.star),
                                      const SizedBox(width: 3),
                                      Text(
                                        technicianJobsCount != null
                                            ? '${technicianRating.toStringAsFixed(1)} ($technicianJobsCount+ services)'
                                            : technicianRating.toStringAsFixed(1),
                                        style: const TextStyle(
                                          fontSize: 11.5,
                                          fontWeight: FontWeight.w600,
                                          color: AppColors.textSecondary,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ],
                            ),
                          ),
                          // Call Button — only shown with a real technician
                          // number, never a fallback support line.
                          if (technicianPhone != null && technicianPhone.isNotEmpty)
                            IconButton(
                              onPressed: () {
                                launchUrl(Uri.parse('tel:$technicianPhone'));
                              },
                              icon: Container(
                                padding: const EdgeInsets.all(8),
                                decoration: const BoxDecoration(
                                  color: AppColors.primary,
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(Icons.call_rounded,
                                    color: Colors.white, size: 18),
                              ),
                            ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 20),

                    // Progress Timeline
                    const Text(
                      'Service Status',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: AppColors.navy,
                      ),
                    ),
                    const SizedBox(height: 12),

                    _TimelineStep(
                      title: 'Booking Confirmed',
                      subtitle: 'Your request has been placed',
                      isCompleted: currentStep > 0,
                      isActive: currentStep == 0,
                    ),
                    _TimelineStep(
                      title: 'Technician Assigned',
                      subtitle: 'Expert professional allocated',
                      isCompleted: currentStep > 1,
                      isActive: currentStep == 1,
                    ),
                    _TimelineStep(
                      title: 'On the Way',
                      subtitle: 'Technician is en route to your address',
                      isCompleted: currentStep > 2,
                      isActive: currentStep == 2,
                    ),
                    _TimelineStep(
                      title: 'Service in Progress',
                      subtitle: 'OTP verification & work begins',
                      isCompleted: currentStep > 3,
                      isActive: currentStep == 3,
                    ),
                    _TimelineStep(
                      title: 'Completed',
                      subtitle: 'Service finished & final invoice',
                      isCompleted: currentStep >= 4,
                      isActive: currentStep == 4,
                      isLast: !canCancel,
                    ),

                    if (canCancel) ...[
                      const SizedBox(height: 20),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.error,
                            side: const BorderSide(color: AppColors.errorLight),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                          onPressed: () => _showCancelDialog(context, ref, widget.booking!),
                          icon: const Icon(Icons.cancel_outlined),
                          label: const Text('Cancel Booking'),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _copyOtp(String otp, {required bool isPayment}) {
    Clipboard.setData(ClipboardData(text: otp));
    setState(() {
      if (isPayment) {
        _paymentOtpCopied = true;
      } else {
        _startOtpCopied = true;
      }
    });
    Future.delayed(const Duration(seconds: 2), () {
      if (!mounted) return;
      setState(() {
        if (isPayment) {
          _paymentOtpCopied = false;
        } else {
          _startOtpCopied = false;
        }
      });
    });
  }

  // Mirrors booking_detail_screen.dart's _showCancelDialog exactly — same
  // controller, same endpoint (`POST /booking/<id>/cancel/`), same
  // confirmation copy, so cancelling from the tracking screen behaves
  // identically to cancelling from booking details.
  void _showCancelDialog(BuildContext context, WidgetRef ref, Booking booking) {
    final reasonController = TextEditingController();

    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancel Booking'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Are you sure you want to cancel this booking? If advance was paid, refund will be initiated.',
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: reasonController,
              decoration: const InputDecoration(
                labelText: 'Reason for cancellation',
                hintText: 'e.g. Plans changed / Booked by mistake',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Keep Booking'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () async {
              Navigator.pop(ctx);
              final error = await ref
                  .read(bookingActionControllerProvider.notifier)
                  .cancelBooking(
                    booking.id,
                    reasonController.text.trim().isNotEmpty
                        ? reasonController.text.trim()
                        : 'Customer requested cancellation',
                  );
              if (error != null && context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(error), backgroundColor: AppColors.error),
                );
              } else if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Booking cancelled.')),
                );
                context.pop();
              }
            },
            child: const Text('Confirm Cancel'),
          ),
        ],
      ),
    );
  }
}

class _OtpCard extends StatelessWidget {
  const _OtpCard({
    required this.label,
    required this.hint,
    required this.otp,
    required this.color,
    required this.background,
    required this.border,
    required this.copied,
    required this.onCopy,
  });

  final String label;
  final String hint;
  final String otp;
  final Color color;
  final Color background;
  final Color border;
  final bool copied;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: border, width: 0.8),
      ),
      child: Row(
        children: [
          Icon(Icons.key_rounded, size: 20, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.4,
                    color: color,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  hint,
                  style: TextStyle(fontSize: 10.5, color: color.withValues(alpha: 0.85)),
                ),
                const SizedBox(height: 2),
                Text(
                  otp,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 4,
                    fontFeatures: const [FontFeature.tabularFigures()],
                    color: color,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: onCopy,
            icon: Icon(copied ? Icons.check_rounded : Icons.copy_rounded, size: 18, color: color),
            tooltip: 'Copy',
          ),
        ],
      ),
    );
  }
}

class _TimelineStep extends StatelessWidget {
  const _TimelineStep({
    required this.title,
    required this.subtitle,
    required this.isCompleted,
    required this.isActive,
    this.isLast = false,
  });

  final String title;
  final String subtitle;
  final bool isCompleted;
  final bool isActive;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Column(
          children: [
            Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                color: isCompleted
                    ? AppColors.primary
                    : (isActive ? AppColors.navy : const Color(0xFFE2E8F0)),
                shape: BoxShape.circle,
              ),
              child: Center(
                child: isCompleted
                    ? const Icon(Icons.check_rounded,
                        size: 14, color: Colors.white)
                    : (isActive
                        ? Container(
                            width: 8,
                            height: 8,
                            decoration: const BoxDecoration(
                              color: Colors.white,
                              shape: BoxShape.circle,
                            ),
                          )
                        : null),
              ),
            ),
            if (!isLast)
              Container(
                width: 2,
                height: 32,
                color: isCompleted
                    ? AppColors.primary
                    : const Color(0xFFE2E8F0),
              ),
          ],
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                  color: isCompleted || isActive
                      ? AppColors.navy
                      : AppColors.textSecondary,
                ),
              ),
              Text(
                subtitle,
                style: const TextStyle(
                  fontSize: 11.5,
                  color: AppColors.textSecondary,
                ),
              ),
              if (!isLast) const SizedBox(height: 14),
            ],
          ),
        ),
      ],
    );
  }
}

class _TechAvatarFallback extends StatelessWidget {
  const _TechAvatarFallback({this.name});

  final String? name;

  @override
  Widget build(BuildContext context) {
    final initial = (name != null && name!.trim().isNotEmpty)
        ? name!.trim()[0].toUpperCase()
        : 'T';
    return Container(
      width: 48,
      height: 48,
      color: AppColors.navy,
      child: Center(
        child: Text(
          initial,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}
