import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/api_error.dart';
import '../../catalog/data/marketplace_catalog_repository.dart';
import 'cart_notifier.dart';

/// Seller Hub product ids are offset by this much when used as cart ids (see MarketplaceProduct).
const int kMarketplaceCartIdOffset = 800000000;
const int _offsetEnd = 899999999;

/// The warehouse the grocery cart's products ship from - the one whose delivery slots to show,
/// exactly like the web cart (`cart.warehouse_groups[0].warehouse_id`).
///
/// 1. A cart line that already carries its warehouse (added since the app started recording it).
/// 2. Otherwise - lines saved earlier, or added through another path - ask the server which warehouse the
///    product ships from (`GET /marketplace/products/<id>/`).
/// 3. Otherwise null: the server then uses its configured default warehouse.
final cartWarehouseIdProvider = FutureProvider.autoDispose<int?>((ref) async {
  final items = ref.watch(cartProvider);

  for (final item in items) {
    final known = item.service.warehouseId;
    if (known != null) return known;
  }

  final repo = ref.watch(marketplaceCatalogRepositoryProvider);
  for (final item in items) {
    final id = item.service.id;
    if (id <= kMarketplaceCartIdOffset || id > _offsetEnd) continue;
    final result = await repo.getProductDetail(id - kMarketplaceCartIdOffset);
    if (result is Success<MarketplaceProduct>) {
      final w = result.data.warehouseId;
      if (w != null) return w;
    }
  }
  return null;
});
