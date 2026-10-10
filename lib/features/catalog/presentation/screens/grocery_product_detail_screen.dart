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
                child: _ProductGallery(
                  key: ValueKey('gallery-${product.id}'),
                  urls: galleryUrls,
                  product: product,
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

                  // Variant picker (e.g. 500g / 1kg / 5kg) — added 2026-10-08
                  // per explicit request ("for a particular product there
                  // are three variations ... could you get into our app").
                  // Each sibling is a REAL, separately priced/stocked
                  // product on the vendor (see MarketplaceProduct's doc
                  // comment on `variants`), only known once the background
                  // detail enrichment above resolves — same
                  // progressive-enhancement pattern as the description.
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

                  // Stock note
                  if (!product.inStock)
                    _InfoRow(icon: Icons.remove_shopping_cart_outlined, text: 'Currently out of stock', color: AppColors.error)
                  else if (product.maxQuantity > 0 && product.maxQuantity <= 5)
                    _InfoRow(icon: Icons.inventory_2_outlined, text: 'Only ${product.maxQuantity} left in stock', color: AppColors.warning),

                  // Choose unit — sibling units of the SAME product live
                  // here, above "About", and switch in place.
                  if (hasUnits) ...[
                    const SizedBox(height: 16),
                    _UnitSelector(
                      variants: enrichedProduct!.variants,
                      selectedId: selectedVariant?.id ?? enrichedProduct.id,
                      attributeName: enrichedProduct.variantAttributeName,
                      onSelect: (id) => setState(() => _selectedVariantId = id),
                    ),
                  ],

                  // Description — real admin/seller-entered copy only.
                  // Fixed 2026-10-08 ("align the details properly use bold
                  // for title and lite for details"): this combined block
                  // (real description + specs + storage + shelf life, see
                  // MarketplaceProduct._combinedDescription) is a flat list
                  // of lines where sellers consistently alternate a short
                  // label line ("Health Benefits", "Shelf Life", "Country
                  // of Origin"...) with its value line(s) right after —
                  // rendering it as one plain Text lost that structure
                  // entirely. _ProductAboutSection below recognizes the
                  // known label lines and bolds them, keeping everything
                  // else as regular/lighter body text.
                  if ((effectiveDescription ?? '').trim().isNotEmpty) ...[
                    const SizedBox(height: 16),
                    const Text('About this product', style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
                    const SizedBox(height: 8),
                    _ProductAboutSection(text: effectiveDescription!.trim()),
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
          _buildCartBar(context, ref, product, quantityInCart),
        ],
      ),
    );
  }

  Widget _buildCartBar(BuildContext context, WidgetRef ref, ServiceItem product, int quantityInCart) {
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

  bool _isLabelLine(String line) {
    final normalized = line.trim().toLowerCase().replaceAll(RegExp(r':$'), '').trim();
    return _knownLabels.contains(normalized);
  }

  @override
  Widget build(BuildContext context) {
    final lines = text.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).toList();

    final children = <Widget>[];
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      final isLabel = _isLabelLine(line);
      children.add(
        Padding(
          padding: EdgeInsets.only(top: isLabel && i > 0 ? 10 : 2),
          child: Text(
            line,
            style: isLabel
                ? const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800, color: AppColors.textPrimary)
                : const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w400, color: AppColors.textSecondary, height: 1.45),
          ),
        ),
      );
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: children);
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
    final heading = (attributeName ?? '').isNotEmpty ? 'Choose ${attributeName!.toLowerCase()}' : 'Choose unit';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(heading, style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
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
                    color: selected ? AppColors.groceryGreen.withValues(alpha: 0.08) : Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: selected ? AppColors.groceryGreen : const Color(0xFFE2E8F0),
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
                          fontSize: 13,
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
                            Text('\u20b9${v.sellingPrice}', style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
                            if (v.hasStrikeThroughMrp) ...[
                              const SizedBox(width: 5),
                              Text(
                                '\u20b9${v.mrp}',
                                style: const TextStyle(fontSize: 11, color: AppColors.textHint, decoration: TextDecoration.lineThrough),
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

  @override
  void dispose() {
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
      fit: BoxFit.contain,
    );
  }

  @override
  Widget build(BuildContext context) {
    final urls = widget.urls;
    if (urls.length <= 1) return _image(urls.isEmpty ? null : urls.first);
    return Stack(
      fit: StackFit.expand,
      children: [
        PageView.builder(
          controller: _controller,
          itemCount: urls.length,
          onPageChanged: (i) => setState(() => _page = i),
          itemBuilder: (_, i) => _image(urls[i]),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 10,
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
                  color: active ? AppColors.groceryGreen : Colors.black26,
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
