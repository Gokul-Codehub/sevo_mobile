import 'dart:async';

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
import '../../data/marketplace_catalog_repository.dart';
import '../../data/recipe_models.dart';
import '../../domain/catalog_models.dart';
import '../../domain/catalog_providers.dart';
import '../widgets/product_card.dart';
import '../../../../core/navigation/safe_back.dart';

// Product page palette (matches the redesigned cart / bookings / services).
const Color _gpHero = Color(0xFFF4F6F4);
const Color _gpCream = Color(0xFFF4F6F4);
const Color _gpGrey = Color(0xFF6B7788);
const Color _gpGreen = Color(0xFF157038); // matches the category page Add button
// Offer colors — same golden yellow / amber orange the home page uses.
const Color _gpOfferYellow = Color(0xFFF9C93A);
const Color _gpOfferOrange = Color(0xFFF59E0B);
const Color _gpOfferDeep = Color(0xFFD97706);
const Color _gpGreenDark =Color(0xFF10612F); // matches the Go to Cart pill

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

class _GroceryProductDetailBody extends ConsumerStatefulWidget {
  const _GroceryProductDetailBody({required this.product});

  final ServiceItem product;

  @override
  ConsumerState<_GroceryProductDetailBody> createState() => _GroceryProductDetailBodyState();
}

class _GroceryProductDetailBodyState extends ConsumerState<_GroceryProductDetailBody> {
  /// Which unit/variant of this product is currently shown. Null means the
  /// product the customer opened. Switching units only swaps what this page
  /// renders (price, image, stock, description, cart line) — no navigation.
  int? _selectedVariantId;

  /// Builds the cart/display [ServiceItem] for a sibling unit, borrowing the
  /// category context the (sparser) sibling payload doesn't carry.
  ServiceItem _variantItem(MarketplaceProduct v, ServiceItem base) {
    final s = v.toServiceItem();
    return ServiceItem(
      id: s.id,
      title: s.title,
      slug: s.slug,
      price: s.price,
      discountedPrice: s.discountedPrice,
      unit: s.unit,
      description: s.description,
      rating: base.rating,
      reviewCount: base.reviewCount,
      categoryId: base.categoryId,
      categoryName: base.categoryName ?? s.categoryName,
      categorySlug: s.categorySlug,
      imageUrl: s.imageUrl ?? base.imageUrl,
      inStock: s.inStock,
      maxQuantity: s.maxQuantity,
    );
  }

