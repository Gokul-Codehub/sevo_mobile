import 'package:calservices_customer/features/booking/domain/booking_status.dart';
import 'package:calservices_customer/features/booking/presentation/widgets/grocery_order_status_view.dart';
import 'package:calservices_customer/shared/widgets/common_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a grocery order shows its timeline step, never service wording', () {
    expect(groceryStatusLabel('new_request'), 'Order Placed');
    expect(groceryStatusLabel('confirmed'), 'Order Confirmed');
    expect(groceryStatusLabel('assigned'), 'Packed');
    expect(groceryStatusLabel('on_the_way'), 'Out for Delivery');
    expect(groceryStatusLabel('arrived'), 'Out for Delivery');
    expect(groceryStatusLabel('in_progress'), 'Out for Delivery');
    expect(groceryStatusLabel('completed'), 'Delivered');
    for (final s in ['new_request', 'confirmed', 'assigned', 'on_the_way', 'completed']) {
      expect(groceryStatusLabel(s).toLowerCase(), isNot(contains('technician')), reason: s);
    }
  });

  test('payment and ended states keep their own wording', () {
    expect(groceryStatusLabel('pending_payment'), bookingStatusLabel('pending_payment'));
    expect(groceryStatusLabel('waiting_for_payment'), bookingStatusLabel('waiting_for_payment'));
    expect(groceryStatusLabel('cancelled'), bookingStatusLabel('cancelled'));
  });

  test('the pill and the detail page use the same names for the same stage', () {
    final byStep = {
      'new_request': 0,
      'confirmed': 1,
      'assigned': 2,
      'on_the_way': 3,
      'completed': 4,
    };
    byStep.forEach((status, step) => expect(groceryStatusLabel(status), kGrocerySteps[step].title, reason: status));
  });

  testWidgets('the chip shows the grocery label only when asked', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Column(children: [
        BookingStatusChip(status: 'assigned', grocery: true),
        BookingStatusChip(status: 'assigned'),
      ]),
    ));
    expect(find.text('Packed'), findsOneWidget);
    expect(find.text(bookingStatusLabel('assigned')), findsOneWidget);
  });
}
