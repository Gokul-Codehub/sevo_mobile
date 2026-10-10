import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../shared/theme/app_colors.dart';
import '../../../../shared/widgets/app_remote_image.dart';
import '../../../../shared/widgets/common_widgets.dart';
import '../../../booking/domain/booking_models.dart';
import '../../../booking/domain/cart_notifier.dart';
import '../../data/marketplace_catalog_repository.dart';
import '../widgets/product_card.dart';

/// Browse the vendor's real Seller Hub grocery catalog by its admin-managed
/// department tree ("Superadmin Console → Seller Hub → Categories") — the
/// same left-rail-departments + scrolling-product-grid UX this app already
/// uses for Vegetable Inventory produce (see CategoryDetailScreen), applied
/// to packaged groceries (Oils & Ghee, Dairy & Beverages, Pantry, etc.)
/// sourced from [marketplaceCategoryTreeProvider] /
/// [marketplaceProductsByCategoryProvider] instead of the Vegetable
/// Inventory tree.
///
/// Added 2026-09-25. Deliberately separate from [GroceryHubCategoryScreen]
/// (the flat, hierarchy-less Bestsellers-tile browse screen) — both stay in
/// the app; this is the new, real-category-tree entry point.
///
/// Simplified 2026-09-28 per explicit correction ("remove the top 'Main
/// categories' — if i get into Groceries -> list sub categories in left
/// side and inside every sub category list the leaf/products"): a prior
/// pass added a horizontal strip of every root category above this screen,
/// but the real ask is simpler — this screen IS the "Groceries" main
/// category's own page. It now goes straight to Groceries' own real
/// subcategories (its direct children — "Dairy & Eggs", "Oil", "Flour" —
/// each with its own real uploaded photo) in the left rail, and the grid
/// shows that subcategory's products. [MarketplaceCatalogRepository.
/// getProducts]'s own doc comment confirms the products endpoint already
/// aggregates "one department (and everything under it)" server-side, so
/// selecting "Oil" correctly shows SunFlower/Groundnut/Gold Winner oil
/// products together without this screen re-flattening the tree itself.
/// Product approval stays entirely server-side (`SellerProduct`, "APPROVED
/// + in-stock only") — nothing here re-filters or second-guesses that.
class SellerHubGroceriesScreen extends ConsumerStatefulWidget {
  const SellerHubGroceriesScreen({super.key, this.initialCategorySlug});

  final String? initialCategorySlug;

  @override
  ConsumerState<SellerHubGroceriesScreen> createState() => _SellerHubGroceriesScreenState();
}

/// True if [node] or anything in its subtree matches [wantedSlugClean]
/// (already lowercased/underscored) — used only to resolve a deep-linked
/// slug (e.g. a Bestseller tile's leaf-level link) to the direct-child
/// subcategory that contains it, since the rail itself only ever shows one
/// level (direct children), never the full flattened leaf list.
bool _subtreeContainsSlug(MarketplaceCategory node, String wantedSlugClean) {
  if (node.slug.replaceAll('-', '_').toLowerCase() == wantedSlugClean) return true;
  for (final child in node.children) {
    if (_subtreeContainsSlug(child, wantedSlugClean)) return true;
  }
  return false;
}

class _SellerHubGroceriesScreenState extends ConsumerState<SellerHubGroceriesScreen> {
  int? _selectedRootId;
  int? _selectedSubcategoryId;
  bool _appliedInitialSlug = false;

  /// Same lookup the body does once on its first build, as a pure function,
  /// so the AppBar can show the right title on the very first frame.
  int? _rootIdForSlug(List<MarketplaceCategory> roots, String? rawSlug) {
    final slug = rawSlug?.trim();
    if (slug == null || slug.isEmpty) return null;
    final wanted = slug.replaceAll('-', '_').toLowerCase();
    for (final root in roots) {
      if (root.slug.replaceAll('-', '_').toLowerCase() == wanted) return root.id;
      for (final child in root.children) {
        if (_subtreeContainsSlug(child, wanted)) return root.id;
      }
    }
    return null;
  }

  /// The AppBar title: the name of the main category being browsed (e.g.
  /// "Dairy & Bakery"), not a fixed "Groceries". Falls back to "Groceries"
  /// while the tree is still loading or empty.
  String _screenTitle(List<MarketplaceCategory>? tree) {
    const fallback = 'Groceries';
    if (tree == null) return fallback;
    final roots = tree.where((r) => r.hasAnyProducts).toList();
    if (roots.isEmpty) return fallback;
    final defaultRoot = roots.firstWhere(
      (r) => r.name.toLowerCase().contains('grocer') || r.slug.toLowerCase().contains('grocer'),
      orElse: () => roots.first,
    );
    final id = _selectedRootId ??
        (_appliedInitialSlug ? null : _rootIdForSlug(roots, widget.initialCategorySlug)) ??
        defaultRoot.id;
    final root = roots.firstWhere((r) => r.id == id, orElse: () => defaultRoot);
    final name = root.name.trim();
    return name.isEmpty ? fallback : name;
  }

