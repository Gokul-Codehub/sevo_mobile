import 'package:calservices_customer/core/permissions/permission_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class FakePlatform implements PermissionPlatform {
  PermState current = PermState.denied;
  PermState afterRequest = PermState.granted;
  int requests = 0;
  int settingsOpened = 0;
  @override
  Future<PermState> status(AppPermission permission) async => current;
  @override
  Future<PermState> request(AppPermission permission) async {
    requests++;
    current = afterRequest;
    return afterRequest;
  }

  @override
  Future<void> openSettings() async => settingsOpened++;
}

void main() {
  late FakePlatform platform;
  late int rationaleShown;
  late int settingsShown;
  late bool acceptRationale;
  late bool acceptSettings;

  PermissionManager make() => PermissionManager(
        platform: platform,
        askRationale: (c, r) async {
          rationaleShown++;
          return acceptRationale;
        },
        askSettings: (c, r) async {
          settingsShown++;
          return acceptSettings;
        },
      );

  setUp(() {
    platform = FakePlatform();
    rationaleShown = 0;
    settingsShown = 0;
    acceptRationale = true;
    acceptSettings = true;
  });

  Future<bool> run(WidgetTester tester, PermissionManager m, [AppPermission p = AppPermission.location]) async {
    late bool result;
    await tester.pumpWidget(MaterialApp(
      home: Builder(builder: (context) {
        return TextButton(
          onPressed: () async => result = await m.ensure(context, p),
          child: const Text('go'),
        );
      }),
    ));
    await tester.tap(find.text('go'));
    await tester.pump();
    await tester.pump();
    return result;
  }

  testWidgets('already granted: no prompts at all', (tester) async {
    platform.current = PermState.granted;
    expect(await run(tester, make()), isTrue);
    expect(rationaleShown, 0);
    expect(platform.requests, 0);
  });

  testWidgets('denied: explains first, then asks the system, granted', (tester) async {
    expect(await run(tester, make()), isTrue);
    expect(rationaleShown, 1);
    expect(platform.requests, 1);
  });

  testWidgets('declining the explanation never triggers the system prompt', (tester) async {
    acceptRationale = false;
    expect(await run(tester, make()), isFalse);
    expect(platform.requests, 0);
    expect(settingsShown, 0);
  });

  testWidgets('system says no once: false, no settings loop yet', (tester) async {
    platform.afterRequest = PermState.denied;
    expect(await run(tester, make()), isFalse);
    expect(settingsShown, 0);
  });

  testWidgets('system says never ask again: offers Open settings and opens them', (tester) async {
    platform.afterRequest = PermState.permanentlyDenied;
    expect(await run(tester, make()), isFalse);
    expect(settingsShown, 1);
    expect(platform.settingsOpened, 1);
  });

  testWidgets('permanently denied from the start: straight to the settings sheet', (tester) async {
    platform.current = PermState.permanentlyDenied;
    expect(await run(tester, make()), isFalse);
    expect(rationaleShown, 0);
    expect(settingsShown, 1);
    expect(platform.settingsOpened, 1);
  });

  testWidgets('cancelling the settings sheet does not open settings', (tester) async {
    platform.current = PermState.permanentlyDenied;
    acceptSettings = false;
    expect(await run(tester, make()), isFalse);
    expect(platform.settingsOpened, 0);
  });

  test('every permission has customer-friendly copy', () {
    for (final p in AppPermission.values) {
      final r = PermissionRationale.defaults[p]!;
      expect(r.title, isNotEmpty);
      expect(r.body, isNotEmpty);
      expect(r.settingsHint, isNotEmpty);
    }
  });

  testWidgets('default sheets render and return the choice', (tester) async {
    platform.current = PermState.permanentlyDenied;
    final m = PermissionManager(platform: platform);
    late bool result;
    await tester.pumpWidget(MaterialApp(
      home: Builder(builder: (context) => TextButton(onPressed: () async => result = await m.ensure(context, AppPermission.camera), child: const Text('go'))),
    ));
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    expect(find.text('Permission needed'), findsOneWidget);
    await tester.tap(find.text('Open settings'));
    await tester.pumpAndSettle();
    expect(result, isFalse);
    expect(platform.settingsOpened, 1);
  });
}
