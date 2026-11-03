import 'package:equatable/equatable.dart';

/// Last step of a goods declaration (every Goods & Transport service): optional handling notes for the driver at pickup
/// and drop, and the customer's confirmation that the goods are described accurately. The confirmation is required
/// whenever the customer typed their own goods ("Other / Not listed"); the server enforces the same rule.
/// Nothing here changes a price. Sent inside `cart_data[0]`, like the web booking pages.
class GtGoodsDecl extends Equatable {
  const GtGoodsDecl({this.pickup = '', this.drop = '', this.accepted = false});

  final String pickup;
  final String drop;
  final bool accepted;

  static const int maxNoteLength = 300;

  GtGoodsDecl copyWith({String? pickup, String? drop, bool? accepted}) => GtGoodsDecl(
        pickup: pickup ?? this.pickup,
        drop: drop ?? this.drop,
        accepted: accepted ?? this.accepted,
      );

  /// `goods_declaration_accepted` (only when goods were typed) and `handling_instructions` (only when written).
  Map<String, dynamic> cartFields({required bool hasTypedGoods}) {
    final p = pickup.trim();
    final d = drop.trim();
    return {
      if (hasTypedGoods) 'goods_declaration_accepted': accepted,
      if (p.isNotEmpty || d.isNotEmpty)
        'handling_instructions': {if (p.isNotEmpty) 'pickup': p, if (d.isNotEmpty) 'drop': d},
    };
  }

  @override
  List<Object?> get props => [pickup, drop, accepted];
}
