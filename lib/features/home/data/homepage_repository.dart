import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/api_error.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/response_normalizer.dart';
import '../domain/grocery_section_layout.dart';

/// One admin-configured promotional offer/banner item from the homepage CMS.
///
/// Added 2026-09-16: the Home screen's advertisement carousel and its
/// "Offers & Coupons" card were both fully static — hardcoded copy (see
/// `_promoBanners` in home_screen.dart, whose own comment already said
/// "swap this list for a live promotions/banners provider whenever the
/// backend exposes one") and a fixed "FIRSTSEVO — Get ₹150 OFF" card that
/// never reflected what the admin actually configured. The backend already
/// has a real, admin-editable homepage CMS
/// (settings_hub/views_homepage.py: HomePageConfigAPIView, GET/PUT
/// /api/settings/homepage/) whose `offers.items` section is exactly this
/// kind of promotional content — this model reads that real data.
class HomeOffer {
  const HomeOffer({
    required this.id,
    required this.tag,
    required this.discount,
    required this.title,
    required this.cta,
    this.imageUrl,
    this.link,
    this.flow,
    this.mediaType = 'image',
  });

  final String id;
  final String tag;
  final String discount;
  final String title;
  final String cta;

  /// Added 2026-09-21 per explicit request ("the banners and advertisement
  /// could allow admin to upload video and images... and that should be
  /// reflected in mobile application"): mirrors
  /// [MobileMediaItem.mediaType] — 'image' or 'video' — for whichever
  /// admin-uploaded asset [imageUrl] actually points at, so home_screen.dart
  /// knows whether to render a still image or a looping video.
  final String mediaType;

  /// Added 2026-09-19 — carries [MobileMediaItem.flow] through for items
  /// sourced from the admin's mobile banners/ads (null for the web
  /// `offers` section, which has no such field). See that field's doc
  /// comment for the full story.
  final String? flow;

  /// The real admin-uploaded banner image for this offer card. Mirrors the
  /// web app's `offers.items[].image` (see LandingPage.jsx's "Promotional
  /// Offers Row": "each card is a single admin-uploaded banner image (like
  /// a real ad), no code-drawn discount/countdown/coupon text on top of
  /// it") — added 2026-09-16 so the mobile carousel can finally show that
  /// same real photo instead of only merging the offer's text onto a
  /// static gradient template. Falls back to `image_url` (the backend's
  /// resolved-CDN-URL sibling key from settings_hub's `_resolve_image_urls`)
  /// when `image` itself isn't already a full URL.
  final String? imageUrl;

  /// Admin-configured click-through target (e.g. "?category=cleaning" or a
  /// full URL) — parsed for completeness but not yet routed anywhere in the
  /// app; tap behavior still resolves against the live category list (see
  /// `_PromoBannerSlide._handleTap` in home_screen.dart) so a banner never
  /// dead-ends even when this field is empty or points at a web-only route.
  final String? link;

  factory HomeOffer.fromJson(Map<String, dynamic> json) {
    // Fixed 2026-09-21 — root cause of "video not playing, shows the
    // default icon": settings_hub's `_resolve_image_urls` (backend) sends
    // BOTH `image` (the raw Supabase Storage path this was originally
    // uploaded to, e.g. "homepage/mobile-banners/abc123.mp4") AND
    // `image_url` (that path already resolved to the real, fetchable CDN
    // URL) for every media field. This used to prefer the raw `image`
    // value whenever present — for a still image that "worked" only
    // because AppRemoteImage's ImageUrlHelper.resolve() happens to
    // re-prefix any relative-looking path with Env.mediaBaseUrl (the
    // customer API host, NOT the Supabase Storage bucket), which is
    // usually the wrong host entirely, and the wrong path shape
    // (`https://customer.caldimservices.online/homepage/...` isn't a
    // route this backend serves) — the image likely wasn't loading
    // correctly either, silently swallowed by AppRemoteImage's own
    // semantic-icon fallback. BannerMedia's video path builds a
    // VideoPlayerController straight from this URL with no such
    // resolve-and-recover step, so a raw storage path there fails outright
    // instead of quietly showing a placeholder icon in its place — the
    // "default icon" the report describes. Preferring the already-resolved
    // `image_url` fixes both.
    final rawImage = (json['image_url'] ?? json['image'] ?? '').toString();
    final rawMediaType = (json['mediaType'] ?? '').toString().trim().toLowerCase();
    return HomeOffer(
      id: (json['id'] ?? '').toString(),
      tag: (json['tag'] ?? '').toString(),
      discount: (json['discount'] ?? '').toString(),
      title: (json['title'] ?? '').toString(),
      cta: (json['cta'] ?? 'Book Now →').toString(),
      imageUrl: rawImage.isNotEmpty ? rawImage : null,
      link: (json['link'] ?? '').toString().isNotEmpty
          ? (json['link'] ?? '').toString()
          : null,
      mediaType: rawMediaType == 'video' ? 'video' : 'image',
    );
  }
}

