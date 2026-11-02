import 'package:calservices_customer/core/navigation/pending_link.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('only account-specific screens need sign-in', () {
    for (final r in ['/bookings/5', '/bookings', '/tracking/7?x=1', '/orders/2', '/notifications']) {
      expect(PendingLink.needsSignIn(r), isTrue, reason: r);
    }
    for (final r in ['/categories', '/cart', '/', '/products/abc']) {
      expect(PendingLink.needsSignIn(r), isFalse, reason: r);
    }
  });

  test('a stored link is returned once and then forgotten', () {
    PendingLink.set('/bookings/9');
    expect(PendingLink.hasPending, isTrue);
    expect(PendingLink.take(), '/bookings/9');
    expect(PendingLink.take(), isNull);
    expect(PendingLink.hasPending, isFalse);
  });
}