  @override
  Widget build(BuildContext context) {
    final base = widget.product;

    // Seller Hub detail (variants, full gallery, specs) loads in the
    // background; the page paints instantly from the list data in [base].
    final sellerHubId = base.slug.startsWith('seller-hub-')
        ? int.tryParse(base.slug.substring('seller-hub-'.length))
        : null;
    final enrichedProduct = sellerHubId != null
        ? ref.watch(marketplaceProductDetailProvider(sellerHubId)).valueOrNull
        : null;
    final hasUnits = enrichedProduct != null && enrichedProduct.hasSelectableVariants;
    MarketplaceProduct? selectedVariant;
    if (hasUnits) {
      final wanted = _selectedVariantId ?? enrichedProduct!.id;
      selectedVariant = enrichedProduct!.variants.where((v) => v.id == wanted).firstOrNull;
    }
    final switched = selectedVariant != null && selectedVariant.id != enrichedProduct!.id;
    final ServiceItem product = switched ? _variantItem(selectedVariant!, base) : base;
    final MarketplaceProduct? activeSource = switched ? selectedVariant : enrichedProduct;
    var galleryUrls = activeSource?.galleryImages ?? const <String>[];
    if (galleryUrls.isEmpty && (product.imageUrl ?? '').isNotEmpty) galleryUrls = [product.imageUrl!];

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

    // Fixed 2026-10-08 ("the description and all other details of the
    // product has not been shown" — compared against sevo.co.in's own
    // "About this item" card for the same Seller Hub Marketplace product):
    // `initialProduct` only ever carries LIST-endpoint data (see this
    // screen's own doc comment on why there's no separate detail fetch by
    // default) — and the vendor's list endpoint doesn't include the
    // seller's free-form `specs` rows (Health Benefits, Disclaimer,
    // Customer Care Details, Country of Origin, etc.), only the single
    // `GET /marketplace/products/<id>/` detail call does. This fetches
    // that detail in the background — same progressive-enhancement
    // pattern as the "Similar Products" strip below — and swaps in its
    // richer combined description once it arrives, without blocking the
    // instant paint from initialProduct.
    final effectiveDescription = activeSource?.toServiceItem().description ??
        enrichedProduct?.toServiceItem().description ??
        product.description ??
        product.shortDescription;

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
    final cartCount = cartItems.fold<int>(0, (sum, i) => sum + i.quantity);
    final showTag = product.hasDiscount && product.discountPercent != null;
    final categoryLabel = (product.categoryName ?? '').trim();

    // Stat strip cells — only real fields the backend actually sent.
    final statCells = <({String value, String label})>[
      if (product.displayUnit.isNotEmpty) (value: product.displayUnit, label: 'Pack'),
      if (showTag) (value: '${product.discountPercent}%', label: 'Discount'),
      (value: product.inStock ? 'In stock' : 'Sold out', label: 'Availability'),
    ];

    return Container(
      color: Colors.white,
      child: Column(
        children: [
          Expanded(
            child: CustomScrollView(
              slivers: [
                SliverAppBar(
                  expandedHeight: 360,
                  pinned: true,
                  elevation: 0,
                  scrolledUnderElevation: 0,
                  backgroundColor: _gpHero,
                  surfaceTintColor: Colors.transparent,
                  automaticallyImplyLeading: false,
                  leadingWidth: 64,
                  leading: Padding(
                    padding: const EdgeInsets.only(left: 16),
                    child: Center(
                      child: _RoundIconButton(
                        icon: Icons.arrow_back_rounded,
                        tooltip: 'Back',
                        onTap: () => context.goBack(),
                      ),
                    ),
                  ),
                  // The rounded white sheet that rises over the photo.
                  bottom: PreferredSize(
                    preferredSize: const Size.fromHeight(24),
                    child: Container(
                      height: 24,
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
                      ),
                    ),
                  ),
                  flexibleSpace: FlexibleSpaceBar(
                    background: Container(
                      color: _gpHero,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          Padding(
                            // Photo runs behind the sheet's rounded corners, so the
                            // corners show the photo (not a grey gap).
                            padding: EdgeInsets.zero,
                            child: _ProductGallery(
                              key: ValueKey('gallery-${product.id}'),
                              urls: galleryUrls,
                              product: product,
                            ),
                          ),
                          if (showTag)
                            Positioned(
                              left: 0,
                              bottom: 28,
                              child: _DiscountTag(percent: product.discountPercent!),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: Container(
                    color: Colors.white,
                    padding: const EdgeInsets.fromLTRB(20, 6, 20, 0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Title + rating
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Text(
                                product.title,
                                style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w800,
                                  color: AppColors.textPrimary,
                                  height: 1.25,
                                ),
                              ),
                            ),
                            if (product.rating > 0) ...[
                              const SizedBox(width: 12),
                              _RatingBadge(rating: product.rating, reviewCount: product.reviewCount),
                            ],
                          ],
                        ),
                        if (product.displayUnit.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            product.displayUnit,
                            style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary, fontWeight: FontWeight.w600),
                          ),
                        ],
                        if (categoryLabel.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  categoryLabel,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 12.5, color: _gpGrey, fontWeight: FontWeight.w600),
                                ),
                              ),
                            ],
                          ),
                        ],
                        const SizedBox(height: 14),

                        // Price
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.baseline,
                          textBaseline: TextBaseline.alphabetic,
                          children: [
                            Text(
                              '₹${product.effectivePrice}',
                              style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: _gpGreen),
                            ),
                            if (product.hasDiscount) ...[
                              const SizedBox(width: 10),
                              Text(
                                'MRP ₹${product.price}',
                                style: const TextStyle(
                                  fontSize: 13,
                                  color: AppColors.textHint,
                                  decoration: TextDecoration.lineThrough,
                                ),
                              ),
                            ],
                          ],
                        ),
                        if (showTag) ...[
                          const SizedBox(height: 3),
                          Text(
                            '${product.discountPercent}% OFF on MRP',
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: _gpOfferDeep),
                          ),
                        ],
                        const SizedBox(height: 3),
                        const Text(
                          'Inclusive of all taxes',
                          style: TextStyle(fontSize: 11.5, color: AppColors.textHint),
                        ),
                        const SizedBox(height: 16),

                        _StatStrip(cells: statCells),

                        // Stock note
                        if (!product.inStock) ...[
                          const SizedBox(height: 12),
                          _InfoRow(icon: Icons.remove_shopping_cart_outlined, text: 'Currently out of stock', color: AppColors.error),
                        ] else if (product.maxQuantity > 0 && product.maxQuantity <= 5) ...[
                          const SizedBox(height: 12),
                          _InfoRow(icon: Icons.inventory_2_outlined, text: 'Only ${product.maxQuantity} left in stock', color: AppColors.warning),
                        ],

                        // Choose unit — sibling units of the SAME product live
                        // here, above the description, and switch in place.
                        if (hasUnits) ...[
                          const SizedBox(height: 18),
                          _UnitSelector(
                            variants: enrichedProduct!.variants,
                            selectedId: selectedVariant?.id ?? enrichedProduct.id,
                            attributeName: enrichedProduct.variantAttributeName,
                            onSelect: (id) => setState(() => _selectedVariantId = id),
                          ),
                        ],

                        // Description — real admin/seller-entered copy only.
                        if ((effectiveDescription ?? '').trim().isNotEmpty) ...[
                          const SizedBox(height: 22),
                          _ProductAboutSection(text: effectiveDescription!.trim()),
                        ],

                        // Recipes & Meal Ideas — only when the seller enabled it
                        // for this product and recipes actually exist.
                        if (enrichedProduct != null && enrichedProduct.showRecipes && enrichedProduct.recipes.isNotEmpty) ...[
                          const SizedBox(height: 26),
                          _RecipesRail(productTitle: product.title, recipes: enrichedProduct.recipes),
                        ],

                        if (relatedAsync != null) ...[
                          const SizedBox(height: 26),
                          const Text(
                            'Similar Products',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.textPrimary),
                          ),
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
          _buildCartBar(context, ref, product, quantityInCart, cartCount),
        ],
      ),
    );
  }

  Widget _buildCartBar(BuildContext context, WidgetRef ref, ServiceItem product, int quantityInCart, int cartCount) {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [BoxShadow(color: const Color(0xFF14532D).withValues(alpha: 0.07), blurRadius: 16, offset: const Offset(0, -4))],
        ),
        child: _BottomActions(product: product, quantityInCart: quantityInCart, cartCount: cartCount),
      ),
    );
  }
}

