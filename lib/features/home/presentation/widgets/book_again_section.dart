import 'package:decimal/decimal.dart';
import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/utils/image_url_helper.dart';
import '../../../../shared/theme/app_colors.dart';
import '../../../../shared/widgets/app_remote_image.dart';
import '../../../booking/domain/booking_models.dart';
import '../../../booking/domain/booking_providers.dart';
import '../../../catalog/data/grocery_hub_repository.dart';
import '../../../catalog/data/marketplace_catalog_repository.dart';
import '../../../catalog/domain/catalog_models.dart';
import '../../../catalog/domain/catalog_providers.dart';
import '../../data/home_studio_repository.dart';
import '../../../booking/domain/cart_notifier.dart' show isUserAuthenticatedProvider;
import '../../../catalog/domain/recently_viewed.dart';
import 'studio_title.dart';

/// Up to 6 distinct services/groceries pulled from the customer's own
/// booking history for the "Book Again" shortcut row beneath the promo
/// banner — never an invented or hardcoded list. De-duplicated by service
/// id so re-ordering the same thing repeatedly doesn't crowd out other
/// recent orders. Bookings are sorted most-recent-first by their own
/// `createdAt` rather than assumed to already arrive that way from the API.
///
/// [flowFilter] added 2026-09-19 as part of the two-themed-home-pages
/// redesign: Services mode's "Book Again" should only reorder past
/// services, Groceries mode's only past groceries — otherwise switching
/// modes wouldn't actually separate the two experiences.
///
/// Id-range offset applied when converting a Marketplace / Grocery Hub
/// product into a [ServiceItem] (see `MarketplaceProduct.toServiceItem()` /
/// `GroceryHubProduct.toServiceItem()`) so those ids can never collide with
/// another source's id in the cart — re-declared here (also mirrored in
/// [BookAgainTile]) as a reliable fallback signal for "this is a grocery
/// item", used below.
const int kBookAgainMarketplaceIdOffset = 800000000;

/// Fixed 2026-10-07 per explicit bug report (a grocery reorder — "Yellaki
/// Banana" etc. — showing up in Services mode's "Book Again", opening the
/// wrong [service detail] page instead of the product page, and missing its
/// photo): all three symptoms traced to the same cause. [ServiceItem.
/// flowType] is derived purely from categorySlug/categoryName/slug — fields
/// that come straight from the JSON passed to [ServiceItem.fromJson]. A
/// booking's own echoed cart item (schemaless `cart_data`, as documented
/// elsewhere in this codebase) frequently omits them entirely, so flowType
/// silently fell back to [CatalogFlowType.serviceBooking] for a grocery
/// reorder — wrongly passing Services mode's "not grocery" filter, taking
/// the services branch in [BookAgainTile]'s route/image lookup, and never
/// finding its real catalog record. This checks two more fields that
/// survive the echo far more reliably: the vegetable-category fields (set
/// whenever the source was a produce item) and the Marketplace/Grocery Hub
/// id-offset range above (always present — it's baked into the id itself).
bool isGroceryBookAgainItem(ServiceItem service) {
  return service.flowType == CatalogFlowType.grocery ||
      (service.vegetableCategorySlug?.isNotEmpty ?? false) ||
      (service.vegetableCategoryName?.isNotEmpty ?? false) ||
      service.id >= kBookAgainMarketplaceIdOffset;
}

