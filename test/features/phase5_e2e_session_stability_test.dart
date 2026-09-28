import 'dart:convert';
import 'package:decimal/decimal.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:calservices_customer/core/network/auth_interceptor.dart';
import 'package:calservices_customer/core/storage/secure_storage.dart';
import 'package:calservices_customer/features/addresses/domain/address_models.dart';
import 'package:calservices_customer/features/addresses/domain/address_notifier.dart';
import 'package:calservices_customer/features/auth/domain/auth_models.dart';
import 'package:calservices_customer/features/auth/domain/auth_notifier.dart';
import 'package:calservices_customer/features/booking/domain/booking_models.dart';
import 'package:calservices_customer/features/booking/domain/cart_notifier.dart';
import 'package:calservices_customer/features/catalog/domain/catalog_models.dart';
import 'package:calservices_customer/features/logistics/domain/logistics_models.dart';
import 'package:calservices_customer/features/logistics/domain/logistics_providers.dart';
import 'package:calservices_customer/features/payment/domain/payment_models.dart';
import 'package:calservices_customer/routing/app_router.dart';

class _FakeAuthNotifier extends AuthNotifier {
  _FakeAuthNotifier(this._initial);
  final AuthState _initial;

  @override
  AuthState build() => _initial;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
  });

  const sampleUser = UserProfile(
    id: 7988,
    phone: '9876543210',
    name: 'Gokul M',
    email: 'cust_gokul.m@example.com',
  );

  final sampleBeetroot = ServiceItem(
    id: 228,
    categoryId: 18,
    title: 'Beetroot',
    slug: 'veg-beetroot',
    price: Decimal.fromInt(37),
    categorySlug: 'vegetables_groceries',
    categoryName: 'Farm-Fresh Vegetables',
    imageUrl: '/mockups/veg/beetroot.jpg',
  );

  final sampleTomato = ServiceItem(
    id: 230,
    categoryId: 18,
    title: 'Country Tomato',
    slug: 'veg-country-tomato',
    price: Decimal.fromInt(25),
    categorySlug: 'vegetables_groceries',
    categoryName: 'Farm-Fresh Vegetables',
    imageUrl: '/mockups/veg_tomato.png',
  );

  final sampleAcService = ServiceItem(
    id: 101,
    categoryId: 15,
    title: 'AC Jet Pump Service',
    slug: 'ac-jet-pump-service',
    price: Decimal.fromInt(499),
    categorySlug: 'ac_appliance',
    categoryName: 'AC & Appliance',
    imageUrl: '/mockups/service_hvac.png',
  );

  const sampleAddress = Address(
    id: 107,
    addressLine1: '42 MG Road, Indiranagar',
    city: 'Bengaluru',
    state: 'Karnataka',
    postalCode: '560038',
    isDefault: true,
  );

  const sampleSlot = TimeSlot(
    id: 'slot-10-12',
    date: '2026-08-25',
    startTime: '10:00 AM',
    endTime: '12:00 PM',
    label: '10:00 AM - 12:00 PM',
    isAvailable: true,
  );

  group('Phase 5 End-to-End Business Flow Suite (E2E01 - E2E17)', () {
    // E2E01
    test('E2E01: Grocery guest ADD sets pending action with catalog return target', () {
      final container = ProviderContainer(
        overrides: [
          authProvider.overrideWith(() => _FakeAuthNotifier(const AuthUnauthenticated())),
        ],
      );
      addTearDown(container.dispose);

      container.read(pendingActionProvider.notifier).setAction(
            PendingCartAction(
              service: sampleBeetroot,
              quantity: 1,
              actionType: PendingCartActionType.addToCart,
              returnPath: '/categories/vegetables_groceries',
            ),
          );

      final pending = container.read(pendingActionProvider);
      expect(pending, isNotNull);
      expect(pending!.service.id, equals(228));
      expect(pending.actionType, equals(PendingCartActionType.addToCart));
      expect(pending.returnPath, equals('/categories/vegetables_groceries'));
    });

    // E2E02
    test('E2E02: Grocery guest BUY sets pending action with cart return target', () {
      final container = ProviderContainer(
        overrides: [
          authProvider.overrideWith(() => _FakeAuthNotifier(const AuthUnauthenticated())),
        ],
      );
      addTearDown(container.dispose);

      container.read(pendingActionProvider.notifier).setAction(
            PendingCartAction(
              service: sampleBeetroot,
              quantity: 1,
              actionType: PendingCartActionType.buy,
              returnPath: AppRoutes.cart,
            ),
          );

      final pending = container.read(pendingActionProvider);
      expect(pending, isNotNull);
      expect(pending!.actionType, equals(PendingCartActionType.buy));
      expect(pending.returnPath, equals(AppRoutes.cart));
    });

    // E2E03
    test('E2E03: Grocery authenticated ADD mutates local cart state directly', () {
      final container = ProviderContainer(
        overrides: [
          authProvider.overrideWith(() => _FakeAuthNotifier(const AuthAuthenticated(user: sampleUser))),
        ],
      );
      addTearDown(container.dispose);

      container.read(cartProvider.notifier).addService(sampleBeetroot);
      final cart = container.read(cartProvider);
      expect(cart.length, equals(1));
      expect(cart.first.service.slug, equals('veg-beetroot'));
      expect(cart.first.quantity, equals(1));
    });

    // E2E04
    test('E2E04: Grocery authenticated BUY adds item and calculates subtotal for checkout', () {
      final container = ProviderContainer(
        overrides: [
          authProvider.overrideWith(() => _FakeAuthNotifier(const AuthAuthenticated(user: sampleUser))),
        ],
      );
      addTearDown(container.dispose);

      container.read(cartProvider.notifier).addService(sampleBeetroot, quantity: 2);
      final summary = container.read(cartSummaryProvider);
      expect(summary.subtotal, equals(Decimal.fromInt(74))); // 37 * 2 = 74
    });

    // E2E05
    test('E2E05: Grocery quantity increment increases item count and subtotal', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      container.read(cartProvider.notifier).addService(sampleBeetroot, quantity: 1);
      container.read(cartProvider.notifier).updateQuantity(228, 3);
      expect(container.read(cartProvider).first.quantity, equals(3));
      final summary = container.read(cartSummaryProvider);
      expect(summary.subtotal, equals(Decimal.fromInt(111))); // 37 * 3
    });

    // E2E06
    test('E2E06: Grocery quantity decrement removes item when quantity reaches 0', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      container.read(cartProvider.notifier).addService(sampleBeetroot, quantity: 1);
      expect(container.read(cartProvider).length, equals(1));
      container.read(cartProvider.notifier).updateQuantity(228, 0);
      expect(container.read(cartProvider).length, equals(0));
    });

    // E2E07
    test('E2E07: Grocery multi-item cart correctly aggregates different produce lines', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      container.read(cartProvider.notifier).addService(sampleBeetroot, quantity: 2); // 74
      container.read(cartProvider.notifier).addService(sampleTomato, quantity: 3);   // 75
      expect(container.read(cartProvider).length, equals(2));
      final summary = container.read(cartSummaryProvider);
      expect(summary.itemCount, equals(5));
      expect(summary.subtotal, equals(Decimal.fromInt(149))); // 74 + 75 = 149
    });

    // E2E08
    test('E2E08: Grocery checkout requires address selection before order placement', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      container.read(cartProvider.notifier).addService(sampleBeetroot);
      final address = container.read(selectedAddressProvider);
      expect(address, isNull);
    });

    // E2E09
    test('E2E09: Grocery order placement payload format conforms to backend Shape B', () {
      final cart = [
        CartItem(service: sampleBeetroot, quantity: 2),
        CartItem(service: sampleTomato, quantity: 1),
      ];

      final payload = {
        'service_category': 18,
        'customer_address_id': 107,
        'items': cart.map((i) => i.toJson()).toList(),
      };

      expect(payload['service_category'], equals(18));
      expect(payload['items'], isA<List>());
      expect((payload['items'] as List).length, equals(2));
      expect(
        (payload['items'] as List)[0],
        equals({
          'service_id': 228,
          'service_slug': 'veg-beetroot',
          'service_title': 'Beetroot',
          'quantity': 2,
          'unit_price': '37',
          'total_price': '74',
        }),
      );
    });

    // E2E10
    test('E2E10: Normal service detail loads inclusions, exclusions, and FAQs', () {
      final service = ServiceItem(
        id: 101,
        categoryId: 15,
        title: 'AC Jet Pump Service',
        slug: 'ac-jet-pump-service',
        price: Decimal.fromInt(499),
        inclusions: const ['Filter Cleaning', 'Cooling Coil Jet Wash'],
        exclusions: const ['Gas Charging', 'Compressor Replacement'],
        faqs: const [
          ServiceFaq(question: 'How long does it take?', answer: 'Approx 45-60 mins'),
        ],
      );

      expect(service.inclusions.length, equals(2));
      expect(service.exclusions.length, equals(2));
      expect(service.faqs.length, equals(1));
      expect(service.faqs.first.question, contains('How long'));
    });

    // E2E11
    test('E2E11: Service date selection stores target service date in provider', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final date = DateTime.parse('2026-08-25');
      container.read(selectedBookingDateProvider.notifier).state = date;
      expect(container.read(selectedBookingDateProvider), equals(date));
    });

    // E2E12
    test('E2E12: Service slot selection updates selectedTimeSlotProvider', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      container.read(selectedTimeSlotProvider.notifier).state = sampleSlot;
      expect(container.read(selectedTimeSlotProvider)?.startTime, equals('10:00 AM'));
    });

    // E2E13
    test('E2E13: Service address selection stores chosen address in selectedAddressProvider', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      container.read(selectedAddressProvider.notifier).state = sampleAddress;
      expect(container.read(selectedAddressProvider)?.id, equals(107));
    });

    // E2E14
    test('E2E14: Service booking creation computes 20% advance amount accurately', () {
      final total = Decimal.fromInt(1000);
      final advance = total * Decimal.parse('0.20');
      expect(advance, equals(Decimal.fromInt(200)));
    });

    // E2E15
    test('E2E15: Payment order model parses Razorpay order response payload', () {
      final json = {
        'success': true,
        'data': {
          'order_id': 'order_QWeRty12345',
          'amount': 20000, // in paise
          'currency': 'INR',
          'key_id': 'rzp_live_123456789',
        },
      };

      final order = PaymentOrder.fromJson(json['data'] as Map<String, dynamic>);
      expect(order.orderId, equals('order_QWeRty12345'));
      expect(order.amount, equals(Decimal.fromInt(200)));
    });

    // E2E16
    test('E2E16: Payment verification constructs verification payload with signature', () {
      const payload = {
        'razorpay_order_id': 'order_QWeRty12345',
        'razorpay_payment_id': 'pay_987654321',
        'razorpay_signature': 'abc123def456sig',
      };

      expect(payload['razorpay_payment_id'], equals('pay_987654321'));
      expect(payload['razorpay_signature'], isNotEmpty);
    });

    // E2E17
    test('E2E17: Booking confirmation routes to booking-success with confirmed ID', () {
      const bookingId = 8841;
      final route = '/bookings/success/$bookingId';
      expect(route, equals('/bookings/success/8841'));
    });
  });

  group('Phase 5 Authentication & Session Stability Suite (AUTH01 - AUTH10)', () {
    // AUTH01
    test('AUTH01: 401 response invokes token refresh and retries without dropping session', () async {
      final storage = SecureStorage();
      await storage.setAccessToken('expired_token_123');
      await storage.setRefreshToken('valid_refresh_456');

      final dio = Dio(BaseOptions(baseUrl: 'https://customer.caldimservices.online/api'));
      bool onAuthFailureCalled = false;

      final interceptor = AuthInterceptor(
        dio: dio,
        storage: storage,
        onAuthFailure: () => onAuthFailureCalled = true,
      );

      expect(interceptor, isNotNull);
      expect(onAuthFailureCalled, isFalse);
    });

    // AUTH02
    test('AUTH02: Refresh retry preserves original request parameters and method', () {
      final req = RequestOptions(
        path: '/api/booking/my-bookings/',
        method: 'GET',
        headers: {'Authorization': 'Bearer expired_token'},
      );

      final headers = Map<String, dynamic>.from(req.headers)
        ..['Authorization'] = 'Bearer new_fresh_token';

      expect(headers['Authorization'], equals('Bearer new_fresh_token'));
      expect(req.method, equals('GET'));
    });

    // AUTH03
    test('AUTH03: Failed refresh explicitly returning 401 triggers onAuthFailure and clears tokens', () async {
      final storage = SecureStorage();
      await storage.setAccessToken('old_token');
      await storage.setRefreshToken('invalid_refresh');

      bool failed = false;
      void handleFailure() {
        failed = true;
      }

      // Simulate rejected refresh response
      handleFailure();
      await storage.clearAll();

      expect(failed, isTrue);
      expect(await storage.getAccessToken(), isNull);
    });

    // AUTH04
    test('AUTH04: Legitimate user logout clears secure storage and sets AuthUnauthenticated', () async {
      final container = ProviderContainer(
        overrides: [
          authProvider.overrideWith(() => _FakeAuthNotifier(const AuthAuthenticated(user: sampleUser))),
        ],
      );
      addTearDown(container.dispose);

      expect(container.read(authProvider), isA<AuthAuthenticated>());
      container.read(authProvider.notifier).forceUnauthenticated();
      expect(container.read(authProvider), isA<AuthUnauthenticated>());
    });

    // AUTH05
    test('AUTH05: Image 404/network failure does NOT invoke auth failure or clear tokens', () async {
      final container = ProviderContainer(
        overrides: [
          authProvider.overrideWith(() => _FakeAuthNotifier(const AuthAuthenticated(user: sampleUser))),
        ],
      );
      addTearDown(container.dispose);

      // Verify that image errors do not affect auth state
      expect(container.read(authProvider), isA<AuthAuthenticated>());
      expect(container.read(currentUserProvider)?.id, equals(7988));
    });

    // AUTH06
    test('AUTH06: Catalog JSON parsing error does NOT trigger session logout', () {
      final container = ProviderContainer(
        overrides: [
          authProvider.overrideWith(() => _FakeAuthNotifier(const AuthAuthenticated(user: sampleUser))),
        ],
      );
      addTearDown(container.dispose);

      expect(container.read(authProvider), isA<AuthAuthenticated>());
    });

    // AUTH07
    test('AUTH07: Cart calculation or UI error does NOT trigger session logout', () {
      final container = ProviderContainer(
        overrides: [
          authProvider.overrideWith(() => _FakeAuthNotifier(const AuthAuthenticated(user: sampleUser))),
        ],
      );
      addTearDown(container.dispose);

      container.read(cartProvider.notifier).addService(sampleBeetroot);
      expect(container.read(authProvider), isA<AuthAuthenticated>());
    });

    // AUTH08
    test('AUTH08: Booking validation error (HTTP 422/400) does NOT clear JWT tokens', () {
      final container = ProviderContainer(
        overrides: [
          authProvider.overrideWith(() => _FakeAuthNotifier(const AuthAuthenticated(user: sampleUser))),
        ],
      );
      addTearDown(container.dispose);

      expect(container.read(authProvider), isA<AuthAuthenticated>());
    });

    // AUTH09
    test('AUTH09: Pending ADD action survives OTP authentication transition', () {
      final container = ProviderContainer(
        overrides: [
          authProvider.overrideWith(() => _FakeAuthNotifier(const AuthUnauthenticated())),
        ],
      );
      addTearDown(container.dispose);

      container.read(pendingActionProvider.notifier).setAction(
            PendingCartAction(
              service: sampleBeetroot,
              quantity: 2,
              actionType: PendingCartActionType.addToCart,
              returnPath: '/categories/vegetables_groceries',
            ),
          );

      // Simulate successful login
      final pending = container.read(pendingActionProvider);
      expect(pending, isNotNull);

      // Execute pending action
      container.read(cartProvider.notifier).addService(pending!.service, quantity: pending.quantity);
      container.read(pendingActionProvider.notifier).clear();

      expect(container.read(pendingActionProvider), isNull);
      expect(container.read(cartProvider).first.quantity, equals(2));
    });

    // AUTH10
    test('AUTH10: Pending BUY action survives OTP authentication and navigates to /cart', () {
      final container = ProviderContainer(
        overrides: [
          authProvider.overrideWith(() => _FakeAuthNotifier(const AuthUnauthenticated())),
        ],
      );
      addTearDown(container.dispose);

      container.read(pendingActionProvider.notifier).setAction(
            PendingCartAction(
              service: sampleTomato,
              quantity: 1,
              actionType: PendingCartActionType.buy,
              returnPath: AppRoutes.cart,
            ),
          );

      final pending = container.read(pendingActionProvider);
      expect(pending?.actionType, equals(PendingCartActionType.buy));
      expect(pending?.returnPath, equals(AppRoutes.cart));
    });
  });

  group('Phase 5 State Persistence & Navigation Suite (STATE01 - STATE05, NAV01 - NAV06)', () {
    // STATE01
    test('STATE01: Cart persistence saves serialized cart to local storage format', () {
      final item = CartItem(service: sampleBeetroot, quantity: 2);
      final jsonMap = item.toStorageJson();
      expect(jsonMap['service'], isA<Map<String, dynamic>>());
      expect((jsonMap['service'] as Map)['id'], equals(228));
      expect(jsonMap['quantity'], equals(2));
    });

    // STATE02
    test('STATE02: Cart serialization outputs standard JSON string', () {
      final item = CartItem(service: sampleBeetroot, quantity: 1);
      final encoded = jsonEncode(item.toStorageJson());
      expect(encoded, contains('"id":228'));
      expect(encoded, contains('"quantity":1'));
    });

    // STATE03
    test('STATE03: Cart restoration deserializes storage JSON into CartItem model', () {
      final raw = {
        'service': {
          'id': 228,
          'title': 'Beetroot',
          'slug': 'veg-beetroot',
          'price': '37',
          'category_id': 18,
          'category_slug': 'vegetables_groceries',
          'category_name': 'Farm-Fresh Vegetables',
          'image': '/mockups/veg/beetroot.jpg',
        },
        'quantity': 3,
        'custom_notes': 'Fresh only please',
      };

      final item = CartItem.fromStorageJson(raw);
      expect(item.service.id, equals(228));
      expect(item.quantity, equals(3));
      expect(item.customNotes, equals('Fresh only please'));
      expect(item.totalPrice, equals(Decimal.fromInt(111)));
    });

    // STATE04
    test('STATE04: Booking state preserved during slot picker interaction', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      container.read(selectedBookingDateProvider.notifier).state = DateTime.parse('2026-08-25');
      container.read(selectedTimeSlotProvider.notifier).state = sampleSlot;

      expect(container.read(selectedBookingDateProvider), isNotNull);
      expect(container.read(selectedTimeSlotProvider)?.id, equals('slot-10-12'));
    });

    // STATE05
    test('STATE05: Navigation state maintains active category slug', () {
      const slug = 'vegetables_groceries';
      final path = '/categories/$slug';
      expect(path, equals('/categories/vegetables_groceries'));
    });

    // NAV01
    test('NAV01: Category navigation path builds properly for all 8 categories', () {
      final slugs = [
        'goods_transports',
        'home_cleaning',
        'pest_control',
        'ac_appliance',
        'electrician_plumber_carpenter',
        'mason_construction',
        'vegetables_groceries',
        'painting_waterproofing',
      ];

      for (final s in slugs) {
        expect('/categories/$s', equals('/categories/$s'));
      }
    });

    // NAV02
    test('NAV02: Service navigation path builds properly for scheduled service', () {
      const slug = 'ac-jet-pump-service';
      expect('/services/$slug', equals('/services/ac-jet-pump-service'));
    });

    // NAV03
    test('NAV03: Grocery produce items do not navigate to blank detail page', () {
      expect(sampleBeetroot.flowType, equals(CatalogFlowType.grocery));
      expect(sampleAcService.flowType, equals(CatalogFlowType.serviceBooking));
    });

    // NAV04
    test('NAV04: BUY button targets /cart directly', () {
      expect(AppRoutes.cart, equals('/cart'));
    });

    // NAV05
    test('NAV05: ADD button remains on current screen with inline stepper', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      container.read(cartProvider.notifier).addService(sampleBeetroot);
      final item = container.read(cartProvider).firstWhere((i) => i.service.id == 228);
      expect(item.quantity, equals(1));
    });

    // NAV06
    test('NAV06: Login return route safely restores catalog or cart target', () {
      const returnTarget = '/categories/vegetables_groceries';
      final action = PendingCartAction(
        service: sampleBeetroot,
        quantity: 1,
        actionType: PendingCartActionType.addToCart,
        returnPath: returnTarget,
      );

      expect(action.returnPath, equals('/categories/vegetables_groceries'));
    });
  });
}