/// Renders the combined "About this product" text (real description +
/// specs + storage + shelf life — see [MarketplaceProduct._combinedDescription])
/// with seller-entered label lines (e.g. "Health Benefits", "Shelf Life",
/// "Country of Origin") shown bold, and their value line(s) right after
/// shown in a lighter/regular weight — added 2026-10-08 per feedback that
/// the flat text lost that label/value structure entirely.
class _ProductAboutSection extends StatelessWidget {
  const _ProductAboutSection({required this.text});

  final String text;

  static const Set<String> _knownLabels = {
    'health benefits',
    'description',
    'unit',
    'shelf life',
    'disclaimer',
    'customer care details',
    'country of origin',
    'storage',
    'storage temperature',
  };

  static bool _isLabelLine(String line) {
    final normalized = line.trim().toLowerCase().replaceAll(RegExp(r':$'), '').trim();
    return _knownLabels.contains(normalized);
  }

  /// "Wheat-Semolina Vermicelli: The most common type..." — a bold lead-in
  /// followed by its explanation.
  static final RegExp _leadIn = RegExp(r'^([A-Za-z][A-Za-z0-9 &/\-]{2,40}):\s+(.+)$');
  static final RegExp _bullet = RegExp(r'^[-\u2022*]\s+(.+)$');

  /// A short line with no full stop or colon ("Types of Vermicelli") reads as
  /// a sub-heading.
  static bool _isSubheading(String line) =>
      line.length <= 40 &&
      !line.endsWith('.') &&
      !line.contains(':') &&
      line.split(' ').length <= 6;

  static const _body = TextStyle(
    fontSize: 12.5,
    fontWeight: FontWeight.w400,
    color: AppColors.textSecondary,
    height: 1.5,
  );
  static const _strong = TextStyle(
    fontSize: 12.5,
    fontWeight: FontWeight.w700,
    color: AppColors.textPrimary,
    height: 1.5,
  );

