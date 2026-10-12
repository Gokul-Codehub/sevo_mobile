import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/utils/app_logger.dart';
import '../../../../routing/app_router.dart';
import '../../../../shared/theme/app_colors.dart';
import '../../../../shared/widgets/app_remote_image.dart';
import '../../../../shared/widgets/common_widgets.dart';
import '../../../../shared/widgets/listing_skeleton.dart';
import '../../../booking/domain/booking_models.dart';
import '../../../booking/domain/cart_notifier.dart';
import '../../domain/catalog_models.dart';
import '../../domain/catalog_providers.dart';
import '../widgets/product_card.dart';
import '../widgets/service_card.dart';

/// Blinkit-style circular department tile (e.g. "Fresh Vegetables", "Fresh
/// Fruits") built from the Vegetable Inventory category each product
/// carries — see [VegetableDepartmentGroup] / [ServiceItem.vegetableDepartmentName].
///
/// Restored 2026-09-23 as a persistent VERTICAL rail per explicit request
/// ("you removed the previous layout... make it like the uploaded image",
/// a reference screenshot of the app's own long-standing left-hand
/// department rail + independently-scrolling right-hand product grid). A
/// horizontal top-strip version of this tile briefly replaced that layout
/// earlier the same day — this widget is that rail tile, not the strip one.
class _VerticalDepartmentTile extends StatelessWidget {
  const _VerticalDepartmentTile({
    required this.label,
    required this.selected,
    required this.onTap,
    this.image,
    this.icon = Icons.eco_rounded,
    this.accent = AppColors.groceryGreen,
    this.accentLight = AppColors.groceryGreenLight,
    this.accentDark = AppColors.groceryGreenDark,
  });

