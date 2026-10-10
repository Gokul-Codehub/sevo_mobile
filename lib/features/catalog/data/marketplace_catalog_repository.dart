import 'package:decimal/decimal.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../config/env.dart';
import '../../../core/errors/api_error.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/response_normalizer.dart';
import '../domain/catalog_models.dart';
import 'basket_models.dart';

/// Seller Hub Marketplace catalog — the REAL, admin-managed category tree
/// for packaged groceries.
///
/// Added 2026-09-25 per explicit request: a new "Ven" vendor codebase
/// folder was connected showing the vendor's own admin ("Superadmin
/// Console" → Seller Hub → Categories) managing a proper nested category
/// tree (`workforce_api.models.SellerHubCategory`, unlimited depth, exactly
/// analogous to this app's existing Vegetable Inventory tree) with real
/// products (`SellerProduct`, APPROVED + in-stock only) filed under it.
/// The ask was to browse Groceries by that real department tree "as like
/// vegetable we had" instead of the flat, hierarchy-less list
/// [GroceryHubRepository] already uses for Home's Bestsellers tiles (that
/// repository deliberately calls the vendor's public storefront, which has
/// no category tree at all — see its own doc comment).
///
/// The vendor's actual tree data only exists behind a secret-gated
/// server-to-server endpoint (`IsMarketplaceIntegrationCaller`,
/// `/api/workforce/marketplace/...` on the Ven backend) — embedding that
/// shared secret in a distributed mobile app would be a real security
/// leak (extractable from the APK), exactly the reasoning
/// [GroceryHubRepository]'s doc comment already gives for avoiding it.
/// Instead, this repository calls the CalServices customer backend's own
/// PUBLIC proxy (`workforce_integration/marketplace_urls.py`,
/// `AllowAny`, already live at `/api/marketplace/...` on this app's normal
/// [Env.mediaBaseUrl] host) which holds the secret server-side and
/// forwards the (sanitized) vendor response — the same "backend holds the
/// secret, app never does" pattern used everywhere else in this app.
///
/// This is a SEPARATE catalog surface from [GroceryHubRepository] — both
/// stay in place: this repository is additive for the new
/// category-department browse screen and does not change Home's
/// Bestsellers tiles or the existing flat GroceryHubCategoryScreen.

/// Resolves a possibly-relative image path returned by the Seller Hub
/// Marketplace proxy against the vendor's own host (the data ultimately
/// comes from the Ven vendor backend, not this app's own media backend) —
/// same reasoning as `_resolveVendorMedia` in grocery_hub_repository.dart.
String? _resolveSellerHubMedia(dynamic raw) {
  final trimmed = (raw ?? '').toString().trim();
  if (trimmed.isEmpty) return null;
  if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
    return trimmed;
  }
  return trimmed.startsWith('/')
      ? '${Env.groceryHubBaseUrl}$trimmed'
      : '${Env.groceryHubBaseUrl}/$trimmed';
}

/// One node of the Seller Hub category tree (`_sanitize_category_node` on
/// the CalServices proxy, mirroring `SellerHubCategory` on the vendor).
class MarketplaceCategory {
  const MarketplaceCategory({
    required this.id,
    required this.name,
    required this.slug,
    this.parentId,
    this.icon,
    this.image,
    this.isLeaf = true,
    this.hasChildren = false,
    this.productCount = 0,
    this.totalProductCount = 0,
    this.children = const [],
  });

  final int id;
  final String name;
  final String slug;
  final int? parentId;
  final String? icon;
  final String? image;
  final bool isLeaf;
  final bool hasChildren;
  final int productCount;
  final int totalProductCount;
  final List<MarketplaceCategory> children;

  /// Whether this department (or anything under it) actually has sellable
  /// products right now — a department tile with zero products anywhere in
  /// its subtree is still real admin data, but not worth showing as a
  /// browsable tile in a customer-facing rail.
  bool get hasAnyProducts => totalProductCount > 0;

  factory MarketplaceCategory.fromJson(Map<String, dynamic> json) {
    int parseInt(dynamic v) => int.tryParse(v?.toString() ?? '') ?? 0;
    final rawChildren = json['children'];
    return MarketplaceCategory(
      id: parseInt(json['id']),
      name: (json['name'] ?? '').toString(),
      slug: (json['slug'] ?? '').toString(),
      parentId: json['parent_id'] != null ? int.tryParse(json['parent_id'].toString()) : null,
      icon: (json['icon'] ?? '').toString().trim().isEmpty ? null : json['icon'].toString(),
      image: _resolveSellerHubMedia(json['image']),
      isLeaf: json['is_leaf'] != false,
      hasChildren: json['has_children'] == true,
      productCount: parseInt(json['product_count']),
      totalProductCount: parseInt(json['total_product_count'] ?? json['product_count']),
      children: rawChildren is List
          ? rawChildren
              .whereType<Map>()
              .map((c) => MarketplaceCategory.fromJson(Map<String, dynamic>.from(c)))
              .toList()
          : const [],
    );
  }
}

