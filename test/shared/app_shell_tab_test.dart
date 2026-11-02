import 'package:calservices_customer/routing/app_router.dart';
import 'package:calservices_customer/shared/widgets/app_shell.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  int bookings() => appShellTabIndexForLocation(AppRoutes.myBookings);

  test('Bookings is not the Home tab', () {
    expect(bookings(), isNot(0));
    expect(appShellTabIndexForLocation('/'), 0);
  });

  test('a grocery order, and its return page, highlight Bookings - not Home', () {
    expect(appShellTabIndexForLocation('/grocery-orders/MKT00164'), bookings());
    expect(appShellTabIndexForLocation('/grocery-orders/MKT00164/return'), bookings());
    expect(appShellTabIndexForLocation('/grocery-orders'), bookings());
  });

  test('the existing tabs are unchanged', () {
    expect(appShellTabIndexForLocation('/bookings'), bookings());
    expect(appShellTabIndexForLocation('/bookings/42'), bookings());
    expect(appShellTabIndexForLocation(AppRoutes.cart), isNot(0));
    expect(appShellTabIndexForLocation(AppRoutes.profile), isNot(0));
  });

  test('a path that only starts like the order route is not an order page', () {
    expect(appShellTabIndexForLocation('/grocery-orders-archive'), isNot(bookings()));
  });
}
