import 'package:calservices_customer/features/auth/domain/auth_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Auth OTP Identifier Encoding & Args Tests', () {
    test('OtpVerifyArgs preserves plus-addressed email without space corruption', () {
      const email = 'user+test@caldimengg.in';
      const args = OtpVerifyArgs(
        identifier: email,
        channel: 'email',
        resendAfterSeconds: 60,
      );

      expect(args.identifier, equals('user+test@caldimengg.in'));
      expect(args.channel, equals('email'));
      expect(args.resendAfterSeconds, equals(60));
    });

    test('Uri with queryParameters properly percent-encodes plus characters', () {
      const email = 'customer+special&promo@domain.com';
      final uri = Uri(
        path: '/login/verify',
        queryParameters: {
          'identifier': email,
          'channel': 'email',
          'resend_after': '60',
        },
      );

      // Verify the string representation encodes '+' and '&' safely
      expect(uri.toString(), contains('customer%2Bspecial%26promo%40domain.com'));
      // When decoded back with standard Uri queryParameters, it must match original
      expect(uri.queryParameters['identifier'], equals(email));
    });
  });
}
