import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../shared/theme/app_colors.dart';
import '../../../../shared/widgets/app_remote_image.dart';
import '../../../../shared/widgets/common_widgets.dart';
import '../../../../shared/navigation/admin_link_resolver.dart';
import '../../../catalog/domain/catalog_models.dart';
import '../../../catalog/presentation/widgets/product_card.dart';
import '../../../catalog/data/marketplace_catalog_repository.dart';
import '../../data/homepage_repository.dart';
import '../../domain/grocery_section_layout.dart';

/// Grocery Home Section Builder — Layout Resolver.
///
/// Added 2026-10-05, extended the same day to all 12 layouts the spec
/// defines. Replaces the old `_CuratedGrocerySectionCarousel` (which only
/// ever knew "horizontal" vs "grid"): this widget is the single place that
/// decides which concrete layout widget renders a given admin section, so a
/// future layout means adding one `case` in [_ProductDrivenSection] or
/// [_CategoryDiscoverySection] below — never growing a single giant
/// widget's conditional branches.
///
/// Every layout falls into exactly one of two data sources, decided once
/// here by [GrocerySectionLayoutX.isCategoryDiscovery]:
///   - PRODUCT-DRIVEN (9 layouts): the section's picked category ids select
///     real Seller Hub Marketplace *products* (merged/deduped across every
///     picked id, same as before). Handled by [_ProductDrivenSection].
///   - CATEGORY-DISCOVERY (2 layouts: Category Tile Grid, Circular Category
///     Rail): the section's picked category ids ARE the things shown — real
///     Seller Hub *departments* (name, admin-uploaded image, real product
///     count), not their products. Handled by [_CategoryDiscoverySection].
/// Both paths share the same admin-configured `title`/`category_ids`/
/// `maxProducts` fields on [MobileGrocerySection] — a category id just means
/// something different depending which data source its layout reads from.
class GrocerySectionResolver extends ConsumerWidget {
  const GrocerySectionResolver({super.key, required this.section});

  final MobileGrocerySection section;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (section.layout.isCategoryDiscovery) {
      return _CategoryDiscoverySection(section: section);
    }
    return _ProductDrivenSection(section: section);
  }
}

/// Fetching, merge/dedupe across the section's picked category ids, and the
/// loading/error/empty rules are all shared across every product-driven
/// layout, done once here — no layout duplicates this.
class _ProductDrivenSection extends ConsumerWidget {
  const _ProductDrivenSection({required this.section});

  final MobileGrocerySection section;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Added 2026-10-05 (Phase B, layout-aware config): "Specific Products"
    // source mode resolves an admin-curated, order-preserving id list
    // instead of merging by category — see MobileGrocerySection.productIds'
    // doc comment. Every section saved before this field existed has an
    // empty productIds and falls straight through to the original
    // category-merge path, unchanged.
    final productsAsync = section.usesSpecificProducts
        ? ref.watch(marketplaceProductsByIdsProvider(section.productIds.join(',')))
        : ref.watch(marketplaceMergedProductsProvider(([...section.categoryIds]..sort()).join(',')));

    return productsAsync.when(
      loading: () => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionTitle(section.title),
          const SizedBox(height: 12),
          const SizedBox(height: 308, child: _HorizontalShimmerRow(height: 308)),
        ],
      ),
      // Catalog API failed for this section — never crash, never show fake
      // data, just hide this one section. The rest of Home keeps working.
      error: (err, st) => const SizedBox.shrink(),
      data: (products) {
        if (products.isEmpty) return const SizedBox.shrink();
        // Performance rule: never render more than the admin's configured
        // cap, however many products the merge turned up.
        final capped = products.length > section.maxProducts
            ? products.sublist(0, section.maxProducts)
            : products;
        final items = capped.map((p) => p.toServiceItem()).toList();

        switch (section.layout) {
          case GrocerySectionLayout.grid3:
            return _ProductGridLayout(
              section: section,
              items: items,
              crossAxisCount: 3,
            );
          case GrocerySectionLayout.grid2:
            return _ProductGridLayout(
              section: section,
              items: items,
              crossAxisCount: 2,
            );
          case GrocerySectionLayout.compactList:
            return _CompactListLayout(section: section, items: items);
          case GrocerySectionLayout.quickAddList:
            return _QuickAddListLayout(section: section, items: items);
          case GrocerySectionLayout.featuredHero:
            return _FeaturedHeroLayout(section: section, items: items);
          case GrocerySectionLayout.dealCards:
            return _DealCardsLayout(section: section, items: items);
          case GrocerySectionLayout.bannerProductRail:
            return _BannerProductRailLayout(section: section, items: items);
          case GrocerySectionLayout.splitFeatured:
            return _SplitFeaturedLayout(section: section, items: items);
          case GrocerySectionLayout.masonry:
            return _MasonryLayout(title: section.title, items: items);
          case GrocerySectionLayout.horizontalCarousel:
          default:
            // Covers horizontalCarousel plus any future layout this mobile
            // build doesn't know how to render yet (see
            // GrocerySectionLayout.isImplemented) — the section still shows
            // something real rather than disappearing.
            return _HorizontalCarouselLayout(section: section, items: items);
        }
      },
    );
  }
}

