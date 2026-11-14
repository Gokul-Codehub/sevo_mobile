/// One place that builds the quantity label shown on grocery products, so the
/// app matches the website (productGroupingUtils.js `getVariantLabel`):
/// pack size + unit when the pack size doesn't already end with the unit
/// ("500" + "g" -> "500 g"), else the pack size, else the unit.
String groceryPackLabel(String? packSize, String? unit) {
  final ps = (packSize ?? '').trim();
  final u = (unit ?? '').trim();
  if (ps.isNotEmpty && u.isNotEmpty && !ps.toLowerCase().endsWith(u.toLowerCase())) {
    return '$ps $u';
  }
  if (ps.isNotEmpty) return ps;
  return u;
}
