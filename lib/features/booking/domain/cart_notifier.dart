import 'dart:convert';
import 'package:decimal/decimal.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/storage/secure_storage.dart';
import '../../../core/utils/app_logger.dart';
import '../../auth/domain/auth_models.dart';
import '../../auth/domain/auth_notifier.dart';
import '../../catalog/domain/catalog_models.dart';
import '../../pricing/domain/pricing_providers.dart';
import 'booking_models.dart';

/// State notifier for customer shopping cart with persistent local storage.
class CartNotifier extends Notifier<List<CartItem>> {
  @override
  List<CartItem> build() {
    _loadFromStorage();
    return const [];
  }

  Future<void> _loadFromStorage() async {
    try {
      final storage = ref.read(secureStorageProvider);
      final raw = await storage.getCartJson();
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          final items = decoded
              .whereType<Map>()
              .map((m) => CartItem.fromStorageJson(Map<String, dynamic>.from(m)))
              .toList();
          if (items.isNotEmpty && state.isEmpty) {
            state = items;
          }
        }
      }
    } catch (_) {
      // Storage unavailable in unit test harness
    }
  }

  void _persist() {
    try {
      final storage = ref.read(secureStorageProvider);
      if (state.isEmpty) {
        storage.clearCartStorage().catchError((_) {});
      } else {
        final list = state.map((i) => i.toStorageJson()).toList();
        storage.setCartJson(jsonEncode(list)).catchError((_) {});
      }
    } catch (_) {
      // Storage unavailable in unit test harness
    }
  }

  void addService(ServiceItem service, {int quantity = 1, String? notes}) {
    final existingIndex = state.indexWhere((i) => i.service.id == service.id);
    if (existingIndex >= 0) {
      final existing = state[existingIndex];
      final updated = existing.copyWith(
        quantity: existing.quantity + quantity,
        customNotes: notes ?? existing.customNotes,
      );
      final list = [...state];
      list[existingIndex] = updated;
      state = list;
    } else {
      state = [
        ...state,
        CartItem(service: service, quantity: quantity, customNotes: notes),
      ];
    }
    AppLogger.d('[P0-CART]',
        'CART_ADD: serviceId=${service.id} (${service.title}), quantityAdded=$quantity, cartLength=${state.length}, items=${state.map((i) => "${i.service.title}:${i.service.id}x${i.quantity}").toList()}');
    _persist();
  }

  void updateQuantity(int serviceId, int newQuantity) {
    if (newQuantity <= 0) {
      removeService(serviceId);
      return;
    }
    state = state.map((item) {
      if (item.service.id == serviceId) {
        return item.copyWith(quantity: newQuantity);
      }
      return item;
    }).toList();
    AppLogger.d('[P0-CART]',
        'CART_UPDATE: serviceId=$serviceId, newQuantity=$newQuantity, cartLength=${state.length}, items=${state.map((i) => "${i.service.title}:${i.service.id}x${i.quantity}").toList()}');
    _persist();
  }

  void removeService(int serviceId) {
    state = state.where((item) => item.service.id != serviceId).toList();
    AppLogger.d('[P0-CART]',
        'CART_REMOVE: serviceId=$serviceId, cartLength=${state.length}, items=${state.map((i) => "${i.service.title}:${i.service.id}").toList()}');
    _persist();
  }

  void clearCart() {
    AppLogger.d('[P0-CART]', 'CART_CLEAR triggered!');
    state = const [];
    _persist();
  }
}

// ── Providers ─────────────────────────────────────────────────────────────────
final cartProvider = NotifierProvider<CartNotifier, List<CartItem>>(
  CartNotifier.new,
);

/// Type of cart action waiting for user authentication.
enum PendingCartActionType {
  addToCart,
  buy,
}

/// Information about a cart action attempted while logged out.
class PendingCartAction {
  const PendingCartAction({
    required this.service,
    required this.actionType,
    this.quantity = 1,
    this.notes,
    this.returnPath,
  });

  final ServiceItem service;
  final PendingCartActionType actionType;
  final int quantity;
  final String? notes;
  final String? returnPath;
}

class PendingActionNotifier extends Notifier<PendingCartAction?> {
  @override
  PendingCartAction? build() => null;

  void setAction(PendingCartAction action) {
    state = action;
  }

  void clear() {
    state = null;
  }
}

