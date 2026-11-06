import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../../../core/errors/api_error.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/network/response_normalizer.dart';
import '../../../../shared/maps/sevo_map_style.dart';
import '../../../../shared/theme/app_colors.dart';

/// One admin-drawn service area (circle or polygon) from `GET /api/settings/service-zones/`.
class GtZone {
  const GtZone({
    required this.id,
    required this.name,
    required this.color,
    required this.vehicleClasses,
    this.center,
    this.radiusMeters,
    this.ring = const [],
  });

  final int id;
  final String name;
  final Color color;

  /// Empty = every vehicle class.
  final List<String> vehicleClasses;
  final LatLng? center;
  final double? radiusMeters;
  final List<LatLng> ring;

  bool get isCircle => ring.length < 3 && center != null && (radiusMeters ?? 0) > 0;

  bool servesClass(String? vehicleClass) =>
      vehicleClasses.isEmpty || vehicleClass == null || vehicleClasses.contains(vehicleClass);

  bool contains(double lat, double lng) {
    if (isCircle) return _haversineMeters(center!.latitude, center!.longitude, lat, lng) <= radiusMeters!;
    if (ring.length < 3) return false;
    var inside = false;
    for (var i = 0, j = ring.length - 1; i < ring.length; j = i++) {
      final a = ring[i];
      final b = ring[j];
      final crosses = (a.latitude > lat) != (b.latitude > lat) &&
          lng < (b.longitude - a.longitude) * (lat - a.latitude) / (b.latitude - a.latitude) + a.longitude;
      if (crosses) inside = !inside;
    }
    return inside;
  }

  static GtZone? tryParse(Map<String, dynamic> m) {
    double? d(dynamic v) => v is num ? v.toDouble() : double.tryParse('${v ?? ''}');
    final id = m['id'] is num ? (m['id'] as num).toInt() : int.tryParse('${m['id']}');
    if (id == null) return null;
    final lat = d(m['center_lat']);
    final lng = d(m['center_lng']);
    final ring = <LatLng>[];
    final poly = m['polygon'];
    if (poly is Map && poly['coordinates'] is List && (poly['coordinates'] as List).isNotEmpty) {
      var first = (poly['coordinates'] as List).first;
      // MultiPolygon: coordinates[0][0] is the outer ring.
      if (first is List && first.isNotEmpty && first.first is List && (first.first as List).isNotEmpty && (first.first as List).first is List) {
        first = first.first;
      }
      if (first is List) {
        for (final p in first) {
          if (p is List && p.length >= 2) {
            final x = d(p[0]);
            final y = d(p[1]);
            if (x != null && y != null) ring.add(LatLng(y, x)); // GeoJSON is [lng, lat]
          }
        }
      }
    }
    final type = '${m['zone_type'] ?? ''}'.toLowerCase();
    final useRing = type == 'polygon' && ring.length >= 3;
    final classes = m['vehicle_classes'] is List ? (m['vehicle_classes'] as List).map((e) => '$e').toList() : <String>[];
    return GtZone(
      id: id,
      name: '${m['name'] ?? 'Service area'}',
      color: _parseColor('${m['color'] ?? ''}'),
      vehicleClasses: classes,
      center: lat != null && lng != null ? LatLng(lat, lng) : null,
      radiusMeters: d(m['radius_meters']),
      ring: useRing ? ring : const [],
    );
  }
}

Color _parseColor(String hex) {
  var h = hex.trim().replaceFirst('#', '');
  if (h.length == 3) h = h.split('').map((c) => '$c$c').join();
  final v = h.length == 6 ? int.tryParse('FF$h', radix: 16) : null;
  return v == null ? AppColors.navy : Color(v);
}