List<ServiceItem> recentBookAgainItems(
  List<Booking> bookings, {
  CatalogFlowType? flowFilter,
  int limit = 6,
}) {
  final sorted = [...bookings]..sort((a, b) {
      final aDate = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      final bDate = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      return bDate.compareTo(aDate);
    });

  final seenServiceIds = <int>{};
  final result = <ServiceItem>[];
  for (final booking in sorted) {
    for (final item in booking.items) {
      // Fixed 2026-09-19: this used to be a strict equality check, so
      // passing CatalogFlowType.serviceBooking (Services mode's call below)
      // silently excluded the new CatalogFlowType.logistics value (Goods &
      // Transport) the moment that enum value was added — Goods & Transport
      // bookings vanished from "Book Again" in Services mode even though
      // they're bookings, not groceries. Services mode's filter now means
      // "anything that isn't a grocery booking" instead of "only
      // serviceBooking"; Groceries mode's filter (passed as
      // CatalogFlowType.grocery) is unaffected.
      if (flowFilter != null) {
        final isGroceryItem = isGroceryBookAgainItem(item.service);
        final matches =
            flowFilter == CatalogFlowType.grocery ? isGroceryItem : !isGroceryItem;
        if (!matches) continue;
      }
      if (seenServiceIds.add(item.service.id)) {
        result.add(item.service);
        if (result.length >= limit) return result;
      }
    }
  }
  return result;
}

/// One "Book Again" reorder tile: a square thumbnail of a real prior-booking
/// service/grocery item plus its name — deliberately minimal (no price, no
/// rating) since this is a quick-glance shortcut back to something already
/// booked before, not another full product listing.
class BookAgainTile extends ConsumerWidget {
  const BookAgainTile({super.key, required this.service, required this.width, this.caption = 'Book Again'});

  final ServiceItem service;
  final double width;

  /// The small line under the name: "Book Again" for past bookings, the price for recently viewed items.
  final String caption;

