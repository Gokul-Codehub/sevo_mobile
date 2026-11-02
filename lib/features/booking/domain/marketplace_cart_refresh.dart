import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/api_error.dart';
import '../../catalog/data/marketplace_catalog_repository.dart';
import '../../catalog/domain/catalog_models.dart';
import 'booking_models.dart';
import 'cart_notifier.dart';
import 'marketplace_cart.dart';

/// Server error codes meaning "what is in your cart no longer matches the shelf" (sold out, price changed, delisted).
const Set<String> kCartStaleCodes = {
  'INSUFFICIENT_STOCK',
  'PRICE_CHANGED',
  'PRODUCT_UNAVAILABLE',
  'ITEM_UNAVAILABLE',
  'CART_VALIDATION_FAILED',
};

bool isCartStaleError(Object? error) => error is ValidationError && kCartStaleCodes.contains((error.code ?? '').toUpperCase());

/// What a refreshed cart line becomes: the fresh product, or null to drop it (no longer sold / out of stock).
/// Pure, so the rule is testable: quantity never exceeds what is in stock now.
({ServiceItem service, int quantity})? refreshedLine(CartItem line, MarketplaceProduct? fresh) {
  if (fresh == null) return (service: line.service, quantity: line.quantity); // could not look it up: leave as is
  if (!fresh.inStock) return null;
  final service = fresh.toServiceItem();
  final cap = service.maxQuantity < 1 ? 1 : service.maxQuantity;
  return (service: service, quantity: line.quantity > cap ? cap : line.quantity);
}

/// Re-reads every single-product line of the cart from the Seller Hub (price, stock) and updates the cart to match.
/// Combo lines keep their bundle price. Returns how many lines changed or were removed.
Future<int> refreshMarketplaceCart(WidgetRef ref) async {
  final items = ref.read(cartProvider);
  final repo = ref.read(marketplaceCatalogRepositoryProvider);
  final singles = [for (final i in items) if (i.comboKey == null && marketplaceProductIdOf(i) != null) i];
  final fetched = await Future.wait([
    for (final i in singles) repo.getProductDetail(marketplaceProductIdOf(i)!),
  ]);
  var changed = 0;
  final notifier = ref.read(cartProvider.notifier);
  for (var n = 0; n < singles.length; n++) {
    final line = singles[n];
    final fresh = switch (fetched[n]) {
      Success<MarketplaceProduct>(:final data) => data,
      _ => null,
    };
    final next = refreshedLine(line, fresh);
    if (next == null) {
      notifier.removeService(line.service.id);
      changed++;
    } else if (next.service.price != line.service.price ||
        next.service.discountedPrice != line.service.discountedPrice ||
        next.quantity != line.quantity) {
      notifier.replaceLine(line.service.id, next.service, next.quantity);
      changed++;
    }
  }
  return changed;
}
