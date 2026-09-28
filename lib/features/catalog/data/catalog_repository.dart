import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/api_error.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/response_normalizer.dart';
import '../../../core/utils/app_logger.dart';
import '../domain/catalog_models.dart';

/// Repository for fetching categories and services.
class CatalogRepository {
  CatalogRepository({required this.api});

  final ApiClient api;

  // ── Last-known-good guard for getServicesByCategory ───────────────────────
  //
  // Root cause note (2026-08-26): a real device confirmed the catalog list
  // for a category can go from N items to 0 items after leaving and
  // re-entering the screen, with the SAME query params both times (verified:
  // no code path derives categoryId/categorySlug/subcategorySlug from cart
  // state — see docs/CalServices_Cart_Catalog_RootCause_Audit.md). Since a
  // stable vegetable/service catalog cannot legitimately go from "15 items"
  // to "0 items" between two requests seconds apart for the identical
  // query, this is treated as a transient/anomalous response (flaky
  // network, a backend hiccup, a load balancer routing to a stale replica,
  // etc.) rather than truth. This cache remembers the last non-empty result
  // per exact query key and serves it instead of a suspicious empty one,
  // while logging loudly so the anomaly is never silently hidden. It is a
  // resilience guard, not a substitute for finding why the empty response
  // happens — remove it once that's confirmed and fixed server-side.
  static final Map<String, List<ServiceItem>> _lastKnownGoodByKey = {};

  static String _cacheKey(int? resolvedId, String? canonicalSlug, String? subcategorySlug) =>
      '${resolvedId ?? ''}|${canonicalSlug ?? ''}|${subcategorySlug ?? ''}';

  // ── Fetch all categories ──────────────────────────────────────────────────
  Future<Result<List<Category>>> getCategories() async {
    try {
      final response = await api.get('/catalog/categories/');
      return ResponseNormalizer.extract(response, (data) {
        final list = data is List
            ? data
            : (data is Map && data['results'] is List
                ? data['results'] as List
                : (data is Map && data['data'] is List ? data['data'] as List : []));

        return list
            .whereType<Map>()
            .map((m) => Category.fromJson(Map<String, dynamic>.from(m)))
            .toList();
      });
    } on Exception catch (e) {
      return Failure(_toError(e));
    }
  }

  // ── Fetch sub-services for a category ────────────────────────────────────
  Future<Result<List<Subcategory>>> getSubServicesByCategory({
    required String categorySlug,
  }) async {
    try {
      // Fixed 2026-09-01: previously ran categorySlug through
      // _resolveCategorySlug's hardcoded keyword→slug guess-table; now
      // passed straight through as given by the caller (the real admin
      // category slug from the live categoriesProvider).
      final response = await api.get(
        '/catalog/sub-services/',
        queryParameters: {'category_slug': categorySlug},
      );
      return ResponseNormalizer.extract(response, (data) {
        final list = data is List
            ? data
            : (data is Map && data['results'] is List
                ? data['results'] as List
                : (data is Map && data['data'] is List ? data['data'] as List : []));

        return list
            .whereType<Map>()
            .map((m) => Subcategory.fromJson(Map<String, dynamic>.from(m)))
            .toList();
      });
    } on Exception catch (e) {
      return Failure(_toError(e));
    }
  }

