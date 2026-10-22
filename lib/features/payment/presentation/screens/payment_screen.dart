import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../shared/theme/app_colors.dart';
import '../../../../shared/widgets/common_widgets.dart';
import '../../../booking/domain/booking_providers.dart';
import '../../../../core/services/notification_service.dart';
import '../../../notifications/domain/notification_providers.dart';
import '../../domain/payment_controller.dart';
import '../../domain/payment_models.dart';
import '../../../../core/navigation/safe_back.dart';

/// Screen 16: Payment Options Screen
/// Matches reference screen 16 with amount payable banner, selectable payment methods,
/// Razorpay integration, 256-bit security seal, and sticky pay button.
/// While the real payment gateway is not live, online payments run against
/// the backend's TEST gateway. Set to false when the real gateway ships to
/// remove the "test payment" notice.
const bool kPaymentTestMode = true;

class PaymentScreen extends ConsumerStatefulWidget {
  const PaymentScreen({
    super.key,
    required this.bookingId,
    this.paymentType = 'advance',
    this.fromCheckout = false,
  });

  /// True when opened straight after "Confirm Booking" with Pay Online: a
  /// successful payment then continues to the booking-confirmed screen.
  final bool fromCheckout;

  final int bookingId;
  final String paymentType; // 'advance' | 'balance' | 'full'

  @override
  ConsumerState<PaymentScreen> createState() => _PaymentScreenState();
}

class _PaymentScreenState extends ConsumerState<PaymentScreen> {
  int _selectedMethodIndex = 0;

  final List<_PaymentMethodOption> _paymentMethods = const [
    _PaymentMethodOption(
      title: 'UPI',
      subtitle: 'GPay, PhonePe, Paytm and more',
      icon: Icons.account_balance_wallet_rounded,
    ),
    _PaymentMethodOption(
      title: 'Credit / Debit Card',
      subtitle: 'Visa, Mastercard, RuPay, Maestro',
      icon: Icons.credit_card_rounded,
    ),
    _PaymentMethodOption(
      title: 'Net Banking',
      subtitle: 'All Indian banks supported',
      icon: Icons.account_balance_rounded,
    ),
  ];

  bool _leaving = false;

  /// Back / close from the payment page. Straight after checkout the booking
  /// only exists to take this payment, so leaving unpaid withdraws it: nothing
  /// is booked until the payment goes through.
  Future<void> _leave() async {
    if (_leaving) return;
    if (!widget.fromCheckout) {
      context.goBack();
      return;
    }
    final cancel = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancel payment?'),
        content: const Text(
          'Your booking will not be placed until the payment is completed. '
          'If you leave now, it will be withdrawn.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Stay'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Leave', style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
    if (cancel != true || !mounted) return;
    setState(() => _leaving = true);
    await ref
        .read(bookingActionControllerProvider.notifier)
        .cancelBooking(widget.bookingId, 'Online payment not completed');
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Payment cancelled. Your booking was not placed.')),
    );
    context.go('/');
  }

