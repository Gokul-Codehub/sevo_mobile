import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/booking/domain/booking_models.dart';
import '../../features/booking/domain/booking_providers.dart';
import 'notification_service.dart';

/// Mounted once at the app root (see main.dart) — watches the customer's
/// own bookings and posts a real device notification (via
/// [NotificationService]) whenever a booking's status actually changes
/// since the last time this running app checked.
///
/// This complements the immediate "Booking Placed" notification fired
/// directly from `BookingActionController.createBooking()` on success —
/// this watcher instead covers everything that happens to a booking
/// AFTER it's placed (confirmed, technician assigned, on the way,
/// completed, cancelled, ...), none of which the app would otherwise
/// learn about until the customer happens to reopen the Bookings screen.
///
/// Still a LOCAL mechanism, not push (see NotificationService's doc
/// comment): it can only notice a change when this code actually runs,
/// which is (a) on this 45s poll while the app is open, and (b) whenever
/// `myBookingsProvider` is refetched anywhere else (opening the Bookings
/// tab, resuming the app from background, right after placing a new
/// booking). A status change that happens while the app is fully closed
/// won't be noticed until the app is reopened.
class BookingNotificationWatcher extends ConsumerStatefulWidget {
  const BookingNotificationWatcher({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<BookingNotificationWatcher> createState() =>
      _BookingNotificationWatcherState();
}

class _BookingNotificationWatcherState
    extends ConsumerState<BookingNotificationWatcher>
    with WidgetsBindingObserver {
  Timer? _pollTimer;

  /// booking id -> last status this app has seen for it. Seeded (not
  /// notified on) the first time bookings load after app start, so
  /// opening the app never fires a wall of notifications for bookings
  /// whose status changed while the app was closed — those are exactly
  /// the changes true push would have covered; this local fallback only
  /// notifies on changes it watches happen live.
  final Map<int, String> _lastKnownStatus = {};
  bool _seeded = false;

  static const _pollInterval = Duration(seconds: 45);

  // Only these transitions are worth interrupting the customer for — the
  // rest of the 23-status lifecycle (draft, pending_payment,
  // waiting_for_payment, reviewed, received, accepted, awaiting_
  // verification, verified, feedback_pending/received, rework_requested,
  // follow_up_required) is either pre-booking, too granular, or not
  // something the backend actually surfaces as customer-facing yet.
  static const _notifiableStatuses = {
    'confirmed',
    'assigned',
    'on_the_way',
    'arrived',
    'in_progress',
    'completed',
    'closed',
    'cancelled',
    'rejected',
    'rescheduled',
  };

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    NotificationService.instance.initialize();
    _pollTimer = Timer.periodic(_pollInterval, (_) {
      ref.invalidate(myBookingsProvider(null));
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ref.invalidate(myBookingsProvider(null));
    }
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  String _titleFor(String status) => switch (status) {
        'confirmed' => 'Booking Confirmed',
        'assigned' => 'Technician Assigned',
        'on_the_way' => 'Technician On The Way',
        'arrived' => 'Technician Has Arrived',
        'in_progress' => 'Service In Progress',
        'completed' || 'closed' => 'Service Completed',
        'cancelled' || 'rejected' => 'Booking Cancelled',
        'rescheduled' => 'Booking Rescheduled',
        _ => 'Booking Update',
      };

  String _bodyFor(Booking booking, String status) {
    final label =
        booking.items.isNotEmpty ? booking.items.first.service.title : 'Your booking';
    final tech = booking.technician?.name;
    return switch (status) {
      'confirmed' => '$label has been confirmed.',
      'assigned' => tech != null
          ? '$tech has been assigned to $label.'
          : 'A technician has been assigned to $label.',
      'on_the_way' =>
        tech != null ? '$tech is on the way for $label.' : 'Your technician is on the way.',
      'arrived' => 'Your technician has arrived for $label.',
      'in_progress' => '$label is now in progress.',
      'completed' || 'closed' => '$label has been completed. Rate your experience!',
      'cancelled' || 'rejected' => '$label was cancelled.',
      'rescheduled' => '$label has been rescheduled.',
      _ => '$label status updated to ${status.replaceAll('_', ' ')}.',
    };
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<AsyncValue<List<Booking>>>(myBookingsProvider(null), (previous, next) {
      final bookings = next.valueOrNull;
      if (bookings == null) return;

      if (!_seeded) {
        for (final b in bookings) {
          _lastKnownStatus[b.id] = b.status;
        }
        _seeded = true;
        return;
      }

      for (final booking in bookings) {
        final previousStatus = _lastKnownStatus[booking.id];
        _lastKnownStatus[booking.id] = booking.status;

        if (previousStatus == null) {
          // A booking this app hasn't seen before — createBooking()
          // already notified "Booking Placed" for one just created here;
          // one created elsewhere (e.g. web) with no prior local status
          // isn't announced retroactively, to avoid guessing how long
          // ago it actually changed.
          continue;
        }
        if (previousStatus == booking.status) continue;
        if (!_notifiableStatuses.contains(booking.status)) continue;

        NotificationService.instance.show(
          title: _titleFor(booking.status),
          body: _bodyFor(booking, booking.status),
          routePayload: '/bookings/${booking.id}',
        );
      }
    });

    return widget.child;
  }
}
