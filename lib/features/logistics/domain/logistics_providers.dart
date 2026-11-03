import 'dart:convert';

import 'gt_assist.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';
import 'package:location/location.dart' as loc;

import '../../../core/errors/api_error.dart';
import '../../../core/storage/secure_storage.dart';
import '../data/logistics_repository.dart';
import '../../addresses/domain/address_notifier.dart' show selectedAddressProvider;
import '../../notifications/domain/capacity_claim.dart';
import '../../payment/data/payment_repository.dart';
import 'gt_models.dart';
import 'logistics_models.dart';
import 'package:flutter/foundation.dart' show TargetPlatform, defaultTargetPlatform;

/// Currently selected booking appointment date.
final selectedBookingDateProvider = StateProvider<DateTime>((ref) {
  // Start on today. Whether today is still bookable (cut-off, notice, closed
  // day) is decided by the server's slot engine, exactly like the web; the
  // slot picker offers "next available day" when today has nothing left.
  return DateTime.now();
});

/// Currently selected booking time slot.
final selectedTimeSlotProvider = StateProvider<TimeSlot?>((ref) => null);

/// Fixed 2026-10-06: slots must be fetched per the specific service being
/// booked (admin's Time Slot Management is configured per service — hours,
/// duration, capacity all differ), not just per date. `CheckoutScreen` sets
/// this (to the service's slug) as soon as it knows which service is being
/// booked, and clears it on dispose. Left `null` for flows with no single
/// service in scope — [LogisticsRepository.getTimeSlots] then calls the
/// `resolve` endpoint, which falls back to a sane default service rather
/// than failing.
final selectedBookingServiceIdProvider = StateProvider<String?>((ref) => null);

/// One day's slots + day-level facts for a date (YYYY-MM-DD), service id/slug
/// and (optionally) a held availability claim token.
final timeSlotDayProvider = FutureProvider.autoDispose.family<TimeSlotDay,
    ({String date, String? serviceId, String? claimToken, double? latitude, double? longitude})>((ref, params) async {
  final repo = ref.watch(logisticsRepositoryProvider);
  final result = await repo.getTimeSlotDay(
    date: params.date,
    serviceId: params.serviceId,
    claimToken: params.claimToken,
    latitude: params.latitude,
    longitude: params.longitude,
  );

  return switch (result) {
    Success(:final data) => data,
    Failure(:final error) => throw error,
  };
});

/// Provider fetching time slots for a given date (YYYY-MM-DD) + service id/slug.
final timeSlotsProvider = FutureProvider.autoDispose.family<List<TimeSlot>,
    ({String date, String? serviceId})>((ref, params) async {
  final day = await ref.watch(timeSlotDayProvider(
          (date: params.date, serviceId: params.serviceId, claimToken: null, latitude: null, longitude: null))
      .future);
  return day.slots;
});

/// The held availability claim for the service being booked, if it is still
/// valid ("a slot opened up" — see CapacityClaim).
final activeCapacityClaimProvider = Provider<CapacityClaim?>((ref) {
  final claim = ref.watch(capacityClaimProvider);
  if (claim == null || claim.isExpired) return null;
  final serviceId = ref.watch(selectedBookingServiceIdProvider);
  if (claim.serviceSlug != null &&
      serviceId != null &&
      claim.serviceSlug!.toLowerCase() != serviceId.toLowerCase()) {
    // Same booking flow but a different service: the claim isn't for this one.
    // (Slugs can differ between the sub-service and the package, so only
    // reject when both are known AND clearly unrelated.)
    return null;
  }
  return claim;
});

/// The selected date's day (slots + day-level facts) for the service being booked.
final currentSelectedDayProvider = FutureProvider.autoDispose<TimeSlotDay>((ref) {
  final selectedDate = ref.watch(selectedBookingDateProvider);
  final serviceId = ref.watch(selectedBookingServiceIdProvider);
  final claim = ref.watch(activeCapacityClaimProvider);
  final address = ref.watch(selectedAddressProvider);
  final dateString = DateFormat('yyyy-MM-dd').format(selectedDate);
  return ref.watch(timeSlotDayProvider((
    date: dateString,
    serviceId: serviceId,
    claimToken: claim?.token,
    latitude: address?.latitude,
    longitude: address?.longitude,
  )).future).then((day) {
    // Remember the booking window (closed weekdays, how far ahead, same-day)
    // so the calendar can grey out days the server will refuse.
    Future.microtask(() {
      try {
        ref.read(slotWindowProvider.notifier).state = day;
      } catch (_) {}
    });
    return day;
  });
});

