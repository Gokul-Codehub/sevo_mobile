import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/utils/app_logger.dart';
import '../../../../core/utils/image_url_helper.dart';
import '../../../../shared/theme/app_colors.dart';
import '../../../../shared/utils/app_toast.dart';
import '../../../../shared/widgets/app_remote_image.dart';
import '../../../../shared/widgets/common_widgets.dart';
import '../../../booking/domain/cart_notifier.dart';
import '../../domain/catalog_models.dart';
import '../../domain/catalog_providers.dart';
import '../widgets/product_card.dart';

/// Dedicated product page for groceries, vegetables and fruits —
/// deliberately SEPARATE from [ServiceDetailScreen].
///
/// Added 2026-09-28 per explicit correction: the first pass routed grocery
/// items into [ServiceDetailScreen], which is right for a scheduled service
/// (AC repair, electrician...) but wrong for a packaged product — that
/// screen shows "What's Included" / "How It Works" / "Tools & Products We
/// Use" sections that make no sense for a bag of atta or a kilo of tomatoes.
/// This screen instead follows the quick-commerce product-page convention
/// (Blinkit/Zepto/Amazon-style) the user pointed to: image, rating, title,
/// weight/unit, price with MRP + discount, a category info row, and a
/// "Similar Products" strip below — no service-only sections at all.
///
/// Only ever renders fields the backend actually sent — no fabricated
/// attribute chips (shelf life, milling process, etc.) that this app's data
/// model has no real source for.
class GroceryProductDetailScreen extends ConsumerWidget {
  const GroceryProductDetailScreen({
    super.key,
    required this.productSlug,
    this.initialProduct,
  });

  final String productSlug;
  final ServiceItem? initialProduct;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Every grocery/vegetable/fruit product this app shows anywhere is
    // already fully loaded client-side (Vegetable Inventory, Grocery Hub
    // bestsellers, and Seller Hub Marketplace items are all fetched as full
    // lists, never lazily by slug) — the `extra: service` navigation always
    // carries the real object, so there is no separate detail fetch here,
    // matching how ServiceDetailScreen already treats `initialService` as
    // authoritative once present.
    final product = initialProduct;
    if (product == null) {
      // Fixed 2026-09-28: this used to be a bare `Center(child: Text(...))`
      // with no diagnostic — visually indistinguishable from a genuinely
      // blank/broken page, which is exactly what was reported ("returns
      // empty screen"). Logged so a live repro's debug console can confirm
      // whether THIS is actually the path being hit (extra never arrived —
      // a routing/navigation defect) as opposed to
      // [_GroceryProductDetailBody] rendering with real but incomplete data
      // (see that widget's own incomplete-data guard below).
      AppLogger.d('[GROCERY-DETAIL]', 'initialProduct was NULL for slug=$productSlug — extra was not a ServiceItem');
      // Deliberately NOT a Scaffold — see _GroceryProductDetailBody's build()
      // for the full explanation: this screen sits inside AppShell's own
      // Scaffold via the ShellRoute, and a second nested Scaffold here is
      // the confirmed "RenderBox was not laid out" / FAB-slot crash already
      // fixed the same way on CategoryDetailScreen.
      return Container(
        color: Colors.white,
        child: Column(
          children: [
            AppBar(backgroundColor: Colors.white, foregroundColor: AppColors.textPrimary, elevation: 0.5),
            Expanded(
              child: Center(
                child: EmptyStateWidget(
                  title: 'Product Not Found',
                  subtitle: 'This product could not be loaded. Please go back and try again.',
                  emoji: '❓',
                ),
              ),
            ),
          ],
        ),
      );
    }
    return _GroceryProductDetailBody(product: product);
  }
}

class _GroceryProductDetailBody extends ConsumerWidget {
  const _GroceryProductDetailBody({required this.product});