  // ── Fetch services for a category ─────────────────────────────────────────
  Future<Result<List<ServiceItem>>> getServicesByCategory({
    int? categoryId,
    String? categorySlug,
    String? subcategorySlug,
  }) async {
    try {
      // Fixed 2026-09-01: this used to run categoryId/categorySlug through
      // _resolveCategoryId/_resolveCategorySlug, which guessed an ID/slug by
      // matching keywords against a FIXED, hand-enumerated list of
      // categories (AC & Appliance, Electrician/Plumbing/Carpentry,
      // Vegetables & Groceries, Mason, Paintings, ...). That list is exactly
      // the "hardcoded categories" problem: the real categories and their
      // IDs are whatever the admin portal's Service Catalog currently has
      // (see admin's Catalog > Services tab) and can be renamed, added to,
      // or removed at any time — a guess-table here silently mismatches or
      // drops any category the admin adds that this list doesn't know
      // about, and can misroute an admin-renamed category to the wrong
      // hardcoded ID. The caller (categoriesProvider-backed screens) is
      // expected to pass the REAL id/slug straight from the live
      // /catalog/categories/ response now — this method just uses exactly
      // what it's given, with no keyword-based reinterpretation.
      final resolvedId = (categoryId != null && categoryId > 0) ? categoryId : null;
      final canonicalSlug = categorySlug?.trim();
      final query = <String, dynamic>{
        if (resolvedId != null && resolvedId > 0)
          'category_id': resolvedId.toString()
        else if (canonicalSlug != null && canonicalSlug.isNotEmpty)
          'category': canonicalSlug,
      };

      AppLogger.d('[P0-CATALOG]',
          'request started: categoryId=$categoryId, resolvedId=$resolvedId, categorySlug=$categorySlug, subcategorySlug=$subcategorySlug, query=$query');

      final response = await api.get('/catalog/services/', queryParameters: query);
      AppLogger.d('[P0-CATALOG]', 'HTTP status=${response.statusCode}');

      final result = ResponseNormalizer.extract(response, (data) {
        final list = data is List
            ? data
            : (data is Map && data['results'] is List
                ? data['results'] as List
                : (data is Map && data['data'] is List ? data['data'] as List : []));

        AppLogger.d('[P0-CATALOG]', 'response item count=${list.length}');
        if (list.isEmpty) {
          // Diagnostic only: distinguishes "VPS returned zero items" (CASE B)
          // from a client-side parsing bug (CASE A) without needing a
          // separate network capture. Data shape is logged, not contents.
          AppLogger.d('[P0-CATALOG]',
              'EMPTY_RESULT diagnostic: rawDataType=${data.runtimeType}, '
              'rawDataKeys=${data is Map ? (data).keys.toList() : 'n/a'}, '
              'query=$query');
        }

        var items = list
            .whereType<Map>()
            .map((m) => ServiceItem.fromJson(Map<String, dynamic>.from(m)))
            .toList();

        AppLogger.d('[P0-CATALOG]', 'parsed item count=${items.length}');

        // If in-memory subcategory filtering is applicable
        if (subcategorySlug != null && subcategorySlug.isNotEmpty && items.isNotEmpty) {
          final subLower = subcategorySlug.toLowerCase().replaceAll('-', '_');
          final beforeCount = items.length;
          final filtered = items.where((i) {
            final sSlug = i.slug.toLowerCase().replaceAll('-', '_');
            final subSlug = (i.subcategorySlug ?? '').toLowerCase().replaceAll('-', '_');
            final subName = (i.subcategoryName ?? '').toLowerCase().replaceAll('-', '_');
            return subSlug == subLower ||
                subSlug.contains(subLower) ||
                subName.contains(subLower) ||
                sSlug.contains(subLower);
          }).toList();
          AppLogger.d('[P0-CART]',
              'UI_FILTER subcategorySlug="$subcategorySlug": before=$beforeCount, after=${filtered.length}');
          if (filtered.isNotEmpty) {
            items = filtered;
          }
        }

        return items;
      });

      // ── Last-known-good guard ──────────────────────────────────────────
      // Only engages for an unfiltered category/subcategory fetch (the exact
      // shape that renders the category listing screen) — never touches
      // search results or any other query.
      final cacheKey = _cacheKey(resolvedId, canonicalSlug, subcategorySlug);
      if (result is Success<List<ServiceItem>>) {
        if (result.data.isNotEmpty) {
          _lastKnownGoodByKey[cacheKey] = result.data;
          return result;
        }
        final previous = _lastKnownGoodByKey[cacheKey];
        if (previous != null && previous.isNotEmpty) {
          AppLogger.d('[P0-CATALOG]',
              'ANOMALY: query returned 0 items for a category that previously had ${previous.length} — '
              'serving last-known-good list instead of regressing the UI to empty. '
              'key=$cacheKey, query=$query');
          return Success(previous);
        }
      }
      return result;
    } on Exception catch (e) {
      return Failure(_toError(e));
    }
  }