/// Where a section's "See All" should go: the browse screen already opened on
/// that section's own department (its picked categories, or — for a
/// "Specific Products" section — the categories of its picked products). It
/// used to always open the general page, which defaults to Grocery & Staples.
/// Falls back to the general page when nothing can be resolved.
String _seeAllRoute(WidgetRef ref, MobileGrocerySection? section) {
  const general = '/groceries/seller-hub';
  if (section == null) return general;
  final tree = ref.read(marketplaceCategoryTreeProvider).valueOrNull;
  if (tree == null) return general;

  var ids = section.categoryIds;
  if (ids.isEmpty && section.productIds.isNotEmpty) {
    final products = ref
        .read(marketplaceProductsByIdsProvider(section.productIds.join(',')))
        .valueOrNull;
    ids = [
      for (final p in products ?? const <MarketplaceProduct>[])
        if (p.categoryId != null) p.categoryId!,
    ];
  }
  final resolved = _resolveSectionCategories(tree, ids);
  if (resolved.isEmpty) return general;
  final first = resolved.first;
  final root = first.isVegetableRoot ? '/vegetables' : '/groceries';
  return '$root/seller-hub?category=${first.category.slug}';
}

class _SectionTitle extends ConsumerWidget {
  const _SectionTitle(this.title, {this.showSeeAll = false, this.section});
  final String title;

  /// The section this title belongs to — used to point "See All" at that
  /// section's own department (see [_seeAllRoute]).
  final MobileGrocerySection? section;

  // "See All" display checkbox (Phase B). Opens the browse screen on this
  // section's own category, or the general page when that can't be resolved.
  final bool showSeeAll;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: AppColors.navy,
              ),
            ),
          ),
          if (showSeeAll)
            InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () => context.push(_seeAllRoute(ref, section)),
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'See All',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: AppColors.groceryGreen,
                      ),
                    ),
                    SizedBox(width: 2),
                    Icon(Icons.chevron_right, size: 16, color: AppColors.groceryGreen),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Shared horizontal product strip used by both Horizontal Carousel and
/// Banner + Product Rail below — one real ListView of [ProductCard], never
/// duplicated per layout.
class _ProductCarouselRow extends StatelessWidget {
  const _ProductCarouselRow({
    required this.items,
    this.showImage = true,
    this.showPrice = true,
    this.showDiscount = true,
    this.showAddButton = true,
  });

  final List<ServiceItem> items;

  // Fixed 2026-10-05: height is computed from [ProductCard.groceryCardHeight] --
  // the one place that actually knows this card's real content height for a
  // given combination of showImage/showPrice/showAddButton -- so it can never
  // drift out of sync with [ProductCard]'s own layout.
  static const double? height = null;
  static const double cardWidth = 165;
  final bool showImage;
  final bool showPrice;
  final bool showDiscount;
  final bool showAddButton;

  @override
  Widget build(BuildContext context) {
    final resolvedHeight = height ??
        ProductCard.groceryCardHeight(
          cardWidth: cardWidth,
          showImage: showImage,
          showPrice: showPrice,
          showAddButton: showAddButton,
        );
    return SizedBox(
      height: resolvedHeight,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        scrollDirection: Axis.horizontal,
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (context, i) => SizedBox(
          width: cardWidth,
          child: RepaintBoundary(
            child: ProductCard(
              service: items[i],
              showImage: showImage,
              showPrice: showPrice,
              showDiscount: showDiscount,
              showAddButton: showAddButton,
            ),
          ),
        ),
      ),
    );
  }
}

/// Layout 1 — Horizontal Carousel. Unchanged from the original curated
/// section behavior, just now driven by the resolver above, plus the
/// Display checkboxes and "See All" added 2026-10-05.
class _HorizontalCarouselLayout extends StatelessWidget {
  const _HorizontalCarouselLayout({this.title, this.section, required this.items});

  // `title` alone is kept for the fallback `default:` case in the resolver
  // switch above, which has no [MobileGrocerySection] to hand it (a future
  // mobile-only layout string this build doesn't recognize) — every real
  // call site now passes `section` instead, which wins when both are given.
  final String? title;
  final MobileGrocerySection? section;
  final List<ServiceItem> items;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionTitle(section?.title ?? title ?? '', showSeeAll: section?.showSeeAll ?? false, section: section),
        const SizedBox(height: 12),
        _ProductCarouselRow(
          items: items,
          showImage: section?.showProductImage ?? true,
          showPrice: section?.showProductPrice ?? true,
          showDiscount: section?.showProductDiscount ?? true,
          showAddButton: section?.showAddButton ?? true,
        ),
      ],
    );
  }
}

