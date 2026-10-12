import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../shared/theme/app_colors.dart';
import '../../../../shared/widgets/app_remote_image.dart';
import '../../../../shared/widgets/common_widgets.dart';
import '../../data/basket_models.dart';
import '../../data/marketplace_catalog_repository.dart';

/// Lists Seller Hub combo/bundle offers ("Baskets").
///
/// Reached from Home's "Combo Offers" section ("See all") and directly via
/// [AppRoutes.baskets]. Each card shows a photo of one of the products inside
/// the combo (the combo itself usually has no photo of its own), a SAVE chip,
/// the bundle price and what it saves.
class BasketListScreen extends ConsumerWidget {
  const BasketListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final basketsAsync = ref.watch(marketplaceBasketsProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0.5,
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
            return const EmptyStateWidget(
              title: 'No combo offers right now',
              subtitle: 'New combos land here as soon as they are published.',
              emoji: '🎁',
            );
          }
          return LayoutBuilder(
            builder: (context, constraints) {
              const pad = 12.0;
              const gap = 10.0;
              final cellWidth = (constraints.maxWidth - pad * 2 - gap) / 2;
              // Fixed row height (photo + the text block) instead of a guessed
              // aspect ratio, so the card can never overflow ("BOTTOM
              // OVERFLOWED BY 22 PIXELS").
              final cellHeight = cellWidth / 1.2 + 132;
              return GridView.builder(
                padding: const EdgeInsets.all(pad),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  mainAxisExtent: cellHeight,
                  crossAxisSpacing: gap,
                  mainAxisSpacing: gap,
                ),
                itemCount: baskets.length,
                itemBuilder: (context, index) => _BasketCard(basket: baskets[index]),
              );
            },
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
    final pct = basket.savingsPercentRounded;
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => context.push('/baskets/${basket.id}', extra: basket),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border),
          boxShadow: const [
            BoxShadow(color: Color(0x0A0F172A), blurRadius: 8, offset: Offset(0, 2)),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 1.2,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Container(
                    color: const Color(0xFFF6F8FB),
                    padding: const EdgeInsets.all(10),
                    child: AppRemoteImage(
                      imageUrl: basket.coverImage,
                      rawPath: basket.coverImage,
                      title: basket.title,
                      categoryName: 'grocery',
                      slug: 'seller_hub_groceries',
                      width: double.infinity,
                      height: double.infinity,
                      fit: BoxFit.contain,
                    ),
                  ),
                  if (pct != null)
                    Positioned(
                      left: 8,
                      top: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFBBF24),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          'SAVE $pct%',
                          style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w900,
                            color: Color(0xFF1F2937),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      basket.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        height: 1.25,
                        fontWeight: FontWeight.w800,
                        color: AppColors.navy,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${basket.itemCount} item${basket.itemCount == 1 ? '' : 's'}'
                      '${basket.isMultiOption ? ' · customizable' : ''}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
                    ),
                    const Spacer(),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        if (basket.bundlePrice != null)
                          Text(
                            '₹${basket.bundlePrice}',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w900,
                              color: AppColors.textPrimary,
                            ),
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
                    if (basket.hasSavings)
                      Text(
                        'You save ₹${basket.savings}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: AppColors.groceryGreenDark,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
