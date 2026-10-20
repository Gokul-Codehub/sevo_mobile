import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../shared/theme/app_colors.dart';
import '../../../../shared/widgets/app_remote_image.dart';
import '../../../../shared/widgets/common_widgets.dart';
import '../../data/basket_models.dart';
import '../../data/marketplace_catalog_repository.dart';
import '../../../../core/navigation/safe_back.dart';

/// Lists Seller Hub combo/bundle offers ("Baskets") as a two-column grid.
///
/// Reached from Home's "Combo Offers" section ("See all") and directly via
/// [AppRoutes.baskets]. Each offer is a card: a dark green photo frame with the
/// saving, a rounded photo carousel (swipe through the photos of what is in the
/// combo), the title and price; tapping opens the combo to choose items.
class ComboOffersScreen extends ConsumerWidget {
  const ComboOffersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final basketsAsync = ref.watch(marketplaceBasketsProvider);

    return Scaffold(
      backgroundColor: const Color(0xFFF5F6F8),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0.5,
        leading: IconButton(
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
              final cellWidth = (constraints.maxWidth - pad * 2 - gap) / 2;
              // Fixed row height built from the card's parts (header + photo +
              // info panel) so it can never overflow.
              final cellHeight = cellWidth + 140;
              return GridView.builder(
                padding: const EdgeInsets.fromLTRB(pad, 12, pad, 110),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
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
        loading: () => GridView.builder(
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 110),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 0.62,
          ),
          itemCount: 6,
          itemBuilder: (_, __) => const ShimmerBox(borderRadius: 24),
        ),
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

  @override
  Widget build(BuildContext context) {
    final basket = widget.basket;
    final pct = basket.savingsPercentRounded;
    final photos = basket.galleryImages;
    final count = photos.isEmpty ? 1 : photos.length;
    final desc = basket.description.trim().isNotEmpty
        ? basket.description.trim()
        : (basket.isMultiOption ? 'Customizable combo \u2014 pick your favourites' : 'Fixed combo \u2014 everything you need in one pack');
    
    Widget chip(Widget child, {required Color bg}) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
          decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(9)),
          child: child,
        );

    return GestureDetector(
      onTap: () => context.push('/baskets/${basket.id}', extra: basket),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          boxShadow: const [
            BoxShadow(color: Color(0x240F172A), blurRadius: 16, offset: Offset(0, 6)),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── Photo with big rounded bottom corners ──
              ClipRRect(
                borderRadius: const BorderRadius.vertical(bottom: Radius.circular(26)),
                child: AspectRatio(
                  aspectRatio: 1.0,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      const ColoredBox(color: Colors.white),
                      // True-colour photo on a clean white stage.
                      photos.length < 2
                          ? _photo(photos.isEmpty ? basket.coverImage : photos.first, basket)
                          : PageView.builder(
                              controller: _pages,
                              itemCount: photos.length,
                              onPageChanged: (i) => setState(() => _page = i),
                              itemBuilder: (_, i) => _photo(photos[i], basket),
                            ),
                      Positioned(
                        top: 8,
                        left: 8,
                        right: 8,
                        child: Row(
                          children: [
                            chip(
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.verified_rounded, size: 12, color: Colors.white),
                                  const SizedBox(width: 3),
                                  Text(
                                    pct != null ? '$pct% off' : 'Combo',
                                    style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: Colors.white),
                                  ),
                                ],
                              ),
                              bg: const Color(0xFF0F5C31),
                            ),
                            const Spacer(),
                            chip(
                              Text(
                                '${basket.itemCount} item${basket.itemCount == 1 ? '' : 's'}',
                                style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: Color(0xFF14532D)),
                              ),
                              bg: Colors.white,
                            ),
                          ],
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
                                  width: d == _page ? 14 : 5,
                                  height: 5,
                                  margin: const EdgeInsets.symmetric(horizontal: 2),
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(3),
                                    color: d == _page ? const Color(0xFF0F5C31) : Colors.black26,
                                  ),
                                ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ),

              // ── Title + price, description, call to open ──
              Expanded(
                child: Container(
                  color: const Color(0xFFF5F6F8),
                  padding: const EdgeInsets.fromLTRB(11, 9, 11, 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              basket.title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 12.5,
                                height: 1.2,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFF0B0B0B),
                              ),
                            ),
                          ),
                          if (basket.bundlePrice != null) ...[
                            const SizedBox(width: 6),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  '\u20b9${basket.bundlePrice}',
                                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: Color(0xFF157038)),
                                ),
                                if (basket.hasSavings && basket.mrpTotal != null)
                                  Text(
                                    '\u20b9${basket.mrpTotal}',
                                    maxLines: 1,
                                    style: const TextStyle(fontSize: 9.5, color: AppColors.textHint, decoration: TextDecoration.lineThrough),
                                  ),
                              ],
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        desc,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 9.5, height: 1.3, color: AppColors.textSecondary),
                      ),
                      const Spacer(),
                      // Not an add-to-cart: the whole card opens the combo,
                      // where the customer chooses their products.
                      Container(
                        height: 32,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          gradient: const LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [Color(0xFF1E8A4C), Color(0xFF0B5A2C)],
                          ),
                        ),
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              'Choose items',
                              style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: Colors.white),
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
