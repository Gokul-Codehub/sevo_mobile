import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import '../../../../core/utils/image_url_helper.dart';
import '../../../../core/utils/location_gate.dart';
import '../../../../routing/app_router.dart';
import '../../../../shared/theme/app_colors.dart';
import '../../../../shared/utils/app_toast.dart';
import '../../../../shared/widgets/app_remote_image.dart';
import '../../../addresses/domain/address_models.dart';
import '../../../addresses/domain/address_notifier.dart';
import '../../../auth/domain/auth_notifier.dart';
import '../../../logistics/domain/logistics_models.dart';
import '../../../home/domain/home_flow_mode.dart';
import '../../domain/booking_providers.dart';
import '../../domain/cart_notifier.dart';
import '../../../pricing/domain/pricing_providers.dart';
import '../../../catalog/data/marketplace_catalog_repository.dart';
import '../widgets/coupon_bottom_sheet.dart';

/// Added 2026-10-06 per explicit request ("Before checkout ask the user
/// to select the delivery option below [Quick delivery, Slot booking
/// (every day 6pm to 8pm)]"): the two delivery-timing choices a grocery
/// order can be placed with. [quick] = Instant Delivery — the next
/// available real slot for today. [scheduled] = Scheduled Delivery — a
/// customer-picked date (today + the next two days) and a real slot for
/// that date.
///
/// Corrected 2026-10-07 ("the slots for grocery/vegetale of should from
/// the seller hub-delivery slot as per the uploaded image"): both options
/// used to resolve to ONE hardcoded fixed window (quick = a fake "10-15
/// Min Express Delivery", scheduled = a fixed daily "6:00 PM - 8:00 PM")
/// with no connection to any real delivery capacity. Both now resolve to
/// a real `workforce_api.DeliverySlot` from the Vendor Seller Hub's own
/// admin-configured "Delivery Slots & Capacity" page (e.g. 09:00-11:00,
/// 11:00-13:00, 14:00-16:00, 16:00-18:00 for "Jeemangalam Hub" today),
/// fetched live via [marketplaceDeliverySlotsForDateProvider] — see that
/// provider's doc comment for the full proxy chain.
enum _DeliveryOption { quick, scheduled }

/// The next 3 calendar dates (today + 2) a customer can pick a Scheduled
/// delivery slot for — "List 3 dates with slots which is getting from the
/// vendor application - seller hub - delivery slots".
List<DateTime> _nextThreeDeliveryDates() {
  final today = DateTime.now();
  final base = DateTime(today.year, today.month, today.day);
  return [base, base.add(const Duration(days: 1)), base.add(const Duration(days: 2))];
}

/// Authoritative Quick Commerce Grocery Cart & Checkout Screen matching calservices_web.
class GroceryCartScreen extends ConsumerStatefulWidget {
  const GroceryCartScreen({super.key});

  @override
  ConsumerState<GroceryCartScreen> createState() => _GroceryCartScreenState();
}

class _GroceryCartScreenState extends ConsumerState<GroceryCartScreen> {
  Address? _selectedAddress;
  bool _isSubmitting = false;
  String? _errorMessage;
  bool _isCustomTipOpen = false;
  final TextEditingController _customTipController = TextEditingController();
  // Added 2026-10-07 ("the promp/coupons model is not showing up"): this
  // whole grocery checkout flow never had ANY coupon entry point at all —
  // [_handlePlaceOrder] below creates the booking directly from this
  // screen without ever routing through checkout_screen.dart (the
  // scheduled-service booking flow's own checkout), which was the only
  // screen with a working Apply Coupon box. There is no separate
  // "coupon_code" field on the booking API — exactly like
  // checkout_screen.dart's own `_openCouponSheet`/`_couponDiscountAmount`,
  // the discount is applied by folding it into the lower `totalAmount`
  // this screen already sends to `createBooking`, never by telling the
  // backend which coupon was used.
  String? _appliedCouponCode;
  int _couponDiscountAmount = 0;
  // Null until the customer actually picks one — Proceed to Pay opens the
  // picker instead of placing the order whenever this is still null, so a
  // delivery option is always explicitly chosen before checkout, never
  // silently defaulted.
  _DeliveryOption? _deliveryOption;
  // The real Seller Hub DeliverySlot the picker resolved — for [quick]
  // this is the earliest available slot for today; for [scheduled] it's
  // whichever slot the customer tapped for [_selectedSlotDate]. Both are
  // set together, only on a successful "Confirm" in the picker sheet.
  DeliverySlotOption? _selectedSlot;
  String? _selectedSlotDate;
  // Date currently shown in the inline slot card (defaults to today).
  DateTime? _inlineSlotDate;
  // Added 2026-10-08 ("here also show the payment setting whether online
  // or cash on delivery" — grocery orders had no payment-method UI at all,
  // unlike the home-service checkout_screen.dart flow which already got
  // this on 2026-10-08 for QA CME02. [_handlePlaceOrder] below creates the
  // booking directly from THIS screen without ever routing through
  // checkout_screen.dart (see the coupon comment on `_appliedCouponCode`
  // above for why), so that earlier fix never reached grocery orders —
  // every one was silently COD regardless of what the customer might have
  // wanted. Defaults to 'COD' so behaviour for anyone who never touches
  // this selector is unchanged.
  String _paymentMethod = 'COD';