/// One sellable product from `GET /api/marketplace/products/` (a published,
/// APPROVED, in-stock `SellerProduct` on the vendor).
/// One admin/seller-entered attribute row on a product's "About this item"
/// section (e.g. label "Health Benefits", value "Vitamin C & Vitamin K
/// Rich") — the vendor's own detail endpoint returns these as a free-form
/// `specs` list, not a fixed set of columns, so this app renders whatever
/// the seller filled in rather than hardcoding specific attribute names.
class MarketplaceProductSpec {
  const MarketplaceProductSpec({required this.label, required this.value});

  final String label;
  final String value;

  factory MarketplaceProductSpec.fromJson(Map<String, dynamic> json) {
    return MarketplaceProductSpec(
      label: (json['label'] ?? '').toString().trim(),
      value: (json['value'] ?? '').toString().trim(),
    );
  }
}

/// Resolves the vendor's `images` gallery (a list of URL strings or of
/// `{image|url|path: ...}` maps) into distinct absolute URLs.
List<String> _parseGallery(dynamic raw) {
  if (raw is! List) return const [];
  final out = <String>[];
  for (final item in raw) {
    dynamic v = item;
    if (item is Map) v = item['image'] ?? item['url'] ?? item['path'] ?? item['src'];
    final url = _resolveSellerHubMedia(v);
    if (url != null && url.isNotEmpty && !out.contains(url)) out.add(url);
  }
  return out;
}

/// Units of one product (500g / 1kg / 5kg) arrive as separate list rows
/// sharing a `variant_group_id`. The customer should see ONE listing for
/// the product and choose the unit on its detail page, so keep a single
/// representative per group (lowest-priced in-stock unit, at the position
/// of the group's first appearance). Standalone products are untouched.
List<MarketplaceProduct> _collapseVariantGroups(List<MarketplaceProduct> products) {
  final best = <int, MarketplaceProduct>{};
  for (final p in products) {
    final g = p.variantGroupId;
    if (g == null) continue;
    final cur = best[g];
    if (cur == null) {
      best[g] = p;
      continue;
    }
    final better = (p.inStock && !cur.inStock) ||
        (p.inStock == cur.inStock && p.sellingPrice < cur.sellingPrice);
    if (better) best[g] = p;
  }
  final emitted = <int>{};
  final out = <MarketplaceProduct>[];
  for (final p in products) {
    final g = p.variantGroupId;
    if (g == null) {
      out.add(p);
    } else if (emitted.add(g)) {
      out.add(best[g]!);
    }
  }
  return out;
}

class MarketplaceProduct {
  const MarketplaceProduct({
    required this.id,
    required this.title,
    required this.sellingPrice,
    this.brand,
    this.unit,
    this.packSize,
    this.mrp,
    this.primaryImage,
    this.images = const [],
    this.categoryId,
    this.categoryName,
    this.categorySlug,
    this.sellerName,
    this.inStock = true,
    this.availableStock = 0,
    this.description,
    this.storageInfo,
    this.expiryInfo,
    this.specs = const [],
    this.variantGroupId,
    this.variantAttributeName,
    this.variantLabel,
    this.variants = const [],
  });

  final int id;
  final String title;
  final Decimal sellingPrice;
  final String? brand;
  final String? unit;
  final String? packSize;
  final Decimal? mrp;
  final String? primaryImage;

  /// Full gallery (vendor `images`), already resolved to absolute URLs and
  /// de-duplicated, with [primaryImage] first. Empty when the vendor sent
  /// none; use [galleryImages] for a never-empty-if-any-image view.
  final List<String> images;
  final int? categoryId;
  final String? categoryName;
  final String? categorySlug;
  final String? sellerName;
  final bool inStock;
  final num availableStock;

  // Fixed 2026-10-08 ("See here the description and all other details of
  // the product has not been shown in the mobile application" — compared
  // against sevo.co.in's own "About this item" card for the same Seller
  // Hub Marketplace product): the vendor's product detail/list endpoints
  // (workforce_api/views_marketplace_integration.py) already return
  // `description` (plain, pre-sanitized text), `storage_info`, `expiry_info`
  // and (detail only) a free-form `specs` label/value list — this model
  // just never parsed any of them, so every Seller Hub Marketplace product
  // silently had no description data at all on this app, regardless of
  // what the seller had actually entered.
  final String? description;
  final String? storageInfo;
  final String? expiryInfo;
  final List<MarketplaceProductSpec> specs;

  // ── Product variations (added 2026-10-08, ported from the Vendor Seller
  // Hub's existing variant-group feature — "for a particular product there
  // are three variations, 1kg/500g/5kg"): the vendor backend already groups
  // sibling products (e.g. "Atta 1kg", "Atta 5kg") under one
  // `variant_group_id`, each sibling being its own REAL, independently
  // priced/stocked SellerProduct row — not a sub-field of one product. The
  // CalServices proxy (marketplace_views.py) already forwards all of this
  // untouched; this app's model just never parsed it. [variantLabel] is
  // THIS product's own variant (e.g. "500g"), [variantAttributeName] is
  // what that label represents (e.g. "Size" or "Weight", seller-chosen),
  // and [variants] is every sibling in the group INCLUDING this product
  // itself, each parsed as a full (if sparser — no category/seller)
  // [MarketplaceProduct] so [toServiceItem] and existing cart/detail
  // navigation work on a selected variant with no special-casing.
  final int? variantGroupId;
  final String? variantAttributeName;
  final String? variantLabel;
  final List<MarketplaceProduct> variants;