  /// Selection / ring colors — grocery green by default, service blue for the
  /// services rail.
  final Color accent;
  final Color accentLight;
  final Color accentDark;

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final String? image;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
        decoration: BoxDecoration(
          color: selected ? AppColors.background : Colors.transparent,
          border: Border(
            right: BorderSide(
              color: selected ? accent : Colors.transparent,
              width: 3,
            ),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 52,
              height: 52,
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: selected ? accent : Colors.transparent,
                  width: 2,
                ),
                color: accentLight,
              ),
              child: ClipOval(
                child: image != null
                    ? AppRemoteImage(
                        imageUrl: image,
                        title: label,
                        fit: BoxFit.cover,
                        semanticIcon: icon,
                      )
                    : Icon(icon, color: accentDark, size: 24),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              label,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                color: selected ? AppColors.navy : AppColors.textPrimary,
                height: 1.2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Generic, category-agnostic hero copy + accent look for the banner shown
/// at the top of this screen — client-side keyword mapping (no such
/// marketing-copy fields exist on the backend's Category model), matching
/// the same approach `AllServicesScreen`'s `_styleFor` uses for its own
/// grid tiles. Falls back to copy built from the real category name for
/// any category outside the known keyword set, so a newly-added admin
/// category never breaks this banner.
class _HeroCopy {
  const _HeroCopy({
    required this.icon,
    required this.color,
    required this.tagline,
    required this.headline1,
    required this.headline2,
    required this.subtext,
  });

  final IconData icon;
  final Color color;
  final String tagline;
  final String headline1;
  final String headline2;
  final String subtext;
}

_HeroCopy _heroCopyFor(String slug, String name) {
  final s = '$slug $name'.toLowerCase();
  if (s.contains('ac') || s.contains('appliance')) {
    return const _HeroCopy(
      icon: Icons.ac_unit_rounded,
      color: AppColors.serviceBlue,
      tagline: 'Cooling Comfort, Anytime',
      headline1: 'Keep Your Home Cool',
      headline2: '& Hassle-Free',
      subtext: 'Expert service for all your appliances',
    );
  }
  if (s.contains('good') || s.contains('transport') || s.contains('truck')) {
    return const _HeroCopy(
      icon: Icons.local_shipping_rounded,
      color: AppColors.groceryGreen,
      tagline: 'Safe & Reliable Moves',
      headline1: 'Move Your Goods',
      headline2: '& Hassle-Free',
      subtext: 'Reliable transport for all your shifting needs',
    );
  }
  if (s.contains('clean') || s.contains('pest')) {
    return const _HeroCopy(
      icon: Icons.home_rounded,
      color: Color(0xFF7C3AED),
      tagline: 'Healthier Homes, Guaranteed',
      headline1: 'Keep Your Home Clean',
      headline2: '& Hassle-Free',
      subtext: 'Expert cleaning & pest control, done right',
    );
  }
  if (s.contains('mason') || s.contains('construct')) {
    return const _HeroCopy(
      icon: Icons.foundation_rounded,
      color: AppColors.warning,
      tagline: 'Strong Foundations, Better Homes',
      headline1: 'Build It Strong',
      headline2: '& Hassle-Free',
      subtext: 'Expert construction & repair work',
    );
  }
  if (s.contains('paint')) {
    return const _HeroCopy(
      icon: Icons.format_paint_rounded,
      color: Color(0xFFEC4899),
      tagline: 'Color Your Dreams',
      headline1: 'Color Your Home',
      headline2: '& Hassle-Free',
      subtext: 'Expert painting, interior & exterior',
    );
  }
  if (s.contains('plumb') || s.contains('electric') || s.contains('carpenter')) {
    return const _HeroCopy(
      icon: Icons.build_rounded,
      color: AppColors.serviceBlue,
      tagline: 'Fixed Right, First Time',
      headline1: 'Fix It Right',
      headline2: '& Hassle-Free',
      subtext: 'Expert repairs & installations',
    );
  }
  return _HeroCopy(
    icon: Icons.home_repair_service_rounded,
    color: AppColors.primary,
    tagline: 'Trusted Professionals, Anytime',
    headline1: name,
    headline2: '& Hassle-Free',
    subtext: 'Expert service, done right',
  );
}


/// Pill-shaped filter chip matching the reference screenshot's rounded,
/// colored-when-selected subcategory filters — replaces the plain Material
/// `ChoiceChip` previously used here.
class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? AppColors.primary : Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected ? AppColors.primary : AppColors.border,
            width: 1.2,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              selected ? Icons.check_circle_rounded : Icons.circle_outlined,
              size: 14,
              color: selected ? Colors.white : AppColors.textSecondary,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: selected ? Colors.white : AppColors.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Screen displaying services within a specific category with subcategory filtering.
class CategoryDetailScreen extends ConsumerStatefulWidget {
  const CategoryDetailScreen({
    super.key,
    required this.categorySlug,
    this.initialCategory,
  });

  final String categorySlug;
  final Category? initialCategory;

  @override
  ConsumerState<CategoryDetailScreen> createState() =>
      _CategoryDetailScreenState();
}

class _CategoryDetailScreenState extends ConsumerState<CategoryDetailScreen> {
  String? _selectedSubcategorySlug;

  // Fixed 2026-10-08 (QA CMP02/CMP03/CMP06 — "the page should automatically
  // refresh/update the latest data without requiring the user to manually
  // reload" / an admin-deleted package or service still showing): every
  // catalog provider (catalog_providers.dart) is a plain `ref.keepAlive()`
  // FutureProvider — correct for making catalog browsing feel instant, but
  // it means a response fetched once stays cached for as long as the app
  // process is alive, with nothing to ever ask the backend again. This app
  // has no catalog push/websocket, so the realistic, testable version of
  // "auto-refresh" is: ask again every time the customer actually opens
  // this screen. Invalidating (not refreshing) a FutureProvider.family
  // with no argument re-fetches every currently-alive instance of it, and
  // Riverpod's `AsyncValue.when` skips the loading branch on a refresh by
  // default (`skipLoadingOnRefresh: true`) as long as previous data
  // exists — so this silently re-syncs in the background and swaps in
  // fresh data (or quietly drops a since-deleted/deactivated package) the
  // next time this screen builds, without flashing the shimmer loader seen
  // on a genuine first-ever load.
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.invalidate(categoryServicesProvider);
      ref.invalidate(subServicesProvider);
    });
  }

  // Vegetable Inventory department browse (added 2026-09-23) — independent
  // of [_selectedSubcategorySlug] above (that one filters by the flat
  // Service-level subcategory the admin's older Service Catalog exposes;
  // this pair filters by the deep VegetableCategory tree the new "Vegetable
  // Inventory" admin module builds — see [groupServiceItemsByDepartment]).
  // Selecting a department resets the subcategory, since a department's own
  // subcategory names are meaningless once a different department is picked.
  String? _selectedDepartment;
  String? _selectedVegSubcategory;

  void _selectDepartment(String? department) {
    setState(() {
      _selectedDepartment = department;
      _selectedVegSubcategory = null;
    });
  }

  // Added 2026-09-20 per explicit request: "For specifically for Goods and
  // Transport - Do not list the services like Mini truck, 2wheeler" — this
  // screen must never render the normal per-package list for a logistics
  // category, from ANY entry point (home tiles, All Services grid, search,
  // Book Again, a raw deep link into /categories/:slug — all of them land
  // here). Rather than special-case every caller, this screen redirects
  // itself, once, the first time it resolves a logistics-flow category —
  // to the consolidated GoodsTransportBookingScreen (pickup/drop-on-map/
  // date/slot/vehicle-category/fare, all on one page). Guarded by this flag
  // so a rebuild (e.g. from cart changes) never re-fires the redirect.
  bool _redirectedToLogistics = false;

  void _maybeRedirectToLogistics(Category? currentCategory) {
    if (_redirectedToLogistics) return;
    if (currentCategory?.flowType != CatalogFlowType.logistics) return;
    _redirectedToLogistics = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.pushReplacement(
        AppRoutes.goodsTransportBooking,
        extra: currentCategory,
      );
    });
  }

  // Fixed 2026-09-01: removed _resolveCanonicalSlug / _resolveCategoryNameFromSlug
  // / _resolveCategoryIdFromSlug — all three guessed a category's real slug,
  // display name and numeric ID by matching keywords against a fixed,
  // hand-enumerated list (AC & Appliance, Electrician/Plumbing/Carpentry,
  // Mason, Paintings, ...). That list is exactly the "hardcoded categories"
  // problem reported: the admin's Service Catalog portal is the only place
  // categories/sub-services are actually defined, and it can rename, add,
  // or remove them at any time — a category the admin adds that doesn't
  // match any of those keywords used to silently fall back to a slugified
  // guess-name and a null ID (querying by raw slug only), and worse, a
  // coincidental keyword overlap (e.g. any future category whose name
  // contains "clean") could resolve to the WRONG hardcoded ID entirely.
  //
  // This screen now trusts exactly two sources of truth, in priority order:
  // 1. `widget.initialCategory` — the real Category object passed via
  //    `extra:` by whichever screen already loaded it from the live
  //    /catalog/categories/ API (AllServicesScreen, Book Again, etc).
  // 2. The live `categoriesProvider` list itself, matched against
  //    `widget.categorySlug` by exact (case/hyphen-insensitive) slug
  //    equality — no keyword bucketing, no guessed ID.
  // Until one of those resolves, the screen shows its existing loading
  // state rather than a synthesized placeholder category.

  Widget? _buildCartBar(
    BuildContext context,
    Category category,
    List<CartItem> cartItems,
  ) {
    final isGroceryCategory = category.flowType == CatalogFlowType.grocery;

    if (!isGroceryCategory) {
      return null;
    }

    int itemCount = 0;
    Decimal subtotal = Decimal.zero;
    for (final item in cartItems) {
      itemCount += item.quantity;
      subtotal += item.totalPrice;
    }

    if (itemCount == 0) return null;

    // The exact crash (confirmed from the Flutter error log, which names
    // the FilledButton "Go to Cart" below by file:line) was this bar's
    // Row receiving BoxConstraints(w=Infinity) — this screen no longer
    // sits under a Scaffold (see the comment on CategoryDetailScreen's
    // build() for why), and whatever ambient widget is asking this
    // subtree to lay out during a route/shell transition sometimes probes
    // it with an unbounded width query, which FilledButton's internal
    // Material/PhysicalShape layer cannot handle and throws — taking the
    // whole screen down with it. Forcing an explicit, concrete width from
    // MediaQuery here (instead of trusting whatever width the ambient
    // BoxConstraints hands down) makes this bar immune to that: it is
    // now impossible for any downstream widget in this bar to ever see
    // an infinite/unbounded width, regardless of what odd constraints the
    // host passes in.
    final screenWidth = MediaQuery.of(context).size.width;

    return SafeArea(
      top: false,
      child: SizedBox(
        width: screenWidth,
        child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 96),
        child: Container(
      width: screenWidth,
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      child: Row(
        children: [
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0F766E).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        '$itemCount ${itemCount == 1 ? "ITEM" : "ITEMS"}',
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF0F766E),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '₹$subtotal',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                const Text(
                  'Continue adding or go to cart',
                  style: TextStyle(
                    fontSize: 11,
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          // The real, confirmed bug (from the crash log, every single
          // time): FilledButton.icon internally builds a _RenderInputPadding
          // to enforce its minimum tap-target size, and that widget's own
          // constraint math produces an invalid TIGHT-infinite width
          // (min==max==Infinity, not just an unbounded max) whenever it's
          // given an unbounded width to work with — which is exactly what
          // a Row always hands a non-Expanded child for its main axis, in
          // every Flutter app, by design. No amount of forcing a bounded
          // width on this button's ancestors could fix that (a Row still
          // hands its own non-flex children unbounded width regardless of
          // the Row's own width) — the fix has to stop this specific
          // button from ever seeing that unbounded constraint at all.
          // IntrinsicWidth measures the child's natural width first and
          // then lays it out with that concrete, finite number, so
          // _RenderInputPadding never receives an unbounded constraint in
          // the first place.
          IntrinsicWidth(
            child: FilledButton.icon(
              onPressed: () => context.go('/cart'),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF059669),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
              ),
              icon: const Icon(Icons.shopping_cart_checkout, size: 16),
              label: const Text('Go to Cart', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
            ),
          ),
        ],
      ),
        ),
      ),
      ),
    );
  }

  /// Service categories: the subcategories (e.g. Washing Machine, Fridge) as a
  /// persistent vertical rail on the LEFT — image + name — and the matching
  /// packages on the RIGHT. Built outside the services `.when` so the rail
  /// stays put while the right side reloads after a tap. Grocery categories
  /// (own department rail) and categories with no subcategories are untouched.
  Widget _withServiceRail(
    bool isGrocery,
    List<Subcategory> subs,
    Widget body,
  ) {
    if (isGrocery || subs.isEmpty) return body;
    const blue = AppColors.serviceBlue;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          width: 82,
          color: Colors.white,
          child: ListView(
            padding: const EdgeInsets.symmetric(vertical: 8),
            children: [
              _VerticalDepartmentTile(
                label: 'All',
                icon: Icons.grid_view_rounded,
                accent: blue,
                accentLight: AppColors.serviceBlueLight,
                accentDark: AppColors.serviceBlueDark,
                selected: _selectedSubcategorySlug == null,
                onTap: () => setState(() => _selectedSubcategorySlug = null),
              ),
              for (final sub in subs)
                _VerticalDepartmentTile(
                  label: sub.name,
                  image: sub.image,
                  icon: Icons.home_repair_service_rounded,
                  accent: blue,
                  accentLight: AppColors.serviceBlueLight,
                  accentDark: AppColors.serviceBlueDark,
                  selected: _selectedSubcategorySlug == sub.slug,
                  onTap: () => setState(() => _selectedSubcategorySlug =
                      _selectedSubcategorySlug == sub.slug ? null : sub.slug),
                ),
            ],
          ),
        ),
        const VerticalDivider(width: 1, thickness: 0.8),
        Expanded(child: body),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final categoriesAsync = ref.watch(categoriesProvider);

    // Fixed 2026-09-01: the category this screen renders is now resolved
    // from real data only, in priority order — never guessed:
    //   1. widget.initialCategory — the live Category the caller already
    //      had (e.g. AllServicesScreen passes `extra: category` straight
    //      from categoriesProvider).
    //   2. An exact (case/hyphen-insensitive) slug match against the live
    //      categoriesProvider list — the admin's real, current categories.
    // If neither is available yet (first frame, deep link, or a stale
    // slug the admin has since removed), currentCategory is null and the
    // screen shows its loading state rather than a synthesized name/ID.
    final liveCategories = categoriesAsync.valueOrNull;
    final wClean = widget.categorySlug.replaceAll('-', '_').toLowerCase();
    final currentCategory = widget.initialCategory ??
        liveCategories?.where((c) {
          final cClean = c.slug.replaceAll('-', '_').toLowerCase();
          return c.slug == widget.categorySlug || cClean == wClean;
        }).firstOrNull;

    _maybeRedirectToLogistics(currentCategory);
    if (currentCategory?.flowType == CatalogFlowType.logistics) {
      // Redirect scheduled above for after this frame — show a plain
      // loading state in the meantime rather than flashing the normal
      // per-package list (or the "loading" shimmer for it) even briefly.
      return const Scaffold(
        backgroundColor: Colors.white,
        body: Padding(
          padding: EdgeInsets.all(16),
          child: ShimmerCard(height: 140),
        ),
      );
    }

    final resolvedCategoryId = currentCategory?.id;
    // categorySlug is passed through exactly as given/pushed — the
    // repository no longer reinterprets it, so this is the real admin slug
    // whenever currentCategory resolved, or the raw route segment as a
    // last resort while it's still loading.
    final categorySlug = currentCategory?.slug ?? widget.categorySlug;
    AppLogger.d('[P0-NAV]', 'opening ${currentCategory?.name ?? "(loading)"}');
    AppLogger.d('[P0-NAV]', 'categoryId=$resolvedCategoryId');
    AppLogger.d('[P0-CATEGORY]', 'categoryId=$resolvedCategoryId, slug=$categorySlug');

    final servicesParam = CategoryServicesParam(
      categoryId: resolvedCategoryId,
      categorySlug: categorySlug,
      subcategorySlug: _selectedSubcategorySlug,
    );

    final subServicesAsync = ref.watch(subServicesProvider(categorySlug));
    final servicesAsync = ref.watch(categoryServicesProvider(servicesParam));
    final departmentsAsync = ref.watch(vegetableDepartmentsProvider);
    final approvedSlugsAsync = ref.watch(approvedVegetableCategorySlugsProvider);
    final cartItems = ref.watch(cartProvider);

    // Groceries browse as a 2-column product grid (Blinkit/Instamart
    // style); scheduled services keep the single-column detail list —
    // they carry more per-item info (duration, inclusions) that reads
    // better full-width. Driven by the real category's flowType, not a
    // hardcoded ID/slug check.
    final isGroceryCategory =
        currentCategory?.flowType == CatalogFlowType.grocery;

    servicesAsync.whenData((services) {
      AppLogger.d('[P0-CATALOG]', 'UI item count=${services.length}, cartItemCount=${cartItems.length}');
    });

    final subcategories =
        subServicesAsync.valueOrNull ?? currentCategory?.subcategories ?? const [];

    final theme = Theme.of(context);

    AppLogger.d('[DEBUG-SCREEN]',
        'CategoryDetailScreen BUILD: categorySlug=${widget.categorySlug}, resolvedId=$resolvedCategoryId, subcategories=${subcategories.length}, services=${servicesAsync.asData?.value.length}');

    final cartBar = currentCategory == null
        ? null
        : _buildCartBar(context, currentCategory, cartItems);

    // Deliberately NOT a second Scaffold. Disabling the FAB animator
    // (tried first) did not stop the crash — the actual trigger is a
    // Scaffold nested inside AppShell's own Scaffold via the ShellRoute:
    // two Scaffolds means two competing _ScaffoldSlot.floatingActionButton
    // layout/hit-test cycles in the same tree, and toggling this screen's
    // bottomNavigationBar between null and a widget (as cart contents
    // change) was enough to desync them — surfacing as "RenderBox was not
    // laid out" / "Cannot hit test a render box that has never been laid
    // out", and, because the exception broke this subtree's build, as the
    // category page going blank or freezing. Building the app bar and the
    // cart bar as plain widgets in a Column removes the second Scaffold
    // (and its FAB slot) entirely — AppBar works standalone; it only needs
    // a Navigator (for the back button), not a Scaffold.
    return Container(
      color: AppColors.background,
      child: Column(
        children: [
          AppBar(
        titleSpacing: 0,
        title: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              currentCategory?.name ?? '',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
                fontSize: 16.5,
              ),
            ),
            if (currentCategory != null)
              Text(
                _heroCopyFor(currentCategory.slug, currentCategory.name).tagline,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textSecondary,
                ),
              ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Search services',
            icon: const Icon(Icons.search),
            onPressed: () => context.push('/search'),
          ),
        ],
      ),
      Expanded(
            child: _withServiceRail(isGroceryCategory, subcategories, servicesAsync.when(
        // Grocery categories show their own rail once loaded, so the skeleton
        // draws one; service categories get their rail from _withServiceRail
        // around this body, so the skeleton must not add a second.
        loading: () => IllustrationThenSkeleton(
          skeleton: ListingSkeleton(
            grid: isGroceryCategory,
            showRail: isGroceryCategory,
          ),
        ),
        error: (err, st) => Padding(
          padding: const EdgeInsets.all(20),
          child: Center(
            child: ErrorStateWidget(
              message: err.toString(),
              onRetry: () =>
                  ref.refresh(categoryServicesProvider(servicesParam)),
            ),
          ),
        ),
        data: (rawServices) {
          // Fixed 2026-09-23 per explicit request ("there are some
          // vegetables from different endpoints... make sure the data
          // only come from admin -> vegetable inventory"): this screen's
          // services come from `/catalog/services/?category_id=...`, which
          // returns EVERY Package filed under this admin Category — not
          // only the ones the Vegetable Inventory bulk-upload/approval flow
          // created (see inventory/services/vegetable_catalog_service.py).
          // A Package added directly in the admin's plain Service Catalog
          // for this same category (never touching Vegetable Inventory at
          // all) has no `vegetable_category_*` fields and used to still
          // show up here, uncategorized.
          //
          // Fixed again 2026-09-23 — confirmed by the user directly in the
          // admin panel: `hasVegetableCategory` alone let through "Ash
          // Gourd (Sambar Pusanikkai)", which carries a non-empty
          // vegetable_category_name/_slug from the API but does NOT appear
          // anywhere under admin -> Vegetable Inventory -> Vegetable
          // Categories (old seed-script data whose category link was never
          // a real, approved admin category — see
          // [CatalogRepository.getApprovedVegetableCategorySlugs]). Every
          // item is now also cross-checked against the live set of
          // APPROVED category slugs; while that set is still loading, the
          // hasVegetableCategory-only filter is used as a fallback so the
          // grid doesn't flash empty. Service-booking categories are
          // untouched — they were never supposed to relate to Vegetable
          // Inventory at all.
          final approvedSlugs = approvedSlugsAsync.valueOrNull;
          final services = isGroceryCategory
              ? rawServices.where((s) {
                  if (!s.hasVegetableCategory) return false;
                  if (approvedSlugs == null) return true;
                  return approvedSlugs.contains(s.vegetableCategorySlug!.toLowerCase().trim());
                }).toList()
              : rawServices;

          if (services.isEmpty) {
            return Padding(
              padding:
                  const EdgeInsets.symmetric(vertical: 40, horizontal: 20),
              child: Center(
                child: EmptyStateWidget(
                  title: isGroceryCategory
                      ? 'No Produce Found'
                      : 'No Services Found',
                  subtitle: isGroceryCategory
                      ? 'Our farm-fresh produce list is being updated. Please try again shortly.'
                      : 'We are currently expanding our offerings in this category.',
                  emoji: isGroceryCategory ? '🥦' : '🛠️',
                  actionLabel: 'Browse All Categories',
                  action: () => context.go('/'),
                ),
              ),
            );
          }

          // Product-derived grouping, built purely from the Vegetable
          // Inventory category each already-fetched item carries (see
          // [groupServiceItemsByDepartment]) — the source of truth for tile
          // images, subcategory breakdowns, and the actual product grid.
          final productDepartmentGroups =
              isGroceryCategory ? groupServiceItemsByDepartment(services) : const <VegetableDepartmentGroup>[];

          // Fixed 2026-09-23 per user feedback ("see here / completly
          // different...", comparing this screen against the admin's real
          // "Vegetable Categories" tree): the tile strip used to be built
          // ONLY from [productDepartmentGroups] above, so an admin-created
          // department with no live produce yet (confirmed in the admin
          // screenshot: "Fresh Fruits" and "Coriander & Others", both 0
          // direct produce) never appeared as a tile at all — the strip
          // silently diverged from what the admin actually configured. The
          // real, admin-managed department list from
          // `GET /api/inventory/vegetable-categories/?only_roots=true` (see
          // [vegetableDepartmentsProvider]) is now the source of truth for
          // which tiles exist; product data still decides each tile's
          // image, its subcategory chips, and what fills the grid. Falls
          // back to the product-derived list only while the admin tree is
          // still loading or unreachable, so the strip never just vanishes.
          final adminDepartments = isGroceryCategory
              ? (departmentsAsync.valueOrNull ?? const <VegetableCategorySummary>[])
              : const <VegetableCategorySummary>[];

          final departmentNames = adminDepartments.isNotEmpty
              ? adminDepartments.map((d) => d.name).toList()
              : productDepartmentGroups.map((g) => g.name).toList();
          final showDepartmentBrowse = departmentNames.length > 1;

          VegetableDepartmentGroup? findProductGroup(String name) {
            for (final g in productDepartmentGroups) {
              if (g.name.toLowerCase() == name.toLowerCase()) return g;
            }
            return null;
          }

          final selectedProductGroup =
              _selectedDepartment != null ? findProductGroup(_selectedDepartment!) : null;

          // The grid actually shown below: everything, unless a department
          // is selected. A department the admin defined but that has no
          // live produce yet resolves to no product group at all, so this
          // is correctly empty for it — falling through to the "No Produce
          // Here Yet" empty state below instead of the tile not existing.
          final gridItems = _selectedDepartment == null
              ? services
              : (selectedProductGroup == null
                  ? const <ServiceItem>[]
                  : (_selectedVegSubcategory != null
                      ? (selectedProductGroup.subcategories[_selectedVegSubcategory] ??
                          selectedProductGroup.items)
                      : selectedProductGroup.items));

          // Build the 2-per-row grocery grid as plain Rows rather than a
          // GridView with a fixed childAspectRatio — a fixed aspect ratio
          // is exactly what caused the "RenderFlex overflowed" errors
          // before (content height varies slightly by title/price length,
          // but the aspect ratio didn't). A Row's height instead adapts to
          // its tallest child, so there's nothing to overflow.
          final List<Widget> groceryRows = [];
          if (isGroceryCategory) {
            for (var i = 0; i < gridItems.length; i += 2) {
              final hasSecond = i + 1 < gridItems.length;
              groceryRows.add(
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: RepaintBoundary(
                          child: ProductCard(service: gridItems[i]),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: hasSecond
                            ? RepaintBoundary(
                                child: ProductCard(service: gridItems[i + 1]),
                              )
                            : const SizedBox.shrink(),
                      ),
                    ],
                  ),
                ),
              );
            }
          }

          // Fixed 2026-09-23: this legacy Service-subcategory chip row
          // (driven by [subServicesProvider] — a flat list of Django
          // `Service` records, NOT the Vegetable Inventory tree above)
          // used to render for every category including grocery, where it
          // showed the internal auto-generated Service name "Farm-Fresh
          // Vegetable" (see inventory/services/vegetable_catalog_service.py)
          // alongside the department rail — the exact "completely
          // different" duplicate/conflicting row from an earlier
          // screenshot. Grocery categories use the department rail below
          // exclusively; this row is for service-booking categories (AC &
          // Appliance, Electrician, ...) only.
          if (!isGroceryCategory) {
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              children: [
                ...services.map(
                  (service) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: ServiceCard(service: service),
                  ),
                ),
              ],
            );
          }

          // Grocery layout: Blinkit-style persistent left-hand department
          // rail + an independently-scrolling right-hand product grid —
          // restored 2026-09-23 per explicit request ("you removed the
          // previous layout... make it like the uploaded image"). The rail
          // stays fixed while only the grid on the right scrolls, matching
          // the reference screenshot; a category with only one browsable
          // department (showDepartmentBrowse == false) skips the rail
          // entirely and the grid takes the full width.
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (showDepartmentBrowse)
                Container(
                  width: 78,
                  color: Colors.white,
                  child: ListView(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    children: [
                      _VerticalDepartmentTile(
                        label: 'All',
                        icon: Icons.grid_view_rounded,
                        selected: _selectedDepartment == null,
                        onTap: () => _selectDepartment(null),
                      ),
                      ...(adminDepartments.isNotEmpty
                          ? adminDepartments.map(
                              (dept) => _VerticalDepartmentTile(
                                label: dept.name,
                                image: dept.image ?? findProductGroup(dept.name)?.image,
                                selected: _selectedDepartment == dept.name,
                                onTap: () => _selectDepartment(
                                  _selectedDepartment == dept.name ? null : dept.name,
                                ),
                              ),
                            )
                          : productDepartmentGroups.map(
                              (group) => _VerticalDepartmentTile(
                                label: group.name,
                                image: group.image,
                                selected: _selectedDepartment == group.name,
                                onTap: () => _selectDepartment(
                                  _selectedDepartment == group.name ? null : group.name,
                                ),
                              ),
                            )),
                    ],
                  ),
                ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
                  children: [
                    if (selectedProductGroup != null && selectedProductGroup.hasSubcategoryBreakdown) ...[
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            _FilterChip(
                              label: 'All ${selectedProductGroup.name}',
                              selected: _selectedVegSubcategory == null,
                              onTap: () => setState(() => _selectedVegSubcategory = null),
                            ),
                            const SizedBox(width: 8),
                            ...selectedProductGroup.subcategories.keys.map(
                              (sub) => Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: _FilterChip(
                                  label: sub,
                                  selected: _selectedVegSubcategory == sub,
                                  onTap: () => setState(() => _selectedVegSubcategory =
                                      _selectedVegSubcategory == sub ? null : sub),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                    if (gridItems.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 24),
                        child: Center(
                          child: EmptyStateWidget(
                            title: 'No Produce Here Yet',
                            subtitle: 'Nothing in this category right now — check back soon.',
                            emoji: '🥦',
                            actionLabel: 'Show All',
                            action: () => _selectDepartment(null),
                          ),
                        ),
                      )
                    else
                      ...groceryRows,
                  ],
                ),
              ),
            ],
          );
        },
            )),
          ),
          ?cartBar,
        ],
      ),
    );
  }
}