  // Mirrors MarketplaceProduct.toServiceItem()'s own private
  // `_cartIdOffset` (marketplace_catalog_repository.dart) and
  // GroceryHubProduct.toServiceItem()'s own private `_cartIdOffset`
  // (grocery_hub_repository.dart) — every grocery ServiceItem id from
  // those two sources is offset into its own range specifically so it
  // can't collide with another source's id in the cart. Re-declared here
  // (not exported from those files) so this tile can tell, from a booked
  // ServiceItem's id alone, which live source to look it back up in. The
  // plain Vegetable Inventory catalog (groceryProduceProvider) uses real,
  // un-offset ids below both of these.
  static const int _marketplaceIdOffset = 800000000;
  static const int _groceryHubIdOffset = 900000000;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Fixed 2026-10-07: was `service.flowType == CatalogFlowType.grocery`
    // alone — unreliable for a booking-echoed item (see
    // [isGroceryBookAgainItem]'s doc comment above for why), which made a
    // grocery reorder tile wrongly take the services branch below: wrong
    // detail route, wrong (service-catalog) image lookup.
    final isGrocery = isGroceryBookAgainItem(service);
    // Rewritten 2026-09-19 — the previous fix only patched the tile's own
    // thumbnail image; tapping through still passed the booking's own
    // echoed item (from cart_data) as `extra`, and ServiceDetailScreen
    // skips its network fetch whenever `extra` is present (see
    // service_detail_screen.dart's `initialService` check). Cart_data is
    // schemaless and, in practice, is frequently missing far more than
    // just the image — description, "What's Included", price accuracy,
    // categoryId (needed for the Related Items strip) — so the detail
    // page was rendering an incomplete/stale snapshot instead of the real
    // catalog record. Fixed properly here: look the same service id up in
    // whichever live catalog strip is already loaded (fetched for
    // Essential Picks / Recommended Services anyway, so this is free) and
    // prefer that FULL, current record over the echoed one for
    // everything — thumbnail, navigation slug, and the `extra` passed
    // through.
    //
    // Fixed 2026-10-06: the grocery branch only ever searched
    // groceryProduceProvider — the plain Vegetable Inventory catalog. A
    // grocery booking placed from Seller Hub Marketplace (ids offset by
    // +800000000 — e.g. the "Quick Commerce Vegetable Order" bookings) or
    // from the Grocery Hub vendor (+900000000) was never found there, so
    // it silently fell back to the stale cart_data echo for every such
    // booking. That echo frequently has no usable image at all, which is
    // exactly why "Organic Fruits"/"Farm-fresh Vegetables" reorder tiles
    // showed a generic placeholder icon instead of the real product
    // photo. Each id range now resolves against its own real source —
    // the Grocery Hub store detail already being loaded for Home's
    // Bestsellers strip (primaryGroceryHubStoreProvider, free to watch
    // again here) for the hub range, and a one-off marketplace product
    // lookup (reusing marketplaceProductsByIdsProvider, the same family
    // provider the admin-curated grocery sections already use) for the
    // marketplace range.
    ServiceItem? liveMatch;
    if (isGrocery && service.id >= _groceryHubIdOffset) {
      final hubProducts =
          ref.watch(primaryGroceryHubStoreProvider).valueOrNull?.products;
      liveMatch = hubProducts
          ?.where((p) => _groceryHubIdOffset + p.id == service.id)
          .firstOrNull
          ?.toServiceItem();
    } else if (isGrocery && service.id >= _marketplaceIdOffset) {
      final marketplaceProductId = service.id - _marketplaceIdOffset;
      final matches = ref
          .watch(marketplaceProductsByIdsProvider('$marketplaceProductId'))
          .valueOrNull;
      liveMatch = matches?.firstOrNull?.toServiceItem();
    } else {
      final live = isGrocery
          ? ref.watch(groceryProduceProvider).valueOrNull
          : ref.watch(popularServicesProvider).valueOrNull;
      liveMatch = live?.where((s) => s.id == service.id).firstOrNull;
    }
    final displayService = liveMatch ?? service;
    final displayImageUrl = displayService.imageUrl;
    // Fixed 2026-10-07 ("The Book again section not showing the image"):
    // `isGrocery` above is already computed robustly (flowType OR the
    // vegetable-category fields OR the marketplace/grocery-hub id offset —
    // see [isGroceryBookAgainItem]), but AppRemoteImage/ImageUrlHelper
    // below never saw that: it was only ever handed
    // `displayService.categorySlug` and re-derives its OWN, weaker
    // "is this grocery" signal from a bare substring match against it. When
    // `liveMatch` is null (the live-catalog lookup above didn't find this
    // item — still loading, removed, or an id-range assumption that
    // doesn't hold) this falls back to the booking's own echoed `service`
    // from `cart_data`, which — per the doc comment on `Booking.
    // isGroceryBooking` — frequently has no `category_slug` at all. With
    // nothing recognizably grocery to go on, ImageUrlHelper's grocery-only
    // fallbacks (the food-photo guess table, and the grocery branch of
    // mapCategoryIcon's default case) were both skipped entirely, landing
    // on the plain `Icons.category_rounded` glyph — the exact "generic
    // placeholder icon" in the screenshot. Forcing a real grocery keyword
    // through whenever this tile already knows it's a grocery item (even
    // with no live match and no echoed category metadata) keeps
    // ImageUrlHelper's own detection in agreement with it, the same
    // "force the keyword" convention already used by
    // MarketplaceProduct.toServiceItem() and GroceryHubProduct.
    // toServiceItem() for exactly this reason.
    final imageCategorySlug = isGrocery
        ? ((displayService.categorySlug?.isNotEmpty ?? false)
            ? displayService.categorySlug
            : 'vegetables_groceries')
        : displayService.categorySlug;
    if (kDebugMode && isGrocery && (displayImageUrl == null || displayImageUrl.isEmpty)) {
      // Diagnostic only — helps tell apart the two different ways a Book
      // Again grocery tile can end up with no photo: liveMatch == null
      // means the id-range lookup above never found this item in its live
      // source (removed from catalog, id-range assumption wrong, or the
      // fetch is still loading/failed), while liveMatch != null but still
      // no imageUrl means the live record itself genuinely has no image
      // (a backend/vendor data gap, not a lookup bug).
      debugPrint('[BOOK-AGAIN] no image for "${service.title}" '
          '(id=${service.id}, liveMatch=${liveMatch != null ? "found" : "NOT FOUND"})');
    }
    final accent = isGrocery ? AppColors.groceryGreen : AppColors.serviceBlue;

