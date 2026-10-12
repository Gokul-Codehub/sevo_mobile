import 'dart:async';
import 'dart:convert';

import 'package:decimal/decimal.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../../core/errors/api_error.dart';
import '../../../core/network/api_client.dart';
import '../data/catalog_repository.dart';
import '../data/marketplace_catalog_repository.dart';
import 'catalog_models.dart';
import 'catalog_providers.dart';

// Search is split in two, Amazon-style:
//   1. while TYPING, the search box shows plain keyword suggestions (no
//      packages / products / prices) — see [searchSuggestionsProvider];
//   2. SUBMITTING a keyword opens a results page for the active mode —
//      Services or Groceries — see search_results_screen.dart.
//
// Both halves use the backend's search API (`/api/search/suggestions/`,
// `/api/search/results/`): ranked, with synonyms and typo tolerance, ~70 ms.

/// Which half of the app a search belongs to (the Home search bar passes the
/// active Groceries / Services mode).
enum SearchMode { services, groceries }

extension SearchModeX on SearchMode {
  String get wire => this == SearchMode.services ? 'services' : 'groceries';

  static SearchMode? fromWire(String? raw) => switch ((raw ?? '').toLowerCase()) {
        'services' || 'service' => SearchMode.services,
        'groceries' || 'grocery' => SearchMode.groceries,
        _ => null,
      };
}

// ── Text helpers ────────────────────────────────────────────────────────────

/// What gets sent to the server: trimmed, spaces collapsed, "a/c" -> "ac",
/// stray symbols removed (a "/" in the query makes the API answer with an
/// HTML 404 page).
String normalizeQuery(String raw) {
  var s = raw.trim();
  s = s.replaceAllMapped(
    RegExp(r'([A-Za-z])[/.]([A-Za-z])'),
    (m) => '${m[1]}${m[2]}',
  );
  s = s.replaceAll(RegExp(r"[^A-Za-z0-9 &'\-]"), ' ');
  return s.replaceAll(RegExp(r'\s+'), ' ').trim();
}

/// `Dairy & Eggs (500 g)` -> `dairy & eggs`: lower-cased, sizes/brackets
/// dropped, spaces collapsed — so "Milk (500ml)" and "Milk (1L)" become one
/// keyword.
String cleanKeyword(String raw) {
  var s = raw.replaceAll(RegExp(r'\([^)]*\)'), ' ');
  s = s.replaceAll(RegExp(r'\s+'), ' ').trim().toLowerCase();
  return s;
}

int _levenshtein(String a, String b) {
  if (a == b) return 0;
  if (a.isEmpty) return b.length;
  if (b.isEmpty) return a.length;
  var prev = List<int>.generate(b.length + 1, (i) => i);
  for (var i = 1; i <= a.length; i++) {
    final cur = List<int>.filled(b.length + 1, 0)..[0] = i;
    for (var j = 1; j <= b.length; j++) {
      final cost = a.codeUnitAt(i - 1) == b.codeUnitAt(j - 1) ? 0 : 1;
      var m = cur[j - 1] + 1;
      if (prev[j] + 1 < m) m = prev[j] + 1;
      if (prev[j - 1] + cost < m) m = prev[j - 1] + cost;
      cur[j] = m;
    }
    prev = cur;
  }
  return prev[b.length];
}

/// Typo-tolerant match of [query] against known phrases — "mlk" -> milk,
/// "bananna" -> banana. A phrase matches when one of its words (or the start
/// of one, for a half-typed word) is within 1–2 edits.
List<String> fuzzyMatches(String query, Iterable<String> vocabulary, {int limit = 6}) {
  final q = query.trim().toLowerCase();
  if (q.length < 3) return const [];
  final maxDist = q.length <= 5 ? 1 : 2;
  final hits = <({String phrase, int dist})>[];
  final seen = <String>{};
  for (final phrase in vocabulary) {
    final p = phrase.toLowerCase();
    if (p.isEmpty || !seen.add(p)) continue;
    var best = 99;
    for (final w in p.split(RegExp(r'[^a-z0-9]+'))) {
      if (w.length < 3) continue;
      final whole = _levenshtein(q, w);
      final prefix = w.length > q.length ? _levenshtein(q, w.substring(0, q.length)) : whole;
      final d = whole < prefix ? whole : prefix;
      if (d < best) best = d;
    }
    if (best <= maxDist) hits.add((phrase: phrase, dist: best));
  }
  hits.sort((a, b) {
    final byDist = a.dist.compareTo(b.dist);
    return byDist != 0 ? byDist : a.phrase.length.compareTo(b.phrase.length);
  });
  return hits.take(limit).map((h) => h.phrase).toList();
}

/// Keeps an auto-disposed provider alive for [duration] after its last
/// listener leaves, so going back and forth between suggestions and results
/// (or retyping the same thing) is instant instead of refetching.
void _cacheFor(Ref<Object?> ref, Duration duration) {
  final link = ref.keepAlive();
  final timer = Timer(duration, link.close);
  ref.onDispose(timer.cancel);
}

// ── Keyword suggestions ─────────────────────────────────────────────────────

