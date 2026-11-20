/// Where a web path from the backend (notifications, AI replies) should go in
/// the app. The backend writes paths for the website; this maps them onto the
/// screens the app really has.
class AppLink {
  const AppLink({this.route, this.groceriesHome = false, this.external, this.claimToken, this.claimServiceSlug});

  /// An in-app route to push.
  final String? route;

  /// Open the Groceries home (switch Home to Groceries mode).
  final bool groceriesHome;

  /// No app screen for it: open this page on the website.
  final Uri? external;

  /// A future-capacity claim token carried by the link
  /// (`...&waitlist_claim=<token>`), to be held for the booking that follows.
  final String? claimToken;
  final String? claimServiceSlug;
}

/// Maps a web path / URL to an [AppLink].
///
///   /booking/services?category=<slug>[&service=<slug>][&waitlist_claim=<t>]
///                                     -> /categories/<slug>[?sub=<service>]
///   /booking, /services               -> /categories
///   /trucks.. /two-wheelers.. /packers.. -> Goods & Transport
///   /vegetables /groceries            -> Groceries home
///   /bookings /customer/bookings      -> My bookings
///   /marketplace/combo/<id>, /combos  -> the combo offer (or the combo list)
///   /cart /profile /support           -> the matching screen
///   anything else                     -> the website
///
/// [knownCategorySlugs], when given, is used to swap the web's combined
/// category names for the nearest real one (the app's catalog doesn't have them).
AppLink resolveWebLink(String rawUrl, {Set<String>? knownCategorySlugs}) {
  var uri = Uri.tryParse(rawUrl.trim());
  if (uri == null) return const AppLink();

  if (uri.hasScheme) {
    final isSevo = uri.host == 'sevo.co.in' || uri.host.endsWith('.sevo.co.in');
    if (!isSevo) return AppLink(external: uri);
    uri = Uri(path: uri.path, query: uri.hasQuery ? uri.query : null);
  }

  var path = uri.path;
  if (path.length > 1 && path.endsWith('/')) path = path.substring(0, path.length - 1);
  final q = uri.queryParameters;

  final claim = (q['waitlist_claim'] ?? q['future_capacity_claim_token'] ?? '').trim();

  if ((path == '/booking/services' || path == '/services') && (q['category'] ?? '').isNotEmpty) {
    const aliases = {
      'electrician_plumbing_carpentry': 'electrician',
      'home_pest_control': 'cleaning',
    };
    var slug = q['category']!;
    if (knownCategorySlugs != null && !knownCategorySlugs.contains(slug)) {
      final alias = aliases[slug];
      slug = (alias != null && knownCategorySlugs.contains(alias)) ? alias : '';
    }
    final sub = (q['service'] ?? q['subtab'] ?? '').trim();
    final route = slug.isEmpty
        ? '/categories'
        : '/categories/${Uri.encodeComponent(slug)}'
            '${sub.isEmpty || q['service'] == null ? '' : '?sub=${Uri.encodeQueryComponent(sub)}'}';
    return AppLink(
      route: route,
      claimToken: claim.isEmpty ? null : claim,
      claimServiceSlug: (q['service'] ?? '').trim().isEmpty ? null : q['service']!.trim(),
    );
  }
  if (path == '/booking' || path == '/services' || path == '/categories') {
    return const AppLink(route: '/categories');
  }
  if (path.startsWith('/trucks')) return const AppLink(route: '/goods-transport/booking?category=truck');
  if (path.startsWith('/two-wheeler')) {
    return const AppLink(route: '/goods-transport/booking?category=two_wheeler');
  }
  if (path.startsWith('/packers')) {
    return const AppLink(route: '/goods-transport/booking?category=packers_movers');
  }
  if (path == '/vegetables' || path == '/groceries' || path == '/grocery') {
    return const AppLink(groceriesHome: true);
  }
  // A grocery order's own page (the delivery-OTP notification links here).
  if (RegExp(r'^/grocery-orders/[A-Za-z0-9_-]+$').hasMatch(path)) return AppLink(route: path);
  if (path == '/bookings' || path == '/my-bookings' || path == '/customer/bookings') {
    return const AppLink(route: '/bookings');
  }
  // Combo offers: the website's /marketplace/combo/<id> (and /combos) -> the
  // app's combo screens.
  final combo = RegExp(r'^/(?:marketplace/)?(?:combo|combos|baskets?)(?:/(\d+))?$').firstMatch(path);
  if (combo != null) {
    final id = combo.group(1);
    return AppLink(route: id == null ? '/baskets' : '/baskets/$id');
  }
  // A product page (the product's slug): the app has the same /products/<slug> screen.
  if (RegExp(r'^/products/[A-Za-z0-9_.~%-]+$').hasMatch(path)) return AppLink(route: path);
  // The website's store page /marketplace?category=<slug> -> the app's Seller Hub store, opened on that department.
  if (path == '/marketplace') {
    final cat = (q['category'] ?? '').trim();
    if (cat.isEmpty) return const AppLink(groceriesHome: true);
    final isProduce = cat.contains('vegetable') || cat.contains('fruit');
    return AppLink(
      route: '${isProduce ? '/vegetables/seller-hub' : '/groceries/seller-hub'}?category=${Uri.encodeQueryComponent(cat)}',
    );
  }
  // The website's product page /marketplace/product/<id> -> the app's /products/<id> screen (it looks the product up by id).
  final webProduct = RegExp(r'^/marketplace/product/(\d+)$').firstMatch(path);
  if (webProduct != null) return AppLink(route: '/products/${webProduct.group(1)}');
  // An admin "Offers page" rule (/offers?mode=upto&v=60&cats=12,14&scope=grocery) is an app screen of its own. Without this
  // it fell through to the website and opened a browser instead of the offers page.
  if (path == '/offers') return AppLink(route: uri.hasQuery ? '/offers?${uri.query}' : '/offers');
  if (path == '/cart') return const AppLink(route: '/cart');
  if (path == '/profile') return const AppLink(route: '/profile');
  if (path == '/support') return const AppLink(route: '/support');
  // A support reply opens its ticket (/support/tickets/<id>) and the other support screens inside the app. Only the bare
  // /support was mapped, so tapping a "Support replied" notification in the notification list opened the website.
  if (path.startsWith('/support/') && RegExp(r'^/support/(tickets/\d+|requests|new)$').hasMatch(path)) {
    return AppLink(route: uri.hasQuery ? '$path?${uri.query}' : path);
  }

  return AppLink(external: Uri.https('sevo.co.in', path, q.isEmpty ? null : q));
}
