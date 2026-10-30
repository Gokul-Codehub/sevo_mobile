import 'package:flutter/material.dart';

import '../../features/booking/domain/booking_status.dart';
import '../theme/app_colors.dart';
import 'status_page.dart';

/// Animated shimmer block with configurable dimensions, shape, and corner radius.
class ShimmerBox extends StatefulWidget {
  const ShimmerBox({
    super.key,
    this.width,
    this.height,
    this.borderRadius = 8,
    this.shape = BoxShape.rectangle,
  });

  final double? width;
  final double? height;
  final double borderRadius;
  final BoxShape shape;

  @override
  State<ShimmerBox> createState() => _ShimmerBoxState();
}

class _ShimmerBoxState extends State<ShimmerBox>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
    _animation = Tween<double>(begin: -2, end: 2).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return Container(
          height: widget.height,
          width: widget.width,
          decoration: BoxDecoration(
            shape: widget.shape,
            borderRadius: widget.shape == BoxShape.circle
                ? null
                : BorderRadius.circular(widget.borderRadius),
            gradient: LinearGradient(
              begin: Alignment(_animation.value - 1, 0),
              end: Alignment(_animation.value + 1, 0),
              colors: const [
                AppColors.shimmerBase,
                AppColors.shimmerHighlight,
                AppColors.shimmerBase,
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Shimmer loading placeholder for any list or card.
class ShimmerCard extends StatelessWidget {
  const ShimmerCard({
    super.key,
    this.height = 120,
    this.width = double.infinity,
    this.borderRadius = 12,
  });

  final double height;
  final double width;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    return ShimmerBox(
      height: height,
      width: width,
      borderRadius: borderRadius,
    );
  }
}

/// Circular shimmer avatar or icon placeholder.
class ShimmerCircle extends StatelessWidget {
  const ShimmerCircle({super.key, required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return ShimmerBox(
      width: size,
      height: size,
      shape: BoxShape.circle,
    );
  }
}

/// Text line skeleton placeholder.
class ShimmerLine extends StatelessWidget {
  const ShimmerLine({
    super.key,
    this.width = double.infinity,
    this.height = 12,
    this.borderRadius = 6,
  });

  final double width;
  final double height;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    return ShimmerBox(
      width: width,
      height: height,
      borderRadius: borderRadius,
    );
  }
}

/// Structured skeleton representing a product/service card (165px wide)
/// matching the exact footprint of ProductCard on Home Screen & Catalog.
class ProductCardSkeleton extends StatelessWidget {
  const ProductCardSkeleton({
    super.key,
    this.height = 228,
    this.width = 165,
    this.borderRadius = 8,
  });

  final double height;
  final double width;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(borderRadius),
        border: Border.all(color: AppColors.border, width: 0.8),
      ),
      clipBehavior: Clip.antiAlias,
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Image area
          AspectRatio(
            aspectRatio: 1.15,
            child: ShimmerBox(borderRadius: 0),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(8, 8, 8, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ShimmerLine(width: 110, height: 11),
                SizedBox(height: 6),
                ShimmerLine(width: 60, height: 9),
                SizedBox(height: 8),
                ShimmerLine(width: 50, height: 13),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Skeleton for a circular/rounded category icon tile + label line below it.
class CategoryTileSkeleton extends StatelessWidget {
  const CategoryTileSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      width: 64,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ShimmerBox(width: 48, height: 48, borderRadius: 12),
          SizedBox(height: 6),
          ShimmerLine(width: 42, height: 8),
        ],
      ),
    );
  }
}

/// Skeleton loader for a booking card, matching the structure of `_BookingCard`
/// in my_bookings_screen.dart (request-id + status chip / title / date-time row
/// / price+button footer). Shown during the very first bookings load only.
class BookingCardSkeleton extends StatelessWidget {
  const BookingCardSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.borderSubtle, width: 0.8),
        boxShadow: const [
          BoxShadow(
            color: AppColors.cardShadow,
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Row 1: request id + status chip
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              ShimmerLine(width: 120, height: 12),
              ShimmerLine(width: 72, height: 22, borderRadius: 8),
            ],
          ),
          SizedBox(height: 12),
          Divider(height: 1, color: AppColors.borderSubtle),
          SizedBox(height: 10),
          // Title
          ShimmerLine(width: double.infinity, height: 13),
          SizedBox(height: 6),
          ShimmerLine(width: 180, height: 11),
          SizedBox(height: 12),
          // Date-time row
          Row(
            children: [
              ShimmerCircle(size: 14),
              SizedBox(width: 6),
              ShimmerLine(width: 80, height: 10),
              SizedBox(width: 16),
              ShimmerCircle(size: 14),
              SizedBox(width: 6),
              ShimmerLine(width: 60, height: 10),
            ],
          ),
          SizedBox(height: 12),
          Divider(height: 1, color: AppColors.borderSubtle),
          SizedBox(height: 10),
          // Footer: price + button
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              ShimmerLine(width: 70, height: 16),
              ShimmerLine(width: 72, height: 30, borderRadius: 8),
            ],
          ),
        ],
      ),
    );
  }
}

