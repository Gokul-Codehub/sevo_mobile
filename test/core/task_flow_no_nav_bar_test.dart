import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

/// Mirrors app_router.dart: browsing pages live in the shell (bottom bar), task flows open above it.
final _root = GlobalKey<NavigatorState>();

GoRouter _router(String initial) => GoRouter(
      navigatorKey: _root,
      initialLocation: initial,
      routes: [
        GoRoute(path: '/onboarding', builder: (c, s) => _Page('ONBOARDING', actions: {'pick': () => c.push('/addresses?select=true')})),
        ShellRoute(
          builder: (context, state, child) => Scaffold(body: child, bottomNavigationBar: const SizedBox(key: Key('nav-bar'), height: 56)),
          routes: [
            GoRoute(path: '/', builder: (c, s) => _Page('HOME', actions: {'category': () => c.push('/category'), 'address': () => c.push('/addresses')})),
            GoRoute(path: '/category', builder: (c, s) => _Page('CATEGORY', actions: {'book': () => c.pushReplacement('/booking')})),
          ],
        ),
        // Task flows: top-level, next to the shell (go_router only allows leaving the shell this way).
        GoRoute(path: '/addresses', builder: (c, s) => _Page('ADDRESSES', actions: {'add': () => c.push('/addresses/add')})),
        GoRoute(path: '/addresses/add', builder: (c, s) => _Page('ADD-ADDRESS')),
        GoRoute(path: '/booking', builder: (c, s) => _Page('BOOKING')),
      ],
    );

class _Page extends StatelessWidget {
  const _Page(this.label, {this.actions = const {}});
  final String label;
  final Map<String, VoidCallback> actions;

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Column(children: [
          Text(label),
          for (final e in actions.entries) TextButton(key: Key(e.key), onPressed: e.value, child: Text(e.key)),
        ]),
      );
}

Future<GoRouter> _start(WidgetTester tester, String initial) async {
  final r = _router(initial);
  await tester.pumpWidget(MaterialApp.router(routerConfig: r));
  await tester.pumpAndSettle();
  return r;
}

Future<void> _tap(WidgetTester tester, String key) async {
  await tester.tap(find.byKey(Key(key)));
  await tester.pumpAndSettle();
}

void main() {
  final navBar = find.byKey(const Key('nav-bar'));

  testWidgets('onboarding > enter location manually: no bottom bar over the location step', (tester) async {
    final r = await _start(tester, '/onboarding');
    expect(navBar, findsNothing);
    await _tap(tester, 'pick');
    expect(find.text('ADDRESSES'), findsOneWidget);
    expect(navBar, findsNothing); // the bug: this used to show the bar and let a tab tap abandon the flow

    await _tap(tester, 'add');
    expect(find.text('ADD-ADDRESS'), findsOneWidget);
    expect(navBar, findsNothing);

    r.pop();
    await tester.pumpAndSettle();
    expect(find.text('ADDRESSES'), findsOneWidget);
    r.pop();
    await tester.pumpAndSettle();
    expect(find.text('ONBOARDING'), findsOneWidget);
  });

  testWidgets('browsing keeps the bar; a task flow hides it and back returns to the browsing page', (tester) async {
    final r = await _start(tester, '/');
    expect(navBar, findsOneWidget);
    await _tap(tester, 'category');
    expect(navBar, findsOneWidget);

    await _tap(tester, 'book'); // pushReplacement from a shell page to a task flow
    expect(find.text('BOOKING'), findsOneWidget);
    expect(navBar, findsNothing);

    r.pop();
    await tester.pumpAndSettle();
    expect(find.text('HOME'), findsOneWidget); // the category page was replaced by the booking page
    expect(navBar, findsOneWidget);
  });

  testWidgets('address screens from Home hide the bar and back brings it back', (tester) async {
    final r = await _start(tester, '/');
    await _tap(tester, 'address');
    expect(navBar, findsNothing);
    r.pop();
    await tester.pumpAndSettle();
    expect(find.text('HOME'), findsOneWidget);
    expect(navBar, findsOneWidget);
  });
}
