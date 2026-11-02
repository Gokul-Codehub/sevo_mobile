import 'dart:convert';

import 'package:calservices_customer/core/network/api_client.dart';
import 'package:calservices_customer/core/errors/api_error.dart';
import 'package:calservices_customer/features/catalog/data/marketplace_catalog_repository.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

class _Adapter implements HttpClientAdapter {
  _Adapter(this.respond);
  final (int, Object) Function(RequestOptions) respond;
  final List<RequestOptions> calls = [];
  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<List<int>>? requestStream, Future<void>? cancelFuture) async {
    calls.add(options);
    final (status, body) = respond(options);
    return ResponseBody.fromString(jsonEncode(body), status, headers: {
      Headers.contentTypeHeader: ['application/json'],
    });
  }

  @override
  void close({bool force = false}) {}
}

MarketplaceCatalogRepository repoFor(_Adapter a, {Future<DeliveryZone> Function()? zone}) {
  final dio = Dio(BaseOptions(baseUrl: 'https://example.test'))..httpClientAdapter = a;
  return MarketplaceCatalogRepository(api: ApiClient.withDio(dio), warehouseResolver: zone);
}

(int, Object) products(RequestOptions o) => (200, {'results': [{'id': 1, 'title': 'Tomato', 'selling_price': '40'}], 'count': 1});

void main() {
  group('resolving the warehouse', () {
    test('a serviceable point gives the warehouse', () async {
      final a = _Adapter((_) => (200, {'is_serviceable': true, 'warehouse': {'id': 7, 'name': 'Hosur Hub'}}));
      final zone = await repoFor(a).resolveWarehouse(lat: 12.7, lng: 77.8);
      expect((zone.status, zone.warehouseId, zone.name), (DeliveryZoneStatus.serviceable, 7, 'Hosur Hub'));
      expect(a.calls.single.queryParameters, {'lat': 12.7, 'lng': 77.8});
    });

    test('outside every service area is unserviceable, with the server message', () async {
      final a = _Adapter((_) => (200, {'is_serviceable': false, 'warehouse': null, 'message': 'We do not deliver to this location yet.'}));
      final zone = await repoFor(a).resolveWarehouse(lat: 1, lng: 1);
      expect(zone.status, DeliveryZoneStatus.unserviceable);
      expect(zone.message, contains('do not deliver'));
    });

    test('a saved address without coordinates is resolved by id', () async {
      final a = _Adapter((_) => (200, {'is_serviceable': true, 'warehouse': {'id': 2, 'name': 'X'}}));
      await repoFor(a).resolveWarehouse(addressId: 9);
      expect(a.calls.single.queryParameters, {'address_id': 9});
    });

    test('server errors and nothing to look up fail open (unknown), never unserviceable', () async {
      expect((await repoFor(_Adapter((_) => (502, {'error': 'x'}))).resolveWarehouse(lat: 1, lng: 1)).status, DeliveryZoneStatus.unknown);
      expect((await repoFor(_Adapter((_) => (200, {}))).resolveWarehouse()).status, DeliveryZoneStatus.unknown);
    });
  });

  group('product lists follow the delivery zone', () {
    test('the warehouse id is sent with the request', () async {
      final a = _Adapter(products);
      final r = await repoFor(a, zone: () async => const DeliveryZone.serviceable(7, 'Hub')).getProducts(categoryId: 3);
      expect(a.calls.single.queryParameters['warehouse_id'], 7);
      expect((r as Success<MarketplaceProductPage>).data.products, hasLength(1));
    });

    test('unknown zone: no filter, products still load', () async {
      final a = _Adapter(products);
      await repoFor(a, zone: () async => const DeliveryZone.unknown()).getProducts();
      expect(a.calls.single.queryParameters.containsKey('warehouse_id'), isFalse);
    });

    test('unserviceable: nothing is requested and the list is empty', () async {
      final a = _Adapter(products);
      final r = await repoFor(a, zone: () async => const DeliveryZone.unserviceable('no')).getProducts();
      expect(a.calls, isEmpty);
      expect((r as Success<MarketplaceProductPage>).data.products, isEmpty);
    });
  });
}
