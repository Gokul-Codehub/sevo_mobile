import 'package:calservices_customer/features/booking/domain/booking_models.dart';
import 'package:calservices_customer/features/booking/domain/booking_status.dart';
import 'package:calservices_customer/features/booking/domain/grocery_fee_split.dart';
import 'package:calservices_customer/features/booking/presentation/widgets/grocery_order_status_view.dart';
import 'package:calservices_customer/features/catalog/data/marketplace_catalog_repository.dart';
import 'package:calservices_customer/shared/theme/app_theme.dart';
import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Booking order(String status, {String? otp, bool cancel = false, String payment = 'COD', String paymentStatus = 'pending'}) => Booking(
      id: 8,
      requestId: 'SEVO-VG-008',
      status: status,
      scheduledDate: '2026-11-02',
      scheduledTimeSlot: '2:00 PM - 3:00 PM',
      totalAmount: Decimal.parse('80.92'),
      advanceAmount: Decimal.zero,
      balanceAmount: Decimal.zero,
      paymentMethod: payment,
      paymentStatus: paymentStatus,
      startOtp: otp,
      createdAt: DateTime.utc(2026, 11, 2, 7, 18),
      availableActions: cancel ? const ['cancel'] : const [],
      items: [
        CartItem(
          service: MarketplaceProduct.fromJson({'id': 5, 'title': 'Butter Biscuits', 'selling_price': '40.00'}).toServiceItem(),
          quantity: 2,
        ),
      ],
    );

Future<void> pump(WidgetTester tester, Booking b, {VoidCallback? onCancel, VoidCallback? onInvoice, List<FeeLine>? feeLines}) async {
  tester.view.physicalSize = const Size(800, 3600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    theme: AppTheme.light, // the real theme: its buttons default to full width, which broke the page on device
    home: Scaffold(
      body: GroceryOrderStatusView(
        booking: b,
        status: b.status,
        itemThumb: (_) => const SizedBox(),
        onHelp: () {},
        onCancel: onCancel,
        onInvoice: onInvoice,
        feeLines: feeLines,
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  test('booking stages map onto the five grocery steps', () {
    expect(groceryStepFor(BookingStage.requested), 0);
    expect(groceryStepFor(BookingStage.confirmed), 1);
    expect(groceryStepFor(BookingStage.assigned), 2);
    expect(groceryStepFor(BookingStage.onTheWay), 3);
    expect(groceryStepFor(BookingStage.inProgress), 3);
    expect(groceryStepFor(BookingStage.completed), 4);
    expect(groceryStepFor(BookingStage.cancelled), isNull);
    expect(groceryStepFor(BookingStage.ended), isNull);
  });

  testWidgets('confirmed order: progress, timeline, items, address/payment, help; no map or technician wording', (tester) async {
    await pump(tester, order('confirmed'));
    expect(find.text('Order SEVO-VG-008'), findsOneWidget);
    expect(find.text('Delivery Progress'), findsNothing); // one tracker only: the vertical timeline
    expect(find.textContaining('Estimated delivery'), findsOneWidget);
    expect(find.text('Order Timeline'), findsOneWidget);
    expect(find.text('Current'), findsOneWidget);
    expect(find.text('Order Confirmed'), findsWidgets);
    expect(find.text('Butter Biscuits'), findsOneWidget);
    expect(find.text('Qty: 2'), findsOneWidget);
    // 2 x 40 of items inside an 80.92 order: the rest is fees / taxes, shown as one line, and the sum adds up.
    expect(find.text('Items total (2 items)'), findsOneWidget);
    expect(find.text('₹80'), findsWidgets);
    expect(find.text('Delivery, handling fees & taxes'), findsOneWidget);
    expect(find.text('₹0.92'), findsOneWidget);
    expect(find.text('Order total'), findsOneWidget);
    expect(find.text('Cash on Delivery'), findsOneWidget);
    expect(find.text('Payment pending'), findsOneWidget);
    expect(find.text('Need help with your order?'), findsOneWidget);
    expect(find.textContaining('Technician'), findsNothing);
    expect(find.textContaining('Track'), findsNothing);
    expect(find.textContaining('Share this code'), findsNothing);
  });

  testWidgets('out for delivery shows the delivery code', (tester) async {
    await pump(tester, order('on_the_way', otp: '4821'));
    expect(find.text('4821'), findsOneWidget);
    expect(find.textContaining('Share this code'), findsOneWidget);
  });

  testWidgets('the code is not shown before the order is on the way', (tester) async {
    await pump(tester, order('confirmed', otp: '4821'));
    expect(find.text('4821'), findsNothing);
  });

  testWidgets('delivered: everything ticked, no Current tag, invoice offered', (tester) async {
    var invoice = 0;
    await pump(tester, order('completed', paymentStatus: 'paid'), onInvoice: () => invoice++);
    expect(find.text('Current'), findsNothing);
    expect(find.text('Paid'), findsOneWidget);
    await tester.tap(find.text('Invoice'));
    expect(invoice, 1);
  });

  testWidgets('cancelled: a cancelled note instead of progress; no invoice button', (tester) async {
    await pump(tester, order('cancelled'), onInvoice: () {});
    expect(find.textContaining('was cancelled'), findsOneWidget);
    expect(find.text('Delivery Progress'), findsNothing);
    expect(find.text('Order Timeline'), findsNothing);
    expect(find.text('Invoice'), findsNothing);
  });

  testWidgets('an order cheaper than its items shows a discount, not a fee', (tester) async {
    final b = Booking(
      id: 9,
      requestId: 'SEVO-VG-009',
      status: 'confirmed',
      scheduledDate: '2026-11-02',
      scheduledTimeSlot: '2:00 PM - 3:00 PM',
      totalAmount: Decimal.parse('70'),
      advanceAmount: Decimal.zero,
      balanceAmount: Decimal.zero,
      items: order('confirmed').items,
    );
    await pump(tester, b);
    expect(find.text('Discount applied'), findsOneWidget);
    expect(find.text('-₹10'), findsOneWidget);
    expect(find.text('Delivery, handling fees & taxes'), findsNothing);
  });

  testWidgets('fees that could be rebuilt are listed one by one, once for the whole order', (tester) async {
    await pump(tester, order('confirmed'), feeLines: [FeeLine('Delivery fee', Decimal.parse('30')), FeeLine('Handling & packaging fee', Decimal.parse('6.92'))]);
    expect(find.text('Delivery fee'), findsOneWidget);
    expect(find.text('Handling & packaging fee'), findsOneWidget);
    expect(find.text('Delivery, handling fees & taxes'), findsNothing);
  });

  testWidgets('Cancel order appears only when the server allows it', (tester) async {
    await pump(tester, order('confirmed', cancel: true), onCancel: () {});
    expect(find.text('Cancel order'), findsOneWidget);
    await pump(tester, order('confirmed'));
    expect(find.text('Cancel order'), findsNothing);
  });
}
