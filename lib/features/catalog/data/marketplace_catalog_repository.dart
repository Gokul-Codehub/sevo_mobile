import 'package:decimal/decimal.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../config/env.dart';
import '../../../core/errors/api_error.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/response_normalizer.dart';
import '../domain/catalog_models.dart';

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
    this.categoryId,
    this.categoryName,
    this.categorySlug,
    this.sellerName,
    this.inStock = true,
    this.availableStock = 0,
  });

  final int id;
  final String title;
  final Decimal sellingPrice;
  final String? brand;
  final String? unit;
  final String? packSize;
  final Decimal? mrp;
  final String? primaryImage;
  final int? categoryId;
  final String? categoryName;
  final String? categorySlug;
  final String? sellerName;
  final bool inStock;
  final num availableStock;

  /// Only shows a strike-through MRP when it's a real, higher figure — same
  /// "never render a fake discount" rule as [GroceryHubProduct].
  bool get hasStrikeThroughMrp => mrp != null && mrp! > sellingPrice;

  // Every id from this catalog is offset into its own range before use as a
  // [ServiceItem.id] so it can never collide with the real catalog's ids or
  // with [GroceryHubProduct]'s own offset range (900000000) — see that
  // class's matching doc comment for why this matters for the shared cart.
  static const int _cartIdOffset = 800000000;

  ServiceItem toServiceItem() {
    final hasMrp = hasStrikeThroughMrp;
    return ServiceItem(
      id: _cartIdOffset + id,
      title: title,
      slug: 'seller-hub-$id',
      price: hasMrp ? mrp! : sellingPrice,
      discountedPrice: hasMrp ? sellingPrice : null,
      unit: unit,
      categoryName: categoryName,
      // Forced to contain "grocer" so ServiceItem.flowType always resolves
      // to CatalogFlowType.grocery regardless of this tree's own category
      // names (e.g. "Oils & Ghee", which wouldn't otherwise match).
      categorySlug: 'seller_hub_groceries',
      imageUrl: primaryImage,
      inStock: inStock,
      maxQuantity: availableStock > 0 ? availableStock.floor().clamp(1, 99) : 0,
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
      categoryId: int.tryParse(category['id']?.toString() ?? ''),
      categoryName: (category['name'] ?? '').toString().trim().isEmpty ? null : category['name'].toString(),
      categorySlug: (category['slug'] ?? '').toString().trim().isEmpty ? null : category['slug'].toString(),
      sellerName: (seller['name'] ?? '').toString().trim().isEmpty ? null : seller['name'].toString(),
      inStock: json['in_stock'] != false,
      availableStock: num.tryParse(json['available_stock']?.toString() ?? '') ?? 0,
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
        products: products,
        count: int.tryParse(map['count']?.toString() ?? '') ?? products.length,
        page: int.tryParse(map['page']?.toString() ?? '') ?? page,
        totalPages: int.tryParse(map['total_pages']?.toString() ?? '') ?? 1,
      ));
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
