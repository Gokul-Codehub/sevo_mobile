import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import 'marketplace_catalog_repository.dart' show MarketplaceProduct;
import 'recipe_models.dart';

/// One ingredient of a recipe, with the Seller Hub products that can be
/// bought for it (`ingredient.linked_products[]`).
class RecipeIngredient {
  const RecipeIngredient({
    required this.id,
    required this.name,
    this.quantity = '',
    this.isOptional = false,
    this.linkedProducts = const [],
  });

  final int id;
  final String name;
  final String quantity;
  final bool isOptional;
  final List<MarketplaceProduct> linkedProducts;

  /// The product offered for this ingredient: the first one in stock, else
  /// the first one (shown as "Out of stock"). Null for pantry staples that
  /// have no linked product.
  MarketplaceProduct? get product {
    if (linkedProducts.isEmpty) return null;
    return linkedProducts.where((p) => p.inStock).firstOrNull ?? linkedProducts.first;
  }

  bool get canOrder => product?.inStock ?? false;

  factory RecipeIngredient.fromJson(Map<String, dynamic> j) {
    final linked = <MarketplaceProduct>[];
    if (j['linked_products'] is List) {
      for (final raw in (j['linked_products'] as List).whereType<Map>()) {
        final p = _linkedProduct(Map<String, dynamic>.from(raw));
        if (p != null) linked.add(p);
      }
    }
    return RecipeIngredient(
      id: int.tryParse(j['id']?.toString() ?? '') ?? 0,
      name: (j['name'] ?? '').toString().trim(),
      quantity: (j['quantity'] ?? '').toString().trim(),
      isOptional: j['is_optional'] == true,
      linkedProducts: linked,
    );
  }
}

/// A recipe's linked products come in a slimmer shape than the catalog's
/// (`price` instead of `selling_price`, `image` instead of `primary_image`,
/// no stock count). Fill those gaps, then reuse the catalog's own parser so
/// the result is a normal [MarketplaceProduct] the cart already understands.
MarketplaceProduct? _linkedProduct(Map<String, dynamic> j) {
  final m = Map<String, dynamic>.from(j);
  m['selling_price'] ??= m['price'];
  if ((m['primary_image'] ?? '').toString().isEmpty) m['primary_image'] = m['image'];
  final inStock = m['in_stock'] == true;
  m['in_stock'] = inStock;
  // No stock count on recipe links: don't let the cart cap the quantity at 0.
  if (inStock && m['available_stock'] == null) m['available_stock'] = 99;
  final p = MarketplaceProduct.fromJson(m);
  return (p.id == 0 || p.title.isEmpty) ? null : p;
}

class RecipeStep {
  const RecipeStep({required this.number, required this.instruction, this.image});

  final int number;
  final String instruction;
  final String? image;

  factory RecipeStep.fromJson(Map<String, dynamic> j, int index) => RecipeStep(
        number: int.tryParse(j['step_number']?.toString() ?? '') ?? (index + 1),
        instruction: (j['instruction'] ?? '').toString().trim(),
        image: resolveRecipeMedia(j['image']),
      );
}

class RecipeDetail {
  const RecipeDetail({
    required this.id,
    required this.slug,
    required this.title,
    this.description = '',
    this.coverImage,
    this.diet = RecipeDiet.veg,
    this.cookTimeMinutes = 0,
    this.kcal = 0,
    this.servings = 0,
    this.ingredients = const [],
    this.steps = const [],
  });

  final int id;
  final String slug;
  final String title;
  final String description;
  final String? coverImage;
  final RecipeDiet diet;
  final int cookTimeMinutes;
  final int kcal;
  final int servings;
  final List<RecipeIngredient> ingredients;
  final List<RecipeStep> steps;

  /// How many ingredients can be ordered right now (have an in-stock product).
  int get orderableCount => ingredients.where((i) => i.canOrder).length;

  factory RecipeDetail.fromJson(Map<String, dynamic> j) {
    int n(dynamic v) => int.tryParse(v?.toString() ?? '') ?? 0;
    final steps = <RecipeStep>[];
    if (j['steps'] is List) {
      final raw = (j['steps'] as List).whereType<Map>().toList();
      for (var i = 0; i < raw.length; i++) {
        final s = RecipeStep.fromJson(Map<String, dynamic>.from(raw[i]), i);
        if (s.instruction.isNotEmpty) steps.add(s);
      }
    }
    return RecipeDetail(
      id: n(j['id']),
      slug: (j['slug'] ?? '').toString().trim(),
      title: (j['title'] ?? '').toString().trim(),
      description: (j['description'] ?? '').toString().trim(),
      coverImage: resolveRecipeMedia(j['cover_image']),
      diet: recipeDietFrom(j['diet_type']),
      cookTimeMinutes: n(j['cook_time_minutes']),
      kcal: n(j['kcal']),
      servings: n(j['servings']),
      ingredients: j['ingredients'] is List
          ? (j['ingredients'] as List)
              .whereType<Map>()
              .map((m) => RecipeIngredient.fromJson(Map<String, dynamic>.from(m)))
              .where((i) => i.name.isNotEmpty)
              .toList()
          : const [],
      steps: steps,
    );
  }
}

/// `GET /api/marketplace/recipes/<slug-or-id>/` (public proxy to the Seller
/// Hub recipe). Resolves to null when the recipe doesn't exist (404); any
/// other failure throws so the screen can offer a retry.
final recipeDetailProvider =
    FutureProvider.autoDispose.family<RecipeDetail?, String>((ref, key) async {
  final api = ref.watch(apiClientProvider);
  try {
    final response = await api.get('/marketplace/recipes/${Uri.encodeComponent(key)}/');
    final body = response.data;
    if (body is! Map) return null;
    var map = Map<String, dynamic>.from(body);
    // The proxy answers {success, data: {...}}; accept a bare object too.
    if (map['data'] is Map) map = Map<String, dynamic>.from(map['data'] as Map);
    final recipe = RecipeDetail.fromJson(map);
    return (recipe.id == 0 && recipe.title.isEmpty) ? null : recipe;
  } on DioException catch (e) {
    if (e.response?.statusCode == 404) return null;
    rethrow;
  }
});
