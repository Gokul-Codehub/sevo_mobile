import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';
import 'package:location/location.dart' as loc;

import '../../../core/errors/api_error.dart';
import '../data/logistics_repository.dart';
import 'logistics_models.dart';

/// Currently selected booking appointment date.
final selectedBookingDateProvider = StateProvider<DateTime>((ref) {
  final now = DateTime.now();
  // If at or after 6 PM (18:00), same-day booking closes; default to tomorrow
  return now.hour >= 18 ? now.add(const Duration(days: 1)) : now;
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

/// Provider fetching time slots for a given date (YYYY-MM-DD) + service id/slug.
final timeSlotsProvider = FutureProvider.family<List<TimeSlot>,
    ({String date, String? serviceId})>((ref, params) async {
  final repo = ref.watch(logisticsRepositoryProvider);
  final result =
      await repo.getTimeSlots(date: params.date, serviceId: params.serviceId);

  return switch (result) {
    Success(:final data) => data,
    Failure(:final error) => throw error,
  };
});

/// Convenience provider for slots of the currently selected date + service.
final currentSelectedDateSlotsProvider = FutureProvider<List<TimeSlot>>((ref) {
  final selectedDate = ref.watch(selectedBookingDateProvider);
  final serviceId = ref.watch(selectedBookingServiceIdProvider);
  final dateString = DateFormat('yyyy-MM-dd').format(selectedDate);
  return ref.watch(
      timeSlotsProvider((date: dateString, serviceId: serviceId)).future);
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
  });

  final int tierId;
  final String serviceCategory;
  final double pickupLatitude;
  final double pickupLongitude;
  final double dropLatitude;
  final double dropLongitude;

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
          dropLongitude == other.dropLongitude;

  @override
  int get hashCode => Object.hash(tierId, serviceCategory, pickupLatitude,
      pickupLongitude, dropLatitude, dropLongitude);
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
  );

  return switch (result) {
    Success(:final data) => data,
    Failure(:final error) => throw error,
  };
});

/// Customer location state model.
class CustomerLocationState {
  const CustomerLocationState({
    this.address = 'Hosur, Tamil Nadu',
    this.pincode = '635109',
    this.latitude = 12.7409,
    this.longitude = 77.8253,
    this.isDetected = true,
  });

  final String address;
  final String pincode;
  final double latitude;
  final double longitude;
  final bool isDetected;

  CustomerLocationState copyWith({
    String? address,
    String? pincode,
    double? latitude,
    double? longitude,
    bool? isDetected,
  }) {
    return CustomerLocationState(
      address: address ?? this.address,
      pincode: pincode ?? this.pincode,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      isDetected: isDetected ?? this.isDetected,
    );
  }
}

/// Customer location notifier provider.
class CustomerLocationNotifier extends StateNotifier<CustomerLocationState> {
  CustomerLocationNotifier() : super(const CustomerLocationState());

  // Fixed 2026-08-27: this previously never touched the device's actual GPS
  // at all — it just always set the same hardcoded "Current Location,
  // Hosur" / 635109, regardless of where the customer actually was. Now it
  // reads the real device position (respecting permission state) and
  // reverse-geocodes it, falling back to the previous state (never to fake
  // coordinates) if location is unavailable/denied.
  Future<void> detectAndSetCurrentLocation() async {
    try {
      // Fixed 2026-09-29 per explicit report ("if user clicks the user my
      // current location the android does not open the accessibility to
      // turn on"): this used to just `return` here, doing nothing at all
      // when the phone's location service (GPS) itself is switched off at
      // the OS level — a common state, especially on first launch.
      //
      // Fixed again 2026-10-01 per explicit report ("whenever i open the
      // app it open the mobile settings to turn on th location... if user
      // click in back [it] should turn on the location without redirect to
      // the settings"): this used to unconditionally call
      // Geolocator.openLocationSettings(), kicking the customer straight
      // out to Android's system Settings app on every app open where GPS
      // was off — this is the exact screen (LocationAccessScreen, shown
      // right on first/every app launch) the report was about. `location`'s
      // requestService() shows Google Play Services' own native in-app
      // "Turn on location" resolution dialog instead (same pattern already
      // applied in core/utils/location_gate.dart for the checkout flow), so
      // the customer can enable GPS without ever leaving CalServices.
      // Falls back to the old Settings deep-link only if the in-app prompt
      // fails or isn't available (iOS, or Play Services missing/outdated).
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        var enabledNow = false;
        try {
          enabledNow = await loc.Location().requestService();
        } catch (_) {
          enabledNow = false;
        }
        if (!enabledNow) {
          final stillDisabled = !(await Geolocator.isLocationServiceEnabled());
          if (stillDisabled) {
            await Geolocator.openLocationSettings();
            return;
          }
        }
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.deniedForever) {
        // Permanently denied ("Don't ask again") — Android will never show
        // the in-app permission dialog again from here on, so the only way
        // forward is the app's own permission settings page. openAppSettings()
        // jumps straight there, same fix pattern as the GPS-off case above.
        await Geolocator.openAppSettings();
        return;
      }
      if (permission == LocationPermission.denied) {
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 15),
        ),
      );

      String address = state.address;
      String pincode = state.pincode;
      try {
        final placemarks = await placemarkFromCoordinates(
          position.latitude,
          position.longitude,
        );
        if (placemarks.isNotEmpty) {
          final p = placemarks.first;
          final locality = (p.locality ?? '').trim();
          final adminArea = (p.administrativeArea ?? '').trim();
          if (locality.isNotEmpty || adminArea.isNotEmpty) {
            address = [locality, adminArea].where((s) => s.isNotEmpty).join(', ');
          }
          if ((p.postalCode ?? '').trim().isNotEmpty) {
            pincode = p.postalCode!.trim();
          }
        }
      } catch (_) {
        // Reverse geocoding is best-effort — coordinates below are still real.
      }

      state = state.copyWith(
        address: address,
        pincode: pincode,
        latitude: position.latitude,
        longitude: position.longitude,
        isDetected: true,
      );
    } catch (_) {
      // Leave state unchanged on any GPS failure rather than substituting
      // fake coordinates.
    }
  }

  void setManualLocation(String address, String pincode) {
    state = state.copyWith(
      address: address,
      pincode: pincode,
      isDetected: false,
    );
  }
}

final customerLocationProvider =
    StateNotifierProvider<CustomerLocationNotifier, CustomerLocationState>(
        (ref) => CustomerLocationNotifier());

