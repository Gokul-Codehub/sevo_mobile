import 'package:calservices_customer/features/logistics/domain/gt_assist.dart';
import 'package:calservices_customer/features/logistics/domain/logistics_models.dart';
import 'package:flutter_test/flutter_test.dart';

LogisticsTier tier({double helper = 0, int max = 0, double carry = 0}) => LogisticsTier.fromJson({
      'id': 1,
      'extra_helper_charge': helper,
      'max_extra_helpers': max,
      'carry_charge_per_floor': carry,
    });

void main() {
  test('nothing asked, nothing sent', () {
    expect(const GtAssist().isEmpty, isTrue);
    expect(const GtAssist().accessJson(), isNull);
  });

  test('a tier that offers nothing strips helpers and carry but keeps the access answers', () {
    final a = const GtAssist(helpers: 2, carry: true, pickupFloor: 3, pickupHasLift: false).forTier(tier());
    expect(a.isEmpty, isTrue);
    expect(a.pickupFloor, 3);
  });

  test('helpers are capped at the tier maximum', () {
    expect(const GtAssist(helpers: 9).forTier(tier(helper: 100, max: 2)).helpers, 2);
  });

  test('carry is dropped when the tier has no per-floor rate', () {
    final a = const GtAssist(helpers: 1, carry: true).forTier(tier(helper: 100, max: 2));
    expect(a.carry, isFalse);
    expect(a.helpers, 1);
  });

  test('only an end above ground with no lift is carried by stairs', () {
    const a = GtAssist(carry: true, pickupFloor: 3, dropFloor: 2, pickupHasLift: true, dropHasLift: false);
    expect(a.carryFloors, 2);
    expect(const GtAssist(carry: true, pickupFloor: 3).carryFloors, 0); // lift not answered
    expect(const GtAssist(carry: true, dropHasLift: false).carryFloors, 0); // ground floor
  });

  test('cargo_access: floors, lift answers and narrow lane, as the web sends them', () {
    const a = GtAssist(pickupFloor: 3, pickupHasLift: false, dropFloor: 2, narrowLane: true);
    expect(a.accessJson(), {
      'pickup': {'floor': 3, 'has_lift': false, 'stairs_only': true, 'narrow_lane': true},
      'drop': {'floor': 2, 'narrow_lane': true},
    });
    expect(const GtAssist(dropFloor: 1, dropHasLift: true).accessJson(), {
      'drop': {'floor': 1, 'has_lift': true, 'stairs_only': false},
    });
  });

  test('going back to ground clears the lift answer', () {
    final a = const GtAssist(pickupFloor: 2, pickupHasLift: false).copyWith(pickupFloor: 0, pickupHasLift: null);
    expect(a.pickupHasLift, isNull);
  });
}
