import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/api_error.dart';
import '../../../core/network/api_client.dart';

/// One availability alert the customer asked for ("tell me if this date opens up").
class WaitlistEntry {
  const WaitlistEntry({
    required this.id,
    required this.serviceId,
    required this.serviceName,
    required this.date,
    required this.status,
    this.claimExpiresAt,
  });

  final int id;
  final int serviceId;
  final String serviceName;

  /// YYYY-MM-DD
  final String date;

  /// WAITING | NOTIFIED | BOOKED | EXPIRED | CANCELLED
  final String status;
  final DateTime? claimExpiresAt;

  bool get isActive => status == 'WAITING' || status == 'NOTIFIED';

  factory WaitlistEntry.fromJson(Map<String, dynamic> j) => WaitlistEntry(
        id: int.tryParse('${j['id']}') ?? 0,
        serviceId: int.tryParse('${j['service_id']}') ?? 0,
        serviceName: (j['service_name'] ?? '').toString(),
        date: (j['date'] ?? '').toString(),
        status: (j['status'] ?? '').toString().toUpperCase(),
        claimExpiresAt: j['claim_expires_at'] == null
            ? null
            : DateTime.tryParse(j['claim_expires_at'].toString())?.toLocal(),
      );
}

/// Availability alerts for fully-booked future dates (backend `service_requests`):
///   POST   /api/services/<service>/capacity-waitlist/  {date, address, email_opt_in, in_app_opt_in}
///   GET    /api/customer/capacity-waitlist/
///   DELETE /api/customer/capacity-waitlist/<id>/
/// All need a signed-in customer. When a place opens, the backend adds an inbox
/// notification (with a claim link) and optionally emails.
class CapacityWaitlistRepository {
  CapacityWaitlistRepository({required this.api});

  final ApiClient api;

  Future<Result<({WaitlistEntry entry, String message})>> join({
    required String service,
    required String date,
    required String address,
    bool email = true,
  }) async {
    try {
      final response = await api.post(
        '/services/${Uri.encodeComponent(service)}/capacity-waitlist/',
        data: {
          'date': date,
          'address': address,
          'email_opt_in': email,
          'in_app_opt_in': true,
        },
      );
      final body = response.data;
      if (body is! Map || body['data'] is! Map) {
        return Failure(UnknownError('Unexpected response'));
      }
      return Success((
        entry: WaitlistEntry.fromJson(Map<String, dynamic>.from(body['data'] as Map)),
        message: (body['message'] ?? 'We will let you know if an appointment becomes available.').toString(),
      ));
    } on Exception catch (e) {
      return Failure(_toError(e));
    }
  }

  Future<Result<List<WaitlistEntry>>> list() async {
    try {
      final response = await api.get('/customer/capacity-waitlist/');
      final body = response.data;
      final raw = body is Map ? body['data'] : null;
      return Success(raw is List
          ? raw.whereType<Map>().map((m) => WaitlistEntry.fromJson(Map<String, dynamic>.from(m))).toList()
          : <WaitlistEntry>[]);
    } on Exception catch (e) {
      return Failure(_toError(e));
    }
  }

  Future<Result<void>> cancel(int id) async {
    try {
      await api.delete('/customer/capacity-waitlist/$id/');
      return const Success(null);
    } on Exception catch (e) {
      return Failure(_toError(e));
    }
  }

  ApiError _toError(Object e) {
    if (e is ApiError) return e;
    if (e is DioException && e.error is ApiError) return e.error! as ApiError;
    return UnknownError(e.toString());
  }
}

final capacityWaitlistRepositoryProvider = Provider<CapacityWaitlistRepository>((ref) {
  return CapacityWaitlistRepository(api: ref.watch(apiClientProvider));
});

/// The signed-in customer's availability alerts.
final myWaitlistProvider = FutureProvider.autoDispose<List<WaitlistEntry>>((ref) async {
  final result = await ref.watch(capacityWaitlistRepositoryProvider).list();
  return switch (result) {
    Success(:final data) => data,
    Failure() => const <WaitlistEntry>[],
  };
});
