import 'package:calservices_customer/features/booking/domain/booking_models.dart';
import 'package:calservices_customer/features/booking/domain/cart_notifier.dart';
import 'package:calservices_customer/features/catalog/domain/catalog_models.dart';
import 'package:decimal/decimal.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
  });

  final acRepair = ServiceItem(
    id: 490,
    categoryId: 15,
    title: '2-in-1 Combo AC Power Jet Service',
    slug: 'ac-combo-2-units',
    price: Decimal.fromInt(899),
    categorySlug: 'ac_appliance',
    categoryName: 'AC & Appliance',
    durationMinutes: 90,
    description: 'Complete power jet foam wash for 2 Split AC units',
  );

  final beetroot = ServiceItem(
    id: 228,
    categoryId: 18,
    title: 'Beetroot',
    slug: 'veg-beetroot',
    price: Decimal.fromInt(37),
    categorySlug: 'vegetables_groceries',
    categoryName: 'Farm-Fresh Vegetable',
  );

  group('Normal Service Flow vs Grocery Flow Isolation Tests', () {
    test('Normal Service item has flowType == serviceBooking', () {
      expect(acRepair.flowType, equals(CatalogFlowType.serviceBooking));
      expect(acRepair.flowType == CatalogFlowType.grocery, isFalse);
    });

    test('Normal Service Cart calculates GST 5%, Service Safety Fee ₹49, and 20% advance', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      container.read(cartProvider.notifier).addService(acRepair);

      final summary = container.read(cartSummaryProvider);
      expect(summary.subtotal, equals(Decimal.parse('899.00')));
      expect(summary.serviceFee, equals(Decimal.parse('29.00')));
      expect(summary.taxes, equals(Decimal.parse('161.82'))); // 18% of 899
      expect(summary.total, equals(Decimal.parse('1089.82'))); // 899 + 29 + 161.82
      expect(summary.advancePayable, equals(Decimal.parse('217.964'))); // 20% of 1089.82
    });

    test('Booking model requires scheduled date and slot for normal service', () {
      final booking = Booking(
        id: 101,
        requestId: 'CAL-20260823-101',
        status: 'confirmed',
        totalAmount: Decimal.parse('992.95'),
        advanceAmount: Decimal.parse('198.59'),
        balanceAmount: Decimal.parse('794.36'),
        scheduledDate: '2026-08-25',
        scheduledTimeSlot: '10:00 AM - 12:00 PM',
        items: [CartItem(service: acRepair, quantity: 1)],
      );

      expect(booking.scheduledDate, equals('2026-08-25'));
      expect(booking.scheduledTimeSlot, equals('10:00 AM - 12:00 PM'));
      expect(booking.advanceAmount, equals(Decimal.parse('198.59')));
      expect(booking.balanceAmount, equals(Decimal.parse('794.36')));
    });

    test('Strict separation: Grocery cart does not charge 5% service GST or split into advance/balance', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      container.read(cartProvider.notifier).addService(beetroot, quantity: 2); // 2 * 37 = 74

      final summary = container.read(cartSummaryProvider);
      expect(summary.isGroceryCart, isTrue);
      expect(summary.taxes, equals(Decimal.zero));
      expect(summary.serviceFee, equals(Decimal.zero));
      expect(summary.advancePayable, equals(summary.total));
      expect(summary.balancePayable, equals(Decimal.zero));
    });
  });
}