/// Turns the backend's entity suggestions (`GET /api/search/suggestions/`:
/// categories / services (packages) / products / goods) into keyword phrases.
/// Services mode uses categories + packages + goods; Groceries mode uses
/// products. Phrases containing what was typed come first.
List<String> keywordsFromSuggestions(
  Map<String, dynamic> data,
  SearchMode mode,
  String query,
) {
  List<String> titles(String key) {
    final raw = data[key];
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((m) => (m['title'] ?? '').toString())
        .where((t) => t.trim().isNotEmpty)
        .toList();
  }

  final ordered = mode == SearchMode.services
      ? [...titles('categories'), ...titles('services'), ...titles('goods')]
      : [...titles('products')];

  final q = query.trim().toLowerCase();
  final seen = <String>{};
  final matching = <String>[];
  final others = <String>[];
  for (final title in ordered) {
    final k = cleanKeyword(title);
    if (k.isEmpty || !seen.add(k)) continue;
    (k.contains(q) ? matching : others).add(k);
  }
  // Synonym-driven hits may not contain the typed text; keep them after.
  return [...matching, ...others].take(8).toList();
}

/// Trending searches for the empty search box (`GET /api/search/trending/`),
/// as keyword phrases for the active mode.
final trendingKeywordsProvider =
    FutureProvider.family<List<String>, SearchMode>((ref, mode) async {
  ref.keepAlive();
  final api = ref.watch(apiClientProvider);
  try {
    final response = await api.get('/search/trending/');
    final body = response.data;
    final data = body is Map ? body['data'] : null;
    if (data is! List) return const [];
    final wanted = mode == SearchMode.services
        ? const {'service', 'category', 'package', 'goods_tier'}
        : const {'product'};
    final seen = <String>{};
    final out = <String>[];
    for (final item in data.whereType<Map>()) {
      if (!wanted.contains((item['entity_type'] ?? '').toString())) continue;
      final k = cleanKeyword((item['title'] ?? '').toString());
      if (k.isNotEmpty && seen.add(k)) out.add(k);
    }
    return out.take(10).toList();
  } catch (_) {
    return const [];
  }
});

/// Everything the app already knows by name — category names and trending
/// searches — used to repair typos when the server finds nothing.
final searchVocabularyProvider =
    FutureProvider.family<List<String>, SearchMode>((ref, mode) async {
  ref.keepAlive();
  final out = <String>{};
  try {
    if (mode == SearchMode.services) {
      final cats = await ref.watch(categoriesProvider.future);
      for (final c in cats) {
        out.add(cleanKeyword(c.name));
        for (final s in c.subcategories) {
          out.add(cleanKeyword(s.name));
        }
      }
    } else {
      final tree = await ref.watch(marketplaceCategoryTreeProvider.future);
      void walk(List<MarketplaceCategory> nodes) {
        for (final n in nodes) {
          out.add(cleanKeyword(n.name));
          walk(n.children);
        }
      }

      walk(tree);
    }
  } catch (_) {}
  try {
    out.addAll(await ref.watch(trendingKeywordsProvider(mode).future));
  } catch (_) {}
  return out.where((e) => e.isNotEmpty).toList();
});

/// Keyword suggestions for what has been typed so far. Needs >= 2 characters
/// (the API rejects less). When the server has nothing — a typo like "mlk" —
/// close matches from the app's own vocabulary are offered instead. Any
/// failure just means "no suggestions": the customer can still search for
/// exactly what they typed.
final searchSuggestionsProvider = FutureProvider.autoDispose
    .family<List<String>, ({String q, SearchMode mode})>((ref, p) async {
  _cacheFor(ref, const Duration(seconds: 90));
  final q = normalizeQuery(p.q);
  if (q.length < 2) return const [];

  final api = ref.watch(apiClientProvider);
  try {
    final response = await api.get('/search/suggestions/', queryParameters: {'q': q});
    final body = response.data;
    final data = body is Map ? (body['data'] ?? body) : null;
    if (data is Map) {
      final fromServer = keywordsFromSuggestions(Map<String, dynamic>.from(data), p.mode, q);
      if (fromServer.isNotEmpty) return fromServer;
    }
  } catch (_) {}

  try {
    final vocab = await ref.watch(searchVocabularyProvider(p.mode).future);
    return fuzzyMatches(q, vocab);
  } catch (_) {
    return const [];
  }
});

/// The customer's own last searches, per mode, kept on the device.
class RecentSearchesNotifier extends StateNotifier<List<String>> {
  RecentSearchesNotifier(this._mode) : super(const []) {
    _load();
  }

  final SearchMode _mode;
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );
  static const _max = 8;

  String get _key => 'sevo_recent_searches_${_mode.wire}';

  Future<void> _load() async {
    try {
      final raw = await _storage.read(key: _key);
      if (raw == null || raw.isEmpty) return;
      final list = jsonDecode(raw);
      if (list is List && mounted) {
        state = list.map((e) => e.toString()).take(_max).toList();
      }
    } catch (_) {}
  }

  Future<void> _save() async {
    try {
      await _storage.write(key: _key, value: jsonEncode(state));
    } catch (_) {}
  }

  Future<void> add(String query) async {
    final q = query.trim();
    if (q.isEmpty) return;
    state = [q, ...state.where((e) => e.toLowerCase() != q.toLowerCase())].take(_max).toList();
    await _save();
  }

  Future<void> remove(String query) async {
    state = state.where((e) => e != query).toList();
    await _save();
  }

  Future<void> clear() async {
    state = const [];
    await _save();
  }
}