  // Fixed 2026-09-01: removed _resolveCategorySlug/_resolveCategoryId — both
  // were a fixed, hand-maintained keyword→ID guess-table covering only the
  // categories that existed at one point in time (AC & Appliance,
  // Electrician/Plumbing/Carpentry, Vegetables & Groceries, Mason,
  // Paintings, ...). The admin's Service Catalog portal is the only source
  // of truth for real category IDs/slugs/names now (they can be renamed,
  // added, or removed there at any time) — nothing in this repository
  // reinterprets or guesses them anymore; getServicesByCategory above uses
  // exactly the categoryId/categorySlug it's given.

  // Per-probe timeout for the multi-strategy lookup below. The shared Dio
  // client's default is 30s; without this, a grocery-item lookup that misses
  // strategy 1 can chain up to 3 full 30s timeouts (~90s) before surfacing
  // "not found" when the backend is unreachable. Bounding each probe to 10s
  // caps the worst case at ~30s and only affects this fallback chain — it
  // does not change the timeout used by normal category browsing or search.
  static const _probeTimeout = Duration(seconds: 10);

  // ── Fetch single service detail ───────────────────────────────────────────
  Future<Result<ServiceItem>> getServiceDetail(String identifier) async {
    try {
      final cleanId = identifier.trim();
      final numStr = cleanId.startsWith('svc-') ? cleanId.substring(4) : cleanId;
      final matchId = int.tryParse(numStr);

      // 0. Check in-memory cache of already loaded services across all categories
      for (final list in _lastKnownGoodByKey.values) {
        for (final item in list) {
          if (matchId != null && item.id == matchId) return Success(item);
          if (item.slug.toLowerCase() == cleanId.toLowerCase()) return Success(item);
          if (item.title.toLowerCase() == cleanId.toLowerCase()) return Success(item);
        }
      }

      // 1. Direct query with service_slug
      try {
        final slugResponse = await api
            .get('/catalog/services/', queryParameters: {'service_slug': cleanId})
            .timeout(_probeTimeout);
        final slugResult = ResponseNormalizer.extract(slugResponse, (data) {
          final list = data is List
              ? data
              : (data is Map && data['results'] is List
                  ? data['results'] as List
                  : (data is Map && data['data'] is List ? data['data'] as List : []));
          return list
              .whereType<Map>()
              .map((m) => ServiceItem.fromJson(Map<String, dynamic>.from(m)))
              .toList();
        });

        if (slugResult is Success<List<ServiceItem>> && slugResult.data.isNotEmpty) {
          for (final item in slugResult.data) {
            if (matchId != null && item.id == matchId) return Success(item);
            if (item.slug.toLowerCase() == cleanId.toLowerCase()) return Success(item);
          }
          return Success(slugResult.data.first);
        }
      } catch (e) {
        AppLogger.d('[P0-CATALOG]', 'getServiceDetail strategy 1 failed: $e');
      }

      // 2. Fetch all active categories and search within each category via getServicesByCategory
      try {
        final categoriesRes = await getCategories().timeout(_probeTimeout);
        if (categoriesRes is Success<List<Category>>) {
          final activeCats = categoriesRes.data.where((c) => c.isActive).toList();
          final results = await Future.wait(activeCats.map(
            (c) => getServicesByCategory(categoryId: c.id, categorySlug: c.slug)
                .timeout(_probeTimeout, onTimeout: () => const Failure(NetworkError('Timed out'))),
          ));

          for (final res in results) {
            if (res is Success<List<ServiceItem>>) {
              for (final item in res.data) {
                if (matchId != null && item.id == matchId) return Success(item);
                if (item.slug.toLowerCase() == cleanId.toLowerCase()) return Success(item);
                if (item.title.toLowerCase() == cleanId.toLowerCase()) return Success(item);
              }
            }
          }
        }
      } catch (e) {
        AppLogger.d('[P0-CATALOG]', 'getServiceDetail strategy 2 failed: $e');
      }

      AppLogger.d('[CatalogRepository]', '"$cleanId" not found on VPS after probe strategies.');
      return Failure(const NotFoundError('Service not found on production server.'));
    } on Exception catch (e) {
      return Failure(_toError(e));
    }
  }

