import 'package:decimal/decimal.dart';
import 'package:equatable/equatable.dart';

import '../../../core/network/response_normalizer.dart';
import '../../../core/utils/image_url_helper.dart';

/// Subcategory model under a primary category.
class Subcategory extends Equatable {
  const Subcategory({
    required this.id,
    required this.name,
    required this.slug,
    this.description,
    this.icon,
    this.image,
  });

  final int id;
  final String name;
  final String slug;
  final String? description;
  final String? icon;
  final String? image;

  factory Subcategory.fromJson(Map<String, dynamic> json) {
    return Subcategory(
      id: parseInt(json['id']),
      name: json['name']?.toString() ?? '',
      slug: json['slug']?.toString() ?? '',
      description: json['description']?.toString(),
      icon: json['icon']?.toString(),
      image: ImageUrlHelper.resolve(
        json['image']?.toString() ?? json['image_url']?.toString(),
      ),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'slug': slug,
        if (description != null) 'description': description,
        if (icon != null) 'icon': icon,
        if (image != null) 'image': image,
      };

  @override
  List<Object?> get props => [id, name, slug, description, icon, image];
}

/// Business flow classification distinguishing quick-commerce grocery,
/// scheduled service bookings, and goods/logistics transport.
enum CatalogFlowType {
  /// Quick commerce: instant/express delivery, items cart, quantity (+/-), delivery address, grocery checkout
  grocery,

  /// Service booking: technicians, packages, inclusions/exclusions, date/time slot picker, advance deposit
  serviceBooking,

  /// Added 2026-09-19 as part of building the real Goods & Transport
  /// booking flow (verified backend category slug "goods_transports", id
  /// 12, per CALSERVICES_PRODUCTION_API_CONTRACT.md and
  /// CALSERVICES_PRODUCTION_SOURCE_OF_TRUTH.md §7). Before this, every
  /// Goods & Transport category fell through to [serviceBooking] and
  /// routed into the generic package-detail/checkout screen, which has no
  /// pickup/drop address, no vehicle-tier picker, and never sends
  /// `drop_address`/`logistics_tier`/`logistics_lane` — the real backend
  /// booking-create serializer (`ServiceRequestPublicCreateSerializer`)
  /// then rejects the booking with a 400 because it can't resolve a fare
  /// without a tier/lane. This flow type is what routes those categories
  /// to the dedicated Goods & Transport booking screen instead.
  logistics,
}

/// Service category model.
class Category extends Equatable {
  const Category({
    required this.id,
    required this.name,
    required this.slug,
    this.description,
    this.icon,
    this.image,
    this.displayOrder = 0,
    this.isActive = true,
    this.subcategories = const [],
  });

  final int id;
  final String name;
  final String slug;
  final String? description;
  final String? icon;
  final String? image;
  final int displayOrder;
  final bool isActive;
  final List<Subcategory> subcategories;

  /// Determines whether this category represents a quick-commerce grocery catalog or scheduled services.
  ///
  /// Fixed 2026-09-01: dropped the `id == 18` shortcut. Category IDs are
  /// assigned by the admin portal and are not guaranteed to stay fixed —
  /// keying flow detection to a specific numeric ID risks misclassifying
  /// whatever category the admin happens to give that ID to next. The
  /// backend has no explicit "flow type" field, so name/slug keyword
  /// matching is still the only signal available; it is applied uniformly
  /// here rather than short-circuited by an ID that could be reassigned.
  CatalogFlowType get flowType {
    final slugLower = slug.toLowerCase().replaceAll('-', '_');
    final nameLower = name.toLowerCase();
    if (slugLower == 'vegetables_groceries' ||
        slugLower == 'farm_fresh_vegetables_groceries' ||
        slugLower == 'vegetables_and_groceries' ||
        slugLower == 'farm_fresh' ||
        slugLower.contains('vegetable') ||
        slugLower.contains('grocer') ||
        nameLower.contains('vegetable') ||
        nameLower.contains('grocer')) {
      return CatalogFlowType.grocery;
    }
    // Added 2026-09-19: the real, verified category slug is
    // "goods_transports" (id 12) — matched exactly first, with a
    // name/slug keyword fallback (same convention as the grocery check
    // above) in case the admin ever renames it slightly.
    if (slugLower == 'goods_transports' ||
        slugLower.contains('goods_transport') ||
        slugLower.contains('transport') ||
        (nameLower.contains('goods') && nameLower.contains('transport'))) {
      return CatalogFlowType.logistics;
    }
    return CatalogFlowType.serviceBooking;
  }

