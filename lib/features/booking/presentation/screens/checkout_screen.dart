import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/errors/api_error.dart';
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
import '../../../catalog/domain/catalog_models.dart';
import '../../../catalog/domain/catalog_providers.dart';
import '../../../logistics/domain/logistics_providers.dart';
import '../../../logistics/presentation/widgets/slot_picker_widget.dart';
import '../../domain/booking_models.dart';
import '../../domain/booking_providers.dart';
import '../../domain/cart_notifier.dart';
import '../../../pricing/domain/pricing_providers.dart';
import '../../../pricing/domain/service_fare.dart';
import '../../data/coupon_repository.dart';
import '../widgets/coupon_bottom_sheet.dart';
import '../../../../core/navigation/safe_back.dart';

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

  // Redesigned flow (2026-10-14): page 0 = date & time, page 1 = address,
  // page 2 = details + payment.
  int _step = 0;
  bool _showNotes = false;
  final _couponController = TextEditingController();
  bool _couponChecking = false;
  String? _couponError;

  // Fixed 2026-10-08 (QA CME02 — "the payment method (Pay online, pay
  // after service) is not shown to the customer, but it is showed on the
  // web"): this screen never had any payment-method UI at all, and
  // booking_repository.dart's createBooking() never sent a `payment_method`
  // key in its payload either — so the backend's own
  // `(request.data.get('payment_method') or 'COD').upper()` fallback
  // silently defaulted every single mobile booking to Cash on Service,
  // with no way for the customer to choose to pay online instead (which
  // the web booking flow already lets them do). 'COD' as the default here
  // keeps existing behaviour unchanged for anyone who never touches the
  // selector.
  String _paymentMethod = 'COD';

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
    // Fixed 2026-10-06: PricingConfigNotifier only fetches the live
    // admin-set pricing once, at app cold start — the admin Settings >
    // Pricing page's own banner promises "The customer app fetches these
    // values when a customer opens checkout or the grocery cart", but
    // nothing called the refreshNow() it exposes for exactly that. See
    // the matching fix in grocery_cart_screen.dart's initState.
    ref.read(pricingConfigProvider.notifier).refreshNow();
  }

  void _bootstrapInitialService() {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      // Fixed 2026-10-06: the time-slot grid (SlotPickerWidget, below) must
      // know which service is being booked — admin's Time Slot Management
      // is configured per service (hours/duration/capacity), and slots
      // fetched without a service id only ever matched the global default
      // config, never the specific one the customer was actually seeing.
      // This write has to happen here, inside a post-frame callback — doing
      // it directly in initState() throws Riverpod's "Tried to modify a
      // provider while the widget tree was building" (initState counts as
      // "building" for this purpose, same as build/dispose/didUpdateWidget).
      final initialSlug = _scheduledService?.slug ?? widget.initialServiceSlug;
      if (initialSlug != null) {
        ref.read(selectedBookingServiceIdProvider.notifier).state =
            initialSlug;
      }

      if (_scheduledService == null && widget.initialServiceSlug != null) {
        final fetched = await ref.read(
          serviceDetailProvider(widget.initialServiceSlug!).future,
        );
        if (mounted) {
          setState(() {
            _scheduledService = fetched;
          });
          ref.read(selectedBookingServiceIdProvider.notifier).state =
              fetched.slug;
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
    _couponController.dispose();
    // Not clearing selectedBookingServiceIdProvider/selectedTimeSlotProvider
    // here: modifying a provider inside dispose() throws Riverpod's "Tried
    // to modify a provider while the widget tree was building" (dispose
    // counts, same as initState/build). The next screen that cares about
    // either provider (this screen, next time it opens) already overwrites
    // them itself in its own post-frame callback above, so a stale value
    // sitting here between visits is harmless.
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
        AppToast.show(
          context,
          'Coupon "${applied.code}" applied! Saved ₹$_couponDiscountAmount',
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
      AppToast.show(
        context,
        'Please select a service first.',
        type: AppToastType.error,
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
      AppToast.show(
        context,
        'Please select or add a service address.',
        type: AppToastType.error,
      );
      context.push('/addresses?select=true');
      return;
    }

    if (selectedSlot == null) {
      AppToast.show(
        context,
        'Please select an appointment time slot.',
        type: AppToastType.error,
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
    // Fixed 2026-10-01: these used to be hardcoded Decimal.fromInt(49) /
    // "5%" constants — now read from the admin-configurable PricingConfig
    // (Settings > Pricing in the admin panel), same as cart_notifier.dart's
    // cartSummaryProvider.
    // 2026-10-12: services are priced exactly like the web app / backend
    // (home_services_pricing.py) -- each package's own GST rate, one
    // platform fee per booking -- see ServiceFare.
    final orderFare = ServiceFare.fromLines(
      (_scheduledService != null
              ? [CartItem(service: _scheduledService!, quantity: _serviceQuantity)]
              : ref.read(cartProvider))
          .map((i) => (service: i.service, lineTotal: i.totalPrice)),
    );
    final Decimal placeOrderServiceFee = orderFare.platformFee;
    final Decimal placeOrderTaxes = orderFare.gst;
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
          paymentMethod: _paymentMethod,
        );

    if (!mounted) return;
    setState(() => _isLoading = false);

    if (result.error != null) {
      AppToast.show(context, result.error!, type: AppToastType.error);
    } else if (result.booking != null) {
      AppToast.bookingSuccessful(context);
      context.go('/bookings/success/${result.booking!.id}',
          extra: result.booking);
    }
  }

  // ───────────────────────────────────────────────────────────────────────
  // Redesigned booking summary (2026-10-14, per the UI requirement image):
  // a two-page flow under a 3-step header —
  //   page 0: Date & Time + Service Address (+ special instructions) → Continue
  //   page 1: Service details, booking details, coupon, payment method,
  //           price details → Confirm Booking.
  // All data / pricing / booking logic is unchanged.
  // ───────────────────────────────────────────────────────────────────────
  static const Color _pageBg = Color(0xFFF8F4EF);
  static const Color _okGreen = AppColors.navy;
  static const Color _mint = Color(0xFFEEF1F7);
  static const Color _mintText = Color(0xFF1E3A8A);
  static const Color _blue = Color(0xFF1D5EE8);

  Widget _card({required Widget child, EdgeInsets? padding}) {
    return Container(
      width: double.infinity,
      padding: padding ?? const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF1E3A8A).withValues(alpha: 0.06),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: child,
    );
  }

  Widget _numberedHeader(String number, String title, {String? subtitle, Widget? trailing}) {
    return Row(
      children: [
        Container(
          width: 28,
          height: 28,
          decoration: const BoxDecoration(color: _okGreen, shape: BoxShape.circle),
          child: Center(
            child: Text(number,
                style: const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13)),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w900, color: AppColors.navy)),
              if (subtitle != null)
                Text(subtitle,
                    style: const TextStyle(fontSize: 11.5, color: AppColors.textSecondary)),
            ],
          ),
        ),
        ?trailing,
      ],
    );
  }

  Widget _discountPill(int percent) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(color: _mint, borderRadius: BorderRadius.circular(20)),
      child: Text('$percent% OFF',
          style: const TextStyle(
              fontSize: 11, fontWeight: FontWeight.w800, color: _mintText)),
    );
  }

  void _goNext() {
    if (_step == 0) {
      if (ref.read(selectedTimeSlotProvider) == null) {
        AppToast.show(context, 'Please select an appointment time slot.',
            type: AppToastType.error);
        return;
      }
    } else if (_step == 1) {
      if (ref.read(selectedAddressProvider) == null) {
        AppToast.show(context, 'Please select or add a service address.',
            type: AppToastType.error);
        return;
      }
    }
    setState(() => _step = _step + 1);
  }

  Future<void> _applyCouponCode(Decimal cartTotal) async {
    final code = _couponController.text.trim().toUpperCase();
    if (code.isEmpty) {
      setState(() => _couponError = 'Please enter a coupon code.');
      return;
    }
    setState(() {
      _couponError = null;
      _couponChecking = true;
    });
    final result = await ref
        .read(couponRepositoryProvider)
        .validateCoupon(code: code, cartTotal: cartTotal);
    if (!mounted) return;
    switch (result) {
      case Success(:final data):
        setState(() {
          _couponChecking = false;
          _appliedCouponCode = data.couponCode.isNotEmpty ? data.couponCode : code;
          _couponDiscountAmount = data.discountAmount.toDouble().round();
          _couponController.clear();
        });
      case Failure(:final error):
        setState(() {
          _couponChecking = false;
          _couponError = error.message;
        });
    }
  }

  void _removeCoupon() {
    setState(() {
      _appliedCouponCode = null;
      _couponDiscountAmount = 0;
      _couponError = null;
    });
  }

  Widget _buildStepper() {
    Widget node(int i, String label) {
      final done = i < _step;
      final active = i == _step;
      final reached = done || active;
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: reached ? _okGreen : Colors.white,
              shape: BoxShape.circle,
              border: Border.all(
                  color: reached ? _okGreen : const Color(0xFFCBD5E1), width: 1.5),
            ),
            child: Center(
              child: done
                  ? const Icon(Icons.check_rounded, size: 18, color: Colors.white)
                  : Text('${i + 1}',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: reached ? Colors.white : AppColors.textHint)),
            ),
          ),
          const SizedBox(height: 4),
          Text(label,
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: reached ? FontWeight.w800 : FontWeight.w500,
                  color: reached ? AppColors.navy : AppColors.textSecondary)),
        ],
      );
    }

    Widget line(bool filled) => Expanded(
          child: Padding(
            padding: const EdgeInsets.only(bottom: 18),
            child: Container(
                height: 2, color: filled ? _okGreen : const Color(0xFFE2E8F0)),
          ),
        );

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 6, 24, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          node(0, 'Date & Time'),
          line(_step > 0),
          node(1, 'Address'),
          line(_step > 1),
          node(2, 'Payment'),
        ],
      ),
    );
  }

  Widget _addressTypeIcon(String type) {
    final t = type.toLowerCase();
    final icon = t.contains('office') || t.contains('work')
        ? Icons.business_rounded
        : (t.contains('home') ? Icons.home_rounded : Icons.place_rounded);
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
          color: const Color(0xFFE8F1FF), borderRadius: BorderRadius.circular(12)),
      child: Icon(icon, size: 22, color: _blue),
    );
  }

  String _titleCase(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1).toLowerCase();

  Widget _buildAddressSection(Address? selected) {
    final addresses = ref.watch(addressListProvider).valueOrNull ?? const <Address>[];
    final list = <Address>[...addresses];
    if (selected != null && !list.any((a) => a.id == selected.id)) {
      list.insert(0, selected);
    }
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _numberedHeader(
            '2',
            'Service Address',
            subtitle: 'Where should we come?',
            trailing: GestureDetector(
              onTap: () => context.push('/addresses/add'),
              child: const Text('Add New',
                  style: TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w800, color: _blue)),
            ),
          ),
          const SizedBox(height: 12),
          for (final a in list)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () => ref.read(selectedAddressProvider.notifier).state = a,
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: selected?.id == a.id ? const Color(0xFFF3F6FC) : Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: selected?.id == a.id ? _okGreen : const Color(0xFFE2E8F0),
                      width: selected?.id == a.id ? 1.5 : 1,
                    ),
                  ),
                  child: Row(
                    children: [
                      _addressTypeIcon(a.addressType),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(_titleCase(a.addressType),
                                style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w800,
                                    color: AppColors.navy)),
                            const SizedBox(height: 2),
                            Text(a.formattedAddress,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    fontSize: 12,
                                    height: 1.35,
                                    color: AppColors.textSecondary)),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Icon(
                        selected?.id == a.id
                            ? Icons.radio_button_checked_rounded
                            : Icons.radio_button_off_rounded,
                        color: selected?.id == a.id ? _okGreen : AppColors.textHint,
                        size: 24,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () => context.push('/addresses/add'),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFBFD4F6)),
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.add_rounded, color: _blue, size: 20),
                  SizedBox(width: 6),
                  Text('Add New Address',
                      style: TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w800, color: _blue)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInstructions() {
    return _card(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Column(
        children: [
          InkWell(
            onTap: () => setState(() => _showNotes = !_showNotes),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Row(
                children: [
                  const Icon(Icons.edit_note_rounded, color: AppColors.navy, size: 24),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text('Special Instructions (Optional)',
                        style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w800,
                            color: AppColors.navy)),
                  ),
                  Icon(
                    _showNotes
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.chevron_right_rounded,
                    color: AppColors.textHint,
                  ),
                ],
              ),
            ),
          ),
          if (_showNotes || _notesController.text.trim().isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: TextField(
                controller: _notesController,
                maxLines: 2,
                decoration: InputDecoration(
                  hintText: 'e.g. Please bring ladder, call before arrival',
                  hintStyle:
                      const TextStyle(fontSize: 12, color: AppColors.textHint),
                  filled: true,
                  fillColor: _pageBg,
                  contentPadding: const EdgeInsets.all(12),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildDateTimeStep() {
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _numberedHeader('1', 'Select Date & Time',
              subtitle: 'Choose your preferred slot'),
          const SizedBox(height: 14),
          const SlotPickerWidget(),
        ],
      ),
    );
  }

  Widget _buildAddressStep(Address? selectedAddress) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildAddressSection(selectedAddress),
        const SizedBox(height: 12),
        _buildInstructions(),
      ],
    );
  }

  Widget _kv(String label, String value,
      {bool bold = false, Color? valueColor, Color? labelColor}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Flexible(
            child: Text(label,
                style: TextStyle(
                    fontSize: bold ? 16 : 14,
                    fontWeight: bold ? FontWeight.w900 : FontWeight.w500,
                    color: labelColor ??
                        (bold ? AppColors.navy : AppColors.textSecondary))),
          ),
          const SizedBox(width: 8),
          Text(value,
              style: TextStyle(
                  fontSize: bold ? 20 : 14,
                  fontWeight: bold ? FontWeight.w900 : FontWeight.w700,
                  color: valueColor ?? (bold ? _okGreen : AppColors.navy))),
        ],
      ),
    );
  }

  Widget _detailRow(IconData icon, String title, String value,
      {String? sub, int goTo = 0}) {
    return InkWell(
      onTap: () => setState(() => _step = goTo),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 20, color: AppColors.textSecondary),
            const SizedBox(width: 12),
            SizedBox(
              width: 64,
              child: Text(title,
                  style: const TextStyle(
                      fontSize: 12.5, color: AppColors.textSecondary)),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(value,
                      style: const TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w800,
                          color: AppColors.navy)),
                  if (sub != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(sub,
                          style: const TextStyle(
                              fontSize: 12,
                              height: 1.35,
                              color: AppColors.textSecondary)),
                    ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: AppColors.textHint),
          ],
        ),
      ),
    );
  }

  Widget _paymentTile({
    required String label,
    required String subtitle,
    required IconData icon,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: selected ? const Color(0xFFF3F6FC) : Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
                color: selected ? _okGreen : const Color(0xFFE2E8F0),
                width: selected ? 1.5 : 1),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                    color: selected ? Colors.white : const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(12)),
                child: Icon(icon,
                    size: 22, color: selected ? _okGreen : AppColors.navy),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label,
                        style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            color: AppColors.navy)),
                    Text(subtitle,
                        style: const TextStyle(
                            fontSize: 12, color: AppColors.textSecondary)),
                  ],
                ),
              ),
              Icon(
                selected
                    ? Icons.check_circle_rounded
                    : Icons.radio_button_off_rounded,
                color: selected ? _okGreen : AppColors.textHint,
                size: 26,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPaymentStep({
    required bool hasScheduledService,
    required List<CartItem> cartItems,
    required Decimal subtotal,
    required Decimal serviceFee,
    required Decimal taxes,
    required Decimal grandTotal,
  }) {
    final selectedDate = ref.watch(selectedBookingDateProvider);
    final selectedSlot = ref.watch(selectedTimeSlotProvider);
    final selectedAddress = ref.watch(selectedAddressProvider);
    final s = _scheduledService;

    final Decimal listTotal = (s != null && s.hasDiscount)
        ? s.price * Decimal.fromInt(_serviceQuantity)
        : subtotal;
    final Decimal packageDiscount = listTotal - subtotal;
    final pct = s?.discountPercent;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Service Details ──
        _card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Service Details',
                  style: TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w900, color: AppColors.navy)),
              const SizedBox(height: 12),
              if (s != null) ...[
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: SizedBox(
                        width: 68,
                        height: 68,
                        child: AppRemoteImage(
                          imageUrl: s.imageUrl,
                          rawPath: s.imageUrl,
                          categoryName: s.categoryName,
                          slug: s.slug,
                          semanticIcon:
                              ImageUrlHelper.mapCategoryIcon(s.categoryName, s.slug),
                          width: 68,
                          height: 68,
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(s.title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontSize: 14.5,
                                  fontWeight: FontWeight.w800,
                                  color: AppColors.navy)),
                          if (s.durationMinutes > 0) ...[
                            const SizedBox(height: 3),
                            Row(
                              children: [
                                const Icon(Icons.schedule_rounded,
                                    size: 15, color: AppColors.textSecondary),
                                const SizedBox(width: 4),
                                Text('${s.durationMinutes} mins',
                                    style: const TextStyle(
                                        fontSize: 12,
                                        color: AppColors.textSecondary)),
                              ],
                            ),
                          ],
                          if (s.hasDiscount && pct != null) ...[
                            const SizedBox(height: 6),
                            _discountPill(pct),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text('₹${s.effectivePrice}',
                            style: const TextStyle(
                                fontSize: 16.5,
                                fontWeight: FontWeight.w900,
                                color: AppColors.navy)),
                        if (s.hasDiscount)
                          Text('₹${s.price}',
                              style: const TextStyle(
                                  fontSize: 12,
                                  color: AppColors.textHint,
                                  decoration: TextDecoration.lineThrough)),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    const Text('Quantity',
                        style: TextStyle(
                            fontSize: 12.5, color: AppColors.textSecondary)),
                    const Spacer(),
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: Row(
                        children: [
                          IconButton(
                            icon: const Icon(Icons.remove, size: 18),
                            padding: EdgeInsets.zero,
                            constraints:
                                const BoxConstraints(minWidth: 38, minHeight: 36),
                            onPressed: _serviceQuantity > 1
                                ? () => setState(() {
                                      _serviceQuantity--;
                                      _removeCoupon();
                                    })
                                : null,
                          ),
                          Text('$_serviceQuantity',
                              style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 14,
                                  color: AppColors.navy)),
                          IconButton(
                            icon: const Icon(Icons.add, size: 18),
                            padding: EdgeInsets.zero,
                            constraints:
                                const BoxConstraints(minWidth: 38, minHeight: 36),
                            onPressed: () => setState(() {
                              _serviceQuantity++;
                              _removeCoupon();
                            }),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ] else
                ...cartItems.map(
                  (item) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text('${item.service.title} × ${item.quantity}',
                              style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13,
                                  color: AppColors.navy)),
                        ),
                        Text('₹${item.totalPrice}',
                            style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 13.5,
                                color: AppColors.navy)),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // ── Booking Details ──
        _card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Booking Details',
                  style: TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w900, color: AppColors.navy)),
              const SizedBox(height: 6),
              _detailRow(Icons.calendar_today_rounded, 'Date',
                  DateFormat('EEE, d MMM yyyy').format(selectedDate)),
              const Divider(height: 1, color: Color(0xFFF1F5F9)),
              _detailRow(Icons.schedule_rounded, 'Time', selectedSlot?.label ?? '—'),
              const Divider(height: 1, color: Color(0xFFF1F5F9)),
              _detailRow(
                Icons.location_on_outlined,
                'Address',
                selectedAddress != null ? _titleCase(selectedAddress.addressType) : '—',
                sub: selectedAddress?.formattedAddress,
                goTo: 1,
              ),
              if (_notesController.text.trim().isNotEmpty) ...[
                const Divider(height: 1, color: Color(0xFFF1F5F9)),
                _detailRow(Icons.edit_note_rounded, 'Notes',
                    _notesController.text.trim(),
                    goTo: 1),
              ],
            ],
          ),
        ),
        const SizedBox(height: 12),

        // ── Coupon ──
        _card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.local_offer_outlined,
                      size: 22, color: AppColors.navy),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text('Apply Coupon / Promo Code',
                        style: TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w900,
                            color: AppColors.navy)),
                  ),
                  TextButton(
                    onPressed: _openCouponSheet,
                    style: TextButton.styleFrom(
                      foregroundColor: _blue,
                      padding:
                          const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      minimumSize: const Size(0, 36),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: const Text('View offers',
                        style: TextStyle(
                            fontSize: 12, fontWeight: FontWeight.w800)),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _couponController,
                      textCapitalization: TextCapitalization.characters,
                      onSubmitted: (_) => _applyCouponCode(subtotal),
                      decoration: InputDecoration(
                        hintText: 'Enter coupon code',
                        hintStyle: const TextStyle(
                            fontSize: 13, color: AppColors.textHint),
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 14),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: _blue),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  SizedBox(
                    height: 48,
                    child: ElevatedButton(
                      onPressed:
                          _couponChecking ? null : () => _applyCouponCode(subtotal),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _blue,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        // The app theme sets minimumSize.width = infinity, which
                        // throws inside a Row and blanked everything below.
                        minimumSize: const Size(88, 48),
                        padding: const EdgeInsets.symmetric(horizontal: 22),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      child: _couponChecking
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white))
                          : const Text('Apply',
                              style: TextStyle(
                                  fontWeight: FontWeight.w800, fontSize: 13.5)),
                    ),
                  ),
                ],
              ),
              if (_couponError != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(_couponError!,
                      style: const TextStyle(
                          fontSize: 12, color: AppColors.error)),
                ),
              if (_appliedCouponCode != null) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF3F6FC),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFDDE3ED)),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 30,
                        height: 30,
                        decoration: const BoxDecoration(
                            color: _okGreen, shape: BoxShape.circle),
                        child: const Icon(Icons.percent_rounded,
                            size: 16, color: Colors.white),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('$_appliedCouponCode applied!',
                                style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w800,
                                    color: _mintText)),
                            Text('You saved ₹$_couponDiscountAmount',
                                style: const TextStyle(
                                    fontSize: 12, color: _mintText)),
                          ],
                        ),
                      ),
                      GestureDetector(
                        onTap: _removeCoupon,
                        child: const Icon(Icons.close_rounded,
                            size: 20, color: AppColors.textSecondary),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 12),

        // ── Payment Method ──
        _card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Payment Method',
                  style: TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w900, color: AppColors.navy)),
              const SizedBox(height: 12),
              _paymentTile(
                label: 'Pay after Service',
                subtitle: 'Cash / UPI on completion',
                icon: Icons.payments_outlined,
                selected: _paymentMethod == 'COD',
                onTap: () => setState(() => _paymentMethod = 'COD'),
              ),
              _paymentTile(
                label: 'Pay Online',
                subtitle: 'UPI / Card / Wallet',
                icon: Icons.credit_card_rounded,
                selected: _paymentMethod == 'ONLINE',
                onTap: () => setState(() => _paymentMethod = 'ONLINE'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // ── Price Details ──
        _card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Price Details',
                  style: TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w900, color: AppColors.navy)),
              const SizedBox(height: 8),
              _kv(s != null && s.hasDiscount ? 'Service Charge' : 'Item Total',
                  '₹$listTotal'),
              if (packageDiscount > Decimal.zero)
                _kv(
                  pct != null ? 'Discount ($pct%)' : 'Discount',
                  '- ₹$packageDiscount',
                  valueColor: _okGreen,
                  labelColor: _okGreen,
                ),
              if (_couponDiscountAmount > 0)
                _kv(
                  'Coupon ($_appliedCouponCode)',
                  '- ₹$_couponDiscountAmount',
                  valueColor: _okGreen,
                  labelColor: _okGreen,
                ),
              _kv('Safety & Platform Fee', '₹$serviceFee'),
              _kv('Taxes (GST)', '₹$taxes'),
              const Divider(height: 22, color: Color(0xFFE2E8F0)),
              _kv('Total Amount', '₹$grandTotal', bold: true),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // ── Reassurance ──
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFFF3F6FC),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: [
              const Icon(Icons.verified_user_outlined, color: _okGreen, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  _paymentMethod == 'COD'
                      ? "You won't be charged now. Pay after service completion."
                      : 'Your payment is processed securely online.',
                  style: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w600, color: _mintText),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final cartItems = ref.watch(cartProvider);
    final fallbackSummary = ref.watch(cartSummaryProvider);
    final selectedAddress = ref.watch(selectedAddressProvider);

    final bool hasScheduledService = _scheduledService != null;
    final bool hasItems = hasScheduledService || cartItems.isNotEmpty;

    final Decimal subtotal;
    if (hasScheduledService) {
      subtotal =
          _scheduledService!.effectivePrice * Decimal.fromInt(_serviceQuantity);
    } else {
      subtotal = fallbackSummary.subtotal;
    }

    // Services are priced exactly like the web app / backend — see ServiceFare.
    final displayFare = ServiceFare.fromLines(
      (hasScheduledService
              ? [CartItem(service: _scheduledService!, quantity: _serviceQuantity)]
              : cartItems)
          .map((i) => (service: i.service, lineTotal: i.totalPrice)),
    );
    final Decimal serviceFee = displayFare.platformFee;
    final Decimal taxes = displayFare.gst;
    final Decimal discount = Decimal.fromInt(_couponDiscountAmount);
    final Decimal rawGrandTotal = subtotal + serviceFee + taxes - discount;
    final Decimal grandTotal =
        rawGrandTotal > Decimal.zero ? rawGrandTotal : Decimal.zero;

    final s = _scheduledService;
    final bool showStrike = s != null && s.hasDiscount;
    final Decimal listTotal =
        showStrike ? s!.price * Decimal.fromInt(_serviceQuantity) : subtotal;
    final int? discPct = showStrike ? s!.discountPercent : null;

    return PopScope(
      canPop: _step == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _step > 0) setState(() => _step = _step - 1);
      },
      child: Scaffold(
        backgroundColor: _pageBg,
        appBar: AppBar(
          backgroundColor: _pageBg,
          elevation: 0,
          scrolledUnderElevation: 0,
          titleSpacing: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_rounded, color: AppColors.navy),
            onPressed: () {
              if (_step > 0) {
                setState(() => _step = _step - 1);
              } else {
                context.goBack();
              }
            },
          ),
          title: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Booking Summary',
                  style: TextStyle(
                      color: AppColors.navy,
                      fontWeight: FontWeight.w900,
                      fontSize: 16.5)),
              Text('Complete your booking in a few steps',
                  style: TextStyle(fontSize: 11.5, color: AppColors.textSecondary)),
            ],
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
            : Column(
                children: [
                  _buildStepper(),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(14, 4, 14, 24),
                      child: _step == 0
                          ? _buildDateTimeStep()
                          : _step == 1
                              ? _buildAddressStep(selectedAddress)
                              : _buildPaymentStep(
                              hasScheduledService: hasScheduledService,
                              cartItems: cartItems,
                              subtotal: subtotal,
                              serviceFee: serviceFee,
                              taxes: taxes,
                              grandTotal: grandTotal,
                            ),
                    ),
                  ),
                ],
              ),

        // ── Floating bottom bar ──
        bottomNavigationBar: !hasItems
            ? null
            : Padding(
                padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
                child: Container(
                  padding: const EdgeInsets.fromLTRB(16, 10, 10, 10),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF1E3A8A).withValues(alpha: 0.12),
                        blurRadius: 22,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: SafeArea(
                    top: false,
                    child: Column(
                     mainAxisSize: MainAxisSize.min,
                     children: [
                      Row(
                      children: [
                        if (_step < 2) ...[
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 150),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('Item Total',
                                    style: TextStyle(
                                        fontSize: 11,
                                        color: AppColors.textSecondary,
                                        fontWeight: FontWeight.w500)),
                                FittedBox(
                                  fit: BoxFit.scaleDown,
                                  alignment: Alignment.centerLeft,
                                  child: Row(
                                    crossAxisAlignment: CrossAxisAlignment.baseline,
                                    textBaseline: TextBaseline.alphabetic,
                                    children: [
                                      Text('₹$subtotal',
                                          style: const TextStyle(
                                              fontSize: 22,
                                              fontWeight: FontWeight.w900,
                                              color: AppColors.navy)),
                                      if (showStrike) ...[
                                        const SizedBox(width: 8),
                                        Text('₹$listTotal',
                                            style: const TextStyle(
                                                fontSize: 12,
                                                color: AppColors.textHint,
                                                decoration:
                                                    TextDecoration.lineThrough)),
                                      ],
                                    ],
                                  ),
                                ),
                                if (discPct != null) ...[
                                  const SizedBox(height: 3),
                                  _discountPill(discPct),
                                ],
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                        ],
                        Expanded(
                          child: SizedBox(
                            height: 56,
                            width: double.infinity,
                            child: ElevatedButton(
                              onPressed: _isLoading
                                  ? null
                                  : (_step < 2 ? _goNext : _handlePlaceOrder),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.navy,
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16)),
                                elevation: 0,
                              ),
                              child: _isLoading
                                  ? const SizedBox(
                                      height: 22,
                                      width: 22,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2, color: Colors.white),
                                    )
                                  : Text(
                                      _step < 2 ? 'Continue' : 'Confirm Booking',
                                      style: const TextStyle(
                                          fontSize: 16, fontWeight: FontWeight.w800),
                                    ),
                            ),
                          ),
                        ),
                      ],
                    ),
                      if (_step == 2) ...[
                        const SizedBox(height: 6),
                        const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.lock_outline_rounded,
                                size: 12, color: AppColors.textHint),
                            SizedBox(width: 4),
                            Text('Your payment is 100% secure',
                                style: TextStyle(
                                    fontSize: 10.5,
                                    color: AppColors.textSecondary)),
                          ],
                        ),
                      ],
                     ],
                    ),
                  ),
                ),
              ),
      ),
    );
  }
}
