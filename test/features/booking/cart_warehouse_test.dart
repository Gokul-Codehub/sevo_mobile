import 'package:calservices_customer/core/errors/api_error.dart';
import 'package:calservices_customer/core/network/api_client.dart';
import 'package:calservices_customer/features/booking/domain/booking_models.dart';
import 'package:calservices_customer/features/booking/domain/cart_notifier.dart';
import 'package:calservices_customer/features/booking/domain/cart_warehouse.dart';
import 'package:calservices_customer/features/catalog/data/marketplace_catalog_repository.dart';
import 'package:calservices_customer/features/catalog/domain/catalog_models.dart';
import 'package:decimal/decimal.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _FixedCart extends CartNotifier {
  _FixedCart(this.items);
  final List<CartItem> items;
  @override
  List<CartItem> build() => items;
}

class _Repo extends MarketplaceCatalogRepository {
  _Repo(this.warehouseByProduct) : super(api: ApiClient.withDio(Dio()));
  final Map<int, int?> warehouseByProduct;
  final List<int> asked = [];

  @override
  Future<Result<MarketplaceProduct>> getProductDetail(int id) async {
    asked.add(id);
    if (!warehouseByProduct.containsKey(id)) return const Failure(NetworkError());
    return Success(MarketplaceProduct(id: id, title: 'p$id', sellingPrice: Decimal.parse('10'), warehouseId: warehouseByProduct[id]));
  }
}

ServiceItem item(int id, {int? warehouseId}) =>
    ServiceItem(id: id, title: 'i$id', slug: 's$id', price: Decimal.parse('10'), warehouseId: warehouseId);

Future<int?> resolve(List<CartItem> lines, _Repo repo) async {
  final c = ProviderContainer(overrides: [
    cartProvider.overrideWith(() => _FixedCart(lines)),
    marketplaceCatalogRepositoryProvider.overrideWithValue(repo),
  ]);
  addTearDown(c.dispose);
  return c.read(cartWarehouseIdProvider.future);
}

void main() {
  test('a cart line that carries its warehouse is used without any lookup', () async {
    final repo = _Repo({});
    expect(await resolve([CartItem(service: item(800000079, warehouseId: 1))], repo), 1);
    expect(repo.asked, isEmpty);
  });

  test('a line saved earlier (no warehouse) is resolved from the product', () async {
    final repo = _Repo({79: 1});
    expect(await resolve([CartItem(service: item(800000079))], repo), 1);
    expect(repo.asked, [79]);
  });

  test('the first product that knows its warehouse wins; failed lookups are skipped', () async {
    final repo = _Repo({80: 4});
    expect(await resolve([CartItem(service: item(800000079)), CartItem(service: item(800000080))], repo), 4);
    expect(repo.asked, [79, 80]);
  });

  test('services and legacy ids are never looked up, and nothing resolved means the server default', () async {
    final repo = _Repo({});
    expect(await resolve([CartItem(service: item(12)), CartItem(service: item(900000005))], repo), isNull);
    expect(repo.asked, isEmpty);
  });

  test('lookup failure never throws: falls back to the server default', () async {
    final repo = _Repo({});
    expect(await resolve([CartItem(service: item(800000079))], repo), isNull);
  });
}