  factory Category.fromJson(Map<String, dynamic> json) {
    final rawSub = json['subcategories'] ?? json['subs'] ?? json['services'];
    final List<dynamic> subList;
    if (rawSub is List) {
      subList = rawSub;
    } else if (rawSub is Map && rawSub['results'] is List) {
      subList = rawSub['results'] as List;
    } else if (rawSub is Map && rawSub['data'] is List) {
      subList = rawSub['data'] as List;
    } else {
      subList = const [];
    }

    final rawImage = json['image']?.toString() ?? json['image_url']?.toString();
    final catName = json['name']?.toString() ?? '';
    final catSlug = json['slug']?.toString() ?? '';
    final resolvedImage = ImageUrlHelper.resolve(
      rawImage,
      title: catName,
      slug: catSlug,
      categorySlug: catSlug,
      categoryId: parseIntOrNull(json['id']),
    );

    return Category(
      id: parseInt(json['id']),
      name: catName,
      slug: catSlug,
      description: (json['description'] ?? json['desc'])?.toString(),
      icon: json['icon']?.toString(),
      image: resolvedImage,
      // API returns 'sort_order' — 'display_order' is the legacy field name
      displayOrder: parseInt(json['sort_order'] ?? json['display_order']),
      isActive: parseBoolOrDefault(json['is_active'] ?? json['active'], true),
      subcategories: subList
          .whereType<Map>()
          .map((m) => Subcategory.fromJson(Map<String, dynamic>.from(m)))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'slug': slug,
        if (description != null) 'description': description,
        if (icon != null) 'icon': icon,
        if (image != null) 'image': image,
        'display_order': displayOrder,
        'is_active': isActive,
        'subcategories': subcategories.map((s) => s.toJson()).toList(),
      };

  @override
  List<Object?> get props => [
        id,
        name,
        slug,
        description,
        icon,
        image,
        displayOrder,
        isActive,
        subcategories,
      ];
}

/// FAQ item for a service.
class ServiceFaq extends Equatable {
  const ServiceFaq({
    required this.question,
    required this.answer,
  });

  final String question;
  final String answer;

  factory ServiceFaq.fromJson(Map<String, dynamic> json) {
    return ServiceFaq(
      question: (json['question'] ?? json['q'] ?? '').toString(),
      answer: (json['answer'] ?? json['a'] ?? '').toString(),
    );
  }

  Map<String, dynamic> toJson() => {
        'question': question,
        'answer': answer,
      };

  @override
  List<Object?> get props => [question, answer];
}

/// Service item model with money parsing and metadata.
class ServiceItem extends Equatable {
  const ServiceItem({
    required this.id,
    required this.title,
    required this.slug,
    required this.price,
    this.discountedPrice,
    this.unit,
    this.shortDescription,
    this.description,
    this.durationMinutes = 60,
    this.rating = 4.8,
    this.reviewCount = 0,
    this.categoryId,
    this.categoryName,
    this.categorySlug,
    this.subcategoryName,
    this.subcategorySlug,
    this.imageUrl,
    this.isPopular = false,
    this.isEssential = false,
    this.inclusions = const [],
    this.exclusions = const [],
    this.faqs = const [],
    this.readyInstructions = const [],
    this.tools = const [],
    this.vegetableCategoryName,
    this.vegetableCategorySlug,
    this.vegetableCategoryParentName,
    this.vegetableCategoryFullPath,
    this.inStock = true,
    this.maxQuantity = 99,
    this.gstRate,
    this.platformFee,
  });

  final int id;
  final String title;
  final String slug;
  final Decimal price;
  final Decimal? discountedPrice;
  final String? unit;
  final String? shortDescription;
  final String? description;
  final int durationMinutes;
  final double rating;
  final int reviewCount;
  final int? categoryId;
  final String? categoryName;
  final String? categorySlug;
  final String? subcategoryName;
  final String? subcategorySlug;
  final String? imageUrl;
  final bool isPopular;
  final bool isEssential;
  final List<String> inclusions;
  final List<String> exclusions;
  final List<ServiceFaq> faqs;

  /// "What you need to get ready" — the real backend's Package.ready field
  /// (service_requests/models.py: `Package.ready = JSONField(default=list)`,
  /// exposed via CatalogServiceSerializer). Fixed 2026-09-16: this was
  /// briefly mis-typed as a String and parsed with `.toString()` on the
  /// decoded JSON list, which produces Dart's bracket-literal debug text
  /// (e.g. "[Keep pets away, Clear access]") instead of usable items — it is
  /// a list of instruction strings, exactly like [inclusions]/[exclusions].
  final List<String> readyInstructions;

