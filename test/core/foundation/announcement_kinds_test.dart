import 'package:calservices_customer/core/foundation/announcement_host.dart';
import 'package:calservices_customer/core/foundation/foundation_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

AppAnnouncement ann(int id, String kind, {String severity = 'info', bool dismissible = true}) =>
    AppAnnouncement(id: id, kind: kind, title: 'T$id $kind', body: 'B$id', severity: severity, dismissible: dismissible);

Future<ProviderContainer> pump(WidgetTester tester, List<AppAnnouncement> all) async {
  final container = ProviderContainer(overrides: [
    visibleAnnouncementsProvider.overrideWith((ref) {
      final hidden = ref.watch(sessionHiddenAnnouncementsProvider);
      final dismissed = ref.watch(dismissedAnnouncementsProvider);
      return [for (final a in all) if (!hidden.contains(a.id) && !(a.dismissible && dismissed.contains(a.id))) a];
    }),
    announcementStoreProvider.overrideWithValue(_MemoryStore()),
  ]);
  addTearDown(container.dispose);
  await tester.pumpWidget(UncontrolledProviderScope(
    container: container,
    child: const MaterialApp(
      home: Scaffold(
        body: Stack(children: [
          Column(children: [AnnouncementBanner(), Expanded(child: Center(child: Text('app')))]),
          AnnouncementInfoCard(),
          AnnouncementModal(),
        ]),
      ),
    ),
  ));
  await tester.pumpAndSettle();
  return container;
}

class _MemoryStore extends AnnouncementStore {
  _MemoryStore() : super();
  Set<int> saved = {};
  @override
  Future<Set<int>> read() async => saved;
  @override
  Future<void> write(Set<int> ids) async => saved = ids;
}

void main() {
  testWidgets('each kind has its own UI and does not appear in the others', (tester) async {
    await pump(tester, [ann(1, 'banner'), ann(2, 'modal'), ann(3, 'info')]);
    expect(find.text('T1 banner'), findsOneWidget);
    expect(find.text('T2 modal'), findsOneWidget);
    expect(find.text('Got it'), findsOneWidget); // the modal's button
    expect(find.text('T3 info'), findsOneWidget);
    expect(find.byIcon(Icons.close), findsNWidgets(2)); // banner + info card
  });

  testWidgets('a banner announcement alone shows only the top strip', (tester) async {
    await pump(tester, [ann(1, 'banner')]);
    expect(find.text('T1 banner'), findsOneWidget);
    expect(find.text('Got it'), findsNothing);
  });

  testWidgets('a modal announcement is a pop-up with Got it, not a top strip', (tester) async {
    await pump(tester, [ann(2, 'modal', severity: 'warning')]);
    expect(find.text('T2 modal'), findsOneWidget);
    expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);
    await tester.tap(find.text('Got it'));
    await tester.pumpAndSettle();
    expect(find.text('T2 modal'), findsNothing);
  });

  testWidgets('a non-dismissible modal still has a way out (until the app restarts)', (tester) async {
    final c = await pump(tester, [ann(2, 'modal', dismissible: false)]);
    await tester.tap(find.text('Got it'));
    await tester.pumpAndSettle();
    expect(find.text('T2 modal'), findsNothing);
    expect(c.read(sessionHiddenAnnouncementsProvider), {2});
    expect(c.read(dismissedAnnouncementsProvider), isEmpty); // not remembered across launches
  });

  testWidgets('an info announcement is a floating card that can be closed', (tester) async {
    await pump(tester, [ann(3, 'info')]);
    expect(find.text('T3 info'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();
    expect(find.text('T3 info'), findsNothing);
  });
}
