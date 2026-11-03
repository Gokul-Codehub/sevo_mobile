import 'package:calservices_customer/features/logistics/domain/gt_declaration.dart';
import 'package:calservices_customer/features/logistics/domain/gt_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const pots = CargoLine(
    quantity: 4,
    customName: 'Clay pots',
    weightKg: 6,
    cft: 2.5,
    isFragile: true,
    packing: 'cartons',
    declaredValue: 9000,
    goodsCategoryName: 'Household',
    sizeKey: 'small',
    photoDataUrl: 'data:image/jpeg;base64,AAAA',
    lengthCm: 40,
    widthCm: 30,
    heightCm: 25,
  );

  test('a typed line carries everything the server validates', () {
    final j = pots.toJson();
    expect(j['is_custom'], true);
    expect(j['declared_value'], 9000);
    expect(j['packing'], 'cartons');
    expect([j['length_cm'], j['width_cm'], j['height_cm']], [40, 30, 25]);
    expect(j['photo_url'], startsWith('data:image/jpeg'));
    expect(j['is_liquid'], false);
  });

  test('quote / fitment payloads never carry the photo', () {
    final items = const CargoDeclaration(items: [pots]).toPayload()['cargo_items'] as List;
    expect((items.first as Map).containsKey('photo_url'), isFalse);
    expect((items.first as Map)['declared_value'], 9000);
  });

  test('typed goods add up to the booking value; catalogue items add nothing', () {
    const d = CargoDeclaration(items: [
      pots,
      CargoLine(quantity: 1, customName: 'Chair', weightKg: 5, declaredValue: 1500),
      CargoLine(itemId: 7, quantity: 2),
    ]);
    expect(d.hasCustom, isTrue);
    expect(d.customValueTotal, 10500);
    expect(const CargoDeclaration(items: [CargoLine(itemId: 7, quantity: 2)]).hasCustom, isFalse);
  });

  test('declaration: accepted flag only for typed goods, notes only when written', () {
    expect(const GtGoodsDecl().cartFields(hasTypedGoods: false), isEmpty);
    expect(const GtGoodsDecl(accepted: true).cartFields(hasTypedGoods: true), {'goods_declaration_accepted': true});
    expect(
      const GtGoodsDecl(pickup: ' 3rd floor ', drop: '').cartFields(hasTypedGoods: false),
      {'handling_instructions': {'pickup': '3rd floor'}},
    );
  });

  test('insurance terms: offered and unavailable shapes', () {
    final on = InsuranceTerms.fromJson({
      'offered': true, 'premium': '150.00', 'liability_cap': '10000.00', 'rate_percent': '1.5',
      'exclusions': 'No cash', 'consent_text': 'I agree', 'policy_reference': 'POL-1',
    });
    expect(on.offered, isTrue);
    expect(on.premium, 150);
    expect(on.exclusions, 'No cash');
    final off = InsuranceTerms.fromJson({'offered': false, 'reason': 'expired', 'message': 'x'});
    expect(off.offered, isFalse);
    expect(off.reason, 'expired');
  });
}