  /// "Tools & Products We Use" — the real backend's Package.tools field
  /// (service_requests/models.py: `Package.tools = JSONField(default=list)`),
  /// also exposed via CatalogServiceSerializer. Previously never modeled in
  /// the mobile app at all.
  final List<String> tools;

  // ── Vegetable Inventory category (added 2026-09-23) ──────────────────────
  //
  // The admin's new "Vegetable Inventory" module (Catalog Requests & Uploads
  // → Categories, per the Department/Top-Level → Subcategory L2 →
  // Subcategory L3 picker) organizes real produce into a category tree
  // (`inventory.VegetableCategory`, unlimited nesting). A produce item's
  // sellable [ServiceItem] is still just a `Package` under the single
  // "vegetables" Service — the deep category it was filed under only
  // reaches the customer app via these four fields the backend's
  // `CatalogServiceSerializer` now serializes (`vegetable_category_name`,
  // `_slug`, `_parent_name`, `_full_path`), sourced from
  // `Package.stock_item.category` (`stock_item` is the linked `Vegetable`).
  // A non-produce grocery Package (e.g. one added directly without going
  // through the Vegetable Inventory flow) simply has all four as null —
  // callers must treat that as "uncategorized", never as an error.
  final String? vegetableCategoryName;
  final String? vegetableCategorySlug;
  final String? vegetableCategoryParentName;
  final String? vegetableCategoryFullPath;

  // ── Live stock (added 2026-09-23) ─────────────────────────────────────────
  //
  // The backend's `CatalogServiceSerializer`/`PackageSerializer` already
  // compute these per package (`get_in_stock`/`get_max_quantity`, backed by
  // `inventory.selectors.vegetable_stock_selectors.get_stock_status` —
  // real gram-level stock for a Vegetable Inventory produce item, or the
  // `{"in_stock": true, "max_quantity": 99}` default for anything else) and
  // return them on every catalog response — this app just wasn't reading
  // them yet, so an out-of-stock item showed exactly like an in-stock one
  // with no cap on how many a customer could add. Defaults here
  // (`true`/`99`) intentionally match the backend's own fallback shape, so
  // a service-booking Package (never stock-tracked) or an older cached
  // catalog payload without these keys behaves exactly as before.
  final bool inStock;
  final int maxQuantity;

  // ── Per-package GST / platform fee (added 2026-10-07) ─────────────────────
  //
  // Bug found: the web app (frontend/src/ui/pages/BookingPage.jsx) has
  // always priced each package using ITS OWN `gst_rate`/`platform_fee`
  // (admin-set per package in the Service Catalog; falls back to 18% / ₹29
  // when a package doesn't set its own) -- already returned by the backend's
  // CatalogServiceSerializer on every catalog response. The admin's global
  // Settings > Pricing > "Home Services" page (a single flat GST% and
  // Platform Fee for every service) is a SEPARATE config the web booking
  // flow never actually reads. This app, however, only ever read that flat
  // global config (features/pricing/) and never parsed these per-package
  // fields at all -- so mobile and web could show two different totals for
  // the exact same package. These carry the per-package override through so
  // cart_notifier.dart's cartSummaryProvider can match web's real formula
  // instead of the flat admin page. Null means the backend didn't send one
  // for this package (legacy payload, or genuinely unset) -- callers fall
  // back to web's own default (18% / ₹29), never to the flat global config.
  final double? gstRate;
  final Decimal? platformFee;

  /// Whether this item was filed under a real Vegetable Inventory category
  /// (as opposed to a plain grocery Package with no category tree entry).
  bool get hasVegetableCategory =>
      vegetableCategorySlug != null && vegetableCategorySlug!.isNotEmpty;

