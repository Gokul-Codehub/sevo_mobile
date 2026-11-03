import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/image_url_helper.dart';
import '../../../shared/theme/app_colors.dart';
import '../../../shared/widgets/app_remote_image.dart';
import '../../booking/domain/cart_notifier.dart';
import '../../booking/domain/marketplace_cart.dart';
import '../../catalog/data/marketplace_catalog_repository.dart';
import '../../catalog/domain/catalog_models.dart';
import '../data/grocery_orders_repository.dart';

const int _marketplaceCartIdOffset = 800000000;

/// The Seller Hub product ids this customer bought most recently (delivered orders, newest first), once each, leaving
/// out [inCart]. Combo lines are skipped: their slot choices cannot be repeated blindly.
List<int> buyAgainProductIds(List<GroceryOrder> orders, {Set<int> inCart = const {}, int limit = 12}) {
  final delivered = orders.where((o) => o.stage == OrderStage.delivered).toList()
    ..sort((a, b) => (b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0)).compareTo(a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0)));
  final ids = <int>[];
  for (final o in delivered) {
    for (final l in o.items) {
      final id = l.productId;
      if (l.basketId != null || id == null || inCart.contains(id) || ids.contains(id)) continue;
      ids.add(id);
      if (ids.length >= limit) return ids;
    }
  }
  return ids;
}

/// "Buy it again" for the grocery cart: things this customer already bought and is not buying now, at TODAY's price,
/// one tap to add. Nothing is shown for a first-time customer or when nothing is in stock.
class BuyItAgainStrip extends ConsumerWidget {
  const BuyItAgainStrip({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cart = ref.watch(cartProvider);
    final inCart = {for (final i in cart) if (marketplaceProductIdOf(i) != null) marketplaceProductIdOf(i)!};
    final orders = ref.watch(groceryOrdersProvider).valueOrNull ?? const <GroceryOrder>[];
    final ids = buyAgainProductIds(orders, inCart: inCart);
    if (ids.isEmpty) return const SizedBox.shrink();

    final live = ref.watch(marketplaceProductsByIdsProvider(ids.join(','))).valueOrNull ?? const [];
    final items = [
      for (final p in live)
        if (p.toServiceItem().inStock) p.toServiceItem(),
    ].where((s) => !inCart.contains(s.id - _marketplaceCartIdOffset)).take(10).toList();
    if (items.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(14, 0, 14, 10),
              child: Text('Buy it again', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.navy)),
            ),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var i = 0; i < items.length; i++) ...[
                    _AgainCard(item: items[i]),
                    if (i != items.length - 1) const SizedBox(width: 10),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AgainCard extends ConsumerWidget {
  const _AgainCard({required this.item});

  final ServiceItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    const slug = 'vegetables_groceries';
    return SizedBox(
      width: 104,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AspectRatio(
            aspectRatio: 1,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: AppRemoteImage(
                imageUrl: item.imageUrl,
                rawPath: item.imageUrl,
                title: item.title,
                categoryName: slug,
                slug: item.slug,
                semanticIcon: ImageUrlHelper.mapCategoryIcon(slug, slug),
                width: double.infinity,
                height: double.infinity,
                fit: BoxFit.cover,
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(item.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: AppColors.navy, height: 1.2)),
          const SizedBox(height: 2),
          Text('₹${item.effectivePrice}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
          const SizedBox(height: 4),
          OutlinedButton(
            onPressed: () => ref.read(cartProvider.notifier).addService(item),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.groceryGreen,
              side: const BorderSide(color: AppColors.groceryGreen),
              padding: EdgeInsets.zero,
              minimumSize: const Size(0, 30),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text('ADD', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );
  }
}