  /// Whether this product has more than one real, selectable variant worth
  /// showing a picker for — a lone product technically "in its own group"
  /// (or with no group at all) has nothing to switch between.
  bool get hasSelectableVariants => variants.length > 1;

  /// Every distinct image to show in the detail carousel: the gallery, or
  /// just the primary image when no gallery was returned.
  List<String> get galleryImages {
    final out = <String>[];
    for (final u in [if (primaryImage != null) primaryImage!, ...images]) {
      if (u.isNotEmpty && !out.contains(u)) out.add(u);
    }
    return out;
  }

  /// Only shows a strike-through MRP when it's a real, higher figure — same
  /// "never render a fake discount" rule as [GroceryHubProduct].
  bool get hasStrikeThroughMrp => mrp != null && mrp! > sellingPrice;

  // Every id from this catalog is offset into its own range before use as a
  // [ServiceItem.id] so it can never collide with the real catalog's ids or
  // with [GroceryHubProduct]'s own offset range (900000000) — see that
  // class's matching doc comment for why this matters for the shared cart.
  static const int _cartIdOffset = 800000000;

  /// Combines `specs` + `storage_info` + `expiry_info` + `description` into
  /// one readable block of text, in the same order the vendor's own detail
  /// page lists them in — this app has no dedicated widgets for each of
  /// those separate fields, but [ServiceItem.description] is already
  /// rendered as-is (newlines included) by grocery_product_detail_screen.dart's
  /// existing "About this product" section, so feeding it everything here
  /// is enough to show it all without needing a new UI section.
  String? get _combinedDescription {
    final lines = <String>[
      for (final spec in specs)
        if (spec.label.isNotEmpty && spec.value.isNotEmpty) '${spec.label}: ${spec.value}',
      if ((storageInfo ?? '').trim().isNotEmpty) 'Storage: ${storageInfo!.trim()}',
      if ((expiryInfo ?? '').trim().isNotEmpty) 'Shelf Life: ${expiryInfo!.trim()}',
    ];
    final attributeBlock = lines.join('\n');
    final desc = (description ?? '').trim();
    final combined = [
      if (desc.isNotEmpty) desc,
      if (attributeBlock.isNotEmpty) attributeBlock,
    ].join('\n\n');
    return combined.isEmpty ? null : combined;
  }

  ServiceItem toServiceItem() {
    final hasMrp = hasStrikeThroughMrp;
    return ServiceItem(
      id: _cartIdOffset + id,
      title: title,
      slug: 'seller-hub-$id',
      price: hasMrp ? mrp! : sellingPrice,
      discountedPrice: hasMrp ? sellingPrice : null,
      // Prefer the real variant label (e.g. "1kg", "500g") over the plain
      // `unit` field when this product belongs to a variant group — it's
      // the more specific, customer-meaningful weight/size for THIS
      // particular variant.
      unit: (variantLabel != null && variantLabel!.isNotEmpty) ? variantLabel : unit,
      categoryName: categoryName,
      // Forced to contain "grocer" so ServiceItem.flowType always resolves
      // to CatalogFlowType.grocery regardless of this tree's own category
      // names (e.g. "Oils & Ghee", which wouldn't otherwise match).
      categorySlug: 'seller_hub_groceries',
      imageUrl: primaryImage,
      inStock: inStock,
      maxQuantity: availableStock > 0 ? availableStock.floor().clamp(1, 99) : 0,
      description: _combinedDescription,
    );
  }

