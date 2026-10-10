import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../shared/theme/app_colors.dart';
import '../../../../shared/widgets/app_remote_image.dart';
import '../../data/basket_models.dart';
import '../../data/marketplace_catalog_repository.dart';

/// Lists Seller Hub combo/bundle offers ("Baskets").
///
/// Added 2026-10-08 ("the grocery developer has implemented another
/// feature something like Basket could you get into our app?") — a plain
/// grid over the already-live, already-sanitized `GET
/// /api/marketplace/baskets/` proxy. Reached from Home's "Combo Offers"
/// section ("See all") and directly via [AppRoutes.baskets].
class BasketListScreen extends ConsumerWidget {
  const BasketListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final basketsAsync = ref.watch(marketplaceBasketsProvider);

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: AppColors.navy),
          onPressed: () => context.pop(),
        ),
        title: const Text(
          'Combo Offers',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.navy),
        ),
      ),
      body: basketsAsync.when(
        data: (baskets) {
          if (baskets.isEmpty) {
            return const Center(
              child: Text(
                'No combo offers available right now',
                style: TextStyle(fontSize: 14, color: AppColors.textSecondary),
              ),
            );
          }
          return GridView.builder(
            padding: const EdgeInsets.all(12),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              childAspectRatio: 0.78,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
            ),
            itemCount: baskets.length,
            itemBuilder: (context, index) => _BasketCard(basket: baskets[index]),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => const Center(
          child: Text(
            "Couldn't load combo offers",
            style: TextStyle(fontSize: 14, color: AppColors.textSecondary),
          ),
        ),
      ),
    );
  }
}

class _BasketCard extends StatelessWidget {
  const _BasketCard({required this.basket});

  final MarketplaceBasket basket;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => context.push('/baskets/${basket.id}', extra: basket),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 1.2,
              child: Container(
                color: AppColors.surfaceVariant,
                child: AppRemoteImage(
                  imageUrl: basket.primaryImage,
                  rawPath: basket.primaryImage,
                  title: basket.title,
                  width: double.infinity,
                  height: double.infinity,
                  fit: BoxFit.cover,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    basket.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.navy),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${basket.itemCount} items',
                    style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      if (basket.bundlePrice != null)
                        Text(
                          '₹${basket.bundlePrice}',
                          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: AppColors.textPrimary),
                        ),
                      if (basket.hasSavings && basket.mrpTotal != null) ...[
                        const SizedBox(width: 6),
                        Text(
                          '₹${basket.mrpTotal}',
                          style: const TextStyle(
                            fontSize: 11,
                            color: AppColors.textHint,
                            decoration: TextDecoration.lineThrough,
                          ),
                        ),
                      ],
                    ],
                  ),
                  if (basket.hasSavings) ...[
                    const SizedBox(height: 2),
                    Text(
                      'Save ₹${basket.savings}',
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.groceryGreenDark),
                    ),
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
