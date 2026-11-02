import 'dart:typed_data';

import 'package:flutter/foundation.dart' show debugPrint;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart' show IconData, Icons;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/api_error.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/response_normalizer.dart';
import '../../booking/domain/booking_models.dart' show CartItem;
import '../../booking/domain/marketplace_cart.dart';
import '../../payment/domain/payment_models.dart' show PaymentOrder;
import 'marketplace_online_payment.dart';

/// The stages of a grocery order, in the order the seller and rider move it through (same five steps as the web
/// order tracker). `cancelled` sits outside the line.
enum OrderStage { confirmed, packing, readyForPickup, outForDelivery, delivered, cancelled }

OrderStage stageFromStatus(String? status) => switch ((status ?? '').toUpperCase()) {
      'PACKING' => OrderStage.packing,
      'READY_FOR_PICKUP' => OrderStage.readyForPickup,
      'OUT_FOR_DELIVERY' => OrderStage.outForDelivery,
      'DELIVERED' => OrderStage.delivered,
      'CANCELLED' => OrderStage.cancelled,
      _ => OrderStage.confirmed,
    };

/// One step of the tracker: its title and the one-line explanation under it.
class StageInfo {
  const StageInfo(this.stage, this.title, this.subtitle, this.icon);
  final OrderStage stage;
  final String title;
  final String subtitle;

  /// Shown in the tracker until the step is done (then it becomes a tick).
  final IconData icon;
}

const List<StageInfo> kOrderStages = [
  StageInfo(OrderStage.confirmed, 'Confirmed', 'Order received by seller', Icons.check_circle_outline),
  StageInfo(OrderStage.packing, 'Seller is packing', 'Items are being packaged', Icons.inventory_2_outlined),
  StageInfo(OrderStage.readyForPickup, 'Ready for pickup', 'Waiting for courier dispatch', Icons.local_shipping_outlined),
  StageInfo(OrderStage.outForDelivery, 'On the way', 'Out for delivery to your doorstep', Icons.delivery_dining_outlined),
  StageInfo(OrderStage.delivered, 'Delivered', 'Successfully delivered', Icons.home_outlined),
];

String stageTitle(OrderStage s) => s == OrderStage.cancelled ? 'Cancelled' : kOrderStages.firstWhere((i) => i.stage == s).title;

double? _d(Object? v) => v == null ? null : double.tryParse(v.toString());
DateTime? _t(Object? v) => v == null ? null : DateTime.tryParse(v.toString())?.toLocal();

class OrderLine {
  const OrderLine({required this.title, required this.quantity, required this.unitPrice, required this.amount, this.image, this.pack = '', this.id, this.sellerId});

  /// The order item's id (needed to return it) and the seller it came from.
  final int? id;
  final int? sellerId;
  final String title;
  final int quantity;
  final double unitPrice;
  final double amount;
  final String? image;
  final String pack;

  static OrderLine? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final title = (raw['product_title'] ?? '').toString();
    if (title.isEmpty) return null;
    final qty = (double.tryParse(raw['quantity']?.toString() ?? '') ?? 1).round();
    final unit = _d(raw['unit_price_snapshot']) ?? 0;
    final img = (raw['product_image'] ?? '').toString();
    return OrderLine(
      id: int.tryParse(raw['id']?.toString() ?? ''),
      sellerId: int.tryParse(raw['seller_id']?.toString() ?? ''),
      title: title,
      quantity: qty,
      unitPrice: unit,
      amount: _d(raw['line_amount']) ?? unit * qty,
      image: img.isEmpty ? null : img,
      pack: (raw['pack_size'] ?? raw['unit'] ?? '').toString(),
    );
  }
}

class OrderEvent {
  const OrderEvent({required this.label, required this.at});
  final String label;
  final DateTime? at;

  static OrderEvent? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final status = (raw['mapped_status'] ?? raw['vendor_status'] ?? raw['event_type'] ?? '').toString();
    if (status.isEmpty) return null;
    final stage = stageFromStatus(status);
    final known = ['CONFIRMED', 'PACKING', 'READY_FOR_PICKUP', 'OUT_FOR_DELIVERY', 'DELIVERED', 'CANCELLED'].contains(status.toUpperCase());
    final label = known ? stageTitle(stage) : status.replaceAll('_', ' ').toLowerCase().replaceFirstMapped(RegExp(r'^.'), (m) => m[0]!.toUpperCase());
    return OrderEvent(label: label, at: _t(raw['occurred_at'] ?? raw['received_at']));
  }
}