  factory MarketplaceProduct.fromJson(Map<String, dynamic> json) {
    Decimal? parseDecimal(dynamic v) {
      if (v == null) return null;
      final s = v.toString().trim();
      if (s.isEmpty) return null;
      try {
        return Decimal.parse(s);
      } catch (_) {
        return null;
      }
    }

    final category = json['category'] is Map ? Map<String, dynamic>.from(json['category'] as Map) : const {};
    final seller = json['seller'] is Map ? Map<String, dynamic>.from(json['seller'] as Map) : const {};
    final rawBrand = (json['brand'] ?? '').toString();
    final rawUnit = (json['unit'] ?? '').toString();
    final rawPack = (json['pack_size'] ?? '').toString();

    return MarketplaceProduct(
      id: int.tryParse(json['id']?.toString() ?? '') ?? 0,
      title: (json['title'] ?? '').toString(),
      sellingPrice: parseDecimal(json['selling_price']) ?? Decimal.zero,
      brand: rawBrand.isNotEmpty ? rawBrand : null,
      unit: rawUnit.isNotEmpty ? rawUnit : null,
      packSize: rawPack.isNotEmpty ? rawPack : null,
      mrp: parseDecimal(json['mrp']),
      primaryImage: _resolveSellerHubMedia(json['primary_image']),
      images: _parseGallery(json['images']),
      categoryId: int.tryParse(category['id']?.toString() ?? ''),
      categoryName: (category['name'] ?? '').toString().trim().isEmpty ? null : category['name'].toString(),
      categorySlug: (category['slug'] ?? '').toString().trim().isEmpty ? null : category['slug'].toString(),
      sellerName: (seller['name'] ?? '').toString().trim().isEmpty ? null : seller['name'].toString(),
      inStock: json['in_stock'] != false,
      availableStock: num.tryParse(json['available_stock']?.toString() ?? '') ?? 0,
      description: (json['description'] ?? '').toString().trim().isEmpty
          ? null
          : json['description'].toString().trim(),
      storageInfo: (json['storage_info'] ?? '').toString().trim().isEmpty
          ? null
          : json['storage_info'].toString().trim(),
      expiryInfo: (json['expiry_info'] ?? '').toString().trim().isEmpty
          ? null
          : json['expiry_info'].toString().trim(),
      // Only present on the single-product detail endpoint — list responses
      // don't include it, so this is naturally empty there.
      specs: json['specs'] is List
          ? (json['specs'] as List)
              .whereType<Map>()
              .map((m) => MarketplaceProductSpec.fromJson(Map<String, dynamic>.from(m)))
              .where((s) => s.label.isNotEmpty && s.value.isNotEmpty)
              .toList()
          : const [],
      variantGroupId: int.tryParse(json['variant_group_id']?.toString() ?? ''),
      variantAttributeName: (json['variant_attribute_name'] ?? '').toString().trim().isEmpty
          ? null
          : json['variant_attribute_name'].toString().trim(),
      variantLabel: (json['variant_label'] ?? '').toString().trim().isEmpty
          ? null
          : json['variant_label'].toString().trim(),
      // Siblings never carry their own nested `variants` key, so this
      // recursion is naturally one level deep only.
      variants: json['variants'] is List
          ? (json['variants'] as List)
              .whereType<Map>()
              .map((m) => MarketplaceProduct.fromJson(Map<String, dynamic>.from(m)))
              .where((p) => p.id != 0 && p.title.isNotEmpty)
              .toList()
          : const [],
    );
  }
}

class MarketplaceProductPage {
  const MarketplaceProductPage({
    required this.products,
    required this.count,
    required this.page,
    required this.totalPages,
  });

  final List<MarketplaceProduct> products;
  final int count;
  final int page;
  final int totalPages;

  static const empty = MarketplaceProductPage(products: [], count: 0, page: 1, totalPages: 1);
}

class MarketplaceCatalogRepository {
  MarketplaceCatalogRepository({required this.api});

  final ApiClient api;

  /// `GET /api/marketplace/categories/` — defaults to the full nested tree
  /// of active departments, pruned of any department (and its subtree)
  /// with zero sellable products right now.
  Future<Result<List<MarketplaceCategory>>> getCategoryTree({bool hideEmpty = true}) async {
    try {
      final response = await api.get(
        '/marketplace/categories/',
        queryParameters: {'tree': 'true', 'hide_empty': hideEmpty ? 'true' : 'false'},
      );
      return ResponseNormalizer.extract(response, (data) {
        final list = data is List ? data : const [];
        return list
            .whereType<Map>()
            .map((m) => MarketplaceCategory.fromJson(Map<String, dynamic>.from(m)))
            .toList();
      });
    } on Exception catch (e) {
      return Failure(_toError(e));
    }
  }

  /// `GET /api/marketplace/products/` for one department (and everything
  /// under it) — mirrors how the Vegetable Inventory screen fetches a
  /// department's produce by category slug.
  Future<Result<MarketplaceProductPage>> getProducts({
    int? categoryId,
    String? categorySlug,
    String? search,
    int page = 1,
    int pageSize = 60,
  }) async {
    try {
      final response = await api.get('/marketplace/products/', queryParameters: {
        if (categoryId != null) 'category_id': categoryId,
        if (categorySlug != null && categorySlug.isNotEmpty) 'category_slug': categorySlug,
        if (search != null && search.isNotEmpty) 'search': search,
        'page': page,
        'page_size': pageSize,
      });
      // This proxy passes the vendor's raw paginated shape straight through
      // (no {success, data} envelope) — see marketplace_views.py's
      // MarketplaceProductListView, which returns `result["data"]` as the
      // whole response body.
      final dynamic body = response.data;
      final map = body is Map ? Map<String, dynamic>.from(body) : <String, dynamic>{};
      final rawResults = map['results'];
      final products = rawResults is List
          ? rawResults
              .whereType<Map>()
              .map((m) => MarketplaceProduct.fromJson(Map<String, dynamic>.from(m)))
              .where((p) => p.title.isNotEmpty)
              .toList()
          : <MarketplaceProduct>[];
      return Success(MarketplaceProductPage(
        products: _collapseVariantGroups(products),
        count: int.tryParse(map['count']?.toString() ?? '') ?? products.length,
        page: int.tryParse(map['page']?.toString() ?? '') ?? page,
        totalPages: int.tryParse(map['total_pages']?.toString() ?? '') ?? 1,
      ));
    } on Exception catch (e) {
      return Failure(_toError(e));
    }
  }