/// Last booking-window facts the server sent (see [TimeSlotDay]); used by the
/// calendar. Null until the first slot response arrives.
final slotWindowProvider = StateProvider<TimeSlotDay?>((ref) => null);

/// Convenience provider for slots of the currently selected date + service.
final currentSelectedDateSlotsProvider = FutureProvider.autoDispose<List<TimeSlot>>((ref) async {
  final day = await ref.watch(currentSelectedDayProvider.future);
  return day.slots;
});

/// Provider checking serviceability for a pincode, optionally refined with
/// the exact pinned map coordinates. Fixed 2026-10-06: previously keyed by
/// pincode text alone, so the "Add New Address" screen's serviceability
/// banner never reflected where the customer actually dropped the map pin
/// — only whatever was last typed/reverse-geocoded into the PIN Code field.
/// [AddEditAddressScreen] now passes the live pin's lat/lng here too, and
/// `LogisticsRepository.checkServiceability` already accepts them (it just
/// wasn't being given any).
final serviceabilityProvider = FutureProvider.family<ServiceabilityResult,
    ({String pincode, double? lat, double? lng})>((ref, params) async {
  final pincode = params.pincode;
  if (pincode.trim().length != 6 && params.lat == null) {
    return const ServiceabilityResult(
      isServiceable: false,
      message: 'Please enter a valid 6-digit postal code',
    );
  }

  final repo = ref.watch(logisticsRepositoryProvider);
  final result = await repo.checkServiceability(
    postalCode: pincode,
    latitude: params.lat,
    longitude: params.lng,
  );

  return switch (result) {
    Success(:final data) => data,
    Failure(:final error) => throw error,
  };
});

// ── Goods & Transport: vehicle category / tiers / drop location / fare ─────
//
// Added 2026-09-19, REVISED 2026-09-20: "Select Routes" (Lane) selection was
// removed per explicit product decision — the real fare comes from
// POST /api/logistics/quote/ using pickup/drop coordinates, not a fixed
// route/lane lookup, so lane selection was both unwanted UI and unnecessary
// (logistics_lane is an optional field on the booking payload). The tiers
// provider is now keyed by vehicle category (truck/two_wheeler), matching
// the redesigned booking screen's "pick a vehicle category, then a tier
// under it" flow instead of one flat list.

/// Which top-level Goods & Transport vehicle category the customer is
/// currently browsing/booking under.
final selectedVehicleCategoryProvider =
    StateProvider<LogisticsVehicleCategory>((ref) => LogisticsVehicleCategory.truck);

/// Available vehicle/capacity tiers for one vehicle category.
/// `ref.keepAlive()` matches the convention already used by
/// `categoriesProvider` (catalog_providers.dart) — this is reference data the
/// admin rarely changes, not per-booking state.
final logisticsTiersProvider =
    FutureProvider.family<List<LogisticsTier>, LogisticsVehicleCategory>((ref, vehicleCategory) async {
  ref.keepAlive();
  final repo = ref.watch(logisticsRepositoryProvider);
  final result = await repo.getTiers(category: vehicleCategory.tierCategoryValue);

  return switch (result) {
    Success(:final data) => data,
    Failure(:final error) => throw error,
  };
});

/// Currently selected vehicle tier for the in-progress Goods & Transport
/// booking flow. Reset by the booking screen on dispose/submit, and
/// whenever [selectedVehicleCategoryProvider] changes (a tier from the other
/// category is never valid once the category tab switches).
final selectedLogisticsTierProvider = StateProvider<LogisticsTier?>((ref) => null);

