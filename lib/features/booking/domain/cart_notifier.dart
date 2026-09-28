import 'dart:convert';
import 'package:decimal/decimal.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/storage/secure_storage.dart';
import '../../../core/utils/app_logger.dart';
import '../../auth/domain/auth_models.dart';
import '../../auth/domain/auth_notifier.dart';
import '../../catalog/domain/catalog_models.dart';
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

  final isGrocery =
      items.isNotEmpty && items.any((i) => i.service.flowType == CatalogFlowType.grocery);

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
    // ── Quick Commerce Grocery Fee Rules (matching calservices_web) ──────────
    // Delivery fee: ₹15 (FREE if subtotal >= ₹200)
    final freeDeliveryThreshold = Decimal.parse('200.00');
    final deliveryFee = subtotal >= freeDeliveryThreshold
        ? Decimal.zero
        : Decimal.parse('15.00');

    // Handling and packaging: ₹2
    final handlingFee = Decimal.parse('2.00');

    // Small cart fee: ₹5 if subtotal < ₹100
    final smallCartThreshold = Decimal.parse('100.00');
    final smallCartFee =
        subtotal < smallCartThreshold ? Decimal.parse('5.00') : Decimal.zero;

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
  final serviceFee = Decimal.parse('49.00'); // Standard safety & assurance fee
  final taxes = subtotal * Decimal.parse('0.05'); // 5% GST on home services
  final total = subtotal + serviceFee + taxes;

  // Advance deposit: 20% of total or minimum ₹149
  final rawAdvance = total * Decimal.parse('0.20');
  final minAdvance = Decimal.parse('149.00');
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
