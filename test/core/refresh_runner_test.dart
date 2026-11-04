import 'dart:async';

import 'package:calservices_customer/core/refresh/refresh_runner.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<BuildContext> _context(WidgetTester tester) async {
  late BuildContext ctx;
  await tester.pumpWidget(MaterialApp(home: Builder(builder: (c) {
    ctx = c;
    return const SizedBox();
  })));
  return ctx;
}

void main() {
  group('RefreshRunner', () {
    testWidgets('true when every job succeeds', (tester) async {
      final ctx = await _context(tester);
      final ok = await tester.runAsync(() => RefreshRunner.run(ctx, [() async {}, () async {}], quiet: true));
      expect(ok, isTrue);
    });

    testWidgets('false when one job fails, and the others still run', (tester) async {
      final ctx = await _context(tester);
      var otherRan = false;
      final ok = await tester.runAsync(() => RefreshRunner.run(
            ctx,
            [() async => throw StateError('boom'), () async => otherRan = true],
            quiet: true,
          ));
      expect(ok, isFalse);
      expect(otherRan, isTrue);
    });

    testWidgets('gives up waiting after the limit instead of hanging', (tester) async {
      final ctx = await _context(tester);
      final never = Completer<void>();
      final watch = Stopwatch()..start();
      final ok = await tester.runAsync(() => RefreshRunner.run(
            ctx,
            [() => never.future],
            limit: const Duration(milliseconds: 60),
            quiet: true,
          ));
      expect(ok, isFalse);
      expect(watch.elapsedMilliseconds, lessThan(2000));
    });
  });

  group('ResumeRefresh', () {
    test('refreshes only after the app was away for long enough', () {
      var now = DateTime(2026, 1, 1, 10);
      var calls = 0;
      final r = ResumeRefresh(onStale: () => calls++, after: const Duration(minutes: 5), clock: () => now);

      r.didChangeAppLifecycleState(AppLifecycleState.paused);
      now = now.add(const Duration(minutes: 1));
      r.didChangeAppLifecycleState(AppLifecycleState.resumed);
      expect(calls, 0, reason: 'a quick app switch must not reload');

      r.didChangeAppLifecycleState(AppLifecycleState.paused);
      now = now.add(const Duration(minutes: 6));
      r.didChangeAppLifecycleState(AppLifecycleState.resumed);
      expect(calls, 1);

      r.didChangeAppLifecycleState(AppLifecycleState.resumed);
      expect(calls, 1, reason: 'a resume without a pause does nothing');
    });
  });
}