/// Empty state widget shown when a list has no items.
class EmptyStateWidget extends StatefulWidget {
  const EmptyStateWidget({
    super.key,
    required this.title,
    required this.subtitle,
    this.emoji = '📭',
    this.action,
    this.actionLabel,
  });

  final String title;
  final String subtitle;
  final String emoji;
  final VoidCallback? action;
  final String? actionLabel;

  @override
  State<EmptyStateWidget> createState() => _EmptyStateWidgetState();
}

class _EmptyStateWidgetState extends State<EmptyStateWidget>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fadeAnim;
  late final Animation<Offset> _slideAnim;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 450),
    );
    _fadeAnim = CurvedAnimation(parent: _controller, curve: Curves.easeOut);
    _slideAnim = Tween<Offset>(
      begin: const Offset(0, 0.12),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fadeAnim,
      child: SlideTransition(
        position: _slideAnim,
        child: StatusPage(
          kind: StatusKind.empty,
          compact: true,
          title: widget.title,
          message: widget.subtitle,
          actionLabel: widget.actionLabel,
          onAction: widget.action,
        ),
      ),
    );
  }
}

/// Error state widget shown when a network call fails.
class ErrorStateWidget extends StatelessWidget {
  const ErrorStateWidget({
    super.key,
    required this.message,
    required this.onRetry,
  });

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final lower = message.toLowerCase();
    final offline = lower.contains('internet') || lower.contains('network') || lower.contains('connection');
    return StatusPage(
      kind: offline ? StatusKind.noInternet : StatusKind.error,
      compact: true,
      title: offline ? 'No internet connection' : 'Something went wrong',
      message: offline ? 'Please check your network' : message,
      actionLabel: 'Try again',
      onAction: onRetry,
    );
  }
}

/// Status chip for booking status display.
class BookingStatusChip extends StatelessWidget {
  const BookingStatusChip({super.key, required this.status});

  final String status;

  // Rewritten 2026-10-28 (status audit): colour comes from the booking's
  // stage and the label from the shared status table (booking_status.dart),
  // so every status the server can send — including vendor spellings like
  // "ON_THE_WAY" or `en_route` — gets a friendly label instead of raw
  // snake_case, and the chip always agrees with the trackers.
  static (Color, Color) _colorsFor(BookingStage stage) => switch (stage) {
        BookingStage.requested => (const Color(0xFFDDEDFF), AppColors.statusNewRequest),
        BookingStage.confirmed => (const Color(0xFFE8EDF7), AppColors.navy),
        BookingStage.assigned => (const Color(0xFFF3E8FF), AppColors.statusAssigned),
        BookingStage.onTheWay ||
        BookingStage.inProgress =>
          (const Color(0xFFFFF7E6), AppColors.statusInProgress),
        BookingStage.completed => (const Color(0xFFE8EDF7), AppColors.navy),
        BookingStage.ended => (AppColors.shimmerBase, AppColors.textSecondary),
        BookingStage.cancelled => (AppColors.errorLight, AppColors.statusCancelled),
      };

  @override
  Widget build(BuildContext context) {
    final normalized = normalizeBookingStatus(status);
    final (bgColor, textColor) = normalized == 'refund_requested'
        ? (AppColors.warningLight, AppColors.statusRefundRequested)
        : _colorsFor(bookingStageOf(normalized));
    final label = bookingStatusLabel(normalized);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: textColor,
          fontSize: 11.5,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