/// Where the delivery partner is, once the order is on the way.
class RiderInfo {
  const RiderInfo({this.name = 'Delivery Partner', this.phone, this.etaMinutes, this.distanceKm, this.live = false});
  final String name;
  final String? phone;
  final int? etaMinutes;
  final double? distanceKm;
  final bool live;
}

class GroceryOrder {
  const GroceryOrder({
    required this.orderNumber,
    required this.stage,
    required this.statusLabel,
    required this.total,
    required this.createdAt,
    this.sellerName = '',
    this.warehouseName = '',
    this.slot = '',
    this.deliveryAddress = '',
    this.paymentMethod = '',
    this.paymentStatus = '',
    this.subtotal,
    this.deliveryFee,
    this.deliveryOtp,
    this.items = const [],
    this.events = const [],
    this.sellerLines = const [],
    this.rider,
    this.cancellationPending = false,
    this.canReturn = false,
  });

  final String orderNumber;
  final OrderStage stage;
  final String statusLabel;
  final double total;
  final DateTime? createdAt;
  final String sellerName;
  final String warehouseName;
  final String slot;
  final String deliveryAddress;
  final String paymentMethod;
  final String paymentStatus;
  final double? subtotal;
  final double? deliveryFee;
  final String? deliveryOtp;
  final List<OrderLine> items;
  final List<OrderEvent> events;
  final List<SellerLine> sellerLines;
  final RiderInfo? rider;
  final bool cancellationPending;
  final bool canReturn;

  bool get isActive => stage != OrderStage.delivered && stage != OrderStage.cancelled;

  /// 0..1 along the five tracker steps (a cancelled order shows no progress).
  double get progress => stage == OrderStage.cancelled ? 0 : (stage.index + 1) / kOrderStages.length;

  /// Only until the rider has it. Mirrors the server rule: once out for delivery the order can no longer be cancelled.
  bool get canCancel => !cancellationPending && (stage == OrderStage.confirmed || stage == OrderStage.packing || stage == OrderStage.readyForPickup);

  /// The code to give the rider, shown only while the order is on the way.
  bool get showOtp => stage == OrderStage.outForDelivery && (deliveryOtp ?? '').isNotEmpty;

  bool get isCod => paymentMethod.toUpperCase().contains('COD') || paymentMethod.toUpperCase().contains('CASH');

  static GroceryOrder? tryParse(Object? input) {
    if (input is! Map) return null;
    // The orders list nests most fields under `detail`; the order endpoint has them at the top level.
    final raw = <Object?, Object?>{if (input['detail'] is Map) ...(input['detail'] as Map), ...input};
    final number = (raw['order_number'] ?? '').toString();
    if (number.isEmpty) return null;
    final slotRaw = raw['delivery_slot'];
    final slot = slotRaw is Map ? (slotRaw['label'] ?? slotRaw['name'] ?? '').toString() : (slotRaw ?? '').toString();
    final live = raw['live_tracking'];
    RiderInfo? rider;
    if (live is Map && live['technician'] is Map) {
      final t = live['technician'] as Map;
      rider = RiderInfo(
        name: (t['name'] ?? 'Delivery Partner').toString(),
        phone: (t['phone'] ?? '').toString().isEmpty ? null : t['phone'].toString(),
        etaMinutes: int.tryParse(live['eta_minutes']?.toString() ?? ''),
        distanceKm: _d(live['distance_km']),
        live: live['freshness'] == 'LIVE',
      );
    }
    final lines = raw['seller_lines'];
    return GroceryOrder(
      orderNumber: number,
      stage: stageFromStatus(raw['status']?.toString()),
      statusLabel: (raw['status_label'] ?? '').toString(),
      total: _d(raw['total_amount']) ?? 0,
      createdAt: _t(raw['created_at']),
      sellerName: (raw['seller_name'] ?? '').toString(),
      warehouseName: (raw['warehouse_name'] ?? '').toString(),
      slot: slot,
      deliveryAddress: (raw['delivery_address'] ?? '').toString(),
      paymentMethod: (raw['payment_method'] ?? '').toString(),
      paymentStatus: (raw['payment_status'] ?? '').toString(),
      subtotal: _d(raw['subtotal_amount']),
      deliveryFee: _d(raw['delivery_fee']),
      deliveryOtp: (raw['delivery_otp'] ?? (live is Map ? live['delivery_otp'] : null))?.toString(),
      items: [for (final i in (raw['items'] is List ? raw['items'] as List : const [])) ?OrderLine.tryParse(i)],
      events: [for (final e in (raw['events'] is List ? raw['events'] as List : const [])) ?OrderEvent.tryParse(e)],
      sellerLines: [for (final l in (lines is List ? lines : const [])) ?SellerLine.tryParse(l)],
      rider: rider,
      cancellationPending: raw['cancellation_pending'] == true,
      canReturn: raw['can_return'] == true,
    );
  }
}

