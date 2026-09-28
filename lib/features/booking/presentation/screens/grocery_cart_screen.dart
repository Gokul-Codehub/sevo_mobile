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
import '../../../../shared/widgets/common_widgets.dart';
import '../../../addresses/domain/address_models.dart';
import '../../../addresses/domain/address_notifier.dart';
import '../../../auth/domain/auth_notifier.dart';
import '../../../catalog/domain/catalog_providers.dart';
import '../../../home/domain/home_flow_mode.dart';
import '../../../logistics/domain/logistics_models.dart';
import '../../domain/booking_models.dart';
import '../../domain/booking_providers.dart';
import '../../domain/cart_notifier.dart';

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

  @override
  void initState() {
    super.initState();
    // Added 2026-09-19: prompt to turn on device location right as the
    // customer opens their grocery cart/checkout — see
    // location_gate.dart's doc comment.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ensureLocationEnabled(context);
    });
  }

  @override
  void dispose() {
    _customTipController.dispose();
    super.dispose();
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
      // Fixed 2026-09-19 per explicit report ("If cart is empty i click
      // explore more it redirects to the wrog page"): this single Cart
      // screen (route '/cart') is shared by BOTH flows — a service item
      // added via ServiceCard/ProductCard's "Add to Cart" lands in the
      // exact same `cartProvider` as a grocery item — but this empty
      // state was hardcoded to grocery copy and always sent "Explore" to
      // '/categories/vegetables_groceries', regardless of what the
      // customer was actually browsing. Now themed off Home's own current
      // flow mode, same source of truth [_HomeScreenState] itself reads.
      final flowMode = ref.watch(homeFlowModeProvider);
      final isGroceryMode = flowMode == HomeFlowMode.groceries;
      final emptyStateAccent =
          isGroceryMode ? const Color(0xFF0F766E) : AppColors.serviceBlue;

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
                    color: emptyStateAccent.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    isGroceryMode
                        ? Icons.shopping_basket_outlined
                        : Icons.build_outlined,
                    size: 48,
                    color: emptyStateAccent,
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  isGroceryMode
                      ? 'Your grocery cart is empty'
                      : 'Your cart is empty',
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  isGroceryMode
                      ? 'Add farm-fresh vegetables and daily essentials to get instant 10-15 min delivery.'
                      : 'Browse our services and add one to get started.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppColors.textSecondary,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 28),
                FilledButton.icon(
                  onPressed: () => context.go(isGroceryMode
                      ? '/categories/vegetables_groceries'
                      : '/categories'),
                  style: FilledButton.styleFrom(
                    backgroundColor: emptyStateAccent,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 28,
                      vertical: 14,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  icon: Icon(
                      isGroceryMode ? Icons.eco_rounded : Icons.search_rounded,
                      size: 18),
                  label: Text(
                    isGroceryMode
                        ? 'Explore Farm-Fresh Produce'
                        : 'Explore Services',
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final freeThreshold = Decimal.parse('200.00');
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
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 140),
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

                      return Row(
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
                            child: AppRemoteImage(
                              imageUrl: item.service.imageUrl,
                              rawPath: item.service.imageUrl,
                              categoryName: item.service.categoryName,
                              slug: item.service.slug,
                              semanticIcon: ImageUrlHelper.mapCategoryIcon(
                                  item.service.categoryName, item.service.slug),
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
                                const SizedBox(height: 2),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 1,
                                  ),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFF1F5F9),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: const Text(
                                    '8 MINS',
                                    style: TextStyle(
                                      fontSize: 9.5,
                                      color: Color(0xFF0F766E),
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    Text(
                                      '₹$effectivePrice',
                                      style: const TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w900,
                                        color: AppColors.textPrimary,
                                      ),
                                    ),
                                    if (mrp > effectivePrice) ...[
                                      const SizedBox(width: 6),
                                      Text(
                                        '₹$mrp',
                                        style: const TextStyle(
                                          fontSize: 11.5,
                                          color: AppColors.textSecondary,
                                          decoration:
                                              TextDecoration.lineThrough,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ],
                            ),
                          ),

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
                      // Always push to the grocery category screen — never use pop()
                      // which could navigate to an unrelated screen
                      context.push('/categories/vegetables_groceries');
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
                        '₹${cartSummary.total}',
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
              // Address Row
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        Container(
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                            color: const Color(0xFFF1F5F9),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(
                            Icons.location_on_outlined,
                            size: 16,
                            color: AppColors.textSecondary,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Delivering to ${activeAddress != null ? activeAddress.addressType : "Home"}',
                                style: const TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w800,
                                  color: AppColors.textPrimary,
                                ),
                              ),
                              Text(
                                activeAddress?.formattedAddress ??
                                    'Hosur, Tamil Nadu',
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
                      ],
                    ),
                  ),
                  OutlinedButton(
                    onPressed: () => _openAddressSheet(context, addresses),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.textPrimary,
                      side: const BorderSide(color: AppColors.border),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 2,
                      ),
                      minimumSize: const Size(0, 28),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: const Text(
                      'Change',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),

              // Big Green Proceed To Pay Button
              SizedBox(
                width: double.infinity,
                height: 52,
                child: FilledButton(
                  onPressed: _isSubmitting
                      ? null
                      : () => _handlePlaceOrder(context, ref, activeAddress),
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
                            '₹${cartSummary.total}',
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
      final today = DateTime.now();
      final todayStr =
          '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';

      final result = await ref
          .read(bookingActionControllerProvider.notifier)
          .createBooking(
            date: todayStr,
            slot: TimeSlot(
              id: 'express_${DateTime.now().millisecondsSinceEpoch}',
              date: todayStr,
              startTime: '10:00',
              endTime: '10:15',
              label: '10-15 Min Express Delivery',
            ),
            specialInstructions: 'Quick Commerce Vegetable Order',
            contactPhone: ref.read(currentUserProvider)?.phone,
            totalAmount: ref.read(cartSummaryProvider).total,
          );

      if (!context.mounted) return;

      if (result.error != null) {
        if (mounted) {
          setState(() => _errorMessage = result.error);
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result.error!),
            backgroundColor: AppColors.error,
          ),
        );
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
