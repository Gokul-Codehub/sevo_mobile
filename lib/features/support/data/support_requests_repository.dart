import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/errors/api_error.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/response_normalizer.dart';

/// What a support request is about: label shown to the customer -> server category.
const Map<String, ({String label, String hint, String category})> kSupportTopics = {
  'booking': (label: 'Problem with a booking', hint: 'Late technician, poor work, incomplete job...', category: 'POOR_SERVICE'),
  'payment': (label: 'Payment problem', hint: 'Charged twice, wrong amount, payment failed...', category: 'PAYMENT_ISSUE'),
  'refund': (label: 'Refund', hint: 'Where is my refund? Refund not received...', category: 'REFUND_ISSUE'),
  'goods_damaged': (label: 'Goods damaged', hint: 'Something was damaged during transport or moving', category: 'GOODS_DAMAGED'),
  'goods_lost': (label: 'Goods lost or missing', hint: 'Something did not arrive', category: 'GOODS_LOST'),
  'behaviour': (label: 'Professional behaviour', hint: 'Rude behaviour or safety concern', category: 'TECHNICIAN_BEHAVIOUR'),
  'other': (label: 'Something else', hint: 'Anything not listed here', category: 'OTHER'),
};

enum TicketStage { open, inProgress, waitingOnYou, resolved, closed }

class SupportMessage {
  const SupportMessage({required this.id, required this.fromCustomer, required this.text, required this.at});
  final int id;
  final bool fromCustomer;
  final String text;
  final DateTime? at;

  static SupportMessage? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final id = int.tryParse(raw['id']?.toString() ?? '');
    final text = (raw['message'] ?? '').toString();
    if (id == null || text.isEmpty) return null;
    return SupportMessage(
      id: id,
      fromCustomer: (raw['persona'] ?? raw['sender_persona'] ?? '').toString().toUpperCase() == 'CUSTOMER',
      text: text,
      at: DateTime.tryParse((raw['created_at'] ?? '').toString())?.toLocal(),
    );
  }
}

class SupportRequest {
  const SupportRequest({
    required this.id,
    required this.number,
    required this.category,
    required this.categoryLabel,
    required this.description,
    required this.status,
    required this.statusLabel,
    required this.createdAt,
    required this.updatedAt,
    this.bookingId,
    this.bookingRef,
    this.messages = const [],
    this.timeline = const [],
    this.attachments = const [],
    this.canReopen = false,
    this.canEscalate = false,
    this.escalated = false,
  });

  final int id;
  final String number;
  final String category;
  final String categoryLabel;
  final String description;
  final String status;
  final String statusLabel;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final int? bookingId;
  final String? bookingRef;
  final List<SupportMessage> messages;
  final List<({String label, DateTime? at})> timeline;
  final List<String> attachments;
  final bool canReopen;
  final bool canEscalate;
  final bool escalated;

  TicketStage get stage => switch (status.toUpperCase()) {
        'OPEN' => TicketStage.open,
        'WAITING_CUSTOMER' => TicketStage.waitingOnYou,
        'RESOLVED' => TicketStage.resolved,
        'CLOSED' => TicketStage.closed,
        _ => TicketStage.inProgress,
      };

  bool get isActive => stage != TicketStage.resolved && stage != TicketStage.closed;

  static SupportRequest? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final id = int.tryParse(raw['id']?.toString() ?? '');
    if (id == null) return null;
    final status = (raw['status'] ?? '').toString();
    return SupportRequest(
      id: id,
      number: (raw['complaint_number'] ?? 'Request #$id').toString(),
      category: (raw['category'] ?? '').toString(),
      categoryLabel: (raw['category_display'] ?? raw['category'] ?? 'Support request').toString(),
      description: (raw['description'] ?? '').toString(),
      status: status,
      statusLabel: (raw['status_display'] ?? status).toString(),
      createdAt: DateTime.tryParse((raw['created_at'] ?? '').toString())?.toLocal(),
      updatedAt: DateTime.tryParse((raw['updated_at'] ?? '').toString())?.toLocal(),
      bookingId: int.tryParse(raw['booking_id']?.toString() ?? ''),
      bookingRef: raw['booking_request_id']?.toString(),
      messages: raw['messages'] is List ? [for (final m in raw['messages'] as List) ?SupportMessage.tryParse(m)] : const [],
      timeline: raw['timeline'] is List
          ? [
              for (final t in raw['timeline'] as List)
                if (t is Map) (label: (t['status_display'] ?? '').toString(), at: DateTime.tryParse((t['at'] ?? '').toString())?.toLocal()),
            ]
          : const [],
      attachments: raw['attachments'] is List
          ? [
              for (final a in raw['attachments'] as List)
                if (a is Map && (a['url'] ?? '').toString().startsWith('http')) a['url'].toString(),
            ]
          : const [],
      canReopen: raw['can_reopen'] == true,
      canEscalate: raw['can_escalate'] == true,
      escalated: raw['escalation_requested_at'] != null,
    );
  }
}