  final ServiceItem product;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Added 2026-09-28 — temporary diagnostic for a reported "product page
    // shows empty" bug that couldn't be reproduced from code review alone.
    // Debug-only (AppLogger.d is a no-op in release builds): logs exactly
    // which fields this specific product actually arrived with, so the
    // console output from a live repro pinpoints what's null/empty instead
    // of guessing again.
    AppLogger.d('[GROCERY-DETAIL]',
        'id=${product.id} title="${product.title}" slug=${product.slug} '
        'imageUrl=${product.imageUrl} price=${product.price} '
        'discountedPrice=${product.discountedPrice} rating=${product.rating} '
        'categoryId=${product.categoryId} categorySlug=${product.categorySlug} '
        'categoryName=${product.categoryName} inStock=${product.inStock} '
        'maxQuantity=${product.maxQuantity} '
        'descLen=${(product.description ?? '').length} '
        'shortDescLen=${(product.shortDescription ?? '').length}');

    // Fixed 2026-09-28: a product screenshotted mid-bug-report showed a
    // struck-through price and an "Out of Stock" pill but nothing else —
    // proof `initialProduct` WAS non-null (price/stock rendered fine) and
    // the real cause is upstream data missing its title, i.e. a genuinely
    // incomplete catalog record (seed/import data, or one still pending
    // admin completion), not a routing or navigation defect. Rendering the
    // normal layout with an empty title, no image and no description reads
    // exactly like "the page is empty" even though it isn't literally
    // blank. Catching that here and showing one clear, honest state is
    // better than a page that quietly renders almost nothing.
    if (product.title.trim().isEmpty) {
      AppLogger.d('[GROCERY-DETAIL]', 'product id=${product.id} has a blank title — showing incomplete-data state');
      // Deliberately NOT a Scaffold — see the comment on the main return
      // below for why.
      return Container(
        color: Colors.white,
        child: Column(
          children: [
            AppBar(backgroundColor: Colors.white, foregroundColor: AppColors.textPrimary, elevation: 0.5),
            Expanded(
              child: Center(
                child: EmptyStateWidget(
                  title: 'Product Details Unavailable',
                  subtitle: 'This product is missing details right now. Please check back soon.',
                  emoji: '📦',
                ),
              ),
            ),
          ],
        ),
      );
    }

    final cartItems = ref.watch(cartProvider);
    final inCartItem = cartItems.where((i) => i.service.id == product.id).firstOrNull;
    final quantityInCart = inCartItem?.quantity ?? 0;

    // Best-effort "Similar Products" — same catalog-category lookup
    // ServiceDetailScreen already uses. Some grocery sources (Seller Hub
    // Marketplace, Grocery Hub bestsellers) have a categoryId outside this
    // catalog's own id space, so this can legitimately come back empty —
    // the section just doesn't render rather than showing wrong items.
    final rawRelatedAsync = product.categoryId != null
        ? ref.watch(categoryServicesProvider(CategoryServicesParam(
            categoryId: product.categoryId,
            categorySlug: product.categorySlug ?? '',
          )))
        : null;

    // Fixed 2026-09-28 per explicit report ("not all other products/
    // vegetable been shown" — Fenugreek Leaves showing an unrelated
    // packaged item and a melon as "Similar Products"): `categoryId` here
    // is the broad admin Category (the whole "Groceries" bucket this
    // Package sits under), not the specific Vegetable Inventory department
    // (e.g. "Fresh Vegetables") this produce item actually belongs to.
    // Fetching by categoryId alone returns every item in that broad
    // bucket, which is exactly the two visually unrelated products that
    // showed up. When this product carries a real vegetable category,
    // narrow the fetched list down to that same DEPARTMENT (not the exact
    // same leaf category — [vegetableCategorySlug] is this specific
    // product's own narrow leaf node, e.g. "Fenugreek Leaves" itself, so
    // matching it exactly returned nothing else at all, which is why the
    // whole section vanished the first time this was fixed). Matching by
    // [ServiceItem.vegetableDepartmentName] — the same department-level
    // grouping [groupServiceItemsByDepartment] already uses for the
    // Vegetable Inventory browse rail — correctly surfaces other leafy
    // greens instead. Otherwise (Seller Hub Marketplace / Grocery Hub
    // items, which have no vegetable category concept) keep the broader
    // category match as before.
    final relatedAsync = rawRelatedAsync?.whenData((items) {
      final wantedDept = product.vegetableDepartmentName?.trim().toLowerCase();
      if (wantedDept == null || wantedDept.isEmpty) return items;
      return items.where((i) => (i.vegetableDepartmentName?.trim().toLowerCase() ?? '') == wantedDept).toList();
    });

