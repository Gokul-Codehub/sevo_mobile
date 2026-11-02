import 'package:calservices_customer/core/errors/api_error.dart';
import 'package:calservices_customer/core/network/api_client.dart';
import 'package:calservices_customer/features/support/data/support_requests_repository.dart';
import 'package:calservices_customer/features/support/presentation/screens/support_requests_screens.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

Map<String, dynamic> json({int id = 7, String status = 'OPEN', bool reopen = false, bool escalate = false, List<Map<String, dynamic>>? messages}) => {
      'id': id, 'complaint_number': 'CMP-000$id', 'category': 'PAYMENT_ISSUE', 'category_display': 'Payment Issue',
      'description': 'I was charged twice', 'status': status, 'status_display': status, 'booking_id': 12, 'booking_request_id': 'SEVO-12',
      'created_at': '2026-10-30T10:00:00Z', 'updated_at': '2026-10-30T11:00:00Z', 'can_reopen': reopen, 'can_escalate': escalate,
      'messages': messages ?? [], 'timeline': [{'status': 'OPEN', 'status_display': 'Open', 'at': '2026-10-30T10:00:00Z'}],
    };

class _Repo extends SupportRequestsRepository {
  _Repo() : super(api: ApiClient.withDio(Dio()));
  Result<List<SupportRequest>> listResult = const Success([]);
  Result<SupportRequest> detailResult = Success(SupportRequest.tryParse(json())!);
  Result<SupportRequest> createResult = Success(SupportRequest.tryParse(json())!);
  final List<Map<String, Object?>> created = [];
  final List<String> replies = [];
  final List<String> actions = [];

  @override
  Future<Result<List<SupportRequest>>> list() async => listResult;
  @override
  Future<Result<SupportRequest>> detail(int id) async => detailResult;
  @override
  Future<Result<SupportRequest>> create({required String category, required String description, String? bookingId, List<XFile> photos = const []}) async {
    created.add({'category': category, 'description': description, 'booking': bookingId, 'photos': photos.length});
    return createResult;
  }

  @override
  Future<Result<bool>> reply(int id, String message) async {
    replies.add(message);
    return const Success(true);
  }

  @override
  Future<Result<SupportRequest>> reopen(int id) async {
    actions.add('reopen');
    return detailResult;
  }

  @override
  Future<Result<SupportRequest>> escalate(int id) async {
    actions.add('escalate');
    return detailResult;
  }
}

Widget app(_Repo repo, String location) => ProviderScope(
      overrides: [supportRequestsRepositoryProvider.overrideWithValue(repo)],
      child: MaterialApp.router(
        routerConfig: GoRouter(initialLocation: location, routes: [
          GoRoute(path: '/', builder: (_, __) => const Scaffold(body: Text('HOME'))),
          GoRoute(path: '/support/requests', builder: (_, __) => const SupportRequestsScreen()),
          GoRoute(
            path: '/support/new',
            builder: (_, s) => NewSupportRequestScreen(
              topic: s.uri.queryParameters['topic'],
              bookingId: s.uri.queryParameters['booking'],
              bookingRef: s.uri.queryParameters['ref'],
            ),
          ),
          GoRoute(path: '/support/tickets/:id', builder: (_, s) => SupportTicketScreen(id: int.parse(s.pathParameters['id']!))),
        ]),
      ),
    );