double _haversineMeters(double lat1, double lng1, double lat2, double lng2) {
  const r = 6371000.0;
  double rad(double x) => x * math.pi / 180;
  final dLat = rad(lat2 - lat1);
  final dLng = rad(lng2 - lng1);
  final a = math.pow(math.sin(dLat / 2), 2) + math.cos(rad(lat1)) * math.cos(rad(lat2)) * math.pow(math.sin(dLng / 2), 2);
  return 2 * r * math.asin(math.min(1, math.sqrt(a)));
}

/// The active service areas for a GT service slug (e.g. `goods_transport_truck`). Empty when none are drawn / the
/// call fails: the map simply shows no shading, it never blocks the booking.
final gtServiceZonesProvider = FutureProvider.autoDispose.family<List<GtZone>, String>((ref, slug) async {
  try {
    final response = await ref.watch(apiClientProvider).get('/settings/service-zones/', queryParameters: {'services': slug});
    final r = ResponseNormalizer.extractPayload(response);
    final data = r is Success<dynamic> ? r.data : null;
    final list = data is List ? data : (data is Map && data['results'] is List ? data['results'] as List : const []);
    return list.whereType<Map>().map((m) => GtZone.tryParse(Map<String, dynamic>.from(m))).whereType<GtZone>().toList();
  } catch (_) {
    return const <GtZone>[];
  }
});

List<GtZone> zonesFor(List<GtZone> all, String? vehicleClass) =>
    all.where((z) => z.servesClass(vehicleClass)).toList();

/// true / false when areas are drawn; null when none are (nothing to compare against).
bool? insideService(List<GtZone> zones, double lat, double lng) {
  if (zones.isEmpty) return null;
  return zones.any((z) => z.contains(lat, lng));
}

Set<Circle> zoneCircles(List<GtZone> zones) => {
      for (final z in zones)
        if (z.isCircle)
          Circle(
            circleId: CircleId('zone_${z.id}'),
            center: z.center!,
            radius: z.radiusMeters!,
            fillColor: z.color.withValues(alpha: 0.14),
            strokeColor: z.color.withValues(alpha: 0.85),
            strokeWidth: 2,
          ),
    };

Set<Polygon> zonePolygons(List<GtZone> zones) => {
      for (final z in zones)
        if (!z.isCircle && z.ring.length >= 3)
          Polygon(
            polygonId: PolygonId('zone_${z.id}'),
            points: z.ring,
            fillColor: z.color.withValues(alpha: 0.14),
            strokeColor: z.color.withValues(alpha: 0.85),
            strokeWidth: 2,
          ),
    };

LatLngBounds? zonesBounds(List<GtZone> zones, [List<LatLng> extra = const []]) {
  final pts = <LatLng>[...extra];
  for (final z in zones) {
    if (z.isCircle) {
      final dLat = (z.radiusMeters! / 111320.0);
      final dLng = dLat / math.max(0.2, math.cos(z.center!.latitude * math.pi / 180));
      pts
        ..add(LatLng(z.center!.latitude + dLat, z.center!.longitude + dLng))
        ..add(LatLng(z.center!.latitude - dLat, z.center!.longitude - dLng));
    } else {
      pts.addAll(z.ring);
    }
  }
  if (pts.length < 2) return null;
  var minLat = pts.first.latitude, maxLat = pts.first.latitude, minLng = pts.first.longitude, maxLng = pts.first.longitude;
  for (final p in pts) {
    minLat = math.min(minLat, p.latitude);
    maxLat = math.max(maxLat, p.latitude);
    minLng = math.min(minLng, p.longitude);
    maxLng = math.max(maxLng, p.longitude);
  }
  return LatLngBounds(southwest: LatLng(minLat, minLng), northeast: LatLng(maxLat, maxLng));
}

/// "Where do we deliver?" card for the Locations step: the service areas shaded on a map with the pickup and
/// drop-off pins, and a plain inside / outside line for each.
class GtCoverageMap extends ConsumerStatefulWidget {
  const GtCoverageMap({
    super.key,
    required this.serviceSlug,
    this.vehicleClass,
    this.pickup,
    this.drop,
    this.dropAnywhere = false,
  });

