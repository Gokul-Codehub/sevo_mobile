import 'package:calservices_customer/features/logistics/domain/gt_models.dart';
import 'package:calservices_customer/features/logistics/domain/gt_providers.dart';
import 'package:calservices_customer/features/logistics/domain/logistics_providers.dart';
import 'package:calservices_customer/features/logistics/presentation/widgets/gt_insurance_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host(List<Override> overrides, {double? declared = 10000}) => ProviderScope(
      overrides: overrides,
      child: MaterialApp(home: Scaffold(body: SingleChildScrollView(child: GtInsuranceSection(declaredValue: declared)))),
    );

const _notOffered = InsuranceTerms(offered: false, reason: 'terms_incomplete');
const _offered = InsuranceTerms(offered: true);
const _terms = InsuranceTerms(
  offered: true,
  premium: 150,
  liabilityCap: 10000,
  ratePercent: 1.5,
  exclusions: 'No cash or jewellery',
  consentText: 'I accept the insurer terms',
  policyReference: 'POL-2026-1',
);

void main() {
  testWidgets('what the live server says today (terms not configured): the customer is told, with no switch', (tester) async {
    await tester.pumpWidget(_host([insuranceAvailabilityProvider.overrideWith((ref, k) async => _notOffered)]));
    await tester.pumpAndSettle();
    expect(find.textContaining("can't be sold for this service yet"), findsOneWidget);
    expect(find.textContaining('will not be insured'), findsOneWidget);
    expect(find.byType(Switch), findsNothing);
  });

  testWidgets('once the admin configures terms: the switch, the premium, exclusions and the consent box all appear', (tester) async {
    await tester.pumpWidget(_host([
      insuranceAvailabilityProvider.overrideWith((ref, k) async => _offered),
      insuranceTermsProvider.overrideWith((ref, k) async => _terms),
      gtPaymentMethodProvider.overrideWith((ref) => 'online'),
    ]));
    await tester.pumpAndSettle();
    expect(find.text('Add transit insurance for your goods'), findsOneWidget);

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(find.textContaining('Premium ₹150'), findsOneWidget);
    expect(find.textContaining('covers up to ₹10000'), findsOneWidget);
    expect(find.text('Policy: POL-2026-1'), findsOneWidget);
    expect(find.text('No cash or jewellery'), findsOneWidget);
    expect(find.text('I accept the insurer terms'), findsOneWidget);
    expect(find.textContaining('Tick the box to add cover'), findsOneWidget);

    await tester.tap(find.byType(Checkbox));
    await tester.pumpAndSettle();
    expect(find.textContaining('Tick the box to add cover'), findsNothing);
  });

  testWidgets('with cash payment the switch explains that insurance needs online or wallet payment', (tester) async {
    await tester.pumpWidget(_host([
      insuranceAvailabilityProvider.overrideWith((ref, k) async => _offered),
      gtPaymentMethodProvider.overrideWith((ref) => 'cod'),
    ]));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(find.textContaining('online or wallet payment'), findsOneWidget);
  });
}
