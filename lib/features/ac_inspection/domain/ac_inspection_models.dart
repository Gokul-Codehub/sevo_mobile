import 'package:decimal/decimal.dart';
import 'package:equatable/equatable.dart';

/// One line of the spare-parts / repair rate card (e.g. "Capacitor 2-5" Rs 250).
class AcRateItem extends Equatable {
  const AcRateItem({required this.name, required this.price});

  final String name;

  /// Price text exactly as the admin's rate card gives it (e.g. "Rs 1,199").
  final String price;

  @override
  List<Object?> get props => [name, price];
}

class AcRateCategory extends Equatable {
  const AcRateCategory({required this.name, required this.items});

  final String name;
  final List<AcRateItem> items;

  @override
  List<Object?> get props => [name, items];
}

/// `GET /api/settings/ac-inspection/config/` - the "AC Inspection & Diagnostic
/// Visit" the web shows inside the Air Conditioner category. Everything is
/// admin-driven (fee, texts, rate card); nothing here is hardcoded in the app.
class AcInspectionConfig extends Equatable {
  const AcInspectionConfig({
    required this.fee,
    required this.title,
    required this.subtitle,
    this.isActive = true,
    this.badges = const [],
    this.includes = const [],
    this.ready = const [],
    this.rateCard = const [],
  });

  final Decimal fee;
  final String title;
  final String subtitle;
  final bool isActive;
  final List<String> badges;
  final List<String> includes;
  final List<String> ready;
  final List<AcRateCategory> rateCard;

  static List<String> _strings(dynamic raw) {
    if (raw is! List) return const [];
    return raw
        .map((e) => e is Map ? (e['text'] ?? e['label'] ?? '').toString() : e.toString())
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
  }

  factory AcInspectionConfig.fromJson(Map<String, dynamic> json) {
    final feeRaw = json['fee'] ?? json['diagnostic_fee'] ?? 199;
    final cats = <AcRateCategory>[];
    for (final c in (json['rateCardCategories'] as List? ?? const []).whereType<Map>()) {
      final items = <AcRateItem>[];
      for (final i in (c['items'] as List? ?? const []).whereType<Map>()) {
        final name = (i['name'] ?? '').toString().trim();
        if (name.isEmpty || i['is_active'] == false) continue;
        items.add(AcRateItem(name: name, price: (i['price'] ?? '').toString()));
      }
      final name = (c['name'] ?? '').toString().trim();
      if (name.isNotEmpty && items.isNotEmpty) cats.add(AcRateCategory(name: name, items: items));
    }
    return AcInspectionConfig(
      fee: Decimal.tryParse(feeRaw.toString().replaceAll(RegExp(r'[^0-9.]'), '')) ?? Decimal.fromInt(199),
      title: (json['title'] ?? 'AC Inspection & Diagnostic Visit').toString(),
      subtitle: (json['subtitle'] ?? '').toString(),
      isActive: json['is_active'] != false,
      badges: _strings(json['badges']),
      includes: _strings(json['includes']),
      ready: _strings(json['ready']),
      rateCard: cats,
    );
  }

  @override
  List<Object?> get props => [fee, title, subtitle, isActive, badges, includes, ready, rateCard];
}

/// What the customer fills in for the inspection (web: ACInspectionFormModal).
class AcInspectionDetails {
  const AcInspectionDetails({
    required this.brand,
    required this.acType,
    required this.capacity,
    required this.quantity,
    required this.symptom,
    this.notes,
  });

  final String brand;

  /// Backend value: SPLIT | WINDOW | CASSETTE | TOWER | OTHER
  final String acType;

  /// Backend value: 1_TON | 1.5_TON | 2_TON | OTHER
  final String capacity;
  final int quantity;
  final String symptom;
  final String? notes;
}

const acBrands = [
  'Daikin', 'Voltas', 'LG', 'Samsung', 'Blue Star', 'Hitachi', 'Carrier',
  'Panasonic', 'Godrej', 'Whirlpool', 'Lloyd', 'Mitsubishi', 'O General', 'Haier', 'Other',
];

/// (label shown, value sent) - the values the backend validates against.
const acTypes = [
  ('Split AC', 'SPLIT'),
  ('Window AC', 'WINDOW'),
  ('Cassette AC', 'CASSETTE'),
  ('Tower AC', 'TOWER'),
  ('Other', 'OTHER'),
];

const acCapacities = [
  ('1 Ton', '1_TON'),
  ('1.5 Ton', '1.5_TON'),
  ('2 Ton', '2_TON'),
  ('Other', 'OTHER'),
];