  /// The top-level department this item belongs to (e.g. "Fresh
  /// Vegetables", "Fresh Fruits") — the tile a Blinkit-style browse screen
  /// groups by. Derived from [vegetableCategoryFullPath] (e.g. "All → Fresh
  /// Vegetables → Bottle Gourd(Surakkai)"): the leading "All" pseudo-root
  /// segment (the admin portal's own catch-all root node, mirrored by its
  /// `only_roots=true` query param) is dropped, and the next segment is the
  /// department. Falls back to [vegetableCategoryParentName] (the
  /// immediate parent, one level up) when there's no ' → ' to split — i.e.
  /// the item's category IS already a top-level department (no "All" root
  /// configured, or the item sits directly under it) — and finally to
  /// [vegetableCategoryName] itself so a department-less produce item still
  /// gets its own single-item "department" rather than disappearing.
  String? get vegetableDepartmentName {
    final path = vegetableCategoryFullPath?.trim();
    if (path != null && path.isNotEmpty) {
      final segments = path
          .split('→')
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList();
      final withoutRoot = segments.isNotEmpty && segments.first.toLowerCase() == 'all'
          ? segments.skip(1).toList()
          : segments;
      if (withoutRoot.isNotEmpty) return withoutRoot.first;
    }
    final parent = vegetableCategoryParentName?.trim();
    if (parent != null && parent.isNotEmpty && parent.toLowerCase() != 'all') {
      return parent;
    }
    final own = vegetableCategoryName?.trim();
    return (own != null && own.isNotEmpty) ? own : null;
  }

  /// The subcategory directly above the leaf, when the tree is deeper than
  /// department → produce (i.e. department → L2 → ... → this item's own
  /// leaf category). Null when this item's category IS the department
  /// (nothing to show as a second-level chip).
  String? get vegetableSubcategoryName {
    final parent = vegetableCategoryParentName?.trim();
    final dept = vegetableDepartmentName;
    if (parent == null || parent.isEmpty) return null;
    if (dept != null && parent.toLowerCase() == dept.toLowerCase()) return null;
    return parent;
  }

  Decimal get effectivePrice => discountedPrice ?? price;
  bool get hasDiscount => discountedPrice != null && discountedPrice! < price;
  Decimal get mrp => hasDiscount ? price : ((price * Decimal.fromInt(12)) / Decimal.fromInt(10)).toDecimal();

  /// Real discount percentage off MRP, rounded to the nearest whole
  /// percent. Returns null when there's no discount to show.
  ///
  /// Fixed 2026-09-16: the service detail screen previously showed a
  /// hardcoded literal "28% OFF" badge regardless of the actual prices —
  /// this computes the real percentage from price vs. discountedPrice.
  int? get discountPercent {
    if (!hasDiscount) return null;
    final priceD = price.toDouble();
    if (priceD <= 0) return null;
    final diffD = priceD - discountedPrice!.toDouble();
    return ((diffD / priceD) * 100).round();
  }

  /// Determines whether this item belongs to the quick-commerce grocery flow or scheduled service booking.
  ///
  /// Fixed 2026-09-01: dropped the `categoryId == 18` shortcut, matching
  /// [Category.flowType] above — admin-assigned category IDs aren't a
  /// stable signal for this, so only the name/slug keyword match is used.
  CatalogFlowType get flowType {
    final catSlugLower = (categorySlug ?? '').toLowerCase().replaceAll('-', '_');
    final catNameLower = (categoryName ?? '').toLowerCase();
    final srvSlugLower = slug.toLowerCase();
    if (catSlugLower == 'vegetables_groceries' ||
        catSlugLower == 'farm_fresh_vegetables_groceries' ||
        catSlugLower == 'vegetables_and_groceries' ||
        catSlugLower == 'farm_fresh' ||
        catSlugLower.contains('vegetable') ||
        catSlugLower.contains('grocer') ||
        catNameLower.contains('vegetable') ||
        catNameLower.contains('grocer') ||
        srvSlugLower.startsWith('veg-') ||
        srvSlugLower.contains('beetroot')) {
      return CatalogFlowType.grocery;
    }
    // Added 2026-09-19 — see [Category.flowType]'s matching comment above
    // for why (real verified slug "goods_transports", id 12).
    if (catSlugLower == 'goods_transports' ||
        catSlugLower.contains('goods_transport') ||
        catSlugLower.contains('transport') ||
        (catNameLower.contains('goods') && catNameLower.contains('transport'))) {
      return CatalogFlowType.logistics;
    }
    return CatalogFlowType.serviceBooking;
  }

  // Marketplace-sourced items are id-offset by +800000000, Grocery-Hub-
  // sourced ones by +900000000 (see MarketplaceProduct.toServiceItem() /
  // GroceryHubProduct.toServiceItem()) specifically so they never collide
  // with a catalog service id in the cart -- a side effect is that id is
  // also a reliable "this came from a grocery source" signal in its own
  // right, independent of category metadata.
  static const int _groceryCartIdOffset = 800000000;

