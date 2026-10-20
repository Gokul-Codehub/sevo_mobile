import '../../../config/env.dart';

/// Resolves a possibly-relative recipe image path against the Seller Hub
/// (vendor) host — recipes live on the vendor backend, same as products.
String? resolveRecipeMedia(dynamic raw) {
  final s = (raw is List && raw.isNotEmpty ? raw.first : raw ?? '').toString().trim();
  if (s.isEmpty) return null;
  if (s.startsWith('http://') || s.startsWith('https://')) return s;
  return s.startsWith('/') ? '${Env.groceryHubBaseUrl}$s' : '${Env.groceryHubBaseUrl}/$s';
}

/// Diet marker shown on a recipe: vegetarian, non-vegetarian or contains egg
/// (same three states and wording as the web recipe page).
enum RecipeDiet { veg, nonVeg, egg }

RecipeDiet recipeDietFrom(dynamic raw) {
  switch ((raw ?? '').toString().trim().toUpperCase()) {
    case 'VEG':
      return RecipeDiet.veg;
    case 'NON_VEG':
      return RecipeDiet.nonVeg;
    default:
      return RecipeDiet.egg;
  }
}

/// A recipe as listed on a product page's "Recipes & Meal Ideas" strip
/// (`product.recipes[]` from the Seller Hub product detail).
class RecipeSummary {
  const RecipeSummary({
    required this.id,
    required this.slug,
    required this.title,
    this.coverImage,
    this.diet = RecipeDiet.veg,
    this.cookTimeMinutes = 0,
    this.kcal = 0,
  });

  final int id;
  final String slug;
  final String title;
  final String? coverImage;
  final RecipeDiet diet;
  final int cookTimeMinutes;
  final int kcal;

  /// What goes in the URL / API path: the slug when there is one, else the id.
  String get key => slug.isNotEmpty ? slug : '$id';

  factory RecipeSummary.fromJson(Map<String, dynamic> j) => RecipeSummary(
        id: int.tryParse(j['id']?.toString() ?? '') ?? 0,
        slug: (j['slug'] ?? '').toString().trim(),
        title: (j['title'] ?? '').toString().trim(),
        coverImage: resolveRecipeMedia(j['cover_image']),
        diet: recipeDietFrom(j['diet_type']),
        cookTimeMinutes: int.tryParse(j['cook_time_minutes']?.toString() ?? '') ?? 0,
        kcal: int.tryParse(j['kcal']?.toString() ?? '') ?? 0,
      );
}
