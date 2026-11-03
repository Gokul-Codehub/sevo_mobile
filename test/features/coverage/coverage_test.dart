import 'package:calservices_customer/features/auth/domain/otp_autofill.dart';
import 'package:calservices_customer/features/coverage/domain/coverage.dart';
import 'package:calservices_customer/features/home/domain/home_flow_mode.dart';
import 'package:calservices_customer/features/logistics/domain/logistics_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const groceries = HomeFlowMode.groceries;
  const services = HomeFlowMode.services;

  group('when the app blocks Home', () {
    test('never on "unknown": no location, no network or a check still running must not lock anyone out', () {
      expect(notServedFor(const AreaCoverage(), groceries), isNull);
      expect(notServedFor(const AreaCoverage(), services), isNull);
    });

    test('never when the vertical being browsed is served', () {
      const c = AreaCoverage(services: Coverage.yes, groceries: Coverage.no);
      expect(notServedFor(c, services), isNull);
    });

    test('blocks the vertical that is surely not served, and offers the other when it is served', () {
      const c = AreaCoverage(services: Coverage.yes, groceries: Coverage.no, groceriesMessage: 'Not in your area');
      final n = notServedFor(c, groceries)!;
      expect(n.mode, groceries);
      expect(n.message, 'Not in your area');
      expect(n.otherServed, services);
    });

    test('services-only gap: groceries are offered instead', () {
      const c = AreaCoverage(services: Coverage.no, groceries: Coverage.yes);
      expect(notServedFor(c, services)!.otherServed, groceries);
    });

    test('nothing served at all: no alternative is offered', () {
      const c = AreaCoverage(services: Coverage.no, groceries: Coverage.no);
      expect(notServedFor(c, groceries)!.otherServed, isNull);
      expect(notServedFor(c, services)!.otherServed, isNull);
    });

    test('an "unknown" other vertical is not offered as an alternative', () {
      const c = AreaCoverage(services: Coverage.unknown, groceries: Coverage.no);
      expect(notServedFor(c, groceries)!.otherServed, isNull);
    });
  });

  test('a service check that could not be made never claims "available" and never blocks', () {
    final r = ServiceabilityResult.couldNotCheck();
    expect(r.isUnknown, isTrue);
    expect(r.isServiceable, isTrue);
  });

  group('SMS code reading', () {
    test('finds the code in the login message, with or without the retriever markers', () {
      expect(extractOtp('Your Sevo login OTP is: 482913. Valid for 5 minutes.'), '482913');
      expect(extractOtp('<#> Your Sevo login OTP is: 482913. Valid for 5 minutes.\nAbCdEfGhIjK'), '482913');
    });

    test('never mistakes a longer number for the code', () {
      expect(extractOtp('Call 9876543210 or order 12345678'), isNull);
      expect(extractOtp(null), isNull);
      expect(extractOtp('no digits here'), isNull);
    });

    test('the default reader is silent until SMS is connected', () async {
      const noop = NoopOtpAutofill();
      expect(await noop.listen().isEmpty, isTrue);
      expect(await noop.appSignature(), isNull);
    });
  });
}
