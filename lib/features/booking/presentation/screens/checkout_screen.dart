import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/utils/location_gate.dart';
import '../../../../routing/app_router.dart';
import '../../../../shared/theme/app_colors.dart';
import '../../../../shared/utils/app_toast.dart';
import '../../../../shared/widgets/common_widgets.dart';
import '../../../addresses/domain/address_notifier.dart';
import '../../../auth/domain/auth_notifier.dart';
import '../../../catalog/domain/catalog_models.dart';
import '../../../catalog/domain/catalog_providers.dart';
import '../../../logistics/domain/logistics_providers.dart';
import '../../../logistics/presentation/widgets/slot_picker_widget.dart';
import '../../domain/booking_models.dart';
import '../../domain/booking_providers.dart';
import '../../domain/cart_notifier.dart';
import '../widgets/coupon_bottom_sheet.dart';

/// Screen 14: Booking Summary / Checkout Screen
/// Matches reference screen 14 with selected service summary, date/time picker,
/// address selector, coupon code application, bill summary, and checkout CTA.
class CheckoutScreen extends ConsumerStatefulWidget {
  const CheckoutScreen({
    super.key,
    this.initialServiceSlug,
    this.initialService,
  });

  final String? initialServiceSlug;
  final ServiceItem? initialService;

  @override
  ConsumerState<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends ConsumerState<CheckoutScreen> {
  final _notesController = TextEditingController();
  final _phoneController = TextEditingController();
  bool _isLoading = false;
  ServiceItem? _scheduledService;
  int _serviceQuantity = 1;
  String? _appliedCouponCode;
  int _couponDiscountAmount = 0;

  @override
  void initState() {
    super.initState();
    _scheduledService = widget.initialService;
    _bootstrapInitialService();
    // Added 2026-09-19: prompt to turn on device location right as the
    // customer reaches checkout — see location_gate.dart's doc comment.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ensureLocationEnabled(context);
    });
  }

  void _bootstrapInitialService() {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (_scheduledService == null && widget.initialServiceSlug != null) {
        final fetched = await ref.read(
          serviceDetailProvider(widget.initialServiceSlug!).future,
        );
        if (mounted) {
          setState(() {
            _scheduledService = fetched;
          });
        }
      }

      final target = _scheduledService;
      if (target != null && target.flowType == CatalogFlowType.grocery) {
        debugPrint(
            '[CheckoutScreen] Item is a grocery item: ID ${target.id} ("${target.title}"). Redirecting to /cart...');
        ref.read(cartProvider.notifier).addService(target);
        if (mounted) {
          context.go('/cart');
        }
        return;
      }
    });
  }

  @override
  void dispose() {
    _notesController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  // Fixed 2026-09-16: the coupon amount used to be guessed client-side from
  // a hardcoded code->amount table (and any unrecognized code still got a
  // fake ₹50 off). The sheet now validates the code against the real
  // backend (POST /customer/coupons/validate/) using the real cart
  // subtotal, and returns the discount the server actually computed —
  // this is the only place `_couponDiscountAmount` is ever set now.
  void _openCouponSheet() async {
    final Decimal cartTotalForCoupon = _scheduledService != null
        ? _scheduledService!.effectivePrice * Decimal.fromInt(_serviceQuantity)
        : ref.read(cartSummaryProvider).subtotal;

    final applied = await CouponBottomSheet.show(
      context,
      cartTotal: cartTotalForCoupon,
      currentCode: _appliedCouponCode,
    );

    if (applied != null) {
      setState(() {
        _appliedCouponCode = applied.code;
        _couponDiscountAmount = applied.discountAmount.toDouble().round();
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                'Coupon "${applied.code}" applied! Saved ₹$_couponDiscountAmount'),
            backgroundColor: AppColors.primary,
          ),
        );
      }
    }
  }

  Future<void> _handlePlaceOrder() async {
    final selectedAddress = ref.read(selectedAddressProvider);
    final selectedDate = ref.read(selectedBookingDateProvider);
    final selectedSlot = ref.read(selectedTimeSlotProvider);
    final currentUser = ref.read(currentUserProvider);

    final List<CartItem> itemsToBook;
    if (_scheduledService != null) {
      itemsToBook = [
        CartItem(
          service: _scheduledService!,
          quantity: _serviceQuantity,
          customNotes: _notesController.text.trim().isEmpty
              ? null
              : _notesController.text.trim(),
        ),
      ];
    } else {
      itemsToBook = ref.read(cartProvider);
    }

    if (itemsToBook.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select a service first.'),
          backgroundColor: AppColors.warning,
        ),
      );
      return;
    }

    final isAuthenticated = ref.read(isUserAuthenticatedProvider);
    if (!isAuthenticated) {
      ref.read(pendingActionProvider.notifier).setAction(
            PendingCartAction(
              service: itemsToBook.first.service,
              actionType: PendingCartActionType.buy,
              quantity: itemsToBook.first.quantity,
              returnPath: AppRoutes.bookingCheckout,
            ),
          );
      context.push(AppRoutes.login);
      return;
    }

    if (selectedAddress == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select or add a service address.'),
          backgroundColor: AppColors.warning,
        ),
      );
      context.push('/addresses?select=true');
      return;
    }

    if (selectedSlot == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select an appointment time slot.'),
          backgroundColor: AppColors.warning,
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    final dateFormatted = DateFormat('yyyy-MM-dd').format(selectedDate);
    final contactPhone = _phoneController.text.trim().isNotEmpty
        ? _phoneController.text.trim()
        : currentUser?.phone;

    // Fixed 2026-08-27: createBooking() requires totalAmount, but this call
    // never supplied it — a compile-blocking bug (same class as the one
    // found in grocery_cart_screen.dart this session). Recomputed here using
    // the exact same formula build() uses to display the total, since this
    // method doesn't share build()'s local variables.
    final Decimal placeOrderSubtotal;
    if (_scheduledService != null) {
      placeOrderSubtotal =
          _scheduledService!.effectivePrice * Decimal.fromInt(_serviceQuantity);
    } else {
      placeOrderSubtotal = ref.read(cartSummaryProvider).subtotal;
    }
    final Decimal placeOrderServiceFee = Decimal.fromInt(49);
    final Decimal placeOrderTaxes = ((placeOrderSubtotal * Decimal.fromInt(5)) /
            Decimal.fromInt(100))
        .toDecimal();
    final Decimal placeOrderDiscount = Decimal.fromInt(_couponDiscountAmount);
    final Decimal placeOrderRawTotal =
        placeOrderSubtotal + placeOrderServiceFee + placeOrderTaxes - placeOrderDiscount;
    final Decimal placeOrderTotal =
        placeOrderRawTotal > Decimal.zero ? placeOrderRawTotal : Decimal.zero;

    final result = await ref
        .read(bookingActionControllerProvider.notifier)
        .createBooking(
          customItems: _scheduledService != null ? itemsToBook : null,
          date: dateFormatted,
          slot: selectedSlot,
          totalAmount: placeOrderTotal,
          specialInstructions: _notesController.text.trim().isEmpty
              ? null
              : _notesController.text.trim(),
          contactPhone: contactPhone,
        );

    if (!mounted) return;
    setState(() => _isLoading = false);

    if (result.error != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(result.error!), backgroundColor: AppColors.error),
      );
    } else if (result.booking != null) {
      AppToast.bookingSuccessful(context);
      context.go('/bookings/success/${result.booking!.id}',
          extra: result.booking);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cartItems = ref.watch(cartProvider);
    final fallbackSummary = ref.watch(cartSummaryProvider);
    final selectedAddress = ref.watch(selectedAddressProvider);

    final bool hasScheduledService = _scheduledService != null;
    final bool hasItems = hasScheduledService || cartItems.isNotEmpty;

    final Decimal subtotal;
    final int totalItemCount;
    if (hasScheduledService) {
      subtotal = _scheduledService!.effectivePrice *
          Decimal.fromInt(_serviceQuantity);
      totalItemCount = _serviceQuantity;
    } else {
      subtotal = fallbackSummary.subtotal;
      totalItemCount = fallbackSummary.itemCount;
    }

    final Decimal serviceFee = Decimal.fromInt(49);
    final Decimal taxes =
        ((subtotal * Decimal.fromInt(5)) / Decimal.fromInt(100)).toDecimal();
    final Decimal discount = Decimal.fromInt(_couponDiscountAmount);
    final Decimal rawGrandTotal = subtotal + serviceFee + taxes - discount;
    final Decimal grandTotal =
        rawGrandTotal > Decimal.zero ? rawGrandTotal : Decimal.zero;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text(
          'Booking Summary',
          style: TextStyle(
            color: AppColors.navy,
            fontWeight: FontWeight.w800,
            fontSize: 18,
          ),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: AppColors.navy),
          onPressed: () => context.pop(),
        ),
      ),
      body: !hasItems
          ? EmptyStateWidget(
              title: 'No Service Selected',
              subtitle: 'Select services from our catalog to get started.',
              emoji: '🛠️',
              actionLabel: 'Browse Services',
              action: () => context.go('/'),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── 1. Selected Services Card ──
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.border, width: 0.8),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Selected Service ($totalItemCount)',
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w800,
                                color: AppColors.navy,
                              ),
                            ),
                            GestureDetector(
                              onTap: () => context.push('/search'),
                              child: const Text(
                                '+ Add More',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.primary,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const Divider(height: 20, color: AppColors.border),
                        if (hasScheduledService)
                          Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      _scheduledService!.title,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                        fontSize: 14,
                                        color: AppColors.navy,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      '₹${_scheduledService!.effectivePrice} each',
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: AppColors.textSecondary,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              // Quantity Stepper
                              Container(
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(
                                      color: AppColors.border, width: 0.8),
                                ),
                                child: Row(
                                  children: [
                                    IconButton(
                                      icon: const Icon(Icons.remove, size: 16),
                                      padding: EdgeInsets.zero,
                                      constraints: const BoxConstraints(
                                        minWidth: 30,
                                        minHeight: 30,
                                      ),
                                      onPressed: _serviceQuantity > 1
                                          ? () => setState(
                                              () => _serviceQuantity--)
                                          : null,
                                    ),
                                    Text(
                                      '$_serviceQuantity',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w800,
                                        fontSize: 13,
                                        color: AppColors.navy,
                                      ),
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.add, size: 16),
                                      padding: EdgeInsets.zero,
                                      constraints: const BoxConstraints(
                                        minWidth: 30,
                                        minHeight: 30,
                                      ),
                                      onPressed: () => setState(
                                          () => _serviceQuantity++),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 14),
                              Text(
                                '₹$subtotal',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w900,
                                  fontSize: 15,
                                  color: AppColors.navy,
                                ),
                              ),
                            ],
                          )
                        else
                          ...cartItems.map(
                            (item) => Padding(
                              padding: const EdgeInsets.symmetric(vertical: 4),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      '${item.service.title} × ${item.quantity}',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 13,
                                        color: AppColors.navy,
                                      ),
                                    ),
                                  ),
                                  Text(
                                    '₹${item.totalPrice}',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                      fontSize: 14,
                                      color: AppColors.navy,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 18),

                  // ── 2. Screen 12: Date and Time Slot Picker ──
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.border, width: 0.8),
                    ),
                    child: const SlotPickerWidget(),
                  ),

                  const SizedBox(height: 18),

                  // ── 3. Screen 13: Service Address Card ──
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.border, width: 0.8),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Row(
                              children: [
                                Icon(
                                  Icons.location_on_rounded,
                                  color: AppColors.primary,
                                  size: 18,
                                ),
                                SizedBox(width: 6),
                                Text(
                                  'Service Address',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w800,
                                    color: AppColors.navy,
                                  ),
                                ),
                              ],
                            ),
                            GestureDetector(
                              onTap: () =>
                                  context.push('/addresses?select=true'),
                              child: Text(
                                selectedAddress != null ? 'Change' : '+ Add New',
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.primary,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const Divider(height: 20, color: AppColors.border),
                        if (selectedAddress != null) ...[
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: AppColors.primaryLight,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  selectedAddress.addressType.toUpperCase(),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 10,
                                    color: AppColors.primary,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            selectedAddress.formattedAddress,
                            style: const TextStyle(
                              fontSize: 13,
                              color: AppColors.textPrimary,
                              height: 1.4,
                            ),
                          ),
                        ] else ...[
                          GestureDetector(
                            onTap: () => context.push('/addresses/add'),
                            child: Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                    color: AppColors.border, width: 0.8),
                              ),
                              child: const Row(
                                children: [
                                  Icon(
                                    Icons.add_location_alt_outlined,
                                    color: AppColors.primary,
                                    size: 20,
                                  ),
                                  SizedBox(width: 10),
                                  Text(
                                    'Tap to select your service address',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 13,
                                      color: AppColors.navy,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),

                  const SizedBox(height: 18),

                  // ── 4. Screen 15: Apply Coupon Box ──
                  GestureDetector(
                    onTap: _openCouponSheet,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 14),
                      decoration: BoxDecoration(
                        color: _appliedCouponCode != null
                            ? const Color(0xFFF0FDF4)
                            : const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: _appliedCouponCode != null
                              ? AppColors.primary
                              : AppColors.border,
                          width: _appliedCouponCode != null ? 1.5 : 0.8,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.discount_outlined,
                            color: _appliedCouponCode != null
                                ? AppColors.primary
                                : AppColors.navy,
                            size: 20,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _appliedCouponCode != null
                                      ? 'Coupon: $_appliedCouponCode'
                                      : 'Apply Coupon / Promo Code',
                                  style: TextStyle(
                                    fontSize: 13.5,
                                    fontWeight: FontWeight.w700,
                                    color: _appliedCouponCode != null
                                        ? AppColors.primary
                                        : AppColors.navy,
                                  ),
                                ),
                                if (_appliedCouponCode != null) ...[
                                  const SizedBox(height: 2),
                                  Text(
                                    'Saved ₹$_couponDiscountAmount on this booking',
                                    style: const TextStyle(
                                      fontSize: 11.5,
                                      color: AppColors.primary,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          const Icon(
                            Icons.chevron_right_rounded,
                            color: AppColors.textHint,
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 18),

                  // ── 5. Special Notes ──
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.border, width: 0.8),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Special Instructions (Optional)',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            color: AppColors.navy,
                          ),
                        ),
                        const SizedBox(height: 10),
                        TextField(
                          controller: _notesController,
                          maxLines: 2,
                          decoration: InputDecoration(
                            hintText:
                                'e.g. Please bring ladder, call before arrival',
                            hintStyle: const TextStyle(
                              fontSize: 13,
                              color: AppColors.textHint,
                            ),
                            filled: true,
                            fillColor: Colors.white,
                            contentPadding: const EdgeInsets.all(12),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(6),
                              borderSide: const BorderSide(
                                  color: AppColors.border, width: 0.8),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(6),
                              borderSide: const BorderSide(
                                  color: AppColors.border, width: 0.8),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 18),

                  // ── 6. Bill Summary Breakdown ──
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.border, width: 0.8),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Payment Summary',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            color: AppColors.navy,
                          ),
                        ),
                        const SizedBox(height: 14),
                        _BillRow(
                          label: 'Item Total',
                          amount: '₹$subtotal',
                        ),
                        const SizedBox(height: 8),
                        _BillRow(
                          label: 'Safety & Platform Fee',
                          amount: '₹$serviceFee',
                        ),
                        const SizedBox(height: 8),
                        _BillRow(
                          label: 'Taxes (GST 5%)',
                          amount: '₹$taxes',
                        ),
                        if (_couponDiscountAmount > 0) ...[
                          const SizedBox(height: 8),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Coupon Discount ($_appliedCouponCode)',
                                style: const TextStyle(
                                  fontSize: 13,
                                  color: AppColors.primary,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              Text(
                                '-₹$_couponDiscountAmount',
                                style: const TextStyle(
                                  fontSize: 13,
                                  color: AppColors.primary,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ],
                          ),
                        ],
                        const Divider(height: 20, color: AppColors.border),
                        _BillRow(
                          label: 'Total Amount',
                          amount: '₹$grandTotal',
                          isBold: true,
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 120),
                ],
              ),
            ),

      // ── Fixed Bottom Booking Bar ──
      bottomNavigationBar: !hasItems
          ? null
          : Container(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 28),
              decoration: BoxDecoration(
                color: Colors.white,
                border: const Border(
                  top: BorderSide(color: AppColors.border, width: 0.8),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 10,
                    offset: const Offset(0, -4),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Total to Pay',
                        style: TextStyle(
                          fontSize: 11,
                          color: AppColors.textSecondary,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      Text(
                        '₹$grandTotal',
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                          color: AppColors.navy,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(width: 24),
                  Expanded(
                    child: SizedBox(
                      height: 52,
                      child: ElevatedButton(
                        onPressed: _isLoading ? null : _handlePlaceOrder,
                        style: ElevatedButton.styleFrom(
                          // Blue = service booking checkout, Green = grocery
                          // checkout — same flow-accent rule as the catalog
                          // and cart screens.
                          backgroundColor: hasScheduledService
                              ? AppColors.serviceBlue
                              : AppColors.groceryGreen,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          elevation: 0,
                        ),
                        child: _isLoading
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Text(
                                'Book Appointment',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}

class _BillRow extends StatelessWidget {
  const _BillRow({
    required this.label,
    required this.amount,
    this.isBold = false,
  });

  final String label;
  final String amount;
  final bool isBold;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: isBold ? 15 : 13,
            fontWeight: isBold ? FontWeight.w800 : FontWeight.w500,
            color: isBold ? AppColors.navy : AppColors.textSecondary,
          ),
        ),
        Text(
          amount,
          style: TextStyle(
            fontSize: isBold ? 16 : 13,
            fontWeight: isBold ? FontWeight.w900 : FontWeight.w700,
            color: AppColors.navy,
          ),
        ),
      ],
    );
  }
}

