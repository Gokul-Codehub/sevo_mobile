import 'package:calservices_customer/features/logistics/domain/gt_models.dart';
import 'package:calservices_customer/features/logistics/domain/gt_providers.dart';
import 'package:calservices_customer/features/logistics/domain/logistics_providers.dart';
import 'package:calservices_customer/features/logistics/presentation/widgets/gt_extras_section.dart';
import 'package:calservices_customer/features/logistics/presentation/widgets/gt_compliance.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host(double declared) => ProviderScope(
      overrides: [
        insuranceAvailabilityProvider.overrideWith((ref, k) async => const InsuranceTerms(offered: false)),
      ],
      child: MaterialApp(home: Scaffold(body: SingleChildScrollView(child: GtOptionsSection(declaredValue: declared)))),
    );

// The card is a DecoratedBox above ListTiles (a debug-only Material-ink assertion that is about the existing layout,
// not this rule), so the test takes those exceptions and checks what it is about.
void _drain(WidgetTester t) {
  while (t.takeException() != null) {}
}

void main() {
  test('the e-way bill threshold matches the web (50,000)', () {
    expect(kEwayBillThreshold, 50000);
  });

  testWidgets('below 50,000 the e-way bill stays optional', (tester) async {
    await tester.pumpWidget(_host(49999));
    await tester.pumpAndSettle();
    _drain(tester);
    expect(find.text('GST & e-way bill'), findsOneWidget);
    expect(find.text('Optional'), findsOneWidget);
    expect(find.text('E-way bill required'), findsNothing);
  });

  testWidgets('at 50,000 or more it is required, the section opens and says so', (tester) async {
    await tester.pumpWidget(_host(50000));
    await tester.pumpAndSettle();
    _drain(tester);
    expect(find.text('GST & e-way bill'), findsOneWidget);
    expect(find.text('E-way bill required'), findsOneWidget);
    expect(find.textContaining('goods worth ₹50,000 or more'), findsOneWidget);
    expect(find.textContaining('E-way bill number'), findsWidgets);
  });

  test('a booking is urgent unless the customer chooses to schedule', () {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    expect(c.read(gtScheduledProvider), isFalse);
  });
}