    // Deliberately NOT a Scaffold. Fixed 2026-09-28 — the confirmed root
    // cause of the reported crash log ("RenderBox was not laid out:
    // RenderDecoratedBox... Failed assertion: line 2251 pos 12: 'hasSize'"):
    // this screen sits inside AppShell's own Scaffold via the ShellRoute
    // (every screen under the ShellRoute does), and it was ALSO building a
    // second, nested Scaffold of its own here — two Scaffolds means two
    // competing FAB-slot RenderObjects in the same tree, which is the exact
    // "RenderBox was not laid out" / "Cannot hit test a render box that has
    // never been laid out" race already diagnosed and fixed on
    // CategoryDetailScreen (see that screen's matching doc comment) and
    // applied to SellerHubGroceriesScreen — just never applied here until
    // now. The failed layout throws mid-build, which is exactly why the
    // page LOOKED empty even when real product data (price, stock status)
    // had already rendered — the crash took down the rest of the subtree
    // after those first widgets painted. SliverAppBar only needs a
    // Navigator (for the back button), not a Scaffold, so it still works
    // exactly the same inside a plain CustomScrollView.
    return Container(
      color: Colors.white,
      child: Column(
        children: [
          Expanded(
            child: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 280,
            pinned: true,
            backgroundColor: Colors.white,
            elevation: 0,
            leading: IconButton(
              icon: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.4), shape: BoxShape.circle),
                child: const Icon(Icons.arrow_back_rounded, color: Colors.white, size: 20),
              ),
              onPressed: () => context.pop(),
            ),
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                color: AppColors.surfaceVariant,
                child: AppRemoteImage(
                  imageUrl: product.imageUrl,
                  rawPath: product.imageUrl,
                  title: product.title,
                  categoryName: product.categoryName,
                  slug: product.slug,
                  semanticIcon: ImageUrlHelper.mapCategoryIcon(product.categoryName, product.slug),
                  width: double.infinity,
                  height: double.infinity,
                  fit: BoxFit.contain,
                ),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Rating
                  if (product.rating > 0)
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: AppColors.groceryGreen,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                product.rating.toStringAsFixed(1),
                                style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: Colors.white),
                              ),
                              const SizedBox(width: 2),
                              const Icon(Icons.star_rounded, size: 13, color: Colors.white),
                            ],
                          ),
                        ),
                        if (product.reviewCount > 0) ...[
                          const SizedBox(width: 8),
                          Text(
                            '${product.reviewCount} ratings',
                            style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
                          ),
                        ],
                      ],
                    ),
                  if (product.rating > 0) const SizedBox(height: 8),

                  // Title
                  Text(
                    product.title,
                    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: AppColors.textPrimary, height: 1.3),
                  ),
                  if (product.displayUnit.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      product.displayUnit,
                      style: const TextStyle(fontSize: 13, color: AppColors.textSecondary, fontWeight: FontWeight.w600),
                    ),
                  ],
                  const SizedBox(height: 12),

                  // Price
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text(
                        '₹${product.effectivePrice}',
                        style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: AppColors.textPrimary),
                      ),
                      if (product.hasDiscount) ...[
                        const SizedBox(width: 8),
                        Text(
                          'MRP ₹${product.price}',
                          style: const TextStyle(fontSize: 13, color: AppColors.textHint, decoration: TextDecoration.lineThrough),
                        ),
                      ],
                    ],
                  ),
                  if (product.hasDiscount && product.discountPercent != null) ...[
                    const SizedBox(height: 3),
                    Text(
                      '${product.discountPercent}% OFF on MRP',
                      style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: AppColors.groceryGreenDark),
                    ),
                  ],
                  const SizedBox(height: 3),
                  const Text(
                    'Inclusive of all taxes',
                    style: TextStyle(fontSize: 11.5, color: AppColors.textHint),
                  ),
                  const SizedBox(height: 16),

                  // Category info row (in place of a brand row this app has
                  // no real brand field for)
                  if ((product.categoryName ?? '').isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                      decoration: BoxDecoration(
                        border: Border.all(color: AppColors.border, width: 0.8),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              color: AppColors.groceryGreenLight,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Icon(Icons.storefront_rounded, size: 18, color: AppColors.groceryGreenDark),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  product.categoryName!,
                                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                                ),
                                const Text(
                                  'From this category',
                                  style: TextStyle(fontSize: 11.5, color: AppColors.textSecondary),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 12),

                  // Stock note
                  if (!product.inStock)
                    _InfoRow(icon: Icons.remove_shopping_cart_outlined, text: 'Currently out of stock', color: AppColors.error)
                  else if (product.maxQuantity > 0 && product.maxQuantity <= 5)
                    _InfoRow(icon: Icons.inventory_2_outlined, text: 'Only ${product.maxQuantity} left in stock', color: AppColors.warning),

                  // Description — real admin-entered copy only.
                  if ((product.description ?? product.shortDescription)?.trim().isNotEmpty ?? false) ...[
                    const SizedBox(height: 16),
                    const Text('About this product', style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
                    const SizedBox(height: 6),
                    Text(
                      (product.description ?? product.shortDescription ?? '').trim(),
                      style: const TextStyle(fontSize: 13.5, color: AppColors.textSecondary, height: 1.45),
                    ),
                  ],

                  if (relatedAsync != null) ...[
                    const SizedBox(height: 22),
                    const Divider(height: 1),
                    const SizedBox(height: 16),
                    const Text('Similar Products', style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
                    const SizedBox(height: 12),
                    _SimilarProductsGrid(relatedAsync: relatedAsync, currentId: product.id),
                  ],
                  const SizedBox(height: 90),
                ],
              ),
            ),
          ),
        ],
            ),
          ),
          _buildCartBar(context, ref, quantityInCart),
        ],
      ),
    );
  }

  Widget _buildCartBar(BuildContext context, WidgetRef ref, int quantityInCart) {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 10, offset: const Offset(0, -2))],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '₹${product.effectivePrice}',
                        style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: AppColors.textPrimary),
                      ),
                      if (product.displayUnit.isNotEmpty)
                        Text(product.displayUnit, style: const TextStyle(fontSize: 11.5, color: AppColors.textSecondary)),
                    ],
                  ),
                ),
                // Fixed 2026-09-28 per reported crash log (creator chain
                // "ConstrainedBox ← _InputPadding ← ... ← FilledButton ←
                // _CartAction ← Row", constraints "BoxConstraints(unconstrained)",
                // additionalConstraints "w=Infinity"): _CartAction's "Add to
                // Cart" state renders a FilledButton, which internally builds a
                // _RenderInputPadding to enforce its minimum tap-target size —
                // that widget's constraint math produces an invalid
                // tight-infinite width whenever it's handed unbounded width,
                // which is exactly what a Row always gives a non-flex child.
                // Same exact bug already diagnosed and fixed the same way on
                // CategoryDetailScreen's cart bar (see that screen's matching
                // doc comment) — IntrinsicWidth measures the child's natural
                // width first and lays it out with that concrete, finite
                // number, so the button never sees an unbounded constraint.
                IntrinsicWidth(
                  child: _CartAction(product: product, quantityInCart: quantityInCart),
                ),
              ],
            ),
            // Added 2026-10-06 per explicit request ("i have added a
            // product then it should show the 'Go to cart' to redirect")
            // — reuses the exact same green pill "Go to Cart" affordance
            // already used on CategoryDetailScreen/SellerHubGroceries-
            // Screen/SellerHubVegetablesScreen's cart bars, wrapped in
            // IntrinsicWidth for the same unbounded-width reason as above.
            // Only shown once this product is actually in the cart.
            if (quantityInCart > 0) ...[
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => context.go('/cart'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF059669),
                    side: const BorderSide(color: Color(0xFF059669)),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                  ),
                  icon: const Icon(Icons.shopping_cart_checkout, size: 16),
                  label: const Text('Go to Cart', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.icon, required this.text, required this.color});

  final IconData icon;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        children: [
          Icon(icon, size: 15, color: color),
          const SizedBox(width: 6),
          Text(text, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: color)),
        ],
      ),
    );
  }
}

