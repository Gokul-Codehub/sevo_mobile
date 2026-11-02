import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/api_error.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/response_normalizer.dart';

enum PaymentKind { service, grocery }

/// Customer-facing outcome of a payment (the server already normalised it).
enum PaymentOutcome { paid, pending, failed, refunded }

class PaymentRecord {
  const PaymentRecord({
    required this.id,
    required this.kind,
    required this.title,
    required this.reference,
    required this.amount,
    required this.outcome,
    required this.statusLabel,
    required this.method,
    required this.createdAt,
    this.bookingId,
  });

  final String id;
  final PaymentKind kind;
  final String title;
  final String reference; // booking id like SEVO-123 (services)
  final double amount;
  final PaymentOutcome outcome;
  final String statusLabel;
  final String method; // Online / Cash
  final DateTime? createdAt;
  final int? bookingId;

  static PaymentRecord? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id']?.toString() ?? '';
    final amount = double.tryParse(raw['amount']?.toString() ?? '');
    if (id.isEmpty || amount == null) return null;
    return PaymentRecord(
      id: id,
      kind: raw['kind'] == 'grocery' ? PaymentKind.grocery : PaymentKind.service,
      title: (raw['title'] ?? 'Payment').toString(),
      reference: (raw['reference'] ?? '').toString(),
      amount: amount,
      outcome: switch (raw['status']) {
        'paid' => PaymentOutcome.paid,
        'failed' => PaymentOutcome.failed,
        'refunded' => PaymentOutcome.refunded,
        _ => PaymentOutcome.pending,
      },
      statusLabel: (raw['status_label'] ?? '').toString(),
      method: (raw['method'] ?? '').toString(),
      createdAt: DateTime.tryParse((raw['created_at'] ?? '').toString())?.toLocal(),
      bookingId: int.tryParse(raw['booking_id']?.toString() ?? ''),
    );
  }
}

class PaymentHistory {
  const PaymentHistory({required this.records, required this.totalPaid, required this.totalRefunded});
  final List<PaymentRecord> records;
  final double totalPaid;
  final double totalRefunded;
}

/// Where a refund is in its journey.
enum RefundStage { requested, underReview, needsInfo, approved, processing, refunded, rejected }

class RefundRecord {
  const RefundRecord({
    required this.id,
    required this.refundId,
    required this.serviceName,
    required this.bookingRef,
    required this.paidAmount,
    required this.requestedAmount,
    required this.approvedAmount,
    required this.reason,
    required this.stage,
    required this.statusLabel,
    required this.createdAt,
    required this.updatedAt,
    this.bookingId,
  });

  final int id;
  final String refundId;
  final String serviceName;
  final String bookingRef;
  final int? bookingId;
  final double paidAmount;
  final double requestedAmount;
  final double? approvedAmount;
  final String reason;
  final RefundStage stage;
  final String statusLabel;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  /// The amount the customer will get / got: the approved amount once approved, otherwise what was asked for.
  double get amount => approvedAmount ?? requestedAmount;

  static RefundStage stageFor(String status) => switch (status.toUpperCase()) {
        'PENDING' => RefundStage.underReview,
        'INFO_REQUESTED' => RefundStage.needsInfo,
        'APPROVED_FULL' || 'APPROVED_PARTIAL' => RefundStage.approved,
        'SENT_TO_FINANCE' => RefundStage.processing,
        'COMPLETED' => RefundStage.refunded,
        'REJECTED' => RefundStage.rejected,
        _ => RefundStage.requested,
      };

  static RefundRecord? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final id = int.tryParse(raw['id']?.toString() ?? '');
    if (id == null) return null;
    final status = (raw['status'] ?? '').toString();
    return RefundRecord(
      id: id,
      refundId: (raw['refund_id'] ?? '').toString(),
      serviceName: (raw['service_name'] ?? 'Booking').toString(),
      bookingRef: (raw['booking_request_id'] ?? '').toString(),
      bookingId: int.tryParse(raw['booking_id']?.toString() ?? ''),
      paidAmount: double.tryParse(raw['paid_amount']?.toString() ?? '') ?? 0,
      requestedAmount: double.tryParse(raw['requested_amount']?.toString() ?? '') ?? 0,
      approvedAmount: double.tryParse(raw['approved_amount']?.toString() ?? ''),
      reason: (raw['reason'] ?? '').toString(),
      stage: stageFor(status),
      statusLabel: (raw['status_display'] ?? status).toString(),
      createdAt: DateTime.tryParse((raw['created_at'] ?? '').toString())?.toLocal(),
      updatedAt: DateTime.tryParse((raw['updated_at'] ?? '').toString())?.toLocal(),
    );
  }
}

/// `GET /api/booking/payments/` (payment history) and `GET /api/booking/refunds/` (refund requests).
class MyPaymentsRepository {
  MyPaymentsRepository({required this.api});
  final ApiClient api;

  Future<Result<PaymentHistory>> history({String? status}) async {
    try {
      final response = await api.get('/booking/payments/', queryParameters: {if (status != null) 'status': status});
      return ResponseNormalizer.extract(response, (data) {
        final map = data is Map ? data : const {};
        final list = map['results'] is List ? map['results'] as List : const [];
        final summary = map['summary'] is Map ? map['summary'] as Map : const {};
        return PaymentHistory(
          records: [for (final r in list) ?PaymentRecord.tryParse(r)],
          totalPaid: double.tryParse(summary['paid']?.toString() ?? '') ?? 0,
          totalRefunded: double.tryParse(summary['refunded']?.toString() ?? '') ?? 0,
        );
      });
    } on Exception catch (e) {
      return Failure(_err(e));
    }
  }

  Future<Result<List<RefundRecord>>> refunds() async {
    try {
      final response = await api.get('/booking/refunds/');
      return ResponseNormalizer.extract(response, (data) {
        final list = data is List ? data : (data is Map && data['results'] is List ? data['results'] as List : const []);
        return [for (final r in list) ?RefundRecord.tryParse(r)];
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

final myPaymentsRepositoryProvider = Provider<MyPaymentsRepository>((ref) => MyPaymentsRepository(api: ref.watch(apiClientProvider)));

final paymentHistoryProvider = FutureProvider.autoDispose<PaymentHistory>((ref) async {
  final r = await ref.watch(myPaymentsRepositoryProvider).history();
  return switch (r) {
    Success(:final data) => data,
    Failure(:final error) => throw error,
  };
});

final myRefundsProvider = FutureProvider.autoDispose<List<RefundRecord>>((ref) async {
  final r = await ref.watch(myPaymentsRepositoryProvider).refunds();
  return switch (r) {
    Success(:final data) => data,
    Failure(:final error) => throw error,
  };
});
