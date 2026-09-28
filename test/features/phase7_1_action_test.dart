import 'package:calservices_customer/features/booking/domain/booking_models.dart';
import 'package:calservices_customer/features/booking/domain/cart_notifier.dart';
import 'package:calservices_customer/features/catalog/domain/catalog_models.dart';
import 'package:calservices_customer/features/catalog/presentation/widgets/service_card.dart';
import 'package:calservices_customer/routing/app_router.dart';
import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final beetroot = ServiceItem(
    id: 228,
    title: 'Beetroot',
    slug: 'veg-beetroot',
    price: Decimal.fromInt(37),
    durationMinutes: 8,
    categoryId: 18,
    categorySlug: 'vegetables_groceries',
    categoryName: 'Farm-Fresh Vegetables & Groceries',
  );

  final amla = ServiceItem(
    id: 244,
    title: 'Amlaa (Nellikaai)',
    slug: 'veg-amla',
    price: Decimal.fromInt(64),
    durationMinutes: 8,
    categoryId: 18,
    categorySlug: 'vegetables_groceries',
    categoryName: 'Farm-Fresh Vegetables & Groceries',
  );

  final acService = ServiceItem(
    id: 101,
    title: '2-in-1 Combo AC Power Jet Service',
    slug: '2-in-1-combo-ac-power-jet-service',
    price: Decimal.fromInt(499),
    durationMinutes: 60,
    categoryId: 15,
    categorySlug: 'ac_appliance',
    categoryName: 'AC & Appliance',
  );

  // ──────────────────────────────────────────────────────────────────────────
  // 1. FARM-FRESH ADD & STEPPER TAP TEST (AUTHENTICATED)
  // ──────────────────────────────────────────────────────────────────────────
  testWidgets('Phase 7.1 — Farm-Fresh ADD: Real Tap, Inline Stepper, and Cart Sync', (tester) async {
    final container = ProviderContainer(
      overrides: [
        isUserAuthenticatedProvider.overrideWithValue(true),
      ],
    );
    final cartNotifier = container.read(cartProvider.notifier);
    cartNotifier.clearCart();

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
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // 1. Initial State: ADD and BUY buttons visible
    expect(find.text('ADD'), findsOneWidget);
    expect(find.text('BUY'), findsOneWidget);
    expect(container.read(cartProvider).isEmpty, isTrue);

    // 2. Action: Tap ADD
    await tester.tap(find.text('ADD'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // 3. Verify: Quantity = 1, Stepper visible, Cart contains Beetroot
    expect(find.text('1'), findsOneWidget);
    expect(find.byIcon(Icons.add), findsOneWidget);
    expect(find.byIcon(Icons.remove), findsOneWidget);
    expect(container.read(cartProvider).length, equals(1));
    expect(container.read(cartProvider).first.service.id, equals(228));
    expect(container.read(cartProvider).first.quantity, equals(1));

    // 4. Action: Tap + (qty -> 2)
    await tester.tap(find.byIcon(Icons.add));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('2'), findsOneWidget);
    expect(container.read(cartProvider).first.quantity, equals(2));

    // 5. Action: Tap + (qty -> 3)
    await tester.tap(find.byIcon(Icons.add));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('3'), findsOneWidget);
    expect(container.read(cartProvider).first.quantity, equals(3));

    // 6. Action: Tap - (qty -> 2)
    await tester.tap(find.byIcon(Icons.remove));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('2'), findsOneWidget);
    expect(container.read(cartProvider).first.quantity, equals(2));

    // 7. Action: Tap - (qty -> 1)
    await tester.tap(find.byIcon(Icons.remove));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('1'), findsOneWidget);
    expect(container.read(cartProvider).first.quantity, equals(1));

    // 8. Action: Tap - (qty -> 0 -> Reset to ADD)
    await tester.tap(find.byIcon(Icons.remove));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('ADD'), findsOneWidget);
    expect(container.read(cartProvider).isEmpty, isTrue);
  });

  // ──────────────────────────────────────────────────────────────────────────
  // 2. FARM-FRESH BUY & CONTINUE SHOPPING (AUTHENTICATED)
  // ──────────────────────────────────────────────────────────────────────────
  testWidgets('Phase 7.1 — Farm-Fresh BUY: Adds item and opens cart directly', (tester) async {
    final container = ProviderContainer(
      overrides: [
        isUserAuthenticatedProvider.overrideWithValue(true),
      ],
    );
    final cartNotifier = container.read(cartProvider.notifier);
    cartNotifier.clearCart();

    final testRouter = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => Scaffold(body: ServiceCard(service: beetroot)),
        ),
        GoRoute(
          path: AppRoutes.cart,
          builder: (context, state) => const Scaffold(body: Text('Cart Screen Rendered')),
        ),
      ],
    );

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(
          routerConfig: testRouter,
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // Tap BUY
    await tester.tap(find.text('BUY'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // Verify Beetroot is added to cart and cart screen routed
    expect(container.read(cartProvider).length, equals(1));
    expect(container.read(cartProvider).first.service.id, equals(228));
    expect(container.read(cartProvider).first.quantity, equals(1));
    expect(find.text('Cart Screen Rendered'), findsOneWidget);

    // Continue shopping: Add second produce item (Amla)
    cartNotifier.addService(amla);
    expect(container.read(cartProvider).length, equals(2));
    expect(container.read(cartSummaryProvider).subtotal, equals(Decimal.fromInt(101))); // 37 + 64 = 101
  });

  // ──────────────────────────────────────────────────────────────────────────
  // 3. GUEST ADD & GUEST BUY PRESERVATION FLOW (UNAUTHENTICATED)
  // ──────────────────────────────────────────────────────────────────────────
  testWidgets('Phase 7.1 — Guest BUY: Adds item and routes to Cart Screen', (tester) async {
    final container = ProviderContainer(
      overrides: [
        isUserAuthenticatedProvider.overrideWithValue(false), // Unauthenticated Guest
      ],
    );

    final testRouter = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => Scaffold(body: ServiceCard(service: beetroot)),
        ),
        GoRoute(
          path: AppRoutes.cart,
          builder: (context, state) => const Scaffold(body: Text('Cart Screen Rendered')),
        ),
      ],
    );

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(
          routerConfig: testRouter,
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // Action: Tap BUY as Guest
    await tester.tap(find.text('BUY'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // Verify item is in cart and Cart Screen is rendered
    expect(container.read(cartProvider).length, equals(1));
    expect(container.read(cartProvider).first.service.id, equals(228));
    expect(find.text('Cart Screen Rendered'), findsOneWidget);
  });

  // ──────────────────────────────────────────────────────────────────────────
  // 4. NORMAL SERVICE BOOKING FLOW & 20% ADVANCE
  // ──────────────────────────────────────────────────────────────────────────
  testWidgets('Phase 7.1 — Normal Service: View Details & ₹149 Floor Advance calculation', (tester) async {
    final container = ProviderContainer();
    container.read(cartProvider.notifier).clearCart();
    container.read(cartProvider.notifier).addService(acService);

    final summary = container.read(cartSummaryProvider);
    expect(summary.isGroceryCart, isFalse);
    expect(summary.advancePayable, equals(Decimal.parse('149.00')));
    expect(summary.balancePayable > Decimal.zero, isTrue);
  });

  // ──────────────────────────────────────────────────────────────────────────
  // 5. MY BOOKINGS ENVELOPE SAFETY
  // ──────────────────────────────────────────────────────────────────────────
  testWidgets('Phase 7.1 — My Bookings: Safe envelope parsing and zero Map->List error', (tester) async {
    final rawBookingMap = {
      'id': 8841,
      'request_id': 'CAL-8841',
      'status': 'confirmed',
      'total_amount': '499.00',
      'scheduled_date': '2026-08-25',
      'scheduled_time_slot': '10:00 AM - 12:00 PM',
      'available_actions': ['cancel', 'reschedule', 'pay_advance', 'track'],
      'address': {
        'id': 107,
        'address_line1': 'No. 42, Sipcot Phase 1',
        'city': 'Hosur',
        'postal_code': '635126',
      },
    };

    final booking = Booking.fromJson(rawBookingMap);
    expect(booking.id, equals(8841));
    expect(booking.canCancel, isTrue);
    expect(booking.canReschedule, isTrue);
    expect(booking.canTrack, isTrue);
    expect(booking.address?.city, equals('Hosur'));
  });
}
