import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:calservices_customer/features/auth/presentation/screens/splash_screen.dart';

void main() {
  testWidgets('SplashScreen renders Sevo splash card asset and loading indicator',
      (tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: SplashScreen(),
        ),
      ),
    );

    // Initial frame render
    await tester.pump();

    // Verify Image asset is present
    expect(find.byType(Image), findsOneWidget);

    // Verify CircularProgressIndicator is present
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    // Verify "LOADING YOUR SEVO" status text is rendered
    expect(find.text('LOADING YOUR SEVO'), findsOneWidget);

    // Pump timer to clean up
    await tester.pump(const Duration(milliseconds: 500));
  });
}
