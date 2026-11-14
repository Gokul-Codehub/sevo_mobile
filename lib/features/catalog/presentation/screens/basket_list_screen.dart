import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../shared/layout/responsive.dart';
import '../../../../shared/theme/app_colors.dart';
import '../../../../shared/widgets/app_remote_image.dart';
import '../../../../shared/widgets/common_widgets.dart';
import '../../../../shared/widgets/state_widgets.dart';
import '../../data/basket_models.dart';
import '../../data/marketplace_catalog_repository.dart';
import '../../../../core/navigation/safe_back.dart';

/// Lists Seller Hub combo/bundle offers ("Baskets") as a two-column grid.
///
/// Reached from Home's "Combo Offers" section ("See all") and directly via
/// [AppRoutes.baskets]. Each offer is a card: a dark green photo frame with the
/// saving, a rounded photo carousel (swipe through the photos of what is in the
/// combo), the title and price; tapping opens the combo to choose items.
class BasketListScreen extends ConsumerWidget {
  const BasketListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final basketsAsync = ref.watch(marketplaceBasketsProvider);

    return Scaffold(
      backgroundColor: const Color(0xFFE8F4EC),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0.5,
        leading: IconButton(
        tooltip: 'Back',
          icon: const Icon(Icons.arrow_back_rounded, color: AppColors.navy),
          onPressed: () => context.goBack(),
        ),
        title: const Text(
          'Combo Offers',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w800,
            color: AppColors.navy,
          ),
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
              final cols = AppResponsive.productColumns(constraints.maxWidth);
              final cellWidth =
                  (constraints.maxWidth - pad * 2 - gap * (cols - 1)) / cols;
              // Fixed row height built from the card's parts (header + photo +
              // info panel) so it can never overflow.
              final cellHeight = cellWidth + 140;
              return GridView.builder(
                padding: const EdgeInsets.fromLTRB(pad, 12, pad, 110),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: cols,
                  mainAxisExtent: cellHeight,
                  crossAxisSpacing: gap,
                  mainAxisSpacing: gap,
                ),
                itemCount: baskets.length,
                itemBuilder: (context, index) =>
                    _ComboCard(basket: baskets[index]),
              );
            },
          );
        },
        loading: () => const LoadingState(),
        error: (_, __) => const Center(
          child: Text(
            "Couldn't load combo offers",
            style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
          ),
        ),
      ),
    );
  }
}

class _ComboCard extends ConsumerStatefulWidget {
  const _ComboCard({required this.basket});

  final MarketplaceBasket basket;

  @override
  ConsumerState<_ComboCard> createState() => _ComboCardState();
}

class _ComboCardState extends ConsumerState<_ComboCard> {
  final _pages = PageController();
  int _page = 0;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  static const _sale = AppColors.swatchE11D48;
  static const _saleSoft = Color(0xFFFFE4E6);
  static const _price = AppColors.groceryGreen;

  @override
  Widget build(BuildContext context) {
    final basket = widget.basket;
    final pct = basket.savingsPercentRounded;
    final photos = basket.galleryImages;
    final count = photos.isEmpty ? 1 : photos.length;
    final desc = basket.description.trim().isNotEmpty
        ? basket.description.trim()
        : (basket.isMultiOption
            ? 'Customizable combo — pick your favourites'
            : 'Fixed combo — everything you need in one pack');

    return GestureDetector(
      onTap: () => context.push('/baskets/${basket.id}', extra: basket),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.swatchE8ECF1),
          boxShadow: [
            BoxShadow(
              color: AppColors.textPrimary.withValues(alpha: 0.08),
              blurRadius: 14,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AspectRatio(
                aspectRatio: 1.05,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    const ColoredBox(color: AppColors.background),
                    photos.length < 2
                        ? _photo(photos.isEmpty ? basket.coverImage : photos.first, basket)
                        : PageView.builder(
                            controller: _pages,
                            itemCount: photos.length,
                            onPageChanged: (i) => setState(() => _page = i),
                            itemBuilder: (_, i) => _photo(photos[i], basket),
                          ),
                    const Positioned(
                      top: 0,
                      left: 0,
                      right: 0,
                      height: 56,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [Color(0x66000000), Color(0x00000000)],
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      top: 8,
                      left: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFFF43F5E), AppColors.swatchE11D48],
                          ),
                          borderRadius: BorderRadius.circular(8),
                          boxShadow: [
                            BoxShadow(
                              color: _sale.withValues(alpha: 0.35),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.local_offer_rounded, size: 11, color: Colors.white),
                            const SizedBox(width: 3),
                            Text(
                              pct != null ? '$pct% OFF' : 'COMBO',
                              style: const TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w900,
                                color: Colors.white,
                                letterSpacing: 0.2,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    Positioned(
                      top: 8,
                      right: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.95),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: Text(
                          '${basket.itemCount} item${basket.itemCount == 1 ? '' : 's'}',
                          style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF334155),
                          ),
                        ),
                      ),
                    ),
                    if (count > 1)
                      Positioned(
                        bottom: 8,
                        left: 0,
                        right: 0,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            for (var d = 0; d < count && d < 6; d++)
                              Container(
                                width: d == _page ? 12 : 5,
                                height: 5,
                                margin: const EdgeInsets.symmetric(horizontal: 2),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(3),
                                  color: d == _page ? _sale : Colors.white70,
                                ),
                              ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(10, 9, 10, 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        basket.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12.5,
                          height: 1.25,
                          fontWeight: FontWeight.w800,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      if (basket.bundlePrice != null) ...[
                        const SizedBox(height: 5),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              '₹${basket.bundlePrice}',
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w900,
                                color: _price,
                                height: 1,
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
                                  height: 1.2,
                                ),
                              ),
                            ],
                            if (basket.hasSavings && basket.savings != null) ...[
                              const SizedBox(width: 6),
                              Flexible(
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: _saleSoft,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    'Save ₹${basket.savings}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 9.5,
                                      fontWeight: FontWeight.w800,
                                      color: _sale,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                      const SizedBox(height: 4),
                      Text(
                        desc,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 10,
                          height: 1.3,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      const Spacer(),
                      Container(
                        height: 34,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(17),
                          gradient: const LinearGradient(
                            colors: [Color(0xFF16A34A), AppColors.groceryGreen],
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: _price.withValues(alpha: 0.25),
                              blurRadius: 8,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              'Choose items',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                                color: Colors.white,
                              ),
                            ),
                            SizedBox(width: 4),
                            Icon(Icons.arrow_forward_rounded, size: 14, color: Colors.white),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _photo(String url, MarketplaceBasket basket) => Padding(
    padding: const EdgeInsets.all(4),
    child: AppRemoteImage(
      imageUrl: url,
      rawPath: url,
      title: basket.title,
      categoryName: 'grocery',
      slug: 'seller_hub_groceries',
      width: double.infinity,
      height: double.infinity,
      fit: BoxFit.contain,
    ),
  );
}