/// A drop-off location picked on the map (`DropLocationPickerScreen`) for the
/// in-progress Goods & Transport booking. Free-text-only addresses cannot
/// satisfy the backend's authoritative distance-fare resolution (it requires
/// real `drop_latitude`/`drop_longitude`), so this is a required capture,
/// not an optional convenience.
class PickedDropLocation {
  const PickedDropLocation({
    required this.latitude,
    required this.longitude,
    required this.address,
  });

  final double latitude;
  final double longitude;
  final String address;
}

final dropLocationProvider = StateProvider<PickedDropLocation?>((ref) => null);

/// Optional intermediate stops between pickup and drop-off, in order.
/// Server cap is the tier's `max_additional_stops` (web default 3).
const int kMaxGtAdditionalStops = 3;
final gtStopsProvider =
    StateProvider<List<PickedDropLocation>>((ref) => const []);

/// Parameters that determine whether a live fare quote can be fetched, and
/// what it should be for.
class LogisticsQuoteParam {
  const LogisticsQuoteParam({
    required this.tierId,
    required this.serviceCategory,
    required this.pickupLatitude,
    required this.pickupLongitude,
    required this.dropLatitude,
    required this.dropLongitude,
    this.laneId,
    this.loadingHelp,
    this.cargo,
    this.customerGstin,
    this.waypoints,
    this.assist,
  });

  final int tierId;
  final String serviceCategory;
  final double pickupLatitude;
  final double pickupLongitude;
  final double dropLatitude;
  final double dropLongitude;

  /// Optional inputs the updated backend quote honours. All part of the
  /// provider key so a change re-quotes (and re-locks) the fare.
  final int? laneId;
  final bool? loadingHelp;
  final CargoDeclaration? cargo;
  final String? customerGstin;

  /// Intermediate stops as {lat, lng}, in order. Part of the key.
  final List<Map<String, double>>? waypoints;

  /// Extra helpers / stairs carrying (Mini Truck). Part of the key, so changing it re-quotes the fare.
  final GtAssist? assist;

  String get _waypointsKey =>
      (waypoints ?? const []).map((w) => '${w['lat']},${w['lng']}').join('|');

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LogisticsQuoteParam &&
          runtimeType == other.runtimeType &&
          tierId == other.tierId &&
          serviceCategory == other.serviceCategory &&
          pickupLatitude == other.pickupLatitude &&
          pickupLongitude == other.pickupLongitude &&
          dropLatitude == other.dropLatitude &&
          dropLongitude == other.dropLongitude &&
          laneId == other.laneId &&
          loadingHelp == other.loadingHelp &&
          cargo == other.cargo &&
          customerGstin == other.customerGstin &&
          assist == other.assist &&
          _waypointsKey == other._waypointsKey;

  @override
  int get hashCode => Object.hash(tierId, serviceCategory, pickupLatitude,
      pickupLongitude, dropLatitude, dropLongitude, laneId, loadingHelp, cargo,
      customerGstin, _waypointsKey, assist);
}

/// The live, authoritative fare for the currently selected tier + pickup +
/// drop — "the fare engine ... calculated and shown to the customer" per
/// the real customer web app's own booking pages. `.autoDispose` because
/// this is transient, per-attempt state, unlike the tiers list above.
final logisticsQuoteProvider = FutureProvider.autoDispose
    .family<LogisticsQuote, LogisticsQuoteParam>((ref, param) async {
  final repo = ref.watch(logisticsRepositoryProvider);
  final result = await repo.getQuote(
    tierId: param.tierId,
    serviceCategory: param.serviceCategory,
    pickupLatitude: param.pickupLatitude,
    pickupLongitude: param.pickupLongitude,
    dropLatitude: param.dropLatitude,
    dropLongitude: param.dropLongitude,
    laneId: param.laneId,
    loadingHelp: param.loadingHelp,
    cargo: param.cargo,
    customerGstin: param.customerGstin,
    waypoints: param.waypoints,
    assist: param.assist,
  );

  return switch (result) {
    Success(:final data) => data,
    Failure(:final error) => throw error,
  };
});