  // ── Search catalog ────────────────────────────────────────────────────────
  //
  // Fixed 2026-09-28 per explicit report, shown via screenshots ("see here
  // it always return this only.." — every query, e.g. "sunflower oil" and
  // "ac installation", returned the exact same top two items): the network
  // branch below trusted ANY non-empty response from `/catalog/services/
  // ?search=<query>` as already correctly filtered. The backend endpoint
  // does not reliably honor that `search` param — for at least some
  // queries it silently returns its normal unfiltered/default-ordered
  // list, and since that list is non-empty, the old code returned it
  // as-is instead of ever reaching the (correctly-filtering) cache
  // fallback below. The same match criteria the fallback already used is
  // now applied to the network response too, so a query only ever
  // surfaces items that actually match it, regardless of whether the
  // backend itself filtered anything.
  bool _serviceMatchesQuery(ServiceItem s, String cleanQuery) =>
      s.title.toLowerCase().contains(cleanQuery) ||
      s.slug.toLowerCase().contains(cleanQuery) ||
      (s.description?.toLowerCase().contains(cleanQuery) ?? false) ||
      (s.categoryName?.toLowerCase().contains(cleanQuery) ?? false);

  Future<Result<List<ServiceItem>>> searchServices(String query) async {
    final clean = query.trim().toLowerCase();
    if (clean.isEmpty) return const Success([]);

    try {
      final response = await api.get(
        '/catalog/services/',
        queryParameters: {'search': query},
      );
      final res = ResponseNormalizer.extract(response, (data) {
        final list = data is List
            ? data
            : (data is Map && data['results'] is List
                ? data['results'] as List
                : (data is Map && data['data'] is List ? data['data'] as List : []));

        return list
            .whereType<Map>()
            .map((m) => ServiceItem.fromJson(Map<String, dynamic>.from(m)))
            .toList();
      });
      if (res is Success<List<ServiceItem>>) {
        final filtered =
            res.data.where((s) => _serviceMatchesQuery(s, clean)).toList();
        if (filtered.isNotEmpty) {
          return Success(filtered);
        }
      }
    } catch (e) {
      AppLogger.d('[P0-CATALOG]', 'searchServices network search error: $e');
    }

    // Safe fallback: search loaded cache and active categories
    final matches = <int, ServiceItem>{};
    for (final list in _lastKnownGoodByKey.values) {
      for (final s in list) {
        if (_serviceMatchesQuery(s, clean)) {
          matches[s.id] = s;
        }
      }
    }
    return Success(matches.values.toList());
  }