final pendingActionProvider =
    NotifierProvider<PendingActionNotifier, PendingCartAction?>(
  PendingActionNotifier.new,
);

/// Helper provider checking if the active user is fully authenticated.
final isUserAuthenticatedProvider = Provider<bool>((ref) {
  final user = ref.watch(currentUserProvider);
  if (user != null && !user.isGuest) return true;
  final authState = ref.watch(authProvider);
  return switch (authState) {
    AuthAuthenticated(:final user) => !user.isGuest,
    _ => false,
  };
});

// ── State for Delivery Tip ──────────────────────────────────────────────────
class DeliveryTipNotifier extends Notifier<Decimal> {
  @override
  Decimal build() => Decimal.zero;

  void setTip(Decimal amount) => state = amount;
}

final deliveryTipProvider =
    NotifierProvider<DeliveryTipNotifier, Decimal>(DeliveryTipNotifier.new);

/// Summary calculation for active cart items supporting both Quick Commerce and Service Bookings.
class CartSummary {
  const CartSummary({
    required this.itemCount,
    required this.subtotal,
    required this.originalTotal,
    required this.totalSavings,
    required this.serviceFee,
    required this.deliveryFee,
    required this.handlingFee,
    required this.smallCartFee,
    required this.tipAmount,
    required this.taxes,
    required this.total,
    required this.advancePayable,
    required this.balancePayable,
    required this.isGroceryCart,
  });

  final int itemCount;
  final Decimal subtotal;
  final Decimal originalTotal;
  final Decimal totalSavings;
  final Decimal serviceFee;
  final Decimal deliveryFee;
  final Decimal handlingFee;
  final Decimal smallCartFee;
  final Decimal tipAmount;
  final Decimal taxes;
  final Decimal total;
  final Decimal advancePayable;
  final Decimal balancePayable;
  final bool isGroceryCart;
}

