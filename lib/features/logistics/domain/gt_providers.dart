import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/api_error.dart';
import '../data/logistics_repository.dart';
import 'gt_assist.dart';
import 'gt_declaration.dart';
import 'gt_models.dart';
import 'logistics_models.dart';

// Riverpod wiring for the Goods & Transport endpoints added to the backend
// (`backend/logistics`). Reference data (catalogue, FAQs, policies, PTL config)
// is cached like `logisticsTiersProvider`; per-attempt data is autoDispose.

T _unwrap<T>(Result<T> result) => switch (result) {
      Success(:final data) => data,
      Failure(:final error) => throw error,
    };

// ── Reference data ──────────────────────────────────────────────────────────

final goodsCategoriesProvider = FutureProvider<List<GoodsCategory>>((ref) async {
  ref.keepAlive();
  return _unwrap(await ref.watch(logisticsRepositoryProvider).getGoodsCategories());
});

/// Items of one goods category (id or slug); null = every item.
final goodsItemsProvider =
    FutureProvider.family<List<GoodsItem>, Object?>((ref, category) async {
  ref.keepAlive();
  return _unwrap(
    await ref.watch(logisticsRepositoryProvider).getGoodsItems(category: category),
  );
});

final gtFaqsProvider =
    FutureProvider.family<List<GtFaq>, ({String? category, String? city})>(
        (ref, p) async {
  ref.keepAlive();
  return _unwrap(
    await ref
        .watch(logisticsRepositoryProvider)
        .getGtFaqs(category: p.category, city: p.city),
  );
});

/// Terms for `service_category` (goods_transport_truck |
/// goods_transport_two_wheeler | packers_movers).
final gtPoliciesProvider =
    FutureProvider.family<GtPolicyTerms, String>((ref, serviceCategory) async {
  ref.keepAlive();
  return _unwrap(
    await ref.watch(logisticsRepositoryProvider).getGtPolicies(
          serviceCategory.split('#').first,
          bookingMode: serviceCategory.contains('#') ? serviceCategory.split('#').last : null,
        ),
  );
});

final ptlConfigProvider =
    FutureProvider.family<PtlConfig, String?>((ref, city) async {
  return _unwrap(await ref.watch(logisticsRepositoryProvider).getPtlConfig(city: city));
});

// ── Per-attempt data ────────────────────────────────────────────────────────

/// Truck / 2-Wheeler dispatch choice, as on the web: false = Urgent (nearest driver now), true = Schedule for a later date.
final gtScheduledProvider = StateProvider<bool>((ref) => false);

/// Server-authoritative slots for a date + service category (+ city).
final gtSlotsProvider = FutureProvider.autoDispose
    .family<GtSlotsResult, ({String date, String category, String? city})>(
        (ref, p) async {
  return _unwrap(
    await ref
        .watch(logisticsRepositoryProvider)
        .getGtSlots(date: p.date, category: p.category, city: p.city),
  );
});

/// Which vehicles can safely carry the declared cargo.
final cargoFitmentProvider = FutureProvider.autoDispose
    .family<CargoFitment, ({CargoDeclaration cargo, String city})>((ref, p) async {
  return _unwrap(
    await ref
        .watch(logisticsRepositoryProvider)
        .evaluateCargo(cargo: p.cargo, city: p.city),
  );
});

/// Whether transit insurance is sold for a service (and why not), checked with a nominal value like the web does.
final insuranceAvailabilityProvider = FutureProvider.autoDispose
    .family<InsuranceTerms, ({String service, String? mode})>((ref, k) async {
  return _unwrap(await ref
      .watch(logisticsRepositoryProvider)
      .getInsuranceTerms(1000, serviceCategory: k.service, bookingMode: k.mode));
});

/// Premium, cover, exclusions and consent wording for a declared goods value.
final insuranceTermsProvider = FutureProvider.autoDispose
    .family<InsuranceTerms, ({double value, String service, String? mode})>((ref, k) async {
  return _unwrap(await ref
      .watch(logisticsRepositoryProvider)
      .getInsuranceTerms(k.value, serviceCategory: k.service, bookingMode: k.mode));
});