  // ── Fetch admin Vegetable Inventory top-level departments ─────────────────
  //
  // Added 2026-09-23: the real, admin-managed department list (see
  // [VegetableCategorySummary] doc comment) — includes departments with
  // zero produce today, unlike deriving departments purely from already-
  // fetched products.
  //
  // Bug fixed 2026-09-23 (real-device screenshot: two "All" tiles side by
  // side — the app's own synthetic "All" tile, plus a second "All" that
  // came straight from this API): `only_roots=true` on the backend
  // (inventory/views.py VegetableCategoryListCreateView.get) matches
  // `Q(parent__isnull=True) | Q(parent_id__in=all_root_ids)` — which
  // deliberately includes the admin's own pseudo-root "All" node itself
  // (it has parent=null), not just its real children (Fresh Vegetables,
  // Fresh Fruits, ...). The backend needs that node included so `depth`/
  // `ancestors` resolve correctly for its children.
  //
  // Fixed again 2026-09-23: matching that node by `name`/`slug == "all"`
  // alone turned out not to be reliable enough on its own (still surfaced
  // after a rebuild) — filtering is now keyed off actual tree structure
  // instead: whenever this response contains at least one node with a
  // real `parent`, EVERY null-parent node in it is a root wrapper (the
  // "All" node itself, or a duplicate of it), never a real department, so
  // all of them are dropped. Only when nothing here has a parent at all
  // (a flat top-level list, no "All" wrapper convention in use) are
  // null-parent nodes kept, since those are then the real departments.
  // The name/slug=="all" check stays as a second, independent guard.
  Future<Result<List<VegetableCategorySummary>>> getVegetableDepartments() async {
    try {
      final response = await api.get(
        '/inventory/vegetable-categories/',
        queryParameters: {'status': 'APPROVED', 'only_roots': 'true'},
      );
      return ResponseNormalizer.extract(response, (data) {
        final list = data is List
            ? data
            : (data is Map && data['results'] is List
                ? data['results'] as List
                : (data is Map && data['data'] is List ? data['data'] as List : []));

        final parsed = list
            .whereType<Map>()
            .map((m) => VegetableCategorySummary.fromJson(Map<String, dynamic>.from(m)))
            .where((cat) => cat.slug.toLowerCase() != 'all' && cat.name.toLowerCase() != 'all')
            .toList();

        final hasRealChild = parsed.any((cat) => cat.parentId != null);
        return hasRealChild
            ? parsed.where((cat) => cat.parentId != null).toList()
            : parsed;
      });
    } on Exception catch (e) {
      return Failure(_toError(e));
    }
  }

  // ── Fetch every APPROVED Vegetable Inventory category slug ────────────────
  //
  // Added 2026-09-23 — confirmed directly by the user checking the admin
  // panel: "Ash Gourd (Sambar Pusanikkai)" still showed up in the grocery
  // grid / Essential Picks after the earlier `hasVegetableCategory` filter,
  // but does NOT appear anywhere under admin -> Vegetable Inventory ->
  // Vegetable Categories. Root cause: `CatalogServiceSerializer.
  // vegetable_category_name/_slug` (service_requests/serializers.py) is a
  // plain `source="stock_item.category.name"` traversal with no status or
  // is_active check at all — a Package whose linked Vegetable points at a
  // category that is PENDING, REJECTED, or inactive (old seed-script data
  // from before this admin module existed, in this case) still serializes
  // a non-empty vegetable_category_name, so `hasVegetableCategory` alone
  // isn't a strong enough signal that a category is real, admin-approved
  // Vegetable Inventory data. This fetches the flat set of every category
  // slug that genuinely IS approved (no `only_roots` — a leaf like "Ash
  // Gourd"'s real category could be nested at any depth), so callers can
  // cross-check `ServiceItem.vegetableCategorySlug` against it directly.
  Future<Result<Set<String>>> getApprovedVegetableCategorySlugs() async {
    try {
      final response = await api.get(
        '/inventory/vegetable-categories/',
        queryParameters: {'status': 'APPROVED'},
      );
      return ResponseNormalizer.extract(response, (data) {
        final list = data is List
            ? data
            : (data is Map && data['results'] is List
                ? data['results'] as List
                : (data is Map && data['data'] is List ? data['data'] as List : []));

        return list
            .whereType<Map>()
            .map((m) => m['slug']?.toString().toLowerCase().trim())
            .whereType<String>()
            .where((slug) => slug.isNotEmpty)
            .toSet();
      });
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

// ── Provider ─────────────────────────────────────────────────────────────────
final catalogRepositoryProvider = Provider<CatalogRepository>((ref) {
  return CatalogRepository(api: ref.watch(apiClientProvider));
});
