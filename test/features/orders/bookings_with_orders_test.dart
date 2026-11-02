import 'package:calservices_customer/features/auth/domain/auth_models.dart';
import 'package:calservices_customer/features/auth/domain/auth_notifier.dart';
import 'package:calservices_customer/features/booking/domain/booking_models.dart';
import 'package:calservices_customer/features/booking/domain/booking_providers.dart';
import 'package:calservices_customer/features/booking/presentation/screens/my_bookings_screen.dart';
import 'package:calservices_customer/features/orders/data/grocery_orders_repository.dart';
import 'package:calservices_customer/shared/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

GroceryOrder order(String number, String status, {String title = '2-Minute Masala Instant Noodles'}) => GroceryOrder.tryParse({
      'order_type': 'marketplace',
      'order_number': number,
      'status': status,
      'status_label': status,
      'total_amount': '88.00',
      'created_at': '2026-11-02T10:00:00Z',
      'delivery_slot': 'Immediate',
      'detail': {
        'seller_name': 'SevoGrocery',
        'items': [
          {'product_title': title, 'quantity': 2, 'unit_price_snapshot': '44.00', 'line_amount': '88.00'},
        ],
      },
    })!;

Future<void> pump(WidgetTester tester, List<GroceryOrder> orders) async {
  tester.view.physicalSize = const Size(800, 2200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      currentUserProvider.overrideWithValue(const UserProfile(id: 1, phone: '9876543210', name: 'Asha')),
      myBookingsProvider(null).overrideWith((ref) async => <Booking>[]),
      groceryOrdersProvider.overrideWith((ref) async => orders),
    ],
    child: MaterialApp.router(
      theme: AppTheme.light,
      routerConfig: GoRouter(routes: [
        GoRoute(path: '/', builder: (_, __) => const MyBookingsScreen()),
        GoRoute(path: '/grocery-orders/:n', builder: (_, s) => Scaffold(body: Text('detail ${s.pathParameters['n']}'))),
      ]),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('grocery orders are listed in My Bookings with their product, status and total', (tester) async {
    await pump(tester, [order('MKT00164', 'PACKING')]);
    expect(find.text('#MKT00164'), findsOneWidget);
    expect(find.text('GROCERY'), findsWidgets);
    expect(find.text('2-Minute Masala Instant Noodles'), findsOneWidget);
    expect(find.text('Seller is packing'), findsOneWidget);
    expect(find.text('₹88'), findsOneWidget);
    expect(find.text('Active (1)'), findsOneWidget);
  });

  testWidgets('tapping an order opens its tracking page', (tester) async {
    await pump(tester, [order('MKT00164', 'PACKING')]);
    await tester.tap(find.text('#MKT00164'));
    await tester.pumpAndSettle();
    expect(find.text('detail MKT00164'), findsOneWidget);
  });

  testWidgets('delivered and cancelled orders are under History, not Active', (tester) async {
    await pump(tester, [order('MKT1', 'DELIVERED'), order('MKT2', 'CANCELLED'), order('MKT3', 'CONFIRMED')]);
    expect(find.text('Active (1)'), findsOneWidget);
    expect(find.text('History (2)'), findsOneWidget);
    await tester.tap(find.textContaining('History'));
    await tester.pumpAndSettle();
    expect(find.text('#MKT1'), findsOneWidget);
    expect(find.text('#MKT2'), findsOneWidget);
    expect(find.text('#MKT3'), findsNothing);
  });

  testWidgets('the Services filter hides grocery orders; Groceries shows them', (tester) async {
    await pump(tester, [order('MKT00164', 'PACKING')]);
    await tester.tap(find.text('Services'));
    await tester.pumpAndSettle();
    expect(find.text('#MKT00164'), findsNothing);
    await tester.tap(find.text('Groceries'));
    await tester.pumpAndSettle();
    expect(find.text('#MKT00164'), findsOneWidget);
  });

  testWidgets('search finds an order by its number or product', (tester) async {
    await pump(tester, [order('MKT00164', 'PACKING'), order('MKT00200', 'PACKING', title: 'Iodized Salt')]);
    await tester.enterText(find.byType(TextField), 'salt');
    await tester.pumpAndSettle();
    expect(find.text('#MKT00200'), findsOneWidget);
    expect(find.text('#MKT00164'), findsNothing);
  });
}
