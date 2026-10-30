import 'dart:async';

import 'package:calservices_customer/core/errors/api_error.dart';
import 'package:calservices_customer/core/network/api_client.dart';
import 'package:calservices_customer/features/app_update/data/app_version_repository.dart';
import 'package:calservices_customer/features/app_update/data/play_update_client.dart';
import 'package:calservices_customer/features/app_update/domain/app_update_models.dart';

class FakeInstalledReader implements InstalledAppReader {
  FakeInstalledReader(this.app);
  InstalledApp app;
  int reads = 0;
  @override
  Future<InstalledApp> read() async {
    reads++;
    return app;
  }
}

InstalledApp installedApp(int build, {String name = '1.0.9'}) =>
    InstalledApp(versionName: name, buildNumber: build, packageName: 'com.caldim.sevo_customer');

class FakeRepo implements AppVersionRepository {
  FakeRepo(this.handler);
  Result<VersionPolicy> Function(InstalledApp) handler;
  int calls = 0;
  @override
  ApiClient get api => throw UnimplementedError();
  @override
  Future<String?> Function()? get installId => null;
  @override
  Future<Result<VersionPolicy>> check(InstalledApp installed) async {
    calls++;
    return handler(installed);
  }
}

class FakeStore extends AppUpdateStore {
  int? requiredBuild;
  String requiredName = '';
  int? snoozedBuild;
  DateTime? snoozedUntil;

  @override
  Future<({int build, String versionName})?> readRequired() async =>
      requiredBuild == null ? null : (build: requiredBuild!, versionName: requiredName);
  @override
  Future<void> writeRequired(int build, String versionName) async {
    requiredBuild = build;
    requiredName = versionName;
  }

  @override
  Future<void> clearRequired() async => requiredBuild = null;
  @override
  Future<void> snooze(int latestBuild, DateTime until) async {
    snoozedBuild = latestBuild;
    snoozedUntil = until;
  }

  @override
  Future<bool> isSnoozed(int latestBuild, DateTime now) async =>
      snoozedBuild == latestBuild && snoozedUntil != null && now.isBefore(snoozedUntil!);
}

class FakePlay implements PlayUpdateClient {
  PlayUpdateInfo info = const PlayUpdateInfo(available: true, immediateAllowed: true, flexibleAllowed: true, availableVersionCode: 30);
  bool throwUnavailable = false;
  PlayUpdateOutcome immediateOutcome = PlayUpdateOutcome.success;
  PlayUpdateOutcome flexibleOutcome = PlayUpdateOutcome.success;
  int immediateCalls = 0;
  int flexibleCalls = 0;
  int completeCalls = 0;
  final StreamController<PlayInstallStatus> status = StreamController<PlayInstallStatus>.broadcast();

  @override
  Future<PlayUpdateInfo> check() async {
    if (throwUnavailable) throw const PlayUnavailableException('test');
    return info;
  }

  @override
  Future<PlayUpdateOutcome> performImmediate() async {
    immediateCalls++;
    return immediateOutcome;
  }

  @override
  Future<PlayUpdateOutcome> startFlexible() async {
    flexibleCalls++;
    return flexibleOutcome;
  }

  @override
  Future<void> completeFlexible() async => completeCalls++;

  @override
  Stream<PlayInstallStatus> get installStatus => status.stream;
}

VersionPolicy upToDatePolicy() => const VersionPolicy(
    status: VersionStatus.upToDate, mandatory: false, updateMode: 'none', latestVersionName: '1.0.9', latestBuild: 10, minimumVersionName: '1.0.0', minimumBuild: 5);

VersionPolicy optionalPolicy({int latest = 20, String mode = 'flexible'}) => VersionPolicy(
    status: VersionStatus.updateAvailable,
    mandatory: false,
    updateMode: mode,
    latestVersionName: '1.2.0',
    latestBuild: latest,
    minimumVersionName: '1.0.0',
    minimumBuild: 5,
    releaseTitle: 'Faster bookings',
    releaseNotes: const ['Faster checkout', 'Bug fixes'],
    storeUrl: 'https://play.google.com/store/apps/details?id=com.caldim.sevo_customer');

VersionPolicy mandatoryPolicy({int minimum = 15}) => VersionPolicy(
    status: VersionStatus.updateRequired,
    mandatory: true,
    updateMode: 'immediate',
    latestVersionName: '1.2.0',
    latestBuild: 20,
    minimumVersionName: '1.1.0',
    minimumBuild: minimum,
    releaseTitle: 'Security update',
    releaseNotes: const ['Important fixes'],
    storeUrl: 'https://play.google.com/store/apps/details?id=com.caldim.sevo_customer');