/// One seller's part of an order that ships from several sellers.
class SellerLine {
  const SellerLine({required this.sellerName, required this.stage, required this.statusLabel, this.id, this.sellerId});
  final int? id;
  final int? sellerId;
  final String sellerName;
  final OrderStage stage;
  final String statusLabel;

  static SellerLine? tryParse(Object? raw) {
    if (raw is! Map) return null;
    return SellerLine(
      id: int.tryParse(raw['id']?.toString() ?? ''),
      sellerId: int.tryParse(raw['seller_id']?.toString() ?? ''),
      sellerName: (raw['seller_name'] ?? '').toString(),
      stage: stageFromStatus(raw['status']?.toString()),
      statusLabel: (raw['status_label'] ?? '').toString(),
    );
  }
}

/// One statutory document for an order: a tax invoice per seller once delivered, and a credit note if it was reversed.
class OrderInvoice {
  const OrderInvoice({required this.sellerId, required this.sellerName, required this.number, required this.isCreditNote, required this.total});
  final int sellerId;
  final String sellerName;
  final String number;
  final bool isCreditNote;
  final double total;

  static OrderInvoice? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final seller = int.tryParse(raw['seller_id']?.toString() ?? '');
    final number = (raw['invoice_number'] ?? '').toString();
    if (seller == null || number.isEmpty) return null;
    return OrderInvoice(
      sellerId: seller,
      sellerName: (raw['seller_name'] ?? '').toString(),
      number: number,
      isCreditNote: (raw['document_type'] ?? '').toString().toUpperCase().contains('CREDIT'),
      total: double.tryParse(raw['grand_total']?.toString() ?? '') ?? 0,
    );
  }
}

/// Everything the marketplace checkout needs besides the cart (same fields the web store sends).
class MarketplaceCheckout {
  const MarketplaceCheckout({
    required this.address,
    required this.name,
    required this.phone,
    required this.email,
    required this.instant,
    required this.idempotencyKey,
    this.paymentMethod = 'COD',
    this.lat,
    this.lng,
    this.slotId,
    this.slotLabel,
    this.slotDate,
    this.slotStart,
    this.slotEnd,
  });

  final String address;
  final String name;
  final String phone;
  final String email;
  final double? lat;
  final double? lng;

  /// "Instant" delivery (no slot) versus a scheduled Seller Hub slot.
  final bool instant;
  final int? slotId;
  final String? slotLabel;
  final String? slotDate; // yyyy-MM-dd
  final String? slotStart; // HH:mm
  final String? slotEnd;
  final String idempotencyKey;

  /// `COD` (cash on delivery) or `UPI` (online: the server picks the gateway).
  final String paymentMethod;

  static String _iso(String date, String hhmm) => '${date}T${hhmm.length == 5 ? '$hhmm:00' : hhmm}';
  static double? _six(double? v) => v == null ? null : double.parse(v.toStringAsFixed(6));

  Map<String, Object?> toJson() {
    final scheduled = !instant && slotDate != null;
    return {
      'delivery_address': address,
      'customer_name': name,
      'customer_phone': phone,
      'customer_email': email,
      'payment_method': paymentMethod,
      'fulfilment_type': 'DELIVERY',
      'delivery_type': instant ? 'FAST' : 'SLOT',
      'delivery_slot': instant ? 'Immediate' : (slotLabel ?? ''),
      if (scheduled && slotId != null) 'delivery_slot_id': slotId,
      if (scheduled) 'delivery_date': slotDate,
      if (scheduled && slotStart != null) 'delivery_slot_start': _iso(slotDate!, slotStart!),
      if (scheduled && slotEnd != null) 'delivery_slot_end': _iso(slotDate!, slotEnd!),
      if (_six(lat) != null) 'delivery_latitude': _six(lat),
      if (_six(lng) != null) 'delivery_longitude': _six(lng),
    };
  }
}

class GroceryOrdersRepository {
  GroceryOrdersRepository({required this.api});
  final ApiClient api;

