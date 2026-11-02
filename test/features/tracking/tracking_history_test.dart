import 'package:calservices_customer/features/tracking/domain/tracking_models.dart';
import 'package:calservices_customer/features/tracking/presentation/widgets/tracking_history_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, Object?> ev(String to, String at) => {'from_status': '', 'to_status': to, 'occurred_at': at};

void main() {
  group('status_history parsing', () {
    test('events are oldest-first with readable labels, and repeats are collapsed', () {
      final events = TrackingHistoryEvent.parseList([
        ev('technician_assigned', '2026-10-30T10:00:00+05:30'),
        ev('on_the_way', '2026-10-30T11:00:00+05:30'),
        ev('on_the_way', '2026-10-30T11:05:00+05:30'),
        ev('arrived', '2026-10-30T11:40:00+05:30'),
      ]);
      expect(events.map((e) => e.status), ['technician_assigned', 'on_the_way', 'arrived']);
      expect(events.every((e) => e.label.isNotEmpty && !e.label.contains('_')), isTrue);
    });

    test('out-of-order input is sorted; junk and entries without a time or status are dropped', () {
      final events = TrackingHistoryEvent.parseList([
        ev('arrived', '2026-10-30T12:00:00+05:30'),
        ev('on_the_way', '2026-10-30T11:00:00+05:30'),
        {'to_status': '', 'occurred_at': '2026-10-30T09:00:00+05:30'},
        {'to_status': 'completed', 'occurred_at': null},
        'junk',
        5,
      ]);
      expect(events.map((e) => e.status), ['on_the_way', 'arrived']);
    });

    test('nothing or garbage means no history', () {
      expect(TrackingHistoryEvent.parseList(null), isEmpty);
      expect(TrackingHistoryEvent.parseList('nope'), isEmpty);
    });

    test('it is part of the tracking update', () {
      final u = TrackingUpdate.fromJson({'status': 'arrived', 'status_history': [ev('arrived', '2026-10-30T12:00:00+05:30')]});
      expect(u.history, hasLength(1));
    });
  });

  group('TrackingHistoryCard', () {
    List<TrackingHistoryEvent> events() => TrackingHistoryEvent.parseList([
          ev('technician_assigned', '2026-10-30T10:00:00+05:30'),
          ev('on_the_way', '2026-10-30T11:00:00+05:30'),
        ]);

    testWidgets('hidden with no events', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: Scaffold(body: TrackingHistoryCard(events: []))));
      expect(find.text('Tracking history'), findsNothing);
    });

    testWidgets('collapsed shows the count; expanding lists the steps newest first', (tester) async {
      final list = events();
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: SingleChildScrollView(child: TrackingHistoryCard(events: list)))));
      expect(find.text('2 updates'), findsOneWidget);
      await tester.tap(find.byKey(const Key('tracking_history')));
      await tester.pumpAndSettle();
      final newest = tester.getTopLeft(find.text(list.last.label)).dy;
      final oldest = tester.getTopLeft(find.text(list.first.label)).dy;
      expect(newest, lessThan(oldest));
    });

    test('times are shown in 12-hour form', () {
      expect(TrackingHistoryCard.timeOf(DateTime(2026, 10, 30, 0, 5)), '12:05 AM');
      expect(TrackingHistoryCard.timeOf(DateTime(2026, 10, 30, 13, 40)), '1:40 PM');
      expect(TrackingHistoryCard.timeOf(DateTime(2026, 10, 30, 12, 0)), '12:00 PM');
    });
  });

  group('share tracking', () {
    test('the link carries the tracking id (escaped) and no phone numbers or personal details', () {
      final t = trackingShareText('abc-123');
      expect(t, 'Follow my SEVO booking live: https://sevo.co.in/tracking/abc-123');
      expect(trackingShareText('a b/c'), contains('tracking/a%20b%2Fc'));
      expect(trackingShareText('x', serviceName: 'AC Service'), contains('(AC Service)'));
    });
  });
}
