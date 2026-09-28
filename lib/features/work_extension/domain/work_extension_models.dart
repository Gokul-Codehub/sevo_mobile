import 'package:decimal/decimal.dart';
import 'package:equatable/equatable.dart';

import '../../../core/network/response_normalizer.dart';

/// Single item in a work extension proposal.
class WorkExtensionItem extends Equatable {
  const WorkExtensionItem({
    required this.title,
    required this.quantity,
    required this.price,
  });

  final String title;
  final int quantity;
  final Decimal price;

  Decimal get totalPrice => price * Decimal.fromInt(quantity);

  factory WorkExtensionItem.fromJson(Map<String, dynamic> json) {
    return WorkExtensionItem(
      title: (json['title'] ?? json['name'] ?? 'Additional Part/Work').toString(),
      quantity: parseInt(json['quantity'], fallback: 1),
      price: parseMoney(json['price'] ?? json['unit_price'] ?? 0),
    );
  }

  @override
  List<Object?> get props => [title, quantity, price];
}

/// Work extension proposed on-site by technician.
class WorkExtensionProposal extends Equatable {
  const WorkExtensionProposal({
    required this.token,
    required this.bookingId,
    required this.requestId,
    required this.technicianName,
    required this.reason,
    required this.additionalAmount,
    this.items = const [],
    this.status = 'pending', // 'pending' | 'approved' | 'rejected'
  });

  final String token;
  final int bookingId;
  final String requestId;
  final String technicianName;
  final String reason;
  final Decimal additionalAmount;
  final List<WorkExtensionItem> items;
  final String status;

  bool get isPending => status == 'pending';

  factory WorkExtensionProposal.fromJson(Map<String, dynamic> json, String token) {
    final rawItemsObj = json['items'] ?? json['parts'];
    final List<dynamic> rawItems = rawItemsObj is List
        ? rawItemsObj
        : (rawItemsObj is Map && rawItemsObj['results'] is List
            ? rawItemsObj['results'] as List
            : (rawItemsObj is Map ? [rawItemsObj] : const []));
    return WorkExtensionProposal(
      token: token,
      bookingId: parseInt(json['booking_id'] ?? json['id']),
      requestId: (json['request_id'] ?? 'CAL-$token').toString(),
      technicianName: (json['technician_name'] ?? json['technician'] ?? 'Assigned Professional').toString(),
      reason: (json['reason'] ?? json['description'] ?? 'Additional work required to complete the repair safely.').toString(),
      additionalAmount: parseMoney(json['additional_amount'] ?? json['amount'] ?? 0),
      items: rawItems
          .whereType<Map>()
          .map((m) => WorkExtensionItem.fromJson(Map<String, dynamic>.from(m)))
          .toList(),
      status: (json['status'] ?? 'pending').toString().toLowerCase(),
    );
  }

  @override
  List<Object?> get props => [
        token,
        bookingId,
        requestId,
        technicianName,
        reason,
        additionalAmount,
        items,
        status,
      ];
}
