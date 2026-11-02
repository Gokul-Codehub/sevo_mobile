import 'package:calservices_customer/core/errors/api_error.dart';
import 'package:calservices_customer/core/errors/error_manager.dart';
import 'package:calservices_customer/shared/widgets/state_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ErrorManager.present', () {
    test('every error type gives a title and body, none leak internals', () {
      final errors = <Object?>[
        const NetworkError(), const UnauthorizedError(), const ForbiddenError(), const NotFoundError(), const ServerError(),
        const ParseError(), const UnknownError(), const ValidationError('x'),
        const ApiContractError(endpoint: '/api/x', expected: 'a', actual: 'b'),
        StateError('Bad state: secret detail'), null,
      ];
      for (final e in errors) {
        final m = ErrorManager.present(e);
        expect(m.title, isNotEmpty);
        expect(m.body, isNotEmpty);
        expect(m.body.contains('secret detail'), isFalse);
        expect(m.body.contains('/api/x'), isFalse);
      }
    });

    test('offline, session and not-found are classified', () {
      expect(ErrorManager.present(const NetworkError()).kind, UserMessageKind.offline);
      expect(ErrorManager.present(const UnauthorizedError()).kind, UserMessageKind.signIn);
      expect(ErrorManager.present(const NotFoundError()).retryable, isFalse);
      expect(ErrorManager.isRetryable(const NetworkError()), isTrue);
    });

    test('server business messages are shown, code-like text is not', () {
      expect(ErrorManager.present(const ValidationError('This slot is full. Please pick another.')).body, 'This slot is full. Please pick another.');
      final bad = ErrorManager.present(const ValidationError('Traceback (most recent call last): {"x": 1}'));
      expect(bad.body.contains('Traceback'), isFalse);
      final long = ErrorManager.present(ValidationError('a' * 500));
      expect(long.body.length, lessThan(100));
    });

    test('machine codes map to their own messages', () {
      expect(ErrorManager.present(const ValidationError('m', code: 'MAINTENANCE')).kind, UserMessageKind.maintenance);
      expect(ErrorManager.present(const ValidationError('Goods & Transport is paused', code: 'FEATURE_DISABLED')).kind, UserMessageKind.featureOff);
      expect(ErrorManager.present(const ValidationError('m', code: 'SESSION_REVOKED')).kind, UserMessageKind.signIn);
    });
  });

  group('shared state widgets', () {
    testWidgets('ErrorState shows the message and Retry re-runs', (tester) async {
      var retries = 0;
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: ErrorState.from(const NetworkError(), onRetry: () => retries++))));
      expect(find.text('No connection'), findsOneWidget);
      await tester.tap(find.text('Try again'));
      expect(retries, 1);
    });

    testWidgets('no Retry button when retrying cannot help', (tester) async {
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: ErrorState.from(const NotFoundError(), onRetry: () {}))));
      expect(find.text('Try again'), findsNothing);
    });

    testWidgets('EmptyState explains and offers the action', (tester) async {
      var tapped = 0;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: EmptyState(icon: Icons.event, title: 'No bookings yet', body: 'Book a service to see it here.', actionLabel: 'Browse services', onAction: () => tapped++)),
      ));
      await tester.tap(find.text('Browse services'));
      expect(tapped, 1);
      expect(find.text('No data'), findsNothing);
    });

    testWidgets('LoadingState shows nothing for the first 300 ms, then a skeleton', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: Scaffold(body: LoadingState())));
      expect(find.byType(ListView), findsNothing);
      await tester.pump(const Duration(milliseconds: 350));
      expect(find.byType(ListView), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('states render on a small phone without overflow', (tester) async {
      tester.view.physicalSize = const Size(320, 480);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: ErrorState.from(const ServerError(), onRetry: () {}))));
      expect(tester.takeException(), isNull);
    });
  });
}