/// A single mobile-only image + optional link, from the admin's "Mobile
/// App" section (config['mobile']['banners'] / config['mobile']['ads']).
/// Added 2026-09-17 per explicit request ("add a side section 'Mobile' ...
/// give the access to upload the banners, advertisement, top cards
/// [Groceries, Services] images") — kept separate from [HomeOffer] since
/// these items carry no discount/tag/title copy at all, unlike the web's
/// "offers" section: the mobile admin tabs only ever collect an image and
/// a link.
class MobileMediaItem {
  const MobileMediaItem({
    required this.id,
    this.imageUrl,
    this.link,
    this.enabled = true,
    this.flow,
    this.mediaType = 'image',
  });

  final String id;
  final String? imageUrl;
  final String? link;
  final bool enabled;

  /// Added 2026-09-21 per explicit request ("the banners and advertisement
  /// could allow admin to upload video and images... and that should be
  /// reflected in mobile application"): 'image' or 'video' — which kind of
  /// asset [imageUrl] points at. The admin panel's upload endpoint tags
  /// each upload with this (HomePageImageUploadAPIView's `media_type`
  /// response field), and HomePageCustomizerPage.jsx stores it on the
  /// banner/ad item as `mediaType`. Defaults to 'image' for any item saved
  /// before this field existed, so nothing already published changes
  /// behavior.
  final String mediaType;

  /// Added 2026-09-19 per explicit request ("i want to show the separate
  /// advertisement... this too separate to both services and grocery...
  /// give access to admin panel to update dynamically"): the admin's
  /// "Show On" dropdown for this banner/ad (HomePageCustomizerPage.jsx) —
  /// 'services', 'groceries', or null/'both' for no restriction. This
  /// replaces the earlier client-side guess (matching keywords in [link])
  /// with the admin's real, explicit choice; home_screen.dart still falls
  /// back to the keyword guess only for items saved before this field
  /// existed (where this is null and the link happens to look grocery
  /// -flavored), so nothing already published silently disappears.
  final String? flow;

  factory MobileMediaItem.fromJson(Map<String, dynamic> json) {
    // See the matching fix/comment in HomeOffer.fromJson above — same bug,
    // same fix: prefer the already-resolved `image_url` over the raw
    // Supabase Storage path in `image`.
    final rawImage = (json['image_url'] ?? json['image'] ?? '').toString();
    final rawLink = (json['link'] ?? '').toString();
    final rawFlow = (json['flow'] ?? '').toString().trim().toLowerCase();
    final rawMediaType = (json['mediaType'] ?? '').toString().trim().toLowerCase();
    return MobileMediaItem(
      id: (json['id'] ?? '').toString(),
      imageUrl: rawImage.isNotEmpty ? rawImage : null,
      link: rawLink.isNotEmpty ? rawLink : null,
      enabled: json['enabled'] != false,
      flow: (rawFlow == 'services' || rawFlow == 'groceries' || rawFlow == 'both' || rawFlow == 'all')
          ? rawFlow
          : null,
      mediaType: rawMediaType == 'video' ? 'video' : 'image',
    );
  }
}

/// One quick-access card at the top of the Home screen (originally just
/// "Groceries" / "Services", now an admin-managed, freely add/remove/
/// editable list — config['mobile']['topCards']).
///
/// Fixed 2026-09-18 per explicit request ("Top cards 'Groceries' and
/// 'Services' could be editable like add new, delete and make text also
/// editable from admin panel"): this used to be a fixed `MobileTopCard`
/// pair (`groceryTopCard`/`serviceTopCard` on [HomepageConfig]) with only
/// an image+link, no admin-editable label — the two cards' names were
/// hardcoded strings in home_screen.dart itself. Now this mirrors
/// [MobileMediaItem]'s shape plus a real `label`, and the admin's list
/// (any length, any labels) drives the Home screen row directly.
class MobileTopCardItem {
  const MobileTopCardItem({
    required this.id,
    required this.label,
    this.imageUrl,
    this.link,
    this.enabled = true,
  });