class PtlQuoteParam {
  const PtlQuoteParam({
    required this.tierId,
    required this.declaredWeightKg,
    required this.pickupLatitude,
    required this.pickupLongitude,
    required this.dropLatitude,
    required this.dropLongitude,
    this.laneId,
    this.loadAssist = false,
  });

  final int tierId;
  final double declaredWeightKg;
  final double pickupLatitude;
  final double pickupLongitude;
  final double dropLatitude;
  final double dropLongitude;
  final int? laneId;
  final bool loadAssist;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PtlQuoteParam &&
          tierId == other.tierId &&
          declaredWeightKg == other.declaredWeightKg &&
          pickupLatitude == other.pickupLatitude &&
          pickupLongitude == other.pickupLongitude &&
          dropLatitude == other.dropLatitude &&
          dropLongitude == other.dropLongitude &&
          laneId == other.laneId &&
          loadAssist == other.loadAssist;

  @override
  int get hashCode => Object.hash(tierId, declaredWeightKg, pickupLatitude,
      pickupLongitude, dropLatitude, dropLongitude, laneId, loadAssist);
}

final ptlQuoteProvider =
    FutureProvider.autoDispose.family<PtlQuote, PtlQuoteParam>((ref, p) async {
  return _unwrap(
    await ref.watch(logisticsRepositoryProvider).getPtlQuote(
          tierId: p.tierId,
          declaredWeightKg: p.declaredWeightKg,
          pickupLatitude: p.pickupLatitude,
          pickupLongitude: p.pickupLongitude,
          dropLatitude: p.dropLatitude,
          dropLongitude: p.dropLongitude,
          laneId: p.laneId,
          loadAssist: p.loadAssist,
        ),
  );
});

// ── In-progress booking selections ──────────────────────────────────────────
// Reset by the booking screen when it submits / is disposed.

/// What the customer is shipping (items, goods category, weight, CFT).
final cargoDeclarationProvider =
    StateProvider<CargoDeclaration>((ref) => const CargoDeclaration());

/// "Loading help" — driver-assisted loading (default on, matching the backend).
final loadingHelpProvider = StateProvider<bool>((ref) => true);

/// Mini Truck extra helpers / stairs carrying the customer asked for (nothing by default).
final gtAssistProvider = StateProvider<GtAssist>((ref) => const GtAssist());

/// Optional fixed-fare lane picked by the customer (`logistics_lane`).
final selectedGtLaneProvider = StateProvider<LogisticsLane?>((ref) => null);

/// Customer consent to an estimated-distance fare (`accept_estimated_distance`),
/// required by the backend only when road routing is unavailable and Admin
/// policy is ESTIMATE_WITH_CONSENT.
final acceptEstimatedDistanceProvider = StateProvider<bool>((ref) => false);

/// Transit insurance opt-in (`insurance_opted_in`) — prepaid payment only.
final insuranceOptInProvider = StateProvider<bool>((ref) => false);

/// The goods the customer lists for a Part Truck Load or a Packers & Movers booking (sent as `declared_goods`,
/// like the web's goods list). Truck / Two-Wheeler bookings keep their goods in [cargoDeclarationProvider].
final declaredGoodsProvider = StateProvider<List<CargoLine>>((ref) => const []);

/// The customer's tick on the insurer's consent wording (`insurance_consent`); without it the booking is not insured.
final insuranceConsentProvider = StateProvider<bool>((ref) => false);

/// Handling notes for the driver + the accuracy confirmation (required for typed goods).
final gtGoodsDeclProvider = StateProvider<GtGoodsDecl>((ref) => const GtGoodsDecl());

final customerGstinProvider = StateProvider<String>((ref) => '');
final ewayBillNumberProvider = StateProvider<String>((ref) => '');

/// Light PTL (Part Truck Load) mode: priced per kg, advance-only, customer
/// loads/unloads, single pickup → single drop.
final ptlModeProvider = StateProvider<bool>((ref) => false);
final ptlWeightKgProvider = StateProvider<double?>((ref) => null);
final ptlLoadAssistProvider = StateProvider<bool>((ref) => false);
