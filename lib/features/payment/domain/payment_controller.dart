import 'package:decimal/decimal.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';

import '../../../core/errors/api_error.dart';
import '../../auth/domain/auth_notifier.dart';
import '../../booking/domain/booking_models.dart';
import '../../booking/domain/booking_providers.dart';
import '../data/payment_repository.dart';
import 'payment_models.dart';

/// State notifier managing the complete Razorpay checkout and verification lifecycle.
class PaymentController extends Notifier<PaymentState> {
  late final Razorpay _razorpay;
  int? _activeBookingId;
  String? _activeOrderId;

  @override
  PaymentState build() {
    _razorpay = Razorpay();
    _razorpay.on(Razorpay.EVENT_PAYMENT_SUCCESS, _handlePaymentSuccess);
    _razorpay.on(Razorpay.EVENT_PAYMENT_ERROR, _handlePaymentError);
    _razorpay.on(Razorpay.EVENT_EXTERNAL_WALLET, _handleExternalWallet);

    ref.onDispose(() {
      _razorpay.clear();
    });

    return const PaymentInitial();
  }

  PaymentRepository get _repo => ref.read(paymentRepositoryProvider);

  // ── Launch Payment ────────────────────────────────────────────────────────
  // Fixed 2026-10-01 (production resolution — Payment scope, critical
  // rule): this used to fall back, on ANY order-creation failure, to a
  // client-fabricated order id ('order_sim_...') and still call
  // `_razorpay.open()` with a hardcoded live key — meaning a real charge
  // could be taken through the live gateway with no server-created order
  // behind it. PaymentVerifyView (service_requests/payment_views.py) binds
  // every verification to a Payment row that only PaymentInitiateView can
  // create, so that charge could never be reconciled: the customer pays,
  // the booking never shows as paid, and support has no record to work
  // from. There is now no fallback at all — if the backend does not hand
  // back a real order, this stops and reports a failure instead of
  // proceeding to a real payment gateway.
  Future<void> startPayment({
    required Booking booking,
    required Decimal amount,
    required String paymentType, // 'advance' | 'balance' | 'full'
  }) async {
    _activeBookingId = booking.id;
    state = const PaymentProcessing(statusMessage: 'Preparing secure checkout...');

    // 1. Create a real payment order on the backend. No fallback — see
    //    the critical rule in this method's doc comment above.
    final orderResult = await _repo.createPaymentOrder(
      bookingId: booking.id,
      amount: amount,
      paymentType: paymentType,
    );

    final PaymentOrder order;
    switch (orderResult) {
      case Success(:final data):
        order = data;
      case Failure(:final error):
        state = PaymentFailed(
          errorMessage: 'Could not start payment: ${error.message}',
        );
        return;
    }

    if (order.orderId.isEmpty) {
      state = const PaymentFailed(
        errorMessage:
            'Payment could not be started — no order was returned by the server. Please try again.',
      );
      return;
    }
    _activeOrderId = order.orderId;

    // PaymentInitiateView returns an empty key_id specifically when this
    // backend environment has no live Razorpay gateway configured (see
    // PaymentOrder.fromJson's doc comment) — fail honestly instead of
    // guessing a key and opening a checkout that cannot actually complete.
    if (order.keyId == null || order.keyId!.isEmpty) {
      state = const PaymentFailed(
        errorMessage:
            'Online payment is not available right now. Please choose cash on service or contact support.',
      );
      return;
    }

    final currentUser = ref.read(currentUserProvider);

    // 2. Configure Razorpay checkout options — always with the real,
    //    backend-issued order_id; Razorpay is never opened without one.
    final options = {
      'key': order.keyId,
      'amount': order.amountInPaise,
      'name': 'CalServices',
      'description': 'Booking #${booking.requestId}',
      'order_id': order.orderId,
      'prefill': {
        if (currentUser != null && currentUser.phone.isNotEmpty)
          'contact': currentUser.phone,
        if (currentUser?.email != null && currentUser!.email!.isNotEmpty)
          'email': currentUser.email!,
        if (currentUser?.name != null && currentUser!.name!.isNotEmpty)
          'name': currentUser.name!,
      },
      'theme': {
        'color': '#0F766E', // CalServices brand teal primary
      },
      'retry': {'enabled': true, 'max_count': 3},
    };

    try {
      _razorpay.open(options);
    } catch (e) {
      state = PaymentFailed(
        errorMessage: 'Unable to launch Razorpay checkout: $e',
      );
    }
  }

  // ── Success Callback ──────────────────────────────────────────────────────
  Future<void> _handlePaymentSuccess(PaymentSuccessResponse response) async {
    final bookingId = _activeBookingId ?? 0;
    final orderId = response.orderId ?? _activeOrderId ?? '';
    final paymentId = response.paymentId ?? '';
    final signature = response.signature ?? '';

    state = const PaymentProcessing(
      statusMessage: 'Verifying payment with bank...',
    );

    final verifyResult = await _repo.verifyPayment(
      PaymentVerificationPayload(
        paymentId: paymentId,
        orderId: orderId,
        signature: signature,
        bookingId: bookingId,
      ),
    );

    switch (verifyResult) {
      case Success():
        state = PaymentSuccess(
          paymentId: paymentId,
          orderId: orderId,
          bookingId: bookingId,
        );
        // Refresh booking details & list
        if (bookingId > 0) {
          ref.invalidate(bookingDetailProvider(bookingId));
        }
        ref.invalidate(myBookingsProvider);
      case Failure(:final error):
        state = PaymentFailed(
          errorMessage: 'Payment received but verification failed: ${error.message}',
        );
    }
  }

  // ── Error Callback ────────────────────────────────────────────────────────
  void _handlePaymentError(PaymentFailureResponse response) {
    state = PaymentFailed(
      errorMessage: response.message ?? 'Payment was cancelled or unsuccessful.',
      code: response.code,
    );
  }

  // ── External Wallet Callback ──────────────────────────────────────────────
  void _handleExternalWallet(ExternalWalletResponse response) {
    debugPrint('[Payment] External wallet selected: ${response.walletName}');
  }

  void reset() {
    state = const PaymentInitial();
  }
}

// ── Provider ─────────────────────────────────────────────────────────────────
final paymentControllerProvider =
    NotifierProvider<PaymentController, PaymentState>(
  PaymentController.new,
);