  Widget _dot(Widget child) => Padding(
        padding: const EdgeInsets.only(top: 3, bottom: 3, left: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.only(top: 8, right: 9),
              child: Icon(Icons.circle, size: 5, color: _gpGreen),
            ),
            Expanded(child: child),
          ],
        ),
      );

  /// One line of prose: bullet, "Lead-in: text", sub-heading or paragraph.
  Widget _line(String line, {bool lead = false}) {
    final b = _bullet.firstMatch(line);
    if (b != null) return _dot(Text(b.group(1)!, style: _body));

    final m = _leadIn.firstMatch(line);
    if (m != null) {
      return _dot(
        Text.rich(
          TextSpan(children: [
            TextSpan(text: '${m.group(1)}: ', style: _strong),
            TextSpan(text: m.group(2), style: _body),
          ]),
        ),
      );
    }
    if (!lead && _isSubheading(line)) {
      return Padding(
        padding: const EdgeInsets.only(top: 10, bottom: 2),
        child: Text(line, style: _strong),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Text(line, style: lead ? _strong : _body),
    );
  }

  @override
  Widget build(BuildContext context) {
    final lines = text.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).toList();

    // Lines before the first known label are free-form description;
    // everything after a label line belongs to that label.
    final intro = <String>[];
    final sections = <({String label, List<String> body})>[];
    for (final line in lines) {
      if (_isLabelLine(line)) {
        sections.add((label: line.replaceAll(RegExp(r':$'), '').trim(), body: <String>[]));
      } else if (sections.isEmpty) {
        intro.add(line);
      } else {
        sections.last.body.add(line);
      }
    }

    final children = <Widget>[
      for (var i = 0; i < intro.length; i++) _line(intro[i], lead: i == 0 && intro.length > 1),
    ];

    for (final s in sections) {
      if (s.body.isEmpty) continue;
      if (children.isNotEmpty) children.add(const SizedBox(height: 10));
      final shortValue = s.body.length == 1 && s.body.first.length <= 36;
      if (shortValue) {
        // "Unit | 1 kg", "Shelf Life | 3 days" — compact two-column row.
        children.add(
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(width: 118, child: Text(s.label, style: _strong)),
                Expanded(child: Text(s.body.first, style: _body)),
              ],
            ),
          ),
        );
      } else {
        children.add(Text(s.label, style: _strong));
        children.add(const SizedBox(height: 2));
        for (final l in s.body) {
          children.add(_line(l));
        }
      }
    }

    return SizedBox(
      width: double.infinity,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'About this item',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.textPrimary),
          ),
          const SizedBox(height: 10),
          ...children,
        ],
      ),
    );
  }
}

/// "Choose unit" section: every real unit/size of this product (e.g. 500g,
/// 1kg, 5kg) as a selectable card with its own price. Selecting one swaps
/// the page content in place (see [_GroceryProductDetailBodyState]).
class _UnitSelector extends StatelessWidget {
  const _UnitSelector({
    required this.variants,
    required this.selectedId,
    required this.attributeName,
    required this.onSelect,
  });

  final List<MarketplaceProduct> variants;
  final int selectedId;
  final String? attributeName;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: BoxDecoration(
        color: _gpCream,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'SELECT PACK ${(attributeName ?? '').isNotEmpty ? attributeName!.toUpperCase() : 'SIZE'} / VARIANT',
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.6,
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 74,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: variants.length,
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (context, i) {
              final v = variants[i];
              final selected = v.id == selectedId;
              final out = !v.inStock;
              final label = (v.variantLabel?.isNotEmpty ?? false) ? v.variantLabel! : (v.unit ?? v.title);
              return GestureDetector(
                onTap: out ? null : () => onSelect(v.id),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  constraints: const BoxConstraints(minWidth: 96),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: selected ? _gpGreen.withValues(alpha: 0.08) : Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: selected ? _gpGreen : const Color(0xFFE3E8F0),
                      width: selected ? 1.6 : 1.1,
                    ),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: out ? AppColors.textHint : AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 3),
                      if (out)
                        const Text('Out of stock', style: TextStyle(fontSize: 11, color: AppColors.error, fontWeight: FontWeight.w700))
                      else
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text('\u20b9${v.sellingPrice}', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
                            if (v.hasStrikeThroughMrp) ...[
                              const SizedBox(width: 5),
                              Text(
                                '\u20b9${v.mrp}',
                                style: TextStyle(fontSize: 11, color: AppColors.textHint, decoration: TextDecoration.lineThrough),
                              ),
                            ],
                          ],
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
      ),
    );
  }
}