final recentSearchesProvider = StateNotifierProvider.family<RecentSearchesNotifier,
    List<String>, SearchMode>((ref, mode) => RecentSearchesNotifier(mode));

// ── Results ─────────────────────────────────────────────────────────────────

/// One hit from `GET /api/search/results/` — a category, a service
/// (sub-category), a package, a product or a goods-transport vehicle tier.
class SearchEntity {
  const SearchEntity({
    required this.type,
    required this.entityId,
    required this.title,
    this.subtitle = '',
    this.imageUrl,
    this.price,
    this.mrp,
    this.stockQty,
    this.isAvailable = true,
    this.route = const {},
    this.categoryId,
    this.serviceId,
  });

  /// category | service | package | product | goods_tier
  final String type;
  final int entityId;
  final String title;
  final String subtitle;
  final String? imageUrl;
  final double? price;
  final double? mrp;
  final double? stockQty;
  final bool isAvailable;
  final Map<String, dynamic> route;
  final int? categoryId;

  /// The sub-service (e.g. "Tap repair") a package or service belongs to.
  final int? serviceId;

  String? get packageSlug => _s(route['package_slug']);

  /// The category this entity belongs to (or is, for a category hit).
  String? get categorySlug => _s(route['category_slug']) ?? _s(route['target']);

  static String? _s(dynamic v) {
    final s = (v ?? '').toString().trim();
    return s.isEmpty ? null : s;
  }

  factory SearchEntity.fromJson(Map<String, dynamic> j) {
    final price = j['price'] is Map
        ? Map<String, dynamic>.from(j['price'] as Map)
        : const <String, dynamic>{};
    final img = (j['image_url'] ?? '').toString().trim();
    return SearchEntity(
      type: (j['entity_type'] ?? '').toString(),
      entityId: int.tryParse((j['entity_id'] ?? '').toString()) ?? 0,
      title: (j['title'] ?? '').toString(),
      subtitle: (j['subtitle'] ?? '').toString(),
      imageUrl: img.isEmpty ? null : img,
      price: double.tryParse((price['price'] ?? '').toString()),
      mrp: double.tryParse((price['mrp'] ?? '').toString()),
      stockQty: double.tryParse((price['stock_qty'] ?? '').toString()),
      isAvailable: j['is_available'] != false,
      route: j['route'] is Map ? Map<String, dynamic>.from(j['route'] as Map) : const {},
      categoryId: int.tryParse((j['category_id'] ?? '').toString()),
      serviceId: int.tryParse((j['service_id'] ?? '').toString()),
    );
  }
}

// ── Paged results ───────────────────────────────────────────────────────────

/// What the results pages show, accumulated page by page
/// (`GET /api/search/results/?page=N`, 20 per page).
class SearchPageState {
  const SearchPageState({
    this.categories = const [],
    this.services = const [],
    this.goods = const [],
    this.packages = const [],
    this.products = const [],
    this.brands = const {},
    this.hitCategories = const [],
    this.hitServices = const [],
    this.page = 0,
    this.hasNext = false,
    this.total = 0,
    this.loading = true,
    this.loadingMore = false,
    this.error,
  });

  final List<SearchEntity> categories;
  final List<SearchEntity> services;
  final List<SearchEntity> goods;

  /// Services mode: matching packages as full catalog records.
  final List<ServiceItem> packages;

  /// Groceries mode: matching products.
  final List<ServiceItem> products;

  /// Groceries mode: product id -> brand (the hit's subtitle is "Brand • Category").
  final Map<int, String> brands;

  /// Ids of the categories the hits belong to, best match first (drives
  /// "Explore other").
  final List<int> hitCategories;

  /// Ids of the sub-services the hits belong to (Services mode).
  final List<int> hitServices;
  final int page;
  final bool hasNext;
  final int total;
  final bool loading;
  final bool loadingMore;
  final Object? error;

  bool get isEmptyResult =>
      !loading &&
      error == null &&
      categories.isEmpty &&
      services.isEmpty &&
      goods.isEmpty &&
      packages.isEmpty &&
      products.isEmpty;

  SearchPageState copyWith({
    List<SearchEntity>? categories,
    List<SearchEntity>? services,
    List<SearchEntity>? goods,
    List<ServiceItem>? packages,
    List<ServiceItem>? products,
    Map<int, String>? brands,
    List<int>? hitCategories,
    List<int>? hitServices,
    int? page,
    bool? hasNext,
    int? total,
    bool? loading,
    bool? loadingMore,
    Object? error,
    bool clearError = false,
  }) =>
      SearchPageState(
        categories: categories ?? this.categories,
        services: services ?? this.services,
        goods: goods ?? this.goods,
        packages: packages ?? this.packages,
        products: products ?? this.products,
        brands: brands ?? this.brands,
        hitCategories: hitCategories ?? this.hitCategories,
        hitServices: hitServices ?? this.hitServices,
        page: page ?? this.page,
        hasNext: hasNext ?? this.hasNext,
        total: total ?? this.total,
        loading: loading ?? this.loading,
        loadingMore: loadingMore ?? this.loadingMore,
        error: clearError ? null : (error ?? this.error),
      );
}