  /// Whether this item is a grocery/vegetable item, for places where
  /// [flowType]'s pure category-keyword match is not reliable on its own.
  ///
  /// Bug found: a booking's own echoed `cart_data` (a schemaless JSONField)
  /// frequently omits `category_slug`/`category_name`, so a `ServiceItem`
  /// rebuilt from it silently misclassified as [CatalogFlowType.serviceBooking]
  /// even for a genuine grocery item. That was already fixed for the Home
  /// screen's "Book Again" tiles (2026-10-06/07) with this exact fallback
  /// chain; `cartSummaryProvider` (cart_notifier.dart) had the identical bug
  /// in its own `isGrocery` check -- charging a grocery cart the home-service
  /// fee formula (platform fee + GST) instead of delivery/handling/small-cart
  /// fees, folded into the grand total with no line item shown for it at
  /// all. Prefer this getter over a bare `flowType ==
  /// CatalogFlowType.grocery` check anywhere pricing or cart-mode filtering
  /// depends on getting this right.
  bool get isGroceryFlow =>
      flowType == CatalogFlowType.grocery ||
      hasVegetableCategory ||
      (vegetableCategoryName?.isNotEmpty ?? false) ||
      id >= _groceryCartIdOffset;

  /// Formatted weight/unit string for grocery items (defaults to '500 g' or '1 unit' if unspecified).
  String get displayUnit {
    if (unit != null && unit!.isNotEmpty) return unit!;
    if (shortDescription != null && shortDescription!.contains(RegExp(r'\d+\s*(g|kg|ml|L|pcs|pack|bunch)', caseSensitive: false))) {
      return shortDescription!;
    }
    return '500 g';
  }

  /// Extracts a flat list of display strings from one of this catalog's
  /// "list of admin-entered lines" JSON fields (inclusions/exclusions/ready/
  /// tools). Handles both shapes actually seen from the backend:
  ///   - a plain string: `"Complete inspection"`
  ///   - a labeled object with a per-line enable toggle, e.g.
  ///     `{"text": "Continuous water tap...", "enabled": true}`
  ///
  /// Fixed 2026-09-17: this used to call `.toString()` on every raw element
  /// regardless of type — for the labeled-object shape (confirmed live on
  /// device: "What you need to get ready" / "Tools and products we use"
  /// were rendering the literal `{text: ..., enabled: true}` Dart Map
  /// representation instead of the actual text). It also never respected
  /// `enabled: false`, which the admin panel uses to hide a line without
  /// deleting it — those were being shown to the customer anyway.
  static List<String> _extractLabeledList(dynamic raw) {
    if (raw is! List) return const [];
    final out = <String>[];
    for (final e in raw) {
      if (e is Map) {
        final map = Map<String, dynamic>.from(e);
        final enabled = map['enabled'];
        if (enabled == false) continue; // admin explicitly hid this line
        final text = (map['text'] ?? map['label'] ?? map['name'] ?? map['title'])
            ?.toString()
            .trim();
        if (text != null && text.isNotEmpty) out.add(text);
      } else if (e != null) {
        final text = e.toString().trim();
        if (text.isNotEmpty) out.add(text);
      }
    }
    return out;
  }

