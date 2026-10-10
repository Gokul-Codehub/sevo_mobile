import 'package:decimal/decimal.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/api_error.dart';
import '../../../core/services/notification_service.dart';
import '../../addresses/domain/address_notifier.dart';
import '../../auth/domain/auth_notifier.dart';
import '../../logistics/domain/logistics_models.dart';
import '../data/booking_repository.dart';
import '../data/quote_repository.dart';
import 'booking_models.dart';
import 'cart_notifier.dart';

/// Provider for list of customer bookings filtered by status ('active', 'completed', or null).
///
/// Fixed 2026-09-17: made `.autoDispose` to stop it caching forever and
/// showing a stale status like "Booking Confirmed" after closing and
/// reopening the app. That fixed staleness, but had a side effect nobody
/// noticed until the full navigation audit below: `MyBookingsScreen` (and
/// Home's "Book Again" strip, which watches this same provider) sit under
/// a `ShellRoute` bottom-tab shell where switching tabs via `context.go()`
/// destroys and recreates the destination screen's widget/State — see
/// `app_shell.dart`'s tab `onTap` and `app_router.dart`'s `ShellRoute`.
/// Every time `_MyBookingsScreenState` was torn down (left the Bookings
/// tab) its listener count hit zero, and `.autoDispose` immediately threw
/// the cached list away — not just marked it stale. So returning to the
/// tab created a brand-new widget watching a provider with ZERO previous
/// value, forcing `MyBookingsScreen`'s full `ShimmerCard` list every
/// single time, even on the 2nd/3rd/Nth visit in the same session —
/// exactly the "page shows the loading indicator again even though
/// already visited" bug.
///
/// Fixed 2026-10-07: restored to a plain, `ref.keepAlive()`-marked
/// `FutureProvider.family` (same pattern as `categoriesProvider` and the
/// other catalog providers in catalog_providers.dart) so a tab-switch
/// teardown/recreate of the watching widget no longer wipes the cached
/// list — the next visit renders instantly from cache instead of
/// reloading. Freshness is still handled, just no longer by *destroying*
/// the data: every place that already called `ref.invalidate
/// (myBookingsProvider)` for a real reason — `createBooking`/
/// `cancelBooking`/`rescheduleBooking`/`decide` below, and
/// `MyBookingsScreen.didChangeAppLifecycleState`'s resume hook — still
/// does, but `ref.invalidate` on a kept-alive provider triggers a
/// BACKGROUND refetch while the previous list stays visible
/// (`AsyncValue.valueOrNull`/`.previous` carries forward through the
/// reload), instead of a full dispose that blanks the screen. See
/// `MyBookingsScreen`'s body for the instant-render-from-cache +
/// subtle-refresh-indicator pattern this enables.
final myBookingsProvider =
    FutureProvider.family<List<Booking>, String?>((ref, statusFilter) async {
  ref.keepAlive();
  final repo = ref.watch(bookingRepositoryProvider);
  final result = await repo.getMyBookings(statusFilter: statusFilter);

  return switch (result) {
    Success(:final data) => data,
    Failure(:final error) => throw error,
  };
});

/// Provider for a single booking detail.
///
/// Fixed 2026-08-27: this previously returned a stale cached [Booking] from
/// `bookingActionControllerProvider` (whatever snapshot was left over from
/// the last create/cancel/reschedule call) or from `myBookingsProvider`'s
/// cached list, UNCONDITIONALLY and BEFORE ever attempting a live fetch.
/// That meant the detail screen — and even its own "Refresh" button, which
/// just calls `ref.refresh(bookingDetailProvider(id))` — could show a status
/// that had been stale for hours while the bookings list (which fetches
/// fresh) correctly showed the booking's real, current status. Always fetch
/// live now; `BookingDetailScreen`'s `initialBooking` param already handles
/// instant-paint UX from whatever the caller navigated with.
final bookingDetailProvider = FutureProvider.autoDispose
    .family<Booking, int>((ref, id) async {
  final repo = ref.watch(bookingRepositoryProvider);
  final result = await repo.getBookingDetail(id);

  return switch (result) {
    Success(:final data) => data,
    Failure(:final error) => throw error,
  };
});