  /// `GET /api/marketplace/products/<id>/` — one product by its real Seller
  /// Hub id. Added 2026-10-05 for the Grocery Home Section Builder's
  /// "Specific Products" source mode (an admin-curated list of exact
  /// products, as opposed to "Categories" mode's whole-department filter).
  /// There is no bulk-by-ids endpoint on the vendor side to proxy, so
  /// [marketplaceProductsByIdsProvider] below calls this once per id in
  /// parallel — acceptable because every layout that offers "Specific
  /// Products" caps how many an admin can pick to a small curated count
  /// (Featured Hero, Deal Cards, Split Featured and similar spotlight
  /// layouts), never the full department-sized lists Categories mode loads.
  Future<Result<MarketplaceProduct>> getProductDetail(int id) async {
    try {
      final response = await api.get('/marketplace/products/$id/');
      // Same unwrapped-vendor-shape convention as getProducts() above — the
      // detail view (marketplace_views.py's MarketplaceProductDetailView)
      // returns the single product object with no {success, data} envelope.
      final dynamic body = response.data;
      if (body is! Map) return Failure(UnknownError('Unexpected product detail shape'));
      final product = MarketplaceProduct.fromJson(Map<String, dynamic>.from(body));
      if (product.title.isEmpty) return Failure(UnknownError('Product not found'));
      return Success(product);
    } on Exception catch (e) {
      return Failure(_toError(e));
    }
  }

  /// `GET /api/marketplace/warehouses/` — active Seller Hub fulfillment
  /// warehouses, so a caller can resolve a warehouse_id before calling
  /// [getDeliverySlots]. Added for the grocery "Instant / Scheduled
  /// delivery" feature ("the slots for grocery/vegetable should be from
  /// the seller hub-delivery slot"), replacing the previously hardcoded
  /// "6:00 PM - 8:00 PM" window on [GroceryCartScreen].
  Future<Result<List<DeliveryWarehouse>>> getWarehouses() async {
    try {
      final response = await api.get('/marketplace/warehouses/');
      return ResponseNormalizer.extract(response, (data) {
        final list = data is List ? data : const [];
        return list
            .whereType<Map>()
            .map((m) => DeliveryWarehouse.fromJson(Map<String, dynamic>.from(m)))
            .toList();
      });
    } on Exception catch (e) {
      return Failure(_toError(e));
    }
  }

  /// `GET /api/marketplace/delivery-slots/?warehouse_id=&date=` — the real,
  /// admin-configured Seller Hub delivery slots (Seller Hub > Delivery
  /// Slots & Capacity) for one warehouse and one calendar date, with live
  /// per-date capacity/cutoff already applied server-side. [warehouseId]
  /// may be omitted — the CalServices proxy falls back to the first active
  /// warehouse (today there is exactly one, "Jeemangalam Hub").
  Future<Result<DeliverySlotDay>> getDeliverySlots({
    int? warehouseId,
    required String date,
  }) async {
    try {
      final response = await api.get('/marketplace/delivery-slots/', queryParameters: {
        if (warehouseId != null) 'warehouse_id': warehouseId,
        'date': date,
      });
      return ResponseNormalizer.extract(response, (data) {
        final map = data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{};
        return DeliverySlotDay.fromJson(map);
      });
    } on Exception catch (e) {
      return Failure(_toError(e));
    }
  }

  /// `GET /api/marketplace/baskets/` — Seller Hub combo/bundle offers.
  /// Added 2026-10-08 ("the grocery developer has implemented another
  /// feature something like Basket could you get into our app?") — the
  /// backend proxy (`CustomerMarketplaceBasketListView`) already sanitizes
  /// and paginates this, same unwrapped-vendor-shape convention as
  /// [getProducts] above (no `{success, data}` envelope).
  Future<Result<MarketplaceBasketPage>> getBaskets({
    int? companyId,
    String? search,
    int page = 1,
    int pageSize = 20,
  }) async {
    try {
      final response = await api.get('/marketplace/baskets/', queryParameters: {
        if (companyId != null) 'company_id': companyId,
        if (search != null && search.isNotEmpty) 'search': search,
        'page': page,
        'page_size': pageSize,
      });
      final dynamic body = response.data;
      if (body is List) {
        // The view returns a bare list when the vendor's own response had
        // no "results" key (see CustomerMarketplaceBasketListView.get).
        final baskets = body
            .whereType<Map>()
            .map((m) => MarketplaceBasket.fromJson(Map<String, dynamic>.from(m)))
            .where((b) => b.id != 0)
            .toList();
        return Success(MarketplaceBasketPage(
          baskets: baskets,
          count: baskets.length,
          page: page,
          totalPages: 1,
        ));
      }
      final map = body is Map ? Map<String, dynamic>.from(body) : <String, dynamic>{};
      final rawResults = map['results'];
      final baskets = rawResults is List
          ? rawResults
              .whereType<Map>()
              .map((m) => MarketplaceBasket.fromJson(Map<String, dynamic>.from(m)))
              .where((b) => b.id != 0)
              .toList()
          : <MarketplaceBasket>[];
      return Success(MarketplaceBasketPage(
        baskets: baskets,
        count: int.tryParse(map['count']?.toString() ?? '') ?? baskets.length,
        page: int.tryParse(map['page']?.toString() ?? '') ?? page,
        totalPages: int.tryParse(map['total_pages']?.toString() ?? '') ?? 1,
      ));
    } on Exception catch (e) {
      return Failure(_toError(e));
    }
  }