  factory ServiceItem.fromJson(Map<String, dynamic> json) {
    final incList = _extractLabeledList(json['inclusions'] ?? json['includes']);
    final excList = _extractLabeledList(json['exclusions'] ?? json['excludes']);

    final rawFaq = json['faqs'] ?? json['faq'];
    final faqList = rawFaq is List ? rawFaq : const [];

    final readyList = _extractLabeledList(json['ready']);
    final toolsList = _extractLabeledList(json['tools']);

    // Safely resolve image: check image, service_image, and image_url ignoring empty strings
    String? rawImage;
    final imgCandidate = json['image']?.toString();
    final srvImgCandidate = json['service_image']?.toString();
    final imgUrlCandidate = json['image_url']?.toString();

    if (imgCandidate != null && imgCandidate.trim().isNotEmpty) {
      rawImage = imgCandidate;
    } else if (srvImgCandidate != null && srvImgCandidate.trim().isNotEmpty) {
      rawImage = srvImgCandidate;
    } else if (imgUrlCandidate != null && imgUrlCandidate.trim().isNotEmpty) {
      rawImage = imgUrlCandidate;
    }

    final title = (json['title'] ?? json['name'] ?? '').toString();
    final slug = json['slug']?.toString() ?? '';
    final categoryId = parseIntOrNull(
      json['category_id'] ??
          (json['category'] is Map ? json['category']['id'] : json['category']),
    );
    final categorySlug = json['category_slug']?.toString() ??
        (json['category'] is Map ? json['category']['slug']?.toString() : null);

    return ServiceItem(
      id: parseInt(json['id']),
      title: title,
      slug: slug,
      price: parseMoney(json['price'] ?? json['base_price'] ?? 0),
      // Fixed 2026-09-16: the real backend (CatalogServiceSerializer) sends
      // the discounted/final price as `offer_price` — this only ever
      // checked `discounted_price`, which the backend never sends, so MRP/
      // discount/final-price were silently never showing for any package
      // that actually had an offer price configured. `discounted_price` is
      // still checked first for forward-compat with any endpoint that does
      // use that name.
      discountedPrice: _positiveOrNull(parseMoneyOrNull(
        json['discounted_price'] ?? json['offer_price'],
      )),
      unit: json['unit']?.toString(),
      shortDescription: json['short_description']?.toString(),
      description: json['description']?.toString(),
      // API returns 'duration' as string (e.g. '3 hrs') — parse to minutes.
      // Fall back to 'duration_minutes' int if present.
      durationMinutes: _parseDurationMinutes(
        json['duration']?.toString(),
        json['duration_minutes'],
      ),
      rating: parseDoubleOrNull(json['rating']) ?? 4.8,
      reviewCount: parseInt(json['review_count']),
      categoryId: categoryId,
      categoryName: json['category_name']?.toString() ??
          (json['category'] is Map ? json['category']['name']?.toString() : null),
      categorySlug: categorySlug,
      subcategoryName: json['subcategory_name']?.toString() ?? json['service_name']?.toString(),
      subcategorySlug: json['subcategory_slug']?.toString() ?? json['service_slug']?.toString(),
      imageUrl: ImageUrlHelper.resolve(
        rawImage,
        title: title,
        slug: slug,
        categorySlug: categorySlug,
        categoryId: categoryId,
      ),
      // API returns 'popular' (not 'is_popular') — check both for forward-compat
      isPopular: parseBoolOrDefault(json['popular'] ?? json['is_popular'], false),
      isEssential: parseBoolOrDefault(json['is_essential'] ?? json['essential'], false),
      inclusions: incList,
      exclusions: excList,
      faqs: faqList
          .whereType<Map>()
          .map((m) => ServiceFaq.fromJson(Map<String, dynamic>.from(m)))
          .toList(),
      // Real backend fields (CatalogServiceSerializer's "ready"/"tools") —
      // see _extractLabeledList's doc comment above for the two JSON shapes
      // this now handles correctly.
      readyInstructions: readyList,
      tools: toolsList,
      vegetableCategoryName: _nonEmpty(json['vegetable_category_name']),
      vegetableCategorySlug: _nonEmpty(json['vegetable_category_slug']),
      vegetableCategoryParentName: _nonEmpty(json['vegetable_category_parent_name']),
      vegetableCategoryFullPath: _nonEmpty(json['vegetable_category_full_path']),
      inStock: parseBoolOrDefault(json['in_stock'], true),
      maxQuantity: parseInt(json['max_quantity'], fallback: 99),
      gstRate: parseDoubleOrNull(json['gst_rate']),
      platformFee: parseMoneyOrNull(json['platform_fee']),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'slug': slug,
        'price': price.toString(),
        if (discountedPrice != null) 'discounted_price': discountedPrice.toString(),
        if (unit != null) 'unit': unit,
        if (shortDescription != null) 'short_description': shortDescription,
        if (description != null) 'description': description,
        'duration_minutes': durationMinutes,
        'rating': rating,
        'review_count': reviewCount,
        if (categoryId != null) 'category_id': categoryId,
        if (categoryId != null) 'category': categoryId,
        if (categoryName != null) 'category_name': categoryName,
        if (categorySlug != null) 'category_slug': categorySlug,
        if (subcategoryName != null) 'subcategory_name': subcategoryName,
        if (subcategorySlug != null) 'subcategory_slug': subcategorySlug,
        if (imageUrl != null) 'image': imageUrl,
        'is_popular': isPopular,
        'is_essential': isEssential,
        'inclusions': inclusions,
        'exclusions': exclusions,
        'faqs': faqs.map((f) => f.toJson()).toList(),
        'ready': readyInstructions,
        'tools': tools,
        if (vegetableCategoryName != null) 'vegetable_category_name': vegetableCategoryName,
        if (vegetableCategorySlug != null) 'vegetable_category_slug': vegetableCategorySlug,
        if (vegetableCategoryParentName != null)
          'vegetable_category_parent_name': vegetableCategoryParentName,
        if (vegetableCategoryFullPath != null)
          'vegetable_category_full_path': vegetableCategoryFullPath,
        'in_stock': inStock,
        'max_quantity': maxQuantity,
        if (gstRate != null) 'gst_rate': gstRate,
        if (platformFee != null) 'platform_fee': platformFee.toString(),
      };

  @override
  List<Object?> get props => [
        id,
        title,
        slug,
        price,
        discountedPrice,
        shortDescription,
        description,
        durationMinutes,
        rating,
        reviewCount,
        categoryId,
        categoryName,
        categorySlug,
        subcategoryName,
        subcategorySlug,
        imageUrl,
        isPopular,
        isEssential,
        inclusions,
        exclusions,
        faqs,
        readyInstructions,
        tools,
        vegetableCategoryName,
        vegetableCategorySlug,
        vegetableCategoryParentName,
        vegetableCategoryFullPath,
        inStock,
        maxQuantity,
        gstRate,
        platformFee,
      ];
}

/// Returns [value] unless it's non-positive (backend sends 0/absent offer
/// prices for un-discounted packages, which must never be treated as a
/// real discounted price — see [ServiceItem.discountedPrice]).
Decimal? _positiveOrNull(Decimal? value) {
  if (value == null || value <= Decimal.zero) return null;
  return value;
}

/// Trims [raw] and returns it unless empty/null — used for the optional
/// vegetable-category string fields, which the backend sends as `null` for
/// any Package that isn't linked to a Vegetable Inventory produce item.
String? _nonEmpty(dynamic raw) {
  final s = raw?.toString().trim();
  return (s == null || s.isEmpty) ? null : s;
}

// ── Helpers ───────────────────────────────────────────────────────────────────

/// Parses the API's string duration ('3 hrs', '45 mins', '1.5 hours') to minutes.
/// Falls back to [rawMinutes] int if the string is absent/unparseable, then to 60.
int _parseDurationMinutes(String? durationStr, dynamic rawMinutes) {
  // Prefer the direct int field if available
  if (rawMinutes != null) {
    final parsed = int.tryParse(rawMinutes.toString());
    if (parsed != null && parsed > 0) return parsed;
  }

  if (durationStr == null || durationStr.trim().isEmpty) return 60;

  final s = durationStr.toLowerCase().trim();

  // Try parsing patterns like '3 hrs', '45 mins', '1.5 hours', '90 min', '2h'
  final numMatch = RegExp(r'(\d+(?:\.\d+)?)').firstMatch(s);
  if (numMatch == null) return 60;
  final value = double.tryParse(numMatch.group(1) ?? '') ?? 1.0;

  if (s.contains('hr') || s.contains('hour') || s.contains('h')) {
    return (value * 60).round();
  } else if (s.contains('min') || s.contains('m')) {
    return value.round();
  }
  // Fallback: assume hours if number is small, minutes if large
  return value < 10 ? (value * 60).round() : value.round();
}

// ── Vegetable Inventory department grouping (added 2026-09-23) ─────────────
//
// Blinkit/Instamart-style "browse by department, then subcategory" grouping
// built entirely client-side from [ServiceItem.vegetableDepartmentName] /
// [ServiceItem.vegetableSubcategoryName] — items already fetched for the
// grocery category's flat product list, no extra network call. A produce
// item with no Vegetable Inventory category at all (a plain grocery Package
// never filed under a [VegetableCategory]) is bucketed under
// [kUncategorizedDepartment] so it's still browsable rather than silently
// dropped from the grid.
const String kUncategorizedDepartment = 'Everyday Essentials';

/// One department tile (e.g. "Fresh Vegetables") plus everything under it,
/// pre-split into its L2 subcategory groups for the chip row shown after
/// drilling in. [image] is best-effort: the first item in the department
/// that actually has one, purely for the tile's thumbnail — never used for
/// anything transactional.
class VegetableDepartmentGroup {
  const VegetableDepartmentGroup({
    required this.name,
    required this.items,
    required this.subcategories,
  });

