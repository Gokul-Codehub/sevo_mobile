import 'package:decimal/decimal.dart';

import '../domain/catalog_models.dart';

/// Models for the Seller Hub "Basket" (combo-offer) feature.
///
/// Added 2026-10-08 ("the grocery developer has implemented another feature
/// something like Basket could you get into our app?") — mirrors the
/// already-built, already-live backend proxy in
/// `marketplace_catalog_repository.dart`'s sibling endpoints:
///   GET /api/marketplace/baskets/            — list, paginated
///   GET /api/marketplace/baskets/<id>/        — full detail
/// Both are `AllowAny` (work for guests, same as the rest of the grocery
/// catalog) and already fully sanitized server-side by
/// `workforce_integration/marketplace_views.py`'s `_sanitize_basket()` — see
/// that function's exact field list, which every parser below mirrors
/// one-for-one. No backend changes were needed for this feature; this file
/// and [MarketplaceCatalogRepository.getBaskets]/[getBasketDetail] are the
/// only new code it took.
///
/// A basket/combo bundles several real catalog products at one all-in
/// [MarketplaceBasket.bundlePrice] — e.g. "Weekly Veg Combo" at a price
/// below what its parts would cost individually. Some slots are
/// multi-option (`is_multi_option`): the customer picks one product from a
/// short list for that slot (e.g. "Any 1kg rice brand") rather than getting
/// a fixed item.
// Same offset `MarketplaceProduct._cartIdOffset` uses — every id here
// (`product_id`) is a real Seller Hub product id in that exact same id
// space, so offsetting by the same amount means adding a basket component
// to the cart merges with any quantity of that same product already added
// by browsing the catalog directly, instead of creating a second line for
// what is really the same item.
const int _basketCartIdOffset = 800000000;

Decimal? _parseDecimal(dynamic v) {
  if (v == null) return null;
  final s = v.toString().trim();
  if (s.isEmpty) return null;
  try {
    return Decimal.parse(s);
  } catch (_) {
    return null;
  }
}

/// One selectable product for a multi-option [BasketSlot] (e.g. one of
/// three rice brands a customer can pick for the "1kg Rice" slot).
class BasketSlotOption {
  const BasketSlotOption({
    this.id,
    this.optionId,
    this.productId,
    this.sku = '',
    this.title = '',
    this.brand = '',
    this.unit = '',
    this.packSize = '',
    this.mrp,
    this.sellingPrice,
    this.isDefault = false,
    this.primaryImage = '',
    this.images = const [],
    this.inStock = true,
    this.availableQuantity = 0,
  });

  final int? id;
  final int? optionId;
  final int? productId;
  final String sku;
  final String title;
  final String brand;
  final String unit;
  final String packSize;
  final Decimal? mrp;
  final Decimal? sellingPrice;
  final bool isDefault;
  final String primaryImage;
  final List<dynamic> images;
  final bool inStock;
  final int availableQuantity;

  /// Converts this option to a cart-addable [ServiceItem] at the option's
  /// OWN regular [sellingPrice] — see [MarketplaceBasket]'s doc comment for
  /// why the bundle's combo pricing can't be carried through yet.
  ServiceItem? toServiceItem() {
    final pid = productId ?? id ?? optionId;
    if (pid == null || title.isEmpty) return null;
    final hasMrp = mrp != null && sellingPrice != null && mrp! > sellingPrice!;
    return ServiceItem(
      id: _basketCartIdOffset + pid,
      title: title,
      slug: 'seller-hub-$pid',
      price: hasMrp ? mrp! : (sellingPrice ?? Decimal.zero),
      discountedPrice: hasMrp ? sellingPrice : null,
      unit: unit.isNotEmpty ? unit : (packSize.isNotEmpty ? packSize : null),
      categorySlug: 'seller_hub_groceries',
      imageUrl: primaryImage,
      inStock: inStock,
      maxQuantity: inStock ? availableQuantity.clamp(1, 99) : 0,
    );
  }