  final String serviceSlug;
  final String? vehicleClass;
  final LatLng? pickup;
  final LatLng? drop;

  /// Intercity moves: only the pickup must be inside the area.
  final bool dropAnywhere;

  @override
  ConsumerState<GtCoverageMap> createState() => _GtCoverageMapState();
}

class _GtCoverageMapState extends ConsumerState<GtCoverageMap> {
  GoogleMapController? _c;

  @override
  void dispose() {
    _c?.dispose();
    super.dispose();
  }

  void _fit(List<GtZone> zones) {
    final c = _c;
    if (c == null) return;
    final extra = [if (widget.pickup != null) widget.pickup!, if (widget.drop != null && !widget.dropAnywhere) widget.drop!];
    final b = zonesBounds(zones, extra);
    if (b == null) return;
    c.animateCamera(CameraUpdate.newLatLngBounds(b, 36));
  }

  @override
  Widget build(BuildContext context) {
    final all = ref.watch(gtServiceZonesProvider(widget.serviceSlug)).valueOrNull ?? const <GtZone>[];
    final zones = zonesFor(all, widget.vehicleClass);
    if (zones.isEmpty) return const SizedBox.shrink();

    final pickup = widget.pickup;
    final drop = widget.drop;
    final markers = <Marker>{
      if (pickup != null)
        Marker(markerId: const MarkerId('pickup'), position: pickup, icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen), infoWindow: const InfoWindow(title: 'Pickup')),
      if (drop != null)
        Marker(markerId: const MarkerId('drop'), position: drop, icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed), infoWindow: const InfoWindow(title: 'Drop-off')),
    };
    final start = pickup ?? zones.first.center ?? (zones.first.ring.isNotEmpty ? zones.first.ring.first : const LatLng(12.7409, 77.8253));

    Widget line(String who, double? lat, double? lng, {bool anywhere = false}) {
      if (lat == null || lng == null) return const SizedBox.shrink();
      final inside = insideService(zones, lat, lng);
      final String text;
      final Color color;
      final IconData icon;
      if (anywhere) {
        text = '$who can be in any city';
        color = AppColors.navy;
        icon = Icons.public_rounded;
      } else if (inside == true) {
        text = '$who is inside our service area';
        color = const Color(0xFF15803D);
        icon = Icons.check_circle_rounded;
      } else {
        text = '$who is outside our service area';
        color = AppColors.error;
        icon = Icons.error_rounded;
      }
      return Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Row(children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          Expanded(child: Text(text, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: color))),
        ]),
      );
    }

    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(children: [
            Icon(Icons.radar_rounded, size: 18, color: AppColors.navy),
            SizedBox(width: 6),
            Text('Our service area', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: AppColors.navy)),
          ]),
          const SizedBox(height: 4),
          const Text('The shaded area is where we pick up and deliver.', style: TextStyle(fontSize: 11.5, color: AppColors.textSecondary)),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: SizedBox(
              height: 190,
              child: GoogleMap(
                initialCameraPosition: CameraPosition(target: start, zoom: 11),
                circles: zoneCircles(zones),
                polygons: zonePolygons(zones),
                markers: markers,
                style: SevoMap.style,
                cloudMapId: SevoMap.cloudMapId,
                onMapCreated: (c) {
                  _c = c;
                  Future.delayed(const Duration(milliseconds: 350), () => mounted ? _fit(zones) : null);
                },
                zoomControlsEnabled: false,
                mapToolbarEnabled: false,
                myLocationButtonEnabled: false,
                compassEnabled: false,
                rotateGesturesEnabled: false,
                tiltGesturesEnabled: false,
              ),
            ),
          ),
          line('Pickup', pickup?.latitude, pickup?.longitude),
          line('Drop-off', drop?.latitude, drop?.longitude, anywhere: widget.dropAnywhere),
        ],
      ),
    );
  }
}