  @override
  Widget build(BuildContext context) {
    final bookingAsync = ref.watch(bookingDetailProvider(widget.bookingId));
    final paymentState = ref.watch(paymentControllerProvider);

    // Listen for payment events
    ref.listen(paymentControllerProvider, (previous, next) {
      if (next is PaymentSuccess) {
        // The booking is only announced once the payment has gone through.
        final svcTitle = bookingAsync.valueOrNull?.items.firstOrNull?.service.title;
        const confirmedTitle = 'Booking Confirmed';
        final confirmedBody = svcTitle != null
            ? '$svcTitle has been booked successfully.'
            : 'Your booking has been placed successfully.';
        final inbox = ref.read(notificationsControllerProvider.notifier);
        if (!inbox.hasRecent(confirmedTitle)) {
          inbox.addLocal(title: confirmedTitle, body: confirmedBody);
          NotificationService.instance.show(
            title: confirmedTitle,
            body: confirmedBody,
            routePayload: '/bookings/${widget.bookingId}',
          );
        }
        showDialog<void>(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            title: const Row(
              children: [
                Icon(Icons.check_circle, color: AppColors.primary, size: 28),
                SizedBox(width: 10),
                Text(
                  'Payment Successful',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                    color: AppColors.navy,
                  ),
                ),
              ],
            ),
            content: Text(
              'Your payment has been received successfully.\n\nTransaction ID: ${next.paymentId}',
              style: const TextStyle(fontSize: 12, height: 1.4),
            ),
            actions: [
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                  onPressed: () {
                    Navigator.pop(ctx);
                    context.go(widget.fromCheckout
                        ? '/bookings/success/${widget.bookingId}'
                        : '/bookings/${widget.bookingId}');
                  },
                  child: Text(widget.fromCheckout ? 'Continue' : 'View Booking'),
                ),
              ),
            ],
          ),
        );
      } else if (next is PaymentFailed) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(next.errorMessage),
            backgroundColor: AppColors.error,
          ),
        );
      }
    });

    final booking = bookingAsync.valueOrNull;
    final amount = booking == null
        ? null
        : (widget.paymentType == 'advance'
            ? booking.advanceAmount
            : (widget.paymentType == 'balance'
                ? booking.balanceAmount
                : booking.totalAmount));
    final processing = paymentState is PaymentProcessing;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _leave();
      },
      child: Scaffold(
      backgroundColor: const Color(0xFFF6F7FA),
      appBar: AppBar(
        centerTitle: true,
        title: const Text(
          'Payment Method',
          style: TextStyle(
            color: AppColors.navy,
            fontWeight: FontWeight.w700,
            fontSize: 17,
          ),
        ),
        backgroundColor: const Color(0xFFF6F7FA),
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded,
              color: AppColors.navy, size: 20),
          onPressed: _leave,
        ),
      ),
      body: bookingAsync.when(
        loading: () => const Padding(
          padding: EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          child: Column(
            children: [
              ShimmerCard(height: 72, borderRadius: 16),
              SizedBox(height: 12),
              ShimmerCard(height: 72, borderRadius: 16),
              SizedBox(height: 12),
              ShimmerCard(height: 72, borderRadius: 16),
            ],
          ),
        ),
        error: (err, stackTrace) => ErrorStateWidget(
          message: err.toString(),
          onRetry: () => ref.refresh(bookingDetailProvider(widget.bookingId)),
        ),
        data: (booking) {
          return SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Method cards ──
                ...List.generate(_paymentMethods.length, (index) {
                  final method = _paymentMethods[index];
                  final isSelected = _selectedMethodIndex == index;
                  return GestureDetector(
                    onTap: () => setState(() => _selectedMethodIndex = index),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 160),
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                          color: isSelected
                              ? AppColors.primary
                              : Colors.transparent,
                          width: 1.4,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.navy.withValues(alpha: 0.06),
                            blurRadius: 14,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: AppColors.primaryLight,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(method.icon,
                                color: AppColors.primary, size: 22),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  method.title,
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.navy,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  method.subtitle,
                                  style: const TextStyle(
                                    fontSize: 11.5,
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Container(
                            width: 22,
                            height: 22,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: isSelected
                                    ? AppColors.navy
                                    : AppColors.border,
                                width: 1.6,
                              ),
                            ),
                            child: isSelected
                                ? Center(
                                    child: Container(
                                      width: 11,
                                      height: 11,
                                      decoration: const BoxDecoration(
                                        color: AppColors.navy,
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                  )
                                : null,
                          ),
                        ],
                      ),
                    ),
                  );
                }),

                const SizedBox(height: 8),

                // ── Highlight bar (test notice while the gateway is a mock) ──
                if (kPaymentTestMode)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 14),
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.science_outlined,
                            color: Colors.white, size: 20),
                        SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Test payment - no real money is charged.',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                const SizedBox(height: 24),

                // ── Summary ──
                _SummaryRow(
                    label: 'Booking ID', value: booking.requestId, muted: true),
                const SizedBox(height: 12),
                _SummaryRow(
                  label: widget.paymentType == 'advance'
                      ? 'Advance amount'
                      : 'Service amount',
                  value: '₹${amount ?? ''}',
                  muted: true,
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 14),
                  child: Divider(height: 1, color: AppColors.border),
                ),
                _SummaryRow(
                  label: 'Total',
                  value: '₹${amount ?? ''}',
                  bold: true,
                ),
                const SizedBox(height: 18),
                const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.lock_outline_rounded,
                        color: AppColors.textSecondary, size: 14),
                    SizedBox(width: 6),
                    Text(
                      'Safe & secure, 256-bit encrypted payment',
                      style: TextStyle(
                          fontSize: 11, color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),

      // ── Pay button ──
      bottomNavigationBar: Container(
        color: const Color(0xFFF6F7FA),
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        child: SafeArea(
          top: false,
          child: SizedBox(
            height: 56,
            child: ElevatedButton(
              onPressed: (processing || booking == null || amount == null)
                  ? null
                  : () {
                      ref.read(paymentControllerProvider.notifier).startPayment(
                            booking: booking,
                            amount: amount,
                            paymentType: widget.paymentType,
                          );
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.navy,
                foregroundColor: Colors.white,
                disabledBackgroundColor: AppColors.navy.withValues(alpha: 0.5),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
                elevation: 0,
              ),
              child: processing
                  ? const SizedBox(
                      height: 22,
                      width: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Text(
                      amount == null ? 'Pay' : 'Pay ₹$amount',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
            ),
          ),
        ),
      ),
    ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({
    required this.label,
    required this.value,
    this.muted = false,
    this.bold = false,
  });

  final String label;
  final String value;
  final bool muted;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: bold ? 15 : 13,
            fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
            color: muted ? AppColors.textSecondary : AppColors.navy,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: bold ? 18 : 14,
            fontWeight: bold ? FontWeight.w800 : FontWeight.w700,
            color: AppColors.navy,
          ),
        ),
      ],
    );
  }
}

class _PaymentMethodOption {
  const _PaymentMethodOption({
    required this.title,
    required this.subtitle,
    required this.icon,
  });

  final String title;
  final String subtitle;
  final IconData icon;
}

