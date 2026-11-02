import 'package:calservices_customer/features/tracking/domain/tracking_models.dart';
import 'package:calservices_customer/features/tracking/presentation/widgets/work_photos_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> payload(List<Object?> proofs) => {'status': 'completed', 'completion_proofs': proofs};

void main() {
  group('completion_proofs parsing', () {
    test('real photos are kept with their label, type, notes and time', () {
      final u = TrackingUpdate.fromJson(payload([
        {
          'id': 'wf_1_appliance', 'proof_type': 'APPLIANCE', 'label': 'Appliance After Service',
          'image': 'https://media.sevo.co.in/p/a.jpg', 'notes': 'Filter cleaned', 'captured_at': '2026-10-30T10:15:00+05:30',
        },
        {'id': 'wf_1_signature', 'proof_type': 'SIGNATURE', 'image': 'https://media.sevo.co.in/p/s.png'},
      ]));
      expect(u.completionProofs, hasLength(2));
      final a = u.completionProofs.first;
      expect((a.label, a.type, a.notes), ('Appliance After Service', 'APPLIANCE', 'Filter cleaned'));
      expect(a.capturedAt, isNotNull);
      expect(u.completionProofs.last.isSignature, isTrue);
      expect(u.completionProofs.last.label, 'Signature'); // no label sent -> made readable from the type
    });

    test('entries without a usable image are skipped, junk never throws', () {
      final u = TrackingUpdate.fromJson(payload([
        {'proof_type': 'PRESENCE', 'image': ''},
        {'proof_type': 'PRESENCE', 'image': '/relative/path.jpg'},
        'junk', null, 5,
        {'proof_type': 'WORK_AREA', 'image': 'https://media.sevo.co.in/p/w.jpg'},
      ]));
      expect(u.completionProofs.map((p) => p.type), ['WORK_AREA']);
      expect(u.completionProofs.single.label, 'Work Area');
    });

    test('no proofs in the payload means an empty list', () {
      expect(TrackingUpdate.fromJson({'status': 'on_the_way'}).completionProofs, isEmpty);
      expect(TrackingUpdate.fromJson({'status': 'x', 'completion_proofs': 'nope'}).completionProofs, isEmpty);
    });
  });

  group('WorkPhotosCard', () {
    TrackingProof proof(String label) => TrackingProof(id: label, type: 'APPLIANCE', label: label, imageUrl: 'https://media.sevo.co.in/p/$label.jpg');

    testWidgets('hidden when there are no photos', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: Scaffold(body: WorkPhotosCard(proofs: []))));
      expect(find.text('Work photos'), findsNothing);
    });

    testWidgets('shows the heading and each photo label', (tester) async {
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: WorkPhotosCard(proofs: [proof('After service'), proof('Work area')]))));
      expect(find.text('Work photos'), findsOneWidget);
      expect(find.text('After service'), findsOneWidget);
      expect(find.text('Work area'), findsOneWidget);
    });

    testWidgets('tapping a photo opens it with a close button', (tester) async {
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: WorkPhotosCard(proofs: [proof('After service')]))));
      await tester.tap(find.text('After service'));
      await tester.pump();
      expect(find.text('Close'), findsOneWidget);
      await tester.tap(find.text('Close'));
      await tester.pump();
      expect(find.text('Close'), findsNothing);
    });
  });
}