  @override
  void initState() {
    super.initState();
    // Added 2026-09-19: prompt to turn on device location right as the
    // customer opens their grocery cart/checkout — see
    // location_gate.dart's doc comment.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ensureLocationEnabled(context);
    });
    // Fixed 2026-10-06 ("set the minimum order in the admin page it does
    // not change the visual in the cart and it does not perform as per
    // the setting"): PricingConfigNotifier only ever fetches the live
    // admin-set values once, the moment the app process starts (see
    // pricing_providers.dart's build()) — it never refetches after that.
    // The admin Settings > Pricing page's own "How this reaches the app"
    // banner explicitly promises "The customer app fetches these values
    // when a customer opens checkout or the grocery cart", but nothing
    // actually called the `refreshNow()` it provides for exactly that —
    // so an admin's price change never reached an already-running app
    // until the customer force-quit and reopened it. Now the cart
    // actually re-fetches every time it's opened, matching that promise.
    ref.read(pricingConfigProvider.notifier).refreshNow();
  }

  @override
  void dispose() {
    _customTipController.dispose();
    super.dispose();
  }

  /// Opens the real [CouponBottomSheet] (live coupons from the backend,
  /// "No coupons available right now." when there are none) and applies
  /// whatever it returns — mirrors checkout_screen.dart's own
  /// `_openCouponSheet` exactly, since that's the screen this flow never
  /// shared a coupon mechanism with.
  Future<void> _openCouponSheet() async {
    final cartTotalForCoupon = ref.read(cartSummaryProvider).subtotal;
    final applied = await CouponBottomSheet.show(
      context,
      cartTotal: cartTotalForCoupon,
      currentCode: _appliedCouponCode,
    );

    if (applied != null && mounted) {
      setState(() {
        _appliedCouponCode = applied.code;
        _couponDiscountAmount = applied.discountAmount.toDouble().round();
      });
      if (mounted) {
        AppToast.show(
          context,
          'Coupon "${applied.code}" applied! Saved ₹$_couponDiscountAmount',
        );
      }
    }
  }

  /// `cartSummary.total` minus whatever coupon discount is currently
  /// applied, floored at zero — the single place both the displayed Grand
  /// Total/sticky bar amount and the real `totalAmount` sent to
  /// `createBooking` in [_handlePlaceOrder] derive the discounted figure
  /// from, so the two can never drift apart.
  Decimal _effectiveGrandTotal(CartSummary summary) {
    final discount = Decimal.fromInt(_couponDiscountAmount);
    return summary.total > discount ? summary.total - discount : Decimal.zero;
  }

  @override
  Widget build(BuildContext context) {
    final cartItems = ref.watch(cartProvider);
    final cartSummary = ref.watch(cartSummaryProvider);
    final selectedTip = ref.watch(deliveryTipProvider);
    final addressesAsync = ref.watch(addressListProvider);

    final addresses = addressesAsync.valueOrNull ?? const [];
    final activeAddress = _selectedAddress ??
        addresses.where((a) => a.isDefault).firstOrNull ??
        addresses.firstOrNull;

    if (cartItems.isEmpty) {
      // Fixed 2026-10-08 per explicit correction ("Grocery and services
      // cannot be the same cart at all... Even user inside the service
      // home page click the cart from footer that should be show only the
      // groceries list if user has added before or else show empty cart
      // browse groceries/vegetable to redirect to the grocery home page"):
      // this screen (route '/cart') is now ALWAYS the grocery cart —
      // services never enter `cartProvider` at all (they book directly via
      // Checkout, see service_detail_screen.dart/app_router.dart's matching
      // reverts) — so this empty state is always grocery-themed and always
      // sends "Explore" to the grocery/vegetable category, regardless of
      // which Home tab (Services/Groceries) the customer currently has
      // selected. Previously (2026-09-19 fix, now superseded) this themed
      // itself off Home's current flow mode because a service COULD still
      // land in this same cart back then — that's no longer possible.
      return Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          title: const Text('My Cart'),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 90,
                  height: 90,
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F766E).withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.shopping_basket_outlined,
                    size: 48,
                    color: Color(0xFF0F766E),
                  ),
                ),
                const SizedBox(height: 20),
                const Text(
                  'Your grocery cart is empty',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Add farm-fresh vegetables and daily essentials to get instant 10-15 min delivery.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    color: AppColors.textSecondary,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 28),
                FilledButton.icon(
                  onPressed: _goShopGroceries,
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF0F766E),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 28,
                      vertical: 14,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  icon: const Icon(Icons.eco_rounded, size: 18),
                  label: const Text(
                    'Explore Farm-Fresh Produce',
                    style: TextStyle(
                        fontSize: 14, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    // Fixed 2026-10-06: this used to be a literal '200.00', completely
    // independent of the admin-configurable PricingConfig — so this
    // banner's progress bar and "₹x/₹y" text kept showing the old
    // hardcoded ₹200 target no matter what the admin set Free Delivery
    // Threshold to in Settings > Pricing (cartSummary.deliveryFee itself,
    // down in Bill Details, was already correctly reading the real admin
    // value via cart_notifier.dart — only this banner had its own
    // disconnected copy of the number).
    final freeThreshold = ref.watch(pricingConfigProvider).freeDeliveryThreshold;
    final amountForFreeDelivery = cartSummary.subtotal < freeThreshold
        ? freeThreshold - cartSummary.subtotal
        : Decimal.zero;
    final progressFraction =
        (cartSummary.subtotal / freeThreshold).toDecimal().toDouble().clamp(0.0, 1.0);

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.textPrimary),
          onPressed: () {
            if (Navigator.of(context).canPop()) {
              Navigator.of(context).pop();
            } else {
              context.go('/');
            }
          },
        ),
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'My Cart',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w900,
                color: AppColors.textPrimary,
              ),
            ),
            Text(
              'Hosur Express Delivery',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            // IntrinsicWidth: an AppBar's actions render in a Row, which
            // hands non-Expanded children like this button an unbounded
            // width for sizing — the exact condition that made
            // FilledButton.icon's internal minimum-tap-target padding
            // throw "BoxConstraints forces an infinite width" on the
            // category screen's cart bar. Same button family, same risk
            // here, so it gets the same fix pre-emptively.
            child: IntrinsicWidth(
              child: OutlinedButton.icon(
                onPressed: () {
                  Share.share(
                    'Check out my CalServices fresh grocery cart with ${cartSummary.itemCount} items worth ₹${cartSummary.total}!',
                    subject: 'My CalServices Grocery Cart',
                  );
                },
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.textPrimary,
                  side: const BorderSide(color: AppColors.border),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  minimumSize: const Size(0, 32),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
                icon: const Icon(Icons.shopping_cart_outlined, size: 14),
                label: const Text(
                  'Share Cart',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_errorMessage != null) ...[
              Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: Colors.red.shade200),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline, color: Colors.red, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _errorMessage!,
                        style: TextStyle(
                          color: Colors.red.shade900,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            // ── Delivery address (moved up from the fixed bottom bar) ───────
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.border, width: 0.6),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.03),
                    blurRadius: 10,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: const Color(0xFFECFDF5),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.location_on_rounded,
                      size: 20,
                      color: Color(0xFF059669),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Delivering to ${activeAddress != null ? activeAddress.addressType : "Home"}',
                          style: const TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w800,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          activeAddress?.formattedAddress ?? 'Hosur, Tamil Nadu',
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.textSecondary,
                            height: 1.3,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton(
                    onPressed: () => _openAddressSheet(context, addresses),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.textPrimary,
                      side: const BorderSide(color: AppColors.border),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                      minimumSize: const Size(0, 32),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: const Text(
                      'Change',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),

            // ── Free Delivery Incentive Card ────────────────────────────────
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.border, width: 0.6),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.02),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          const Icon(
                            Icons.auto_awesome,
                            size: 14,
                            color: Color(0xFF059669),
                          ),
                          const SizedBox(width: 6),
                          if (cartSummary.subtotal >= freeThreshold)
                            const Text(
                              '🎉 You unlocked FREE delivery!',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFF059669),
                              ),
                            )
                          else
                            RichText(
                              text: TextSpan(
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: AppColors.textPrimary,
                                  fontWeight: FontWeight.bold,
                                ),
                                children: [
                                  const TextSpan(text: 'Add '),
                                  TextSpan(
                                    text: '₹$amountForFreeDelivery',
                                    style: const TextStyle(
                                      color: Color(0xFF059669),
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                  const TextSpan(text: ' more to get '),
                                  const TextSpan(
                                    text: 'FREE delivery',
                                    style: TextStyle(
                                      color: Color(0xFF059669),
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                      if (cartSummary.subtotal < freeThreshold)
                        Text(
                          '₹${cartSummary.subtotal}/₹$freeThreshold',
                          style: const TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.bold,
                            color: AppColors.textSecondary,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: progressFraction,
                      minHeight: 4,
                      backgroundColor: const Color(0xFFF1F5F9),
                      valueColor: const AlwaysStoppedAnimation<Color>(
                        Color(0xFF059669),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),

            // ── Cart Items List Card ─────────────────────────────────────────
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.border, width: 0.6),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.03),
                    blurRadius: 10,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                children: [
                  ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(14),
                    itemCount: cartItems.length,
                    separatorBuilder: (context, index) =>
                        const Divider(height: 20, color: AppColors.border),
                    itemBuilder: (context, index) {
                      final item = cartItems[index];
                      final effectivePrice = item.service.effectivePrice;
                      final mrp = item.service.mrp;

                      // Tapping the image or details opens that product's own
                      // page (same route the product cards use).
                      void openProduct() {
                        final slug = item.service.slug.isNotEmpty
                            ? item.service.slug
                            : 'svc-${item.service.id}';
                        context.push(
                          '/products/${Uri.encodeComponent(slug)}',
                          extra: item.service,
                        );
                      }

                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Expanded(
                            child: InkWell(
                              onTap: openProduct,
                              borderRadius: BorderRadius.circular(8),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                          // Thumbnail
                          Container(
                            width: 58,
                            height: 58,
                            decoration: BoxDecoration(
                              color: AppColors.surfaceVariant,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            clipBehavior: Clip.antiAlias,
                            // Fixed 2026-10-07 ("Images are not showing
                            // inside cart"): `title` was never passed here,
                            // which was one real bug — but STILL showed the
                            // generic icon afterward for Seller Hub
                            // Marketplace / Grocery Hub items (e.g. "Red
                            // Banana") because of a second one: this passed
                            // `item.service.categoryName` (the raw vendor
                            // category label, e.g. "Fruits") as the grocery
                            // signal, but ImageUrlHelper's grocery check is
                            // a bare `contains('veg') || contains('groc')`
                            // substring match — "Fruits", "Dairy", "Chips &
                            // Namkeen" etc. never match it. `categoryId`
                            // doesn't help either: MarketplaceProduct.
                            // toServiceItem() / GroceryHubProduct.
                            // toServiceItem() never set it at all. Every
                            // grocery source instead force-sets
                            // `categorySlug` to literally contain
                            // "vegetable"/"grocery" for exactly this
                            // reason (see those two toServiceItem() doc
                            // comments) — using THAT here instead, the same
                            // fix already applied to the Home screen's
                            // "Book Again" tile, makes the grocery signal
                            // reliable regardless of the vendor's own
                            // category naming.
                            child: AppRemoteImage(
                              imageUrl: item.service.imageUrl,
                              rawPath: item.service.imageUrl,
                              title: item.service.title,
                              categoryName: item.service.categorySlug,
                              categoryId: item.service.categoryId,
                              slug: item.service.categorySlug,
                              semanticIcon: ImageUrlHelper.mapCategoryIcon(
                                  item.service.categorySlug, item.service.categorySlug),
                              width: 58,
                              height: 58,
                              fit: BoxFit.cover,
                            ),
                          ),
                          const SizedBox(width: 12),

                          // Details
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  item.service.title,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 13.5,
                                    color: AppColors.textPrimary,
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 3),
                                // "500 g • ₹90.00" — pack size and unit price.
                                Text(
                                  [
                                    if ((item.service.unit ?? '').trim().isNotEmpty)
                                      item.service.unit!.trim(),
                                    '₹${effectivePrice.toStringAsFixed(2)}',
                                  ].join(' • '),
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                const Text(
                                  'Seller: SevoGrocery',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.textPrimary,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                // Line total for this quantity.
                                Row(
                                  children: [
                                    Text(
                                      '₹${item.totalPrice}',
                                      style: const TextStyle(
                                        fontSize: 14.5,
                                        fontWeight: FontWeight.w900,
                                        color: AppColors.textPrimary,
                                      ),
                                    ),
                                    if (mrp > effectivePrice) ...[
                                      const SizedBox(width: 6),
                                      Text(
                                        '₹${mrp * Decimal.fromInt(item.quantity)}',
                                        style: const TextStyle(
                                          fontSize: 11.5,
                                          color: AppColors.textSecondary,
                                          decoration: TextDecoration.lineThrough,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ],
                            ),
                          ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),

                          // Quantity Stepper matching Web
                          Container(
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: AppColors.border,
                                width: 1,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                InkWell(
                                  onTap: () {
                                    ref
                                        .read(cartProvider.notifier)
                                        .updateQuantity(
                                          item.service.id,
                                          item.quantity - 1,
                                        );
                                  },
                                  borderRadius: const BorderRadius.horizontal(
                                    left: Radius.circular(6),
                                  ),
                                  child: const Padding(
                                    padding: EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 6,
                                    ),
                                    child: Icon(
                                      Icons.remove,
                                      size: 14,
                                      color: AppColors.textSecondary,
                                    ),
                                  ),
                                ),
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                  ),
                                  child: Text(
                                    '${item.quantity}',
                                    style: const TextStyle(
                                      color: AppColors.textPrimary,
                                      fontWeight: FontWeight.w900,
                                      fontSize: 12.5,
                                    ),
                                  ),
                                ),
                                InkWell(
                                  onTap: () {
                                    ref.read(cartProvider.notifier).addService(
                                          item.service,
                                        );
                                    // Fixed 2026-09-18 per explicit request
                                    // ("the message popped up only for the
                                    // first, if count increases that also
                                    // should be popping out"): bumping the
                                    // quantity of an already-in-cart item
                                    // is still adding to the cart — it just
                                    // didn't have its own confirmation yet.
                                    AppToast.addedToCart(
                                        context, item.service.title);
                                  },
                                  borderRadius: const BorderRadius.horizontal(
                                    right: Radius.circular(6),
                                  ),
                                  child: const Padding(
                                    padding: EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 6,
                                    ),
                                    child: Icon(
                                      Icons.add,
                                      size: 14,
                                      color: Color(0xFF059669),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      );
                    },
                  ),

                  const Divider(height: 1, color: AppColors.border),
                  InkWell(
                    onTap: () {
                      // Back to the Groceries home to keep shopping.
                      _goShopGroceries();
                    },
                    borderRadius: const BorderRadius.vertical(
                        bottom: Radius.circular(8)),
                    child: const Padding(
                      padding: EdgeInsets.symmetric(vertical: 13),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.add_circle_outline_rounded,
                              size: 16, color: Color(0xFF0F766E)),
                          SizedBox(width: 6),
                          Text(
                            'Add More Farm Produce',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF0F766E),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),

            // ── Delivery slot card (inline, always visible) ──────────────────
            _buildDeliverySlotCard(context),
            const SizedBox(height: 14),

            // ── Payment method (moved up from the fixed bottom bar) ──────────
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.border, width: 0.6),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.03),
                    blurRadius: 10,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.account_balance_wallet_outlined,
                          size: 18, color: AppColors.textPrimary),
                      SizedBox(width: 8),
                      Text(
                        'Payment method',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _GroceryPaymentMethodOption(
                          label: 'Cash on Delivery',
                          subtitle: 'Cash / UPI on arrival',
                          icon: Icons.payments_outlined,
                          selected: _paymentMethod == 'COD',
                          onTap: () => setState(() => _paymentMethod = 'COD'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _GroceryPaymentMethodOption(
                          label: 'Pay Online',
                          subtitle: 'Card / UPI / Wallet now',
                          icon: Icons.account_balance_wallet_outlined,
                          selected: _paymentMethod == 'ONLINE',
                          onTap: () => setState(() => _paymentMethod = 'ONLINE'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),

            // ── Bill Details Card (Matching Web Reference) ───────────────────
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.border, width: 0.6),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.03),
                    blurRadius: 10,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Bill Details',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 14),

                  // Items total
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.description_outlined,
                              size: 15, color: AppColors.textSecondary),
                          const SizedBox(width: 6),
                          const Text(
                            'Items total',
                            style: TextStyle(
                              fontSize: 12.5,
                              color: AppColors.textPrimary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          if (cartSummary.totalSavings > Decimal.zero) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 1.5,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFFECFDF5),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                  color: const Color(0xFFA7F3D0),
                                  width: 0.8,
                                ),
                              ),
                              child: Text(
                                'Saved ₹${cartSummary.totalSavings}',
                                style: const TextStyle(
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.w800,
                                  color: Color(0xFF047857),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      Row(
                        children: [
                          if (cartSummary.totalSavings > Decimal.zero) ...[
                            Text(
                              '₹${cartSummary.originalTotal}',
                              style: const TextStyle(
                                fontSize: 11.5,
                                color: AppColors.textSecondary,
                                decoration: TextDecoration.lineThrough,
                              ),
                            ),
                            const SizedBox(width: 6),
                          ],
                          Text(
                            '₹${cartSummary.subtotal}',
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                              color: AppColors.textPrimary,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),

                  // Delivery charge
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.local_shipping_outlined,
                              size: 15, color: AppColors.textSecondary),
                          SizedBox(width: 6),
                          Text(
                            'Delivery charge',
                            style: TextStyle(
                              fontSize: 12.5,
                              color: AppColors.textPrimary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          SizedBox(width: 4),
                          Icon(Icons.info_outline,
                              size: 13, color: AppColors.textSecondary),
                        ],
                      ),
                      Text(
                        cartSummary.deliveryFee == Decimal.zero
                            ? 'FREE'
                            : '₹${cartSummary.deliveryFee}',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: cartSummary.deliveryFee == Decimal.zero
                              ? const Color(0xFF059669)
                              : AppColors.textPrimary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),

                  // Handling & packaging
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.inventory_2_outlined,
                              size: 15, color: AppColors.textSecondary),
                          SizedBox(width: 6),
                          Text(
                            'Handling & packaging',
                            style: TextStyle(
                              fontSize: 12.5,
                              color: AppColors.textPrimary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          SizedBox(width: 4),
                          Icon(Icons.info_outline,
                              size: 13, color: AppColors.textSecondary),
                        ],
                      ),
                      Text(
                        '₹${cartSummary.handlingFee}',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ],
                  ),

                  // Small cart fee (if applicable)
                  if (cartSummary.smallCartFee > Decimal.zero) ...[
                    const SizedBox(height: 10),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.shopping_bag_outlined,
                                size: 15, color: AppColors.textSecondary),
                            SizedBox(width: 6),
                            Text(
                              'Small cart fee',
                              style: TextStyle(
                                fontSize: 12.5,
                                color: AppColors.textPrimary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            SizedBox(width: 4),
                            Icon(Icons.info_outline,
                                size: 13, color: AppColors.textSecondary),
                          ],
                        ),
                        Text(
                          '₹${cartSummary.smallCartFee}',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ],
                    ),
                  ],

                  if (selectedTip > Decimal.zero) ...[
                    const SizedBox(height: 10),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.volunteer_activism_outlined,
                                size: 15, color: AppColors.textSecondary),
                            SizedBox(width: 6),
                            Text(
                              'Rider Tip',
                              style: TextStyle(
                                fontSize: 12.5,
                                color: AppColors.textPrimary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                        Text(
                          '₹$selectedTip',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ],
                    ),
                  ],

                  const SizedBox(height: 10),

                  // ── Apply Coupon / Promo Code ──
                  // Added 2026-10-07 — see the doc comment on
                  // `_appliedCouponCode` above for why this didn't exist
                  // here at all until now.
                  InkWell(
                    onTap: _openCouponSheet,
                    borderRadius: BorderRadius.circular(6),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.discount_outlined,
                              size: 15,
                              color: _appliedCouponCode != null
                                  ? AppColors.primary
                                  : AppColors.textSecondary,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              _appliedCouponCode != null
                                  ? 'Coupon: $_appliedCouponCode'
                                  : 'Apply Coupon / Promo Code',
                              style: TextStyle(
                                fontSize: 12.5,
                                color: _appliedCouponCode != null
                                    ? AppColors.primary
                                    : AppColors.textPrimary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                        const Icon(
                          Icons.chevron_right_rounded,
                          size: 18,
                          color: AppColors.textHint,
                        ),
                      ],
                    ),
                  ),

                  if (_couponDiscountAmount > 0) ...[
                    const SizedBox(height: 10),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.local_offer_outlined,
                                size: 15, color: Color(0xFF059669)),
                            const SizedBox(width: 6),
                            Text(
                              'Coupon Discount ($_appliedCouponCode)',
                              style: const TextStyle(
                                fontSize: 12.5,
                                color: Color(0xFF059669),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                        Text(
                          '-₹$_couponDiscountAmount',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF059669),
                          ),
                        ),
                      ],
                    ),
                  ],

                  const Divider(height: 22, color: AppColors.border),

                  // Grand Total
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Grand Total',
                        style: TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w900,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      Text(
                        '₹${_effectiveGrandTotal(cartSummary)}',
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w900,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),

            // ── Support Your Delivery Partner (Tips matching web) ────────────
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.border, width: 0.6),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.03),
                    blurRadius: 10,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Support your delivery partner',
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  const Text(
                    'Add a tip to show appreciation. 100% of the tip goes directly to your rider.',
                    style: TextStyle(
                      fontSize: 11.5,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _buildTipCard(
                          label: '₹20',
                          desc: 'Say Thanks',
                          isSelected: selectedTip == Decimal.parse('20'),
                          onTap: () {
                            ref.read(deliveryTipProvider.notifier).setTip(
                                  selectedTip == Decimal.parse('20')
                                      ? Decimal.zero
                                      : Decimal.parse('20'),
                                );
                            setState(() => _isCustomTipOpen = false);
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _buildTipCard(
                          label: '₹30',
                          desc: 'Buy a Chai',
                          isSelected: selectedTip == Decimal.parse('30'),
                          onTap: () {
                            ref.read(deliveryTipProvider.notifier).setTip(
                                  selectedTip == Decimal.parse('30')
                                      ? Decimal.zero
                                      : Decimal.parse('30'),
                                );
                            setState(() => _isCustomTipOpen = false);
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _buildTipCard(
                          label: '₹50',
                          desc: 'Show Love',
                          isSelected: selectedTip == Decimal.parse('50'),
                          onTap: () {
                            ref.read(deliveryTipProvider.notifier).setTip(
                                  selectedTip == Decimal.parse('50')
                                      ? Decimal.zero
                                      : Decimal.parse('50'),
                                );
                            setState(() => _isCustomTipOpen = false);
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _buildTipCard(
                          label: 'Custom',
                          desc: 'Other',
                          isSelected: _isCustomTipOpen,
                          onTap: () {
                            setState(() {
                              _isCustomTipOpen = !_isCustomTipOpen;
                              if (!_isCustomTipOpen) {
                                ref
                                    .read(deliveryTipProvider.notifier)
                                    .setTip(Decimal.zero);
                              }
                            });
                          },
                        ),
                      ),
                    ],
                  ),
                  if (_isCustomTipOpen) ...[
                    const SizedBox(height: 10),
                    TextField(
                      controller: _customTipController,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        hintText: 'Enter custom tip amount (₹)',
                        hintStyle: const TextStyle(fontSize: 12),
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(6),
                          borderSide: const BorderSide(color: AppColors.border),
                        ),
                      ),
                      onChanged: (val) {
                        final parsed = Decimal.tryParse(val) ?? Decimal.zero;
                        ref.read(deliveryTipProvider.notifier).setTip(parsed);
                      },
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 14),

            // ── Cancellation Policy Card ─────────────────────────────────────
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.border, width: 0.6),
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Cancellation Policy',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'Orders cannot be cancelled once packed for delivery. In case of unexpected delays, a refund will be provided, if applicable.',
                    style: TextStyle(
                      fontSize: 11,
                      color: AppColors.textSecondary,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),

      // ── Fixed Bottom Bar Matching Uploaded Reference ────────────────────────
      bottomNavigationBar: Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        decoration: BoxDecoration(
          color: Colors.white,
          border: const Border(
            top: BorderSide(color: AppColors.divider, width: 0.5),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 10,
              offset: const Offset(0, -3),
            ),
          ],
        ),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Big Green Proceed To Pay Button
              SizedBox(
                width: double.infinity,
                height: 52,
                child: FilledButton(
                  onPressed: _isSubmitting
                      ? null
                      : () => _onProceedToPayTapped(context, activeAddress),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF059669),
                    disabledBackgroundColor:
                        const Color(0xFF059669).withValues(alpha: 0.5),
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '₹${_effectiveGrandTotal(cartSummary)}',
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                              color: Colors.white,
                              height: 1.1,
                            ),
                          ),
                          const Text(
                            'TOTAL AMOUNT',
                            style: TextStyle(
                              fontSize: 8.5,
                              fontWeight: FontWeight.w900,
                              color: Colors.white70,
                              letterSpacing: 0.8,
                            ),
                          ),
                        ],
                      ),
                      Row(
                        children: [
                          Text(
                            _isSubmitting ? 'Placing Order...' : 'Proceed to Pay',
                            style: const TextStyle(
                              fontSize: 14.5,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(width: 4),
                          const Icon(
                            Icons.chevron_right,
                            color: Colors.white,
                            size: 20,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTipCard({
    required String label,
    required String desc,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? const Color(0xFF0F172A) : AppColors.border,
            width: 1,
          ),
        ),
        child: Column(
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: isSelected ? Colors.white : AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              desc,
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w600,
                color: isSelected ? Colors.white70 : AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }


  /// Takes the customer to the Groceries home page to shop (the old
  /// /categories/vegetables_groceries route now lands on "No Produce Found").
  void _goShopGroceries() {
    ref.read(homeFlowModeProvider.notifier).state = HomeFlowMode.groceries;
    context.go(AppRoutes.home);
  }

  void _openAddressSheet(BuildContext context, List<Address> addresses) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(8)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Select Delivery Address',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 12),
              if (addresses.isEmpty)
                ListTile(
                  leading: const Icon(Icons.add_location_alt_rounded),
                  title: const Text('Add New Address'),
                  onTap: () {
                    Navigator.pop(ctx);
                    context.push('/addresses/add');
                  },
                )
              else
                ...addresses.map(
                  (addr) => ListTile(
                    leading: Icon(
                      addr.addressType.toLowerCase().contains('work')
                          ? Icons.work_outline
                          : Icons.home_outlined,
                      color: const Color(0xFF0F766E),
                    ),
                    title: Text(
                      addr.addressType.toUpperCase(),
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Text(addr.formattedAddress),
                    onTap: () {
                      setState(() => _selectedAddress = addr);
                      Navigator.pop(ctx);
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// Always-visible delivery slot picker (shown in the cart body, above
  /// Bill Details) — the same real Seller Hub slots the bottom-bar sheet
  /// offers, but surfaced inline so the customer sees them without having
  /// to discover a hidden "Choose" button. Writes straight into
  /// [_deliveryOption]/[_selectedSlot]/[_selectedSlotDate].
  Widget _buildDeliverySlotCard(BuildContext context) {
    final dates = _nextThreeDeliveryDates();
    final pickedDate = _inlineSlotDate ?? dates.first;
    final pickedStr = _formatDateForBooking(pickedDate);
    final todayStr = _formatDateForBooking(dates.first);

    Widget label(String t) => Text(
          t,
          style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: AppColors.textSecondary),
        );

    Widget retry(String date) => Row(
          children: [
            const Expanded(
              child: Text(
                'Could not load delivery slots.',
                style: TextStyle(fontSize: 11.5, color: AppColors.error),
              ),
            ),
            TextButton(
              onPressed: () => ref.invalidate(marketplaceDeliverySlotsForDateProvider(date)),
              child: const Text('Retry', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
            ),
          ],
        );

    final todayAsync = ref.watch(marketplaceDeliverySlotsForDateProvider(todayStr));
    final slotsAsync = ref.watch(marketplaceDeliverySlotsForDateProvider(pickedStr));

    // Earliest still-upcoming, available slot today -> "Instant" delivery.
    DeliverySlotOption? instantSlot;
    todayAsync.whenData((day) {
      for (final s in day.slots) {
        if (s.isAvailable && !_isSlotPast(dates.first, s)) {
          instantSlot = s;
          break;
        }
      }
    });
    final instant = instantSlot;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border, width: 0.6),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 10, offset: const Offset(0, 2)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: const [
              Icon(Icons.schedule_outlined, size: 18, color: AppColors.textPrimary),
              SizedBox(width: 8),
              Text(
                'Delivery slot',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.textPrimary),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _DeliveryOptionTile(
            icon: Icons.bolt_outlined,
            title: 'Instant Delivery',
            subtitle: todayAsync.isLoading
                ? 'Checking next available slot…'
                : instant != null
                    ? 'Today, ${_slotTimeRangeLabel(instant)}'
                    : 'No slot left today — choose a scheduled slot',
            isSelected: _deliveryOption == _DeliveryOption.quick,
            onTap: () {
              if (instant == null) {
                AppToast.show(
                  context,
                  'No delivery slots are available today. Please pick a scheduled slot.',
                  type: AppToastType.error,
                );
                return;
              }
              setState(() {
                _deliveryOption = _DeliveryOption.quick;
                _selectedSlot = instant;
                _selectedSlotDate = todayStr;
              });
            },
          ),
          const SizedBox(height: 14),
          label('Or schedule — pick a date'),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: dates.map((date) {
              final isPicked = date.year == pickedDate.year &&
                  date.month == pickedDate.month &&
                  date.day == pickedDate.day;
              return _SlotChip(
                label: _describeSlotDate(date),
                isSelected: isPicked,
                onTap: () => setState(() => _inlineSlotDate = date),
              );
            }).toList(),
          ),
          const SizedBox(height: 12),
          label('Available slots'),
          const SizedBox(height: 8),
          slotsAsync.when(
            data: (day) {
              if (day.failed) return retry(pickedStr);
              final visible = day.slots.where((s) => !_isSlotPast(pickedDate, s)).toList();
              if (visible.isEmpty) {
                return const Text(
                  'No delivery slots available for this date.',
                  style: TextStyle(fontSize: 11.5, color: AppColors.textSecondary),
                );
              }
              return Wrap(
                spacing: 8,
                runSpacing: 8,
                children: visible.map((slot) {
                  final selected = _deliveryOption == _DeliveryOption.scheduled &&
                      _selectedSlotDate == pickedStr &&
                      _selectedSlot?.id == slot.id;
                  return _SlotChip(
                    label: slot.label.isNotEmpty
                        ? '${slot.label} · ${_slotTimeRangeLabel(slot)}'
                        : _slotTimeRangeLabel(slot),
                    isSelected: selected,
                    isDisabled: !slot.isAvailable,
                    onTap: slot.isAvailable
                        ? () => setState(() {
                              _deliveryOption = _DeliveryOption.scheduled;
                              _selectedSlot = slot;
                              _selectedSlotDate = pickedStr;
                            })
                        : null,
                  );
                }).toList(),
              );
            },
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2)),
            ),
            error: (_, __) => retry(pickedStr),
          ),
        ],
      ),
    );
  }

  /// "Today" / "Tomorrow" / "Mon D" for one of [_nextThreeDeliveryDates] —
  /// replacing the old fixed "every day 6pm-8pm" framing now that the
  /// customer actually picks among real, separately-dated slot lists.
  String _describeSlotDate(DateTime date) {
    final today = DateTime.now();
    final base = DateTime(today.year, today.month, today.day);
    final target = DateTime(date.year, date.month, date.day);
    final diff = target.difference(base).inDays;
    if (diff == 0) return 'Today';
    if (diff == 1) return 'Tomorrow';
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${months[date.month - 1]} ${date.day}';
  }

  String _formatDateForBooking(DateTime date) =>
      '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

  /// "09:00" -> "9:00 AM" — the Vendor Seller Hub stores slot times as
  /// plain 24-hour strings; this is purely a display formatter, the raw
  /// "HH:MM" strings are still what's sent to [TimeSlot] for booking.
  String _formatTimeLabel(String hhmm) {
    final parts = hhmm.split(':');
    if (parts.length < 2) return hhmm;
    var hour = int.tryParse(parts[0]) ?? 0;
    final minute = parts[1].padLeft(2, '0');
    final period = hour >= 12 ? 'PM' : 'AM';
    hour = hour % 12;
    if (hour == 0) hour = 12;
    return '$hour:$minute $period';
  }

  String _slotTimeRangeLabel(DeliverySlotOption slot) =>
      '${_formatTimeLabel(slot.startTime)} - ${_formatTimeLabel(slot.endTime)}';

  /// Fixed 2026-10-07 ("in at scheduled delivery the past time slots also
  /// showing"): `DeliverySlotOption.isAvailable` only reflects the Seller
  /// Hub's configured capacity/cutoff for the slot in general — it does
  /// NOT know the customer's current wall-clock time, so a 09:00-11:00
  /// slot for "Today" still came back `available: true` from the backend
  /// at 2pm.
  ///
  /// Fixed 2026-10-08 ("across the slot that should show the very next
  /// slot" — at 11:24 the 11:00-12:00 slot was still offered and
  /// selectable even though it had already started): the original fix
  /// above only dropped a slot once its END time had elapsed, so a slot
  /// already in progress (start <= now < end) stayed selectable — the
  /// customer could "schedule" a delivery for a window that was already
  /// half over. A slot now counts as past once its START time has
  /// elapsed, so only slots that haven't begun yet — starting with the
  /// very next upcoming one — are offered. Slots for any other date are
  /// never touched.
  bool _isSlotPast(DateTime date, DeliverySlotOption slot) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final target = DateTime(date.year, date.month, date.day);
    if (target != today) return false;
    final parts = slot.startTime.split(':');
    if (parts.length < 2) return false;
    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);
    if (hour == null || minute == null) return false;
    final slotStart = DateTime(now.year, now.month, now.day, hour, minute);
    return !slotStart.isAfter(now);
  }

  /// Gates "Proceed to Pay": a delivery option must be explicitly chosen
  /// first (per "Before checkout ask the user to select the delivery
  /// option"), so this opens the picker instead of placing the order
  /// whenever none has been chosen yet, and only calls through to
  /// [_handlePlaceOrder] once one has.
  void _onProceedToPayTapped(BuildContext context, Address? activeAddress) {
    if (_deliveryOption == null || _selectedSlot == null) {
      // The delivery slot card is on this page — point the customer at it
      // instead of opening a second picker.
      AppToast.show(
        context,
        'Please choose a delivery slot first (Instant or a scheduled slot).',
        type: AppToastType.error,
      );
      return;
    }
    _handlePlaceOrder(context, ref, activeAddress);
  }

  Future<void> _handlePlaceOrder(
    BuildContext context,
    WidgetRef ref,
    Address? activeAddress,
  ) async {
    final cartItems = ref.read(cartProvider);

    if (cartItems.isEmpty) return;

    final isAuthenticated = ref.read(isUserAuthenticatedProvider);
    if (!isAuthenticated) {
      ref.read(pendingActionProvider.notifier).setAction(
            PendingCartAction(
              service: cartItems.first.service,
              actionType: PendingCartActionType.buy,
              quantity: cartItems.first.quantity,
              returnPath: AppRoutes.cart,
            ),
          );
      context.push(AppRoutes.login);
      return;
    }

    if (activeAddress != null) {
      ref.read(selectedAddressProvider.notifier).state = activeAddress;
    }

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    try {
      // Fixed 2026-10-07 ("the slots for grocery/vegetale of should from
      // the seller hub-delivery slot as per the uploaded image"): every
      // grocery order used to submit a hardcoded window (a fake "10-15
      // Min Express Delivery" or a fixed daily "6:00 PM - 8:00 PM") with
      // no connection to any real delivery capacity. Now it submits
      // whichever REAL Seller Hub DeliverySlot the picker resolved
      // (_openDeliveryOptionSheet, above) for either option.
      // `_selectedSlot`/`_selectedSlotDate` defaulting here too is just a
      // defensive fallback — _onProceedToPayTapped never reaches this
      // call with either still null.
      final slotDateStr = _selectedSlotDate ?? _formatDateForBooking(DateTime.now());
      final chosenSlot = _selectedSlot;
      final slot = chosenSlot != null
          ? TimeSlot(
              id: 'seller_hub_slot_${chosenSlot.id}_$slotDateStr',
              date: slotDateStr,
              startTime: chosenSlot.startTime,
              endTime: chosenSlot.endTime,
              label: chosenSlot.label.isNotEmpty
                  ? chosenSlot.label
                  : _slotTimeRangeLabel(chosenSlot),
            )
          : TimeSlot(
              id: 'express_${DateTime.now().millisecondsSinceEpoch}',
              date: slotDateStr,
              startTime: '10:00',
              endTime: '10:15',
              label: '10-15 Min Express Delivery',
            );

      final result = await ref
          .read(bookingActionControllerProvider.notifier)
          .createBooking(
            date: slotDateStr,
            slot: slot,
            specialInstructions: 'Quick Commerce Vegetable Order',
            contactPhone: ref.read(currentUserProvider)?.phone,
            // Fixed 2026-10-07: now sends the coupon-discounted total (see
            // `_effectiveGrandTotal`) instead of the full `cartSummary.total`
            // — otherwise an applied coupon would show correctly in the
            // Bill Details card above but the customer would still be
            // charged the full, undiscounted amount at the actual booking
            // step, which is the one place that matters.
            totalAmount: _effectiveGrandTotal(ref.read(cartSummaryProvider)),
            paymentMethod: _paymentMethod,
          );

      if (!context.mounted) return;

      if (result.error != null) {
        if (mounted) {
          setState(() => _errorMessage = result.error);
        }
        AppToast.show(context, result.error!, type: AppToastType.error);
      } else if (result.booking != null) {
        AppToast.bookingSuccessful(context);
        context.go(
          '/bookings/success/${result.booking!.id}',
          extra: result.booking,
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _errorMessage = e.toString());
      }
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }
}