/// `/booking/complaints/...` - the customer's support requests.
class SupportRequestsRepository {
  SupportRequestsRepository({required this.api});
  final ApiClient api;

  Future<Result<List<SupportRequest>>> list() => _run(() async {
        final r = await api.get('/booking/complaints/');
        return ResponseNormalizer.extract(r, (d) => [for (final x in (d is List ? d : const [])) ?SupportRequest.tryParse(x)]);
      });

  Future<Result<SupportRequest>> detail(int id) => _run(() async {
        final r = await api.get('/booking/complaints/$id/');
        return ResponseNormalizer.extract(r, (d) => SupportRequest.tryParse(d) ?? (throw const ParseError('Unexpected response.')));
      });

  Future<Result<SupportRequest>> create({
    required String category,
    required String description,
    String? bookingId,
    List<XFile> photos = const [],
  }) =>
      _run(() async {
        final form = FormData.fromMap({
          'category': category,
          'description': description.trim(),
          if (bookingId != null && bookingId.isNotEmpty) 'booking_id': bookingId,
          if (photos.isNotEmpty)
            'attachments': [
              for (final p in photos) MultipartFile.fromBytes(await p.readAsBytes(), filename: p.name.isEmpty ? 'photo.jpg' : p.name),
            ],
        });
        final r = await api.post('/booking/complaints/create/', data: form, options: Options(contentType: 'multipart/form-data'));
        return ResponseNormalizer.extract(r, (d) => SupportRequest.tryParse(d) ?? (throw const ParseError('Unexpected response.')));
      });

  Future<Result<bool>> reply(int id, String message) => _run(() async {
        await api.post('/booking/complaints/$id/response/', data: {'message': message.trim()});
        return const Success(true);
      });

  Future<Result<SupportRequest>> reopen(int id) => _action(id, 'reopen');
  Future<Result<SupportRequest>> escalate(int id) => _action(id, 'escalate');

  Future<Result<SupportRequest>> _action(int id, String name) => _run(() async {
        final r = await api.post('/booking/complaints/$id/$name/', data: <String, dynamic>{});
        return ResponseNormalizer.extract(r, (d) => SupportRequest.tryParse(d) ?? (throw const ParseError('Unexpected response.')));
      });

  Future<Result<T>> _run<T>(Future<Result<T>> Function() call) async {
    try {
      return await call();
    } on ApiError catch (e) {
      return Failure(e);
    } on DioException catch (e) {
      return Failure(e.error is ApiError ? e.error! as ApiError : const NetworkError());
    } catch (_) {
      return const Failure(UnknownError());
    }
  }
}

final supportRequestsRepositoryProvider =
    Provider<SupportRequestsRepository>((ref) => SupportRequestsRepository(api: ref.watch(apiClientProvider)));

final supportRequestsProvider = FutureProvider.autoDispose<List<SupportRequest>>((ref) async {
  final r = await ref.watch(supportRequestsRepositoryProvider).list();
  return switch (r) {
    Success(:final data) => data,
    Failure(:final error) => throw error,
  };
});

final supportRequestProvider = FutureProvider.autoDispose.family<SupportRequest, int>((ref, id) async {
  final r = await ref.watch(supportRequestsRepositoryProvider).detail(id);
  return switch (r) {
    Success(:final data) => data,
    Failure(:final error) => throw error,
  };
});