  final String id;
  final String label;
  final String? imageUrl;
  final String? link;
  final bool enabled;

  factory MobileTopCardItem.fromJson(Map<String, dynamic> json) {
    // Same fix as HomeOffer.fromJson/MobileMediaItem.fromJson above:
    // prefer the already-resolved `image_url` over the raw storage path.
    final rawImage = (json['image_url'] ?? json['image'] ?? '').toString();
    final rawLink = (json['link'] ?? '').toString();
    return MobileTopCardItem(
      id: (json['id'] ?? '').toString(),
      label: (json['label'] ?? '').toString(),
      imageUrl: rawImage.isNotEmpty ? rawImage : null,
      link: rawLink.isNotEmpty ? rawLink : null,
      enabled: json['enabled'] != false,
    );
  }
}

/// One admin-authored "Bestsellers" tile from the Home screen's Groceries
/// strip (config['mobile']['bestsellers']).
///
/// Added 2026-09-23 per explicit request ("make the 'Best Seller' has
/// reliable data and the counts... give privilege to admin to update this
/// from the admin panel"): this strip used to be built ENTIRELY from the
/// separate Vendor Grocery Hub's own live product feed
/// (`groceryHubCategoriesProvider`, grouped client-side by whatever
/// category string that hub's products happened to carry) — the admin here
/// had no control over which tiles showed or what count they displayed.
/// [productCount] is admin-entered rather than computed, since that's
/// exactly what made the old tiles' counts unreliable.
///
/// Fixed 2026-09-23 (real-device screenshot vs. the reference screenshot,
/// "the best seller should have been updated like this by the admin"): a
/// tile in the reference is a 2x2 GRID of up to 4 product photos, not one
/// flat image — the first version of this only let the admin upload a
/// single [imageUrl]. [thumbnails] (up to 4 images) is now what the admin
/// actually fills in and what the tile renders, matching
/// `_GroceryHubBestsellerTile`'s look exactly. [imageUrl] stays only to
/// parse a config saved before this change (upgraded in memory to a
/// single-item [thumbnails] list) so nothing already published breaks.
class MobileBestsellerItem {
  const MobileBestsellerItem({
    required this.id,
    required this.title,
    this.thumbnails,
    this.productCount = 0,
    this.link,
    this.enabled = true,
  });

  final String id;
  final String title;

  /// Up to 4 admin-uploaded product photos, rendered as a 2x2 grid — see
  /// `_AdminBestsellerTile` in home_screen.dart.
  final List<String>? thumbnails;
  final int productCount;
  final String? link;
  final bool enabled;

  factory MobileBestsellerItem.fromJson(Map<String, dynamic> json) {
    String? resolveImage(dynamic raw) {
      final s = (raw ?? '').toString().trim();
      return s.isEmpty ? null : s;
    }

    // Same fix as HomeOffer.fromJson above: prefer the already-resolved
    // CDN URLs (`thumbnails_url`, built server-side by
    // settings_hub/views_homepage.py's `_resolve_image_urls` the same way
    // it already does for `collageImages_url`) over the raw Supabase
    // Storage paths in `thumbnails` — a raw path resolves against the
    // wrong host from this app.
    final rawThumbnails = json['thumbnails_url'] ?? json['thumbnails'];
    List<String> thumbnails;
    if (rawThumbnails is List) {
      thumbnails = rawThumbnails
          .map((t) {
            if (t is Map) {
              return resolveImage(t['image_url'] ?? t['image']);
            }
            return resolveImage(t);
          })
          .whereType<String>()
          .toList();
    } else {
      // Upgrade a config saved before `thumbnails` existed — the old
      // single `image`/`image_url` field.
      final legacy = resolveImage(json['image_url'] ?? json['image']);
      thumbnails = legacy != null ? [legacy] : const [];
    }

    final rawLink = (json['link'] ?? '').toString();
    final rawCount = json['productCount'];
    return MobileBestsellerItem(
      id: (json['id'] ?? '').toString(),
      title: (json['title'] ?? '').toString(),
      thumbnails: thumbnails,
      productCount: rawCount is num
          ? rawCount.toInt()
          : int.tryParse(rawCount?.toString() ?? '') ?? 0,
      link: rawLink.isNotEmpty ? rawLink : null,
      enabled: json['enabled'] != false,
    );
  }
}