/// Swipeable product photo carousel with page dots. Falls back to a single
/// image when the vendor sent only one.
class _ProductGallery extends StatefulWidget {
  const _ProductGallery({super.key, required this.urls, required this.product});

  final List<String> urls;
  final ServiceItem product;

  @override
  State<_ProductGallery> createState() => _ProductGalleryState();
}

class _ProductGalleryState extends State<_ProductGallery> {
  final PageController _controller = PageController();
  int _page = 0;
  Timer? _timer;

  /// Photos advance on their own every few seconds; a touch restarts the
  /// countdown so a customer swiping isn't fought by the timer.
  static const _interval = Duration(seconds: 4);

  void _startAutoSlide() {
    _timer?.cancel();
    if (widget.urls.length <= 1) return;
    _timer = Timer.periodic(_interval, (_) {
      if (!mounted || !_controller.hasClients) return;
      final next = (_page + 1) % widget.urls.length;
      _controller.animateToPage(
        next,
        duration: const Duration(milliseconds: 450),
        curve: Curves.easeInOut,
      );
    });
  }

  @override
  void initState() {
    super.initState();
    _startAutoSlide();
  }

  @override
  void didUpdateWidget(covariant _ProductGallery oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.urls.length != widget.urls.length) {
      if (_page >= widget.urls.length) _page = 0;
      _startAutoSlide();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  Widget _image(String? url) {
    final p = widget.product;
    return AppRemoteImage(
      imageUrl: url,
      rawPath: url,
      title: p.title,
      categoryName: p.categoryName,
      slug: p.slug,
      semanticIcon: ImageUrlHelper.mapCategoryIcon(p.categoryName, p.slug),
      width: double.infinity,
      height: double.infinity,
      fit: BoxFit.cover,
    );
  }

  @override
  Widget build(BuildContext context) {
    final urls = widget.urls;
    if (urls.length <= 1) return _image(urls.isEmpty ? null : urls.first);
    return Stack(
      fit: StackFit.expand,
      children: [
        Listener(
          onPointerDown: (_) => _startAutoSlide(),
          child: PageView.builder(
            controller: _controller,
            itemCount: urls.length,
            onPageChanged: (i) => setState(() => _page = i),
            itemBuilder: (_, i) => _image(urls[i]),
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 34,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(urls.length, (i) {
              final active = i == _page;
              return AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                margin: const EdgeInsets.symmetric(horizontal: 3),
                width: active ? 18 : 6,
                height: 6,
                decoration: BoxDecoration(
                  color: active ? _gpGreen : Colors.black26,
                  borderRadius: BorderRadius.circular(3),
                ),
              );
            }),
          ),
        ),
      ],
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
          Text(text, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: color)),
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

/// Floating white circle button used over the hero photo (back / cart) and in
/// the bottom bar. [badge] > 0 shows a small count bubble.
class _RoundIconButton extends StatelessWidget {
  const _RoundIconButton({
    required this.icon,
    required this.onTap,
    this.tooltip,
    this.badge = 0,
    this.size = 42,
    this.bordered = false,
  });

  final IconData icon;
  final VoidCallback onTap;
  final String? tooltip;
  final int badge;
  final double size;
  final bool bordered;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: tooltip,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: SizedBox(
          width: size,
          height: size,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                width: size,
                height: size,
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  border: bordered ? Border.all(color: const Color(0xFFE3E8F0), width: 1.2) : null,
                  boxShadow: bordered
                      ? null
                      : [BoxShadow(color: Colors.black.withValues(alpha: 0.10), blurRadius: 10, offset: const Offset(0, 3))],
                ),
                child: Icon(icon, size: size * 0.5, color: _gpGreen),
              ),
              if (badge > 0)
                Positioned(
                  top: -2,
                  right: -2,
                  child: Container(
                    constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: _gpGreen,
                      borderRadius: BorderRadius.circular(9),
                      border: Border.all(color: Colors.white, width: 1.5),
                    ),
                    child: Text(
                      badge > 99 ? '99+' : '$badge',
                      style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: Colors.white),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// "20% OFF" ribbon that sits on the photo's lower-left edge, just above the
/// white sheet.
class _DiscountTag extends StatelessWidget {
  const _DiscountTag({required this.percent});

  final Object percent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 8, 22, 8),
      decoration: const BoxDecoration(
        // Home page's golden yellow → amber orange.
        gradient: LinearGradient(colors: [_gpOfferYellow, _gpOfferOrange]),
        borderRadius: BorderRadius.only(topRight: Radius.circular(22), bottomRight: Radius.circular(22)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 24,
            height: 24,
            decoration: const BoxDecoration(color: Color(0xFF1F2937), shape: BoxShape.circle),
            child: const Icon(Icons.percent_rounded, size: 14, color: _gpOfferYellow),
          ),
          const SizedBox(width: 8),
          Text(
            '$percent% OFF',
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: Color(0xFF1F2937)),
          ),
        ],
      ),
    );
  }
}

