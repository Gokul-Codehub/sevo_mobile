import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../shared/theme/app_colors.dart';
import '../../../../shared/utils/app_toast.dart';
import '../../../../shared/widgets/app_remote_image.dart';
import '../../../../shared/widgets/common_widgets.dart';
import '../../../booking/domain/cart_notifier.dart';
import '../../data/basket_cart.dart';
import '../../data/basket_models.dart';
import '../../data/marketplace_catalog_repository.dart';

/// Lists Seller Hub combo/bundle offers ("Baskets") as a two-column grid.
///
/// Reached from Home's "Combo Offers" section ("See all") and directly via
/// [AppRoutes.baskets]. Each offer is a card: a lime-green header with the
/// saving, a rounded photo carousel (swipe through the photos of what is in the
/// combo, "1 / 3"), a tag, the title, a dashed rule, and the price above a black
/// "Add to cart" button.
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
          style: TextStyle(
            fontSize: 16,
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
              final photoHeight = (cellWidth - 14) / 1.25;
              final cellHeight = 34 + photoHeight + 8 + 150;
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

  /// Puts the combo's default picks (and its fixed items) in the cart.
  void _addToCart() {
    final basket = widget.basket;
    final added = addComboToCart(
      ref.read(cartProvider.notifier),
      basket,
      (slot) => slot.defaultOption,
    );
    if (!mounted) return;
    if (added > 0) {
      AppToast.addedToCart(context, basket.title);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("This combo's items aren't available right now"),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final basket = widget.basket;
    final pct = basket.savingsPercentRounded;
    final photos = basket.galleryImages;
    final count = photos.isEmpty ? 1 : photos.length;
    // Fresh lime-green band from the reference card (bright at the top, softer below).
    const tintGradient = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [Color(0xFFB2F596), Color(0xFFD8FCCA)],
    );

    return GestureDetector(
      onTap: () => context.push('/baskets/${basket.id}', extra: basket),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          boxShadow: const [
            BoxShadow(
              color: Color(0x1A0F172A),
              blurRadius: 16,
              offset: Offset(0, 6),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── Lime header + photo carousel ──
              Container(
                decoration: const BoxDecoration(gradient: tintGradient),
                padding: const EdgeInsets.fromLTRB(7, 7, 7, 0),
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(3, 0, 3, 6),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.verified_rounded,
                            size: 14,
                            color: AppColors.navy,
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              pct != null ? '$pct% off' : 'Combo',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                                color: AppColors.navy,
                              ),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.navy,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              '${basket.itemCount} item${basket.itemCount == 1 ? '' : 's'}',
                              style: const TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    ClipRRect(
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(16),
                      ),
                      child: AspectRatio(
                        aspectRatio: 1.25,
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            Container(
                              color: const Color(0xFFF6F8FB),
                              child: photos.length < 2
                                  ? _photo(
                                      photos.isEmpty
                                          ? basket.coverImage
                                          : photos.first,
                                      basket,
                                    )
                                  : PageView.builder(
                                      controller: _pages,
                                      itemCount: photos.length,
                                      onPageChanged: (i) =>
                                          setState(() => _page = i),
                                      itemBuilder: (_, i) =>
                                          _photo(photos[i], basket),
                                    ),
                            ),
                            if (count > 1)
                              Positioned(
                                top: 6,
                                right: 7,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.black.withValues(alpha: 0.55),
                                    borderRadius: BorderRadius.circular(9),
                                  ),
                                  child: Text.rich(
                                    TextSpan(
                                      children: [
                                        TextSpan(
                                          text: '${_page + 1}',
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                        TextSpan(text: ' / $count'),
                                      ],
                                    ),
                                    style: const TextStyle(
                                      fontSize: 10,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // ── White info panel ──
              Expanded(
                child: Container(
                  color: Colors.white,
                  padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.groceryGreenLight,
                          borderRadius: BorderRadius.circular(7),
                          border: Border.all(color: AppColors.groceryGreenTint),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              basket.isMultiOption
                                  ? Icons.tune_rounded
                                  : Icons.eco_rounded,
                              size: 11,
                              color: AppColors.groceryGreenDark,
                            ),
                            const SizedBox(width: 4),
                            Flexible(
                              child: Text(
                                basket.isMultiOption
                                    ? 'Customizable'
                                    : 'Fixed combo',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.navy,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        basket.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13.5,
                          height: 1.2,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF0B0B0B),
                        ),
                      ),
                      const Spacer(),
                      const _DashedRule(),
                      const SizedBox(height: 6),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          if (basket.bundlePrice != null)
                            Flexible(
                              flex: 3,
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  '₹${basket.bundlePrice}',
                                  style: const TextStyle(
                                    fontSize: 17,
                                    fontWeight: FontWeight.w800,
                                    color: Color(0xFF0B0B0B),
                                  ),
                                ),
                              ),
                            ),
                          if (basket.hasSavings && basket.mrpTotal != null) ...[
                            const SizedBox(width: 5),
                            Flexible(
                              child: Text(
                                '₹${basket.mrpTotal}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: AppColors.textHint,
                                  decoration: TextDecoration.lineThrough,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 6),
                      Material(
                        color: const Color(0xFF0B0B0B),
                        borderRadius: BorderRadius.circular(20),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(20),
                          onTap: _addToCart,
                          child: const SizedBox(
                            height: 32,
                            width: double.infinity,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.shopping_cart_outlined,
                                  size: 15,
                                  color: Colors.white,
                                ),
                                SizedBox(width: 5),
                                Flexible(
                                  child: FittedBox(
                                    fit: BoxFit.scaleDown,
                                    child: Text(
                                      'Add to cart',
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
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
    padding: const EdgeInsets.all(6),
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

/// A thin dashed horizontal rule.
class _DashedRule extends StatelessWidget {
  const _DashedRule();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        const dash = 4.0, gap = 3.0;
        final n = (c.maxWidth / (dash + gap)).floor();
        return Row(
          children: List.generate(
            n,
            (_) => const Padding(
              padding: EdgeInsets.only(right: gap),
              child: SizedBox(
                width: dash,
                height: 1,
                child: ColoredBox(color: Color(0xFFD9DEE5)),
              ),
            ),
          ),
        );
      },
    );
  }
}
