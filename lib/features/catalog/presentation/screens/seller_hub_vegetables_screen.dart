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

/// Browse Fresh Vegetables & Fruits by the admin's real Seller Hub category
/// tree ("Superadmin Console → Seller Hub → Categories") — the exact same
/// left-rail-departments + independently-scrolling product-grid UX
/// [SellerHubGroceriesScreen] already uses for packaged groceries, applied
/// to whichever root department in that same tree is Vegetables & Fruits.
///
/// Added 2026-09-30 per explicit request: the admin no longer manages
/// produce through the separate "Vegetable Inventory" module
/// (`inventory.VegetableCategory`, `/api/inventory/vegetable-categories/` —
/// what [CategoryDetailScreen]'s grocery branch and
/// `catalog_providers.vegetableDepartmentsProvider` still read from). Fresh
/// Vegetables & Fruits is now added the same way Groceries is: as its own
/// main category in the Seller Hub tree, with sub-categories and leaf
/// products underneath — so this screen sources from
/// [marketplaceCategoryTreeProvider] / [marketplaceProductsByCategoryProvider]
/// exactly like [SellerHubGroceriesScreen] does, just matched to the
/// "vegetable"/"fruit" root instead of "grocer". [CategoryDetailScreen]'s
/// older Vegetable Inventory-based branch is left in place (unreachable
/// from the UI now that every entry point below routes here) rather than
/// deleted outright, in case the admin ever needs to fall back to it.
class SellerHubVegetablesScreen extends ConsumerStatefulWidget {
  const SellerHubVegetablesScreen({super.key, this.initialCategorySlug});

  final String? initialCategorySlug;

  @override
  ConsumerState<SellerHubVegetablesScreen> createState() => _SellerHubVegetablesScreenState();
}

/// True if [node] or anything in its subtree matches [wantedSlugClean]
/// (already lowercased/underscored) — same deep-link resolution
/// [SellerHubGroceriesScreen] uses.
bool _subtreeContainsSlug(MarketplaceCategory node, String wantedSlugClean) {
  if (node.slug.replaceAll('-', '_').toLowerCase() == wantedSlugClean) return true;
  for (final child in node.children) {
    if (_subtreeContainsSlug(child, wantedSlugClean)) return true;
  }
  return false;
}

class _SellerHubVegetablesScreenState extends ConsumerState<SellerHubVegetablesScreen> {
  int? _selectedRootId;
  int? _selectedSubcategoryId;
  bool _appliedInitialSlug = false;

  @override
  Widget build(BuildContext context) {
    final treeAsync = ref.watch(marketplaceCategoryTreeProvider);
    final cartItems = ref.watch(cartProvider);

    // Deliberately NOT a Scaffold — same reasoning as
    // SellerHubGroceriesScreen's matching comment (this screen sits inside
    // AppShell's own Scaffold via the ShellRoute; a second Scaffold here
    // would double up on _ScaffoldSlot.floatingActionButton layout/hit-test
    // cycles, the confirmed root cause of an earlier "RenderBox was not
    // laid out" crash elsewhere in this app when a bottomNavigationBar
    // toggled between null and a widget as cart contents changed — exactly
    // what this screen's own cart bar does below).
    return Container(
      color: AppColors.background,
      child: Column(
        children: [
          AppBar(
            title: const Text('Fresh Vegetables & Fruits'),
            backgroundColor: Colors.white,
            foregroundColor: AppColors.textPrimary,
            elevation: 0.5,
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
                  message: 'Could not load Vegetables & Fruits right now. Please try again.',
                  onRetry: () => ref.invalidate(marketplaceCategoryTreeProvider),
                ),
              ),
              data: (tree) {
                final roots = tree.where((r) => r.hasAnyProducts).toList();
                if (roots.isEmpty) {
                  return const Center(
                    child: EmptyStateWidget(
                      title: 'No Vegetables & Fruits Right Now',
                      subtitle: 'The produce catalog is empty at the moment — check back soon.',
                      emoji: '🥦',
                    ),
                  );
                }

                // The "Vegetables & Fruits" main category itself — matched
                // by real name/slug the same keyword-based way the rest of
                // this app already classifies flow types (never a
                // hardcoded id), same convention as
                // SellerHubGroceriesScreen's "grocer" match. Falls back to
                // the first available root only if the admin hasn't
                // created a vegetable/fruit main category in this tree yet.
                final vegetableRoot = roots.where(
                  (r) =>
                      r.name.toLowerCase().contains('vegetable') ||
                      r.slug.toLowerCase().contains('vegetable') ||
                      r.name.toLowerCase().contains('fruit') ||
                      r.slug.toLowerCase().contains('fruit'),
                ).firstOrNull;

                if (vegetableRoot == null) {
                  return const Center(
                    child: EmptyStateWidget(
                      title: 'No Vegetables & Fruits Right Now',
                      subtitle: 'Ask the admin to add a "Vegetables & Fruits" category in Seller Hub.',
                      emoji: '🥦',
                    ),
                  );
                }
                final defaultRoot = vegetableRoot;

                // Resolve a deep-linked/click-through slug, exactly once —
                // same convention as SellerHubGroceriesScreen.
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

                // The rail is the selected main category's own DIRECT
                // children ("Fresh Vegetables", "Fresh Fruits", "Leafy
                // Greens"...) — never flattened further, same as
                // SellerHubGroceriesScreen.
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
                        semanticIcon: Icons.eco_rounded,
                      )
                    : const Icon(Icons.eco_rounded, color: AppColors.groceryGreenDark, size: 24),
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