  /// `GET /api/marketplace/baskets/<id>/` — full basket detail with its
  /// component slots/items, for the basket detail screen's option picker.
  Future<Result<MarketplaceBasket>> getBasketDetail(int basketId) async {
    try {
      final response = await api.get('/marketplace/baskets/$basketId/');
      final dynamic body = response.data;
      if (body is! Map) return Failure(UnknownError('Unexpected basket detail shape'));
      final basket = MarketplaceBasket.fromJson(Map<String, dynamic>.from(body));
      if (basket.id == 0) return Failure(UnknownError('Basket not found'));
      return Success(basket);
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

/// One active Seller Hub fulfillment warehouse
/// (`PublicWarehouseListView` on the vendor backend).
class DeliveryWarehouse {
  const DeliveryWarehouse({required this.id, required this.name});

  final int id;
  final String name;

  factory DeliveryWarehouse.fromJson(Map<String, dynamic> json) {
    return DeliveryWarehouse(
      id: int.tryParse(json['id']?.toString() ?? '') ?? 0,
      name: (json['name'] ?? '').toString(),
    );
  }
}

/// One real, admin-configured delivery window for a warehouse on a given
/// date (`workforce_api.DeliverySlot` on the vendor, surfaced through
/// `PublicDeliverySlotsView`) — e.g. "09:00-11:00", "Standard Delivery",
/// with live capacity/cutoff already applied for the requested date.
class DeliverySlotOption {
  const DeliverySlotOption({
    required this.id,
    required this.label,
    required this.startTime,
    required this.endTime,
    required this.isAvailable,
  });

  final int id;
  final String label;
  final String startTime; // "HH:MM"
  final String endTime; // "HH:MM"
  final bool isAvailable;

  factory DeliverySlotOption.fromJson(Map<String, dynamic> json) {
    return DeliverySlotOption(
      id: int.tryParse(json['id']?.toString() ?? '') ?? 0,
      label: (json['label'] ?? '').toString(),
      startTime: (json['start_time'] ?? '').toString(),
      endTime: (json['end_time'] ?? '').toString(),
      isAvailable: json['available'] == true,
    );
  }
}

/// One warehouse's real delivery slots for one calendar date — the direct
/// response shape of [MarketplaceCatalogRepository.getDeliverySlots].
class DeliverySlotDay {
  const DeliverySlotDay({
    required this.warehouseId,
    this.warehouseName,
    required this.date,
    required this.slots,
    this.failed = false,
  });

  final int? warehouseId;
  final String? warehouseName;
  final String date;
  final List<DeliverySlotOption> slots;

  /// True when the fetch itself failed (network/server) — distinct from a
  /// date that genuinely has no slots, so the UI can offer a retry.
  final bool failed;

  static const empty = DeliverySlotDay(warehouseId: null, date: '', slots: []);
  static const fetchFailed = DeliverySlotDay(warehouseId: null, date: '', slots: [], failed: true);

  factory DeliverySlotDay.fromJson(Map<String, dynamic> json) {
    final rawSlots = json['slots'];
    return DeliverySlotDay(
      warehouseId: int.tryParse(json['warehouse_id']?.toString() ?? ''),
      warehouseName: (json['warehouse_name'] ?? '').toString().trim().isEmpty
          ? null
          : json['warehouse_name'].toString(),
      date: (json['date'] ?? '').toString(),
      slots: rawSlots is List
          ? rawSlots
              .whereType<Map>()
              .map((m) => DeliverySlotOption.fromJson(Map<String, dynamic>.from(m)))
              .toList()
          : const [],
    );
  }
}

final marketplaceCatalogRepositoryProvider = Provider<MarketplaceCatalogRepository>((ref) {
  return MarketplaceCatalogRepository(api: ref.watch(apiClientProvider));
});

/// The full department tree, fetched once and kept alive for the browse
/// screen's lifetime — never throws to its watcher; an unreachable vendor
/// just means an empty tree (screen shows its own empty state) rather than
/// crashing the whole browse screen, same "fail open" convention used
/// throughout this app's other optional data sources.
final marketplaceCategoryTreeProvider = FutureProvider.autoDispose<List<MarketplaceCategory>>((ref) async {
  final repo = ref.watch(marketplaceCatalogRepositoryProvider);
  final result = await repo.getCategoryTree();
  switch (result) {
    case Success(:final data):
      if (kDebugMode) {
        debugPrint('[SELLER-HUB] category tree fetched: ${data.length} root departments');
      }
      return data;
    case Failure(:final error):
      if (kDebugMode) {
        debugPrint('[SELLER-HUB] category tree FAILED: ${error.message}');
      }
      return const [];
  }
});

/// A flat, top-to-bottom list of every LEAF department in the tree — what
/// the vertical department rail actually shows tiles for (mirrors how the
/// Vegetable Inventory screen tiles its departments), in original sort
/// order, depth-first.
final marketplaceLeafDepartmentsProvider = Provider.autoDispose<List<MarketplaceCategory>>((ref) {
  final tree = ref.watch(marketplaceCategoryTreeProvider).valueOrNull ?? const [];
  final leaves = <MarketplaceCategory>[];
  void walk(List<MarketplaceCategory> nodes) {
    for (final node in nodes) {
      if (node.children.isEmpty) {
        if (node.hasAnyProducts) leaves.add(node);
      } else {
        walk(node.children);
      }
    }
  }

  walk(tree);
  return leaves;
});

/// One Home-page product carousel section — a real Seller Hub department
/// (with its own admin-uploaded name/image and approved, in-stock
/// products) plus which root it lives under, so the Home screen can send
/// "See all" to the right browse screen ([isVegetableRoot] picks
/// `/vegetables/seller-hub` vs `/groceries/seller-hub` — see
/// AppRoutes.sellerHubVegetables's doc comment).
class MarketplaceHomeSection {
  const MarketplaceHomeSection({required this.category, required this.isVegetableRoot});

  final MarketplaceCategory category;
  final bool isVegetableRoot;
}

/// Added 2026-09-30 per explicit request ("remove Essential Picks... place
/// the section as like the uploaded image [a Blinkit-style Home page: many
/// titled, horizontally-scrolling product carousels, one per department] —
/// give the privilege to the customer admin to set up the products in
/// UI"): rather than a new, separate admin-curation system, this reuses
/// the SAME Seller Hub Marketplace tree [SellerHubGroceriesScreen] /
/// [SellerHubVegetablesScreen] already browse — the admin already has full
/// control of exactly this data via "Superadmin Console → Seller Hub →
/// Categories" (add a sub-category, file approved products under it, it
/// appears here; remove/rename it there, this list follows). One Home
/// section per direct child of every root that has products (mirrors each
/// screen's own "rail" — a root with no further nesting is its own sole
/// section), flattened across ALL roots so Groceries' and Vegetables &
/// Fruits' departments interleave in one continuous list, same as the
/// reference screenshot mixes "Fruit and vegetables" among general grocery
/// categories.
final marketplaceHomeSectionsProvider = Provider.autoDispose<List<MarketplaceHomeSection>>((ref) {
  final tree = ref.watch(marketplaceCategoryTreeProvider).valueOrNull ?? const [];
  final sections = <MarketplaceHomeSection>[];
  for (final root in tree) {
    if (!root.hasAnyProducts) continue;
    final rootKeyLower = '${root.name} ${root.slug}'.toLowerCase();
    final isVegetableRoot = rootKeyLower.contains('vegetable') || rootKeyLower.contains('fruit');
    final children = root.children.where((c) => c.hasAnyProducts).toList();
    if (children.isNotEmpty) {
      for (final child in children) {
        sections.add(MarketplaceHomeSection(category: child, isVegetableRoot: isVegetableRoot));
      }
    } else {
      sections.add(MarketplaceHomeSection(category: root, isVegetableRoot: isVegetableRoot));
    }
  }
  return sections;
});

/// Products for one department, keyed by category id — `.family` so the
/// browse screen can hold each visited department's product grid without
/// refetching every tap.
final marketplaceProductsByCategoryProvider =
    FutureProvider.autoDispose.family<MarketplaceProductPage, int>((ref, categoryId) async {
  final repo = ref.watch(marketplaceCatalogRepositoryProvider);
  final result = await repo.getProducts(categoryId: categoryId, pageSize: 60);
  switch (result) {
    case Success(:final data):
      return data;
    case Failure():
      return MarketplaceProductPage.empty;
  }
});

/// Merged, deduped products across every category id an admin-curated
/// [MobileGrocerySection] (home_screen.dart) picked — keyed by a
/// comma-joined, sorted string of ids rather than `List<int>` directly,
/// since Dart lists compare by identity, not value, and would defeat this
/// `.family` provider's caching on every rebuild. Each id is fetched in
/// parallel; a failed id is silently dropped (same "fail open" convention
/// as everywhere else optional in this app) rather than failing the whole
/// section, and a product appearing under more than one picked id (e.g. the
/// admin picked both a parent and one of its own children) is kept only
/// once, in first-seen order.
final marketplaceMergedProductsProvider =
    FutureProvider.autoDispose.family<List<MarketplaceProduct>, String>((ref, idsKey) async {
  final ids = idsKey.split(',').where((s) => s.isNotEmpty).map(int.parse).toList();
  if (ids.isEmpty) return const [];

  final repo = ref.watch(marketplaceCatalogRepositoryProvider);
  final results = await Future.wait(ids.map((id) => repo.getProducts(categoryId: id, pageSize: 60)));

  final seenIds = <int>{};
  final merged = <MarketplaceProduct>[];
  for (final result in results) {
    switch (result) {
      case Success(:final data):
        for (final product in data.products) {
          if (seenIds.add(product.id)) merged.add(product);
        }
      case Failure():
        break;
    }
  }
  return merged;
});

/// An admin-curated exact list of product ids ([MobileGrocerySection]'s
/// "Specific Products" source mode, added 2026-10-05) — unlike
/// [marketplaceMergedProductsProvider] above, order is preserved exactly as
/// the admin picked it (a Split Featured or Deal Cards layout cares which
/// product is first) and nothing is deduped, since an admin picking the
/// same product twice is their own choice, not a merge artifact. Keyed by
/// the ids joined in order (not sorted) so re-ordering the admin's picks
/// correctly invalidates this `.family` provider's cache. A failed id is
/// dropped rather than failing the whole section, same "fail open"
/// convention as the rest of this file.
final marketplaceProductsByIdsProvider =
    FutureProvider.autoDispose.family<List<MarketplaceProduct>, String>((ref, idsKey) async {
  final ids = idsKey.split(',').where((s) => s.isNotEmpty).map(int.parse).toList();
  if (ids.isEmpty) return const [];

  final repo = ref.watch(marketplaceCatalogRepositoryProvider);
  final results = await Future.wait(ids.map((id) => repo.getProductDetail(id)));

  final ordered = <MarketplaceProduct>[];
  for (final result in results) {
    switch (result) {
      case Success(:final data):
        ordered.add(data);
      case Failure():
        break;
    }
  }
  return ordered;
});

/// One Seller Hub Marketplace product's full detail (id -> [MarketplaceProduct],
/// specs included) — added 2026-10-08 so
/// grocery_product_detail_screen.dart can enrich its instantly-painted
/// `initialProduct` (which only ever carries list-endpoint data — no
/// `specs` — see [MarketplaceCatalogRepository.getProducts]'s doc comment)
/// with the admin/seller attribute rows (Health Benefits, Disclaimer,
/// Customer Care Details, Country of Origin, etc.) that only the single
/// `GET /marketplace/products/<id>/` detail call returns. `.family` so
/// revisiting the same product doesn't refetch.
final marketplaceProductDetailProvider =
    FutureProvider.autoDispose.family<MarketplaceProduct?, int>((ref, id) async {
  ref.keepAlive();
  final repo = ref.watch(marketplaceCatalogRepositoryProvider);
  final result = await repo.getProductDetail(id);
  switch (result) {
    case Success(:final data):
      return data;
    case Failure():
      return null;
  }
});

/// Active Seller Hub fulfillment warehouses — fetched once and kept alive
/// for [GroceryCartScreen]'s delivery-option picker's lifetime. Never
/// throws to its watcher; an unreachable vendor just means an empty list
/// (the picker falls back to its own "unavailable" messaging) rather than
/// crashing checkout, same "fail open" convention as the rest of this
/// file.
final marketplaceWarehousesProvider = FutureProvider.autoDispose<List<DeliveryWarehouse>>((ref) async {
  final repo = ref.watch(marketplaceCatalogRepositoryProvider);
  final result = await repo.getWarehouses();
  switch (result) {
    case Success(:final data):
      return data;
    case Failure():
      return const [];
  }
});

/// Real, admin-configured Seller Hub delivery slots for one calendar date
/// (`YYYY-MM-DD`) — `.family` so [GroceryCartScreen]'s "Scheduled"
/// delivery-date picker can hold each visited date's slot list without
/// refetching every tap. Added replacing the previously hardcoded daily
/// "6:00 PM - 8:00 PM" window ("the slots for grocery/vegetable should be
/// from the seller hub-delivery slot"). A failed/unreachable fetch
/// resolves to an empty slot list rather than throwing, so the picker can
/// show "No slots available for this date" instead of crashing.
final marketplaceDeliverySlotsForDateProvider =
    FutureProvider.autoDispose.family<DeliverySlotDay, String>((ref, date) async {
  final repo = ref.watch(marketplaceCatalogRepositoryProvider);
  final result = await repo.getDeliverySlots(date: date);
  switch (result) {
    case Success(:final data):
      return data;
    case Failure():
      return DeliverySlotDay.fetchFailed;
  }
});

/// Combo/bundle offers for the grocery home "Combo Offers" section — fails
/// open to an empty list, same convention as [marketplaceWarehousesProvider]
/// above, so an unreachable vendor just means the section renders nothing
/// rather than crashing the Home screen.
final marketplaceBasketsProvider =
    FutureProvider.autoDispose<List<MarketplaceBasket>>((ref) async {
  final repo = ref.watch(marketplaceCatalogRepositoryProvider);
  final result = await repo.getBaskets();
  switch (result) {
    case Success(:final data):
      return data.baskets;
    case Failure():
      return const [];
  }
});

/// One basket's full detail (slots/items) for [BasketDetailScreen] —
/// `.family` so revisiting the same basket doesn't refetch, same pattern
/// as [marketplaceProductDetailProvider] above.
final marketplaceBasketDetailProvider =
    FutureProvider.autoDispose.family<MarketplaceBasket?, int>((ref, id) async {
  ref.keepAlive();
  final repo = ref.watch(marketplaceCatalogRepositoryProvider);
  final result = await repo.getBasketDetail(id);
  switch (result) {
    case Success(:final data):
      return data;
    case Failure():
      return null;
  }
});