/// One admin-curated product carousel on the Grocery Home screen
/// (config['mobile']['grocerySections']) — replaces the old "Essential
/// Picks" strip.
///
/// Added 2026-09-30 per explicit request ("give the privilege to the
/// customer admin to set up the products in UI... user able to enter
/// name... choose how the data should show and which category should
/// show... user can select multiple sub-category"): [categoryIds] are
/// Seller Hub Marketplace category ids (any mix of root/sub-category/leaf
/// — see [MarketplaceHomeSection] in marketplace_catalog_repository.dart),
/// picked read-only from the admin's own category picker; this never
/// writes to that tree, only curates which of its existing nodes feed this
/// section and how.
///
/// Extended 2026-10-05 (Grocery Home Section Builder) from a 2-value
/// `layout` to the full [GrocerySectionLayout] vocabulary, plus a
/// `configuration` map for per-layout settings — currently just
/// `max_products`, read by [maxProducts]. Both changes are additive: a
/// section saved before this upgrade has no `configuration` key and a
/// `layout` of `horizontal`/`grid`, and parses here exactly as it always
/// did (see [GrocerySectionLayoutX.fromRaw]'s backward-compatibility note).
///
/// Extended again 2026-10-05 (same day, improvement pass) with banner
/// fields for the Banner + Product Rail layout, read from
/// `configuration.image`/`.image_url`/`.banner_title`/`.banner_subtitle`/
/// `.banner_cta_text`/`.banner_cta_link`. These reuse the exact same
/// `image`/`image_url` convention every other admin-uploaded image on this
/// Home screen already uses (HomePageConfigAPIView's `_resolve_image_urls`
/// auto-resolves any `image` key to a sibling `image_url`, recursively,
/// with zero backend schema change needed — see
/// `settings_hub/views_homepage.py`) — [bannerImageUrl] prefers the
/// resolved `image_url`, falling back to the raw `image` path only if the
/// backend hasn't resolved it (same "prefer image_url over image" fix
/// already applied to [HomeOffer]/[MobileMediaItem]/[MobileTopCardItem]
/// above). All five are optional and default empty, so a section saved
/// before this upgrade (or any non-banner layout) parses exactly as before.
class MobileGrocerySection {
  const MobileGrocerySection({
    required this.id,
    required this.title,
    this.layout = GrocerySectionLayout.horizontalCarousel,
    this.categoryIds = const [],
    this.productIds = const [],
    this.maxProducts = 30,
    this.configuredMaxProducts,
    this.enabled = true,
    this.bannerImageUrl,
    this.bannerTitle = '',
    this.bannerSubtitle = '',
    this.bannerCtaText = '',
    this.bannerCtaLink = '',
    this.showProductImage = true,
    this.showProductPrice = true,
    this.showProductDiscount = true,
    this.showAddButton = true,
    this.showSeeAll = false,
    this.categoryTileColumns = 3,
    this.showCategoryImage = true,
    this.showCategoryName = true,
    this.showCategoryProductCount = true,
  });

  final String id;
  final String title;
  final GrocerySectionLayout layout;
  final List<int> categoryIds;

  /// Added 2026-10-05 (Phase B, layout-aware config). Non-empty means this
  /// product-driven section is in "Specific Products" source mode
  /// (`configuration.product_source == 'products'`) — an admin-curated,
  /// order-preserving list of exact products, resolved via
  /// [marketplaceProductsByIdsProvider] instead of the category merge
  /// [marketplaceMergedProductsProvider] uses for "Categories" mode (the
  /// default, and the only mode any section saved before this field
  /// existed can be in — [categoryIds] then drives the section exactly as
  /// it always did).
  final List<int> productIds;

  /// Caps how many merged products this section ever renders/fetches —
  /// the "don't load the entire catalog just because a section exists"
  /// performance rule. Admin-configurable (`configuration.max_products`);
  /// falls back to 30 for sections saved before this field existed.
  final int maxProducts;

