import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/api_error.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/response_normalizer.dart';
import '../domain/work_extension_models.dart';

/// Repository for work extension retrieval and customer approval/rejection.
class WorkExtensionRepository {
  WorkExtensionRepository({required this.api});

  final ApiClient api;

  // ── Fetch work extension details ──────────────────────────────────────────
  Future<Result<WorkExtensionProposal>> getExtensionDetails(String token) async {
    try {
      final response = await api.get('/customer/work-extensions/$token/');
      return ResponseNormalizer.extract(
        response,
        (data) => WorkExtensionProposal.fromJson(
          data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{},
          token,
        ),
      );
    } on Exception catch (e) {
      // Fixed 2026-08-27: this previously returned a fabricated Success()
      // with a fake technician name and a fake ₹350.00 charge whenever the
      // API call failed — inventing a dollar amount that could genuinely
      // confuse a customer about what they're being asked to approve. Never
      // invent a charge; surface the real failure so the UI shows an error
      // state instead of a fake approval screen.
      return Failure(_toError(e));
    }
  }

  // ── Customer response: approve or reject ──────────────────────────────────
  Future<Result<bool>> respondToExtension({
    required String token,
    required bool approve,
    String? notes,
  }) async {
    try {
      final response = await api.post(
        '/customer/work-extensions/$token/decide/',
        data: {
          'action': approve ? 'approve' : 'reject',
          if (notes != null && notes.isNotEmpty) 'notes': notes,
        },
      );
      return ResponseNormalizer.extract(response, (_) => true);
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

// ── Providers ─────────────────────────────────────────────────────────────────
final workExtensionRepositoryProvider =
    Provider<WorkExtensionRepository>((ref) {
  return WorkExtensionRepository(api: ref.watch(apiClientProvider));
});

final workExtensionDetailsProvider =
    FutureProvider.family<WorkExtensionProposal, String>((ref, token) async {
  final repo = ref.watch(workExtensionRepositoryProvider);
  final result = await repo.getExtensionDetails(token);
  return switch (result) {
    Success(:final data) => data,
    Failure(:final error) => throw error,
  };
});
