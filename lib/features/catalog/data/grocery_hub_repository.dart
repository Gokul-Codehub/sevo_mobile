import 'package:decimal/decimal.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../config/env.dart';
import '../../../core/errors/api_error.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/response_normalizer.dart';
import '../../../core/storage/secure_storage.dart';
import '../../auth/domain/auth_notifier.dart';
import '../domain/catalog_models.dart';
import 'marketplace_catalog_repository.dart';

/// Vendor Grocery Hub — Public Storefront integration.
///
/// Added 2026-09-19 per the user-supplied
/// `GROCERY_CUSTOMER_MOBILE_INTEGRATION_API_GUIDE.md`: a completely
/// separate backend/app (`/api/workforce/...`, same host as everything
/// else — `ApiClient` already prefixes every path with `/api/`, so
/// `workforce/public/stores/` resolves to
/// `https://customer.caldimservices.online/api/workforce/public/stores/`)
/// from a real seller/vendor marketplace, distinct from this app's own
/// catalog (`catalog_repository.dart`, Category → Service → Package).
///
/// Deliberately uses ONLY the "Public Storefront" endpoints
/// (`/public/stores/`, `/public/stores/<slug>/`, `/public/cart/`) — the
/// guide's other namespace, "Marketplace APIs" (`/marketplace/*`), requires
/// a server-side integration secret (`Authorization: Bearer <API_KEY>` /
/// `X-Workforce-Webhook-Secret`) meant for server-to-server sync, never for
/// embedding in a distributed mobile app. The Public Storefront endpoints
/// need no auth at all and already return everything a browsing/ordering
/// customer needs (products, images, prices, deals, coupons), so nothing
/// is lost by not using the secret-gated endpoints.
///
/// This only ever supplies the *packaged grocery* items this vendor hub
/// actually sells (dairy, chips, bakery, oil, ice cream, etc. — see the
/// guide's own examples). It is NOT used for, and never overrides, this
/// app's existing "Essential Picks" fresh Vegetables & Fruits strip (still
/// [groceryProduceProvider], from the real catalog) or anything in
/// Services mode — those keep reading their own existing data sources
/// entirely untouched.

/// Resolves a possibly-relative media path from the Grocery Hub backend
/// into a fully-qualified URL against [Env.groceryHubBaseUrl] — this
/// backend's own host, NOT [Env.mediaBaseUrl] (the customer backend
/// `AppRemoteImage`/`ImageUrlHelper` resolves everything else against).
/// Without this, a relative `/media/seller_products/...` path from this
/// hub would silently 404 by resolving against the wrong host.
String? _resolveVendorMedia(dynamic raw) {
  final trimmed = (raw ?? '').toString().trim();
  if (trimmed.isEmpty) return null;
  if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
    return trimmed;
  }
  return trimmed.startsWith('/')
      ? '${Env.groceryHubBaseUrl}$trimmed'
      : '${Env.groceryHubBaseUrl}/$trimmed';
}

class GroceryHubProduct {
  const GroceryHubProduct({
    required this.id,
    required this.name,
    required this.category,
    this.image,
    required this.price,
    this.mrp,
    this.hasDeal = false,
    this.dealBadge,
    this.discountPercent = 0,
    this.unit,
    this.inStock = true,
    this.marketplaceItem,
  });

  /// When set, this tile is backed by an approved Seller Hub Marketplace
  /// product, and [toServiceItem] returns that item as-is so ADD / cart /
  /// checkout use the marketplace ids (see MarketplaceProduct) rather than
  /// the legacy Grocery Hub range.
  final ServiceItem? marketplaceItem;

  /// Builds a Bestsellers tile from an approved marketplace product.
  factory GroceryHubProduct.fromMarketplace(MarketplaceProduct p) {
    final hasMrp = p.hasStrikeThroughMrp;
    final price = p.sellingPrice.toDouble();
    final mrp = p.mrp?.toDouble();
    return GroceryHubProduct(
      id: p.id,
      name: p.title,
      category: (p.categoryName ?? '').trim(),
      image: p.galleryImages.isNotEmpty ? p.galleryImages.first : p.primaryImage,
      price: price,
      mrp: hasMrp ? mrp : null,
      discountPercent: hasMrp && mrp != null && mrp > 0
          ? (((mrp - price) / mrp) * 100).round()
          : 0,
      unit: p.packSize ?? p.unit,
      inStock: p.inStock,
      marketplaceItem: p.toServiceItem(),
    );
  }