  /// The raw `configuration.max_products` value, or null when that key was
  /// never set at all. Added 2026-10-05 for [_SplitFeaturedLayout]
  /// specifically: that layout's own historical default was always exactly
  /// 2 cards (`.take(2)`, never configurable), not [maxProducts]' generic
  /// 30 — using [maxProducts]' default here would have silently jumped
  /// every Split Featured section saved before today from 2 cards to 3.
  /// [maxProducts] itself is untouched and still defaults to 30 for every
  /// other layout, exactly as before.
  final int? configuredMaxProducts;
  final bool enabled;

  /// Resolved CDN URL for the section's banner image (Banner + Product
  /// Rail only) — null when no banner image is configured.
  final String? bannerImageUrl;
  final String bannerTitle;
  final String bannerSubtitle;
  final String bannerCtaText;

  /// Raw admin link string in the same `?category=<slug>` / `/products/<slug>` / `https://...` convention [handleAdminLinkTap] (shared/
  /// navigation/admin_link_resolver.dart) already interprets for every
  /// other admin-configured link on this Home screen.
  final String bannerCtaLink;

  /// Added 2026-10-05 (Phase B, layout-aware config) — the spec's
  /// "Display" checkbox group for Horizontal Carousel / Grid 3 / Grid 2
  /// (via [ProductCard]'s matching flags) and Compact List / Quick Add
  /// List (via `_ProductRow` in grocery_section_layouts.dart). All default
  /// to exactly what every section already rendered before these existed
  /// — image/price/discount/add-button visible, no "See All" row — so a
  /// section saved before today parses and renders identically.
  final bool showProductImage;
  final bool showProductPrice;
  final bool showProductDiscount;
  final bool showAddButton;
  final bool showSeeAll;

  /// Added 2026-10-05 (Phase B, Sections 13-14) — Category Tile Grid /
  /// Circular Category Rail only. `categoryTileColumns` (Category Tile
  /// Grid's "Columns" dropdown) defaults to 3, matching that layout's
  /// original hardcoded `crossAxisCount`, so a section saved before this
  /// existed renders an identical 3-across grid. The two category-display
  /// flags both default true, matching every category tile/avatar's
  /// original always-shown name and product count.
  final int categoryTileColumns;
  final bool showCategoryImage;
  final bool showCategoryName;
  final bool showCategoryProductCount;

  bool get isGrid => layout == GrocerySectionLayout.grid3;

  /// True when this section should resolve its products from
  /// [productIds] directly rather than merging by [categoryIds].
  bool get usesSpecificProducts => productIds.isNotEmpty;

  /// Whether there's an actual banner to show (image, title or subtitle) —
  /// a Banner + Product Rail section with none of these configured falls
  /// back to rendering a plain product rail instead of an empty banner box.
  bool get hasBanner =>
      (bannerImageUrl != null && bannerImageUrl!.isNotEmpty) ||
      bannerTitle.isNotEmpty ||
      bannerSubtitle.isNotEmpty;

