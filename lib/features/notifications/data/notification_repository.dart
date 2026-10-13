import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/api_error.dart';
import '../../../core/network/api_client.dart';
import '../domain/notification_models.dart';

/// The customer's in-app inbox (backend `accounts` app):
///   GET  /api/accounts/notifications/?limit=30   -> {success, data: [...], meta: {unread_count}}
///   POST /api/accounts/notifications/<id>/read/  -> {success}
/// Both are scoped to the signed-in customer by the server.
class NotificationRepository {
  NotificationRepository({required this.api});

  final ApiClient api;

  Future<Result<NotificationPage>> getNotifications({int limit = 50}) async {
    try {
      final response = await api.get(
        '/accounts/notifications/',
        queryParameters: {'limit': limit},
      );
      final body = response.data;
      if (body is! Map) return Failure(UnknownError('Unexpected notifications response'));
      final raw = body['data'];
      final items = raw is List
          ? raw
              .whereType<Map>()
              .map((m) => CustomerNotification.fromJson(Map<String, dynamic>.from(m)))
              .toList()
          : <CustomerNotification>[];
      final meta = body['meta'] is Map ? Map<String, dynamic>.from(body['meta'] as Map) : const {};
      final unread = int.tryParse('${meta['unread_count'] ?? ''}') ??
          items.where((n) => !n.isRead).length;
      return Success(NotificationPage(items: items, unreadCount: unread));
    } on Exception catch (e) {
      return Failure(_toError(e));
    }
  }

  Future<Result<void>> markRead(int id) async {
    try {
      await api.post('/accounts/notifications/$id/read/');
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

final notificationRepositoryProvider = Provider<NotificationRepository>((ref) {
  return NotificationRepository(api: ref.watch(apiClientProvider));
});
