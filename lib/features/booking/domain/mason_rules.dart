import 'dart:math' as math;

import 'package:decimal/decimal.dart';

import '../../catalog/domain/catalog_models.dart';
import 'booking_models.dart';

/// Mason (masonry & civil work) is booked as a SITE CONSULTATION, exactly like the web app and the backend's
/// `home_services_pricing.py`:
///  * the consultation is free within [kMasonFreeRadiusKm] of the city centre, [kMasonFarFee] beyond that;
///  * no GST and no platform fee are charged on it;
///  * Minor Masonry needs the work area (at least [kMinorMasonryMinArea] sq.ft);
///  * Bathroom Tile Fixing needs a bathroom size, which fixes the indicative work price ([kBathroomTileSlabs]);
///  * the actual work is then priced by a quotation the customer accepts after the site visit.
const int kMinorMasonryMinArea = 500;

/// Site-visit rules. The values are loaded from the server (see `consultation_rules_provider.dart`); the defaults
/// below are only a fallback for when the config cannot be reached.
class ConsultationRules {
  const ConsultationRules({
    required this.freeRadiusKm,
    required this.beyondFee,
    required this.centreLat,
    required this.centreLng,
  });
  final double freeRadiusKm;
  final Decimal beyondFee;
  final double centreLat;
  final double centreLng;
}

final ConsultationRules kConsultationDefaults = ConsultationRules(
  freeRadiusKm: 15.0,
  beyondFee: Decimal.fromInt(300),
  centreLat: 12.7409,
  centreLng: 77.8253,
);

/// The rules currently in force (server values once loaded).
ConsultationRules kActiveConsultationRules = kConsultationDefaults;

const List<String> kBathroomSizes = ['Small', 'Medium', 'Large'];
const Map<String, int> kBathroomTileSlabs = {'Small': 10000, 'Medium': 10000, 'Large': 20000};

bool isMinorMasonry(ServiceItem s) {
  final k = '${s.slug} ${s.title}'.toLowerCase();
  return k.contains('minor-masonry') || k.contains('minor_masonry') || k.contains('minor masonry');
}

bool isBathroomTileFixing(ServiceItem s) {
  final k = '${s.slug} ${s.title}'.toLowerCase();
  return k.contains('bathroom-tile') || k.contains('bathroom_tile') || k.contains('bathroom tile') || k.contains('tile-fixing');
}

/// True for every service of the Mason category.
bool isMasonOnlyService(ServiceItem s) {
  final c = '${s.categorySlug ?? ''} ${s.categoryName ?? ''}'.toLowerCase();
  return c.contains('mason') || isMinorMasonry(s) || isBathroomTileFixing(s);
}

/// Painting & waterproofing (interior, exterior, waterproofing, wood & metal, texture & decor): booked as the same
/// kind of free site consultation, priced afterwards by a quotation (backend `PAINTING_CATEGORIES`).
bool isPaintingService(ServiceItem s) {
  if (isMasonOnlyService(s)) return false;
  final c = '${s.categorySlug ?? ''} ${s.categoryName ?? ''}'.toLowerCase();
  return c.contains('paint') || c.contains('waterproof') || c.contains('wood-metal') || c.contains('texture');
}

bool isWaterproofingService(ServiceItem s) {
  final k = '${s.slug} ${s.title} ${s.subcategorySlug ?? ''} ${s.subcategoryName ?? ''}'.toLowerCase();
  return k.contains('waterproof');
}

/// Mason OR Painting: every service that is booked as a site consultation first.
bool isMasonService(ServiceItem s) => isMasonOnlyService(s) || isPaintingService(s);

double _haversineKm(double lat1, double lon1, double lat2, double lon2) {
  const r = 6371.0;
  double rad(double d) => d * math.pi / 180;
  final dLat = rad(lat2 - lat1);
  final dLon = rad(lon2 - lon1);
  final a = math.pow(math.sin(dLat / 2), 2) + math.cos(rad(lat1)) * math.cos(rad(lat2)) * math.pow(math.sin(dLon / 2), 2);
  return r * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
}