/// A single selectable row in [_GroceryCartScreenState._openDeliveryOptionSheet]
/// — same selected/unselected visual language as
/// [_GroceryCartScreenState._buildTipCard] (navy fill when selected,
/// light surface otherwise), just icon + title + subtitle instead of a
/// label + amount, since each delivery option needs a one-line
/// explanation of what it actually means.
class _DeliveryOptionTile extends StatelessWidget {
  const _DeliveryOptionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.isSelected,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? const Color(0xFF0F172A) : AppColors.border,
            width: 1,
          ),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 20,
              color: isSelected ? Colors.white : AppColors.textSecondary,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w800,
                      color: isSelected ? Colors.white : AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: isSelected ? Colors.white70 : AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            if (isSelected)
              const Icon(Icons.check_circle, color: Colors.white, size: 20),
          ],
        ),
      ),
    );
  }
}

/// A small selectable pill used for the 3-day date picker and the real
/// delivery-slot list in
/// [_GroceryCartScreenState._openDeliveryOptionSheet] — unlike
/// [_DeliveryOptionTile] (a full-width row for the two top-level delivery
/// options), dates and slots are shown as compact chips since there can
/// be several of them side by side (one per real
/// `workforce_api.DeliverySlot` the Seller Hub admin has configured, e.g.
/// 09:00-11:00, 11:00-13:00, 14:00-16:00, 16:00-18:00). [isDisabled]
/// renders a slot whose capacity/cutoff has made it unavailable today
/// (per `PublicDeliverySlotsView`'s live `available` flag) as struck
/// through and untappable, rather than hiding it — the customer can see
/// it exists, just not right now.
class _SlotChip extends StatelessWidget {
  const _SlotChip({
    required this.label,
    required this.isSelected,
    this.isDisabled = false,
    this.onTap,
  });

