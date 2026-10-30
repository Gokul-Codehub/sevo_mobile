/// Single source of truth for booking status handling in the app.
///
/// Added 2026-10-28 (whole-app status audit). The same ~30 server statuses
/// used to be bucketed separately in six places — the status chip, the My
/// Bookings active/history split, the detail-screen tracker, the live
/// tracking timeline, the notification watcher and the Booking getters —
/// each with its own subset and its own spelling rules. They disagreed:
/// a booking awaiting feedback showed "In Progress" on the detail tracker
/// but sat in History on the list; `en_route` / `service_started` had no
/// chip label; "ON_THE_WAY" or "On the way" from the vendor fell through to
/// "Requested". Every screen now asks this file instead.
library;

/// The customer-facing step a booking is at.
enum BookingStage {
  requested,
  confirmed,
  assigned,
  onTheWay,
  inProgress,
  completed,

  /// Finished without the service being done (unable to complete, quote
  /// declined, estimation closed).
  ended,
  cancelled,
}

/// Lower-case, underscores — "ON_THE_WAY", "On the way" and "on-the-way"
/// all become `on_the_way`.
String normalizeBookingStatus(Object? raw) => (raw ?? '')
    .toString()
    .trim()
    .toLowerCase()
    .replaceAll(RegExp(r'[\s-]+'), '_');

const Map<String, BookingStage> _stageByStatus = {
  // Placed, not yet confirmed.
  'draft': BookingStage.requested,
  'new_request': BookingStage.requested,
  'requested': BookingStage.requested,
  'pending_payment': BookingStage.requested,
  'waiting_for_payment': BookingStage.requested,
  'unassigned': BookingStage.requested,
  'rescheduled': BookingStage.requested,
  // Confirmed by the platform / vendor.
  'confirmed': BookingStage.confirmed,
  'reviewed': BookingStage.confirmed,
  'vendor_confirmed': BookingStage.confirmed,
  'dispatched': BookingStage.confirmed,
  'on_hold': BookingStage.confirmed,
  // A technician / driver has the job.
  'assigned': BookingStage.assigned,
  'received': BookingStage.assigned,
  'accepted': BookingStage.assigned,
  'technician_assigned': BookingStage.assigned,
  'technician_accepted': BookingStage.assigned,
  'employee_accepted': BookingStage.assigned,
  // Travelling to (or at) the customer.
  'on_the_way': BookingStage.onTheWay,
  'en_route': BookingStage.onTheWay,
  'technician_on_the_way': BookingStage.onTheWay,
  'employee_on_the_way': BookingStage.onTheWay,
  'arrived': BookingStage.onTheWay,
  'technician_arrived': BookingStage.onTheWay,
  'employee_arrived': BookingStage.onTheWay,
  // Work under way (or done, waiting for payment / verification).
  'in_progress': BookingStage.inProgress,
  'started': BookingStage.inProgress,
  'service_started': BookingStage.inProgress,
  'proof_submitted': BookingStage.inProgress,
  'cash_pending': BookingStage.inProgress,
  'payment_pending': BookingStage.inProgress,
  'inspection_in_progress': BookingStage.inProgress,
  'inspection_completed': BookingStage.inProgress,
  'quotation_sent': BookingStage.inProgress,
  'customer_approved': BookingStage.inProgress,
  'repair_authorized': BookingStage.inProgress,
  'awaiting_verification': BookingStage.inProgress,
  'rework_requested': BookingStage.inProgress,
  'follow_up_required': BookingStage.inProgress,
  // Done.
  'completed': BookingStage.completed,
  'verified': BookingStage.completed,
  'closed': BookingStage.completed,
  'feedback_pending': BookingStage.completed,
  'feedback_received': BookingStage.completed,
  // Ended without the service.
  'unable_to_complete': BookingStage.ended,
  'customer_rejected': BookingStage.ended,
  'estimation_closed': BookingStage.ended,
  // Cancelled.
  'cancelled': BookingStage.cancelled,
  'canceled': BookingStage.cancelled,
  'rejected': BookingStage.cancelled,
  'refund_requested': BookingStage.cancelled,
  'refunded': BookingStage.cancelled,
  'expired': BookingStage.cancelled,
};

