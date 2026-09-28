import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/api_error.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/response_normalizer.dart';

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

/// The subset of the homepage CMS config this app actually consumes.
class HomepageConfig {
  const HomepageConfig({
    required this.offers,
    this.mobileBanners = const [],
    this.mobileAds = const [],
    this.topCards = const [],
    this.bestsellers = const [],
  });

  final List<HomeOffer> offers;

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

  /// The Home screen's quick-access card row (originally always exactly
  /// "Groceries" + "Services") — now a fully admin-managed list: any
  /// number of cards, each with its own editable label, image and link.
  final List<MobileTopCardItem> topCards;

  /// The Home screen's "Bestsellers" tiles (Groceries mode) — admin-
  /// authored, with a manually-entered product count. Preferred over the
  /// auto-grouped Vendor Grocery Hub tiles (`groceryHubCategoriesProvider`)
  /// whenever non-empty — see home_screen.dart's Bestsellers section.
  final List<MobileBestsellerItem> bestsellers;
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

        return HomepageConfig(
          offers: items,
          mobileBanners: mobileBanners,
          mobileAds: mobileAds,
          topCards: topCards,
          bestsellers: bestsellers,
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