// ── Packers & Movers (inventory-based) state ───────────────────────────────
//
// Added 2026-09-20 — see [PackersMoversQuote]'s file-level note in
// logistics_models.dart for why this is a separate flow from the tier +
// distance quote above.

/// The room-by-room goods catalog, fetched once and kept alive like the
/// tiers list — admin-edited reference data, not per-booking state.
final packersMoversInventoryProvider = FutureProvider<List<PmGoodsCategory>>((ref) async {
  ref.keepAlive();
  final repo = ref.watch(logisticsRepositoryProvider);
  final result = await repo.getPackersMoversInventory();

  return switch (result) {
    Success(:final data) => data,
    Failure(:final error) => throw error,
  };
});

/// Selected item quantities for the in-progress Packers & Movers booking,
/// keyed by [PmGoodsItem.id]. A missing key means "not selected" (quantity
/// 0) — kept separate from the catalog itself so the catalog can stay
/// `keepAlive()` while this resets per booking attempt.
final pmSelectedQuantitiesProvider = StateProvider<Map<int, int>>((ref) => const {});

final pmPackingTierProvider = StateProvider<String>((ref) => 'standard');
final pmDismantlingRequiredProvider = StateProvider<bool>((ref) => true);
final pmUnpackingRequiredProvider = StateProvider<bool>((ref) => false);
final pmPickupFloorProvider = StateProvider<int>((ref) => 0);
final pmPickupHasLiftProvider = StateProvider<bool>((ref) => true);
final pmDropFloorProvider = StateProvider<int>((ref) => 0);
final pmDropHasLiftProvider = StateProvider<bool>((ref) => true);

/// How the customer wants to pay for a Goods Transport / Packers & Movers
/// booking: `cod`, `online` or `wallet` (wallet bookings are created as
/// ONLINE and settled from the SEVO wallet afterwards).
final gtPaymentMethodProvider = StateProvider<String>((ref) => 'cod');

final gtPaymentConfigProvider = FutureProvider.autoDispose<
    ({bool onlineAvailable, bool walletPartPayment})>((ref) {
  return ref.watch(paymentRepositoryProvider).getPaymentConfig();
});

/// SEVO wallet balance; null for guests.
final gtWalletBalanceProvider = FutureProvider.autoDispose<double?>((ref) {
  return ref.watch(paymentRepositoryProvider).getWalletBalance();
});

/// Extra helpers requested for the move (0..admin `max_helpers`).
final pmHelpersRequestedProvider = StateProvider<int>((ref) => 0);

/// Selected add-on services: add-on code -> quantity.
final pmAddOnsSelectedProvider = StateProvider<Map<String, int>>((ref) => const {});

/// Admin limit for extra helpers in [city].
final pmMaxHelpersProvider = FutureProvider.family<int, String>((ref, city) {
  return ref.watch(logisticsRepositoryProvider).getPackersMoversMaxHelpers(city);
});

/// Add-on catalogue configured for [city].
final pmAddOnsProvider = FutureProvider.family<List<PmAddOn>, String>((ref, city) async {
  final result = await ref.watch(logisticsRepositoryProvider).getPackersMoversAddOns(city);
  return switch (result) {
    Success(:final data) => data,
    Failure() => const <PmAddOn>[],
  };
});

/// Inputs for a service-zone coverage check.
typedef TripCoverageParam = ({
  String slug,
  String? point,
  double? pickupLat,
  double? pickupLng,
  double? dropLat,
  double? dropLng,
  String stopsKey,
  String? vehicleClass,
  int? laneId,
});

