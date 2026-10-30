import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/booking/domain/booking_models.dart';
import '../../features/booking/domain/booking_providers.dart';
import '../../features/notifications/domain/notification_providers.dart';
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

  /// 45 s normally; 15 s while a technician is assigned or on the way, so
  /// "On the way" / "Arrived" alerts are not a minute late.
  static const _idlePollInterval = Duration(seconds: 45);
  static const _activePollInterval = Duration(seconds: 15);
  Duration _currentInterval = _idlePollInterval;

  // Rewritten 2026-10-28 (status audit): alerts follow the booking's STAGE
  // (booking_status.dart), not its raw status string. Before, vendor
  // spellings (`en_route`, `technician_arrived`, "ON_THE_WAY") never matched
  // the list and were silently skipped, `accepted` (the moment the customer
  // actually has a technician) never alerted, and a status that flapped
  // between two polls (e.g. arrived -> on_the_way -> arrived) alerted again
  // each time. Now: one alert per step forward, plus cancelled / ended /
  // rescheduled.
  final Map<int, int> _highestNotifiedStep = {};

  static int _step(String status) => switch (bookingStageOf(status)) {
        BookingStage.requested => 0,
        BookingStage.confirmed => 1,
        BookingStage.assigned => 2,
        BookingStage.onTheWay => isBookingArrivedStatus(status) ? 4 : 3,
        BookingStage.inProgress => 5,
        BookingStage.completed => 6,
        BookingStage.ended || BookingStage.cancelled => 7,
      };

  void _schedulePoll(List<Booking>? bookings) {
    final busy = bookings != null &&
        bookings.any((b) {
          final st = bookingStageOf(b.status);
          return st == BookingStage.assigned ||
              st == BookingStage.onTheWay ||
              st == BookingStage.inProgress;
        });
    final wanted = busy ? _activePollInterval : _idlePollInterval;
    if (_pollTimer != null && wanted == _currentInterval) return;
    _currentInterval = wanted;
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(wanted, (_) {
      ref.invalidate(myBookingsProvider(null));
    });
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    NotificationService.instance.initialize();
    _schedulePoll(null);
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

  // Titles match the server's inbox titles (service_requests/
  // notifications.py) so NotificationsController.hasRecent() recognises the
  // same event and the customer is not alerted twice.
  String _titleFor(Booking booking) {
    final s = booking.status;
    final driver = (booking.serviceCategory ?? '').contains('goods') ||
        (booking.serviceCategory ?? '').contains('packers');
    final who = driver ? 'Driver' : 'Technician';
    return switch (bookingStageOf(s)) {
      BookingStage.confirmed => 'Booking Confirmation',
      BookingStage.assigned => '$who Assigned',
      BookingStage.onTheWay => isBookingArrivedStatus(s) ? '$who Has Arrived' : '$who On The Way',
      BookingStage.inProgress => driver ? 'Trip In Progress' : 'Service In Progress',
      BookingStage.completed => driver ? 'Goods Delivered' : 'Service Completed',
      BookingStage.ended => 'Booking Closed',
      BookingStage.cancelled => 'Booking Cancelled',
      BookingStage.requested =>
        normalizeBookingStatus(s) == 'rescheduled' ? 'Booking Rescheduled' : 'Booking Update',
    };
  }

  String _bodyFor(Booking booking) {
    final s = booking.status;
    final label =
        booking.items.isNotEmpty ? booking.items.first.service.title : 'Your booking';
    final tech = booking.technician?.name;
    return switch (bookingStageOf(s)) {
      BookingStage.confirmed => '$label is confirmed.',
      BookingStage.assigned => tech != null
          ? '$tech has been assigned to $label.'
          : 'A professional has been assigned to $label.',
      BookingStage.onTheWay => isBookingArrivedStatus(s)
          ? '${tech ?? 'Your professional'} has arrived for $label.'
          : '${tech ?? 'Your professional'} is on the way for $label.',
      BookingStage.inProgress => '$label is now in progress.',
      BookingStage.completed => '$label has been completed. Rate your experience!',
      BookingStage.ended => '$label was closed: ${bookingStatusLabel(s)}.',
      BookingStage.cancelled => '$label was cancelled.',
      BookingStage.requested => normalizeBookingStatus(s) == 'rescheduled'
          ? '$label has been rescheduled.'
          : '$label status: ${bookingStatusLabel(s)}.',
    };
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<AsyncValue<List<Booking>>>(myBookingsProvider(null), (previous, next) {
      final bookings = next.valueOrNull;
      if (bookings == null) return;

      _schedulePoll(bookings);

      if (!_seeded) {
        for (final b in bookings) {
          _lastKnownStatus[b.id] = b.status;
          _highestNotifiedStep[b.id] = _step(b.status);
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
        final step = _step(booking.status);
        final rescheduled = normalizeBookingStatus(booking.status) == 'rescheduled';
        final highest = _highestNotifiedStep[booking.id] ?? _step(previousStatus);
        // Only a real step forward (or a reschedule) is worth an alert —
        // never the same step twice, never a step backwards.
        if (!rescheduled && (step <= highest || step == 0)) continue;
        _highestNotifiedStep[booking.id] = rescheduled ? 0 : step;
        // An unpaid online booking the customer backed out of was never
        // placed: no "Booking Cancelled" alert for it.
        if (ref.read(withdrawnBookingIdsProvider).contains(booking.id)) continue;

        final title = _titleFor(booking);
        final body = _bodyFor(booking);
        final inbox = ref.read(notificationsControllerProvider.notifier);
        // The server now records these events in the inbox too; if it (or an
        // earlier pass) already did, don't alert a second time.
        if (inbox.hasRecent(title)) continue;
        inbox.addLocal(title: title, body: body);
        NotificationService.instance.show(
          title: title,
          body: body,
          routePayload: '/bookings/${booking.id}',
        );
      }
    });

    return widget.child;
  }
}