  final String name;
  final List<ServiceItem> items;

  /// Subcategory name -> its items, in first-seen order. A department with
  /// no deeper nesting (produce filed directly under it) has exactly one
  /// entry here keyed by [name] itself, so callers can treat "has more than
  /// one subcategory" as the signal to show the L2 chip row at all.
  final Map<String, List<ServiceItem>> subcategories;

  String? get image {
    for (final item in items) {
      if (item.imageUrl != null && item.imageUrl!.isNotEmpty) return item.imageUrl;
    }
    return null;
  }

  /// Whether this department actually has more than one distinct
  /// subcategory worth showing as its own chip (vs. everything just sitting
  /// directly under the department, where an L2 row would be redundant).
  bool get hasSubcategoryBreakdown =>
      subcategories.length > 1 || (subcategories.length == 1 && !subcategories.containsKey(name));
}

/// Groups [items] into Blinkit-style department tiles. Only meant for a
/// grocery-flow item list (callers filter by [ServiceItem.flowType] first);
/// an item with no vegetable category lands in [kUncategorizedDepartment]
/// rather than being dropped, so nothing a customer could otherwise buy
/// disappears from the grid just because it predates the Vegetable
/// Inventory feature.
List<VegetableDepartmentGroup> groupServiceItemsByDepartment(
  List<ServiceItem> items,
) {
  final departmentOrder = <String>[];
  final byDepartment = <String, List<ServiceItem>>{};

  for (final item in items) {
    final dept = item.vegetableDepartmentName ?? kUncategorizedDepartment;
    if (!byDepartment.containsKey(dept)) {
      departmentOrder.add(dept);
      byDepartment[dept] = [];
    }
    byDepartment[dept]!.add(item);
  }

  return departmentOrder.map((dept) {
    final deptItems = byDepartment[dept]!;
    final subOrder = <String>[];
    final bySub = <String, List<ServiceItem>>{};
    for (final item in deptItems) {
      final sub = item.vegetableSubcategoryName ?? dept;
      if (!bySub.containsKey(sub)) {
        subOrder.add(sub);
        bySub[sub] = [];
      }
      bySub[sub]!.add(item);
    }
    return VegetableDepartmentGroup(
      name: dept,
      items: deptItems,
      subcategories: {for (final s in subOrder) s: bySub[s]!},
    );
  }).toList();
}

// ── Admin Vegetable Inventory category tree (added 2026-09-23) ─────────────
//
// [groupServiceItemsByDepartment] above only ever shows departments that
// currently have at least one live, in-stock product — a department the
// admin created in the "Vegetable Categories" tree with zero produce filed
// under it yet (e.g. "Fresh Fruits", "Coriander & Others" — both real,
// confirmed via the admin screenshot) never appeared as a tile at all,
// which is exactly what "completely different from what I configured"
// meant. This model instead comes straight from the admin's own tree via
// `GET /api/inventory/vegetable-categories/?status=APPROVED&only_roots=true`
// (public, confirmed AllowAny — see inventory/views.py
// VegetableCategoryListCreateView.get_permissions) so every top-level
// department the admin has actually created shows up as a tile, empty ones
// included — they fall through to the existing "No Produce Here Yet" empty
// state when tapped instead of not existing at all.
class VegetableCategorySummary extends Equatable {
  const VegetableCategorySummary({
    required this.id,
    required this.name,
    required this.slug,
    this.parentId,
    this.image,
    this.vegetablesCount = 0,
    this.subcategoriesCount = 0,
  });