Decimal _dec(double v) => Decimal.parse(v.toStringAsFixed(2));

ServiceItem _packageFromEntity(SearchEntity e) {
  final hasMrp = e.mrp != null && e.price != null && e.mrp! > e.price!;
  return ServiceItem(
    id: e.entityId,
    title: e.title,
    slug: e.packageSlug ?? 'svc-${e.entityId}',
    price: _dec(hasMrp ? e.mrp! : (e.price ?? 0)),
    discountedPrice: hasMrp ? _dec(e.price!) : null,
    categoryId: e.categoryId,
    categoryName: _splitSubtitle(e.subtitle).brand.isNotEmpty
        ? _splitSubtitle(e.subtitle).brand
        : _splitSubtitle(e.subtitle).category,
    categorySlug: e.categorySlug,
    imageUrl: e.imageUrl,
  );
}

({String brand, String category}) _splitSubtitle(String subtitle) {
  final parts = subtitle
      .split(RegExp('\u2022|\u00e2\u20ac\u00a2'))
      .map((e) => e.trim())
      .where((e) => e.isNotEmpty)
      .toList();
  if (parts.length >= 2) return (brand: parts.first, category: parts.last);
  return (brand: '', category: parts.isEmpty ? '' : parts.first);
}

ServiceItem _productFromEntity(SearchEntity e) {
  final hasMrp = e.mrp != null && e.price != null && e.mrp! > e.price!;
  final stock = e.stockQty ?? 0;
  return ServiceItem(
    id: 800000000 + e.entityId, // same offset as MarketplaceProduct.toServiceItem
    title: e.title,
    slug: 'seller-hub-${e.entityId}',
    price: _dec(hasMrp ? e.mrp! : (e.price ?? 0)),
    discountedPrice: hasMrp ? _dec(e.price!) : null,
    categoryName: _splitSubtitle(e.subtitle).category,
    categorySlug: 'seller_hub_groceries',
    imageUrl: e.imageUrl,
    inStock: e.isAvailable,
    maxQuantity: e.isAvailable ? (stock > 0 ? stock.floor().clamp(1, 99) : 99) : 0,
  );
}

String _stem(String w) => w.length > 3 && w.endsWith('s') ? w.substring(0, w.length - 1) : w;

bool _wordMatches(String q, String w) {
  if (q.length < 3 || w.length < 3) return w == q;
  final a = _stem(q), b = _stem(w);
  if (a == b || b.startsWith(a) && a.length >= 4) return true;
  final maxDist = a.length <= 4 ? 0 : (a.length <= 7 ? 1 : 2);
  return maxDist > 0 && _levenshtein(a, b) <= maxDist;
}

/// Whether a product hit is really about the query. The server pads results
/// with loosely related items ("cookies" also returns mustard oil, potatoes
/// and rice), so a hit counts only when each typed word matches a word of its
/// name, brand or category — allowing plurals and small typos
/// ("cookie", "biscut" -> biscuits).
bool entityMatchesQuery(SearchEntity e, String query) {
  final qs = query.toLowerCase().split(RegExp(r'[^a-z0-9]+')).where((w) => w.length >= 2).toList();
  if (qs.isEmpty) return true;
  final words = '${e.title} ${e.subtitle}'
      .toLowerCase()
      .split(RegExp(r'[^a-z0-9]+'))
      .where((w) => w.isNotEmpty)
      .toList();
  return qs.every((q) => words.any((w) => _wordMatches(q, w)));
}

/// Words that say what kind of thing is wanted, not which one ("ac service").
const _genericWords = {'service', 'services', 'repair', 'installation', 'near', 'me', 'for', 'the'};

/// Services hits are matched more loosely than products: one significant
/// typed word in the name / category is enough (synonyms and sub-services
/// are common), but a hit sharing none of them ("Air fryer cleaning" for
/// "ac service") is dropped.
bool serviceEntityMatches(SearchEntity e, String query) {
  final qs = query
      .toLowerCase()
      .split(RegExp(r'[^a-z0-9]+'))
      .where((w) => w.length >= 2 && !_genericWords.contains(w))
      .toList();
  if (qs.isEmpty) return true;
  final words = '${e.title} ${e.subtitle} ${e.packageSlug ?? ''}'
      .toLowerCase()
      .split(RegExp(r'[^a-z0-9]+'))
      .where((w) => w.isNotEmpty)
      .toList();
  return qs.any((q) => words.any((w) => _wordMatches(q, w)));
}

/// A grocery / vegetable entry — Services search must not list these (they
/// belong to the Groceries search), and vice versa.
bool _isGroceryEntity(SearchEntity e) {
  final slug = (e.categorySlug ?? '').toLowerCase();
  return slug.contains('grocer') ||
      slug.contains('vegetable') ||
      e.title.toLowerCase().contains('grocer') && e.type == 'category';
}

