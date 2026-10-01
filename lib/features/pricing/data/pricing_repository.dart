import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/api_error.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/response_normalizer.dart';
import '../domain/pricing_models.dart';

/// Talks to the backend's admin-configurable pricing endpoint. See
/// pricing_models.dart for why this exists.
class PricingRepository {
  PricingRepository({required this.api});

  final ApiClient api;

  /// GET /api/settings/pricing/ — public, no auth required (same as the
  /// legal/homepage config endpoints), so this works for guest checkout too.
  Future<Result<PricingConfig>> getPricingConfig() async {
    try {
      final response = await api.get('/settings/pricing/');
      return ResponseNormalizer.extract(
        response,
        (data) => PricingConfig.fromJson(
          data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{},
        ),
      );
    } on Exception catch (e) {
      return Failure(_toError(e));
    }
  }

  ApiError _toError(Object e) {
    if (e is ApiError) return e;
    return UnknownError(e.toString());
  }
}

final pricingRepositoryProvider = Provider<PricingRepository>((ref) {
  return PricingRepository(api: ref.watch(apiClientProvider));
});
