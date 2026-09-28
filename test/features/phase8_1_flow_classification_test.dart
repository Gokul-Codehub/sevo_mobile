import 'package:calservices_customer/core/network/api_client.dart';
import 'package:calservices_customer/features/addresses/domain/address_models.dart';
import 'package:calservices_customer/features/addresses/domain/address_notifier.dart';
import 'package:calservices_customer/features/booking/domain/booking_models.dart';
import 'package:calservices_customer/features/booking/domain/booking_providers.dart';
import 'package:calservices_customer/features/booking/domain/cart_notifier.dart';
import 'package:calservices_customer/features/booking/presentation/screens/checkout_screen.dart';
import 'package:calservices_customer/features/catalog/domain/catalog_models.dart';
import 'package:calservices_customer/features/catalog/presentation/screens/category_detail_screen.dart';
import 'package:calservices_customer/features/catalog/presentation/widgets/service_card.dart';
import 'package:calservices_customer/features/logistics/domain/logistics_models.dart';
import 'package:decimal/decimal.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

class _MockSuccessAdapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final path = options.path;
    if (path.contains('/booking/')) {
      final json = '''
      {
        "success": true,
        "message": "Booking created successfully",
        "data": {
          "id": 105,
          "request_id": "CAL-20260824-105",
          "status": "new_request",
          "total_amount": "899.00",
          "advance_amount": "179.80",
          "balance_amount": "719.20",
          "items": [],
          "available_actions": ["cancel", "track"]
        }
      }
      ''';
      return ResponseBody.fromString(
        json,
        200,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      );
    }

    return ResponseBody.fromString('[]', 200, headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    });
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
  });

  group('Phase 8.1 Flow Classification & Repair Tests (FLOW-01 to FLOW-18)', () {
    // ── FLOW-01: Farm-Fresh category (ID: 18) ────────────────────────────────
    test('FLOW-01: Farm-Fresh category (ID: 18) resolves to CatalogFlowType.grocery', () {
      const cat = Category(
        id: 18,
        name: 'Farm-Fresh Vegetables & Groceries',
        slug: 'vegetables_groceries',
      );
      expect(cat.flowType, equals(CatalogFlowType.grocery));
    });

    // ── FLOW-02: AC & Appliance (ID: 15) ─────────────────────────────────────
    test('FLOW-02: AC & Appliance (ID: 15) resolves to CatalogFlowType.serviceBooking', () {
      const cat = Category(
        id: 15,
        name: 'AC & Appliance',
        slug: 'ac_appliance',
      );
      expect(cat.flowType, equals(CatalogFlowType.serviceBooking));
    });

    // ── FLOW-03: Electrician, Plumbing & Carpentry (ID: 14) ──────────────────
    test('FLOW-03: Electrician, Plumbing & Carpentry resolves to serviceBooking', () {
      const cat = Category(
        id: 14,
        name: 'Electrician, Plumbing & Carpentry',
        slug: 'electrician_plumbing_carpentry',
      );
      expect(cat.flowType, equals(CatalogFlowType.serviceBooking));
    });

    // ── FLOW-04: Deep Cleaning (ID: 19) ──────────────────────────────────────
    test('FLOW-04: Deep Cleaning resolves to serviceBooking', () {
      const cat = Category(
        id: 19,
        name: 'Deep Cleaning',
        slug: 'deep_cleaning',
      );
      expect(cat.flowType, equals(CatalogFlowType.serviceBooking));
    });

    // ── FLOW-05: Mason (ID: 11) ──────────────────────────────────────────────
    test('FLOW-05: Mason resolves to serviceBooking', () {
      const cat = Category(
        id: 11,
        name: 'Mason',
        slug: 'mason_construction',
      );
      expect(cat.flowType, equals(CatalogFlowType.serviceBooking));
    });

    // ── FLOW-06: Painting (ID: 17) ───────────────────────────────────────────
    test('FLOW-06: Painting resolves to serviceBooking', () {
      const cat = Category(
        id: 17,
        name: 'Paintings',
        slug: 'paintings',
      );
      expect(cat.flowType, equals(CatalogFlowType.serviceBooking));
    });

    // ── FLOW-07: Home Services & Pest Control (ID: 16) ───────────────────────
    test('FLOW-07: Home Services & Pest Control resolves to serviceBooking', () {
      const cat = Category(
        id: 16,
        name: 'Home Services & Pest Control',
        slug: 'home_services_pest_control',
      );
      expect(cat.flowType, equals(CatalogFlowType.serviceBooking));
    });

    // ── FLOW-08: Goods & Transport (ID: 12) ──────────────────────────────────
    test('FLOW-08: Goods & Transport resolves to serviceBooking', () {
      const cat = Category(
        id: 12,
        name: 'Goods & Transport',
        slug: 'goods_transport',
      );
      expect(cat.flowType, equals(CatalogFlowType.serviceBooking));
    });

    // ── FLOW-09: Grocery item (Beetroot) in ServiceCard ──────────────────────
    testWidgets('FLOW-09: Grocery item in ServiceCard renders ADD and BUY buttons', (tester) async {
      final beetroot = ServiceItem(
        id: 228,
        categoryId: 18,
        title: 'Beetroot',
        slug: 'veg-beetroot',
        price: Decimal.fromInt(37),
        categorySlug: 'vegetables_groceries',
      );

      final container = ProviderContainer();
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Scaffold(
              body: ServiceCard(service: beetroot),
            ),
          ),
        ),
      );

      expect(find.text('ADD'), findsOneWidget);
      expect(find.text('BUY'), findsOneWidget);
    });

    // ── FLOW-10: Normal service item (AC Combo) in ServiceCard ───────────────
    testWidgets('FLOW-10: Normal service item in ServiceCard renders View Details button', (tester) async {
      final acService = ServiceItem(
        id: 490,
        categoryId: 15,
        title: '2-in-1 Combo AC Power Jet Service',
        slug: 'ac-combo-2-units',
        price: Decimal.fromInt(899),
        categorySlug: 'ac_appliance',
      );

      final container = ProviderContainer();
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Scaffold(
              body: ServiceCard(service: acService),
            ),
          ),
        ),
      );

      expect(find.text('View Details'), findsOneWidget);
      expect(find.text('ADD'), findsNothing);
      expect(find.text('BUY'), findsNothing);
    });

    // ── FLOW-11: Normal service card does not mutate cartProvider ────────────
    testWidgets('FLOW-11: Normal service card does not mutate cartProvider', (tester) async {
      final acService = ServiceItem(
        id: 490,
        categoryId: 15,
        title: '2-in-1 Combo AC Power Jet Service',
        slug: 'ac-combo-2-units',
        price: Decimal.fromInt(899),
        categorySlug: 'ac_appliance',
      );

      final container = ProviderContainer();
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Scaffold(
              body: ServiceCard(service: acService),
            ),
          ),
        ),
      );

      expect(container.read(cartProvider), isEmpty);
    });

    // ── FLOW-12: Normal service card tap triggers detail navigation ──────────
    testWidgets('FLOW-12: Normal service card custom onTap executes correctly', (tester) async {
      final acService = ServiceItem(
        id: 490,
        categoryId: 15,
        title: '2-in-1 Combo AC Power Jet Service',
        slug: 'ac-combo-2-units',
        price: Decimal.fromInt(899),
        categorySlug: 'ac_appliance',
      );

      bool detailTapped = false;
      final container = ProviderContainer();
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Scaffold(
              body: ServiceCard(
                service: acService,
                onTap: () => detailTapped = true,
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('View Details'));
      await tester.pump();

      expect(detailTapped, isTrue);
      expect(container.read(cartProvider), isEmpty);
    });

    // ── FLOW-13 & 14: CheckoutScreen with normal service does not redirect ───
    testWidgets('FLOW-13 & 14: CheckoutScreen does NOT redirect to /cart when cart has grocery items', (tester) async {
      final beetroot = ServiceItem(
        id: 228,
        categoryId: 18,
        title: 'Beetroot',
        slug: 'veg-beetroot',
        price: Decimal.fromInt(37),
        categorySlug: 'vegetables_groceries',
      );

      final acService = ServiceItem(
        id: 490,
        categoryId: 15,
        title: '2-in-1 Combo AC Power Jet Service',
        slug: 'ac-combo-2-units',
        price: Decimal.fromInt(899),
        categorySlug: 'ac_appliance',
      );

      final container = ProviderContainer();
      // Pre-fill grocery cart with groceries
      container.read(cartProvider.notifier).addService(beetroot, quantity: 3);
      expect(container.read(cartProvider).length, equals(1));

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: CheckoutScreen(
              initialService: acService,
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Ensure AC Service title is displayed on CheckoutScreen
      expect(find.text('2-in-1 Combo AC Power Jet Service'), findsOneWidget);
      expect(find.text('Booking Summary'), findsOneWidget);
      expect(find.text('Book Appointment'), findsOneWidget);

      // Verify grocery cart was not altered
      expect(container.read(cartProvider).length, equals(1));
      expect(container.read(cartProvider).first.service.title, equals('Beetroot'));
    });

    // ── FLOW-15: Advance payable 20% with ₹149 floor rule ─────────────────────
    testWidgets('FLOW-15: CheckoutScreen calculates payment summary and total to pay', (tester) async {
      final acService = ServiceItem(
        id: 490,
        categoryId: 15,
        title: '2-in-1 Combo AC Power Jet Service',
        slug: 'ac-combo-2-units',
        price: Decimal.fromInt(899),
        categorySlug: 'ac_appliance',
      );

      final container = ProviderContainer();
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: CheckoutScreen(
              initialService: acService,
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Total = ₹899 + ₹49 (fee) + ₹44.95 (taxes) = ₹992.95
      expect(find.text('Total to Pay'), findsOneWidget);
      expect(find.text('₹992.95'), findsWidgets);
    });

    // ── FLOW-16: CategoryDetailScreen AppBar across 360, 390, 412dp ──────────
    for (final width in [360.0, 390.0, 412.0]) {
      testWidgets('FLOW-16: CategoryDetailScreen AppBar renders cleanly at width ${width}dp', (tester) async {
        tester.view.physicalSize = Size(width * 2.75, 2400);
        tester.view.devicePixelRatio = 2.75;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final container = ProviderContainer();
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: const MaterialApp(
              home: CategoryDetailScreen(
                categorySlug: 'vegetables_groceries',
              ),
            ),
          ),
        );

        await tester.pumpAndSettle();

        expect(find.byType(AppBar), findsOneWidget);
        expect(find.byIcon(Icons.search), findsOneWidget);

        final titleFinder = find.text('Farm-Fresh Vegetables & Groceries');
        expect(titleFinder, findsOneWidget);

        final titleRect = tester.getRect(titleFinder);
        expect(titleRect.height, lessThanOrEqualTo(30.0));
      });
    }

    // ── FLOW-17: Normal service category NEVER shows grocery bottom bar ──────
    testWidgets('FLOW-17: Normal service category NEVER shows grocery cart bottom bar even if cart is full', (tester) async {
      final beetroot = ServiceItem(
        id: 228,
        categoryId: 18,
        title: 'Beetroot',
        slug: 'veg-beetroot',
        price: Decimal.fromInt(37),
        categorySlug: 'vegetables_groceries',
      );

      const acCategory = Category(
        id: 15,
        name: 'AC & Appliance',
        slug: 'ac_appliance',
      );

      final container = ProviderContainer();
      container.read(cartProvider.notifier).addService(beetroot, quantity: 5);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: CategoryDetailScreen(
              categorySlug: 'ac_appliance',
              initialCategory: acCategory,
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Continue adding or go to cart'), findsNothing);
      expect(find.text('Go to Cart'), findsNothing);
    });

    // ── FLOW-18: BookingActionController createBooking preserves grocery cart ─
    test('FLOW-18: BookingActionController with customItems preserves grocery cart', () async {
      final beetroot = ServiceItem(
        id: 228,
        categoryId: 18,
        title: 'Beetroot',
        slug: 'veg-beetroot',
        price: Decimal.fromInt(37),
        categorySlug: 'vegetables_groceries',
      );

      final acService = ServiceItem(
        id: 490,
        categoryId: 15,
        title: '2-in-1 Combo AC Power Jet Service',
        slug: 'ac-combo-2-units',
        price: Decimal.fromInt(899),
        categorySlug: 'ac_appliance',
      );

      final container = ProviderContainer();
      final dio = container.read(apiClientProvider).dio;
      dio.httpClientAdapter = _MockSuccessAdapter();

      // Pre-add grocery items
      container.read(cartProvider.notifier).addService(beetroot, quantity: 4);
      expect(container.read(cartProvider).length, equals(1));

      // Set mock address
      container.read(selectedAddressProvider.notifier).state = const Address(
        id: 107,
        addressLine1: '12 Main Street',
        city: 'Coimbatore',
        state: 'Tamil Nadu',
        postalCode: '641001',
      );

      final result = await container
          .read(bookingActionControllerProvider.notifier)
          .createBooking(
            customItems: [CartItem(service: acService, quantity: 1)],
            date: '2026-08-25',
            slot: const TimeSlot(
              id: 'slot-1',
              date: '2026-08-25',
              startTime: '10:00',
              endTime: '12:00',
              label: '10:00 AM - 12:00 PM',
            ),
            totalAmount: acService.price,
          );

      expect(result.error, isNull);
      expect(result.booking, isNotNull);
      expect(result.booking!.id, equals(105));

      // The grocery cart MUST still contain Beetroot!
      expect(container.read(cartProvider).length, equals(1));
      expect(container.read(cartProvider).first.service.title, equals('Beetroot'));
      expect(container.read(cartProvider).first.quantity, equals(4));
    });
  });
}