/// Loads a query's results a page at a time and keeps them for the results
/// page (infinite scroll). Packages are matched to their full catalog records
/// so they draw as the usual service cards; products are built straight from
/// the hit (name, photo, price and stock are already in it). If the server
/// search is unavailable or finds nothing, the older catalog match is used.
class SearchPager extends StateNotifier<SearchPageState> {
  SearchPager(this._api, this._catalog, this._market, this.query, this.mode)
      : super(const SearchPageState()) {
    _load(1);
  }

  final ApiClient _api;
  final CatalogRepository _catalog;
  final MarketplaceCatalogRepository _market;
  final String query;
  final SearchMode mode;

  static const _pageSize = 20;

  /// Groceries: true when page 1 had real matches, so the loosely related
  /// filler the server adds after them is dropped. When nothing matches by
  /// name (a synonym such as "atta" -> wheat flour) everything is kept.
  bool _strict = false;

  /// Services: same idea — page 1 had real matches, so loosely related
  /// filler after them is dropped.
  bool _strictSvc = false;
  final _seenTitles = <String>{};

  Future<void> retry() {
    _seenTitles.clear();
    _strict = false;
    state = const SearchPageState();
    return _load(1);
  }

  Future<void> loadMore() async {
    if (!state.hasNext || state.loading || state.loadingMore || state.error != null) return;
    state = state.copyWith(loadingMore: true);
    await _load(state.page + 1);
  }

  Future<void> _load(int page) async {
    if (query.isEmpty) {
      state = state.copyWith(loading: false, loadingMore: false);
      return;
    }
    try {
      final response = await _api.get(
        '/search/results/',
        queryParameters: {'q': query, 'page': page, 'page_size': _pageSize},
      );
      if (!mounted) return;
      final body = response.data;
      final raw = body is Map && body['data'] is List ? body['data'] as List : const [];
      final pg = body is Map && body['pagination'] is Map
          ? Map<String, dynamic>.from(body['pagination'] as Map)
          : const <String, dynamic>{};
      var entities = raw
          .whereType<Map>()
          .map((m) => SearchEntity.fromJson(Map<String, dynamic>.from(m)))
          .where((e) => e.title.isNotEmpty)
          .toList();

      var next = state.copyWith(
        page: page,
        hasNext: pg['has_next'] == true,
        total: int.tryParse('${pg['total'] ?? ''}') ?? state.total,
        loading: false,
        loadingMore: false,
        clearError: true,
      );

      List<T> merge<T>(List<T> old, Iterable<T> add, Object Function(T) key) {
        final seen = old.map(key).toSet();
        return [...old, ...add.where((e) => seen.add(key(e)))];
      }

      if (mode == SearchMode.services) {
        // Services only: no grocery / vegetable entries, and (when something
        // really matches) no loosely related filler.
        entities = entities.where((e) => !_isGroceryEntity(e)).toList();
        final svc = entities.where((e) => e.type == 'package' || e.type == 'service').toList();
        if (page == 1) _strictSvc = svc.any((e) => serviceEntityMatches(e, query));
        if (_strictSvc) {
          entities = entities
              .where((e) => (e.type != 'package' && e.type != 'service') || serviceEntityMatches(e, query))
              .toList();
        }
        next = next.copyWith(
          categories: merge(next.categories, entities.where((e) => e.type == 'category'), (e) => e.entityId),
          services: merge(next.services, entities.where((e) => e.type == 'service'), (e) => e.entityId),
          goods: merge(next.goods, entities.where((e) => e.type == 'goods_tier'), (e) => e.entityId),
        );
        final pkgs = entities.where((e) => e.type == 'package').toList();
        next = next.copyWith(
          hitCategories: [
            ...next.hitCategories,
            for (final e in entities)
              if (e.type == 'category' && e.entityId != 0)
                e.entityId
              else if (e.type == 'package' && e.categoryId != null)
                e.categoryId!,
          ].toSet().toList(),
          hitServices: [
            ...next.hitServices,
            for (final e in entities)
              if ((e.type == 'package' || e.type == 'service') && e.serviceId != null) e.serviceId!,
          ].toSet().toList(),
        );
        if (pkgs.isNotEmpty) {
          final all = await _catalog.getAllServicesCached();
          final byId = {for (final s in all) s.id: s};
          final bySlug = {for (final s in all) s.slug.toLowerCase(): s};
          next = next.copyWith(
            packages: merge(
              next.packages,
              pkgs.map((e) =>
                  byId[e.entityId] ??
                  bySlug[(e.packageSlug ?? '').toLowerCase()] ??
                  _packageFromEntity(e)),
              (s) => s.id,
            ),
          );
        }
      } else {
        final brands = {...next.brands};
        final items = <ServiceItem>[];
        final all = entities.where((e) => e.type == 'product' && e.entityId != 0).toList();
        if (page == 1) _strict = all.any((e) => entityMatchesQuery(e, query));
        final kept = _strict ? all.where((e) => entityMatchesQuery(e, query)).toList() : all;
        if (_strict && kept.isEmpty) next = next.copyWith(hasNext: false);
        for (final e in kept) {
          // One listing per product name (500 g / 1 kg variants fold together).
          if (!_seenTitles.add(cleanKeyword(e.title))) continue;
          final item = _productFromEntity(e);
          brands[item.id] = _splitSubtitle(e.subtitle).brand;
          items.add(item);
        }
        next = next.copyWith(
          hitCategories: [
            ...next.hitCategories,
            for (final e in kept)
              if (e.categoryId != null) e.categoryId!,
          ].toSet().toList(),
        );
        next = next.copyWith(
          products: merge(next.products, items, (s) => s.id),
          brands: brands,
          // With filler dropped the server's total no longer applies.
          total: _strict ? 0 : null,
        );
      }

      // Server found nothing relevant for this mode on the first page: fall
      // back to the older catalog match.
      final nothing = mode == SearchMode.services
          ? next.categories.isEmpty && next.services.isEmpty && next.goods.isEmpty && next.packages.isEmpty
          : next.products.isEmpty;
      if (mode == SearchMode.services) {
        next = next.copyWith(
          packages: next.packages.where((s) => s.flowType != CatalogFlowType.grocery).toList(),
        );
      }
      if (page == 1 && nothing) {
        next = await _fallback(next);
      }
      if (mounted) state = next;
    } catch (e) {
      if (!mounted) return;
      if (page == 1) {
        final fb = await _fallback(state.copyWith(loading: false, loadingMore: false, clearError: true));
        if (!mounted) return;
        final nothing = mode == SearchMode.services ? fb.packages.isEmpty : fb.products.isEmpty;
        state = nothing ? fb.copyWith(error: e) : fb;
      } else {
        state = state.copyWith(loading: false, loadingMore: false, error: e);
      }
    }
  }

