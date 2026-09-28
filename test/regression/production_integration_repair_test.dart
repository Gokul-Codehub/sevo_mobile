import 'package:calservices_customer/core/errors/api_error.dart';
import 'package:calservices_customer/core/network/api_client.dart';
import 'package:calservices_customer/core/utils/image_url_helper.dart';
import 'package:calservices_customer/features/auth/domain/auth_models.dart';
import 'package:calservices_customer/features/booking/data/booking_repository.dart';
import 'package:calservices_customer/features/booking/domain/booking_models.dart';
import 'package:calservices_customer/features/catalog/data/catalog_repository.dart';
import 'package:calservices_customer/features/catalog/domain/catalog_models.dart';
import 'package:decimal/decimal.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeDioAdapter implements HttpClientAdapter {
  _FakeDioAdapter(this.handler);

  final Future<ResponseBody> Function(RequestOptions options) handler;

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<dynamic>? requestStream,
    Future<void>? cancelFuture,
  ) {
    return handler(options);
  }
}

void main() {
  group('Production Integration Repair Suite', () {
    // ── TEST 1 & 2: Category & Service Detail Identity Propagation ───────────
    test('TEST 1 & 2: Selecting Beetroot preserves its backend ID and prevents category mismatch', () async {
      final dio = Dio(BaseOptions(baseUrl: 'https://sevo.co.in/api'));
      dio.httpClientAdapter = _FakeDioAdapter((options) async {
        if (options.path.contains('/catalog/services/')) {
          final jsonStr = '''
          {
            "success": true,
            "data": [
              {
                "id": 734,
                "name": "1 RK / 1 BHK Shifting",
                "slug": "1-rk-1-bhk-shifting",
                "category": 12,
                "price": "1499.00"
              },
              {
                "id": 228,
                "name": "Beetroot",
                "slug": "veg-beetroot",
                "category": 18,
                "price": "37.00"
              },
              {
                "id": 244,
                "name": "Amlaa (Nellikaai)",
                "slug": "veg-amla",
                "category": 18,
                "price": "45.00"
              }
            ]
          }
          ''';
          return ResponseBody.fromString(jsonStr, 200, headers: {
            Headers.contentTypeHeader: [Headers.jsonContentType],
          });
        }
        return ResponseBody.fromString('{}', 404);
      });

      final repo = CatalogRepository(api: ApiClient.withDio(dio));

      // Fetch Beetroot by slug
      final result = await repo.getServiceDetail('veg-beetroot');
      expect(result.isSuccess, isTrue);

      final service = (result as Success<ServiceItem>).data;
      // Invariant: Beetroot MUST resolve to ID 228 (category 18), NEVER 734 (category 12)
      expect(service.id, equals(228));
      expect(service.title, equals('Beetroot'));
      expect(service.slug, equals('veg-beetroot'));
      expect(service.price, equals(Decimal.parse('37.00')));
    });

    // ── TEST 3 & 4: OTP Response Polymorphic ID Parsing ─────────────────────
    test('TEST 3: OTP response with String "7988" id is parsed into integer 7988 without exception', () {
      final jsonResponse = {
        'id': '7988',
        'username': 'cust_test_audit_user',
        'email': 'test_audit_user@caldimengg.in',
        'phone': null,
        'first_name': 'Audit',
        'last_name': 'User',
      };

      final user = UserProfile.fromJson(jsonResponse);
      expect(user.id, equals(7988));
      expect(user.email, equals('test_audit_user@caldimengg.in'));
      expect(user.name, equals('Audit User'));
      expect(user.phone, equals('test_audit_user@caldimengg.in'));
    });

    test('TEST 4: OTP response with integer 7988 id is parsed correctly', () {
      final jsonResponse = {
        'id': 7988,
        'username': 'cust_test_phone_user',
        'phone': '+919876543210',
        'email': null,
        'first_name': '',
        'last_name': '',
      };

      final user = UserProfile.fromJson(jsonResponse);
      expect(user.id, equals(7988));
      expect(user.phone, equals('+919876543210'));
      expect(user.name, equals('cust_test_phone_user'));
    });

    // ── TEST 5, 6, 7, 8: Centralized Production Image URL Helper ─────────────
    test('TEST 5: Relative image URL resolves to production domain', () {
      final resolved = ImageUrlHelper.resolve('/mockups/vegetables_realistic.png');
      expect(resolved, equals('https://sevo.co.in/mockups/vegetables_realistic.png'));
    });

    test('TEST 6: Absolute HTTPS image URL remains unchanged', () {
      const url = 'https://images.unsplash.com/photo-1585704032915-c3400ca199e7?w=500';
      final resolved = ImageUrlHelper.resolve(url);
      expect(resolved, equals(url));
    });

    test('TEST 7: Null or empty image URL returns null for clean icon fallback', () {
      expect(ImageUrlHelper.resolve(null), isNull);
      expect(ImageUrlHelper.resolve(''), isNull);
      expect(ImageUrlHelper.resolve('   '), isNull);
    });

    test('TEST 8: Insecure HTTP URL is upgraded to HTTPS safely', () {
      final resolved = ImageUrlHelper.resolve('http://sevo.co.in/mockups/ants_control.jpg');
      expect(resolved, equals('https://sevo.co.in/mockups/ants_control.jpg'));
    });

    // ── TEST 9: Booking Payload Service ID Integrity ─────────────────────────
    test('TEST 9: Booking payload service ID equals selected service ID', () {
      final beetroot = ServiceItem(
        id: 228,
        title: 'Beetroot',
        slug: 'veg-beetroot',
        price: Decimal.parse('37.00'),
        categoryId: 18,
      );

      final cartItem = CartItem(service: beetroot, quantity: 2);
      final json = cartItem.toJson();

      expect(json['service_id'], equals(228));
      expect(json['service_slug'], equals('veg-beetroot'));
      expect(json['service_title'], equals('Beetroot'));
      expect(json['quantity'], equals(2));
      expect(json['unit_price'], equals('37'));
      expect(json['total_price'], equals('74'));
    });

    // ── TEST 10: Beetroot Category and Service Identity Model Test ───────────
    test('TEST 10: Beetroot parsed from API correctly assigns category_id = 18 and service_id = 228', () {
      final apiJson = {
        'id': 228,
        'category': 18,
        'category_slug': 'vegetables_groceries',
        'name': 'Beetroot',
        'slug': 'veg-beetroot',
        'price': '37.00',
      };

      final beetroot = ServiceItem.fromJson(apiJson);
      expect(beetroot.id, equals(228));
      expect(beetroot.categoryId, equals(18));
      expect(beetroot.title, equals('Beetroot'));
      expect(beetroot.slug, equals('veg-beetroot'));
      expect(beetroot.effectivePrice, equals(Decimal.parse('37.00')));
    });

    // ── TEST 11: Booking payload contains service_category = 18 and service_id = 228 ──
    test('TEST 11: BookingRepository payload contains service_category = 18 and service_id = 228', () async {
      late Map<String, dynamic> capturedPayload;

      final dio = Dio(BaseOptions(baseUrl: 'https://sevo.co.in/api'));
      dio.httpClientAdapter = _FakeDioAdapter((options) async {
        if (options.path.contains('/booking/')) {
          capturedPayload = options.data as Map<String, dynamic>;
          const jsonStr = '''
          {
            "success": true,
            "data": {
              "id": 1050,
              "request_id": "CAL-20260823-1050",
              "status": "new_request",
              "total_amount": 74.0,
              "advance_amount": 14.8,
              "balance_amount": 59.2,
              "payment_status": "pending",
              "available_actions": ["cancel", "pay"],
              "scheduled_date": "2026-08-25",
              "scheduled_time_slot": "10:00 AM - 12:00 PM"
            }
          }
          ''';
          return ResponseBody.fromString(jsonStr, 200, headers: {
            Headers.contentTypeHeader: [Headers.jsonContentType],
          });
        }
        return ResponseBody.fromString('{}', 404);
      });

      final beetroot = ServiceItem(
        id: 228,
        title: 'Beetroot',
        slug: 'veg-beetroot',
        price: Decimal.parse('37.00'),
        categoryId: 18,
      );

      final repo = BookingRepository(api: ApiClient.withDio(dio));
      final result = await repo.createBooking(
        items: [CartItem(service: beetroot, quantity: 2)],
        addressId: 107,
        scheduledDate: '2026-08-25',
        scheduledTimeSlot: '10:00 AM - 12:00 PM',
        totalAmount: Decimal.parse('74.00'),
        customerName: 'Audit Tester',
        contactPhone: '9876543210',
      );

      expect(result.isSuccess, isTrue);
      expect(capturedPayload['service_category'], equals(18));
      expect(capturedPayload['service_id'], equals(228));
      expect(capturedPayload['issue_title'], equals('Beetroot'));
      expect(capturedPayload['address_id'], equals(107));
      expect(capturedPayload['scheduled_date'], equals('2026-08-25'));
      expect(capturedPayload['scheduled_time_slot'], equals('10:00 AM - 12:00 PM'));
      expect(capturedPayload['items'], isNotEmpty);
      expect(capturedPayload['cart_data'], isNotEmpty);
    });

    // ── TEST 12: available_actions Dynamic State Machine ─────────────────────
    test('TEST 12: Booking availableActions accurately determines action availability', () {
      const json = {
        'id': 1050,
        'request_id': 'CAL-20260823-1050',
        'status': 'assigned',
        'total_amount': 74.0,
        'advance_amount': 14.8,
        'balance_amount': 59.2,
        'payment_status': 'pending',
        'available_actions': ['cancel', 'reschedule', 'pay_advance', 'track'],
        'scheduled_date': '2026-08-25',
        'scheduled_time_slot': '10:00 AM - 12:00 PM',
      };

      final booking = Booking.fromJson(json);
      expect(booking.canCancel, isTrue);
      expect(booking.canReschedule, isTrue);
      expect(booking.canPayAdvance, isTrue);
      expect(booking.canTrack, isTrue);
      expect(booking.canPayBalance, isFalse);
    });

    // ── TEST 13: Image and Icon Fallback Mapping ─────────────────────────────
    test('TEST 13: ImageUrlHelper maps Lucide category icons and slug fallbacks', () {
      expect(ImageUrlHelper.mapCategoryIcon('Carrot', 'vegetables_groceries'), isNotNull);
      expect(ImageUrlHelper.mapCategoryIcon('Truck', 'goods_transports'), isNotNull);
      expect(ImageUrlHelper.mapCategoryIcon('Wind', 'ac_appliance'), isNotNull);
      expect(ImageUrlHelper.mapCategoryIcon('Wrench', 'repair_services'), isNotNull);
    });
  });
}