    // A real slug (from the live catalog match, or from the echoed item
    // if it happened to carry one) lets ServiceDetailScreen fetch the
    // full record itself — the right fix, since it's guaranteed current.
    // Only when NEITHER has a real slug (the service was perhaps removed
    // from the live catalog since this booking was made) do we fall back
    // to passing whatever record we have as `extra`, which skips the
    // fetch — better an old snapshot than a broken "Page Not Found".
    //
    // Fixed 2026-10-06: that fallback logic is specific to
    // ServiceDetailScreen. GroceryProductDetailScreen (the real
    // destination for a grocery item — see the route fix below) never
    // fetches by slug at all; every grocery product it shows is already
    // loaded client-side, so `extra` is the ONLY way it ever receives
    // data (see that screen's own doc comment). Skipping `extra` whenever
    // a real slug exists, as the services branch correctly does, would
    // leave GroceryProductDetailScreen with nothing to render.
    final hasRealSlug = displayService.slug.isNotEmpty;
    final routeSlug =
        hasRealSlug ? displayService.slug : 'svc-${service.id}';

    return GestureDetector(
      onTap: () => context.push(
        // Fixed 2026-10-06: this always pushed '/services/...' — the
        // scheduled-service detail route — even for a grocery/vegetable
        // item, landing on the generic service listing/detail screen
        // instead of GroceryProductDetailScreen's dedicated product page
        // (AppRoutes.groceryProductDetail, '/products/:slug').
        isGrocery ? '/products/$routeSlug' : '/services/$routeSlug',
        extra: isGrocery ? displayService : (hasRealSlug ? null : displayService),
      ),
      child: SizedBox(
        width: width,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            AspectRatio(
              aspectRatio: 1,
              child: Container(
                decoration: BoxDecoration(
                  color: AppColors.surfaceVariant,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.divider, width: 1.0),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0x080F172A),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                clipBehavior: Clip.antiAlias,
                child: AppRemoteImage(
                  imageUrl: displayImageUrl,
                  rawPath: displayImageUrl,
                  title: displayService.title,
                  // Fixed 2026-10-06: this used to pass the raw, vendor-
                  // specific `categoryName` (e.g. "Organic Fruits",
                  // "Fruits") into both of these — but
                  // ImageUrlHelper.resolve()'s no-real-image fallback (the
                  // food-photo/stock-photo guess tables) and
                  // mapCategoryIcon()'s own default case both only
                  // recognize a grocery item by literally finding
                  // "veg"/"grocery" as a SUBSTRING, which a vendor category
                  // name like "Organic Fruits" never contains. Whenever a
                  // Book Again grocery tile had no real photo, that made
                  // both fallbacks miss their grocery branch entirely and
                  // land on the generic, unthemed default icon
                  // (Icons.category_rounded — the plain shape glyph
                  // reported). `categorySlug` is reliable here instead:
                  // every grocery source (Vegetable Inventory, Seller Hub
                  // Marketplace, Grocery Hub) already forces it to contain
                  // "vegetable"/"grocery" specifically so
                  // ServiceItem.flowType resolves correctly — the same
                  // guarantee now used here to pick a real food photo (or
                  // at worst the grocery basket icon) instead of a
                  // meaningless generic glyph.
                  categoryName: imageCategorySlug,
                  slug: displayService.slug,
                  semanticIcon: ImageUrlHelper.mapCategoryIcon(
                      imageCategorySlug, imageCategorySlug),
                  width: double.infinity,
                  height: double.infinity,
                  fit: BoxFit.cover,
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              displayService.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: AppColors.navy,
                height: 1.2,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              caption,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: accent,
              ),
            ),
          ],
        ),
      ),
    );
  }
}


int _studioMaxItems(StudioSection section, int fallback) {
  final raw = section.settings['max_items'];
  final n = raw is num ? raw.toInt() : int.tryParse('$raw');
  return (n ?? fallback).clamp(3, 20);
}