  factory BasketSlotOption.fromJson(Map<String, dynamic> json) {
    return BasketSlotOption(
      id: int.tryParse(json['id']?.toString() ?? ''),
      optionId: int.tryParse(json['option_id']?.toString() ?? ''),
      productId: int.tryParse(json['product_id']?.toString() ?? ''),
      sku: (json['sku'] ?? '').toString(),
      title: (json['title'] ?? '').toString(),
      brand: (json['brand'] ?? '').toString(),
      unit: (json['unit'] ?? '').toString(),
      packSize: (json['pack_size'] ?? '').toString(),
      mrp: _parseDecimal(json['mrp']),
      sellingPrice: _parseDecimal(json['selling_price']),
      isDefault: json['is_default'] == true,
      primaryImage: (json['primary_image'] ?? '').toString(),
      images: json['images'] is List ? json['images'] as List : const [],
      inStock: json['in_stock'] != false,
      availableQuantity: int.tryParse(json['available_quantity']?.toString() ?? '') ?? 0,
    );
  }
}

/// One slot/line of a basket — either a fixed product (one entry in
/// [options], [isMultiOption] false) or a customer-chosen one of several
/// ([isMultiOption] true, [quantity] of it goes into the bundle).
class BasketSlot {
  const BasketSlot({
    this.id,
    this.slotTitle = '',
    this.quantity = 1,
    this.displayOrder = 0,
    this.defaultProductId,
    this.options = const [],
    this.isMultiOption = false,
  });

  final int? id;
  final String slotTitle;
  final int quantity;
  final int displayOrder;
  final int? defaultProductId;
  final List<BasketSlotOption> options;
  final bool isMultiOption;

  /// The option to show/select by default — the server-marked default, or
  /// simply the first option when none is marked.
  BasketSlotOption? get defaultOption {
    if (options.isEmpty) return null;
    return options.firstWhere((o) => o.isDefault, orElse: () => options.first);
  }

  factory BasketSlot.fromJson(Map<String, dynamic> json) {
    final options = (json['options'] as List? ?? const [])
        .whereType<Map>()
        .map((m) => BasketSlotOption.fromJson(Map<String, dynamic>.from(m)))
        .toList();
    return BasketSlot(
      id: int.tryParse(json['id']?.toString() ?? ''),
      slotTitle: (json['slot_title'] ?? '').toString(),
      quantity: int.tryParse(json['quantity']?.toString() ?? '') ?? 1,
      displayOrder: int.tryParse(json['display_order']?.toString() ?? '') ?? 0,
      defaultProductId: int.tryParse(json['default_product_id']?.toString() ?? ''),
      options: options,
      isMultiOption: json['is_multi_option'] == true || options.length > 1,
    );
  }
}

/// One fixed, non-selectable component product inside a basket (the
/// simpler sibling of [BasketSlot] for baskets that don't use the
/// slot/option model at all).
class BasketItem {
  const BasketItem({
    this.productId,
    this.productTitle = '',
    this.productSku = '',
    this.quantity = 1,
    this.unit = '',
    this.packSize = '',
    this.mrp,
    this.unitPrice,
    this.primaryImage = '',
  });

  final int? productId;
  final String productTitle;
  final String productSku;
  final int quantity;
  final String unit;
  final String packSize;
  final Decimal? mrp;
  final Decimal? unitPrice;
  final String primaryImage;

  /// Converts this fixed component to a cart-addable [ServiceItem] at its
  /// own regular [unitPrice] — see [MarketplaceBasket]'s doc comment.
  ServiceItem? toServiceItem() {
    if (productId == null || productTitle.isEmpty) return null;
    final hasMrp = mrp != null && unitPrice != null && mrp! > unitPrice!;
    return ServiceItem(
      id: _basketCartIdOffset + productId!,
      title: productTitle,
      slug: 'seller-hub-$productId',
      price: hasMrp ? mrp! : (unitPrice ?? Decimal.zero),
      discountedPrice: hasMrp ? unitPrice : null,
      unit: unit.isNotEmpty ? unit : (packSize.isNotEmpty ? packSize : null),
      categorySlug: 'seller_hub_groceries',
      imageUrl: primaryImage,
    );
  }