/// Layouts 2 & 3 — Grid 3-Across and Grid 2-Across. Same ProductCard, same
/// grid mechanics the original "grid" layout used; only the column count
/// and card proportions change — a 2-across grid gets noticeably more room
/// per card, matching the "larger cards, more info" brief for that layout.
class _ProductGridLayout extends StatelessWidget {
  const _ProductGridLayout({
    required this.section,
    required this.items,
    required this.crossAxisCount,
  });

  final MobileGrocerySection section;
  final List<ServiceItem> items;
  final int crossAxisCount;

  static const double _crossAxisSpacing = 10;
  static const double _mainAxisSpacing = 14;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionTitle(section.title, showSeeAll: section.showSeeAll, section: section),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          // Fixed 2026-10-05: this used to take a hardcoded
          // `childAspectRatio` literal (0.62 for Grid 3-Across, 0.72 for
          // Grid 2-Across) that was never actually derived from
          // ProductCard's real content height for this section's
          // showImage/showPrice/showAddButton combination -- the exact
          // same mismatch class that produced "BOTTOM OVERFLOWED" in
          // _ProductCarouselRow (fixed earlier the same day by computing
          // its height from [ProductCard.groceryCardHeight] instead of a
          // guessed constant). A GridView's cell WIDTH depends on the
          // available width divided across `crossAxisCount` columns, which
          // isn't known until layout, so this needs a [LayoutBuilder]
          // (the carousel row didn't, since its card width was already a
          // fixed constant) to compute the real per-cell width first, then
          // derive the aspect ratio from that same single source of truth.
          child: LayoutBuilder(
            builder: (context, constraints) {
              final cellWidth = (constraints.maxWidth -
                      _crossAxisSpacing * (crossAxisCount - 1)) /
                  crossAxisCount;
              final cellHeight = ProductCard.groceryCardHeight(
                cardWidth: cellWidth,
                showImage: section.showProductImage,
                showPrice: section.showProductPrice,
                showAddButton: section.showAddButton,
              );
              return GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: items.length,
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: crossAxisCount,
                  crossAxisSpacing: _crossAxisSpacing,
                  mainAxisSpacing: _mainAxisSpacing,
                  childAspectRatio: cellWidth / cellHeight,
                ),
                itemBuilder: (context, i) => RepaintBoundary(
                  child: ProductCard(
                    service: items[i],
                    showImage: section.showProductImage,
                    showPrice: section.showProductPrice,
                    showDiscount: section.showProductDiscount,
                    showAddButton: section.showAddButton,
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

/// Shared row body for Layouts 4 & 5 (Compact List / Quick Add List) — a
/// dense, single-line-per-product list rather than a card grid, for
/// browsing large flat collections (rice, pulses, staples) quickly. Both
/// layouts use the exact same cart control ([QuickAddControl], extracted
/// from [ProductCard]) and the exact same product-detail navigation
/// [ProductCard] itself uses, so there is no second cart or navigation path
/// to keep in sync.
class _ProductRow extends StatelessWidget {
  const _ProductRow({
    required this.service,
    required this.showImage,
    this.showPrice = true,
    this.showDiscount = true,
    this.showAddButton = true,
  });

  final ServiceItem service;
  final bool showImage;
  final bool showPrice;
  final bool showDiscount;
  final bool showAddButton;

  String get _safeSlug => service.slug.isNotEmpty ? service.slug : 'svc-${service.id}';

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => context.push('/products/$_safeSlug', extra: service),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
        child: Row(
          children: [
            if (showImage) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: AppRemoteImage(
                  imageUrl: service.imageUrl,
                  rawPath: service.imageUrl,
                  title: service.title,
                  width: 44,
                  height: 44,
                  fit: BoxFit.cover,
                ),
              ),
              const SizedBox(width: 12),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    service.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppColors.navy,
                    ),
                  ),
                  if (service.displayUnit.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      service.displayUnit,
                      style: const TextStyle(fontSize: 11, color: AppColors.textHint),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 10),
            if (showPrice)
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (service.hasDiscount && showDiscount)
                    Text(
                      '₹${service.price}',
                      style: const TextStyle(
                        fontSize: 10,
                        color: AppColors.textHint,
                        decoration: TextDecoration.lineThrough,
                      ),
                    ),
                  Text(
                    '₹${service.effectivePrice}',
                    style: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w800,
                      color: AppColors.navy,
                    ),
                  ),
                ],
              ),
            if (showAddButton) ...[
              const SizedBox(width: 10),
              QuickAddControl(service: service),
            ],
          ],
        ),
      ),
    );
  }
}

class _ProductRowList extends StatelessWidget {
  const _ProductRowList({
    required this.title,
    required this.items,
    required this.showImage,
    this.showPrice = true,
    this.showDiscount = true,
    this.showAddButton = true,
    this.showSeeAll = false,
    this.section,
  });