final cartSummaryProvider = Provider<CartSummary>((ref) {
  final items = ref.watch(cartProvider);
  final tipAmount = ref.watch(deliveryTipProvider);
  // Fixed 2026-10-01 per explicit request ("The Tax fixing Platform fee
  // and free delivery cost should be fix by the admin not the hard
  // coded... make it dynamic"): every fee below used to be a literal
  // Decimal.parse(...) constant. Now read from the admin-configurable
  // PricingConfig (see features/pricing/), which starts with these exact
  // same values as a fallback and silently swaps in the real admin-set
  // ones once fetched — so this never regresses existing behavior, it
  // just stops requiring an app release to change a price.
  final pricing = ref.watch(pricingConfigProvider);

  int count = 0;
  Decimal subtotal = Decimal.zero;
  Decimal originalTotal = Decimal.zero;

  for (final item in items) {
    count += item.quantity;
    subtotal += item.totalPrice;
    final itemMrp = item.service.mrp;
    originalTotal += itemMrp * Decimal.fromInt(item.quantity);
  }

  final totalSavings = originalTotal > subtotal ? originalTotal - subtotal : Decimal.zero;

  // Bug found (reported by a customer: Grand Total jumped from the
  // itemized ₹83 to ₹126.15 with no matching line item in "Bill Details" --
  // Delivery charge and Handling & packaging both correctly showed ₹0/FREE,
  // but nothing accounted for the remaining ~₹43): this used to check only
  // `service.flowType == CatalogFlowType.grocery`, which is a pure
  // category-name/slug keyword match and unreliable whenever a ServiceItem
  // is rebuilt from data that omits category info (the exact failure mode
  // already fixed for the Home screen's "Book Again" tiles). When this
  // flipped to `false` for a genuine grocery item, the branch below fell
  // through to the home-service fee formula (platform fee + GST) instead of
  // delivery/handling/small-cart fees, and that extra amount was folded
  // straight into `total` with no corresponding row in the UI at all.
  // ServiceItem.isGroceryFlow adds the same vegetable-category and
  // marketplace/grocery-hub id-offset fallbacks already proven for Book
  // Again, so this can't silently charge a grocery cart as if it were a
  // service booking again.
  final isGrocery =
      items.isNotEmpty && items.any((i) => i.service.isGroceryFlow);

  if (count == 0) {
    return CartSummary(
      itemCount: 0,
      subtotal: Decimal.zero,
      originalTotal: Decimal.zero,
      totalSavings: Decimal.zero,
      serviceFee: Decimal.zero,
      deliveryFee: Decimal.zero,
      handlingFee: Decimal.zero,
      smallCartFee: Decimal.zero,
      tipAmount: Decimal.zero,
      taxes: Decimal.zero,
      total: Decimal.zero,
      advancePayable: Decimal.zero,
      balancePayable: Decimal.zero,
      isGroceryCart: false,
    );
  }

  if (isGrocery) {
    // ── Quick Commerce Grocery Fee Rules (admin-configurable, Settings > Pricing) ──
    // Delivery fee: FREE if subtotal >= pricing.freeDeliveryThreshold
    final deliveryFee = subtotal >= pricing.freeDeliveryThreshold
        ? Decimal.zero
        : pricing.deliveryFee;

    // Handling and packaging fee
    final handlingFee = pricing.handlingFee;

    // Small cart fee, charged below pricing.smallCartThreshold
    final smallCartFee =
        subtotal < pricing.smallCartThreshold ? pricing.smallCartFee : Decimal.zero;

    final total = subtotal + deliveryFee + handlingFee + smallCartFee + tipAmount;

    // Full 100% settlement for groceries (no technician advance split)
    return CartSummary(
      itemCount: count,
      subtotal: subtotal,
      originalTotal: originalTotal,
      totalSavings: totalSavings,
      serviceFee: Decimal.zero,
      deliveryFee: deliveryFee,
      handlingFee: handlingFee,
      smallCartFee: smallCartFee,
      tipAmount: tipAmount,
      taxes: Decimal.zero,
      total: total,
      advancePayable: total,
      balancePayable: Decimal.zero,
      isGroceryCart: true,
    );
  }

  // ── Home Service & Technician Booking Fee Rules ───────────────────────────
  // Bug found (reported: "there is cost estimation differently by web and
  // mobile... for every package there is gst and platform fee that is
  // making trouble"): this used to apply the SAME flat GST% and platform
  // fee -- the admin's Settings > Pricing > "Home Services" page -- to
  // every booking regardless of which package was actually in the cart.
  // But the real backend already supports a different GST/platform fee per
  // package (Package.gst_rate / Package.platform_fee, admin-set per package
  // in the Service Catalog, already returned on every catalog response —
  // see ServiceItem.gstRate/platformFee), and the web app's own booking
  // flow (frontend/src/ui/pages/BookingPage.jsx) has always priced bookings
  // that way: summing each item's own gst_rate against its own line total,
  // and taking the HIGHEST platform_fee across the cart -- defaulting to
  // 18% / ₹29 for any package that doesn't set its own. Web never actually
  // reads the admin Pricing page's flat Home Services values at all, so
  // this app silently charged a different total than the website for the
  // exact same package. Mirroring web's real formula (not the unused admin
  // page) is what makes the two uniform.
  const fallbackGstRate = 18.0;
  final fallbackPlatformFee = Decimal.fromInt(29);
  final taxes = items.fold<Decimal>(Decimal.zero, (sum, item) {
    final rate = Decimal.parse((item.service.gstRate ?? fallbackGstRate).toString());
    return sum + ((item.totalPrice * rate) / Decimal.fromInt(100)).toDecimal();
  });
  final serviceFee = items
      .map((item) => item.service.platformFee ?? fallbackPlatformFee)
      .reduce((a, b) => a > b ? a : b);
  final total = subtotal + serviceFee + taxes;

  // Advance deposit: pricing.minAdvancePercent of total, or the configured
  // minimum, whichever is higher
  final rawAdvance =
      ((total * pricing.minAdvancePercent) / Decimal.fromInt(100)).toDecimal();
  final minAdvance = pricing.minAdvanceAmount;
  final advancePayable = total < minAdvance
      ? total
      : (rawAdvance < minAdvance ? minAdvance : rawAdvance);

  final balancePayable = total - advancePayable;

  return CartSummary(
    itemCount: count,
    subtotal: subtotal,
    originalTotal: originalTotal,
    totalSavings: totalSavings,
    serviceFee: serviceFee,
    deliveryFee: Decimal.zero,
    handlingFee: Decimal.zero,
    smallCartFee: Decimal.zero,
    tipAmount: Decimal.zero,
    taxes: taxes,
    total: total,
    advancePayable: advancePayable,
    balancePayable: balancePayable,
    isGroceryCart: false,
  );
});
