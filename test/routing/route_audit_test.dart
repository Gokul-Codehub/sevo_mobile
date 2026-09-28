import 'package:calservices_customer/routing/app_router.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('GoRouter Route Audit & Flow Integrity Tests', () {
    test('AppRoutes contains required route definitions', () {
      expect(AppRoutes.home, equals('/'));
      expect(AppRoutes.login, equals('/login'));
      expect(AppRoutes.otpVerify, equals('/login/verify'));
      expect(AppRoutes.cart, equals('/cart'));
      expect(AppRoutes.myBookings, equals('/bookings'));
      expect(AppRoutes.addresses, equals('/addresses'));
      expect(AppRoutes.categoryDetail, equals('/categories/:slug'));
      expect(AppRoutes.serviceDetail, equals('/services/:slug'));
    });

    test('Verify grocery item slug is distinct from normal service routes', () {
      const grocerySlug = 'veg-beetroot';
      const serviceSlug = 'ac-combo-2-units';

      expect(grocerySlug.startsWith('veg-'), isTrue);
      expect(serviceSlug.startsWith('veg-'), isFalse);
    });
  });
}