/// Is this trip (or one end of it) inside the admin's active coverage? Same
/// rules and messages as the web (`checkRouteCoverage` / `checkPointCoverage`).
final tripCoverageProvider =
    FutureProvider.autoDispose.family<TripCoverage, TripCoverageParam>((ref, p) async {
  // Debounce rapid changes (map pans, stop edits) like the web's 300 ms timer.
  var cancelled = false;
  ref.onDispose(() => cancelled = true);
  await Future<void>.delayed(const Duration(milliseconds: 300));
  if (cancelled) return const TripCoverage();
  final stops = <Map<String, double>>[];
  if (p.stopsKey.isNotEmpty) {
    for (final pair in p.stopsKey.split('|')) {
      final xy = pair.split(',');
      if (xy.length == 2) {
        final a = double.tryParse(xy[0]);
        final b = double.tryParse(xy[1]);
        if (a != null && b != null) stops.add({'lat': a, 'lng': b});
      }
    }
  }
  return ref.watch(logisticsRepositoryProvider).checkTripCoverage(
        serviceSlug: p.slug,
        point: p.point,
        pickupLat: p.pickupLat,
        pickupLng: p.pickupLng,
        dropLat: p.dropLat,
        dropLng: p.dropLng,
        stops: stops,
        vehicleClass: p.vehicleClass,
        laneId: p.laneId,
      );
});

/// Free-form on the backend (only checked for equality between quote and
/// booking, never enumerated/validated) — offered as a simple two-way choice
/// here since that's the only distinction the booking screen can usefully
/// offer without a full city-to-city route builder.
final pmRelocationTypeProvider = StateProvider<String>((ref) => 'Within City');

/// Parameters that determine the current Packers & Movers quote. Inventory
/// is folded into a stable string key for equality/hashing (a `List`/`Map`
/// doesn't compare deeply for provider-family caching purposes otherwise).
class PmQuoteParam {
  PmQuoteParam({
    required this.tierId,
    required this.city,
    required this.pickupLatitude,
    required this.pickupLongitude,
    required this.dropLatitude,
    required this.dropLongitude,
    required this.inventory,
    required this.packingTier,
    required this.dismantlingRequired,
    required this.unpackingRequired,
    required this.pickupFloor,
    required this.pickupHasLift,
    required this.dropFloor,
    required this.dropHasLift,
    required this.relocationType,
    this.moveDate,
    this.moveTime,
    this.stops = const [],
    this.laneId,
  }) : _inventoryKey = (inventory
            .map((e) => '${e['goods_item_id']}:${e['quantity']}')
            .toList()
          ..sort());

  final int tierId;
  final String city;
  final double pickupLatitude;
  final double pickupLongitude;
  final double dropLatitude;
  final double dropLongitude;
  final List<Map<String, dynamic>> inventory;
  final String packingTier;
  final bool dismantlingRequired;
  final bool unpackingRequired;
  final int pickupFloor;
  final bool pickupHasLift;
  final int dropFloor;
  final bool dropHasLift;
  final String relocationType;

  /// `yyyy-MM-dd` / slot label: admin peak-day and off-hours surcharges are
  /// priced server-side from these.
  final String? moveDate;
  final String? moveTime;

  /// Intermediate stops as `{address, latitude, longitude, stop_type}` maps.
  final List<Map<String, dynamic>> stops;
  final int? laneId;

  String get _stopsKey =>
      stops.map((s) => '${s['latitude']},${s['longitude']}').join('|');

  final List<String> _inventoryKey;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PmQuoteParam &&
          runtimeType == other.runtimeType &&
          tierId == other.tierId &&
          city == other.city &&
          pickupLatitude == other.pickupLatitude &&
          pickupLongitude == other.pickupLongitude &&
          dropLatitude == other.dropLatitude &&
          dropLongitude == other.dropLongitude &&
          packingTier == other.packingTier &&
          dismantlingRequired == other.dismantlingRequired &&
          unpackingRequired == other.unpackingRequired &&
          pickupFloor == other.pickupFloor &&
          pickupHasLift == other.pickupHasLift &&
          dropFloor == other.dropFloor &&
          dropHasLift == other.dropHasLift &&
          relocationType == other.relocationType &&
          moveDate == other.moveDate &&
          moveTime == other.moveTime &&
          laneId == other.laneId &&
          _stopsKey == other._stopsKey &&
          _inventoryKey.join(',') == other._inventoryKey.join(',');

  @override
  int get hashCode => Object.hash(
        tierId,
        city,
        pickupLatitude,
        pickupLongitude,
        dropLatitude,
        dropLongitude,
        packingTier,
        dismantlingRequired,
        unpackingRequired,
        pickupFloor,
        pickupHasLift,
        dropFloor,
        dropHasLift,
        relocationType,
        moveDate,
        moveTime,
        laneId,
        _stopsKey,
        _inventoryKey.join(','),
      );
}

