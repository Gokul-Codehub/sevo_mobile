import 'package:calservices_customer/core/services/notification_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the same event is claimed once - a push and a later inbox poll never alert twice', () {
    final s = NotificationService.instance;
    expect(s.claim('technician_assigned_dedupe_test'), isTrue);
    expect(s.claim('technician_assigned_dedupe_test'), isFalse);
    expect(s.claim('another_event_dedupe_test'), isTrue);
  });

  test('no key means no de-duplication (never silently drops a notification)', () {
    final s = NotificationService.instance;
    expect(s.claim(null), isTrue);
    expect(s.claim(null), isTrue);
    expect(s.claim(''), isTrue);
  });

  test('only the most recent 100 keys are remembered', () {
    final s = NotificationService.instance;
    expect(s.claim('first_key_dedupe_cap'), isTrue);
    for (var i = 0; i < 100; i++) {
      s.claim('filler_$i');
    }
    expect(s.claim('first_key_dedupe_cap'), isTrue); // forgotten, so it may alert again
  });
}