  @override
  Widget build(BuildContext context) {
    final treeAsync = ref.watch(marketplaceCategoryTreeProvider);
    final cartItems = ref.watch(cartProvider);

    // Deliberately NOT a Scaffold — this screen sits inside AppShell's own
    // Scaffold via the ShellRoute (see CategoryDetailScreen's matching
    // comment: two Scaffolds means two competing
    // _ScaffoldSlot.floatingActionButton layout/hit-test cycles in the same
    // tree, which is the confirmed root cause of that screen's "RenderBox
    // was not laid out" crash whenever its bottomNavigationBar toggled
    // between null and a widget as cart contents changed — exactly what
    // this screen's own cart bar does below). AppBar works standalone; it
    // only needs a Navigator for the back button, not a Scaffold.
    return Container(
      color: AppColors.background,
      child: Column(
        children: [
          AppBar(
            title: Text(_screenTitle(treeAsync.valueOrNull)),
            backgroundColor: Colors.white,
            foregroundColor: AppColors.textPrimary,
            elevation: 0.5,
            actions: [
              // Added 2026-10-08 ("the grocery developer has implemented
              // another feature something like Basket could you get into
              // our app?") — the only entry point into the new Seller Hub
              // combo/bundle offers; see BasketListScreen's doc comment.
              TextButton.icon(
                onPressed: () => context.push('/baskets'),
                icon: const Icon(Icons.card_giftcard_rounded, size: 18, color: AppColors.primary),
                label: const Text(
                  'Combos',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.primary),
                ),
              ),
            ],
          ),
          Expanded(
            child: treeAsync.when(
        loading: () => const Padding(
          padding: EdgeInsets.all(20),
          child: Column(
            children: [
              ShimmerCard(height: 100),
              SizedBox(height: 12),
              ShimmerCard(height: 100),
              SizedBox(height: 12),
              ShimmerCard(height: 100),
            ],
          ),
        ),
        error: (err, st) => Center(
          child: ErrorStateWidget(
            message: 'Could not load the grocery catalog. Please try again.',
            onRetry: () => ref.invalidate(marketplaceCategoryTreeProvider),
          ),
        ),
        data: (tree) {
          final roots = tree.where((r) => r.hasAnyProducts).toList();
          if (roots.isEmpty) {
            return const Center(
              child: EmptyStateWidget(
                title: 'No Groceries Right Now',
                subtitle: 'The grocery catalog is empty at the moment — check back soon.',
                emoji: '🛒',
              ),
            );
          }

          // The "Groceries" main category itself — matched by real name/
          // slug the same keyword-based way the rest of this app already
          // classifies flow types (never a hardcoded id), falling back to
          // the first available root if the admin ever renames it away
          // from anything containing "grocer".
          final defaultRoot = roots.firstWhere(
            (r) => r.name.toLowerCase().contains('grocer') || r.slug.toLowerCase().contains('grocer'),
            orElse: () => roots.first,
          );

          // Resolve a deep-linked/click-through slug (e.g. a Bestseller
          // tile's "?category=<slug>" link) to whichever ROOT and DIRECT
          // CHILD subcategory actually contains it, exactly once — a later
          // manual tap always wins from then on. A miss (the slug isn't in
          // this catalog) is never retried on rebuild.
          if (!_appliedInitialSlug) {
            final initialSlug = widget.initialCategorySlug?.trim();
            if (initialSlug != null && initialSlug.isNotEmpty) {
              final wanted = initialSlug.replaceAll('-', '_').toLowerCase();
              outer:
              for (final root in roots) {
                if (root.slug.replaceAll('-', '_').toLowerCase() == wanted) {
                  _selectedRootId = root.id;
                  break;
                }
                for (final child in root.children) {
                  if (_subtreeContainsSlug(child, wanted)) {
                    _selectedRootId = root.id;
                    _selectedSubcategoryId = child.id;
                    break outer;
                  }
                }
              }
            }
            _appliedInitialSlug = true;
          }

          final effectiveRootId = _selectedRootId ?? defaultRoot.id;
          final selectedRoot = roots.firstWhere(
            (r) => r.id == effectiveRootId,
            orElse: () => defaultRoot,
          );

          // The rail is the selected main category's own DIRECT children
          // ("Dairy & Eggs", "Oil", "Flour"...) — never flattened further.
          // A root with no subcategories of its own (already a leaf) falls
          // back to treating itself as the sole entry, so the screen still
          // works for a main category that has no further nesting.
          final subcategories = selectedRoot.children.where((c) => c.hasAnyProducts).toList();
          final railItems = subcategories.isNotEmpty ? subcategories : [selectedRoot];

          if (railItems.isEmpty) {
            return const Center(
              child: EmptyStateWidget(
                title: 'Nothing Here Yet',
                subtitle: 'No approved products in this category right now.',
                emoji: '📦',
              ),
            );
          }

          final effectiveSubcategoryId = _selectedSubcategoryId ?? railItems.first.id;
          final selectedSubcategory = railItems.firstWhere(
            (c) => c.id == effectiveSubcategoryId,
            orElse: () => railItems.first,
          );

          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                width: 78,
                color: Colors.white,
                child: ListView(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  children: railItems
                      .map(
                        (dept) => _DepartmentRailTile(
                          label: dept.name,
                          image: dept.image,
                          selected: dept.id == effectiveSubcategoryId,
                          onTap: () => setState(() => _selectedSubcategoryId = dept.id),
                        ),
                      )
                      .toList(),
                ),
              ),
              Expanded(
                child: _DepartmentProductGrid(
                  key: ValueKey(selectedSubcategory.id),
                  departmentId: selectedSubcategory.id,
                ),
              ),
            ],
          );
        },
            ),
          ),
          ?_buildCartBar(context, cartItems),
        ],
      ),
    );
  }

  Widget? _buildCartBar(BuildContext context, List<CartItem> cartItems) {
    int itemCount = 0;
    Decimal subtotal = Decimal.zero;
    for (final item in cartItems) {
      itemCount += item.quantity;
      subtotal += item.totalPrice;
    }
    if (itemCount == 0) return null;

    final screenWidth = MediaQuery.of(context).size.width;
    return SafeArea(
      top: false,
      child: SizedBox(
        width: screenWidth,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 80),
          child: Container(
            width: screenWidth,
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 10, offset: const Offset(0, -2)),
              ],
            ),
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '$itemCount ${itemCount == 1 ? "item" : "items"} · ₹$subtotal',
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.textPrimary),
                  ),
                ),
                const SizedBox(width: 8),
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
}