  final String title;
  final List<ServiceItem> items;
  final bool showImage;
  final bool showPrice;
  final bool showDiscount;
  final bool showAddButton;
  final bool showSeeAll;
  final MobileGrocerySection? section;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionTitle(title, showSeeAll: showSeeAll, section: section),
        const SizedBox(height: 8),
        ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: items.length,
          separatorBuilder: (_, __) => const Divider(height: 1, color: AppColors.divider),
          itemBuilder: (context, i) => RepaintBoundary(
            child: _ProductRow(
              service: items[i],
              showImage: showImage,
              showPrice: showPrice,
              showDiscount: showDiscount,
              showAddButton: showAddButton,
            ),
          ),
        ),
      ],
    );
  }
}

/// Layout 4 — Compact List: thumbnail + name/unit + price + Add, for large
/// flat collections (rice, pulses, staples, packaged groceries).
class _CompactListLayout extends StatelessWidget {
  const _CompactListLayout({required this.section, required this.items});

  final MobileGrocerySection section;
  final List<ServiceItem> items;

  @override
  Widget build(BuildContext context) {
    return _ProductRowList(
      title: section.title,
      items: items,
      showImage: section.showProductImage,
      showPrice: section.showProductPrice,
      showDiscount: section.showProductDiscount,
      showAddButton: section.showAddButton,
      showSeeAll: section.showSeeAll,
      section: section,
    );
  }
}

/// Layout 5 — Product List + Quick Add: optimized purely for fast repeat
/// purchasing (name, unit, price, add/stepper) — no thumbnail, so even more
/// products fit on screen at once than Compact List. The primary action
/// here IS the Add/stepper control, so showAddButton defaults true the same
/// as every other layout — an admin can still turn it off, but doing so
/// turns this layout into a plain read-only list, which the admin UI should
/// warn about (see the Display checkboxes block in HomePageCustomizerPage.jsx).
class _QuickAddListLayout extends StatelessWidget {
  const _QuickAddListLayout({required this.section, required this.items});

  final MobileGrocerySection section;
  final List<ServiceItem> items;

  @override
  Widget build(BuildContext context) {
    return _ProductRowList(
      title: section.title,
      items: items,
      showImage: false,
      showPrice: section.showProductPrice,
      showDiscount: section.showProductDiscount,
      showAddButton: section.showAddButton,
      showSeeAll: section.showSeeAll,
      section: section,
    );
  }
}

/// Layout 6 — Featured Hero: one large spotlight card for the first product
/// among this section's picked categories (deterministic — whichever
/// product the category merge returns first, never a random or fabricated
/// pick), with a bigger image and prominent price/Add, for a single
/// standout item rather than a browsing strip.
class _FeaturedHeroLayout extends StatelessWidget {
  const _FeaturedHeroLayout({required this.section, required this.items});

  final MobileGrocerySection section;
  final List<ServiceItem> items;

  String _safeSlug(ServiceItem s) => s.slug.isNotEmpty ? s.slug : 'svc-${s.id}';