  /// Places a grocery order the way the web store does: put the cart on the server (`/carts/marketplace/`), then
  /// `POST /orders/marketplace/checkout/`. The server creates the order, reserves Seller Hub stock and hands it to
  /// the seller to pack. Returns the order(s) created (one per fulfilment group).
  Future<Result<List<GroceryOrder>>> place(List<CartItem> items, MarketplaceCheckout checkout) async {
    final entries = marketplaceCartEntries(items);
    if (entries.isEmpty) return const Failure(ValidationError('Your cart has nothing that can be ordered.'));
    try {
      await _putCartOnServer(entries);
      final response = await _step(
        'checkout',
        () => api.post(
          '/orders/marketplace/checkout/',
          data: checkout.toJson(),
          options: Options(headers: {'Idempotency-Key': checkout.idempotencyKey}),
        ),
      );
      return ResponseNormalizer.extract(response, (data) {
        final m = data is Map ? data : const {};
        final all = m['orders'] is List && (m['orders'] as List).isNotEmpty ? m['orders'] as List : [m];
        final orders = [for (final o in all) ?GroceryOrder.tryParse(o)];
        if (orders.isEmpty) throw const ParseError();
        return orders;
      });
    } on Exception catch (e) {
      return Failure(_err(e));
    }
  }

  /// `GET /api/orders/my/` - every order family merged; only the grocery (marketplace) ones are kept.
  Future<Result<List<GroceryOrder>>> myOrders() async {
    try {
      final response = await api.get('/orders/my/');
      return ResponseNormalizer.extract(response, (data) {
        final list = data is List ? data : (data is Map && data['results'] is List ? data['results'] as List : const []);
        return [
          for (final o in list)
            if (o is Map && o['order_type'] == 'marketplace') ?GroceryOrder.tryParse(o),
        ];
      });
    } on Exception catch (e) {
      return Failure(_err(e));
    }
  }

  /// `GET /api/orders/marketplace/<n>/` - the order with its items, timeline events, OTP and live rider block.
  Future<Result<GroceryOrder>> detail(String orderNumber) async {
    try {
      final response = await api.get('/orders/marketplace/$orderNumber/');
      return ResponseNormalizer.extract(response, (data) => GroceryOrder.tryParse(data) ?? (throw const UnknownError()));
    } on Exception catch (e) {
      return Failure(_err(e));
    }
  }

  /// Runs one call of the order sequence. A server-side failure (5xx) is turned into a message that says which step
  /// failed and what the server answered, because "our server had a problem" gives nobody anything to act on.
  Future<T> _step<T>(String step, Future<T> Function() call) async {
    try {
      return await call();
    } on DioException catch (e) {
      final code = e.response?.statusCode;
      final body = e.response?.data;
      debugPrint('[ORDER] step=$step status=$code body=$body');
      if (code != null && code >= 500) {
        final m = body is Map ? body : const {};
        final said = (m['message'] ?? m['error'] ?? m['detail'] ?? '').toString().trim();
        final tag = (m['code'] ?? '').toString().trim();
        throw ValidationError(
          'We could not place your order right now'
          '${said.isEmpty ? '' : ': $said'}'
          '. Please try again, or contact support and quote: $step $code${tag.isEmpty ? '' : ' $tag'}.',
          code: tag.isEmpty ? null : tag,
        );
      }
      rethrow;
    }
  }

  /// Start from an empty server cart so the order is exactly what the customer sees, not what an earlier attempt (or
  /// the website) left behind.
  Future<void> _putCartOnServer(List<MarketplaceCartEntry> entries) async {
    await _step('cart-clear', () => api.post('/carts/marketplace/clear/', data: <String, dynamic>{}));
    for (final e in entries) {
      await _step('cart-add', () => api.post('/carts/marketplace/items/', data: e.toJson()));
    }
  }