  factory MobileGrocerySection.fromJson(Map<String, dynamic> json) {
    final rawIds = json['category_ids'];
    final categoryIds = rawIds is List
        ? rawIds.map((v) => int.tryParse(v.toString())).whereType<int>().toList()
        : const <int>[];
    final configuration = json['configuration'];
    final config = configuration is Map ? Map<String, dynamic>.from(configuration) : const <String, dynamic>{};
    final rawMaxProducts = config['max_products'];
    final maxProducts = int.tryParse(rawMaxProducts?.toString() ?? '');
    final rawBannerImageUrl = (config['image_url'] ?? config['image'] ?? '').toString().trim();
    // "Specific Products" entries are written by the admin as either a bare
    // id or `{id, title}` (the title is only there so the admin UI can show
    // a chip without re-fetching) — accept both shapes here.
    final rawProductIds = config['product_ids'];
    final productIds = rawProductIds is List
        ? rawProductIds
            .map((v) => v is Map ? v['id'] : v)
            .map((v) => int.tryParse(v?.toString() ?? ''))
            .whereType<int>()
            .toList()
        : const <int>[];
    // Display checkboxes -- an absent key means "on" for every flag except
    // `see_all` (absent means "off"), so a section saved before this
    // existed, or one that never touched this group, renders exactly as it
    // always did.
    final rawDisplay = config['display'];
    final display = rawDisplay is Map ? Map<String, dynamic>.from(rawDisplay) : const <String, dynamic>{};
    bool displayFlag(String key, bool fallback) {
      final v = display[key];
      if (v is bool) return v;
      return fallback;
    }

    return MobileGrocerySection(
      id: (json['id'] ?? '').toString(),
      title: (json['title'] ?? '').toString(),
      layout: GrocerySectionLayoutX.fromRaw(json['layout']?.toString()),
      categoryIds: categoryIds,
      productIds: productIds,
      maxProducts: (maxProducts != null && maxProducts > 0) ? maxProducts : 30,
      configuredMaxProducts: (maxProducts != null && maxProducts > 0) ? maxProducts : null,
      enabled: json['enabled'] != false,
      bannerImageUrl: rawBannerImageUrl.isEmpty ? null : rawBannerImageUrl,
      bannerTitle: (config['banner_title'] ?? '').toString(),
      bannerSubtitle: (config['banner_subtitle'] ?? '').toString(),
      bannerCtaText: (config['banner_cta_text'] ?? '').toString(),
      bannerCtaLink: (config['banner_cta_link'] ?? '').toString(),
      showProductImage: displayFlag('image', true),
      showProductPrice: displayFlag('price', true),
      showProductDiscount: displayFlag('discount', true),
      showAddButton: displayFlag('add_button', true),
      showSeeAll: displayFlag('see_all', false),
      categoryTileColumns: (() {
        final raw = int.tryParse(config['columns']?.toString() ?? '');
        return (raw != null && raw >= 2 && raw <= 4) ? raw : 3;
      })(),
      showCategoryImage: displayFlag('category_image', true),
      showCategoryName: displayFlag('category_name', true),
      showCategoryProductCount: displayFlag('category_product_count', true),
    );
  }
}

/// One admin-configured trust/quick badge from the homepage CMS (config.hero.quickBadges).
class QuickBadgeItem {
  const QuickBadgeItem({
    required this.id,
    required this.title,
    required this.subtitle,
    this.icon,
    this.iconName,
    this.badgeColor,
    this.link,
  });

  final String id;
  final String title;
  final String subtitle;
  final String? icon;
  final String? iconName;
  final String? badgeColor;
  final String? link;

  String? get resolvedIcon => iconName ?? icon;

  factory QuickBadgeItem.fromJson(Map<String, dynamic> json) {
    return QuickBadgeItem(
      id: (json['id'] ?? '').toString(),
      title: (json['title'] ?? json['text'] ?? '').toString(),
      subtitle: (json['subtitle'] ?? '').toString(),
      icon: (json['icon'] ?? json['icon_name'] ?? '').toString(),
      iconName: (json['icon_name'] ?? json['icon'] ?? '').toString(),
      badgeColor: (json['badge_color'] ?? json['color'] ?? '').toString(),
      link: (json['link'] ?? json['url'] ?? '').toString(),
    );
  }
}

/// The subset of the homepage CMS config this app actually consumes.
class HomepageConfig {
  const HomepageConfig({
    required this.offers,
    this.mobileBanners = const [],
    this.mobileAds = const [],
    this.heroVideoServices,
    this.heroVideoGroceries,
    this.topCards = const [],
    this.bestsellers = const [],
    this.grocerySections = const [],
    this.greetingServices = '',
    this.greetingGroceries = '',
    this.quickBadges = const [],
  });

  final List<HomeOffer> offers;
  final List<QuickBadgeItem> quickBadges;

  /// Added 2026-10-06 per explicit request ("Vanakkam Hosur" / "Welcome,
  /// foodie!" greeting headline shown above the banner, "customized by the
  /// admin through the adminpannel privilage"): admin-authored, per-mode
  /// greeting text (config.mobile.greetingServices / .greetingGroceries) —
  /// empty by default, in which case home_screen.dart falls back to its own
  /// existing mode-themed heading rather than rendering a blank line.
  final String greetingServices;
  final String greetingGroceries;

  /// Mobile-only banner carousel images, from the admin's "Mobile App ▸
  /// App Banners" tab. Preferred over [offers] for the Home screen
  /// carousel whenever non-empty (see home_screen.dart's
  /// `_PromoBannerCarousel`), so mobile creative never has to be mixed
  /// into the web's "Promotional Offers" section.
  final List<MobileMediaItem> mobileBanners;