  Future<SearchPageState> _fallback(SearchPageState base) async {
    try {
      if (mode == SearchMode.services) {
        final result = await _catalog.searchServices(query);
        if (result is Success<List<ServiceItem>>) {
          return base.copyWith(
            packages: rankServiceResults(result.data, query)
                .where((s) => s.flowType != CatalogFlowType.grocery)
                .toList(),
            hasNext: false,
          );
        }
      } else {
        final plain = await _market.getProducts(search: query, pageSize: 60);
        if (plain is Success<MarketplaceProductPage>) {
          final groups = <int>{};
          final out = <ServiceItem>[];
          for (final p in plain.data.products) {
            final g = p.variantGroupId;
            if (g != null && !groups.add(g)) continue;
            out.add(p.toServiceItem());
          }
          return base.copyWith(products: out, hasNext: false);
        }
      }
    } catch (_) {}
    return base;
  }
}

/// One pager per (query, mode), kept for a few minutes so coming back to a
/// results page (or reopening the same search) is instant.
final searchPagerProvider = StateNotifierProvider.autoDispose
    .family<SearchPager, SearchPageState, ({String q, SearchMode mode})>((ref, p) {
  _cacheFor(ref, const Duration(minutes: 3));
  return SearchPager(
    ref.watch(apiClientProvider),
    ref.watch(catalogRepositoryProvider),
    ref.watch(marketplaceCatalogRepositoryProvider),
    normalizeQuery(p.q),
    p.mode,
  );
});

// ── Sort & filter ───────────────────────────────────────────────────────────

enum SearchSort { relevance, priceLow, priceHigh, discount }

extension SearchSortX on SearchSort {
  String get label => switch (this) {
        SearchSort.relevance => 'Relevance',
        SearchSort.priceLow => 'Price: low to high',
        SearchSort.priceHigh => 'Price: high to low',
        SearchSort.discount => 'Biggest discount',
      };
}

/// The customer's sort / filter choices for one results page (applied on the
/// phone to everything loaded so far).
class SearchRefine {
  const SearchRefine({
    this.sort = SearchSort.relevance,
    this.inStockOnly = false,
    this.dealsOnly = false,
    this.minPrice,
    this.maxPrice,
    this.departments = const {},
    this.brands = const {},
  });

  final SearchSort sort;
  final bool inStockOnly;
  final bool dealsOnly;
  final double? minPrice;
  final double? maxPrice;
  final Set<String> departments;
  final Set<String> brands;

  bool get isDefault =>
      sort == SearchSort.relevance &&
      !inStockOnly &&
      !dealsOnly &&
      minPrice == null &&
      maxPrice == null &&
      departments.isEmpty &&
      brands.isEmpty;

  /// How many filters (not counting sort) are on — shown on the Filter chip.
  int get activeFilters =>
      (inStockOnly ? 1 : 0) +
      (dealsOnly ? 1 : 0) +
      (minPrice != null || maxPrice != null ? 1 : 0) +
      departments.length +
      brands.length;

  SearchRefine copyWith({
    SearchSort? sort,
    bool? inStockOnly,
    bool? dealsOnly,
    double? minPrice,
    double? maxPrice,
    bool clearPrice = false,
    Set<String>? departments,
    Set<String>? brands,
  }) =>
      SearchRefine(
        sort: sort ?? this.sort,
        inStockOnly: inStockOnly ?? this.inStockOnly,
        dealsOnly: dealsOnly ?? this.dealsOnly,
        minPrice: clearPrice ? null : (minPrice ?? this.minPrice),
        maxPrice: clearPrice ? null : (maxPrice ?? this.maxPrice),
        departments: departments ?? this.departments,
        brands: brands ?? this.brands,
      );