class _DepartmentProductGrid extends ConsumerWidget {
  const _DepartmentProductGrid({super.key, required this.departmentId});

  final int departmentId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pageAsync = ref.watch(marketplaceProductsByCategoryProvider(departmentId));

    return pageAsync.when(
      loading: () => const Padding(
        padding: EdgeInsets.all(12),
        child: Column(
          children: [
            ShimmerCard(height: 140),
            SizedBox(height: 12),
            ShimmerCard(height: 140),
          ],
        ),
      ),
      error: (err, st) => Center(
        child: ErrorStateWidget(
          message: 'Could not load this department right now.',
          onRetry: () => ref.invalidate(marketplaceProductsByCategoryProvider(departmentId)),
        ),
      ),
      data: (page) {
        final items = page.products.map((p) => p.toServiceItem()).toList();
        if (items.isEmpty) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(
              child: EmptyStateWidget(
                title: 'Nothing Here Yet',
                subtitle: 'No products in this department right now.',
                emoji: '📦',
              ),
            ),
          );
        }

        final rows = <Widget>[];
        for (var i = 0; i < items.length; i += 2) {
          final hasSecond = i + 1 < items.length;
          rows.add(
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: RepaintBoundary(child: ProductCard(service: items[i]))),
                  const SizedBox(width: 12),
                  Expanded(
                    child: hasSecond
                        ? RepaintBoundary(child: ProductCard(service: items[i + 1]))
                        : const SizedBox.shrink(),
                  ),
                ],
              ),
            ),
          );
        }

        return ListView(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
          children: rows,
        );
      },
    );
  }
}

class _DepartmentRailTile extends StatelessWidget {
  const _DepartmentRailTile({
    required this.label,
    required this.selected,
    required this.onTap,
    this.image,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final String? image;

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
              color: selected ? AppColors.groceryGreen : Colors.transparent,
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
                  color: selected ? AppColors.groceryGreen : Colors.transparent,
                  width: 2,
                ),
                color: AppColors.groceryGreenLight,
              ),
              child: ClipOval(
                child: (image != null && image!.trim().isNotEmpty)
                    ? AppRemoteImage(
                        imageUrl: image,
                        title: label,
                        fit: BoxFit.cover,
                        semanticIcon: Icons.storefront_rounded,
                      )
                    : const Icon(Icons.storefront_rounded, color: AppColors.groceryGreenDark, size: 24),
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