  final int id;
  final String name;
  final String category;
  final String? image;
  final double price;
  final double? mrp;
  final bool hasDeal;
  final String? dealBadge;
  final int discountPercent;
  final String? unit;
  final bool inStock;

  /// Whether there's a real strike-through MRP to show (mrp present and
  /// actually higher than the selling price — never renders a "discount"
  /// that isn't one).
  bool get hasStrikeThroughMrp => mrp != null && mrp! > price;

  // Added 2026-09-19 per explicit request ("If user clicks Add buttons it
  // should append in our cart from there we can checkout the order...like
  // vegetables do"): every id from this separate vendor backend is offset
  // into its own range before being used as a [ServiceItem.id] — the
  // existing cart (CartNotifier) keys entries purely by that int id, and
  // this hub's product ids (small ints, starting near 100 per the
  // integration guide's own examples) would otherwise silently collide
  // with real catalog service ids and corrupt an unrelated cart line.
  // 900000000 is far above any realistic catalog id.
  static const int _cartIdOffset = 900000000;

  /// Converts this Grocery Hub product into the same [ServiceItem] shape
  /// the rest of the app's cart, cart badge, checkout and grocery cart
  /// screen already understand — so "ADD" here behaves exactly like it
  /// does on any other grocery item, with no separate cart/checkout path.
  /// `categorySlug` is forced to contain "grocery" so
  /// [ServiceItem.flowType] always resolves to [CatalogFlowType.grocery]
  /// for these items, regardless of this hub's own category names (e.g.
  /// "Chips & Namkeen", which wouldn't otherwise match the grocery
  /// keyword check).
  ServiceItem toServiceItem() {
    final override = marketplaceItem;
    if (override != null) return override;
    final hasMrp = hasStrikeThroughMrp;
    return ServiceItem(
      id: _cartIdOffset + id,
      title: name,
      slug: 'grocery-hub-$id',
      price: Decimal.parse((hasMrp ? mrp! : price).toStringAsFixed(2)),
      discountedPrice: hasMrp ? Decimal.parse(price.toStringAsFixed(2)) : null,
      unit: unit,
      categoryName: category,
      categorySlug: 'grocery_hub_groceries',
      imageUrl: image,
    );
  }

  factory GroceryHubProduct.fromJson(Map<String, dynamic> json) {
    double parseD(dynamic v) {
      if (v == null) return 0.0;
      return double.tryParse(v.toString()) ?? 0.0;
    }

    final rawBadge = (json['deal_badge'] ?? '').toString();
    final rawUnit = (json['unit'] ?? '').toString();
    final mrpValue = json['mrp'] != null ? parseD(json['mrp']) : null;

    return GroceryHubProduct(
      id: int.tryParse(json['id']?.toString() ?? '') ?? 0,
      name: (json['name'] ?? '').toString(),
      category: (json['category'] ?? '').toString(),
      image: _resolveVendorMedia(json['image']),
      price: parseD(json['price']),
      mrp: mrpValue,
      hasDeal: json['has_deal'] == true,
      dealBadge: rawBadge.isNotEmpty ? rawBadge : null,
      discountPercent: int.tryParse(json['discount_percent']?.toString() ?? '') ?? 0,
      unit: rawUnit.isNotEmpty ? rawUnit : null,
      inStock: json['in_stock'] != false,
    );
  }
}

class GroceryHubCoupon {
  const GroceryHubCoupon({
    required this.code,
    required this.description,
    required this.discountType,
    required this.discountValue,
    required this.minOrderAmount,
  });

  final String code;
  final String description;
  final String discountType;
  final double discountValue;
  final double minOrderAmount;

  factory GroceryHubCoupon.fromJson(Map<String, dynamic> json) {
    double parseD(dynamic v) => double.tryParse(v?.toString() ?? '') ?? 0.0;
    return GroceryHubCoupon(
      code: (json['code'] ?? '').toString(),
      description: (json['description'] ?? '').toString(),
      discountType: (json['discount_type'] ?? '').toString(),
      discountValue: parseD(json['discount_value']),
      minOrderAmount: parseD(json['min_order_amount']),
    );
  }
}

/// One row from `GET /public/stores/` — enough to pick a store; the full
/// product/coupon detail only comes from `GET /public/stores/<slug>/`.
class GroceryHubStoreSummary {
  const GroceryHubStoreSummary({
    required this.id,
    required this.storeName,
    required this.storeSlug,
    this.tagline,
    this.logoUrl,
    this.estimatedDeliveryMins,
  });