  @override
  Widget build(BuildContext context) {
    final service = items.first;
    // Added 2026-10-05 (Phase B, Section 2) -- admin-configurable hero
    // framing, reusing the exact same `configuration.image`/`banner_title`/
    // `banner_subtitle`/`banner_cta_text`/`banner_cta_link` keys the Banner
    // + Product Rail layout already uses (see MobileGrocerySection.hasBanner
    // and HomePageCustomizerPage.jsx's shared Hero/Banner config block) --
    // deliberately not a second set of fields for what is the same concept
    // (an admin-uploaded image + promotional caption + optional CTA) on a
    // different layout. The spotlighted PRODUCT's own image/title/price/Add
    // below are never replaced by this -- only the caption overlaid on the
    // image and, optionally, a secondary CTA pill are admin-configurable;
    // the card's own tap target always goes to the real product page,
    // exactly as before this existed.
    final heroImageUrl = section.bannerImageUrl ?? service.imageUrl;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionTitle(section.title),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: () => context.push('/products/${_safeSlug(service)}', extra: service),
            child: Container(
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: AppColors.border),
              ),
              clipBehavior: Clip.antiAlias,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AspectRatio(
                    aspectRatio: 16 / 9,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        AppRemoteImage(
                          imageUrl: heroImageUrl,
                          rawPath: heroImageUrl,
                          title: service.title,
                          categoryName: service.categoryName,
                          slug: service.slug,
                          width: double.infinity,
                          height: double.infinity,
                          fit: BoxFit.cover,
                        ),
                        if (section.bannerTitle.isNotEmpty || section.bannerSubtitle.isNotEmpty || section.bannerCtaText.isNotEmpty)
                          Positioned(
                            left: 0,
                            right: 0,
                            bottom: 0,
                            child: Container(
                              padding: const EdgeInsets.fromLTRB(14, 20, 14, 12),
                              decoration: const BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [Colors.transparent, Color(0xB3000000)],
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (section.bannerTitle.isNotEmpty)
                                    Text(
                                      section.bannerTitle,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w800,
                                        color: Colors.white,
                                      ),
                                    ),
                                  if (section.bannerSubtitle.isNotEmpty)
                                    Text(
                                      section.bannerSubtitle,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(fontSize: 12, color: Colors.white70),
                                    ),
                                  if (section.bannerCtaText.isNotEmpty) ...[
                                    const SizedBox(height: 6),
                                    InkWell(
                                      borderRadius: BorderRadius.circular(20),
                                      onTap: section.bannerCtaLink.trim().isEmpty
                                          ? null
                                          : () => handleAdminLinkTap(
                                                context,
                                                section.bannerCtaLink,
                                                fallbackPath: '/groceries/seller-hub',
                                              ),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: Colors.white,
                                          borderRadius: BorderRadius.circular(20),
                                        ),
                                        child: Text(
                                          section.bannerCtaText,
                                          style: const TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w800,
                                            color: AppColors.groceryGreen,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(14),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                service.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800,
                                  color: AppColors.navy,
                                ),
                              ),
                              if (service.displayUnit.isNotEmpty) ...[
                                const SizedBox(height: 3),
                                Text(
                                  service.displayUnit,
                                  style: const TextStyle(fontSize: 12, color: AppColors.textHint),
                                ),
                              ],
                              const SizedBox(height: 6),
                              Row(
                                children: [
                                  if (service.hasDiscount) ...[
                                    Text(
                                      '₹${service.price}',
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: AppColors.textHint,
                                        decoration: TextDecoration.lineThrough,
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                  ],
                                  Text(
                                    '₹${service.effectivePrice}',
                                    style: const TextStyle(
                                      fontSize: 17,
                                      fontWeight: FontWeight.w900,
                                      color: AppColors.navy,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 10),
                        QuickAddControl(service: service),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Layout 7 — Deal Cards: only products carrying a REAL backend-provided
/// discount (`service.hasDiscount`, backed by the actual `discountedPrice`
/// field — never the fabricated `ServiceItem.mrp` getter, which is not used
/// anywhere in this file). If nothing among this section's picked
/// categories currently has a real discount, the section hides itself
/// entirely rather than inventing one — same "never fabricate a discount"
/// rule the rest of the app follows.
class _DealCardsLayout extends StatelessWidget {
  const _DealCardsLayout({required this.section, required this.items});

  final MobileGrocerySection section;
  final List<ServiceItem> items;

  @override
  Widget build(BuildContext context) {
    // Never fabricated -- filters to service.hasDiscount (the real
    // discountedPrice field), same rule as everywhere else in this app.
    // Added 2026-10-05 (Phase B, Section 11): Display checkboxes now reach
    // this layout too (see HomePageCustomizerPage.jsx's Display block,
    // which now also lists 'deal_cards') -- showDiscount hides BOTH the
    // "% OFF" corner badge below and ProductCard's own strike-through MRP,
    // since both are the same "discount" concept to an admin turning it off.
    final deals = items.where((i) => i.hasDiscount).toList();
    if (deals.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionTitle(section.title),
        const SizedBox(height: 12),
        SizedBox(
          height: 308,
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            scrollDirection: Axis.horizontal,
            itemCount: deals.length,
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (context, i) {
              final service = deals[i];
              return SizedBox(
                width: 172,
                child: Stack(
                  children: [
                    RepaintBoundary(
                      child: ProductCard(
                        service: service,
                        showImage: section.showProductImage,
                        showPrice: section.showProductPrice,
                        showDiscount: section.showProductDiscount,
                        showAddButton: section.showAddButton,
                      ),
                    ),
                    if (service.discountPercent != null && section.showProductDiscount)
                      Positioned(
                        top: 6,
                        left: 6,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                          decoration: BoxDecoration(
                            color: AppColors.error,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            '${service.discountPercent}% OFF',
                            style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w900,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

/// Layout 8 — Banner + Product Rail: a styled gradient header card (the
/// section's own title — no fabricated promo copy or image, since admin
/// grocery sections have no banner-image field of their own) followed by
/// the same shared horizontal product rail every carousel layout uses.
class _BannerProductRailLayout extends StatelessWidget {
  const _BannerProductRailLayout({required this.section, required this.items});

  final MobileGrocerySection section;
  final List<ServiceItem> items;

  @override
  Widget build(BuildContext context) {
    // No banner configured (every section saved before 2026-10-05, or an
    // admin who picked this layout but hasn't filled in the banner yet) —
    // graceful fallback to a plain rail rather than an empty/broken banner
    // box, per the explicit "banner removed" requirement.
    if (!section.hasBanner) {
      return _HorizontalCarouselLayout(title: section.title, items: items);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: section.bannerCtaLink.trim().isEmpty
                ? null
                : () => handleAdminLinkTap(
                      context,
                      section.bannerCtaLink,
                      fallbackPath: '/groceries/seller-hub',
                    ),
            child: Container(
              width: double.infinity,
              height: 150,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                // Shows while the image loads, and is what's visible at all
                // if no banner image was uploaded (title/subtitle-only
                // banner) — never an empty container either way.
                gradient: const LinearGradient(
                  colors: [AppColors.groceryGreen, AppColors.groceryGreenDark],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (section.bannerImageUrl != null)
                    AppRemoteImage(
                      imageUrl: section.bannerImageUrl,
                      rawPath: section.bannerImageUrl,
                      title: section.bannerTitle.isNotEmpty ? section.bannerTitle : section.title,
                      width: double.infinity,
                      height: double.infinity,
                      fit: BoxFit.cover,
                    ),
                  // Scrim so white banner text stays legible over any photo
                  // — matches the gradient-overlay convention AppRemoteImage
                  // itself already uses for its placeholder state.
                  DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Colors.black.withValues(alpha: 0.12),
                          Colors.black.withValues(alpha: 0.42),
                        ],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (section.bannerTitle.isNotEmpty)
                          Text(
                            section.bannerTitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w900,
                              color: Colors.white,
                            ),
                          ),
                        if (section.bannerSubtitle.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            section.bannerSubtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                          ),
                        ],
                        if (section.bannerCtaText.isNotEmpty) ...[
                          const SizedBox(height: 10),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              section.bannerCtaText,
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                                color: AppColors.groceryGreenDark,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        _ProductCarouselRow(items: items),
      ],
    );
  }
}

/// Layout 9 — Split Featured: two large side-by-side cards — same
/// [ProductCard], same shared cart/navigation, just given the full row
/// width each instead of a scrolling strip, for a short high-intent pair
/// rather than a browsing list. Shows one card if the section only has one
/// product (never crashes on a short list).
class _SplitFeaturedLayout extends StatelessWidget {
  const _SplitFeaturedLayout({required this.section, required this.items});

  final MobileGrocerySection section;
  final List<ServiceItem> items;

  @override
  Widget build(BuildContext context) {
    // Added 2026-10-05 (Phase B, Section 12): "max 2-3" is now the admin's
    // own Max Products field, clamped to this layout's real visual range --
    // below 2 there's nothing to split, above 3 the side-by-side cards get
    // too narrow to read. Uses [configuredMaxProducts] (null when the admin
    // never touched this field) rather than [maxProducts] (which defaults
    // to the generic 30) specifically so every Split Featured section
    // saved before today keeps showing exactly 2 cards, unchanged, instead
    // of silently jumping to 3. Real catalog products only (never a
    // hardcoded placeholder) -- items already comes from the resolver's
    // real merge/specific-products fetch above.
    final count = (section.configuredMaxProducts ?? 2).clamp(2, 3);
    final featured = items.take(count).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionTitle(section.title),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var i = 0; i < featured.length; i++) ...[
                if (i > 0) const SizedBox(width: 10),
                Expanded(
                  child: RepaintBoundary(
                    child: ProductCard(
                      service: featured[i],
                      showImage: section.showProductImage,
                      showPrice: section.showProductPrice,
                      showDiscount: section.showProductDiscount,
                      showAddButton: section.showAddButton,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// Layout 12 — Masonry: a lightweight two-column staggered grid, built
/// without adding a new staggered-grid-view package dependency — items
/// alternate into two independent, naturally-sized columns (even index →
/// left, odd index → right), so the columns end up uneven heights whenever
/// product titles/units wrap differently, the same visual effect a real
/// masonry grid gives, without needing to measure each card's rendered
/// height up front. This is a deliberate, lower-risk compromise over a true
/// height-aware masonry algorithm — called out as a known limitation in the
/// implementation notes rather than left silent.
class _MasonryLayout extends StatelessWidget {
  const _MasonryLayout({required this.title, required this.items});

  final String title;
  final List<ServiceItem> items;

  @override
  Widget build(BuildContext context) {
    final left = <ServiceItem>[];
    final right = <ServiceItem>[];
    for (var i = 0; i < items.length; i++) {
      (i.isEven ? left : right).add(items[i]);
    }

    Widget buildColumn(List<ServiceItem> column) {
      return Column(
        children: [
          for (final service in column) ...[
            RepaintBoundary(child: ProductCard(service: service)),
            const SizedBox(height: 10),
          ],
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionTitle(title),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: buildColumn(left)),
              const SizedBox(width: 10),
              Expanded(child: buildColumn(right)),
            ],
          ),
        ),
      ],
    );
  }
}

/// Loading-state shimmer, copied from the original curated carousel so
/// every product-driven layout's loading state looks the same while it
/// fetches.
class _HorizontalShimmerRow extends StatelessWidget {
  const _HorizontalShimmerRow({required this.height});
  final double height;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      scrollDirection: Axis.horizontal,
      itemCount: 4,
      separatorBuilder: (_, __) => const SizedBox(width: 10),
      itemBuilder: (context, i) => SizedBox(
        width: 165,
        child: ProductCardSkeleton(height: height, width: 165, borderRadius: 14),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// Category-discovery data path (Layouts 10 & 11) — real Seller Hub
// departments, not their products.
// ─────────────────────────────────────────────────────────────────────────

/// One of the section's picked category ids, resolved against the real
/// Seller Hub tree, plus which root it lives under (so tapping it can
/// deep-link into the right browse screen).
class _ResolvedCategory {
  const _ResolvedCategory({required this.category, required this.isVegetableRoot});
  final MarketplaceCategory category;
  final bool isVegetableRoot;
}

/// Resolves the section's picked category ids against the real Seller Hub
/// tree, in the admin's own picked order, keeping only categories that
/// actually have sellable products anywhere in their subtree
/// ([MarketplaceCategory.hasAnyProducts]) — same "don't show an empty tile"
/// rule [marketplaceHomeSectionsProvider] already applies elsewhere in this
/// file's sibling repository. [_ResolvedCategory.isVegetableRoot] mirrors
/// that same provider's root-detection heuristic (root name/slug containing
/// "vegetable"/"fruit") so a tap deep-links into the correct browse screen.
List<_ResolvedCategory> _resolveSectionCategories(
  List<MarketplaceCategory> tree,
  List<int> wantedIds,
) {
  final byId = <int, _ResolvedCategory>{};
  void walk(List<MarketplaceCategory> nodes, bool isVegetableRoot) {
    for (final node in nodes) {
      byId[node.id] = _ResolvedCategory(category: node, isVegetableRoot: isVegetableRoot);
      if (node.children.isNotEmpty) walk(node.children, isVegetableRoot);
    }
  }

  for (final root in tree) {
    final rootKey = '${root.name} ${root.slug}'.toLowerCase();
    final isVeg = rootKey.contains('vegetable') || rootKey.contains('fruit');
    byId[root.id] = _ResolvedCategory(category: root, isVegetableRoot: isVeg);
    if (root.children.isNotEmpty) walk(root.children, isVeg);
  }

  final out = <_ResolvedCategory>[];
  for (final id in wantedIds) {
    final match = byId[id];
    if (match != null && match.category.hasAnyProducts) out.add(match);
  }
  return out;
}

void _openCategoryListing(BuildContext context, _ResolvedCategory resolved) {
  final root = resolved.isVegetableRoot ? '/vegetables' : '/groceries';
  context.push('$root/seller-hub?category=${resolved.category.slug}');
}

/// Fixed 2026-10-05: tapping a Category Tile Grid / Circular Category Rail
/// tile always opened that category's full product-LISTING screen, even
/// when the category contains exactly one product -- which happens a lot
/// in practice, since an admin will often pick narrow, single-item leaf
/// categories here specifically to spotlight one product as if it were its
/// own tile (e.g. "Yellakki Banana" as its own category with one product in
/// it). For the customer, tapping what looks like a single product and
/// landing on a listing screen showing that same one product is an extra,
/// pointless tap. When the category's own [totalProductCount] says exactly
/// one, this fetches that one product (via the same
/// [marketplaceProductsByCategoryProvider] the listing screen itself uses,
/// so the result is cached/shared rather than a second, parallel fetch) and
/// deep-links straight to its product detail page instead -- falling back
/// to the normal category listing for every other case (0 products never
/// reaches here at all, since [_resolveSectionCategories] already filters
/// those out; 2+ products keeps the listing, which is the right place to
/// browse them; a fetch failure or count mismatch also falls back, same
/// "fail open, never dead-end the tap" convention as the rest of this
/// file).
Future<void> _openCategory(
  BuildContext context,
  WidgetRef ref,
  _ResolvedCategory resolved,
) async {
  if (resolved.category.totalProductCount != 1) {
    _openCategoryListing(context, resolved);
    return;
  }
  try {
    final page = await ref.read(
      marketplaceProductsByCategoryProvider(resolved.category.id).future,
    );
    if (!context.mounted) return;
    if (page.products.length == 1) {
      // Reuses [MarketplaceProduct.toServiceItem]'s own slug convention
      // (`seller-hub-<id>`) rather than re-deriving it here, so this can
      // never drift out of sync with the one place that actually defines
      // it -- same single-source-of-truth reasoning as
      // [ProductCard.groceryCardHeight] elsewhere in this file.
      final serviceItem = page.products.first.toServiceItem();
      context.push('/products/${serviceItem.slug}', extra: serviceItem);
      return;
    }
  } catch (_) {
    // Fall through to the listing screen below -- never leave the tap
    // doing nothing just because this shortcut's lookup failed.
  }
  if (!context.mounted) return;
  _openCategoryListing(context, resolved);
}

class _CategoryDiscoverySection extends ConsumerWidget {
  const _CategoryDiscoverySection({required this.section});

  final MobileGrocerySection section;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final treeAsync = ref.watch(marketplaceCategoryTreeProvider);
    return treeAsync.when(
      loading: () => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionTitle(section.title),
          const SizedBox(height: 12),
          const SizedBox(height: 108, child: _CategoryShimmerRow()),
        ],
      ),
      // Seller Hub tree failed to load — never crash, never show fake
      // categories, just hide this one section.
      error: (err, st) => const SizedBox.shrink(),
      data: (tree) {
        final resolved = _resolveSectionCategories(tree, section.categoryIds);
        if (resolved.isEmpty) return const SizedBox.shrink();
        final capped = resolved.length > section.maxProducts
            ? resolved.sublist(0, section.maxProducts)
            : resolved;
        return section.layout == GrocerySectionLayout.circularCategoryRail
            ? _CircularCategoryRailLayout(section: section, categories: capped)
            : _CategoryTileGridLayout(section: section, categories: capped);
      },
    );
  }
}

/// Layout 10 — Category Tile Grid: real Seller Hub departments as tappable
/// tiles (admin-uploaded image, real name, real product count) — "shop by
/// category" rather than individual products. Tapping deep-links into the
/// same browse screens (SellerHubGroceriesScreen / SellerHubVegetablesScreen)
/// the rest of the app already uses for this exact tree.
class _CategoryTileGridLayout extends ConsumerWidget {
  const _CategoryTileGridLayout({required this.section, required this.categories});

  final MobileGrocerySection section;
  final List<_ResolvedCategory> categories;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionTitle(section.title),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: categories.length,
            // Added 2026-10-05 (Phase B, Section 13): admin's "Columns"
            // dropdown, defaulting to 3 (this layout's original hardcoded
            // value) so a section saved before this existed renders an
            // identical grid.
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: section.categoryTileColumns,
              crossAxisSpacing: 10,
              mainAxisSpacing: 14,
              childAspectRatio: 0.82,
            ),
            itemBuilder: (context, i) {
              final resolved = categories[i];
              final category = resolved.category;
              return InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () => _openCategory(context, ref, resolved),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    if (section.showCategoryImage)
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(14),
                          child: _CategoryCoverImage(
                            category: category,
                            width: double.infinity,
                            height: double.infinity,
                          ),
                        ),
                      ),
                    const SizedBox(height: 6),
                    Text(
                      category.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.navy),
                    ),
                    if (section.showCategoryProductCount)
                      Text(
                        '${category.totalProductCount} items',
                        style: const TextStyle(fontSize: 10, color: AppColors.textHint),
                      ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

/// Layout 11 — Circular Category Rail: the same real department data as
/// Category Tile Grid, as a horizontal rail of circular avatars + label —
/// the common "shop by category" strip grocery apps show above the main
/// feed.
class _CircularCategoryRailLayout extends ConsumerWidget {
  const _CircularCategoryRailLayout({required this.section, required this.categories});

  final MobileGrocerySection section;
  final List<_ResolvedCategory> categories;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionTitle(section.title),
        const SizedBox(height: 12),
        SizedBox(
          height: 108,
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            scrollDirection: Axis.horizontal,
            itemCount: categories.length,
            separatorBuilder: (_, __) => const SizedBox(width: 14),
            itemBuilder: (context, i) {
              final resolved = categories[i];
              final category = resolved.category;
              return InkWell(
                borderRadius: BorderRadius.circular(40),
                onTap: () => _openCategory(context, ref, resolved),
                child: SizedBox(
                  width: 72,
                  child: Column(
                    children: [
                      if (section.showCategoryImage)
                        ClipOval(
                          child: _CategoryCoverImage(
                            category: category,
                            width: 64,
                            height: 64,
                          ),
                        ),
                      if (section.showCategoryImage) const SizedBox(height: 6),
                      if (section.showCategoryName)
                        Text(
                          category.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.navy),
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

/// A category tile's picture: the admin-uploaded category image when there is
/// one, otherwise a photo of one of the category's own products (many Seller
/// Hub categories have no image uploaded, which left empty grey tiles).
class _CategoryCoverImage extends ConsumerWidget {
  const _CategoryCoverImage({
    required this.category,
    required this.width,
    required this.height,
  });

  final MarketplaceCategory category;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final own = category.image;
    final url = (own != null && own.isNotEmpty)
        ? own
        : ref.watch(marketplaceCategoryCoverImagesProvider).valueOrNull?[category.id];
    return AppRemoteImage(
      imageUrl: url,
      rawPath: url,
      title: category.name,
      categoryName: category.name,
      slug: category.slug,
      width: width,
      height: height,
      fit: BoxFit.cover,
    );
  }
}

class _CategoryShimmerRow extends StatelessWidget {
  const _CategoryShimmerRow();

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      scrollDirection: Axis.horizontal,
      itemCount: 6,
      separatorBuilder: (_, __) => const SizedBox(width: 14),
      itemBuilder: (context, i) => const ShimmerCircle(size: 64),
    );
  }
}
