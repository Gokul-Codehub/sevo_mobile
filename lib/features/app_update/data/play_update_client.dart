import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart' show PlatformException;
import 'package:in_app_update/in_app_update.dart';

import '../domain/app_update_models.dart';

/// Thin seam over Google's Play Core In-App Updates API (the `in_app_update`
/// package) so the update logic can be tested with a fake. Nothing here
/// downloads or installs an APK by itself: Google Play does the update.
abstract class PlayUpdateClient {
  /// Throws [PlayUnavailableException] when the Play API cannot be used
  /// (non-Android, sideloaded build, no Play Services...).
  Future<PlayUpdateInfo> check();

  Future<PlayUpdateOutcome> performImmediate();

  /// Starts the background download; completion is reported on [installStatus].
  Future<PlayUpdateOutcome> startFlexible();

  /// Installs a downloaded flexible update (the app restarts).
  Future<void> completeFlexible();

  Stream<PlayInstallStatus> get installStatus;
}

class InAppUpdatePlayClient implements PlayUpdateClient {
  const InAppUpdatePlayClient();

  bool get _supported => !kIsWeb && Platform.isAndroid;

  @override
  Future<PlayUpdateInfo> check() async {
    if (!_supported) throw const PlayUnavailableException('Not an Android device.');
    try {
      final info = await InAppUpdate.checkForUpdate();
      return PlayUpdateInfo(
        available: info.updateAvailability == UpdateAvailability.updateAvailable ||
            info.updateAvailability == UpdateAvailability.developerTriggeredUpdateInProgress,
        immediateAllowed: info.immediateUpdateAllowed,
        flexibleAllowed: info.flexibleUpdateAllowed,
        availableVersionCode: info.availableVersionCode,
        inProgress: info.updateAvailability == UpdateAvailability.developerTriggeredUpdateInProgress,
      );
    } on PlatformException catch (e) {
      // e.g. ERROR_APP_NOT_OWNED for a build that was not installed from Google Play.
      throw PlayUnavailableException('${e.code}: ${e.message ?? ''}');
    } catch (e) {
      throw PlayUnavailableException('$e');
    }
  }

  @override
  Future<PlayUpdateOutcome> performImmediate() => _run(InAppUpdate.performImmediateUpdate);

  @override
  Future<PlayUpdateOutcome> startFlexible() => _run(InAppUpdate.startFlexibleUpdate);

  Future<PlayUpdateOutcome> _run(Future<AppUpdateResult> Function() action) async {
    if (!_supported) throw const PlayUnavailableException('Not an Android device.');
    try {
      switch (await action()) {
        case AppUpdateResult.success:
          return PlayUpdateOutcome.success;
        case AppUpdateResult.userDeniedUpdate:
          return PlayUpdateOutcome.userDenied;
        case AppUpdateResult.inAppUpdateFailed:
          return PlayUpdateOutcome.failed;
      }
    } on PlatformException {
      return PlayUpdateOutcome.failed;
    }
  }

  @override
  Future<void> completeFlexible() => InAppUpdate.completeFlexibleUpdate();

  @override
  Stream<PlayInstallStatus> get installStatus {
    if (!_supported) return const Stream.empty();
    return InAppUpdate.installUpdateListener.map((s) {
      switch (s) {
        case InstallStatus.downloading:
          return PlayInstallStatus.downloading;
        case InstallStatus.downloaded:
          return PlayInstallStatus.downloaded;
        case InstallStatus.installing:
          return PlayInstallStatus.installing;
        case InstallStatus.installed:
          return PlayInstallStatus.installed;
        case InstallStatus.failed:
          return PlayInstallStatus.failed;
        case InstallStatus.canceled:
          return PlayInstallStatus.canceled;
        default:
          return PlayInstallStatus.other;
      }
    });
  }
}
