import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/api_error.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/response_normalizer.dart';

/// Why a customer returns something - the same five reasons the web offers.
enum ReturnReason {
  damaged('DAMAGED', 'Damaged / defective'),
  wrongItem('WRONG_ITEM', 'Wrong item delivered'),
  notAsDescribed('NOT_AS_DESCRIBED', 'Not as described'),
  quality('QUALITY_ISSUE', 'Quality issue / stale'),
  other('OTHER', 'Other reason');

  const ReturnReason(this.code, this.label);
  final String code;
  final String label;
}

/// How far a return request has got.
enum ReturnStage { requested, approved, pickedUp, refunded, rejected, cancelled }

ReturnStage returnStageFrom(String? status) => switch ((status ?? '').toUpperCase()) {
      'APPROVED' => ReturnStage.approved,
      'PICKED_UP' => ReturnStage.pickedUp,
      'REFUNDED' => ReturnStage.refunded,
      'REJECTED' => ReturnStage.rejected,
      'CANCELLED' => ReturnStage.cancelled,
      _ => ReturnStage.requested,
    };

class ReturnRequest {
  const ReturnRequest({
    required this.returnNumber,
    required this.stage,
    required this.statusLabel,
    required this.reasonLabel,
    required this.refundAmount,
    required this.refundStatus,
    this.rejectionReason = '',
    this.sellerNotes = '',
    this.createdAt,
  });

  final String returnNumber;
  final ReturnStage stage;
  final String statusLabel;
  final String reasonLabel;
  final double refundAmount;

  /// NOT_APPLICABLE | PENDING | REFUNDED | MANUAL_REVIEW | FAILED
  final String refundStatus;
  final String rejectionReason;
  final String sellerNotes;
  final DateTime? createdAt;

  bool get isOpen => stage == ReturnStage.requested || stage == ReturnStage.approved || stage == ReturnStage.pickedUp;

  /// What the customer should be told about the money.
  String get refundNote => switch (refundStatus.toUpperCase()) {
        'REFUNDED' => 'Refunded',
        'MANUAL_REVIEW' => 'Refund will be adjusted by our team',
        'FAILED' => 'Refund needs attention - our team will contact you',
        'NOT_APPLICABLE' => '',
        _ => stage == ReturnStage.rejected || stage == ReturnStage.cancelled ? '' : 'Refund pending',
      };

  static ReturnRequest? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final number = (raw['return_number'] ?? raw['request_number'] ?? '').toString();
    if (number.isEmpty) return null;
    return ReturnRequest(
      returnNumber: number,
      stage: returnStageFrom(raw['status']?.toString()),
      statusLabel: (raw['status_label'] ?? '').toString(),
      reasonLabel: (raw['reason_label'] ?? raw['reason'] ?? '').toString(),
      refundAmount: double.tryParse(raw['refund_amount']?.toString() ?? '') ?? 0,
      refundStatus: (raw['refund_status'] ?? '').toString(),
      rejectionReason: (raw['rejection_reason'] ?? '').toString(),
      sellerNotes: (raw['seller_notes'] ?? '').toString(),
      createdAt: DateTime.tryParse((raw['created_at'] ?? raw['requested_at'] ?? '').toString())?.toLocal(),
    );
  }
}

/// One line to return: an order item and how many of it.
class ReturnLine {
  const ReturnLine(this.orderItemId, this.quantity);
  final int orderItemId;
  final int quantity;
}

class OrderReturnsRepository {
  OrderReturnsRepository({required this.api});
  final ApiClient api;

  /// `POST /api/orders/marketplace/<n>/returns/`. [sellerLineId] is only needed when the order has several sellers.
  Future<Result<ReturnRequest>> create(
    String orderNumber, {
    required List<ReturnLine> lines,
    required ReturnReason reason,
    String notes = '',
    int? sellerLineId,
  }) async {
    if (lines.isEmpty) return const Failure(ValidationError('Please select at least one item to return.'));
    try {
      final response = await api.post('/orders/marketplace/$orderNumber/returns/', data: {
        'items': [
          for (final l in lines) {'order_item_id': l.orderItemId, 'quantity': l.quantity, 'reason': reason.code},
        ],
        'reason': reason.code,
        'customer_notes': notes.trim(),
        'seller_line_id': sellerLineId,
        'resolution_type': 'REFUND_ONLY',
      });
      return ResponseNormalizer.extract(response, (data) => ReturnRequest.tryParse(data) ?? (throw const ParseError()));
    } on Exception catch (e) {
      return Failure(_err(e));
    }
  }

  /// `GET /api/orders/marketplace/<n>/returns/` - newest first.
  Future<Result<List<ReturnRequest>>> forOrder(String orderNumber) async {
    try {
      final response = await api.get('/orders/marketplace/$orderNumber/returns/');
      return ResponseNormalizer.extract(response, (data) {
        final list = data is List ? data : const [];
        return [for (final r in list) ?ReturnRequest.tryParse(r)];
      });
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

final orderReturnsRepositoryProvider = Provider<OrderReturnsRepository>((ref) => OrderReturnsRepository(api: ref.watch(apiClientProvider)));

final orderReturnsProvider = FutureProvider.autoDispose.family<List<ReturnRequest>, String>((ref, number) async {
  final r = await ref.watch(orderReturnsRepositoryProvider).forOrder(number);
  return switch (r) {
    Success(:final data) => data,
    Failure() => const <ReturnRequest>[],
  };
});