  List<ServiceItem> apply(List<ServiceItem> items, {Map<int, String> brandOf = const {}}) {
    var out = items.where((s) {
      final price = s.effectivePrice.toDouble();
      if (inStockOnly && !s.inStock) return false;
      if (dealsOnly && !s.hasDiscount) return false;
      if (minPrice != null && price < minPrice!) return false;
      if (maxPrice != null && price > maxPrice!) return false;
      if (departments.isNotEmpty && !departments.contains(s.categoryName ?? '')) return false;
      if (brands.isNotEmpty && !brands.contains(brandOf[s.id] ?? '')) return false;
      return true;
    }).toList();
    switch (sort) {
      case SearchSort.relevance:
        break;
      case SearchSort.priceLow:
        out.sort((a, b) => a.effectivePrice.compareTo(b.effectivePrice));
      case SearchSort.priceHigh:
        out.sort((a, b) => b.effectivePrice.compareTo(a.effectivePrice));
      case SearchSort.discount:
        out.sort((a, b) => (b.discountPercent ?? 0).compareTo(a.discountPercent ?? 0));
    }
    return out;
  }
}

final searchRefineProvider = StateProvider.autoDispose
    .family<SearchRefine, ({String q, SearchMode mode})>((ref, _) => const SearchRefine());

/// "Did you mean ...?" — the closest known phrase to a query that found nothing.
final didYouMeanProvider = FutureProvider.autoDispose
    .family<String?, ({String q, SearchMode mode})>((ref, p) async {
  final q = normalizeQuery(p.q);
  try {
    final kws = await ref.watch(searchSuggestionsProvider((q: q, mode: p.mode)).future);
    if (kws.isNotEmpty && kws.first.toLowerCase() != q.toLowerCase() && fuzzyMatches(q, [kws.first]).isNotEmpty) {
      return kws.first;
    }
    final vocab = await ref.watch(searchVocabularyProvider(p.mode).future);
    final hits = fuzzyMatches(q, vocab, limit: 1);
    if (hits.isEmpty || hits.first.toLowerCase() == q.toLowerCase()) return null;
    return hits.first;
  } catch (_) {
    return null;
  }
});

/// The catalog search matches a query anywhere in the text, so "ac" also
/// matched "pa**ck**ing"-style descriptions and buried the real AC packages.
/// This scores each hit by how well it matches — title first, then category,
/// then whole-word description matches — drops mere substring noise, and keeps
/// the original order within each score. (Used as the fallback above.)
List<ServiceItem> rankServiceResults(
  List<ServiceItem> items,
  String query, {
  bool dropUnmatched = true,
}) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return items;
  final wordStart = RegExp(r'(^|[^a-z0-9])' + RegExp.escape(q));

  int score(ServiceItem s) {
    final title = s.title.toLowerCase();
    if (title.startsWith(q)) return 5;
    if (wordStart.hasMatch(title)) return 4;
    if (title.contains(q)) return 3;
    if ((s.categoryName ?? '').toLowerCase().contains(q)) return 2;
    if (wordStart.hasMatch(s.slug.toLowerCase())) return 2;
    if (wordStart.hasMatch((s.description ?? '').toLowerCase())) return 1;
    return 0;
  }

  final scored = <({ServiceItem item, int score, int index})>[];
  for (var i = 0; i < items.length; i++) {
    final sc = score(items[i]);
    if (sc > 0 || !dropUnmatched) scored.add((item: items[i], score: sc, index: i));
  }
  scored.sort((a, b) {
    final byScore = b.score.compareTo(a.score);
    return byScore != 0 ? byScore : a.index.compareTo(b.index);
  });
  return scored.map((e) => e.item).toList();
}

// ── Explore other ───────────────────────────────────────────────────────────

/// One category (or sub-service) in "Explore other", with a few of the
/// products / packages inside it.
class ExploreSection {
  const ExploreSection({required this.title, required this.route, required this.items, this.extra});

  final String title;
  final String route;
  final Object? extra;
  final List<ServiceItem> items;
}

/// What sits beside the search hit: the other categories inside the same
/// parent, each with some of its own items. [parent] names that parent.
class ExploreOther {
  const ExploreOther({required this.sections, this.parent});

  final String? parent;
  final List<ExploreSection> sections;
}

const _exploreSections = 5;
const _exploreItems = 8;