/// "★ 4.8 (120)" — top-right of the title row.
class _RatingBadge extends StatelessWidget {
  const _RatingBadge({required this.rating, required this.reviewCount});

  final double rating;
  final int reviewCount;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(color: _gpGreen, borderRadius: BorderRadius.circular(6)),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  rating.toStringAsFixed(1),
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Colors.white),
                ),
                const SizedBox(width: 2),
                const Icon(Icons.star_rounded, size: 13, color: Colors.white),
              ],
            ),
          ),
          if (reviewCount > 0) ...[
            const SizedBox(height: 3),
            Text('$reviewCount ratings', style: const TextStyle(fontSize: 11.5, color: AppColors.textSecondary)),
          ],
        ],
      ),
    );
  }
}

/// Soft rounded stat strip (value over label, thin dividers between cells).
class _StatStrip extends StatelessWidget {
  const _StatStrip({required this.cells});

  final List<({String value, String label})> cells;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(color: _gpCream, borderRadius: BorderRadius.circular(16)),
      child: Row(
        children: [
          for (var i = 0; i < cells.length; i++) ...[
            if (i > 0) Container(width: 1, height: 30, color: const Color(0xFFE3E8F0)),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      cells[i].value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: _gpGreen),
                    ),
                    const SizedBox(height: 3),
                    Text(cells[i].label, style: const TextStyle(fontSize: 11.5, color: _gpGrey)),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Bottom action bar — cart shortcut + Add to Cart, or (once in the cart) a
/// quantity stepper + Go to Cart. Same cartProvider calls as before.
class _BottomActions extends ConsumerWidget {
  const _BottomActions({required this.product, required this.quantityInCart, required this.cartCount});

  final ServiceItem product;
  final int quantityInCart;
  final int cartCount;

  static const double _h = 54;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!product.inStock) {
      return Container(
        height: _h,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: const Color(0xFFEDF0F5), borderRadius: BorderRadius.circular(_h / 2)),
        child: const Text(
          'Out of Stock',
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.textHint),
        ),
      );
    }

    final ctaShape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(_h / 2));

    if (quantityInCart == 0) {
      return Row(
        children: [
          _RoundIconButton(
            icon: Icons.shopping_bag_outlined,
            tooltip: 'Cart',
            badge: cartCount,
            size: _h,
            bordered: true,
            onTap: () => context.push('/cart'),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: FilledButton(
              onPressed: () {
                ref.read(cartProvider.notifier).addService(product);
                AppToast.addedToCart(context, product.title);
              },
              style: FilledButton.styleFrom(
                backgroundColor: _gpGreen,
                foregroundColor: Colors.white,
                minimumSize: const Size(0, _h),
                shape: ctaShape,
              ),
              child: Text(
                'Add to Cart  •  ₹${product.effectivePrice}',
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
              ),
            ),
          ),
        ],
      );
    }

    final atMax = quantityInCart >= product.maxQuantity;
    return Row(
      children: [
        Container(
          height: _h,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(color: const Color(0xFFE6F2EA), borderRadius: BorderRadius.circular(_h / 2)),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _StepButton(
                icon: Icons.remove_rounded,
                filled: false,
                onTap: () => ref.read(cartProvider.notifier).updateQuantity(product.id, quantityInCart - 1),
              ),
              SizedBox(
                width: 36,
                child: Text(
                  '$quantityInCart',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: _gpGreen),
                ),
              ),
              _StepButton(
                icon: Icons.add_rounded,
                filled: true,
                dimmed: atMax,
                onTap: atMax
                    ? () => AppToast.show(context, 'Only ${product.maxQuantity} in stock', type: AppToastType.error)
                    : () {
                        ref.read(cartProvider.notifier).updateQuantity(product.id, quantityInCart + 1);
                        AppToast.addedToCart(context, product.title);
                      },
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: FilledButton.icon(
            onPressed: () => context.go('/cart'),
            icon: const Icon(Icons.shopping_bag_outlined, size: 20),
            label: const Text('Go to Cart', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
            style: FilledButton.styleFrom(
              backgroundColor: _gpGreen,
              foregroundColor: Colors.white,
              minimumSize: const Size(0, _h),
              shape: ctaShape,
            ),
          ),
        ),
      ],
    );
  }
}

