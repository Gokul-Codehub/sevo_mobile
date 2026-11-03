import 'dart:math' as math;

import 'package:equatable/equatable.dart';

import 'logistics_models.dart';

const Object _keep = Object();

/// How the goods get from the door to the vehicle, as the web's "Floor and access" block collects it:
///  * which floor each end is on, whether a lift works there, and whether the vehicle can reach the door - these only
///    brief the driver (sent as `cargo_access`) and never change the price;
///  * Mini Truck extra help, which the server prices from rates the Admin sets on each tier: a charge per helper beyond
///    the driver (up to the tier's maximum) and a charge per floor carried by stairs (only for an end with no lift).
///    Sent to `POST /logistics/quote/` as `assist`, and echoed under cart_data[0].assist when booking.
/// The app never prices any of this: it only tells the server what the customer said.
class GtAssist extends Equatable {
  const GtAssist({
    this.helpers = 0,
    this.carry = false,
    this.pickupFloor = 0,
    this.dropFloor = 0,
    this.pickupHasLift,
    this.dropHasLift,
    this.narrowLane = false,
  });

  final int helpers;
  final bool carry;
  final int pickupFloor;
  final int dropFloor;

  /// null until the customer answers "Is there a working lift?" (asked only above ground).
  final bool? pickupHasLift;
  final bool? dropHasLift;

  /// The vehicle cannot reach the door (narrow lane or no parking).
  final bool narrowLane;

  static const int maxFloor = 60; // the server's limit

  /// No priced extra help asked for: nothing is sent as `assist`.
  bool get isEmpty => helpers == 0 && !carry;

  /// Floors that would be carried by stairs: an end counts only above ground with "no lift" answered.
  int get carryFloors => !carry ? 0 : (_stairs(pickupFloor, pickupHasLift) ? pickupFloor : 0) + (_stairs(dropFloor, dropHasLift) ? dropFloor : 0);

  static bool _stairs(int floor, bool? lift) => floor > 0 && lift == false;

  bool get hasStairs => _stairs(pickupFloor, pickupHasLift) || _stairs(dropFloor, dropHasLift);

  GtAssist copyWith({
    int? helpers,
    bool? carry,
    int? pickupFloor,
    int? dropFloor,
    Object? pickupHasLift = _keep,
    Object? dropHasLift = _keep,
    bool? narrowLane,
  }) =>
      GtAssist(
        helpers: helpers ?? this.helpers,
        carry: carry ?? this.carry,
        pickupFloor: pickupFloor ?? this.pickupFloor,
        dropFloor: dropFloor ?? this.dropFloor,
        pickupHasLift: identical(pickupHasLift, _keep) ? this.pickupHasLift : pickupHasLift as bool?,
        dropHasLift: identical(dropHasLift, _keep) ? this.dropHasLift : dropHasLift as bool?,
        narrowLane: narrowLane ?? this.narrowLane,
      );

  /// What can really be asked on [tier]: helpers within its maximum, no carrying the tier does not offer.
  /// The floors, lifts and narrow-lane answer are kept: they brief the driver whatever the vehicle.
  GtAssist forTier(LogisticsTier? tier) => GtAssist(
        helpers: tier != null && tier.extraHelperCharge > 0 ? math.min(math.max(helpers, 0), tier.maxExtraHelpers) : 0,
        carry: tier != null && tier.carryChargePerFloor > 0 && carry,
        pickupFloor: pickupFloor.clamp(0, maxFloor),
        dropFloor: dropFloor.clamp(0, maxFloor),
        pickupHasLift: pickupHasLift,
        dropHasLift: dropHasLift,
        narrowLane: narrowLane,
      );

  Map<String, Object?> toJson() => {
        'helpers': helpers,
        'carry': carry,
        'pickup_floor': pickupFloor,
        'drop_floor': dropFloor,
        'pickup_has_lift': pickupHasLift,
        'drop_has_lift': dropHasLift,
      };

  /// The booking's top-level `cargo_access`, or null when the customer said nothing beyond the default.
  Map<String, Object>? accessJson() {
    Map<String, Object> side(int floor, bool? lift) => {
          if (floor > 0) 'floor': floor,
          if (floor > 0 && lift != null) ...{'has_lift': lift, 'stairs_only': !lift},
          if (narrowLane) 'narrow_lane': true,
        };
    final p = side(pickupFloor, pickupHasLift);
    final d = side(dropFloor, dropHasLift);
    final out = <String, Object>{if (p.isNotEmpty) 'pickup': p, if (d.isNotEmpty) 'drop': d};
    return out.isEmpty ? null : out;
  }

  @override
  List<Object?> get props => [helpers, carry, pickupFloor, dropFloor, pickupHasLift, dropHasLift, narrowLane];
}
