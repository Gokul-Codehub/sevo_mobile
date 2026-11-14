import 'package:decimal/decimal.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/api_error.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/response_normalizer.dart';
import 'mason_rules.dart';

/// Site-visit (Mason / Painting consultation) rules, loaded from the server
/// (`GET /api/consultation/config/`) so the radius and fee are never hardcoded
/// in the app. Falls back to the built-in defaults if the request fails.
final consultationRulesProvider = FutureProvider<ConsultationRules>((ref) async {
  try {
    final api = ref.watch(apiClientProvider);
    final response = await api.get('/consultation/config/');
    final res = ResponseNormalizer.extract<Map<String, dynamic>>(
      response,
      (d) => d is Map ? Map<String, dynamic>.from(d) : <String, dynamic>{},
    );
    if (res is Success<Map<String, dynamic>>) {
      final d = res.data;
      final km = double.tryParse('${d['free_radius_km']}');
      final fee = Decimal.tryParse('${d['beyond_fee']}');
      final lat = double.tryParse('${d['center_lat']}');
      final lng = double.tryParse('${d['center_lng']}');
      if (km != null && fee != null) {
        final rules = ConsultationRules(
          freeRadiusKm: km,
          beyondFee: fee,
          centreLat: lat ?? kConsultationDefaults.centreLat,
          centreLng: lng ?? kConsultationDefaults.centreLng,
        );
        kActiveConsultationRules = rules;
        return rules;
      }
    }
  } on Exception {
    // fall through to defaults
  }
  return kActiveConsultationRules;
});
