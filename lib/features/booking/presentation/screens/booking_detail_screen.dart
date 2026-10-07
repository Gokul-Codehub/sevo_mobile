import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/errors/api_error.dart';
import '../../../../shared/theme/app_colors.dart';
import '../../../../shared/widgets/common_widgets.dart';
import '../../data/booking_repository.dart';
import '../../domain/booking_models.dart';
import '../../domain/booking_providers.dart';
import '../widgets/active_quote_card.dart';

/// Comprehensive booking detail screen with timeline, actions, and technician info.
class BookingDetailScreen extends ConsumerWidget {
  const BookingDetailScreen({
    super.key,
    required this.bookingId,
    this.initialBooking,
  });

  final int bookingId;
  final Booking? initialBooking;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final bookingAsync = ref.watch(bookingDetailProvider(bookingId));
    final booking = bookingAsync.valueOrNull ?? initialBooking;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Booking Details'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.refresh(bookingDetailProvider(bookingId)),
          ),
        ],
      ),
      body: booking != null
          ? _buildContent(context, ref, theme, booking)
          : bookingAsync.when(
              loading: () => const Padding(
                padding: EdgeInsets.all(20),
                child: Column(
                  children: [
                    ShimmerCard(height: 120),
                    SizedBox(height: 16),
                    ShimmerCard(height: 180),
                    SizedBox(height: 16),
                    ShimmerCard(height: 140),
                  ],
                ),
              ),
              error: (err, stackTrace) => ErrorStateWidget(
                message: err.toString(),
                onRetry: () => ref.refresh(bookingDetailProvider(bookingId)),
              ),
              data: (b) => _buildContent(context, ref, theme, b),
            ),
    );
  }

  Widget _buildContent(
    BuildContext context,
    WidgetRef ref,
    ThemeData theme,
    Booking booking,
  ) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
                // ── 1. Header Card with ID and Status ───────────────────────
                Card(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                    side: const BorderSide(color: AppColors.border, width: 0.5),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Service Request',
                              style: TextStyle(
                                fontSize: 11,
                                color: AppColors.textSecondary,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              booking.requestId,
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: AppColors.primary,
                              ),
                            ),
                          ],
                        ),
                        BookingStatusChip(status: booking.status),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 16),

                // ── 1b. Active Quotation (Painting/Masonry/AC-Inspection) ───
                // Added 2026-09-26: this ESTIMATION-kind booking may have a
                // live quotation attached (see ActiveQuoteCard's doc
                // comment) — shows nothing when booking.quote is null, so
                // this is a no-op for every ordinary fixed-price booking.
                if (booking.hasActiveQuote) ...[
                  ActiveQuoteCard(booking: booking),
                  const SizedBox(height: 16),
                ],

                // ── 2. Booking Timeline Tracker ─────────────────────────────
                Card(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                    side: const BorderSide(color: AppColors.border, width: 0.5),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Service Status Tracker',
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 16),
                        _TimelineTracker(currentStatus: booking.status),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 16),

                // ── 3. Assigned Technician Card (if assigned) ───────────────
                if (booking.technician != null) ...[
                  Card(
                    color: AppColors.surfaceVariant,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                      side: const BorderSide(color: AppColors.primaryLight, width: 0.5),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              ClipOval(
                                child: (booking.technician!.profilePictureUrl != null &&
                                        booking.technician!.profilePictureUrl!.isNotEmpty)
                                    ? CachedNetworkImage(
                                        imageUrl: booking.technician!.profilePictureUrl!,
                                        width: 48,
                                        height: 48,
                                        fit: BoxFit.cover,
                                        placeholder: (context, url) => Container(
                                          width: 48,
                                          height: 48,
                                          color: AppColors.primary,
                                        ),
                                        errorWidget: (context, url, error) =>
                                            _buildTechAvatarFallback(booking.technician!.name),
                                      )
                                    : _buildTechAvatarFallback(booking.technician!.name),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'ASSIGNED TECHNICIAN',
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                        color: AppColors.primaryDark,
                                        letterSpacing: 0.5,
                                      ),
                                    ),
                                    Text(
                                      booking.technician!.name,
                                      style: theme.textTheme.titleMedium?.copyWith(
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    // Only shown when the backend actually sent a
                                    // rating/job count — never a made-up 4.9 (fixed
                                    // 2026-08-27, see TechnicianInfo.rating).
                                    if (booking.technician!.rating != null)
                                      Row(
                                        children: [
                                          const Icon(
                                            Icons.star_rounded,
                                            size: 16,
                                            color: AppColors.warning,
                                          ),
                                          const SizedBox(width: 2),
                                          Text(
                                            booking.technician!.rating!.toStringAsFixed(1),
                                            style: const TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                          if (booking.technician!.completedJobsCount != null)
                                            Text(
                                              ' (${booking.technician!.completedJobsCount} jobs completed)',
                                              style: const TextStyle(
                                                fontSize: 11,
                                                color: AppColors.textSecondary,
                                              ),
                                            ),
                                        ],
                                      ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const Divider(height: 20),
                          Row(
                            children: [
                              if (booking.technician!.phone != null) ...[
                                Expanded(
                                  child: OutlinedButton.icon(
                                    onPressed: () {
                                      final uri = Uri.parse(
                                        'tel:${booking.technician!.phone}',
                                      );
                                      launchUrl(uri);
                                    },
                                    icon: const Icon(Icons.call, size: 16),
                                    label: const Text('Call Pro'),
                                  ),
                                ),
                                const SizedBox(width: 10),
                              ],
                              Expanded(
                                child: FilledButton.icon(
                                  onPressed: () {
                                    final identifier =
                                        booking.trackingIdentifier ?? '${booking.id}';
                                    // Pass the full booking so the tracking
                                    // screen can show the real assigned
                                    // technician (name/phone/rating/photo)
                                    // and real service address instead of
                                    // depending solely on the live-location
                                    // feed for that data.
                                    context.push('/track/$identifier', extra: booking);
                                  },
                                  icon: const Icon(Icons.location_on, size: 16),
                                  label: const Text('Live Track'),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],

                // ── 4. Appointment Schedule & Location ──────────────────────
                Card(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                    side: const BorderSide(color: AppColors.border, width: 0.5),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Schedule & Location',
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 14),
                        Row(
                          children: [
                            const Icon(
                              Icons.calendar_today_outlined,
                              size: 18,
                              color: AppColors.primary,
                            ),
                            const SizedBox(width: 10),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  booking.scheduledDate,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
                                  ),
                                ),
                                Text(
                                  booking.scheduledTimeSlot,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                        if (booking.address != null) ...[
                          const Divider(height: 20),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(
                                Icons.location_on_outlined,
                                size: 18,
                                color: AppColors.primary,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      booking.address!.addressType.toUpperCase(),
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 12,
                                        color: AppColors.primary,
                                      ),
                                    ),
                                    Text(
                                      booking.address!.formattedAddress,
                                      style: const TextStyle(
                                        fontSize: 13,
                                        color: AppColors.textPrimary,
                                        height: 1.3,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 16),

                // ── 5. Service Items & Bill Summary ─────────────────────────
                Card(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                    side: const BorderSide(color: AppColors.border, width: 0.5),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Services & Payment Summary',
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 12),
                        ...booking.items.map(
                          (item) => Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: Text(
                                    '${item.service.title} x ${item.quantity}',
                                    style: const TextStyle(fontSize: 13),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  '₹${item.totalPrice}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const Divider(height: 20),
                        _BillRow(
                          label: 'Total Amount',
                          amount: '₹${booking.totalAmount}',
                          isBold: true,
                        ),
                        const SizedBox(height: 6),
                        // Fixed 2026-09-17 per explicit report: this row
                        // used to unconditionally read "Advance Paid: ₹X"
                        // for every booking — X being a fabricated 20% of
                        // the total that the backend never actually sent —
                        // even when no payment had been made at all. It now
                        // reflects the booking's real `payment_status`:
                        // only a 'paid' booking claims an amount was paid;
                        // everything else (pending, partial without a real
                        // figure, refunded, failed) is shown as owed, never
                        // as a paid receipt that didn't happen.
                        ..._paymentSummaryRows(booking),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 24),

                // ── 6. Action Buttons driven strictly by available_actions ──
                if (booking.canReschedule || booking.canCancel) ...[
                  Row(
                    children: [
                      if (booking.canReschedule) ...[
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () => _showRescheduleModal(context, ref, booking),
                            icon: const Icon(Icons.event_repeat),
                            label: const Text('Reschedule'),
                          ),
                        ),
                        const SizedBox(width: 12),
                      ],
                      if (booking.canCancel) ...[
                        Expanded(
                          child: OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppColors.error,
                              side: const BorderSide(color: AppColors.errorLight),
                            ),
                            onPressed: () => _showCancelDialog(context, ref, booking),
                            icon: const Icon(Icons.cancel_outlined),
                            label: const Text('Cancel'),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 16),
                ],

                if (booking.canPayBalance) ...[
                  FilledButton.icon(
                    onPressed: () {
                      context.push('/checkout/payment?booking=${booking.id}&type=balance');
                    },
                    icon: const Icon(Icons.payment),
                    label: Text('Pay Balance (₹${booking.balanceAmount})'),
                  ),
                  const SizedBox(height: 16),
                ],

                if (booking.canRate) ...[
                  FilledButton.tonalIcon(
                    onPressed: () {
                      context.push('/feedback/${booking.requestId}');
                    },
                    icon: const Icon(Icons.star_outline),
                    label: const Text('Rate Service Experience'),
                  ),
                  const SizedBox(height: 16),
                ],

                // Fixed per explicit report ("after the payment there user
                // should get the invoice that also not places in Booking to
                // seen by user"): the backend already generates a real,
                // ownership-verified invoice PDF
                // (GET /api/booking/<id>/invoice/) — this app just never
                // called it. Mirrors the backend's own restriction
                // (service_requests/payment_views.py InvoiceDownloadView):
                // not available for a cancelled or rejected booking.
                if (booking.status != 'cancelled' && booking.status != 'rejected') ...[
                  OutlinedButton.icon(
                    onPressed: () => _downloadInvoice(context, ref, booking),
                    icon: const Icon(Icons.receipt_long_outlined),
                    label: const Text('Download Invoice'),
                  ),
                  const SizedBox(height: 16),
                ],

                const SizedBox(height: 40),
              ],
            ),
          );
  }

  // Fetches the real backend-generated invoice PDF and hands it to the
  // system share sheet so the customer can view, save, or send it on --
  // avoids building a dedicated in-app PDF viewer just for this.
  Future<void> _downloadInvoice(
      BuildContext context, WidgetRef ref, Booking booking) async {
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(const SnackBar(content: Text('Preparing invoice…')));

    final result =
        await ref.read(bookingRepositoryProvider).downloadInvoice(booking.id);

    if (!context.mounted) return;

    switch (result) {
      case Success(:final data):
        try {
          final dir = await getTemporaryDirectory();
          final file = File('${dir.path}/Invoice-${booking.requestId}.pdf');
          await file.writeAsBytes(data, flush: true);
          await Share.shareXFiles(
            [XFile(file.path, mimeType: 'application/pdf')],
            subject: 'Invoice ${booking.requestId}',
          );
        } catch (_) {
          if (context.mounted) {
            messenger.showSnackBar(const SnackBar(
              content: Text('Could not open the invoice. Please try again.'),
              backgroundColor: AppColors.error,
            ));
          }
        }
      case Failure(:final error):
        messenger.showSnackBar(SnackBar(
          content: Text(error.message),
          backgroundColor: AppColors.error,
        ));
    }
  }

  // Preset cancellation reasons shown as selectable options, with a final
  // "Other" option that reveals a free-text field -- replaces the old
  // single open TextField per the user's request for a pick-list.
  static const _cancelReasonOptions = <String>[
    'Plans changed',
    'Booked by mistake',
    'Found a better price elsewhere',
    'Taking too long to get assigned',
    'Need to reschedule instead',
  ];

  void _showCancelDialog(BuildContext context, WidgetRef ref, Booking booking) {
    final otherController = TextEditingController();
    String? selectedReason;

    showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) {
          final isOther = selectedReason == 'Other';
          return AlertDialog(
            title: const Text('Cancel Booking'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Are you sure you want to cancel this booking? If advance was paid, refund will be initiated.',
                    style: TextStyle(fontSize: 13),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'Reason for cancellation',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                  ..._cancelReasonOptions.map(
                    (reason) => RadioListTile<String>(
                      value: reason,
                      groupValue: selectedReason,
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      visualDensity: VisualDensity.compact,
                      title: Text(reason, style: const TextStyle(fontSize: 13)),
                      onChanged: (value) => setState(() => selectedReason = value),
                    ),
                  ),
                  RadioListTile<String>(
                    value: 'Other',
                    groupValue: selectedReason,
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    visualDensity: VisualDensity.compact,
                    title: const Text('Other', style: TextStyle(fontSize: 13)),
                    onChanged: (value) => setState(() => selectedReason = value),
                  ),
                  if (isOther) ...[
                    const SizedBox(height: 6),
                    TextField(
                      controller: otherController,
                      autofocus: true,
                      decoration: const InputDecoration(
                        labelText: 'Please specify',
                        hintText: 'Type your reason',
                      ),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Keep Booking'),
              ),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: AppColors.error),
                onPressed: selectedReason == null || (isOther && otherController.text.trim().isEmpty)
                    ? null
                    : () async {
                        final finalReason = isOther
                            ? otherController.text.trim()
                            : selectedReason!;
                        Navigator.pop(ctx);
                        final error = await ref
                            .read(bookingActionControllerProvider.notifier)
                            .cancelBooking(booking.id, finalReason);
                        if (error != null && context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text(error), backgroundColor: AppColors.error),
                          );
                        }
                      },
                child: const Text('Confirm Cancel'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showRescheduleModal(BuildContext context, WidgetRef ref, Booking booking) {
    DateTime selectedDate = DateTime.now().add(const Duration(days: 1));
    String selectedSlot = '09:00 AM - 11:00 AM';

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(8)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Reschedule Booking',
                style: Theme.of(ctx).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: 16),
              const Text('Select new appointment date:'),
              const SizedBox(height: 8),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.calendar_month, color: AppColors.primary),
                title: Text(DateFormat('EEEE, d MMMM yyyy').format(selectedDate)),
                trailing: const Text('Change', style: TextStyle(color: AppColors.primary)),
                onTap: () async {
                  final picked = await showDatePicker(
                    context: ctx,
                    initialDate: selectedDate,
                    firstDate: DateTime.now().add(const Duration(days: 1)),
                    lastDate: DateTime.now().add(const Duration(days: 14)),
                  );
                  if (picked != null) {
                    setModalState(() => selectedDate = picked);
                  }
                },
              ),
              const SizedBox(height: 16),
              const Text('Select new time slot:'),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  '09:00 AM - 11:00 AM',
                  '11:00 AM - 01:00 PM',
                  '02:00 PM - 04:00 PM',
                  '04:00 PM - 06:00 PM',
                  '06:00 PM - 08:00 PM',
                ].map((slot) {
                  final isSelected = selectedSlot == slot;
                  return ChoiceChip(
                    label: Text(slot, style: const TextStyle(fontSize: 12)),
                    selected: isSelected,
                    onSelected: (val) {
                      if (val) setModalState(() => selectedSlot = slot);
                    },
                  );
                }).toList(),
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: () async {
                  Navigator.pop(ctx);
                  final formattedDate = DateFormat('yyyy-MM-dd').format(selectedDate);
                  final error = await ref
                      .read(bookingActionControllerProvider.notifier)
                      .rescheduleBooking(
                        id: booking.id,
                        date: formattedDate,
                        slot: selectedSlot,
                      );
                  if (error != null && context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(error), backgroundColor: AppColors.error),
                    );
                  }
                },
                child: const Text('Confirm Reschedule'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TimelineTracker extends StatelessWidget {
  const _TimelineTracker({required this.currentStatus});

  final String currentStatus;

  // Fixed 2026-08-27: the real ServiceRequest lifecycle has 23 statuses
  // (backend/service_requests/state_machine.py), but this tracker only
  // recognized 5 of them — every other real status (arrived, on_the_way,
  // accepted, received, reviewed, unassigned, etc.) silently fell through
  // to the default `_ => 0`, so a booking that had genuinely progressed to
  // "arrived" still rendered as if it were freshly "Requested". Widened to
  // a 6-step tracker covering every documented status, bucketed by how far
  // along the job actually is.
  static const _steps = [
    ('new_request', 'Requested'),
    ('confirmed', 'Confirmed'),
    ('assigned', 'Assigned'),
    ('on_the_way', 'On the Way'),
    ('in_progress', 'In Progress'),
    ('completed', 'Completed'),
  ];

  static const _terminalStatuses = {'cancelled', 'refund_requested', 'rejected'};

  int get _currentIndex {
    return switch (currentStatus) {
      'draft' ||
      'new_request' ||
      'pending_payment' ||
      'waiting_for_payment' ||
      'rescheduled' ||
      'unassigned' =>
        0,
      'confirmed' || 'reviewed' => 1,
      'assigned' || 'received' || 'accepted' => 2,
      'on_the_way' || 'arrived' => 3,
      'in_progress' ||
      'awaiting_verification' ||
      'verified' ||
      'feedback_pending' ||
      'feedback_received' ||
      'rework_requested' ||
      'follow_up_required' =>
        4,
      'completed' || 'closed' => 5,
      'cancelled' || 'refund_requested' || 'rejected' => -1,
      _ => 0,
    };
  }

  @override
  Widget build(BuildContext context) {
    if (_terminalStatuses.contains(currentStatus)) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.errorLight,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          children: [
            const Icon(Icons.cancel, color: AppColors.error, size: 20),
            const SizedBox(width: 10),
            Text(
              currentStatus == 'refund_requested'
                  ? 'Booking Cancelled — Refund in Progress'
                  : currentStatus == 'rejected'
                      ? 'This booking was rejected'
                      : 'This booking has been cancelled',
              style: const TextStyle(
                color: AppColors.error,
                fontWeight: FontWeight.w600,
                fontSize: 12,
              ),
            ),
          ],
        ),
      );
    }

    final activeIndex = _currentIndex;

    return Row(
      children: List.generate(_steps.length * 2 - 1, (index) {
        if (index.isOdd) {
          // Connector Line
          final stepIndex = index ~/ 2;
          final isCompleted = stepIndex < activeIndex;
          return Expanded(
            child: Container(
              height: 2,
              color: isCompleted ? AppColors.primary : AppColors.divider,
            ),
          );
        }

        final stepIndex = index ~/ 2;
        final isPassed = stepIndex <= activeIndex;
        final label = _steps[stepIndex].$2;

        return Column(
          children: [
            Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isPassed ? AppColors.primary : AppColors.surface,
                border: Border.all(
                  color: isPassed ? AppColors.primary : AppColors.border,
                  width: 2,
                ),
              ),
              child: isPassed
                  ? const Icon(Icons.check, size: 12, color: Colors.white)
                  : null,
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 9,
                fontWeight: isPassed ? FontWeight.bold : FontWeight.normal,
                color: isPassed ? AppColors.primary : AppColors.textSecondary,
              ),
            ),
          ],
        );
      }),
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
      children: [
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              fontSize: isBold ? 14 : 12,
              fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
              color: isBold ? AppColors.textPrimary : AppColors.textSecondary,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          amount,
          style: TextStyle(
            fontSize: isBold ? 15 : 12,
            fontWeight: isBold ? FontWeight.bold : FontWeight.w600,
            color: AppColors.textPrimary,
          ),
        ),
      ],
    );
  }
}

