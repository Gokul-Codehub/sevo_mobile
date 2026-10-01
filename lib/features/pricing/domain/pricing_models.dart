import 'package:decimal/decimal.dart';

/// Admin-configurable pricing shown in checkout and the grocery cart.
///
/// Added 2026-10-01 per explicit request ("The Tax fixing Platform fee
/// and free delivery cost should be fix by the admin not the hard
/// coded... please be give access to customer admin to fix those inside
/// setting module that should be change dynamically"). These values
/// used to be hardcoded directly in checkout_screen.dart and
/// cart_notifier.dart — now they're read from the backend's
/// PricingConfigAPIView (GET /api/settings/pricing/), which the admin
/// panel's new Settings > Pricing section edits.
class PricingConfig {
  const PricingConfig({
    required this.platformFee,
    required this.gstPercent,
    required this.minAdvancePercent,
    required this.minAdvanceAmount,
    required this.deliveryFee,
    required this.freeDeliveryThreshold,
    required this.handlingFee,
    required this.smallCartFee,
    required this.smallCartThreshold,
  });

  final Decimal platformFee;
  final Decimal gstPercent;
  final Decimal minAdvancePercent;
  final Decimal minAdvanceAmount;
  final Decimal deliveryFee;
  final Decimal freeDeliveryThreshold;
  final Decimal handlingFee;
  final Decimal smallCartFee;
  final Decimal smallCartThreshold;

  /// Exactly the values that used to be hardcoded in the app. Used as the
  /// starting state before the real config has loaded, and again if that
  /// fetch ever fails, so pricing never shows as zero or breaks checkout —
  /// same "never hard-block, always have a safe default" approach already
  /// used for location_gate.dart.
  static final PricingConfig fallback = PricingConfig(
    platformFee: Decimal.parse('49.00'),
    gstPercent: Decimal.parse('5.00'),
    minAdvancePercent: Decimal.parse('20.00'),
    minAdvanceAmount: Decimal.parse('149.00'),
    deliveryFee: Decimal.parse('15.00'),
    freeDeliveryThreshold: Decimal.parse('200.00'),
    handlingFee: Decimal.parse('2.00'),
    smallCartFee: Decimal.parse('5.00'),
    smallCartThreshold: Decimal.parse('100.00'),
  );

  factory PricingConfig.fromJson(Map<String, dynamic> json) {
    final fb = PricingConfig.fallback;
    Decimal pick(String key, Decimal fallbackValue) {
      final raw = json[key];
      if (raw == null) return fallbackValue;
      try {
        return Decimal.parse(raw.toString());
      } catch (_) {
        return fallbackValue;
      }
    }

    return PricingConfig(
      platformFee: pick('platform_fee', fb.platformFee),
      gstPercent: pick('gst_percent', fb.gstPercent),
      minAdvancePercent: pick('min_advance_percent', fb.minAdvancePercent),
      minAdvanceAmount: pick('min_advance_amount', fb.minAdvanceAmount),
      deliveryFee: pick('delivery_fee', fb.deliveryFee),
      freeDeliveryThreshold:
          pick('free_delivery_threshold', fb.freeDeliveryThreshold),
      handlingFee: pick('handling_fee', fb.handlingFee),
      smallCartFee: pick('small_cart_fee', fb.smallCartFee),
      smallCartThreshold: pick('small_cart_threshold', fb.smallCartThreshold),
    );
  }
}
