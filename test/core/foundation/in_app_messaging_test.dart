import 'package:calservices_customer/core/foundation/in_app_messaging.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeSink implements InAppMessagingSink {
  final calls = <bool>[];
  @override
  Future<void> setSuppressed(bool suppressed) async => calls.add(suppressed);
}

void main() {
  group('InAppMessagingRules', () {
    test('payment, checkout, sign-in and tracking are sensitive', () {
      for (final p in ['/checkout', '/checkout/payment', '/login', '/login/verify', '/track/abc', '/goods-transport/booking']) {
        expect(InAppMessagingRules.isSensitive(p), isTrue, reason: p);
      }
    });
    test('home, categories and bookings list are not', () {
      for (final p in ['/', '/categories', '/bookings', '/profile', '/search', null, '']) {
        expect(InAppMessagingRules.isSensitive(p), isFalse, reason: '$p');
      }
    });
  });

  group('InAppMessagingManager', () {
    test('nothing is sent to Firebase until Firebase is ready', () async {
      final sink = _FakeSink();
      final m = InAppMessagingManager(sink: sink, ensureFirebase: () async => false);
      await m.init();
      m.setLocation('/checkout');
      expect(sink.calls, isEmpty);
    });

    test('suppressed on a payment screen and again allowed on Home', () async {
      final sink = _FakeSink();
      final m = InAppMessagingManager(sink: sink, ensureFirebase: () async => true);
      await m.init();
      expect(sink.calls, [false]);
      m.setLocation('/checkout/payment');
      await Future<void>.delayed(Duration.zero);
      m.setLocation('/');
      await Future<void>.delayed(Duration.zero);
      expect(sink.calls, [false, true, false]);
    });

    test('the remote switch turns messages off everywhere', () async {
      final sink = _FakeSink();
      final m = InAppMessagingManager(sink: sink, ensureFirebase: () async => true);
      await m.init();
      m.setRemoteEnabled(false);
      await Future<void>.delayed(Duration.zero);
      expect(m.suppressed, isTrue);
      expect(sink.calls.last, isTrue);
    });
  });
}