// Fixed 2026-09-17 per explicit report ("there is hardcoded like Advance
// paid even i dont have made any payment"): this used to be two
// unconditional _BillRow widgets ("Advance Paid" / "Balance Remaining")
// computed from a fabricated 20%-of-total split that booking_models.dart
// invented whenever the backend didn't send a real advance_amount — which,
// per the real booking API, it never does. There is no advance/deposit
// concept in the backend at all. This now shows only what payment_status
// actually says: a real "Amount Paid" row when the booking is genuinely
// 'paid', an honest "Amount Due" row otherwise, and a plain status line for
// 'refunded' — never an invented partial figure.
List<Widget> _paymentSummaryRows(Booking booking) {
  switch (booking.paymentStatus) {
    case 'paid':
      return [
        _BillRow(
          label: 'Amount Paid',
          amount: '₹${booking.totalAmount}',
        ),
      ];
    case 'refunded':
      return [
        const _BillRow(
          label: 'Payment Status',
          amount: 'Refunded',
        ),
      ];
    case 'partially_paid':
      return [
        const _BillRow(
          label: 'Payment Status',
          amount: 'Partially Paid',
        ),
      ];
    case 'pending':
    default:
      return [
        _BillRow(
          label: 'Amount Due',
          amount: '₹${booking.totalAmount}',
        ),
      ];
  }
}

Widget _buildTechAvatarFallback(String? name) {
  final initial = (name != null && name.trim().isNotEmpty)
      ? name.trim()[0].toUpperCase()
      : 'T';
  return Container(
    width: 48,
    height: 48,
    color: AppColors.primary,
    child: Center(
      child: Text(
        initial,
        style: const TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.bold,
          color: Colors.white,
        ),
      ),
    ),
  );
}
