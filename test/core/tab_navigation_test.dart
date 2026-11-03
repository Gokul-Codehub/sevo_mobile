import 'package:calservices_customer/core/navigation/safe_back.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

Widget _page(String label, {List<(String, VoidCallback Function(BuildContext))> buttons = const []}) => Builder(
      builder: (context) => Scaffold(
        body: Column(children: [
          Text(label),
          for (final b in buttons) TextButton(key: Key(b.$1), onPressed: b.$2(context), child: Text(b.$1)),
        ]),
      ),
    );

GoRouter _router() => GoRouter(
      initialLocation: '/',
      routes: [
        ShellRoute(
          builder: (context, state, child) => Scaffold(body: child),
          routes: [
            GoRoute(
              path: '/',
              builder: (_, __) => _page('HOME', buttons: [
                ('toCategory', (c) => () => c.push('/category')),
                ('toBookings', (c) => () => c.openTab('/bookings')),
              ]),
            ),
            GoRoute(
              path: '/category',
              builder: (_, __) => _page('CATEGORY', buttons: [
                ('toService', (c) => () => c.push('/service')),
                ('toCart', (c) => () => c.openTab('/cart')),
              ]),
            ),
            GoRoute(
              path: '/service',
              builder: (_, __) => _page('SERVICE', buttons: [
                ('toCart', (c) => () => c.openTab('/cart')),
                ('toBookings', (c) => () => c.openTab('/bookings')),
              ]),
            ),
            GoRoute(
              path: '/cart',
              builder: (_, __) => _page('CART', buttons: [('toProfile', (c) => () => c.openTab('/profile'))]),
            ),
            GoRoute(
              path: '/bookings',
              builder: (_, __) => _page('BOOKINGS', buttons: [('toCart', (c) => () => c.openTab('/cart'))]),
            ),
            GoRoute(path: '/profile', builder: (_, __) => _page('PROFILE')),
          ],
        ),
      ],
    );

Future<GoRouter> _start(WidgetTester tester) async {
  final router = _router();
  await tester.pumpWidget(MaterialApp.router(routerConfig: router));
  await tester.pumpAndSettle();
  return router;
}

Future<void> _tap(WidgetTester tester, String key) async {
  await tester.tap(find.byKey(Key(key)));
  await tester.pumpAndSettle();
}

Future<void> _back(WidgetTester tester, GoRouter router) async {
  router.pop();
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('back retraces the path: Home > Category > Service > Cart', (tester) async {
    final router = await _start(tester);
    await _tap(tester, 'toCategory');
    await _tap(tester, 'toService');
    await _tap(tester, 'toCart');
    expect(find.text('CART'), findsOneWidget);

    await _back(tester, router);
    expect(find.text('SERVICE'), findsOneWidget);
    await _back(tester, router);
    expect(find.text('CATEGORY'), findsOneWidget);
    await _back(tester, router);
    expect(find.text('HOME'), findsOneWidget);
    expect(router.canPop(), isFalse);
  });

  testWidgets('hopping between tabs does not pile up pages', (tester) async {
    final router = await _start(tester);
    await _tap(tester, 'toBookings'); // Home > Bookings: replaces
    await _tap(tester, 'toCart'); // Bookings > Cart: replaces
    await _tap(tester, 'toProfile'); // Cart > Profile: replaces
    expect(find.text('PROFILE'), findsOneWidget);
    expect(router.canPop(), isFalse); // nothing underneath: the shell sends back to Home
  });

  testWidgets('a tab opened from a deep page goes back to that page, and tabs hopped after it replace each other', (tester) async {
    final router = await _start(tester);
    await _tap(tester, 'toCategory');
    await _tap(tester, 'toService');
    await _tap(tester, 'toBookings'); // pushed over Service
    await _tap(tester, 'toCart'); // Bookings is a tab page: replaced by Cart
    expect(find.text('CART'), findsOneWidget);

    await _back(tester, router);
    expect(find.text('SERVICE'), findsOneWidget); // not Bookings, not Home
    await _back(tester, router);
    expect(find.text('CATEGORY'), findsOneWidget);
  });

  testWidgets('opening the tab you are already on does nothing', (tester) async {
    final router = await _start(tester);
    await _tap(tester, 'toBookings');
    await _tap(tester, 'toCart');
    await _tap(tester, 'toProfile');
    expect(router.canPop(), isFalse);
  });
}
