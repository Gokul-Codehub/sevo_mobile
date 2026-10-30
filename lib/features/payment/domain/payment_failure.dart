/// Why an online payment did not complete, in words a customer understands, with the next step.
/// The booking stays pending until the server confirms payment - the app never trusts the gateway callback alone.
enum PaymentFailureKind { userCancelled, bankDeclined, networkLost, timeout, gatewayError, unknown }

class PaymentFailureInfo {
  const PaymentFailureInfo(this.kind, this.title, this.message, this.nextStep);
  final PaymentFailureKind kind;
  final String title;
  final String message;

  /// What the customer can do now (shown under the message).
  final String nextStep;
}

/// Razorpay codes: 0 = cancelled, 1 = invalid options, 2 = network error, 3 = TLS, 100 = unknown.
PaymentFailureInfo classifyPaymentFailure({int? code, String? message}) {
  final m = (message ?? '').toLowerCase();

  bool has(List<String> words) => words.any(m.contains);

  if (code == 0 || has(['cancel', 'back button', 'dismiss', 'closed by user'])) {
    return const PaymentFailureInfo(
      PaymentFailureKind.userCancelled,
      'Payment cancelled',
      'You cancelled the payment, so nothing was charged.',
      'Tap Try again to pay, choose another method, or pay later.',
    );
  }
  if (has(['declin', 'insufficient', 'not enough', 'limit exceeded', 'bank', 'otp', 'authentication failed', 'card'])) {
    return const PaymentFailureInfo(
      PaymentFailureKind.bankDeclined,
      'Your bank declined the payment',
      'The payment was not approved by your bank or card.',
      'Check your balance or card details, or try another payment method.',
    );
  }
  if (has(['timeout', 'timed out', 'took too long', 'expired'])) {
    return const PaymentFailureInfo(
      PaymentFailureKind.timeout,
      'Payment timed out',
      'The payment took too long to complete.',
      'If money was deducted it will be confirmed automatically. Otherwise, try again.',
    );
  }
  if (code == 2 || code == 3 || has(['network', 'internet', 'connection', 'offline', 'unreachable', 'socket'])) {
    return const PaymentFailureInfo(
      PaymentFailureKind.networkLost,
      'Connection lost',
      'We lost the internet connection during the payment.',
      'Check that you are online, then try again. If money was deducted, your booking will update on its own.',
    );
  }
  if (code == 1 || has(['gateway', 'server error', 'invalid', 'razorpay', 'unable to launch', 'could not start'])) {
    return const PaymentFailureInfo(
      PaymentFailureKind.gatewayError,
      'Payment service problem',
      'The payment service had a problem. This is not your fault.',
      'Please try again in a moment, or choose another method.',
    );
  }
  return const PaymentFailureInfo(
    PaymentFailureKind.unknown,
    'Payment did not complete',
    'The payment could not be completed.',
    'Try again, choose another method, or contact support if money was deducted.',
  );
}