  final int id;
  final String name;
  final String slug;

  /// Null for a true root node — including the admin's own "All" pseudo-root
  /// wrapper, which `only_roots=true` deliberately returns alongside its
  /// real children (see [_isPseudoRootAll] in catalog_repository.dart's
  /// getVegetableDepartments). Kept here (rather than filtering purely by
  /// name/slug) so that filter can key off actual tree structure instead of
  /// a hardcoded string match.
  final int? parentId;
  final String? image;

  /// Produce filed DIRECTLY under this category (not recursive — see
  /// inventory/serializers.py get_vegetables_count). A department can be
  /// legitimately "empty" here while still having produce under one of its
  /// own subcategories; [subcategoriesCount] is what actually decides
  /// whether it's worth showing at all, not this count.
  final int vegetablesCount;
  final int subcategoriesCount;

  factory VegetableCategorySummary.fromJson(Map<String, dynamic> json) {
    return VegetableCategorySummary(
      id: parseInt(json['id']),
      name: json['name']?.toString().trim() ?? '',
      slug: json['slug']?.toString() ?? '',
      parentId: parseIntOrNull(json['parent']),
      image: ImageUrlHelper.resolve(json['image']?.toString()),
      vegetablesCount: parseInt(json['vegetables_count']),
      subcategoriesCount: parseInt(json['subcategories_count']),
    );
  }

  @override
  List<Object?> get props =>
      [id, name, slug, parentId, image, vegetablesCount, subcategoriesCount];
}
