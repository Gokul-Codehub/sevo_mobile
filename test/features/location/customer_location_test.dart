import 'package:calservices_customer/core/storage/secure_storage.dart';
import 'package:calservices_customer/features/addresses/domain/address_models.dart';
import 'package:calservices_customer/features/addresses/domain/address_notifier.dart';
import 'package:calservices_customer/features/logistics/domain/logistics_providers.dart';
import 'package:flutter_test/flutter_test.dart';

class _MemoryStorage extends SecureStorage {
  String? saved;
  @override
  Future<String?> getBrowseLocationJson() async => saved;
  @override
  Future<void> setBrowseLocationJson(String json) async => saved = json;
}

void main() {
  lastChoiceTests();
  test('nothing is invented: a fresh state has no location', () {
    const s = CustomerLocationState();
    expect(s.hasLocation, isFalse);
    expect(s.latitude, isNull);
    expect(s.address, isEmpty);
    expect(s.isDetected, isFalse);
  });

  test('a typed place is remembered, and restored by the next launch', () async {
    final store = _MemoryStorage();
    final first = CustomerLocationNotifier(store);
    first.setManualLocation('Hosur, Tamil Nadu', '635109', latitude: 12.74, longitude: 77.82);
    await Future<void>.delayed(Duration.zero);
    expect(first.state.source, LocationSource.manual);
    expect(store.saved, isNotNull);

    final second = CustomerLocationNotifier(store);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(second.state.address, 'Hosur, Tamil Nadu');
    expect(second.state.latitude, 12.74);
    expect(second.state.hasLocation, isTrue);
  });

  test('a slow restore never overwrites a place chosen meanwhile', () async {
    final store = _MemoryStorage()
      ..saved = '{"address":"Old","pincode":"","lat":1.0,"lng":2.0,"source":"gps"}';
    final n = CustomerLocationNotifier(store);
    n.setManualLocation('New', '560001', latitude: 12.9, longitude: 77.6);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(n.state.address, 'New');
  });

  test('a damaged or incomplete saved copy means nothing remembered', () async {
    for (final bad in ['not json', '{"lat":1.0}', '{"lat":1.0,"lng":2.0,"source":"none"}']) {
      final n = CustomerLocationNotifier(_MemoryStorage()..saved = bad);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(n.state.hasLocation, isFalse, reason: bad);
    }
  });

  test('saved addresses no longer default to another city or state', () {
    final a = Address.fromJson({'id': 1, 'address_line_1': '12 Main Rd', 'postal_code': '635109'});
    expect(a.city, isEmpty);
    expect(a.state, isEmpty);
    expect(a.formattedAddress, '12 Main Rd, 635109');
  });
}

void lastChoiceTests() {
  Address a(int id, {bool def = false}) => Address(id: id, addressLine1: 'x$id', city: 'c', postalCode: '1', isDefault: def);

  test('starts from the address used last, else the default', () {
    final all = [a(1, def: true), a(2), a(3)];
    expect(startingAddress(all, parseLastDeliveryChoice('{"id":3}'))?.id, 3);
    expect(startingAddress(all, parseLastDeliveryChoice('{"id":99}'))?.id, 1); // that address was deleted
    expect(startingAddress(all, parseLastDeliveryChoice(null))?.id, 1);
    expect(startingAddress([a(5), a(6)], const LastDeliveryChoice())?.id, 5); // no default: the first
  });

  test('a searched / detected place last time means no saved address is auto-selected', () {
    expect(startingAddress([a(1, def: true)], parseLastDeliveryChoice('{"id":null}')), isNull);
    expect(parseLastDeliveryChoice('garbage').placeChosen, isFalse);
  });
}
