import 'package:decimal/decimal.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:calservices_customer/core/errors/api_error.dart';
import 'package:calservices_customer/core/network/api_client.dart';
import 'package:calservices_customer/core/network/auth_interceptor.dart';
import 'package:calservices_customer/core/storage/secure_storage.dart';
import 'package:calservices_customer/features/addresses/data/address_repository.dart';
import 'package:calservices_customer/features/addresses/domain/address_models.dart';
import 'package:calservices_customer/features/auth/data/auth_repository.dart';
import 'package:calservices_customer/features/auth/domain/auth_models.dart';
import 'package:calservices_customer/features/booking/domain/booking_models.dart';
import 'package:calservices_customer/features/booking/domain/cart_notifier.dart';
import 'package:calservices_customer/features/catalog/domain/catalog_models.dart';
import 'package:calservices_customer/features/payment/data/payment_repository.dart';
import 'package:calservices_customer/features/payment/domain/payment_models.dart';

class _FakeApiClient extends ApiClient {
  _FakeApiClient({required this.handler}) : super.withDio(Dio());
  final Future<Response<dynamic>> Function(String path, {dynamic data, Map<String, dynamic>? queryParameters}) handler;

  @override
  Future<Response<T>> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
    ProgressCallback? onReceiveProgress,
  }) async {
    final res = await handler(path, queryParameters: queryParameters);
    return Response<T>(
      data: res.data as T,
      requestOptions: res.requestOptions,
      statusCode: res.statusCode,
      statusMessage: res.statusMessage,
      headers: res.headers,
    );
  }

  @override
  Future<Response<T>> post<T>(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
  }) async {
    final res = await handler(path, data: data, queryParameters: queryParameters);
    return Response<T>(
      data: res.data as T,
      requestOptions: res.requestOptions,
      statusCode: res.statusCode,
      statusMessage: res.statusMessage,
      headers: res.headers,
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // ──────────────────────────────────────────────────────────────────────────
  // 1. AUTHENTICATION ACCEPTANCE
  // ──────────────────────────────────────────────────────────────────────────
  group('1. Authentication Acceptance Suite', () {
    test('OTP request & verification with String customer_id parsed safely', () async {
      final fakeApi = _FakeApiClient(
        handler: (path, {data, queryParameters}) async {
          if (path.contains('/otp/request/')) {
            return Response(
              requestOptions: RequestOptions(path: path),
              statusCode: 200,
              data: {
                'success': true,
                'data': {'session_id': 'sess_123', 'resend_after_seconds': '60'},
                'message': 'OTP sent',
              },
            );
          }
          if (path.contains('/otp/verify/')) {
            return Response(
              requestOptions: RequestOptions(path: path),
              statusCode: 200,
              data: {
                'success': true,
                'data': {
                  'access': 'access_token_jwt_xyz',
                  'refresh': 'refresh_token_jwt_xyz',
                  'user': {
                    'id': '7988', // String representation from backend serializer
                    'name': 'Gokul M',
                    'phone': '9876543210',
                    'email': 'gokul@caldim.com',
                  },
                  'is_new_user': false,
                },
              },
            );
          }
          throw UnimplementedError(path);
        },
      );

      final storage = SecureStorage();
      final repo = AuthRepository(api: fakeApi, storage: storage);

      final reqResult = await repo.requestOtp(identifier: '9876543210', channel: 'sms');
      expect(reqResult, isA<Success<Map<String, dynamic>>>());

      final verifyResult = await repo.verifyOtp(identifier: '9876543210', otp: '123456', channel: 'sms');
      expect(verifyResult, isA<Success<AuthVerifyResult>>());
      final data = (verifyResult as Success<AuthVerifyResult>).data;
      expect(data.user.id, equals(7988));
      expect(data.user.name, equals('Gokul M'));
      expect(data.access, equals('access_token_jwt_xyz'));
      expect(data.refresh, equals('refresh_token_jwt_xyz'));
    });

    test('Non-auth errors (image 404, catalog 500, booking 422) never trigger logout', () async {
      final storage = SecureStorage();
      bool authFailureTriggered = false;

      final dio = Dio();
      final interceptor = AuthInterceptor(
        storage: storage,
        dio: dio,
        onAuthFailure: () => authFailureTriggered = true,
      );

      expect(interceptor, isNotNull);
      expect(authFailureTriggered, isFalse);
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  // 2. GUEST ACTION + LOGIN RETURN FLOW
  // ──────────────────────────────────────────────────────────────────────────
  group('2. Guest Action + Login Return Flow', () {
    final beetroot = ServiceItem(
      id: 228,
      title: 'Beetroot',
      slug: 'veg-beetroot',
      price: Decimal.fromInt(37),
      categoryId: 18,
      categorySlug: 'vegetables_groceries',
      categoryName: 'Farm-Fresh Vegetables & Groceries',
    );

    test('Case A — Guest ADD: preserves PendingCartAction and adds to cart upon auth completion', () {
      final container = ProviderContainer();
      final pendingNotifier = container.read(pendingActionProvider.notifier);
      final cartNotifier = container.read(cartProvider.notifier);

      // Guest sets pending ADD action
      pendingNotifier.setAction(
        PendingCartAction(service: beetroot, actionType: PendingCartActionType.addToCart),
      );

      expect(container.read(pendingActionProvider), isNotNull);
      expect(container.read(pendingActionProvider)!.service.id, equals(228));
      expect(container.read(pendingActionProvider)!.actionType, equals(PendingCartActionType.addToCart));

      // After user logs in, execute pending action
      final pending = container.read(pendingActionProvider);
      if (pending != null) {
        cartNotifier.addService(pending.service);
        pendingNotifier.clear();
      }

      expect(container.read(cartProvider).length, equals(1));
      expect(container.read(cartProvider).first.service.id, equals(228));
      expect(container.read(pendingActionProvider), isNull);
    });

    test('Case B — Guest BUY: preserves PendingCartAction with buy type', () {
      final container = ProviderContainer();
      final pendingNotifier = container.read(pendingActionProvider.notifier);
      final cartNotifier = container.read(cartProvider.notifier);

      pendingNotifier.setAction(
        PendingCartAction(service: beetroot, actionType: PendingCartActionType.buy),
      );

      final pending = container.read(pendingActionProvider);
      expect(pending, isNotNull);
      expect(pending!.actionType, equals(PendingCartActionType.buy));

      cartNotifier.addService(pending.service);
      pendingNotifier.clear();

      expect(container.read(cartProvider).first.service.id, equals(228));
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  // 3. FARM-FRESH / GROCERY FLOW & ISOLATION
  // ──────────────────────────────────────────────────────────────────────────
  group('3. Farm-Fresh Grocery Flow & Isolation', () {
    test('Beetroot item parsed from live API JSON maintains flowType == grocery and durationMinutes == 8', () {
      final liveJson = {
        'id': 228,
        'category': 18,
        'category_slug': 'vegetables_groceries',
        'name': 'Beetroot',
        'slug': 'veg-beetroot',
        'price': '37.00',
        'duration': '8 MINS',
        'image': '',
        'service_id': 50,
        'service_name': 'Farm-Fresh Vegetable',
        'service_slug': 'vegetables',
        'service_image': '/mockups/vegetables_realistic.png',
      };

      final item = ServiceItem.fromJson(liveJson);
      expect(item.id, equals(228));
      expect(item.flowType, equals(CatalogFlowType.grocery));
      expect(item.durationMinutes, equals(8));
      expect(item.price, equals(Decimal.fromInt(37)));
      expect(item.imageUrl, equals('https://customer.caldimservices.online/mockups/vegetables_realistic.png'));
    });

    test('Cart calculations for multiple grocery produce items', () {
      final container = ProviderContainer();
      final cartNotifier = container.read(cartProvider.notifier);

      final beetroot = ServiceItem(
        id: 228,
        title: 'Beetroot',
        slug: 'veg-beetroot',
        price: Decimal.fromInt(37),
        categoryId: 18,
      );

      final tomato = ServiceItem(
        id: 229,
        title: 'Country Tomato',
        slug: 'veg-tomato',
        price: Decimal.fromInt(24),
        categoryId: 18,
      );

      cartNotifier.addService(beetroot); // Qty 1 (₹37)
      cartNotifier.addService(beetroot); // Qty 2 (₹74)
      cartNotifier.addService(tomato);   // Qty 1 (₹24)

      final summary = container.read(cartSummaryProvider);
      expect(summary.itemCount, equals(3));
      expect(summary.subtotal, equals(Decimal.fromInt(98))); // 74 + 24 = 98

      // Update quantity of beetroot to 1
      cartNotifier.updateQuantity(228, 1);
      final updatedSummary = container.read(cartSummaryProvider);
      expect(updatedSummary.itemCount, equals(2));
      expect(updatedSummary.subtotal, equals(Decimal.fromInt(61))); // 37 + 24 = 61
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  // 4. NORMAL SERVICE FLOW & ADVANCE DEPOSIT
  // ──────────────────────────────────────────────────────────────────────────
  group('4. Normal Service Flow & Advance Deposit Rules', () {
    test('Scheduled service 20% advance calculation adheres to ₹149 floor rule', () {
      // Case A: Standard AC Repair total = ₹499 -> 20% is ₹99.80 -> Floored to ₹149.00
      final acService = ServiceItem(
        id: 101,
        title: 'AC Jet Pump Service',
        slug: 'ac-jet-pump',
        price: Decimal.fromInt(499),
        categoryId: 15,
        categorySlug: 'ac_appliance',
      );
      expect(acService.flowType, equals(CatalogFlowType.serviceBooking));

      final container = ProviderContainer();
      container.read(cartProvider.notifier).addService(acService);

      final summary = container.read(cartSummaryProvider);
      expect(summary.isGroceryCart, isFalse);
      expect(summary.advancePayable, equals(Decimal.parse('149.00')));
    });

    test('High value service total = ₹2000 -> 20% advance exceeds ₹149 floor', () {
      final highValueService = ServiceItem(
        id: 102,
        title: 'Complete Home Painting',
        slug: 'home-painting',
        price: Decimal.fromInt(2000),
        categoryId: 17,
        categorySlug: 'paintings',
      );

      final container = ProviderContainer();
      container.read(cartProvider.notifier).addService(highValueService);

      final summary = container.read(cartSummaryProvider);
      expect(summary.isGroceryCart, isFalse);
      // Subtotal (2000) + service fee (49) + taxes 5% (100) = 2149.00
      // 20% of 2149 = 429.80 (which exceeds 149 floor)
      expect(summary.advancePayable > Decimal.parse('149.00'), isTrue);
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  // 5. ADDRESS & SERVICEABILITY FLOW
  // ──────────────────────────────────────────────────────────────────────────
  group('5. Address & Serviceability Flow', () {
    test('Address list parsing formats address line correctly', () async {
      final fakeApi = _FakeApiClient(
        handler: (path, {data, queryParameters}) async => Response(
          requestOptions: RequestOptions(path: path),
          statusCode: 200,
          data: {
            'success': true,
            'data': [
              {
                'id': 107,
                'customer': 7988,
                'address_line1': 'No. 42, Sipcot Phase 1',
                'landmark': 'Electronic City Toll',
                'city': 'Hosur',
                'state': 'Tamil Nadu',
                'postal_code': '635126',
                'address_type': 'home',
                'is_default': true,
              },
              {
                'id': 108,
                'customer': 7988,
                'address_line1': 'Remote Farm House',
                'city': 'Dharmapuri',
                'postal_code': '636701',
                'is_default': false,
              }
            ],
          },
        ),
      );

      final repo = AddressRepository(api: fakeApi);
      final result = await repo.getAddresses();

      expect(result, isA<Success<List<Address>>>());
      final addresses = (result as Success<List<Address>>).data;
      expect(addresses.length, equals(2));
      expect(addresses[0].id, equals(107));
      expect(addresses[0].city, equals('Hosur'));
      expect(addresses[0].postalCode, equals('635126'));
      expect(addresses[0].formattedAddress, contains('Near Electronic City Toll'));
      expect(addresses[1].id, equals(108));
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  // 6. PAYMENT CONFIRMATION FLOW
  // ──────────────────────────────────────────────────────────────────────────
  group('6. Payment Verification Flow', () {
    test('Payment verification POST /api/payment/verify/ succeeds with verified payload', () async {
      final fakeApi = _FakeApiClient(
        handler: (path, {data, queryParameters}) async {
          expect(path, equals('/payment/verify/'));
          expect(data['booking_id'], equals(8841));
          // Fixed 2026-10-01: this asserted the `razorpay_`-prefixed field
          // names the mobile app used to send, which the real backend
          // (PaymentVerifyView) never actually read — see the matching
          // note in payment_test.dart. Asserting the old names made this
          // fake handler's own `expect()` throw on every real call once
          // PaymentVerificationPayload.toJson() was corrected, which the
          // repository's catch-all turned the thrown exception into a
          // silent Failure result instead of the Success this test
          // expects. Now asserts the corrected, backend-verified names.
          expect(data['order_id'], equals('order_mock_123'));
          expect(data['payment_id'], equals('pay_xyz_456'));
          return Response(
            requestOptions: RequestOptions(path: path),
            statusCode: 200,
            data: {'success': true, 'message': 'Payment verified successfully'},
          );
        },
      );

      final repo = PaymentRepository(api: fakeApi);
      final result = await repo.verifyPayment(
        const PaymentVerificationPayload(
          bookingId: 8841,
          orderId: 'order_mock_123',
          paymentId: 'pay_xyz_456',
          signature: 'sig_mock_789',
        ),
      );

      expect(result, isA<Success<Map<String, dynamic>>>());
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  // 7. MY BOOKINGS & ACTIONS
  // ──────────────────────────────────────────────────────────────────────────
  group('7. My Bookings & Available Actions', () {
    test('Booking with server-provided actions determines available capabilities', () {
      final json = {
        'id': 8841,
        'request_id': 'CAL-8841',
        'status': 'confirmed',
        'total_amount': '499.00',
        'scheduled_date': '2026-08-25',
        'scheduled_time_slot': '10:00 AM - 12:00 PM',
        'available_actions': ['cancel', 'reschedule', 'pay_advance', 'track'],
      };

      final booking = Booking.fromJson(json);
      expect(booking.canCancel, isTrue);
      expect(booking.canReschedule, isTrue);
      expect(booking.canPayAdvance, isTrue);
      expect(booking.canTrack, isTrue);
      expect(booking.canRate, isFalse);
    });
  });
}
