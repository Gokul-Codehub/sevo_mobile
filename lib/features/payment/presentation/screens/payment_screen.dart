import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../shared/theme/app_colors.dart';
import '../../../../shared/widgets/common_widgets.dart';
import '../../../booking/domain/booking_providers.dart';
import '../../domain/payment_controller.dart';
import '../../domain/payment_models.dart';

/// Screen 16: Payment Options Screen
/// Matches reference screen 16 with amount payable banner, selectable payment methods,
/// Razorpay integration, 256-bit security seal, and sticky pay button.
class PaymentScreen extends ConsumerStatefulWidget {
  const PaymentScreen({
    super.key,
    required this.bookingId,
    this.paymentType = 'advance',
  });

  final int bookingId;
  final String paymentType; // 'advance' | 'balance' | 'full'

  @override
  ConsumerState<PaymentScreen> createState() => _PaymentScreenState();
}

class _PaymentScreenState extends ConsumerState<PaymentScreen> {
  int _selectedMethodIndex = 0;

  final List<_PaymentMethodOption> _paymentMethods = const [
    _PaymentMethodOption(
      title: 'UPI (GPay / PhonePe / Paytm)',
      subtitle: 'Instant payment via any UPI app',
      icon: Icons.account_balance_wallet_rounded,
    ),
    _PaymentMethodOption(
      title: 'Credit / Debit Cards',
      subtitle: 'Visa, Mastercard, RuPay, Maestro',
      icon: Icons.credit_card_rounded,
    ),
    _PaymentMethodOption(
      title: 'Net Banking',
      subtitle: 'All Indian banks supported',
      icon: Icons.account_balance_rounded,
    ),
    _PaymentMethodOption(
      title: 'Pay After Service (Cash / UPI)',
      subtitle: 'Pay directly to technician upon completion',
      icon: Icons.payments_rounded,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final bookingAsync = ref.watch(bookingDetailProvider(widget.bookingId));
    final paymentState = ref.watch(paymentControllerProvider);

    // Listen for payment events
    ref.listen(paymentControllerProvider, (previous, next) {
      if (next is PaymentSuccess) {
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
                    fontSize: 18,
                    color: AppColors.navy,
                  ),
                ),
              ],
            ),
            content: Text(
              'Your payment has been received successfully.\n\nTransaction ID: ${next.paymentId}',
              style: const TextStyle(fontSize: 13, height: 1.4),
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
                    context.go('/bookings/${widget.bookingId}');
                  },
                  child: const Text('View Booking'),
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

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text(
          'Payment Options',
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
      body: bookingAsync.when(
        loading: () => const Padding(
          padding: EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          child: Column(
            children: [
              ShimmerCard(height: 140, borderRadius: 16),
              SizedBox(height: 16),
              ShimmerCard(height: 180, borderRadius: 14),
              SizedBox(height: 16),
              ShimmerCard(height: 60, borderRadius: 12),
            ],
          ),
        ),
        error: (err, stackTrace) => ErrorStateWidget(
          message: err.toString(),
          onRetry: () =>
              ref.refresh(bookingDetailProvider(widget.bookingId)),
        ),
        data: (booking) {
          final amount = widget.paymentType == 'advance'
              ? booking.advanceAmount
              : (widget.paymentType == 'balance'
                  ? booking.balanceAmount
                  : booking.totalAmount);

          return SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Total Amount Card ──
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.border, width: 0.8),
                  ),
                  child: Column(
                    children: [
                      Text(
                        widget.paymentType == 'advance'
                            ? 'Advance Deposit Payable'
                            : 'Total Amount Payable',
                        style: const TextStyle(
                          fontSize: 13,
                          color: AppColors.textSecondary,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '₹$amount',
                        style: const TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.w900,
                          color: AppColors.navy,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppColors.primaryLight,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          'Booking ID: ${booking.requestId}',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: AppColors.primary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 24),

                // ── Select Payment Method ──
                const Text(
                  'Select Payment Method',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: AppColors.navy,
                  ),
                ),
                const SizedBox(height: 12),

                ...List.generate(_paymentMethods.length, (index) {
                  final method = _paymentMethods[index];
                  final isSelected = _selectedMethodIndex == index;

                  return GestureDetector(
                    onTap: () =>
                        setState(() => _selectedMethodIndex = index),
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? const Color(0xFFF0FDF4)
                            : Colors.white,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: isSelected
                              ? AppColors.primary
                              : AppColors.border,
                          width: isSelected ? 1.8 : 0.8,
                        ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? AppColors.primaryLight
                                  : const Color(0xFFF1F5F9),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Icon(
                              method.icon,
                              color: isSelected
                                  ? AppColors.primary
                                  : AppColors.navy,
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  method.title,
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                    color: isSelected
                                        ? AppColors.navy
                                        : AppColors.textPrimary,
                                  ),
                                ),
                                const SizedBox(height: 2),
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
                          Icon(
                            isSelected
                                ? Icons.radio_button_checked_rounded
                                : Icons.radio_button_off_rounded,
                            color: isSelected
                                ? AppColors.primary
                                : AppColors.textHint,
                            size: 20,
                          ),
                        ],
                      ),
                    ),
                  );
                }),

                const SizedBox(height: 16),

                // ── 100% Secure Seal ──
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: AppColors.border, width: 0.8),
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.verified_user_rounded,
                        color: AppColors.primary,
                        size: 18,
                      ),
                      SizedBox(width: 8),
                      Text(
                        '100% Safe & Secure 256-Bit Encrypted Payment',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: AppColors.navy,
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 120),
              ],
            ),
          );
        },
      ),

      // ── Fixed Sticky Bottom Bar ──
      bottomNavigationBar: Container(
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
        child: SizedBox(
          height: 52,
          child: ElevatedButton(
            onPressed: paymentState is PaymentProcessing
                ? null
                : () {
                    final booking = bookingAsync.valueOrNull;
                    if (booking != null) {
                      final amount = widget.paymentType == 'advance'
                          ? booking.advanceAmount
                          : (widget.paymentType == 'balance'
                              ? booking.balanceAmount
                              : booking.totalAmount);

                      ref
                          .read(paymentControllerProvider.notifier)
                          .startPayment(
                            booking: booking,
                            amount: amount,
                            paymentType: widget.paymentType,
                          );
                    }
                  },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              elevation: 0,
            ),
            child: paymentState is PaymentProcessing
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Text(
                    'Proceed to Pay',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
          ),
        ),
      ),
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

