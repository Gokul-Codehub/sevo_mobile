import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/api_error.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/response_normalizer.dart';
import '../domain/feedback_models.dart';

/// Repository for tokenized feedback retrieval and submission.
class FeedbackRepository {
  FeedbackRepository({required this.api});

  final ApiClient api;

  // ── Fetch feedback details via token ──────────────────────────────────────
  Future<Result<FeedbackData>> getFeedbackDetails(String token) async {
    try {
      final response = await api.get('/feedback/$token/');
      return ResponseNormalizer.extract(
        response,
        (data) => FeedbackData.fromJson(
          data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{},
          token,
        ),
      );
    } on Exception catch (e) {
      // Fixed 2026-08-27: this previously returned a fabricated Success()
      // with fake service/technician names whenever the API call failed —
      // masking real errors (invalid/expired token, network failure, server
      // down) behind a plausible-looking fake screen. Never invent booking
      // data; surface the real failure so the UI can show an error state.
      return Failure(_toError(e));
    }
  }

  // ── Submit rating & review ────────────────────────────────────────────────
  Future<Result<bool>> submitFeedback(FeedbackSubmission submission) async {
    try {
      await api.post(
        '/feedback/${submission.token}/',
        data: submission.toJson(),
      );
      return const Success(true);
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
final feedbackRepositoryProvider = Provider<FeedbackRepository>((ref) {
  return FeedbackRepository(api: ref.watch(apiClientProvider));
});

final feedbackDetailsProvider =
    FutureProvider.family<FeedbackData, String>((ref, token) async {
  final repo = ref.watch(feedbackRepositoryProvider);
  final result = await repo.getFeedbackDetails(token);
  return switch (result) {
    Success(:final data) => data,
    Failure(:final error) => throw error,
  };
});
