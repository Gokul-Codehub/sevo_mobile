import 'package:calservices_customer/main.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('App smoke test — CalServicesApp renders with ProviderScope', (WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: CalServicesApp(),
      ),
    );
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.byType(CalServicesApp), findsOneWidget);
  });
}