/// Unknown statuses stay at [BookingStage.requested] rather than guessing
/// the job is further along than it is.
BookingStage bookingStageOf(Object? raw) =>
    _stageByStatus[normalizeBookingStatus(raw)] ?? BookingStage.requested;

/// History tab: the booking's life-cycle is over.
bool isBookingFinished(Object? raw) {
  final st = bookingStageOf(raw);
  return st == BookingStage.completed ||
      st == BookingStage.ended ||
      st == BookingStage.cancelled;
}

bool isBookingCancelled(Object? raw) => bookingStageOf(raw) == BookingStage.cancelled;

/// A technician / driver is on the job right now — live tracking applies.
/// Mirrors the server's `tracking_available` set (_build_tracking_payload).
bool isBookingTrackable(Object? raw) => const {
      'accepted',
      'technician_accepted',
      'employee_accepted',
      'on_the_way',
      'en_route',
      'technician_on_the_way',
      'employee_on_the_way',
      'arrived',
      'technician_arrived',
      'employee_arrived',
      'in_progress',
      'started',
      'service_started',
      'proof_submitted',
      'cash_pending',
    }.contains(normalizeBookingStatus(raw));

/// The technician is at the customer's address according to the server.
bool isBookingArrivedStatus(Object? raw) => const {
      'arrived',
      'technician_arrived',
      'employee_arrived',
    }.contains(normalizeBookingStatus(raw));

/// Sort key for the Active list: running jobs first, then accepted ones,
/// then everything else still in flight.
int bookingActiveRank(Object? raw) => switch (bookingStageOf(raw)) {
      BookingStage.onTheWay || BookingStage.inProgress => 0,
      BookingStage.assigned || BookingStage.confirmed => 1,
      _ => 2,
    };

const Map<String, String> _labels = {
  'draft': 'Draft',
  'new_request': 'Requested',
  'requested': 'Requested',
  'pending_payment': 'Pending Payment',
  'waiting_for_payment': 'Awaiting Payment',
  'unassigned': 'Finding Technician',
  'rescheduled': 'Rescheduled',
  'confirmed': 'Confirmed',
  'reviewed': 'Confirmed',
  'vendor_confirmed': 'Confirmed',
  'dispatched': 'Confirmed',
  'on_hold': 'On Hold',
  'assigned': 'Assigned',
  'received': 'Assigned',
  'accepted': 'Accepted',
  'technician_assigned': 'Assigned',
  'technician_accepted': 'Accepted',
  'employee_accepted': 'Accepted',
  'on_the_way': 'On the Way',
  'en_route': 'On the Way',
  'technician_on_the_way': 'On the Way',
  'employee_on_the_way': 'On the Way',
  'arrived': 'Arrived',
  'technician_arrived': 'Arrived',
  'employee_arrived': 'Arrived',
  'in_progress': 'In Progress',
  'started': 'In Progress',
  'service_started': 'In Progress',
  'proof_submitted': 'Work Submitted',
  'cash_pending': 'Payment Pending',
  'payment_pending': 'Payment Pending',
  'inspection_in_progress': 'Inspection',
  'inspection_completed': 'Inspection Done',
  'quotation_sent': 'Quote Received',
  'customer_approved': 'Quote Approved',
  'repair_authorized': 'Repair Approved',
  'awaiting_verification': 'Awaiting Verification',
  'rework_requested': 'Rework Requested',
  'follow_up_required': 'Follow-up Required',
  'completed': 'Completed',
  'verified': 'Completed',
  'closed': 'Closed',
  'feedback_pending': 'Completed',
  'feedback_received': 'Completed',
  'unable_to_complete': 'Not Completed',
  'customer_rejected': 'Quote Declined',
  'estimation_closed': 'Closed',
  'cancelled': 'Cancelled',
  'canceled': 'Cancelled',
  'rejected': 'Rejected',
  'refund_requested': 'Refund Requested',
  'refunded': 'Refunded',
  'expired': 'Expired',
};

/// Customer-facing label for any status, never raw snake_case.
String bookingStatusLabel(Object? raw) {
  final s = normalizeBookingStatus(raw);
  final known = _labels[s];
  if (known != null) return known;
  if (s.isEmpty) return 'Requested';
  return s
      .split('_')
      .where((w) => w.isNotEmpty)
      .map((w) => w[0].toUpperCase() + w.substring(1))
      .join(' ');
}