/// The shared look of the two personal sections: the admin's title above a row of tiles. Collapses to nothing (no
/// title, no gap) when there is nothing to show, so an empty history never leaves a hole in the page.
class _PersonalRail extends StatelessWidget {
  const _PersonalRail({required this.section, required this.fallbackTitle, required this.tiles});

  final StudioSection section;
  final String fallbackTitle;
  final List<Widget> tiles;

  @override
  Widget build(BuildContext context) {
    if (tiles.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: StudioTitle(
              text: section.title.isNotEmpty ? section.title : fallbackTitle,
              imageUrl: section.titleImage,
              font: section.titleFont,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.navy),
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < tiles.length; i++) ...[
                  tiles[i],
                  if (i != tiles.length - 1) const SizedBox(width: 10),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

double _tileWidth(BuildContext context) => (MediaQuery.of(context).size.width - 32 - 30) / 4;

/// Home Studio "Book Again": the signed-in customer's own past bookings (Services page) or past grocery items
/// (Grocery page). Nothing for guests, nothing until there is a history.
class StudioBookAgain extends ConsumerWidget {
  const StudioBookAgain({super.key, required this.section, required this.pageKey});

  final StudioSection section;
  final String pageKey;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(isUserAuthenticatedProvider)) return const SizedBox.shrink();
    final grocery = pageKey == 'grocery_home';
    final bookings = ref.watch(myBookingsProvider(null)).valueOrNull ?? const <Booking>[];
    final items = recentBookAgainItems(
      bookings,
      flowFilter: grocery ? CatalogFlowType.grocery : CatalogFlowType.serviceBooking,
      limit: _studioMaxItems(section, 8),
    );
    final w = _tileWidth(context);
    return _PersonalRail(
      section: section,
      fallbackTitle: 'Book again',
      tiles: [for (final s in items) BookAgainTile(key: ValueKey('book-again-${s.id}'), service: s, width: w)],
    );
  }
}

/// Recently viewed tiles outside Home (the empty search screen). Same data as the Home section; nothing is drawn
/// until something has been viewed.
class RecentlyViewedStrip extends ConsumerWidget {
  const RecentlyViewedStrip({super.key, required this.grocery, this.limit = 10});

  final bool grocery;
  final int limit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = [
      for (final s in ref.watch(recentlyViewedProvider))
        if (RecentlyViewedNotifier.isGrocery(s) == grocery) s,
    ].take(limit).toList();
    if (items.isEmpty) return const SizedBox.shrink();
    final w = (MediaQuery.of(context).size.width - 32 - 30) / 4;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: Text('Recently viewed', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.navy)),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < items.length; i++) ...[
                  BookAgainTile(
                    key: ValueKey('recent-strip-${items[i].id}'),
                    service: items[i],
                    width: w,
                    caption: items[i].effectivePrice > Decimal.zero ? '₹${items[i].effectivePrice}' : '',
                  ),
                  if (i != items.length - 1) const SizedBox(width: 10),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Home Studio "Recently Viewed": what this person last opened on this phone, for this page's kind of item.
/// Works for guests. Hidden until something has been viewed.
class StudioRecentlyViewed extends ConsumerWidget {
  const StudioRecentlyViewed({super.key, required this.section, required this.pageKey});

  final StudioSection section;
  final String pageKey;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final grocery = pageKey == 'grocery_home';
    final viewed = ref.watch(recentlyViewedProvider);
    final items = [
      for (final s in viewed)
        if (RecentlyViewedNotifier.isGrocery(s) == grocery) s,
    ].take(_studioMaxItems(section, 10)).toList();
    final w = _tileWidth(context);
    return _PersonalRail(
      section: section,
      fallbackTitle: 'Recently viewed',
      tiles: [
        for (final s in items)
          BookAgainTile(
            key: ValueKey('recent-${s.id}'),
            service: s,
            width: w,
            caption: s.effectivePrice > Decimal.zero ? '₹${s.effectivePrice}' : '',
          ),
      ],
    );
  }
}