/// Controller handling booking operations (create, cancel, reschedule).
class BookingActionController extends Notifier<AsyncValue<Booking?>> {
  @override
  AsyncValue<Booking?> build() => const AsyncValue.data(null);

  BookingRepository get _repo => ref.read(bookingRepositoryProvider);

  // ── Place new booking ─────────────────────────────────────────────────────
  Future<({String? error, Booking? booking})> createBooking({
    List<CartItem>? customItems,
    required String date,
    required TimeSlot slot,
    required Decimal totalAmount,
    String? specialInstructions,
    String? contactPhone,
    // Fixed 2026-10-08 (QA CME02 — see checkout_screen.dart's
    // `_paymentMethod` doc comment): forwarded as-is to
    // BookingRepository.createBooking, which previously never sent any
    // `payment_method` at all — defaults to 'COD' so every existing caller
    // (e.g. the grocery cart flow, which doesn't pass this yet) keeps its
    // current behaviour unchanged.
    String paymentMethod = 'COD',
    // ── Goods & Transport (logistics) fields ──────────────────────────────
    // Added 2026-09-19 — forwarded as-is to BookingRepository.createBooking;
    // see that method's doc comment for the verified backend field list.
    String? dropAddress,
    double? dropLatitude,
    double? dropLongitude,
    int? logisticsTier,
    int? logisticsLane,
    Decimal? declaredValue,
    String? consigneeRelationship,
    String? dropContactName,
    String? dropContactPhone,
    String? dropContactEmail,
    bool? insuranceOptedIn,
    String? jobType,
    String? serviceCategoryOverride,
    List<Map<String, dynamic>>? cartDataOverride,
  }) async {
    final List<CartItem> items = customItems ?? ref.read(cartProvider);
    final selectedAddress = ref.read(selectedAddressProvider);
    final currentUser = ref.read(currentUserProvider);

    if (items.isEmpty) {
      return (error: 'Please select a service first', booking: null);
    }
    if (selectedAddress == null) {
      return (error: 'Please select a service address', booking: null);
    }

    state = const AsyncValue.loading();

    String? validPhone = contactPhone;
    if (validPhone == null || validPhone.isEmpty || validPhone.contains('@')) {
      final userPhone = currentUser?.phone;
      if (userPhone != null && userPhone.isNotEmpty && !userPhone.contains('@')) {
        validPhone = userPhone;
      } else {
        validPhone = '9876543210';
      }
    }

    final result = await _repo.createBooking(
      items: items,
      addressId: selectedAddress.id,
      // Fixed 2026-09-24: send the customer's real, full street address
      // (line1/line2/landmark/city/state-pincode) as the free-text
      // `address` the backend forwards to the vendor app/technician,
      // instead of just the numeric address ID -- see booking_repository's
      // doc comment on `fullAddress` for why this matters.
      fullAddress: selectedAddress.formattedAddress,
      scheduledDate: date,
      scheduledTimeSlot: slot.label,
      totalAmount: totalAmount,
      specialInstructions: specialInstructions,
      contactPhone: validPhone,
      paymentMethod: paymentMethod,
      customerName: currentUser?.name ?? 'Customer',
      // Fixed 2026-08-27: forward the selected address's coordinates so the
      // backend's ServiceRequest.latitude/longitude columns are actually
      // populated instead of staying null for every booking — see the note
      // in booking_repository.dart.
      latitude: selectedAddress.latitude,
      longitude: selectedAddress.longitude,
      dropAddress: dropAddress,
      dropLatitude: dropLatitude,
      dropLongitude: dropLongitude,
      logisticsTier: logisticsTier,
      logisticsLane: logisticsLane,
      declaredValue: declaredValue,
      consigneeRelationship: consigneeRelationship,
      dropContactName: dropContactName,
      dropContactPhone: dropContactPhone,
      dropContactEmail: dropContactEmail,
      insuranceOptedIn: insuranceOptedIn,
      jobType: jobType,
      serviceCategoryOverride: serviceCategoryOverride,
      cartDataOverride: cartDataOverride,
    );

    switch (result) {
      case Success(:final data):
        state = AsyncValue.data(data);
        // Clear grocery cart only if booking was created from grocery cart items
        if (customItems == null) {
          ref.read(cartProvider.notifier).clearCart();
        }
        // Invalidate bookings lists
        ref.invalidate(myBookingsProvider);
        // Added 2026-09-19: post an immediate real device notification —
        // this is the one status change guaranteed to be known the moment
        // it happens (no polling needed), so it fires straight from here
        // rather than waiting for BookingNotificationWatcher's next poll.
        // See NotificationService's doc comment for what this can/can't do.
        final firstItem = items.firstOrNull;
        NotificationService.instance.show(
          title: 'Booking Placed',
          body: firstItem != null
              ? '${firstItem.service.title} has been booked successfully.'
              : 'Your booking has been placed successfully.',
          routePayload: '/bookings/${data.id}',
        );
        return (error: null, booking: data);
      case Failure(:final error):
        state = AsyncValue.error(error, StackTrace.current);
        return (error: error.message, booking: null);
    }
  }