final pmQuoteProvider = FutureProvider.autoDispose.family<PackersMoversQuote, PmQuoteParam>((ref, param) async {
  final repo = ref.watch(logisticsRepositoryProvider);
  final result = await repo.getPackersMoversQuote(
    inventory: param.inventory,
    pickupLatitude: param.pickupLatitude,
    pickupLongitude: param.pickupLongitude,
    dropLatitude: param.dropLatitude,
    dropLongitude: param.dropLongitude,
    city: param.city,
    selectedTierId: param.tierId,
    packingTier: param.packingTier,
    dismantlingRequired: param.dismantlingRequired,
    unpackingRequired: param.unpackingRequired,
    pickupFloor: param.pickupFloor,
    pickupHasLift: param.pickupHasLift,
    dropFloor: param.dropFloor,
    dropHasLift: param.dropHasLift,
    relocationType: param.relocationType,
    moveDate: param.moveDate,
    moveTime: param.moveTime,
    stops: param.stops,
    laneId: param.laneId,
  );

  return switch (result) {
    Success(:final data) => data,
    Failure(:final error) => throw error,
  };
});

/// Where the customer's browsing location came from. One rule, like the big delivery apps: an explicit choice
/// (a typed place) always beats GPS, GPS only fills the gap when nothing was chosen, and nothing is ever invented.
enum LocationSource { none, gps, manual }

/// Customer browsing location (used when no saved address is selected). Persisted across restarts.
class CustomerLocationState {
  const CustomerLocationState({
    this.address = '',
    this.pincode = '',
    this.latitude,
    this.longitude,
    this.source = LocationSource.none,
  });

  final String address;
  final String pincode;
  final double? latitude;
  final double? longitude;
  final LocationSource source;

  /// A real, usable point (never a made-up default).
  bool get hasLocation => source != LocationSource.none && latitude != null && longitude != null;
  bool get isDetected => source == LocationSource.gps;

  Map<String, dynamic> toJson() => {
        'address': address,
        'pincode': pincode,
        'lat': latitude,
        'lng': longitude,
        'source': source.name,
      };

  static CustomerLocationState? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final lat = (raw['lat'] as num?)?.toDouble();
    final lng = (raw['lng'] as num?)?.toDouble();
    final source = LocationSource.values.where((s) => s.name == raw['source']).firstOrNull ?? LocationSource.none;
    if (lat == null || lng == null || source == LocationSource.none) return null;
    return CustomerLocationState(
      address: (raw['address'] ?? '').toString(),
      pincode: (raw['pincode'] ?? '').toString(),
      latitude: lat,
      longitude: lng,
      source: source,
    );
  }
}

/// Customer location notifier.
///
/// Rules (the same ones Swiggy / Zomato / Amazon follow):
///  1. The last place the customer chose is remembered and restored on the next launch.
///  2. A typed place is an explicit choice: GPS never overwrites it. Only "Use current location" switches back.
///  3. With no choice yet, GPS fills in silently, but only if the permission is already granted and the phone's
///     location is on: no dialogs and no Settings screens on ordinary launches. Those belong to the explicit button.
///  4. A typed place must resolve to real coordinates, so serviceability is never checked against another place.
///  5. With nothing known the location stays empty ("Select location"); no fake default.
class CustomerLocationNotifier extends StateNotifier<CustomerLocationState> {
  CustomerLocationNotifier(this._storage) : super(const CustomerLocationState()) {
    _ready = _restore();
  }

  final SecureStorage _storage;
  late final Future<void> _ready;

  /// Set once something was chosen / detected, so a slow restore can never overwrite it.
  bool _touched = false;

  Future<void> _restore() async {
    try {
      final raw = await _storage.getBrowseLocationJson();
      if (raw == null || _touched || !mounted) return;
      final saved = CustomerLocationState.fromJson(jsonDecode(raw));
      if (saved != null) state = saved;
    } catch (_) {
      // A damaged copy just means "nothing remembered".
    }
  }

