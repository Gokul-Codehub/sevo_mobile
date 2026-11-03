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
    id: 800000228,
    title: 'Beetroot',
    slug: 'veg-beetroot',
    price: Decimal.fromInt(37),
    durationMinutes: 8,
    categoryId: 18,
    categorySlug: 'vegetables_groceries',
    categoryName: 'Farm-Fresh Vegetables & Groceries',
  );

  final amla = ServiceItem(
    id: 800000244,
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

  // ──────────────────────────────────────────────────────────────────────────
  // 2. FARM-FRESH BUY & CONTINUE SHOPPING (AUTHENTICATED)
  // ──────────────────────────────────────────────────────────────────────────

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
    expect(container.read(cartProvider).first.service.id, equals(800000228));
    expect(find.text('Cart Screen Rendered'), findsOneWidget);
  });

  // ──────────────────────────────────────────────────────────────────────────
  // 4. NORMAL SERVICE BOOKING FLOW & 20% ADVANCE
  // ──────────────────────────────────────────────────────────────────────────

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
