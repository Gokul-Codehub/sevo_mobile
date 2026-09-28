import 'package:flutter/material.dart';

import '../../../../shared/theme/app_colors.dart';
import '../../data/grocery_hub_repository.dart';
import '../widgets/product_card.dart';

/// Full product grid for one Grocery Hub "Bestsellers" category — reached
/// by tapping a tile on Home. Added 2026-09-19 alongside that tile.
///
/// This deliberately does NOT show a left-hand subcategory rail like the
/// user's second reference screenshot (Tubs / Sticks / Cones / ...): the
/// Grocery Hub's public storefront API only returns one flat `category`
/// string per product (see grocery_hub_repository.dart's doc comment) —
/// that finer subcategory breakdown only exists on the secret-gated
/// marketplace endpoint this app doesn't call from a mobile client. Rather
/// than fabricate subcategories that aren't real, this shows every real
/// product in the category in one clean grid.
///
/// Fixed 2026-09-19 per explicit follow-up ("If user clicks Add buttons it
/// should append in our cart from there we can checkout the order...like
/// vegetables do"): this used to show its own ADD/stepper wired to this
/// hub's own separate cart endpoint. Every tile here now renders through
/// the same [ProductCard] every other grocery item on this screen uses
/// (via [GroceryHubProduct.toServiceItem]), so ADD/quantity/cart-badge/
/// checkout behave identically to any other grocery item — one cart, one
/// checkout, no second system for the customer to notice.
class GroceryHubCategoryScreen extends StatelessWidget {
  const GroceryHubCategoryScreen({super.key, required this.group});

  final GroceryHubCategoryGroup group;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        foregroundColor: AppColors.navy,
        title: Text(
          group.name,
          style: const TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w800,
            color: AppColors.navy,
          ),
        ),
      ),
      body: GridView.builder(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
        itemCount: group.products.length,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
          childAspectRatio: 0.62,
        ),
        itemBuilder: (context, i) => ProductCard(
          service: group.products[i].toServiceItem(),
        ),
      ),
    );
  }
}