  factory BasketItem.fromJson(Map<String, dynamic> json) {
    return BasketItem(
      productId: int.tryParse(json['product_id']?.toString() ?? ''),
      productTitle: (json['product_title'] ?? '').toString(),
      productSku: (json['product_sku'] ?? '').toString(),
      quantity: int.tryParse(json['quantity']?.toString() ?? '') ?? 1,
      unit: (json['unit'] ?? '').toString(),
      packSize: (json['pack_size'] ?? '').toString(),
      mrp: _parseDecimal(json['mrp']),
      unitPrice: _parseDecimal(json['unit_price']),
      primaryImage: (json['primary_image'] ?? '').toString(),
    );
  }
}

/// A combo/bundle offer — several real catalog products sold together at
/// one all-in [bundlePrice] below their combined [mrpTotal]. The direct
/// response shape of `GET /api/marketplace/baskets/` (list) and
/// `/api/marketplace/baskets/<id>/` (detail) — both return this same
/// sanitized object, so one model serves both screens.
class MarketplaceBasket {
  const MarketplaceBasket({
    required this.id,
    this.title = 'Combo Bundle',
    this.description = '',
    this.sellerId,
    this.sellerName = '',
    this.warehouseId,
    this.warehouseName = '',
    this.bundlePrice,
    this.mrpTotal,
    this.savings,
    this.savingsPercent,
    this.availableStock,
    this.inStock = true,
    this.primaryImage = '',
    this.slots = const [],
    this.isMultiOption = false,
    this.items = const [],
    this.itemCount = 0,
    this.isActive = true,
  });

  final int id;
  final String title;
  final String description;
  final int? sellerId;
  final String sellerName;
  final int? warehouseId;
  final String warehouseName;
  final Decimal? bundlePrice;
  final Decimal? mrpTotal;
  final Decimal? savings;
  final dynamic savingsPercent;
  final dynamic availableStock;
  final bool inStock;
  final String primaryImage;
  final List<BasketSlot> slots;
  final bool isMultiOption;
  final List<BasketItem> items;
  final int itemCount;
  final bool isActive;

  bool get hasSavings => savings != null && savings! > Decimal.zero;

  factory MarketplaceBasket.fromJson(Map<String, dynamic> json) {
    final slots = (json['slots'] as List? ?? const [])
        .whereType<Map>()
        .map((m) => BasketSlot.fromJson(Map<String, dynamic>.from(m)))
        .toList();
    final items = (json['items'] as List? ?? const [])
        .whereType<Map>()
        .map((m) => BasketItem.fromJson(Map<String, dynamic>.from(m)))
        .toList();
    return MarketplaceBasket(
      id: int.tryParse(json['id']?.toString() ?? '') ?? 0,
      title: (json['title'] ?? 'Combo Bundle').toString(),
      description: (json['description'] ?? '').toString(),
      sellerId: int.tryParse(json['seller_id']?.toString() ?? ''),
      sellerName: (json['seller_name'] ?? '').toString(),
      warehouseId: int.tryParse(json['warehouse_id']?.toString() ?? ''),
      warehouseName: (json['warehouse_name'] ?? '').toString(),
      bundlePrice: _parseDecimal(json['bundle_price']),
      mrpTotal: _parseDecimal(json['mrp_total']),
      savings: _parseDecimal(json['savings']),
      savingsPercent: json['savings_percent'],
      availableStock: json['available_stock'],
      inStock: json['in_stock'] != false,
      primaryImage: (json['primary_image'] ?? '').toString(),
      slots: slots,
      isMultiOption: json['is_multi_option'] == true || slots.any((s) => s.isMultiOption),
      items: items,
      itemCount: int.tryParse(json['item_count']?.toString() ?? '') ?? (slots.isNotEmpty ? slots.length : items.length),
      isActive: json['is_active'] != false,
    );
  }
}

/// One page of `GET /api/marketplace/baskets/` — the vendor's raw
/// paginated shape passed straight through, same convention as
/// [MarketplaceCatalogRepository.getProducts]'s `MarketplaceProductPage`.
class MarketplaceBasketPage {
  const MarketplaceBasketPage({
    required this.baskets,
    required this.count,
    required this.page,
    required this.totalPages,
  });

  final List<MarketplaceBasket> baskets;
  final int count;
  final int page;
  final int totalPages;

  static const empty = MarketplaceBasketPage(baskets: [], count: 0, page: 1, totalPages: 1);
}
