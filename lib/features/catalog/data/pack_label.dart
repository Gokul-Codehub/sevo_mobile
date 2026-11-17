/// One place that builds the quantity label shown on grocery products, so the
/// app matches the website (productGroupingUtils.js `getVariantLabel`):
/// pack size + unit when the pack size doesn't already end with the unit
/// ("500" + "g" -> "500 g"), else the pack size, else the unit.
///
/// A product with no pack size and no unit is labelled [kStandardPack] (the
/// backend sends the same text), so the app never shows a blank or invented weight.
const String kStandardPack = 'Standard Pack';

String groceryPackLabel(String? packSize, String? unit) {
  final ps = (packSize ?? '').trim();
  final u = (unit ?? '').trim();
  // A descriptive pack size ("Standard Pack", "Family pack") is already complete: no unit to append.
  if (ps.isNotEmpty && !RegExp(r'\d').hasMatch(ps)) return ps;
  if (ps.isNotEmpty && u.isNotEmpty && !ps.toLowerCase().endsWith(u.toLowerCase())) {
    return '$ps $u';
  }
  if (ps.isNotEmpty) return ps;
  return u.isNotEmpty ? u : kStandardPack;
}