  final String label;
  final bool isSelected;
  final bool isDisabled;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final background = isDisabled
        ? const Color(0xFFF1F5F9)
        : isSelected
            ? const Color(0xFF0F172A)
            : const Color(0xFFF8FAFC);
    final foreground = isDisabled
        ? AppColors.textSecondary
        : isSelected
            ? Colors.white
            : AppColors.textPrimary;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected && !isDisabled ? const Color(0xFF0F172A) : AppColors.border,
            width: 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w700,
            color: foreground,
            decoration: isDisabled ? TextDecoration.lineThrough : null,
          ),
        ),
      ),
    );
  }
}

/// One tappable payment-method choice (Cash on Delivery / Pay Online) in
/// the grocery cart's bottom summary bar — see the "Added 2026-10-08" doc
/// comment on `_GroceryCartScreenState._paymentMethod` for why this exists.
/// Visually mirrors checkout_screen.dart's `_PaymentMethodOption`.
class _GroceryPaymentMethodOption extends StatelessWidget {
  const _GroceryPaymentMethodOption({
    required this.label,
    required this.subtitle,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final String subtitle;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFF059669).withValues(alpha: 0.08) : Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? const Color(0xFF059669) : AppColors.border,
            width: selected ? 1.4 : 0.8,
          ),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 18,
              color: selected ? const Color(0xFF059669) : AppColors.textSecondary,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w800,
                      color: selected ? const Color(0xFF059669) : AppColors.textPrimary,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 10.5,
                      color: AppColors.textSecondary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            if (selected)
              const Icon(Icons.check_circle, size: 16, color: Color(0xFF059669)),
          ],
        ),
      ),
    );
  }
}
