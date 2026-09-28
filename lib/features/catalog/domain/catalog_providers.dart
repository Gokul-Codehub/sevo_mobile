import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/api_error.dart';
import '../data/catalog_repository.dart';
import 'catalog_models.dart';

/// Provider for list of all categories.
final categoriesProvider = FutureProvider<List<Category>>((ref) async {
  ref.keepAlive();
  final repo = ref.watch(catalogRepositoryProvider);
  final result = await repo.getCategories();

  return switch (result) {
    Success(:final data) => data,
    Failure(:final error) => throw error,
  };
});

/// Parameter for fetching services by category ID / slug and optional subcategory.
class CategoryServicesParam {
  const CategoryServicesParam({
    this.categoryId,
    required this.categorySlug,
    this.subcategorySlug,
  });

  final int? categoryId;
  final String categorySlug;
  final String? subcategorySlug;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CategoryServicesParam &&
          runtimeType == other.runtimeType &&
          categoryId == other.categoryId &&
          categorySlug == other.categorySlug &&
          subcategorySlug == other.subcategorySlug;

  @override
  int get hashCode =>
      (categoryId ?? 0).hashCode ^ categorySlug.hashCode ^ (subcategorySlug?.hashCode ?? 0);
}

/// Provider for sub-services (subcategories) under a category.
final subServicesProvider =
    FutureProvider.family<List<Subcategory>, String>((ref, categorySlug) async {
  ref.keepAlive();
  final repo = ref.watch(catalogRepositoryProvider);
  final result = await repo.getSubServicesByCategory(categorySlug: categorySlug);

  return switch (result) {
    Success(:final data) => data,
    Failure(:final error) => throw error,
  };
});

/// Provider for services under a category / subcategory.
final categoryServicesProvider =
    FutureProvider.family<List<ServiceItem>, CategoryServicesParam>(
        (ref, param) async {
  ref.keepAlive();
  final repo = ref.watch(catalogRepositoryProvider);
  final result = await repo.getServicesByCategory(
    categoryId: param.categoryId,
    categorySlug: param.categorySlug,
    subcategorySlug: param.subcategorySlug,
  );

  return switch (result) {
    Success(:final data) => data,
    Failure(:final error) => throw error,
  };
});

/// Provider for a single service item detail.
final serviceDetailProvider =
    FutureProvider.family<ServiceItem, String>((ref, slug) async {
  ref.keepAlive();
  final repo = ref.watch(catalogRepositoryProvider);
  final result = await repo.getServiceDetail(slug);

  return switch (result) {
    Success(:final data) => data,
    Failure(:final error) => throw error,
  };
});

/// Current active search query.
final searchQueryProvider = StateProvider<String>((ref) => '');

/// Provider for search results based on active query.
final searchResultsProvider = FutureProvider<List<ServiceItem>>((ref) async {
  final query = ref.watch(searchQueryProvider).trim();
  if (query.isEmpty) return const [];

  final repo = ref.watch(catalogRepositoryProvider);
  final result = await repo.searchServices(query);

  return switch (result) {
    Success(:final data) => data,
    Failure(:final error) => throw error,
  };
});