  final int id;
  final String storeName;
  final String storeSlug;
  final String? tagline;
  final String? logoUrl;
  final int? estimatedDeliveryMins;

  factory GroceryHubStoreSummary.fromJson(Map<String, dynamic> json) {
    final rawTagline = (json['tagline'] ?? '').toString();
    return GroceryHubStoreSummary(
      id: int.tryParse(json['id']?.toString() ?? '') ?? 0,
      storeName: (json['store_name'] ?? '').toString(),
      storeSlug: (json['store_slug'] ?? '').toString(),
      tagline: rawTagline.isNotEmpty ? rawTagline : null,
      logoUrl: _resolveVendorMedia(json['logo_url']),
      estimatedDeliveryMins: int.tryParse(json['estimated_delivery_mins']?.toString() ?? ''),
    );
  }
}

/// Full `GET /public/stores/<slug>/` response: store info plus its live
/// product catalog and any active coupons.
class GroceryHubStoreDetail {
  const GroceryHubStoreDetail({
    required this.storeName,
    required this.storeSlug,
    required this.isAcceptingOrders,
    required this.products,
    required this.coupons,
  });

  final String storeName;
  final String storeSlug;
  final bool isAcceptingOrders;
  final List<GroceryHubProduct> products;
  final List<GroceryHubCoupon> coupons;

  factory GroceryHubStoreDetail.fromJson(Map<String, dynamic> json) {
    final storeMap = json['store'] is Map
        ? Map<String, dynamic>.from(json['store'] as Map)
        : <String, dynamic>{};
    final rawProducts = json['products'];
    final rawCoupons = json['coupons'];

    return GroceryHubStoreDetail(
      storeName: (storeMap['store_name'] ?? '').toString(),
      storeSlug: (storeMap['store_slug'] ?? '').toString(),
      isAcceptingOrders: storeMap['is_accepting_orders'] != false,
      products: rawProducts is List
          ? rawProducts
              .whereType<Map>()
              .map((m) => GroceryHubProduct.fromJson(Map<String, dynamic>.from(m)))
              .where((p) => p.inStock && p.name.isNotEmpty)
              .toList()
          : const [],
      coupons: rawCoupons is List
          ? rawCoupons
              .whereType<Map>()
              .map((m) => GroceryHubCoupon.fromJson(Map<String, dynamic>.from(m)))
              .toList()
          : const [],
    );
  }
}

/// One category's worth of products from the Grocery Hub, grouped
/// client-side by the flat `category` string each product carries (this
/// public endpoint has no category-tree/hierarchy of its own — see the
/// guide §5.6 vs §5.2's `category_hierarchy`, which is only on the
/// secret-gated marketplace endpoint this app deliberately doesn't call).
class GroceryHubCategoryGroup {
  const GroceryHubCategoryGroup({required this.name, required this.products});

  final String name;
  final List<GroceryHubProduct> products;
}

class GroceryHubRepository {
  GroceryHubRepository({required this.api});

  final ApiClient api;

  Future<Result<List<GroceryHubStoreSummary>>> getStores() async {
    try {
      final response = await api.get('${Env.groceryHubBaseUrl}/api/workforce/public/stores/');
      return ResponseNormalizer.extract(response, (data) {
        final List<dynamic> list;
        if (data is List) {
          list = data;
        } else if (data is Map && data['results'] is List) {
          list = data['results'] as List;
        } else {
          list = const [];
        }
        return list
            .whereType<Map>()
            .map((m) => GroceryHubStoreSummary.fromJson(Map<String, dynamic>.from(m)))
            .toList();
      });
    } on Exception catch (e) {
      return Failure(_toError(e));
    }
  }

  Future<Result<GroceryHubStoreDetail>> getStoreDetail(String slug) async {
    try {
      final response = await api.get('${Env.groceryHubBaseUrl}/api/workforce/public/stores/$slug/');
      return ResponseNormalizer.extract(
        response,
        (data) => GroceryHubStoreDetail.fromJson(
          data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{},
        ),
      );
    } on Exception catch (e) {
      return Failure(_toError(e));
    }
  }

