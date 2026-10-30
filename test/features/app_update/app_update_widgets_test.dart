import 'package:calservices_customer/core/errors/api_error.dart';
import 'package:calservices_customer/features/app_update/data/app_version_repository.dart';
import 'package:calservices_customer/features/app_update/domain/app_update_controller.dart';
import 'package:calservices_customer/features/app_update/domain/app_update_models.dart';
import 'package:calservices_customer/features/app_update/presentation/app_update_gate.dart';
import 'package:calservices_customer/features/app_update/presentation/update_widgets.dart';
import 'package:calservices_customer/features/booking/domain/cart_notifier.dart' show isUserAuthenticatedProvider;
import 'package:calservices_customer/routing/app_router.dart' show rootNavigatorKey;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';

final _authProvider = StateProvider<bool>((ref) => false);

void main() {
  late FakeRepo repo;
  late FakePlay play;
  late FakeInstalledReader reader;
  late FakeStore store;
  late DateTime now;
  var childTaps = 0;

  Future<void> pumpApp(WidgetTester tester) async {
    childTaps = 0;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appVersionRepositoryProvider.overrideWithValue(repo),
          playUpdateClientProvider.overrideWithValue(play),
          installedAppReaderProvider.overrideWithValue(reader),
          appUpdateStoreProvider.overrideWithValue(store),
          updateClockProvider.overrideWithValue(() => now),
          storeLauncherProvider.overrideWithValue((_) async => true),
          isUserAuthenticatedProvider.overrideWith((ref) => ref.watch(_authProvider)),
        ],
        child: MaterialApp(
          navigatorKey: rootNavigatorKey,
          builder: (context, child) => AppUpdateGate(child: child ?? const SizedBox.shrink()),
          home: Scaffold(
            body: Center(child: ElevatedButton(onPressed: () => childTaps++, child: const Text('App content'))),
          ),
        ),
      ),
    );
    await tester.pump(); // post-frame startup check
    await tester.pump(const Duration(milliseconds: 50));
  }

  setUp(() {
    repo = FakeRepo((_) => Success(upToDatePolicy()));
    play = FakePlay();
    reader = FakeInstalledReader(installedApp(10));
    store = FakeStore();
    now = DateTime(2026, 11, 1, 9);
  });

  testWidgets('up to date: no dialog and no mandatory screen', (tester) async {
    await pumpApp(tester);
    expect(find.text('App content'), findsOneWidget);
    expect(find.text('Update available'), findsNothing);
    expect(find.text('Update required'), findsNothing);
    expect(repo.calls, 1);
  });

  testWidgets('optional update: dialog shows versions and release notes, Maybe Later dismisses it', (tester) async {
    repo.handler = (_) => Success(optionalPolicy());
    await pumpApp(tester);
    expect(find.text('Update available'), findsOneWidget);
    expect(find.textContaining('Installed 1.0.9 (10)'), findsOneWidget);
    expect(find.textContaining('Latest 1.2.0 (20)'), findsOneWidget);
    expect(find.text('Faster checkout'), findsOneWidget);
    expect(find.text('Update Now'), findsOneWidget);
    expect(find.text('Maybe Later'), findsOneWidget);

    await tester.tap(find.text('Maybe Later'));
    await tester.pumpAndSettle();
    expect(find.text('Update available'), findsNothing);
    expect(find.text('App content'), findsOneWidget);
    expect(store.snoozedBuild, 20);
  });

  testWidgets('optional update: the dialog is not shown again for the same build after Maybe Later', (tester) async {
    repo.handler = (_) => Success(optionalPolicy());
    await pumpApp(tester);
    await tester.tap(find.text('Maybe Later'));
    await tester.pumpAndSettle();

    now = now.add(const Duration(minutes: 30));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(find.text('Update available'), findsNothing);
  });

  testWidgets('optional update: Update Now starts the Google Play flexible update', (tester) async {
    repo.handler = (_) => Success(optionalPolicy());
    await pumpApp(tester);
    await tester.tap(find.text('Update Now'));
    await tester.pumpAndSettle();
    expect(play.flexibleCalls, 1);
    expect(find.text('Update available'), findsNothing);
  });

  testWidgets('flexible update finished downloading: offers the restart', (tester) async {
    repo.handler = (_) => Success(optionalPolicy());
    await pumpApp(tester);
    await tester.tap(find.text('Update Now'));
    await tester.pumpAndSettle();
    play.status.add(PlayInstallStatus.downloaded);
    await tester.pumpAndSettle();
    expect(find.text('Update ready'), findsOneWidget);
    await tester.tap(find.text('Restart now'));
    await tester.pumpAndSettle();
    expect(play.completeCalls, 1);
  });

  testWidgets('mandatory update: full-screen, no dismiss, app content cannot be used', (tester) async {
    repo.handler = (_) => Success(mandatoryPolicy());
    await pumpApp(tester);
    expect(find.text('Update required'), findsOneWidget);
    expect(find.textContaining('Installed 1.0.9 (10)'), findsOneWidget);
    expect(find.textContaining('Minimum supported 1.1.0 (15)'), findsOneWidget);
    expect(find.text('Important fixes'), findsOneWidget);
    expect(find.text('Update Now'), findsOneWidget);
    expect(find.text('Maybe Later'), findsNothing);

    // taps do not reach the app underneath
    await tester.tap(find.text('App content'), warnIfMissed: false);
    expect(childTaps, 0);

    // Android back is blocked while the update is required
    final pop = tester.widget<PopScope>(find.byType(PopScope).first);
    expect(pop.canPop, isFalse);
  });

  testWidgets('mandatory update: Update Now starts the immediate Play update', (tester) async {
    repo.handler = (_) => Success(mandatoryPolicy());
    await pumpApp(tester);
    await tester.tap(find.text('Update Now'));
    await tester.pumpAndSettle();
    expect(play.immediateCalls, 1);
    expect(find.text('Update required'), findsOneWidget); // not unlocked: build unchanged
  });

  testWidgets('mandatory update: Play cannot deliver it, the screen explains and offers the store', (tester) async {
    repo.handler = (_) => Success(mandatoryPolicy());
    play.throwUnavailable = true;
    await pumpApp(tester);
    await tester.tap(find.text('Update Now'));
    await tester.pumpAndSettle();
    expect(find.textContaining('not available on this device'), findsOneWidget);
    expect(find.text('Open Play Store'), findsOneWidget);
    expect(find.text('I already updated - check again'), findsOneWidget);
    expect(find.text('Update required'), findsOneWidget);
  });

  testWidgets('mandatory update unlocks only once the installed build is really updated', (tester) async {
    repo.handler = (_) => Success(mandatoryPolicy());
    play.throwUnavailable = true;
    await pumpApp(tester);
    await tester.tap(find.text('Update Now'));
    await tester.pumpAndSettle();

    // user updated from the store: new build installed, backend now satisfied
    reader.app = installedApp(20);
    repo.handler = (_) => Success(upToDatePolicy());
    await tester.tap(find.text('I already updated - check again'));
    await tester.pumpAndSettle();
    expect(find.text('Update required'), findsNothing);
    expect(find.text('App content'), findsOneWidget);
  });

  testWidgets('returning to the app (resume) re-checks and unlocks after an update', (tester) async {
    repo.handler = (_) => Success(mandatoryPolicy());
    await pumpApp(tester);
    expect(find.text('Update required'), findsOneWidget);

    reader.app = installedApp(20);
    repo.handler = (_) => Success(upToDatePolicy());
    now = now.add(const Duration(minutes: 1));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(find.text('Update required'), findsNothing);
  });

  testWidgets('backend unavailable at start: the app opens normally', (tester) async {
    repo.handler = (_) => const Failure(NetworkError());
    await pumpApp(tester);
    expect(find.text('App content'), findsOneWidget);
    expect(find.text('Update required'), findsNothing);
  });

  testWidgets('repeated resumes do not hammer the backend', (tester) async {
    await pumpApp(tester);
    for (var i = 0; i < 4; i++) {
      now = now.add(const Duration(minutes: 2));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump(const Duration(milliseconds: 20));
    }
    expect(repo.calls, 1);
  });

  testWidgets('a check runs after the customer signs in', (tester) async {
    await pumpApp(tester);
    expect(repo.calls, 1);
    now = now.add(const Duration(minutes: 3));
    final container = ProviderScope.containerOf(tester.element(find.byType(AppUpdateGate)));
    container.read(_authProvider.notifier).state = true;
    await tester.pump(const Duration(milliseconds: 50));
    expect(repo.calls, 2);
  });

  testWidgets('MandatoryUpdateScreen shows a retry message while offline', (tester) async {
    store.requiredBuild = 15;
    store.requiredName = '1.1.0';
    repo.handler = (_) => const Failure(NetworkError());
    await pumpApp(tester);
    expect(find.text('Update required'), findsOneWidget);
    expect(find.textContaining('internet connection'), findsOneWidget);
  });

  testWidgets('screens render on a small phone without overflow', (tester) async {
    tester.view.physicalSize = const Size(320, 480);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    repo.handler = (_) => Success(mandatoryPolicy());
    await pumpApp(tester);
    expect(tester.takeException(), isNull);
    expect(find.byType(MandatoryUpdateScreen), findsOneWidget);
  });
}