  /// Mobile-only advertisement card(s), from the "Mobile App ▸
  /// Advertisement" tab. Rendered as an extra card on Home only when at
  /// least one enabled item has an image.
  final List<MobileMediaItem> mobileAds;

  /// Dedicated per-mode hero video/image slot (config.mobile.heroVideos
  /// .services / .groceries, 2026-10-09) — separate from the banner carousel
  /// so the admin can set one full-bleed looping clip for each Home mode.
  final MobileMediaItem? heroVideoServices;
  final MobileMediaItem? heroVideoGroceries;

  /// The Home screen's quick-access card row (originally always exactly
  /// "Groceries" + "Services") — now a fully admin-managed list: any
  /// number of cards, each with its own editable label, image and link.
  final List<MobileTopCardItem> topCards;

  /// The Home screen's "Bestsellers" tiles (Groceries mode) — admin-
  /// authored, with a manually-entered product count. Preferred over the
  /// auto-grouped Vendor Grocery Hub tiles (`groceryHubCategoriesProvider`)
  /// whenever non-empty — see home_screen.dart's Bestsellers section.
  final List<MobileBestsellerItem> bestsellers;

  /// The Grocery Home screen's admin-curated product-carousel sections —
  /// see [MobileGrocerySection] doc comment. Preferred over
  /// `marketplaceHomeSectionsProvider`'s auto-generated "one section per
  /// real sub-category" fallback whenever at least one entry here is
  /// enabled — see home_screen.dart's `_MarketplaceHomeSections`.
  final List<MobileGrocerySection> grocerySections;
}

class HomepageRepository {
  HomepageRepository({required this.api});

  final ApiClient api;

