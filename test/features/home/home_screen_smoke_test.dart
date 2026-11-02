import 'package:calservices_customer/features/home/presentation/screens/home_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// The real Home screen must build: it reads providers with ref.watch / ref.listen, which Riverpod only allows inside
/// the screen's own build (a wrapper that built the content elsewhere crashed the app with a red screen).
void main() {
  testWidgets('Home builds without a Riverpod build-context error', (tester) async {
    tester.view.physicalSize = const Size(900, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const ProviderScope(child: MaterialApp(home: HomeScreen())));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.takeException(), isNull);
    // with nothing loaded the full-screen loader is what shows
    expect(find.text('Everything you need, delivered at your doorstep'), findsWidgets);
    await tester.pumpWidget(const SizedBox());
  });
}