  /// Adds/updates one item in THIS HUB'S OWN separate cart (§5.6 of the
  /// integration guide) — kept here but deliberately NOT called from the
  /// "ADD" button anymore (see [ServiceItem.toServiceItem] /
  /// GroceryHubCategoryScreen): the customer asked for one unified cart,
  /// so ADD now goes straight into the app's existing [cartProvider]
  /// instead. This method stays available for whenever checkout for these
  /// items is wired to actually reach this vendor's own order system
  /// (still an open decision — see the app's conversation history) rather
  /// than only the CalServices booking backend, which has no knowledge of
  /// this vendor's inventory. A 409 `CART_STORE_CONFLICT` is a real,
  /// expected response from this endpoint (switching stores), not an
  /// error to swallow, whenever this does get called.
  Future<Result<bool>> addToCart({
    required String customerId,
    required int inventoryItemId,
    required double quantity,
    bool forceReplace = false,
  }) async {
    try {
      await api.post('${Env.groceryHubBaseUrl}/api/workforce/public/cart/', data: {
        'customer_id': customerId,
        'inventory_item_id': inventoryItemId,
        'quantity': quantity,
        'force_replace': forceReplace,
      });
      return const Success(true);
    } on Exception catch (e) {
      return Failure(_toError(e));
    }
  }

  ApiError _toError(Object e) {
    if (e is ApiError) return e;
    if (e is DioException && e.error is ApiError) {
      return e.error! as ApiError;
    }
    return UnknownError(e.toString());
  }
}

final groceryHubRepositoryProvider = Provider<GroceryHubRepository>((ref) {
  return GroceryHubRepository(api: ref.watch(apiClientProvider));
});

/// Legacy public Grocery Hub storefront (`/api/workforce/public/stores/`).
///
/// Disabled 2026-10-28 per the SEVO data-source verification (gap G3): that
/// endpoint reads a different table that ignores the platform admin's
/// approval, category-active and company-active rules, so a product the
/// admin had hidden could still reach customers through it. Home's
/// Bestsellers now come from the approved Seller Hub Marketplace instead
/// (see [groceryHubCategoriesProvider]). The repository methods above are
/// kept only so they can be re-enabled if the vendor adds the same checks.
final groceryHubStoresProvider = FutureProvider<List<GroceryHubStoreSummary>>((ref) async {
  return const <GroceryHubStoreSummary>[];
});

/// See [groceryHubStoresProvider] — no longer calls the legacy endpoint.
final primaryGroceryHubStoreProvider = FutureProvider<GroceryHubStoreDetail?>((ref) async {
  return null;
});

/// Approved, in-stock marketplace products for the Home "Bestsellers"
/// fallback: first page (100) of `GET /api/marketplace/products/`, which
/// the vendor already filters by status APPROVED, active category chain,
/// active company, price and sellable stock.
final _bestsellerMarketplaceProductsProvider =
    FutureProvider.autoDispose<List<MarketplaceProduct>>((ref) async {
  final repo = ref.watch(marketplaceCatalogRepositoryProvider);
  final result = await repo.getProducts(pageSize: 100);
  return switch (result) {
    Success(:final data) => data.products.where((p) => p.inStock).toList(),
    Failure() => const <MarketplaceProduct>[],
  };
});

/// Approved marketplace products grouped by department name, in first-seen
/// order — drives Home's "Bestsellers" tiles when the admin has not set up
/// their own. Empty (never an error) whenever there is nothing to show, so
/// Home simply omits the section.
final groceryHubCategoriesProvider = Provider<List<GroceryHubCategoryGroup>>((ref) {
  final products = ref.watch(_bestsellerMarketplaceProductsProvider).valueOrNull ?? const [];
  if (products.isEmpty) return const [];

  final byCategory = <String, List<GroceryHubProduct>>{};
  for (final p in products) {
    final item = GroceryHubProduct.fromMarketplace(p);
    if (item.category.isEmpty) continue;
    byCategory.putIfAbsent(item.category, () => []).add(item);
  }

  return byCategory.entries
      .map((e) => GroceryHubCategoryGroup(name: e.key, products: e.value))
      .toList();
});

/// The id this app sends as `customer_id` on Grocery Hub cart calls — the
/// real account id once signed in, or a stable per-device guest id
/// generated and persisted the first time it's needed (see
/// [SecureStorage.getOrCreateGroceryHubGuestId]) so a guest's Grocery Hub
/// cart survives navigating around the app before they ever sign in.
final groceryHubCustomerIdProvider = FutureProvider<String>((ref) async {
  final user = ref.watch(currentUserProvider);
  if (user != null) return user.id.toString();
  final storage = ref.watch(secureStorageProvider);
  return storage.getOrCreateGroceryHubGuestId();
});
