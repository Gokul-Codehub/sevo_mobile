import 'dart:math' as math;

import 'package:dio/dio.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

/// A real road-network route between two points.
class RoadRoute {
  const RoadRoute({
    required this.points,
    required this.distanceKm,
    required this.etaMinutes,
  });

  final List<LatLng> points;
  final double distanceKm;
  final int etaMinutes;
}

/// Fetches real road-network route geometry from OSRM (Open Source Routing
/// Machine) — the exact same free, public routing service the reference web
/// app uses for its live tracking Polyline (frontend/src/api/routing.js:
/// `fetchRoadRoute`, calling `${server}/route/v1/driving/...&geometries=geojson`).
/// No API key required, and this deliberately reuses the same public mirror
/// list and 30s result cache the web app already relies on in production.
///
/// Added 2026-09-16 — the mobile tracking screen previously only ever drew a
/// straight line between the technician and the destination; this restores
/// parity with the web app's real routed line.
class RoutingService {
  RoutingService._();

  static final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 4),
      receiveTimeout: const Duration(seconds: 4),
    ),
  );

  static const List<String> _servers = [
    'https://router.project-osrm.org',
    'https://routing.openstreetmap.de/routed-car',
  ];

  static final Map<String, _CachedRoute> _cache = {};

  /// Fetches (or returns a cached) road route from origin to destination.
  /// Returns null if every mirror fails — callers should fall back to a
  /// straight-line polyline in that case, never block the map on this.
  static Future<RoadRoute?> fetchRoadRoute({
    required double originLat,
    required double originLng,
    required double destLat,
    required double destLng,
  }) async {
    final cacheKey =
        '${originLat.toStringAsFixed(4)},${originLng.toStringAsFixed(4)}'
        '->${destLat.toStringAsFixed(4)},${destLng.toStringAsFixed(4)}';
    final cached = _cache[cacheKey];
    if (cached != null &&
        DateTime.now().difference(cached.time) < const Duration(seconds: 30)) {
      return cached.route;
    }

    for (final server in _servers) {
      try {
        final url =
            '$server/route/v1/driving/$originLng,$originLat;$destLng,$destLat'
            '?overview=full&geometries=geojson';
        final response = await _dio.get<dynamic>(url);
        final data = response.data;
        final map = data is Map ? Map<String, dynamic>.from(data) : null;
        final routes = map?['routes'];
        if (routes is! List || routes.isEmpty) continue;

        final route = Map<String, dynamic>.from(routes.first as Map);
        final geometry = route['geometry'];
        final coords = geometry is Map ? geometry['coordinates'] : null;
        if (coords is! List || coords.length < 2) continue;

        final points = coords
            .whereType<List>()
            .where((c) => c.length >= 2)
            .map((c) => LatLng((c[1] as num).toDouble(), (c[0] as num).toDouble()))
            .toList();
        if (points.length < 2) continue;

        final distanceKm = ((route['distance'] as num?)?.toDouble() ?? 0) / 1000.0;
        final durationMin = ((route['duration'] as num?)?.toDouble() ?? 0) / 60.0;

        final result = RoadRoute(
          points: points,
          distanceKm: distanceKm,
          etaMinutes: durationMin.ceil().clamp(1, 999),
        );
        _cache[cacheKey] = _CachedRoute(result, DateTime.now());
        return result;
      } catch (_) {
        // Try the next mirror.
      }
    }
    return null;
  }

  /// Great-circle distance in meters — used purely to throttle how often a
  /// new route is fetched (see live_tracking_screen.dart's
  /// `_maybeFetchRoute`), not for the route line itself.
  static double distanceMeters(double lat1, double lng1, double lat2, double lng2) {
    const earthRadiusM = 6371000.0;
    final dLat = _degToRad(lat2 - lat1);
    final dLng = _degToRad(lng2 - lng1);
    final sinDLat = math.sin(dLat / 2);
    final sinDLng = math.sin(dLng / 2);
    final a = sinDLat * sinDLat +
        math.cos(_degToRad(lat1)) * math.cos(_degToRad(lat2)) * sinDLng * sinDLng;
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return earthRadiusM * c;
  }

  static double _degToRad(double deg) => deg * (math.pi / 180.0);
}

class _CachedRoute {
  _CachedRoute(this.route, this.time);
  final RoadRoute route;
  final DateTime time;
}
