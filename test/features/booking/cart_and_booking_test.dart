import 'package:calservices_customer/features/booking/domain/booking_models.dart';
import 'package:calservices_customer/features/booking/domain/cart_notifier.dart';
import 'package:calservices_customer/features/catalog/domain/catalog_models.dart';
import 'package:decimal/decimal.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Cart & Checkout Calculations', () {
    test('calculates empty cart correctly with zero amounts', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final summary = container.read(cartSummaryProvider);
      expect(summary.itemCount, 0);
      expect(summary.subtotal, Decimal.zero);
      expect(summary.total, Decimal.zero);
    });

    test('adds service item and computes fee + tax + 20% advance', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final service = ServiceItem(
        id: 1,
        title: 'AC Deep Cleaning',
        slug: 'ac-deep-cleaning',
        price: Decimal.parse('1000.00'),
      );

      container.read(cartProvider.notifier).addService(service);

      final summary = container.read(cartSummaryProvider);
      expect(summary.itemCount, 1);
      expect(summary.subtotal, Decimal.parse('1000.00'));
      expect(summary.serviceFee, Decimal.parse('49.00'));
      expect(summary.taxes, Decimal.parse('50.00')); // 5% GST of 1000
      expect(summary.total, Decimal.parse('1099.00'));

      // 20% of 1099.00 is 219.80 (which is > 149.00 min advance)
      expect(summary.advancePayable, Decimal.parse('219.80'));
      expect(summary.balancePayable, Decimal.parse('879.20'));
    });
  });

  group('Booking Available Actions State Machine', () {
    test('derives actions from server available_actions array correctly', () {
      final booking = Booking(
        id: 101,
        requestId: 'CAL-101',
        status: 'confirmed',
        scheduledDate: '2026-08-25',
        scheduledTimeSlot: '09:00 AM - 11:00 AM',
        totalAmount: Decimal.parse('599.00'),
        advanceAmount: Decimal.parse('149.00'),
        balanceAmount: Decimal.parse('450.00'),
        availableActions: const ['cancel', 'reschedule', 'track'],
      );

      expect(booking.canCancel, isTrue);
      expect(booking.canReschedule, isTrue);
      expect(booking.canTrack, isTrue);
      expect(booking.canPayBalance, isFalse);
      expect(booking.canRate, isFalse);
    });

    test('completed booking supports rating and balance settlement if available', () {
      final booking = Booking(
        id: 102,
        requestId: 'CAL-102',
        status: 'completed',
        scheduledDate: '2026-08-20',
        scheduledTimeSlot: '02:00 PM - 04:00 PM',
        totalAmount: Decimal.parse('599.00'),
        advanceAmount: Decimal.parse('149.00'),
        balanceAmount: Decimal.parse('450.00'),
        availableActions: const ['pay_balance', 'rate', 'feedback'],
      );

      expect(booking.canCancel, isFalse);
      expect(booking.canReschedule, isFalse);
      expect(booking.canPayBalance, isTrue);
      expect(booking.canRate, isTrue);
    });
  });
}
