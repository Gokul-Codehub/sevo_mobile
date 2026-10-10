import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../shared/theme/app_colors.dart';
import '../../domain/booking_models.dart';
import '../../domain/booking_providers.dart';

/// Screen 17: Order Confirmed Screen
/// Matches reference screen 17 with animated success ring, booking reference ID,
/// date/slot details, address, and live track CTA.
class BookingSuccessScreen extends ConsumerWidget {
  const BookingSuccessScreen({
    super.key,
    required this.bookingId,
    this.initialBooking,
  });

  final int bookingId;
  final Booking? initialBooking;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bookingAsync = ref.watch(bookingDetailProvider(bookingId));
    final booking = initialBooking ?? bookingAsync.valueOrNull;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        backgroundColor: Colors.white,
        elevation: 0,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          child: Column(
            children: [
              const SizedBox(height: 10),

              // ── Green Check Icon with Animated Glowing Ring ──
              const _AnimatedSuccessBadge(),
              const SizedBox(height: 20),

              const Text(
                'Booking Confirmed!',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                  color: AppColors.navy,
                  letterSpacing: -0.3,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Your service request has been scheduled successfully. Our verified technician will arrive during your chosen time slot.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13.5,
                  color: AppColors.textSecondary,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 28),

              // ── Booking Summary Card ──
              if (booking != null) ...[
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppColors.borderSubtle, width: 0.8),
                    boxShadow: const [
                      BoxShadow(
                        color: AppColors.cardShadow,
                        blurRadius: 12,
                        offset: Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      _SummaryRow(
                        label: 'Booking ID',
                        value: booking.requestId.isNotEmpty
                            ? booking.requestId
                            : '#CS-$bookingId',
                        isHighlight: true,
                      ),
                      const Divider(height: 22, color: AppColors.border),
                      _SummaryRow(
                        label: 'Service Date',
                        value: booking.scheduledDate,
                      ),
                      const SizedBox(height: 10),
                      _SummaryRow(
                        label: 'Time Slot',
                        value: booking.scheduledTimeSlot,
                      ),
                      const SizedBox(height: 10),
                      _SummaryRow(
                        label: 'Total Amount',
                        value: '₹${booking.totalAmount}',
                      ),
                      if (booking.address != null) ...[
                        const Divider(height: 22, color: AppColors.border),
                        _SummaryRow(
                          label: 'Service Address',
                          value: booking.address!.formattedAddress,
                          isMultiLine: true,
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 32),
              ],

              // ── CTA Buttons ──
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton.icon(
                  onPressed: () {
                    // Fixed 2026-08-27: this pushed '/bookings/$bookingId/track',
                    // a path that doesn't match any registered route (the real
                    // live-tracking route is '/track/:identifier' — see
                    // AppRoutes.liveTracking in app_router.dart). Every tap
                    // fell through to go_router's errorBuilder ("Page Not
                    // Found"), which is the "page error" after tapping Track
                    // right after booking. Fixed to the real route, and to
                    // the same trackingIdentifier-first pattern already used
                    // by the Track button on the booking detail screen.
                    final identifier =
                        booking?.trackingIdentifier ?? '$bookingId';
                    context.push('/track/$identifier', extra: booking);
                  },
                  icon: const Icon(Icons.navigation_rounded, size: 18),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 0,
                  ),
                  label: const Text(
                    'Track Service',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),

              SizedBox(
                width: double.infinity,
                height: 52,
                child: OutlinedButton(
                  onPressed: () => context.go('/'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.navy,
                    side: const BorderSide(color: AppColors.border, width: 1),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    'Back to Home',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),
            ],
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
    this.isHighlight = false,
    this.isMultiLine = false,
  });

  final String label;
  final String value;
  final bool isHighlight;
  final bool isMultiLine;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment:
          isMultiLine ? CrossAxisAlignment.start : CrossAxisAlignment.center,
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 13,
            color: AppColors.textSecondary,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(width: 16),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.end,
            style: TextStyle(
              fontSize: isHighlight ? 14.5 : 13,
              fontWeight: isHighlight ? FontWeight.w800 : FontWeight.w600,
              color: label == 'Total Amount'
                  ? AppColors.priceColor
                  : (isHighlight ? AppColors.navy : AppColors.textPrimary),
            ),
          ),
        ),
      ],
    );
  }
}

/// Celebratory animated badge for booking confirmation.
class _AnimatedSuccessBadge extends StatefulWidget {
  const _AnimatedSuccessBadge();

  @override
  State<_AnimatedSuccessBadge> createState() => _AnimatedSuccessBadgeState();
}

class _AnimatedSuccessBadgeState extends State<_AnimatedSuccessBadge>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scaleAnimation;
  late final Animation<double> _outerPulseAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );

    _scaleAnimation = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.0, 0.7, curve: Curves.elasticOut),
    );

    _outerPulseAnimation = Tween<double>(begin: 0.8, end: 1.15).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.2, 1.0, curve: Curves.easeOutQuad),
      ),
    );

    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Stack(
          alignment: Alignment.center,
          children: [
            // Outer glowing ring
            Transform.scale(
              scale: _outerPulseAnimation.value,
              child: Container(
                width: 112,
                height: 112,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.primary.withValues(
                    alpha: 0.12 * (1.0 - _controller.value * 0.5),
                  ),
                ),
              ),
            ),
            // Middle ring
            Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                color: const Color(0xFFF0FDF4),
                shape: BoxShape.circle,
                border: Border.all(
                  color: const Color(0xFFDCFCE7),
                  width: 6,
                ),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.2),
                    blurRadius: 18,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
            ),
            // Scaling checkmark icon
            Transform.scale(
              scale: _scaleAnimation.value,
              child: const Icon(
                Icons.check_circle_rounded,
                color: AppColors.primary,
                size: 58,
              ),
            ),
          ],
        );
      },
    );
  }
}

