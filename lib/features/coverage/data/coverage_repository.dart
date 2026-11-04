import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/api_error.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/response_normalizer.dart';

class PlaceSuggestion {
  const PlaceSuggestion({required this.placeId, required this.main, required this.secondary});
  final String placeId;
  final String main;
  final String secondary;
}

class PlaceDetails {
  const PlaceDetails({
    required this.lat,
    required this.lng,
    required this.label,
    required this.pincode,
    this.name = '',
    this.address = '',
    this.locality = '',
    this.city = '',
    this.state = '',
  });

  final double lat;
  final double lng;

  /// "Main, secondary" as shown in the suggestion list.
  final String label;
  final String pincode;
  final String name;

  /// Google's formatted address, e.g. "Dharmapuri-Bengaluru Rd, Anna Nagar, Hosur, Tamil Nadu 635109, India".
  final String address;
  final String locality;
  final String city;
  final String state;

  List<String> get _parts => address.split(',').map((p) => p.trim()).where((p) => p.isNotEmpty).toList();

  /// The town, read from the address text: the part just before "<state> <pincode>". Google's own `city` field is
  /// sometimes a neighbourhood ("Anna Nagar" for an address in Hosur), so the address text is trusted first.
  String get cityName {
    final parts = _parts;
    var i = parts.indexWhere((p) => state.isNotEmpty && p.toLowerCase().startsWith(state.toLowerCase()));
    if (i < 0 && pincode.isNotEmpty) i = parts.indexWhere((p) => p.contains(pincode));
    if (i > 0) return parts[i - 1];
    return city.isNotEmpty ? city : locality;
  }

  /// The street / area part of the address, without the town, state, pincode and country, led by the place's name when
  /// it is a real name (a building, a bus stand): fits the address form's "street / area" line.
  String get street {
    final town = cityName.toLowerCase();
    final keep = [
      for (final p in _parts)
        if (p.toLowerCase() != 'india' &&
            p.toLowerCase() != town &&
            !(pincode.isNotEmpty && p.contains(pincode)) &&
            !(state.isNotEmpty && p.toLowerCase() == state.toLowerCase()))
          p,
    ];
    final joined = keep.join(', ');
    final n = name.trim();
    final isRealName = n.isNotEmpty && n.toLowerCase() != town && n.toLowerCase() != locality.toLowerCase();
    if (isRealName && !joined.toLowerCase().contains(n.toLowerCase())) {
      return joined.isEmpty ? n : '$n, $joined';
    }
    return joined;
  }
}

/// "Notify me when you arrive" and place search. Both go through our own server: the Google key never ships in the app.
class CoverageRepository {
  CoverageRepository({required this.api});

  final ApiClient api;

  /// `POST /api/settings/coverage/notify/` - register interest for an area we do not serve yet.
  /// Signed-in customers send no phone (the server uses the account's); guests send theirs.
  Future<Result<bool>> notifyMe({
    required String vertical,
    required double lat,
    required double lng,
    String? phone,
    String? pincode,
    String? areaLabel,
  }) async {
    try {
      await api.post('/settings/coverage/notify/', data: {
        'vertical': vertical,
        'lat': lat,
        'lng': lng,
        if ((phone ?? '').isNotEmpty) 'phone': phone,
        if ((pincode ?? '').isNotEmpty) 'pincode': pincode,
        if ((areaLabel ?? '').isNotEmpty) 'area_label': areaLabel,
      });
      return const Success(true);
    } on Exception catch (e) {
      return Failure(_toError(e));
    }
  }

  /// `GET /api/settings/places/autocomplete/`. Empty list for short text; a Failure when place search is unavailable
  /// (the sheet then falls back to plain address search).
  Future<Result<List<PlaceSuggestion>>> autocomplete(String text, {required String session, double? lat, double? lng}) async {
    try {
      final response = await api.get('/settings/places/autocomplete/', queryParameters: {
        'q': text,
        'session': session,
        'lat': ?lat,
        'lng': ?lng,
      });
      return ResponseNormalizer.extract(response, (data) {
        final list = data is List ? data : const [];
        return list
            .whereType<Map>()
            .map((m) => PlaceSuggestion(
                  placeId: (m['place_id'] ?? '').toString(),
                  main: (m['main'] ?? '').toString(),
                  secondary: (m['secondary'] ?? '').toString(),
                ))
            .where((s) => s.placeId.isNotEmpty)
            .toList();
      });
    } on Exception catch (e) {
      return Failure(_toError(e));
    }
  }

  /// `GET /api/settings/places/details/` - the point, pincode and a display name for a chosen suggestion.
  Future<Result<PlaceDetails>> details(PlaceSuggestion s, {required String session}) async {
    try {
      final response = await api.get('/settings/places/details/', queryParameters: {'place_id': s.placeId, 'session': session});
      return ResponseNormalizer.extract(response, (data) {
        final m = data is Map ? data : const {};
        final lat = (m['lat'] as num?)?.toDouble();
        final lng = (m['lng'] as num?)?.toDouble();
        if (lat == null || lng == null) throw const FormatException('no location');
        final label = [s.main, s.secondary].where((p) => p.isNotEmpty).join(', ');
        String text(String k) => (m[k] ?? '').toString().trim();
        return PlaceDetails(
          lat: lat,
          lng: lng,
          label: label.isNotEmpty ? label : text('address'),
          pincode: text('pincode'),
          name: text('name'),
          address: text('address'),
          locality: text('locality'),
          city: text('city'),
          state: text('state'),
        );
      });
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

final coverageRepositoryProvider = Provider<CoverageRepository>((ref) {
  return CoverageRepository(api: ref.watch(apiClientProvider));
});
