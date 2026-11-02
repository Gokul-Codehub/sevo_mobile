import 'dart:convert';

import 'package:calservices_customer/core/network/api_client.dart';
import 'package:calservices_customer/features/booking/domain/booking_models.dart';
import 'package:calservices_customer/features/catalog/data/marketplace_catalog_repository.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _Adapter implements HttpClientAdapter {
  final List<RequestOptions> calls = [];
  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<List<int>>? requestStream, Future<void>? cancelFuture) async {
    calls.add(options);
    final body = {
      'success': true,
      'data': {
        'warehouse_id': options.queryParameters['warehouse_id'],
        'date': options.queryParameters['date'],
        'slots': [
          {'id': 1, 'label': '09:00 AM - 10:00 AM', 'start_time': '09:00', 'end_time': '10:00', 'available': true},
        ],
      },
    };
    return ResponseBody.fromString(jsonEncode(body), 200, headers: {
      Headers.contentTypeHeader: ['application/json'],
    });
  }

  @override
  void close({bool force = false}) {}
}

Map<String, dynamic> productJson({Object? warehouseId = 1, Map<String, dynamic>? warehouse}) => {
      'id': 79,
      'title': 'Farm Tomato',
      'selling_price': '40.00',
      if (warehouseId != null) 'warehouse_id': warehouseId,
      if (warehouse != null) 'warehouse': warehouse,
    };

void main() {
  group('warehouse travels with a Seller Hub product into the cart', () {
    test('parsed from the vendor payload (warehouse_id, or the nested warehouse object)', () {
      expect(MarketplaceProduct.fromJson(productJson()).warehouseId, 1);
      expect(MarketplaceProduct.fromJson(productJson(warehouseId: null, warehouse: {'id': 4, 'name': 'Salem'})).warehouseId, 4);
      expect(MarketplaceProduct.fromJson(productJson(warehouseId: null)).warehouseId, isNull);
      expect(MarketplaceProduct.fromJson(productJson(warehouseId: 'junk')).warehouseId, isNull);
    });

    test('kept on the cart item and after the cart is saved and restored', () {
      final item = CartItem(service: MarketplaceProduct.fromJson(productJson(warehouseId: 1)).toServiceItem(), quantity: 2);
      expect(item.service.warehouseId, 1);
      final restored = CartItem.fromStorageJson(jsonDecode(jsonEncode(item.toStorageJson())) as Map<String, dynamic>);
      expect(restored.service.warehouseId, 1);
      expect(restored.quantity, 2);
    });

    test('products without a warehouse (services, old saved carts) still load', () {
      final item = CartItem.fromStorageJson({'service': {'id': 1, 'title': 'AC', 'slug': 'ac', 'price': '100'}, 'quantity': 1});
      expect(item.service.warehouseId, isNull);
    });
  });

  group('delivery slots are requested for the cart warehouse', () {
    late _Adapter adapter;
    late ProviderContainer container;

    setUp(() {
      adapter = _Adapter();
      final dio = Dio(BaseOptions(baseUrl: 'https://example.test/api/'))..httpClientAdapter = adapter;
      container = ProviderContainer(overrides: [
        marketplaceCatalogRepositoryProvider.overrideWithValue(MarketplaceCatalogRepository(api: ApiClient.withDio(dio))),
      ]);
    });
    tearDown(() => container.dispose());

    test('the warehouse id is sent with the date', () async {
      final day = await container.read(marketplaceDeliverySlotsForDateProvider((date: '2026-10-31', warehouseId: 1)).future);
      expect(adapter.calls.single.queryParameters, {'warehouse_id': 1, 'date': '2026-10-31'});
      expect(day.slots, hasLength(1));
    });

    test('no warehouse means the server default (parameter omitted)', () async {
      await container.read(marketplaceDeliverySlotsForDateProvider((date: '2026-10-31', warehouseId: null)).future);
      expect(adapter.calls.single.queryParameters.containsKey('warehouse_id'), isFalse);
    });

    test('different warehouses are loaded separately', () async {
      await container.read(marketplaceDeliverySlotsForDateProvider((date: '2026-10-31', warehouseId: 1)).future);
      await container.read(marketplaceDeliverySlotsForDateProvider((date: '2026-10-31', warehouseId: 4)).future);
      expect(adapter.calls.map((c) => c.queryParameters['warehouse_id']), [1, 4]);
    });
  });
}