void tall(WidgetTester tester) {
  tester.view.physicalSize = const Size(800, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

void main() {
  group('parsing', () {
    test('stages from server statuses, and active vs finished', () {
      SupportRequest r(String s) => SupportRequest.tryParse(json(status: s))!;
      expect(r('OPEN').stage, TicketStage.open);
      expect(r('ASSIGNED').stage, TicketStage.inProgress);
      expect(r('UNDER_INVESTIGATION').stage, TicketStage.inProgress);
      expect(r('WAITING_CUSTOMER').stage, TicketStage.waitingOnYou);
      expect(r('RESOLVED').isActive, isFalse);
      expect(r('CLOSED').isActive, isFalse);
      expect(r('OPEN').isActive, isTrue);
    });

    test('messages, timeline and flags are parsed; junk is skipped', () {
      final req = SupportRequest.tryParse(json(reopen: true, messages: [
        {'id': 1, 'persona': 'ADMIN', 'message': 'Looking into it', 'created_at': '2026-10-30T12:00:00Z'},
        {'id': 2, 'persona': 'CUSTOMER', 'message': 'Thanks'},
        {'id': 3, 'persona': 'ADMIN', 'message': ''},
      ]))!;
      expect(req.messages.map((m) => m.fromCustomer), [false, true]);
      expect(req.timeline.single.label, 'Open');
      expect(req.canReopen, isTrue);
      expect(SupportRequest.tryParse('x'), isNull);
      expect(SupportRequest.tryParse({'id': 'no'}), isNull);
    });
  });

  group('list', () {
    testWidgets('empty state invites a first request', (tester) async {
      await tester.pumpWidget(app(_Repo(), '/support/requests'));
      await tester.pumpAndSettle();
      expect(find.text('No support requests yet'), findsOneWidget);
    });

    testWidgets('shows each request with a readable status and opens it', (tester) async {
      final repo = _Repo()
        ..listResult = Success([SupportRequest.tryParse(json())!, SupportRequest.tryParse(json(id: 8, status: 'RESOLVED'))!])
        ..detailResult = Success(SupportRequest.tryParse(json())!);
      await tester.pumpWidget(app(repo, '/support/requests'));
      await tester.pumpAndSettle();
      expect(find.text('Received'), findsOneWidget);
      expect(find.text('Resolved'), findsOneWidget);
      await tester.tap(find.text('Received'));
      await tester.pumpAndSettle();
      expect(find.text('I was charged twice'), findsOneWidget);
    });

    testWidgets('load failure shows a retry', (tester) async {
      final repo = _Repo()..listResult = const Failure(NetworkError());
      await tester.pumpWidget(app(repo, '/support/requests'));
      await tester.pumpAndSettle();
      expect(find.text('Try again'), findsOneWidget);
    });
  });

  group('new request', () {
    testWidgets('topic and booking are pre-filled from where the customer came from', (tester) async {
      tall(tester);
      await tester.pumpWidget(app(_Repo(), '/support/new?topic=payment&booking=12&ref=SEVO-12'));
      await tester.pumpAndSettle();
      expect(find.text('About booking SEVO-12'), findsOneWidget);
      final chip = tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Payment problem'));
      expect(chip.selected, isTrue);
    });

    testWidgets('submit is disabled until the description is long enough', (tester) async {
      tall(tester);
      await tester.pumpWidget(app(_Repo(), '/support/new'));
      await tester.pumpAndSettle();
      expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Submit request')).onPressed, isNull);
      await tester.enterText(find.byType(TextField), 'too short');
      await tester.pump();
      expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Submit request')).onPressed, isNull);
      await tester.enterText(find.byType(TextField), 'I was charged twice for one booking');
      await tester.pump();
      expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Submit request')).onPressed, isNotNull);
    });

    testWidgets('submitting sends the server category + booking and opens the new request', (tester) async {
      tall(tester);
      final repo = _Repo();
      await tester.pumpWidget(app(repo, '/support/new?topic=payment&booking=12&ref=SEVO-12'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'I was charged twice for one booking');
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Submit request'));
      await tester.pumpAndSettle();
      expect(repo.created.single, {'category': 'PAYMENT_ISSUE', 'description': 'I was charged twice for one booking', 'booking': '12', 'photos': 0});
      expect(find.text('Support request'), findsOneWidget); // now on the request screen
    });

    testWidgets('a server refusal is shown and the form stays', (tester) async {
      tall(tester);
      final repo = _Repo()..createResult = const Failure(ValidationError('Please describe the problem.'));
      await tester.pumpWidget(app(repo, '/support/new'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'something went wrong here');
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Submit request'));
      await tester.pumpAndSettle();
      expect(find.text('Please describe the problem.'), findsOneWidget);
    });

    test('every topic maps to a category the server accepts', () {
      const accepted = {'POOR_SERVICE', 'PAYMENT_ISSUE', 'REFUND_ISSUE', 'GOODS_DAMAGED', 'GOODS_LOST', 'TECHNICIAN_BEHAVIOUR', 'OTHER'};
      for (final t in kSupportTopics.values) {
        expect(accepted, contains(t.category));
      }
    });
  });

  group('conversation', () {
    testWidgets('shows my message, support replies, and sends a reply', (tester) async {
      final repo = _Repo()
        ..detailResult = Success(SupportRequest.tryParse(json(status: 'WAITING_CUSTOMER', messages: [
          {'id': 1, 'persona': 'ADMIN', 'message': 'Can you send the receipt?'},
        ]))!);
      await tester.pumpWidget(app(repo, '/support/tickets/7'));
      await tester.pumpAndSettle();
      expect(find.text('We need your reply'), findsWidgets);
      expect(find.text('Can you send the receipt?'), findsOneWidget);
      expect(find.text('SEVO Support'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'Sent it');
      await tester.tap(find.byIcon(Icons.send_rounded));
      await tester.pumpAndSettle();
      expect(repo.replies, ['Sent it']);
    });

    testWidgets('Reopen and Escalate appear only when the server allows them', (tester) async {
      await tester.pumpWidget(app(_Repo(), '/support/tickets/7'));
      await tester.pumpAndSettle();
      expect(find.text('Not fixed - reopen'), findsNothing);
      expect(find.text('Escalate'), findsNothing);

      final repo = _Repo()..detailResult = Success(SupportRequest.tryParse(json(status: 'RESOLVED', reopen: true, escalate: true))!);
      await tester.pumpWidget(app(repo, '/support/tickets/7'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Not fixed - reopen'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Escalate'));
      await tester.pumpAndSettle();
      expect(repo.actions, ['reopen', 'escalate']);
    });

    testWidgets('a closed request has no reply box', (tester) async {
      final repo = _Repo()..detailResult = Success(SupportRequest.tryParse(json(status: 'CLOSED'))!);
      await tester.pumpWidget(app(repo, '/support/tickets/7'));
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsNothing);
    });
  });
}