  /// Pays online, the way the web store does: the cart goes to the server, the server creates the payment with the
  /// gateway it is configured for, the customer pays in that gateway, and the server verifies and only then creates
  /// the order. If anything fails before verification, no order exists and the cart is untouched.
  Future<Result<List<GroceryOrder>>> payOnline(
    List<CartItem> items,
    MarketplaceCheckout checkout, {
    required PaymentLauncher launcher,
  }) async {
    final entries = marketplaceCartEntries(items);
    if (entries.isEmpty) return const Failure(ValidationError('Your cart has nothing that can be ordered.'));
    PaymentOrder order;
    try {
      await _putCartOnServer(entries);
      final response = await _step('payment-start', () => api.post('/orders/marketplace/checkout/initiate-payment/', data: checkout.toJson()));
      final init = ResponseNormalizer.extract(response, (data) => PaymentOrder.fromJson(data is Map ? Map<String, dynamic>.from(data) : const {}));
      switch (init) {
        case Success(:final data):
          order = data;
        case Failure(:final error):
          return Failure(error);
      }
    } on Exception catch (e) {
      return Failure(_err(e));
    }
    if (order.orderId.isEmpty) return const Failure(ParseError());

    final done = await launcher.launch(order, name: checkout.name, email: checkout.email, phone: checkout.phone);
    if (!done.askServer) {
      return Failure(ValidationError(done.message ?? 'Payment was not completed. You have not been charged.'));
    }
    try {
      final response = await api.post('/orders/marketplace/checkout/verify-payment/', data: {
        'order_id': order.orderId,
        'transaction_id': done.paymentId,
        'signature': done.signature,
      });
      return ResponseNormalizer.extract(response, (data) {
        final m = data is Map ? data : const {};
        final all = m['orders'] is List && (m['orders'] as List).isNotEmpty ? m['orders'] as List : [m];
        final orders = [for (final o in all) ?GroceryOrder.tryParse(o)];
        if (orders.isEmpty) throw const ParseError();
        return orders;
      });
    } on Exception catch (e) {
      final err = _err(e);
      // The customer may have paid: the gateway also tells the server directly, so the order can still appear.
      return Failure(err is NetworkError
          ? const ValidationError('We could not confirm your payment yet. If money was deducted, your order will appear in My Bookings shortly.')
          : err);
    }
  }

  /// `GET /api/orders/marketplace/<n>/invoices/` - the invoices / credit notes issued so far (none before delivery).
  Future<Result<List<OrderInvoice>>> invoices(String orderNumber) async {
    try {
      final response = await api.get('/orders/marketplace/$orderNumber/invoices/');
      return ResponseNormalizer.extract(response, (data) {
        final list = data is List ? data : (data is Map && data['invoices'] is List ? data['invoices'] as List : const []);
        return [for (final i in list) ?OrderInvoice.tryParse(i)];
      });
    } on Exception catch (e) {
      return Failure(_err(e));
    }
  }

  /// `GET /api/orders/marketplace/<n>/invoice/<seller>/` - the invoice as a PDF.
  Future<Result<Uint8List>> invoicePdf(String orderNumber, int sellerId) async {
    try {
      final response = await api.get<List<int>>(
        '/orders/marketplace/$orderNumber/invoice/$sellerId/',
        options: Options(responseType: ResponseType.bytes),
      );
      final data = response.data;
      if (data == null || data.isEmpty) return const Failure(ValidationError('The invoice is not available yet.'));
      return Success(Uint8List.fromList(data));
    } on DioException catch (e) {
      // A refusal (e.g. not delivered yet) comes back as a normal JSON error; show its message.
      return Failure(e.error is ApiError ? e.error! as ApiError : const ValidationError('The invoice is not available yet.'));
    } on Exception catch (e) {
      return Failure(_err(e));
    }
  }

  /// `POST /api/orders/marketplace/<n>/cancel/`.
  Future<Result<void>> cancel(String orderNumber, {String reason = 'Customer cancelled order'}) async {
    try {
      final response = await api.post('/orders/marketplace/$orderNumber/cancel/', data: {'cancellation_reason': reason});
      return ResponseNormalizer.extract(response, (_) {});
    } on Exception catch (e) {
      return Failure(_err(e));
    }
  }

  ApiError _err(Object e) {
    if (e is ApiError) return e;
    if (e is DioException && e.error is ApiError) return e.error! as ApiError;
    return const NetworkError();
  }
}

final groceryOrdersRepositoryProvider = Provider<GroceryOrdersRepository>((ref) => GroceryOrdersRepository(api: ref.watch(apiClientProvider)));

final groceryOrdersProvider = FutureProvider.autoDispose<List<GroceryOrder>>((ref) async {
  final r = await ref.watch(groceryOrdersRepositoryProvider).myOrders();
  return switch (r) {
    Success(:final data) => data,
    Failure(:final error) => throw error,
  };
});

final groceryInvoicesProvider = FutureProvider.autoDispose.family<List<OrderInvoice>, String>((ref, number) async {
  final r = await ref.watch(groceryOrdersRepositoryProvider).invoices(number);
  return switch (r) {
    Success(:final data) => data,
    Failure() => const <OrderInvoice>[], // no invoices (yet) is not an error worth showing
  };
});

final groceryOrderProvider = FutureProvider.autoDispose.family<GroceryOrder, String>((ref, number) async {
  final r = await ref.watch(groceryOrdersRepositoryProvider).detail(number);
  return switch (r) {
    Success(:final data) => data,
    Failure(:final error) => throw error,
  };
});