  // ── Cancel booking ────────────────────────────────────────────────────────
  Future<String?> cancelBooking(int id, String reason) async {
    final result = await _repo.cancelBooking(id: id, reason: reason);
    switch (result) {
      case Success(:final data):
        // Not notified directly here — BookingNotificationWatcher already
        // fires "Booking Cancelled" itself once this invalidate() below
        // makes it see the new status, and notifying both places would
        // double-fire the same event.
        ref.invalidate(myBookingsProvider);
        ref.invalidate(bookingDetailProvider(id));
        state = AsyncValue.data(data);
        return null;
      case Failure(:final error):
        return error.message;
    }
  }

  // ── Reschedule booking ────────────────────────────────────────────────────
  Future<String?> rescheduleBooking({
    required int id,
    required String date,
    required String slot,
  }) async {
    final result = await _repo.rescheduleBooking(
      id: id,
      date: date,
      slot: slot,
    );
    switch (result) {
      case Success(:final data):
        ref.invalidate(myBookingsProvider);
        ref.invalidate(bookingDetailProvider(id));
        state = AsyncValue.data(data);
        return null;
      case Failure(:final error):
        return error.message;
    }
  }
}

final bookingActionControllerProvider =
    NotifierProvider<BookingActionController, AsyncValue<Booking?>>(
  BookingActionController.new,
);

/// Controller for Accept / Decline / Request Changes on a Painting / Masonry
/// / AC-Inspection quotation (see QuoteSummary / QuoteRepository doc
/// comments for the full backend contract). Deliberately separate from
/// [BookingActionController] — a quote decision isn't a booking mutation by
/// itself, and keeping its own loading/error state means a slow decide()
/// call can't be confused with the parent booking's own loading state on
/// the same screen.
class QuoteDecisionController extends Notifier<AsyncValue<void>> {
  @override
  AsyncValue<void> build() => const AsyncValue.data(null);

  QuoteRepository get _repo => ref.read(quoteRepositoryProvider);

  /// [parentBookingId] is invalidated afterwards regardless of outcome so
  /// the booking detail screen re-fetches the authoritative state from the
  /// API — never trusts this call's own response as "the booking is now
  /// confirmed", per the "socket/response is a signal to refetch, not the
  /// source of truth" rule this flow was audited against.
  Future<String?> decide({
    required String decisionToken,
    required String decision,
    required int parentBookingId,
    String? reasonNotes,
  }) async {
    state = const AsyncValue.loading();
    final result = await _repo.decide(decisionToken, decision, reasonNotes: reasonNotes);
    ref.invalidate(bookingDetailProvider(parentBookingId));
    ref.invalidate(myBookingsProvider);
    switch (result) {
      case Success():
        state = const AsyncValue.data(null);
        return null;
      case Failure(:final error):
        state = AsyncValue.error(error, StackTrace.current);
        return error.message;
    }
  }
}

final quoteDecisionControllerProvider =
    NotifierProvider<QuoteDecisionController, AsyncValue<void>>(
  QuoteDecisionController.new,
);
