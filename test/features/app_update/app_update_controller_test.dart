import 'package:calservices_customer/core/errors/api_error.dart';
import 'package:calservices_customer/features/app_update/domain/app_update_controller.dart';
import 'package:calservices_customer/features/app_update/domain/app_update_models.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';

void main() {
  late FakeRepo repo;
  late FakePlay play;
  late FakeInstalledReader reader;
  late FakeStore store;
  late DateTime now;
  late List<Uri> opened;
  bool openResult = true;

  AppUpdateController build() => AppUpdateController(
        repository: repo,
        play: play,
        installedReader: reader,
        store: store,
        clock: () => now,
        openUrl: (uri) async {
          opened.add(uri);
          return openResult;
        },
      );

  setUp(() {
    repo = FakeRepo((_) => Success(upToDatePolicy()));
    play = FakePlay();
    reader = FakeInstalledReader(installedApp(10));
    store = FakeStore();
    now = DateTime(2026, 11, 1, 9);
    opened = [];
    openResult = true;
  });

  group('installed app detection', () {
    test('uses the installed version and build number the reader reports', () async {
      final c = build();
      await c.check(CheckReason.startup);
      expect(c.state.installed, installedApp(10));
      expect(reader.reads, 1);
    });

    test('hands the installed build to the backend check', () async {
      InstalledApp? seen;
      repo.handler = (i) {
        seen = i;
        return Success(upToDatePolicy());
      };
      reader.app = installedApp(42, name: '2.3.4');
      await build().check(CheckReason.startup);
      expect(seen!.buildNumber, 42);
      expect(seen!.versionName, '2.3.4');
      expect(seen!.packageName, 'com.caldim.sevo_customer');
    });
  });

  group('policy outcomes', () {
    test('latest version: up to date, no prompt', () async {
      final c = build();
      await c.check(CheckReason.startup);
      expect(c.state.phase, UpdatePhase.upToDate);
      expect(c.state.optionalPromptPending, isFalse);
    });

    test('optional update: phase optional and the prompt is pending', () async {
      repo.handler = (_) => Success(optionalPolicy());
      final c = build();
      await c.check(CheckReason.startup);
      expect(c.state.phase, UpdatePhase.optionalAvailable);
      expect(c.state.optionalPromptPending, isTrue);
      expect(c.state.policy!.latestBuild, 20);
    });

    test('mandatory update: phase mandatory and the requirement is remembered', () async {
      repo.handler = (_) => Success(mandatoryPolicy());
      final c = build();
      await c.check(CheckReason.startup);
      expect(c.state.phase, UpdatePhase.mandatory);
      expect(c.state.isMandatory, isTrue);
      expect(store.requiredBuild, 15);
    });

    test('maybe later hides the prompt and snoozes it for this build', () async {
      repo.handler = (_) => Success(optionalPolicy());
      final c = build();
      await c.check(CheckReason.startup);
      await c.maybeLater();
      expect(c.state.optionalPromptPending, isFalse);
      expect(store.snoozedBuild, 20);

      // a later check (same build, inside the window) does not prompt again
      now = now.add(const Duration(hours: 2));
      await c.check(CheckReason.manual);
      expect(c.state.phase, UpdatePhase.optionalAvailable);
      expect(c.state.optionalPromptPending, isFalse);

      // once the snooze has expired it may prompt again
      now = now.add(const Duration(hours: 25));
      await c.check(CheckReason.manual);
      expect(c.state.optionalPromptPending, isTrue);
    });

    test('a newer build than the snoozed one prompts again', () async {
      repo.handler = (_) => Success(optionalPolicy(latest: 20));
      final c = build();
      await c.check(CheckReason.startup);
      await c.maybeLater();
      repo.handler = (_) => Success(optionalPolicy(latest: 25));
      await c.check(CheckReason.manual);
      expect(c.state.optionalPromptPending, isTrue);
    });
  });

  group('failures', () {
    test('backend unavailable: the app carries on and nothing crashes', () async {
      repo.handler = (_) => const Failure(NetworkError());
      final c = build();
      await c.check(CheckReason.startup);
      expect(c.state.phase, UpdatePhase.upToDate);
      expect(c.state.isMandatory, isFalse);
    });

    test('invalid backend response is handled like an unavailable backend', () async {
      repo.handler = (_) => const Failure(ParseError('bad'));
      final c = build();
      await c.check(CheckReason.startup);
      expect(c.state.phase, UpdatePhase.upToDate);
    });

    test('a remembered mandatory requirement keeps the app locked while offline', () async {
      store.requiredBuild = 15;
      store.requiredName = '1.1.0';
      repo.handler = (_) => const Failure(NetworkError());
      final c = build();
      await c.check(CheckReason.startup);
      expect(c.state.isMandatory, isTrue);
      expect(c.state.policy!.minimumBuild, 15);
      expect(c.state.message, contains('internet'));
    });

    test('a remembered requirement is cleared once the installed build meets it', () async {
      store.requiredBuild = 8;
      repo.handler = (_) => const Failure(NetworkError());
      final c = build();
      await c.check(CheckReason.startup); // installed 10 >= 8
      expect(c.state.isMandatory, isFalse);
      expect(store.requiredBuild, isNull);
    });

    test('a successful non-mandatory answer unlocks a remembered lock', () async {
      store.requiredBuild = 15;
      repo.handler = (_) => Success(upToDatePolicy());
      final c = build();
      await c.check(CheckReason.startup);
      expect(c.state.isMandatory, isFalse);
      expect(store.requiredBuild, isNull);
    });
  });

  group('repeated checks', () {
    test('resume is throttled', () async {
      final c = build();
      await c.check(CheckReason.startup);
      now = now.add(const Duration(minutes: 5));
      await c.check(CheckReason.resume);
      expect(repo.calls, 1);
      now = now.add(const Duration(minutes: 11));
      await c.check(CheckReason.resume);
      expect(repo.calls, 2);
    });

    test('a resume while mandatory re-checks immediately (so an update unlocks promptly)', () async {
      repo.handler = (_) => Success(mandatoryPolicy());
      final c = build();
      await c.check(CheckReason.startup);
      now = now.add(const Duration(seconds: 20));
      await c.check(CheckReason.resume);
      expect(repo.calls, 2);
    });

    test('after-login checks are throttled to one a minute', () async {
      final c = build();
      await c.check(CheckReason.startup);
      now = now.add(const Duration(seconds: 20));
      await c.check(CheckReason.afterLogin);
      expect(repo.calls, 1);
      now = now.add(const Duration(minutes: 2));
      await c.check(CheckReason.afterLogin);
      expect(repo.calls, 2);
    });

    test('overlapping checks are collapsed', () async {
      final c = build();
      await Future.wait([c.check(CheckReason.startup), c.check(CheckReason.manual), c.check(CheckReason.manual)]);
      expect(repo.calls, 1);
    });
  });

  group('mandatory update via Google Play (immediate)', () {
    Future<AppUpdateController> lockedController() async {
      repo.handler = (_) => Success(mandatoryPolicy());
      final c = build();
      await c.check(CheckReason.startup);
      return c;
    }

    test('starts the immediate update and unlocks only after the build really changed', () async {
      final c = await lockedController();
      // after the Play flow the installed build is 20 and the backend agrees
      play.immediateOutcome = PlayUpdateOutcome.success;
      reader.app = installedApp(20);
      repo.handler = (_) => Success(upToDatePolicy());
      await c.updateNow();
      expect(play.immediateCalls, 1);
      expect(c.state.isMandatory, isFalse);
      expect(c.state.installed!.buildNumber, 20);
    });

    test('does not claim success when the update was initiated but the build did not change', () async {
      final c = await lockedController();
      play.immediateOutcome = PlayUpdateOutcome.success; // flow ended...
      // ...but the installed build is unchanged and the backend still requires 15
      await c.updateNow();
      expect(play.immediateCalls, 1);
      expect(c.state.isMandatory, isTrue);
    });

    test('user cancels the update: stays locked with a clear message', () async {
      final c = await lockedController();
      play.immediateOutcome = PlayUpdateOutcome.userDenied;
      await c.updateNow();
      expect(c.state.isMandatory, isTrue);
      expect(c.state.message, contains('required'));
      expect(c.state.busy, isFalse);
    });

    test('Play flow fails: stays locked and offers the Play Store fallback', () async {
      final c = await lockedController();
      play.immediateOutcome = PlayUpdateOutcome.failed;
      await c.updateNow();
      expect(c.state.isMandatory, isTrue);
      expect(c.state.playUnavailable, isTrue);
    });

    test('Play unavailable (not installed from Play): stays locked with the store fallback', () async {
      final c = await lockedController();
      play.throwUnavailable = true;
      await c.updateNow();
      expect(c.state.isMandatory, isTrue);
      expect(c.state.playUnavailable, isTrue);
      expect(play.immediateCalls, 0);
    });

    test('Play has no update at all: never silently unlocks', () async {
      final c = await lockedController();
      play.info = const PlayUpdateInfo(available: false);
      await c.updateNow();
      expect(c.state.isMandatory, isTrue);
      expect(c.state.playUnavailable, isTrue);
      expect(c.state.message, contains('not available'));
    });

    test('Play has an older version than the required minimum: treated as unavailable', () async {
      final c = await lockedController();
      play.info = const PlayUpdateInfo(available: true, immediateAllowed: true, availableVersionCode: 12);
      await c.updateNow();
      expect(play.immediateCalls, 0);
      expect(c.state.playUnavailable, isTrue);
    });

    test('immediate update not allowed by Play: fallback to the store', () async {
      final c = await lockedController();
      play.info = const PlayUpdateInfo(available: true, immediateAllowed: false, flexibleAllowed: true, availableVersionCode: 30);
      await c.updateNow();
      expect(play.immediateCalls, 0);
      expect(c.state.playUnavailable, isTrue);
    });

    test('retry check after the user updated from the store unlocks the app', () async {
      final c = await lockedController();
      reader.app = installedApp(20);
      repo.handler = (_) => Success(upToDatePolicy());
      await c.recheck();
      expect(c.state.isMandatory, isFalse);
      expect(store.requiredBuild, isNull);
    });

    test('update taps while busy are ignored', () async {
      final c = await lockedController();
      final first = c.updateNow();
      await c.updateNow(); // busy: no-op
      await first;
      expect(play.immediateCalls, 1);
    });
  });

  group('optional update via Google Play (flexible)', () {
    Future<AppUpdateController> optionalController({String mode = 'flexible'}) async {
      repo.handler = (_) => Success(optionalPolicy(mode: mode));
      final c = build();
      await c.check(CheckReason.startup);
      return c;
    }

    test('Update Now starts the flexible flow', () async {
      final c = await optionalController();
      await c.updateNow();
      expect(play.flexibleCalls, 1);
      expect(play.immediateCalls, 0);
    });

    test('download completion is reported and the restart installs it', () async {
      final c = await optionalController();
      await c.updateNow();
      play.status.add(PlayInstallStatus.downloaded);
      await Future<void>.delayed(Duration.zero);
      expect(c.state.flexibleDownloaded, isTrue);
      await c.installDownloadedUpdate();
      expect(play.completeCalls, 1);
    });

    test('a failed or cancelled download clears the ready flag', () async {
      final c = await optionalController();
      play.status.add(PlayInstallStatus.downloaded);
      await Future<void>.delayed(Duration.zero);
      play.status.add(PlayInstallStatus.canceled);
      await Future<void>.delayed(Duration.zero);
      expect(c.state.flexibleDownloaded, isFalse);
    });

    test('immediate mode configured for an optional update uses the immediate flow', () async {
      final c = await optionalController(mode: 'immediate');
      await c.updateNow();
      expect(play.immediateCalls, 1);
      expect(play.flexibleCalls, 0);
    });

    test('falls back to immediate when only immediate is allowed', () async {
      final c = await optionalController();
      play.info = const PlayUpdateInfo(available: true, immediateAllowed: true, flexibleAllowed: false, availableVersionCode: 30);
      await c.updateNow();
      expect(play.immediateCalls, 1);
    });

    test('Play unavailable falls back to opening the store listing', () async {
      final c = await optionalController();
      play.throwUnavailable = true;
      await c.updateNow();
      expect(opened.single.toString(), contains('play.google.com'));
    });

    test('Play reports no update: opens the store listing', () async {
      final c = await optionalController();
      play.info = const PlayUpdateInfo(available: false);
      await c.updateNow();
      expect(opened, hasLength(1));
    });

    test('a completed install triggers a fresh check', () async {
      final c = await optionalController();
      final before = repo.calls;
      repo.handler = (_) => Success(upToDatePolicy());
      reader.app = installedApp(20);
      play.status.add(PlayInstallStatus.installed);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(repo.calls, greaterThan(before));
      expect(c.state.phase, UpdatePhase.upToDate);
    });
  });

  group('store fallback', () {
    test('uses the configured store url', () async {
      repo.handler = (_) => Success(optionalPolicy());
      final c = build();
      await c.check(CheckReason.startup);
      expect(await c.openStore(), isTrue);
      expect(opened.single.toString(), 'https://play.google.com/store/apps/details?id=com.caldim.sevo_customer');
    });

    test('derives the Play listing from the package id when no url is configured', () async {
      final c = build();
      await c.check(CheckReason.startup); // upToDatePolicy has no store url
      await c.openStore();
      expect(opened.single.toString(), contains('id=com.caldim.sevo_customer'));
    });

    test('reports when the store cannot be opened', () async {
      openResult = false;
      repo.handler = (_) => Success(mandatoryPolicy());
      final c = build();
      await c.check(CheckReason.startup);
      expect(await c.openStore(), isFalse);
      expect(c.state.message, contains('Play Store'));
    });
  });
}
