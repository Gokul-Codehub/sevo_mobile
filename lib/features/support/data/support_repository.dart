import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/api_error.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/response_normalizer.dart';

/// Repository for customer support / help-desk tickets.
///
/// Endpoint contract from Handover Bible §14.13:
///   POST /customer-care/tickets/
///
/// Added 2026-08-27: previously the "Raise Support Request" sheet in
/// support_screen.dart never called the backend at all — it just closed the
/// sheet and showed a hardcoded fake success message with a fixed ticket
/// number ("#CS-8291"), regardless of what the customer typed or whether
/// anything was actually saved server-side. This repository makes the real
/// call so a ticket is genuinely created (or the customer sees a real error
/// instead of a false confirmation).
class SupportRepository {
  SupportRepository({required this.api});

  final ApiClient api;

  /// Submits a new customer support ticket.
  /// Returns the ticket reference/id string from the backend response when
  /// present, so the UI can show the real reference instead of a fake one.
  Future<Result<String?>> submitTicket({
    required String subject,
    required String message,
    required String category,
  }) async {
    try {
      final response = await api.post('/customer-care/tickets/', data: {
        'subject': subject,
        'message': message,
        'description': message,
        'category': category,
      });
      return ResponseNormalizer.extract(response, (data) {
        if (data is Map) {
          final map = Map<String, dynamic>.from(data);
          final ref = map['ticket_id'] ?? map['id'] ?? map['reference'] ?? map['ticket_number'];
          return ref?.toString();
        }
        return null;
      });
    } on Exception catch (e) {
      return Failure(_toError(e));
    }
  }

  ApiError _toError(Object e) {
    if (e is ApiError) return e;
    if (e is DioException && e.error is ApiError) {
      return e.error! as ApiError;
    }
    return UnknownError(e.toString());
  }
}

// ── Provider ─────────────────────────────────────────────────────────────────
final supportRepositoryProvider = Provider<SupportRepository>((ref) {
  return SupportRepository(api: ref.watch(apiClientProvider));
});
