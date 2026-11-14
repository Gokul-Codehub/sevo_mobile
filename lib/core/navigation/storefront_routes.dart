/// The ONE place that decides which screen a storefront tap opens.
///
/// Rules (the same on the web store):
///  * a CATEGORY always opens the category page - sub-categories in the left rail, products on the right - no matter
///    how many products it holds (never a product page);
///  * a PRODUCT always opens the product page directly (never a category page).
///
/// Pure Dart, no Flutter imports, so it is covered by unit tests (test/core/navigation/storefront_routes_test.dart).
/// Do not build '/groceries/seller-hub?...' or '/products/...' strings anywhere else for home taps.
class StorefrontRoutes {
  const StorefrontRoutes._();

  /// Grocery / vegetable category page (two panes).
  static String groceryCategory(String slug, {bool vegetable = false}) =>
      '${vegetable ? '/vegetables' : '/groceries'}/seller-hub?category=${Uri.encodeQueryComponent(slug)}';

  /// Services category page.
  static String serviceCategory(String slug) => '/categories/$slug';

  /// Product detail page.
  static String product(String slug) => '/products/$slug';

  /// Route for a Home Studio destination, or null when the type has no in-app screen handled here
  /// (none, url, route, offer are handled by the caller).
  static String? forDestination({
    required String type,
    String value = '',
    String slug = '',
    required bool grocery,
  }) {
    final v = value.trim();
    switch (type) {
      case 'category':
        final s = slug.trim().isNotEmpty ? slug.trim() : v;
        if (s.isEmpty) return null;
        return grocery ? groceryCategory(s) : serviceCategory(s);
      case 'product':
        return v.isEmpty ? null : product(v);
      case 'service':
      case 'package':
        return v.isEmpty ? null : '/services/$v';
      case 'collection':
        return v.isEmpty ? null : '/baskets/$v';
      case 'search':
        return '/search?mode=${grocery ? 'groceries' : 'services'}${v.isEmpty ? '' : '&q=${Uri.encodeQueryComponent(v)}'}';
      default:
        return null;
    }
  }
}