  void _set(CustomerLocationState next) {
    _touched = true;
    state = next;
    _persist(next);
  }

  Future<void> _persist(CustomerLocationState s) async {
    try {
      await _storage.setBrowseLocationJson(jsonEncode(s.toJson()));
    } catch (_) {}
  }

  /// Reads the device position and names it (reverse geocoding is best effort; the coordinates are always real).
  Future<CustomerLocationState> _readPosition() async {
    final position = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 15)),
    );
    var address = 'Current location';
    var pincode = '';
    try {
      final placemarks = await placemarkFromCoordinates(position.latitude, position.longitude);
      if (placemarks.isNotEmpty) {
        final p = placemarks.first;
        final locality = (p.locality ?? '').trim();
        final adminArea = (p.administrativeArea ?? '').trim();
        final name = [locality, adminArea].where((s) => s.isNotEmpty).join(', ');
        if (name.isNotEmpty) address = name;
        pincode = (p.postalCode ?? '').trim();
      }
    } catch (_) {}
    return CustomerLocationState(
      address: address,
      pincode: pincode,
      latitude: position.latitude,
      longitude: position.longitude,
      source: LocationSource.gps,
    );
  }

  /// Quiet detection for ordinary launches: fills the location from GPS only when the customer has not chosen a
  /// place, the permission is already granted and the phone's location is on. Never shows a dialog or opens Settings.
  Future<void> autoDetectIfNeeded() async {
    await _ready;
    if (state.source == LocationSource.manual) return; // an explicit choice stays
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return;
      final permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever ||
          permission == LocationPermission.unableToDetermine) {
        return;
      }
      final fix = await _readPosition();
      // The customer may have typed a place while the fix was being read.
      if (mounted && state.source != LocationSource.manual) _set(fix);
    } catch (_) {
      // Keep whatever is remembered; never substitute fake coordinates.
    }
  }

  /// "Use current location": the explicit action. Turns the phone's location on (in-app prompt), asks for the
  /// permission, and switches the browsing location to the device position.
  ///
  /// Returns true only when a real position was read and stored. A customer who answers "No thanks" to the in-app
  /// prompt, or denies the permission, gets false and stays where they are. Settings is only opened when the in-app
  /// prompt could not be shown at all (iOS, or Play Services unavailable) or, when [openSettingsIfBlocked], for a
  /// permanently denied permission, which has no other way back.
  Future<bool> detectAndSetCurrentLocation({bool openSettingsIfBlocked = false}) async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        var enabledNow = false;
        var promptUnavailable = false;
        try {
          enabledNow = await loc.Location().requestService();
        } catch (_) {
          promptUnavailable = true;
        }
        // iOS never lets an app flip the switch, so requestService() is always "false" there - not a refusal.
        if (defaultTargetPlatform == TargetPlatform.iOS) promptUnavailable = true;
        if (!enabledNow) {
          final stillDisabled = !(await Geolocator.isLocationServiceEnabled());
          if (stillDisabled) {
            if (promptUnavailable && openSettingsIfBlocked) {
              await Geolocator.openLocationSettings();
            }
            return false;
          }
        }
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.deniedForever) {
        if (openSettingsIfBlocked) await Geolocator.openAppSettings();
        return false;
      }
      if (permission == LocationPermission.denied) return false;

      _set(await _readPosition());
      return true;
    } catch (_) {
      return false;
    }
  }

  /// A place the customer typed (no account needed). Coordinates are required: a place that could not be located is
  /// refused by the caller instead of being saved with another place's coordinates.
  void setManualLocation(String address, String pincode, {required double latitude, required double longitude}) {
    _set(CustomerLocationState(
      address: address,
      pincode: pincode,
      latitude: latitude,
      longitude: longitude,
      source: LocationSource.manual,
    ));
  }
}

final customerLocationProvider =
    StateNotifierProvider<CustomerLocationNotifier, CustomerLocationState>(
        (ref) => CustomerLocationNotifier(ref.read(secureStorageProvider)));
