import 'package:calservices_customer/features/auth/domain/auth_return.dart';
import 'package:calservices_customer/routing/app_router.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

/// A form with something typed in it, behind a login gate. Signing in must bring the customer back to it, with
/// the typed text still there.
class _Form extends ConsumerStatefulWidget {
  const _Form();
  @override
  ConsumerState<_Form> createState() => _FormState();
}

class _FormState extends ConsumerState<_Form> {
  final c = TextEditingController();
  @override
  Widget build(BuildContext context) => Scaffold(
        body: Column(children: [
          TextField(key: const Key('typed'), controller: c),
          TextButton(key: const Key('gate'), onPressed: () => requireLogin(context, ref), child: const Text('Book')),
        ]),
      );
}

class _Login extends ConsumerWidget {
  const _Login();
  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      Scaffold(body: TextButton(key: const Key('next'), onPressed: () => context.push('/login/verify'), child: const Text('Send code')));
}

class _Verify extends ConsumerWidget {
  const _Verify();
  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      Scaffold(body: TextButton(key: const Key('done'), onPressed: () => finishSignIn(context, ref), child: const Text('Verify')));
}

GoRouter _router(String initial) => GoRouter(
      navigatorKey: rootNavigatorKey,
      initialLocation: initial,
      routes: [
        GoRoute(path: '/', name: 'home', builder: (_, __) => const Scaffold(body: Text('HOME'))),
        GoRoute(path: '/form', name: 'form', builder: (_, __) => const _Form()),
        GoRoute(
          path: '/login',
          name: 'login',
          builder: (_, __) => const _Login(),
          routes: [GoRoute(path: 'verify', name: 'otp-verify', builder: (_, __) => const _Verify())],
        ),
      ],
    );

void main() {
  testWidgets('sign-in opened over a form returns to the same form, typed text intact', (tester) async {
    await tester.pumpWidget(ProviderScope(child: MaterialApp.router(routerConfig: _router('/form'))));
    await tester.enterText(find.byKey(const Key('typed')), 'my goods');
    await tester.tap(find.byKey(const Key('gate')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('next')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('done')), findsOneWidget);

    await tester.tap(find.byKey(const Key('done')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('typed')), findsOneWidget);
    expect(find.text('my goods'), findsOneWidget);
    expect(find.byKey(const Key('done')), findsNothing);
  });

  testWidgets('sign-in that was not opened over anything goes Home', (tester) async {
    await tester.pumpWidget(ProviderScope(child: MaterialApp.router(routerConfig: _router('/login'))));
    await tester.tap(find.byKey(const Key('next')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('done')));
    await tester.pumpAndSettle();
    expect(find.text('HOME'), findsOneWidget);
  });
}