/// Provider for Farm-Fresh grocery produce items.
/// Used in the cart's "Frequently Added Produce" section to show real API items.
///
/// Fixed 2026-09-01: no longer hardcodes categoryId: 18 / categorySlug:
/// 'vegetables_groceries' — those were a guess at what the admin's grocery
/// category happens to be called today. This now reads the LIVE category
/// list (whatever the admin's Service Catalog portal currently manages) and
/// picks whichever category that live data itself flags as the grocery
/// flow, so a renamed or re-IDed grocery category (or one that doesn't
/// exist yet) is reflected correctly instead of silently querying a
/// category that may no longer be there.
final groceryProduceProvider = FutureProvider<List<ServiceItem>>((ref) async {
  ref.keepAlive();
  final categories = await ref.watch(categoriesProvider.future);
  final groceryCategory =
      categories.where((c) => c.flowType == CatalogFlowType.grocery).firstOrNull;
  if (groceryCategory == null) return const [];

  final repo = ref.watch(catalogRepositoryProvider);
  final result = await repo.getServicesByCategory(
    categoryId: groceryCategory.id,
    categorySlug: groceryCategory.slug,
  );

  // Fixed 2026-09-23 per explicit request ("In Essential picks too it
  // getting vegetables from different endpoint... make sure the data only
  // come from admin -> vegetable inventory") — same fix as
  // CategoryDetailScreen's grocery grid: `/catalog/services/` returns
  // every Package filed under the grocery Category, including any added
  // directly in the admin's plain Service Catalog rather than through the
  // Vegetable Inventory bulk-upload/approval flow. Those carry no real
  // vegetable-category tag, so this strip (and anywhere else that reads
  // this provider) is now filtered to items that actually have one.
  //
  // Fixed again 2026-09-23 — confirmed by the user directly in the admin
  // panel: `hasVegetableCategory` alone wasn't enough. "Ash Gourd (Sambar
  // Pusanikkai)" carried a non-empty vegetable_category_name/_slug from
  // the API but does NOT appear anywhere under admin -> Vegetable
  // Inventory -> Vegetable Categories — its linked category exists in the
  // database (old seed-script data, per `getApprovedVegetableCategorySlugs`
  // doc comment) but isn't a real, approved admin category. Every item is
  // now cross-checked against the live set of APPROVED category slugs, so
  // only produce that's genuinely visible in the admin's own Vegetable
  // Categories page gets through.
  final approvedSlugs = await ref.watch(approvedVegetableCategorySlugsProvider.future);

  return switch (result) {
    Success(:final data) => data
        .where((s) =>
            s.hasVegetableCategory &&
            approvedSlugs.contains(s.vegetableCategorySlug!.toLowerCase().trim()))
        .toList(),
    Failure(:final error) => throw error,
  };
});

/// Provider for the admin's real Vegetable Inventory top-level departments
/// (e.g. "Fresh Vegetables", "Fresh Fruits", "Coriander & Others") — includes
/// departments with zero produce filed under them yet, unlike deriving
/// departments purely from already-fetched products. See
/// [VegetableCategorySummary] and `CategoryDetailScreen`'s department strip.
final vegetableDepartmentsProvider =
    FutureProvider<List<VegetableCategorySummary>>((ref) async {
  ref.keepAlive();
  final repo = ref.watch(catalogRepositoryProvider);
  final result = await repo.getVegetableDepartments();

  return switch (result) {
    Success(:final data) => data,
    Failure(:final error) => throw error,
  };
});

/// Every APPROVED Vegetable Inventory category slug, at any depth — the
/// cross-check that decides whether an item's `vegetable_category_slug` is
/// genuinely real, admin-visible data (see [CatalogRepository.
/// getApprovedVegetableCategorySlugs] doc comment for why
/// `hasVegetableCategory` alone isn't sufficient).
final approvedVegetableCategorySlugsProvider = FutureProvider<Set<String>>((ref) async {
  ref.keepAlive();
  final repo = ref.watch(catalogRepositoryProvider);
  final result = await repo.getApprovedVegetableCategorySlugs();

  return switch (result) {
    Success(:final data) => data,
    Failure(:final error) => throw error,
  };
});

/// Provider for popular featured services on Home Screen.
///
/// Fixed 2026-09-01: previously hardcoded to categoryId 15 ('ac_appliance')
/// only (the "Home Cleaning (16)" half of the old doc comment was never
/// actually wired up). Now pulls from the live, admin-managed category
/// list — every currently-active service-booking category (not the
/// grocery flow, which has its own "Essential Picks" strip) contributes a
/// few items, so this strip reflects whatever categories the admin
/// actually has today rather than a fixed guess.
final popularServicesProvider = FutureProvider<List<ServiceItem>>((ref) async {
  ref.keepAlive();
  final categories = await ref.watch(categoriesProvider.future);
  // Fixed 2026-09-19: strict `== serviceBooking` silently dropped Goods &
  // Transport the moment CatalogFlowType.logistics became a distinct value
  // — this strip is meant to be "every non-grocery category" (grocery has
  // its own "Essential Picks" strip), not specifically serviceBooking.
  final serviceCategories = categories
      .where((c) => c.flowType != CatalogFlowType.grocery && c.isActive)
      .toList();
  if (serviceCategories.isEmpty) return const [];

  final repo = ref.watch(catalogRepositoryProvider);
  final results = await Future.wait(serviceCategories.map(
    (c) => repo.getServicesByCategory(categoryId: c.id, categorySlug: c.slug),
  ));

  final items = <ServiceItem>[];
  for (final result in results) {
    if (result is Success<List<ServiceItem>>) items.addAll(result.data);
  }
  return items;
});