  /// GET /api/settings/homepage/ — public, no auth required.
  Future<Result<HomepageConfig>> getHomepageConfig() async {
    try {
      final response = await api.get('/settings/homepage/');
      return ResponseNormalizer.extract(response, (data) {
        final map = data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{};
        // The view wraps the actual config under a top-level "config" key
        // (see HomePageConfigAPIView.get) inside the already-unwrapped
        // {success, config} body — ResponseNormalizer only unwraps the
        // outer {success, data/config} envelope shapes it recognises, so
        // this endpoint's own "config" key still needs unwrapping here.
        final config = map['config'] is Map
            ? Map<String, dynamic>.from(map['config'] as Map)
            : map;

        final offersSection = config['offers'] is Map
            ? Map<String, dynamic>.from(config['offers'] as Map)
            : <String, dynamic>{};
        final rawItems = offersSection['items'];
        final items = rawItems is List
            ? rawItems
                .whereType<Map>()
                .map((m) => HomeOffer.fromJson(Map<String, dynamic>.from(m)))
                .where((o) => o.title.isNotEmpty)
                .toList()
            : <HomeOffer>[];

        // Added 2026-09-17: the admin's "Mobile App" section — banners,
        // advertisement, and the Groceries/Services top-card images.
        final mobileSection = config['mobile'] is Map
            ? Map<String, dynamic>.from(config['mobile'] as Map)
            : <String, dynamic>{};

        List<MobileMediaItem> parseMediaList(dynamic raw) {
          if (raw is! List) return const [];
          return raw
              .whereType<Map>()
              .map((m) => MobileMediaItem.fromJson(Map<String, dynamic>.from(m)))
              .where((item) => item.enabled && item.imageUrl != null)
              .toList();
        }

        final mobileBanners = parseMediaList(mobileSection['banners']);
        final mobileAds = parseMediaList(mobileSection['ads']);

        MobileMediaItem? parseHeroVideo(dynamic raw) {
          if (raw is! Map) return null;
          final item = MobileMediaItem.fromJson(Map<String, dynamic>.from(raw));
          return (item.enabled && item.imageUrl != null) ? item : null;
        }

        final rawHero = mobileSection['heroVideos'];
        final heroMap = rawHero is Map ? Map<String, dynamic>.from(rawHero) : <String, dynamic>{};
        final heroVideoServices = parseHeroVideo(heroMap['services']);
        final heroVideoGroceries = parseHeroVideo(heroMap['groceries']);

        // Fixed 2026-09-18: topCards is now an admin-managed list (any
        // length, editable labels) rather than a fixed {groceries,
        // services} object. Still accepts that older object shape here —
        // a config published before this change — and upgrades it in
        // memory to the same 2-item list shape, so nothing the admin
        // already uploaded is lost; the next admin save rewrites it as a
        // real list.
        final rawTopCards = mobileSection['topCards'];
        List<MobileTopCardItem> topCards;
        if (rawTopCards is List) {
          topCards = rawTopCards
              .whereType<Map>()
              .map((m) => MobileTopCardItem.fromJson(Map<String, dynamic>.from(m)))
              .where((c) => c.enabled)
              .toList();
        } else if (rawTopCards is Map) {
          final legacy = Map<String, dynamic>.from(rawTopCards);
          topCards = [
            if (legacy['groceries'] is Map)
              MobileTopCardItem.fromJson({
                'id': 'groceries',
                'label': 'Groceries',
                ...Map<String, dynamic>.from(legacy['groceries'] as Map),
              }),
            if (legacy['services'] is Map)
              MobileTopCardItem.fromJson({
                'id': 'services',
                'label': 'Services',
                ...Map<String, dynamic>.from(legacy['services'] as Map),
              }),
          ];
        } else {
          topCards = const [];
        }

        // Added 2026-09-23: the admin-authored "Bestsellers" tiles — see
        // [MobileBestsellerItem] doc comment.
        final rawBestsellers = mobileSection['bestsellers'];
        final bestsellers = rawBestsellers is List
            ? rawBestsellers
                .whereType<Map>()
                .map((m) => MobileBestsellerItem.fromJson(Map<String, dynamic>.from(m)))
                .where((b) => b.enabled && b.title.isNotEmpty)
                .toList()
            : <MobileBestsellerItem>[];

        // Added 2026-09-30: the admin-curated "Grocery Home Sections" —
        // see [MobileGrocerySection] doc comment.
        final rawGrocerySections = mobileSection['grocerySections'];
        final grocerySections = rawGrocerySections is List
            ? rawGrocerySections
                .whereType<Map>()
                .map((m) => MobileGrocerySection.fromJson(Map<String, dynamic>.from(m)))
                .where((s) => s.enabled && s.title.isNotEmpty && s.categoryIds.isNotEmpty)
                .toList()
            : <MobileGrocerySection>[];

        final heroSection = config['hero'] is Map ? config['hero'] as Map : null;
        final rawQuickBadges = heroSection?['quickBadges'] ?? config['quickBadges'];
        final quickBadges = (rawQuickBadges is List)
            ? rawQuickBadges
                .whereType<Map>()
                .map((m) => QuickBadgeItem.fromJson(Map<String, dynamic>.from(m)))
                .where((b) => b.title.isNotEmpty)
                .toList()
            : const <QuickBadgeItem>[];

        return HomepageConfig(
          offers: items,
          mobileBanners: mobileBanners,
          mobileAds: mobileAds,
          heroVideoServices: heroVideoServices,
          heroVideoGroceries: heroVideoGroceries,
          topCards: topCards,
          bestsellers: bestsellers,
          grocerySections: grocerySections,
          greetingServices: (mobileSection['greetingServices'] ?? '').toString(),
          greetingGroceries: (mobileSection['greetingGroceries'] ?? '').toString(),
          quickBadges: quickBadges,
        );
      });
    } on Exception catch (e) {
      return Failure(_toError(e));
    }
  }

  ApiError _toError(Object e) {
    if (e is ApiError) return e;
    return UnknownError(e.toString());
  }
}

final homepageRepositoryProvider = Provider<HomepageRepository>((ref) {
  return HomepageRepository(api: ref.watch(apiClientProvider));
});

/// Live, admin-managed homepage promotions/offers config. Never throws to
/// its watchers on failure — home_screen.dart falls back to its existing
/// static banner copy whenever this comes back empty/errored, the same
/// "fail open, never blank the screen" pattern used elsewhere in this app
/// (see catalog_repository.dart's last-known-good guard).
final homepageConfigProvider = FutureProvider<HomepageConfig>((ref) async {
  final repo = ref.watch(homepageRepositoryProvider);
  final result = await repo.getHomepageConfig();
  return switch (result) {
    Success(:final data) => data,
    Failure(:final error) => throw error,
  };
});
