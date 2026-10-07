/// The Grocery Home Section Builder's layout vocabulary.
///
/// Added 2026-10-05 as part of the Grocery Home Section Builder upgrade
/// (see MobileGrocerySection in homepage_repository.dart and the
/// GrocerySectionResolver widget in grocery_section_layouts.dart). The
/// backend stores a section's `layout` as a plain string inside
/// `HomePageConfig.config_data["mobile"]["grocerySections"]` — there is no
/// database enum to migrate, so backward compatibility is just "every old
/// string value still maps to something real", which [fromRaw] guarantees.
///
/// Updated 2026-10-05 (same day) — all 12 layouts from the spec are now
/// implemented (see [isImplemented]): the 5 PRODUCT / SHOPPING layouts from
/// the first pass, plus 4 PROMOTIONAL layouts (Featured Hero, Deal Cards,
/// Banner + Product Rail, Split Featured) and 3 CATEGORY DISCOVERY /
/// ADVANCED layouts (Category Tile Grid, Circular Category Rail, Masonry).
/// [fromRaw] still falls back to [horizontalCarousel] for any string this
/// enum doesn't recognize at all (never crashes, never hides a section for
/// an unexpected value) — that fallback path is now purely defensive since
/// every value the admin UI can actually write has a real widget.
enum GrocerySectionLayout {
  // ── PRODUCT / SHOPPING ──────────────────────────────────────────────
  horizontalCarousel,
  grid3,
  grid2,
  compactList,
  quickAddList,

  // ── PROMOTIONAL ──────────────────────────────────────────────────────
  featuredHero,
  dealCards,
  bannerProductRail,
  splitFeatured,

  // ── CATEGORY DISCOVERY / ADVANCED ────────────────────────────────────
  categoryTileGrid,
  circularCategoryRail,
  masonry,
}

extension GrocerySectionLayoutX on GrocerySectionLayout {
  /// The exact string this layout is stored as in the admin's JSON config.
  /// `horizontal` and `grid` are kept as-is (not renamed to `horizontal_carousel`
  /// / `grid_3`) purely for backward compatibility with every section an
  /// admin already saved before this upgrade.
  String get wireValue => switch (this) {
        GrocerySectionLayout.horizontalCarousel => 'horizontal',
        GrocerySectionLayout.grid3 => 'grid',
        GrocerySectionLayout.grid2 => 'grid_2',
        GrocerySectionLayout.compactList => 'compact_list',
        GrocerySectionLayout.quickAddList => 'quick_add_list',
        GrocerySectionLayout.featuredHero => 'featured_hero',
        GrocerySectionLayout.dealCards => 'deal_cards',
        GrocerySectionLayout.bannerProductRail => 'banner_product_rail',
        GrocerySectionLayout.splitFeatured => 'split_featured',
        GrocerySectionLayout.categoryTileGrid => 'category_tile_grid',
        GrocerySectionLayout.circularCategoryRail => 'circular_category_rail',
        GrocerySectionLayout.masonry => 'masonry',
      };

  /// Whether this layout pulls from the merged-products data source
  /// (admin's picked category ids → products inside them) versus the
  /// category-discovery data source (the picked category ids themselves,
  /// rendered as real Seller Hub department tiles/avatars rather than their
  /// products). Drives which provider [GrocerySectionResolver] watches.
  bool get isCategoryDiscovery => switch (this) {
        GrocerySectionLayout.categoryTileGrid ||
        GrocerySectionLayout.circularCategoryRail =>
          true,
        _ => false,
      };

  /// True for every layout that now has a real widget. Kept as a named
  /// getter (rather than inlining `true` everywhere) so a future Phase 4
  /// layout added to the enum above defaults to `false` here until its
  /// widget actually ships — the same safety margin Phase 1 used.
  bool get isImplemented => true;

  static GrocerySectionLayout fromRaw(String? raw) {
    final v = (raw ?? '').trim().toLowerCase();
    for (final layout in GrocerySectionLayout.values) {
      if (layout.wireValue == v) return layout;
    }
    // Unknown / not-yet-shipped-on-mobile value — never crash, never show a
    // broken section; render it the way every section used to render.
    return GrocerySectionLayout.horizontalCarousel;
  }
}
