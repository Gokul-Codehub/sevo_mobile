import 'package:calservices_customer/core/errors/api_error.dart';
import 'package:calservices_customer/core/network/api_client.dart';
import 'package:calservices_customer/features/my_payments/data/my_payments_repository.dart';
import 'package:calservices_customer/features/my_payments/presentation/my_payments_screens.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

class _Repo extends MyPaymentsRepository {
  _Repo() : super(api: ApiClient.withDio(Dio()));
  Result<PaymentHistory> historyResult = Success(PaymentHistory(
    records: [
      PaymentRecord(id: 'service-1', kind: PaymentKind.service, title: 'AC Service', reference: 'SEVO-12', amount: 499, outcome: PaymentOutcome.paid,
          statusLabel: 'Paid', method: 'Online', createdAt: DateTime(2026, 10, 30), bookingId: 12),
      PaymentRecord(id: 'grocery-2', kind: PaymentKind.grocery, title: 'Grocery order', reference: '', amount: 250.5, outcome: PaymentOutcome.failed,
          statusLabel: 'Failed', method: 'Online', createdAt: DateTime(2026, 10, 29)),
      PaymentRecord(id: 'service-3', kind: PaymentKind.service, title: 'Plumbing', reference: 'SEVO-9', amount: 300, outcome: PaymentOutcome.refunded,
          statusLabel: 'Refunded', method: 'Online', createdAt: DateTime(2026, 10, 20), bookingId: 9),
    ],
    totalPaid: 499,
    totalRefunded: 300,
  ));
  Result<List<RefundRecord>> refundResult = const Success([]);
  @override
  Future<Result<PaymentHistory>> history({String? status}) async => historyResult;
  @override
  Future<Result<List<RefundRecord>>> refunds() async => refundResult;
}

Widget app(_Repo repo, Widget screen) => ProviderScope(
      overrides: [myPaymentsRepositoryProvider.overrideWithValue(repo)],
      child: MaterialApp.router(
        routerConfig: GoRouter(routes: [
          GoRoute(path: '/', builder: (_, __) => screen),
          GoRoute(path: '/bookings/:id', builder: (_, s) => Scaffold(body: Text('BOOKING ${s.pathParameters['id']}'))),
        ]),
      ),
    );

RefundRecord refund(String status, {double requested = 500, double? approved}) => RefundRecord.tryParse({
      'id': 1, 'refund_id': 'RF-1', 'booking_id': 12, 'booking_request_id': 'SEVO-12', 'service_name': 'AC Service',
      'paid_amount': '500', 'requested_amount': '$requested', 'approved_amount': approved?.toString(), 'status': status,
      'status_display': status, 'created_at': '2026-10-30T10:00:00Z',
    })!;

void main() {
  group('parsing', () {
    test('refund statuses map to the customer journey', () {
      expect(refund('PENDING').stage, RefundStage.underReview);
      expect(refund('INFO_REQUESTED').stage, RefundStage.needsInfo);
      expect(refund('APPROVED_FULL').stage, RefundStage.approved);
      expect(refund('APPROVED_PARTIAL').stage, RefundStage.approved);
      expect(refund('SENT_TO_FINANCE').stage, RefundStage.processing);
      expect(refund('COMPLETED').stage, RefundStage.refunded);
      expect(refund('REJECTED').stage, RefundStage.rejected);
    });

    test('the refund amount is the approved one once there is one', () {
      expect(refund('PENDING', requested: 500).amount, 500);
      expect(refund('APPROVED_PARTIAL', requested: 500, approved: 350).amount, 350);
    });

    test('junk rows are skipped', () {
      expect(PaymentRecord.tryParse('x'), isNull);
      expect(PaymentRecord.tryParse({'id': 'a'}), isNull);
      expect(RefundRecord.tryParse({'id': 'x'}), isNull);
    });

    test('rupee formatting drops .00 only', () {
      expect(rupees(499), '₹499');
      expect(rupees(250.5), '₹250.50');
    });
  });

  group('PaymentHistoryScreen', () {
    testWidgets('shows totals and every payment with its outcome', (tester) async {
      await tester.pumpWidget(app(_Repo(), const PaymentHistoryScreen()));
      await tester.pumpAndSettle();
      expect(find.text('Total paid'), findsOneWidget);
      expect(find.text('₹499'), findsNWidgets(2)); // total + the AC payment
      expect(find.text('AC Service'), findsOneWidget);
      expect(find.text('Grocery order'), findsOneWidget);
    });

    testWidgets('filter chips narrow the list', (tester) async {
      await tester.pumpWidget(app(_Repo(), const PaymentHistoryScreen()));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ChoiceChip, 'Refunded'));
      await tester.pumpAndSettle();
      expect(find.text('Plumbing'), findsOneWidget);
      expect(find.text('AC Service'), findsNothing);
    });

    testWidgets('tapping a service payment opens its booking', (tester) async {
      await tester.pumpWidget(app(_Repo(), const PaymentHistoryScreen()));
      await tester.pumpAndSettle();
      await tester.tap(find.text('AC Service'));
      await tester.pumpAndSettle();
      expect(find.text('BOOKING 12'), findsOneWidget);
    });

    testWidgets('empty history explains itself', (tester) async {
      final repo = _Repo()..historyResult = const Success(PaymentHistory(records: [], totalPaid: 0, totalRefunded: 0));
      await tester.pumpWidget(app(repo, const PaymentHistoryScreen()));
      await tester.pumpAndSettle();
      expect(find.text('No payments here yet'), findsOneWidget);
    });

    testWidgets('a load failure shows a retry, not a blank page', (tester) async {
      final repo = _Repo()..historyResult = const Failure(NetworkError());
      await tester.pumpWidget(app(repo, const PaymentHistoryScreen()));
      await tester.pumpAndSettle();
      expect(find.text('Try again'), findsOneWidget);
    });
  });

  group('RefundsScreen', () {
    testWidgets('empty state', (tester) async {
      await tester.pumpWidget(app(_Repo(), const RefundsScreen()));
      await tester.pumpAndSettle();
      expect(find.text('No refunds'), findsOneWidget);
    });

    testWidgets('shows the steps, the status message and links to the booking', (tester) async {
      final repo = _Repo()..refundResult = Success([refund('SENT_TO_FINANCE', approved: 500)]);
      await tester.pumpWidget(app(repo, const RefundsScreen()));
      await tester.pumpAndSettle();
      for (final step in ['Requested', 'Under review', 'Approved', 'Processing', 'Refunded']) {
        expect(find.text(step), findsOneWidget);
      }
      expect(find.textContaining('being processed by our finance team'), findsOneWidget);
      await tester.tap(find.text('View booking'));
      await tester.pumpAndSettle();
      expect(find.text('BOOKING 12'), findsOneWidget);
    });

    testWidgets('a rejected refund is explained, and a partial approval states both amounts', (tester) async {
      final repo = _Repo()..refundResult = Success([refund('REJECTED'), refund('APPROVED_PARTIAL', requested: 500, approved: 350)]);
      await tester.pumpWidget(app(repo, const RefundsScreen()));
      await tester.pumpAndSettle();
      expect(find.textContaining('not approved'), findsOneWidget);
      expect(find.textContaining('You asked for ₹500; approved ₹350.'), findsOneWidget);
    });
  });
}
