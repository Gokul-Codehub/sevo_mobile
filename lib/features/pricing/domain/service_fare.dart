import 'package:decimal/decimal.dart';

import '../../catalog/domain/catalog_models.dart';

/// Home-services fare, calculated exactly like the web app / backend
/// (`service_requests/services/home_services_pricing.py`):
///
///  * GST is charged per line at THAT package's own `gst_rate`
///    (default 18%), each line rounded to whole rupees (half-up);
///  * the platform fee is charged ONCE per booking: the highest
///    `platform_fee` among the items (default ₹29), and only when the
///    item total is above zero;
///  * grand total = item total + GST + platform fee - coupon.
class ServiceFare {
  const ServiceFare({
    required this.itemTotal,
    required this.gst,
    required this.platformFee,
  });

  final Decimal itemTotal;
  final Decimal gst;
  final Decimal platformFee;

  Decimal get total => itemTotal + gst + platformFee;

  static const double defaultGstRate = 18.0;
  static final Decimal defaultPlatformFee = Decimal.fromInt(29);

  /// [lines] = (service, line total for that service incl. quantity).
  factory ServiceFare.fromLines(
    Iterable<({ServiceItem service, Decimal lineTotal})> lines,
  ) {
    var itemTotal = Decimal.zero;
    var gst = Decimal.zero;
    Decimal? maxFee;
    final hundred = Decimal.fromInt(100);
    for (final line in lines) {
      itemTotal += line.lineTotal;
      final rate =
          Decimal.parse((line.service.gstRate ?? defaultGstRate).toString());
      gst += ((line.lineTotal * rate) / hundred).toDecimal().round();
      final fee = line.service.platformFee ?? defaultPlatformFee;
      if (maxFee == null || fee > maxFee) maxFee = fee;
    }
    final fee = (itemTotal > Decimal.zero) ? (maxFee ?? Decimal.zero) : Decimal.zero;
    return ServiceFare(itemTotal: itemTotal, gst: gst, platformFee: fee);
  }
}