class _SimilarProductsGrid extends StatelessWidget {
  const _SimilarProductsGrid({required this.relatedAsync, required this.currentId});

  final AsyncValue<List<ServiceItem>> relatedAsync;
  final int currentId;

  @override
  Widget build(BuildContext context) {
    return relatedAsync.when(
      loading: () => const SizedBox(
        height: 220,
        child: Row(children: [Expanded(child: ShimmerCard(height: 220)), SizedBox(width: 12), Expanded(child: ShimmerCard(height: 220))]),
      ),
      error: (_, __) => const SizedBox.shrink(),
      data: (items) {
        final others = items.where((i) => i.id != currentId).toList();
        if (others.isEmpty) return const SizedBox.shrink();

        // Fixed 2026-09-28 per reported "BOTTOM OVERFLOWED BY N PIXELS"
        // error: this used to be a GridView with a fixed childAspectRatio,
        // which forces every cell to the same height regardless of
        // ProductCard's own real (variable) content height — ProductCard is
        // deliberately built with no forced height of its own (see its doc
        // comment), so a fixed-ratio cell that's shorter than a given
        // card's actual content overflows. Same class of bug already fixed
        // the same way on CategoryDetailScreen's and SellerHubGroceries-
        // Screen's grocery grids: plain Rows let each row's height adapt to
        // its tallest card instead of forcing one.
        final rows = <Widget>[];
        for (var i = 0; i < others.length; i += 2) {
          final hasSecond = i + 1 < others.length;
          rows.add(
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: ProductCard(service: others[i])),
                  const SizedBox(width: 12),
                  Expanded(
                    child: hasSecond ? ProductCard(service: others[i + 1]) : const SizedBox.shrink(),
                  ),
                ],
              ),
            ),
          );
        }
        return Column(children: rows);
      },
    );
  }
}