/// Consultation fee for a service address (free when the position is unknown, as on the web).
Decimal masonConsultationFee(double? lat, double? lng) {
  if (lat == null || lng == null) return Decimal.zero;
  final r = kActiveConsultationRules;
  final km = _haversineKm(r.centreLat, r.centreLng, lat, lng);
  return km > r.freeRadiusKm ? r.beyondFee : Decimal.zero;
}

/// The single `cart_data` line the backend expects for a Mason consultation (same shape the web app posts).
Map<String, dynamic> masonCartLine(
  ServiceItem s,
  Decimal fee, {
  int? areaSqFt,
  String? bathroomSize,
}) {
  if (isPaintingService(s)) return _paintingCartLine(s, fee);
  final minor = isMinorMasonry(s);
  final tile = isBathroomTileFixing(s);
  final base = minor
      ? 'minor-masonry'
      : tile
          ? 'bathroom-tile-fixing'
          : (s.slug.isNotEmpty ? s.slug : '${s.id}');
  final title = s.title.endsWith('(Site Consultation)') ? s.title : '${s.title} (Site Consultation)';
  return {
    'id': 'serv-mason-$base',
    'name': title,
    'price': fee.toDouble(),
    'platform_fee': 0,
    'gst_rate': 0,
    'is_consultation': true,
    'quantity': 1,
    'categoryName': 'Mason',
    if ((s.imageUrl ?? '').trim().isNotEmpty) 'image': s.imageUrl,
    if (minor && areaSqFt != null) 'selectedArea': areaSqFt,
    if (tile && bathroomSize != null) ...{
      'selectedBathroomSize': bathroomSize,
      'predefinedPrice': kBathroomTileSlabs[bathroomSize] ?? 10000,
    },
  };
}

/// Painting consultation line, the shape the web app posts (`serv-paint-estimate-<service>`): one line per
/// package with the chosen sub-option listed.
Map<String, dynamic> _paintingCartLine(ServiceItem s, Decimal fee) {
  final raw = '${s.subcategorySlug ?? ''} ${s.slug} ${s.title}'.toLowerCase();
  final serviceSlug = raw.contains('waterproof')
      ? 'waterproofing'
      : raw.contains('exterior')
          ? 'exterior-painting'
          : raw.contains('wood') || raw.contains('metal')
              ? 'wood-metal'
              : raw.contains('texture')
                  ? 'texture-decor'
                  : 'interior-painting';
  final title = s.title.endsWith('(Site Consultation)') ? s.title : '${s.title} (Site Consultation)';
  return {
    'id': 'serv-paint-estimate-${s.slug.isNotEmpty ? s.slug : s.id}',
    'name': title,
    'price': fee.toDouble(),
    'platform_fee': 0,
    'gst_rate': 0,
    'is_consultation': true,
    'quantity': 1,
    'categoryName': 'Painting',
    'categorySlug': 'paintings',
    'service_slug': serviceSlug,
    'serviceSlug': serviceSlug,
    'service': serviceSlug,
    'selectedSubOptions': [s.title],
    if ((s.imageUrl ?? '').trim().isNotEmpty) 'image': s.imageUrl,
  };
}

/// What to print for a booking's amount: a free Mason site visit reads "FREE" instead of "₹0".
String bookingAmountLabel(Booking b) =>
    (b.totalAmount == Decimal.zero && b.items.any((i) => isMasonService(i.service))) ? 'FREE' : '₹${b.totalAmount}';

/// "FREE (within 15 km)" / "₹300 (beyond 15 km)".
String masonFeeLabel(Decimal fee) {
  final km = kActiveConsultationRules.freeRadiusKm;
  final kmText = km == km.roundToDouble() ? '${km.toInt()}' : km.toStringAsFixed(1);
  return fee > Decimal.zero ? '₹$fee (beyond $kmText km)' : 'FREE (within $kmText km)';
}