/// Groceries: takes the best hit's department from the Seller Hub tree (the
/// parent when the hit is a sub-category, the hit itself when it is a
/// department) and loads products from its other sub-categories — "baby soap"
/// shows more of Baby Care. Services: the same for the matched category's
/// other sub-services. Null while loading or when there is nothing to show.
final exploreOtherProvider = FutureProvider.autoDispose
    .family<ExploreOther?, ({String q, SearchMode mode})>((ref, k) async {
  final st = ref.watch(searchPagerProvider(k));
  if (st.loading) return null;
  final hits = st.hitCategories.toSet();

  if (k.mode == SearchMode.groceries) {
    if (hits.isEmpty) return null;
    final repo = ref.watch(marketplaceCatalogRepositoryProvider);
    final roots = await ref.watch(marketplaceCategoryTreeProvider.future);
    final located = <int, ({MarketplaceCategory node, MarketplaceCategory? up})>{};
    final parentOf = <int, MarketplaceCategory?>{};
    void walk(List<MarketplaceCategory> nodes, MarketplaceCategory? up) {
      for (final n in nodes) {
        parentOf[n.id] = up;
        if (hits.contains(n.id)) located[n.id] = (node: n, up: up);
        walk(n.children, n);
      }
    }

    walk(roots, null);
    if (located.isEmpty) return null;
    final ordered = st.hitCategories.where(located.containsKey).toList();
    final pick = ordered.firstWhere((id) => located[id]!.up != null, orElse: () => ordered.first);
    final hit = located[pick]!;
    // Ancestors of the hit, nearest first (the hit itself when it is a
    // top-level department). Climb until one has other categories that still
    // have products to show — "baby soap" (Baby Care > Baby Hygiene > Baby
    // Soap) ends up exploring Diapers & Wipes inside Baby Care.
    final ancestors = <MarketplaceCategory>[];
    for (var up = hit.up; up != null; up = parentOf[up.id]) {
      ancestors.add(up);
    }
    if (ancestors.isEmpty) ancestors.add(hit.node);

    List<MarketplaceCategory> usable(Iterable<MarketplaceCategory> nodes) =>
        nodes.where((c) => c.hasAnyProducts && !hits.contains(c.id)).toList();

    final shownIds = {for (final p in st.products) p.id};

    Future<ExploreSection?> load(MarketplaceCategory c) async {
      final res = await repo.getProducts(categoryId: c.id, pageSize: _exploreItems + 6);
      if (res is! Success<MarketplaceProductPage>) return null;
      final groups = <int>{};
      final items = <ServiceItem>[];
      for (final p in res.data.products) {
        final g = p.variantGroupId;
        if (g != null && !groups.add(g)) continue;
        final item = p.toServiceItem();
        if (shownIds.contains(item.id)) continue;
        items.add(item);
        if (items.length >= _exploreItems) break;
      }
      if (items.isEmpty) return null;
      return ExploreSection(
        title: c.name,
        route: '/groceries/seller-hub?category=${Uri.encodeQueryComponent(c.slug)}',
        items: items,
      );
    }

    Future<List<ExploreSection>> sectionsFor(List<MarketplaceCategory> list) async =>
        (await Future.wait(list.take(_exploreSections + 2).map(load)))
            .whereType<ExploreSection>()
            .take(_exploreSections)
            .toList();

    for (final ancestor in ancestors) {
      final sections = await sectionsFor(usable(ancestor.children));
      if (sections.isNotEmpty) return ExploreOther(parent: ancestor.name, sections: sections);
    }
    // Nothing else in this department: suggest the other departments.
    final top = ancestors.last;
    final sections = await sectionsFor(usable(roots.where((r) => r.id != top.id)));
    return sections.isEmpty ? null : ExploreOther(sections: sections);
  }

  // Services
  final catalog = ref.watch(catalogRepositoryProvider);
  final cats = (await ref.watch(categoriesProvider.future))
      .where((c) => c.isActive && c.flowType != CatalogFlowType.grocery)
      .toList();
  final hitSlugs = {for (final p in st.packages) if ((p.categorySlug ?? '').isNotEmpty) p.categorySlug!};
  Category? match;
  for (final id in st.hitCategories) {
    match = cats.where((c) => c.id == id).firstOrNull;
    if (match != null) break;
  }
  match ??= cats.where((c) => hitSlugs.contains(c.slug)).firstOrNull;
  if (match == null) return null;
  final shownIds = {for (final p in st.packages) p.id};

  Future<ExploreSection?> load(String title, String route,
      {int? categoryId, String? categorySlug, String? subSlug}) async {
    final res = await catalog.getServicesByCategory(
        categoryId: categoryId, categorySlug: categorySlug, subcategorySlug: subSlug);
    if (res is! Success<List<ServiceItem>>) return null;
    final items = res.data.where((s) => !shownIds.contains(s.id)).take(3).toList();
    if (items.isEmpty) return null;
    return ExploreSection(title: title, route: route, items: items);
  }

  var subList = match.subcategories;
  try {
    subList = await ref.watch(subServicesProvider(match.slug).future);
  } catch (_) {}
  final hitServices = st.hitServices.toSet();
  final subs = subList.where((s) => !hitServices.contains(s.id)).toList();
  if (subs.isNotEmpty && subList.length >= 2) {
    final sections = (await Future.wait(subs.take(_exploreSections + 2).map((s) => load(
          s.name,
          '/categories/${match!.slug}?sub=${Uri.encodeQueryComponent(s.slug)}',
          categoryId: match.id,
          categorySlug: match.slug,
          subSlug: s.slug,
        ))))
        .whereType<ExploreSection>()
        .take(_exploreSections)
        .toList();
    if (sections.isNotEmpty) return ExploreOther(parent: match.name, sections: sections);
  }
  final others = cats.where((c) => c.id != match!.id).take(_exploreSections + 2).toList();
  final sections = (await Future.wait(others.map((c) => load(c.name, '/categories/${c.slug}', categoryId: c.id, categorySlug: c.slug))))
      .whereType<ExploreSection>()
      .take(_exploreSections)
      .toList();
  return sections.isEmpty ? null : ExploreOther(sections: sections);
});