/// Full-size ADD / quantity-stepper control for the sticky bottom bar —
/// mirrors ProductCard._buildGroceryAction's logic (same cartProvider calls)
/// at a larger touch target appropriate for a primary page action.
class _CartAction extends ConsumerWidget {
  const _CartAction({required this.product, required this.quantityInCart});

  final ServiceItem product;
  final int quantityInCart;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!product.inStock) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        decoration: BoxDecoration(color: AppColors.surfaceVariant, borderRadius: BorderRadius.circular(8)),
        child: const Text('Out of Stock', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textHint)),
      );
    }

    if (quantityInCart == 0) {
      return FilledButton(
        onPressed: () {
          ref.read(cartProvider.notifier).addService(product);
          AppToast.addedToCart(context, product.title);
        },
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.groceryGreen,
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        child: const Text('Add to Cart', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
      );
    }

    final atMax = quantityInCart >= product.maxQuantity;
    return Container(
      decoration: BoxDecoration(color: AppColors.groceryGreen, borderRadius: BorderRadius.circular(8)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            onPressed: () => ref.read(cartProvider.notifier).updateQuantity(product.id, quantityInCart - 1),
            icon: const Icon(Icons.remove, color: Colors.white, size: 18),
          ),
          Text('$quantityInCart', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 15)),
          IconButton(
            onPressed: atMax
                ? () => AppToast.show(context, 'Only ${product.maxQuantity} in stock', type: AppToastType.error)
                : () {
                    ref.read(cartProvider.notifier).updateQuantity(product.id, quantityInCart + 1);
                    AppToast.addedToCart(context, product.title);
                  },
            icon: Icon(Icons.add, color: atMax ? Colors.white54 : Colors.white, size: 18),
          ),
        ],
      ),
    );
  }
}