class _StepButton extends StatelessWidget {
  const _StepButton({required this.icon, required this.filled, required this.onTap, this.dimmed = false});

  final IconData icon;
  final bool filled;
  final bool dimmed;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: filled ? (dimmed ? _gpGreen.withValues(alpha: 0.4) : _gpGreen) : Colors.white,
          shape: BoxShape.circle,
        ),
        child: Icon(icon, size: 20, color: filled ? Colors.white : _gpGreen),
      ),
    );
  }
}

/// "Recipes & Meal Ideas" strip on a product page: curated recipes that use
/// this product. Tapping one opens the recipe page, where every ingredient
/// can be added to the cart.
class _RecipesRail extends StatelessWidget {
  const _RecipesRail({required this.productTitle, required this.recipes});

  final String productTitle;
  final List<RecipeSummary> recipes;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.restaurant_menu_rounded, size: 19, color: _gpGreen),
            const SizedBox(width: 8),
            const Expanded(
              child: Text(
                'Recipes & Meal Ideas',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.textPrimary),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
              decoration: BoxDecoration(color: const Color(0xFFF1F5F9), borderRadius: BorderRadius.circular(20)),
              child: Text(
                '${recipes.length} ${recipes.length == 1 ? 'recipe' : 'recipes'}',
                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: _gpGrey),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          'Cook something delicious with fresh $productTitle',
          style: const TextStyle(fontSize: 12.5, color: _gpGrey, height: 1.35),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 218,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            clipBehavior: Clip.none,
            itemCount: recipes.length,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (context, i) => _RecipeCard(recipe: recipes[i]),
          ),
        ),
      ],
    );
  }
}

class _RecipeCard extends StatelessWidget {
  const _RecipeCard({required this.recipe});

  final RecipeSummary recipe;

  @override
  Widget build(BuildContext context) {
    final dietColor = switch (recipe.diet) {
      RecipeDiet.veg => const Color(0xFF059669),
      RecipeDiet.nonVeg => const Color(0xFFE11D48),
      RecipeDiet.egg => const Color(0xFFB45309),
    };
    return GestureDetector(
      onTap: () => context.push('/recipes/${Uri.encodeComponent(recipe.key)}'),
      child: Container(
        width: 168,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFFE2E8F0)),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8, offset: const Offset(0, 3))],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              height: 112,
              width: double.infinity,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ColoredBox(
                    color: const Color(0xFFF1F5F9),
                    child: AppRemoteImage(imageUrl: recipe.coverImage, title: recipe.title, fit: BoxFit.cover),
                  ),
                  Positioned(
                    top: 8,
                    left: 8,
                    child: Container(
                      width: 20,
                      height: 20,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: dietColor, width: 1.4),
                      ),
                      child: Center(
                        child: Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(color: dietColor, shape: BoxShape.circle),
                        ),
                      ),
                    ),
                  ),
                  if (recipe.cookTimeMinutes > 0)
                    Positioned(
                      right: 8,
                      bottom: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.6),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.schedule_rounded, size: 11, color: Colors.white),
                            const SizedBox(width: 3),
                            Text(
                              '${recipe.cookTimeMinutes} mins',
                              style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: Colors.white),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 9, 10, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      recipe.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, height: 1.25, color: AppColors.textPrimary),
                    ),
                    const SizedBox(height: 3),
                    if (recipe.kcal > 0)
                      Text(
                        '${recipe.kcal} kcal',
                        style: const TextStyle(fontSize: 11, color: _gpGrey, fontWeight: FontWeight.w600),
                      ),
                    const Spacer(),
                    const Row(
                      children: [
                        Text('View Recipe', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: _gpGreen)),
                        SizedBox(width: 2),
                        Icon(Icons.chevron_right_rounded, size: 16, color: _gpGreen),
                      ],
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
