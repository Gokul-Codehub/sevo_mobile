import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/api_error.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/response_normalizer.dart';
import '../domain/booking_models.dart';

/// Repository for the Painting / Masonry / AC-Inspection quotation flow.
///
/// Added 2026-09-26 after auditing the real (not just documented) CUS
/// backend: booking detail/list responses already embed a lightweight
/// `quote` object (see [QuoteSummary] in booking_models.dart, and
/// `Booking.quote`) carrying a `decision_token` — that token is what this
/// repository's two calls take, hitting
/// `GET/POST /api/workforce/quotes/decision/<token>/`
/// (`WorkforceQuoteDecisionBridgeView` on the backend — its own doc comment
/// says it was built explicitly for "the Customer Quotation Decision Page",
/// i.e. this is the exact same endpoint the React web app's quote card
/// already calls, not a new contract invented for this app).
///
/// Per the backend integration prompt this was audited against: a socket or
/// push notification is only ever a *signal to refetch*, never itself the
/// source of truth. So [getQuote] exists mainly for that refetch — most of
/// the time a screen already has a fresh `QuoteSummary` from the booking
/// payload and only needs [decide].
class QuoteRepository {
  QuoteRepository({required this.api});

  final ApiClient api;

  /// Re-fetches the latest quote state directly by its decision token —
  /// call this after a socket/notification event, on screen focus, or after
  /// [decide] to confirm the backend's authoritative post-decision state.
  Future<Result<QuoteSummary>> getQuote(String token) async {
    try {
      final response = await api.get('/workforce/quotes/decision/$token/');
      return ResponseNormalizer.extract(response, (data) {
        final map = data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{};
        return QuoteSummary.fromJson(map);
      });
    } on Exception catch (e) {
      return Failure(_toError(e));
    }
  }

  /// [decision] must be one of 'CUSTOMER_ACCEPTED', 'DECLINED',
  /// 'CHANGE_REQUESTED' — the backend normalises common synonyms too, but
  /// this app always sends the canonical value so intent is unambiguous in
  /// logs on both sides.
  ///
  /// Returns the backend's confirmation message on success. Never treats a
  /// 200 here as "booking confirmed" by itself — for CUSTOMER_ACCEPTED the
  /// backend creates the Stage-2 (quoted_work) booking asynchronously-ish
  /// inside the same request, but the caller should still re-fetch the
  /// parent booking (bookingDetailProvider) afterwards to pick up the real
  /// child booking rather than assume anything client-side.
  Future<Result<String>> decide(
    String token,
    String decision, {
    String? reasonNotes,
  }) async {
    try {
      final response = await api.post(
        '/workforce/quotes/decision/$token/',
        data: {
          'action': decision,
          if (reasonNotes != null && reasonNotes.trim().isNotEmpty) 'reason_notes': reasonNotes.trim(),
        },
      );
      return ResponseNormalizer.extract(response, (data) {
        final map = data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{};
        return (map['message'] ?? 'Done.').toString();
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

final quoteRepositoryProvider = Provider<QuoteRepository>((ref) {
  return QuoteRepository(api: ref.watch(apiClientProvider));
});
