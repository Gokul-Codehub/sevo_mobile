import 'store_info.dart';
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/errors/api_error.dart';
import '../../../core/utils/app_logger.dart';
import '../data/app_version_repository.dart';
import '../data/play_update_client.dart';
import 'app_update_models.dart';

final installedAppReaderProvider = Provider<InstalledAppReader>((ref) => const PackageInfoReader());
final playUpdateClientProvider = Provider<PlayUpdateClient>((ref) => const InAppUpdatePlayClient());
final appUpdateStoreProvider = Provider<AppUpdateStore>((ref) => AppUpdateStore());
final updateClockProvider = Provider<DateTime Function()>((ref) => DateTime.now);

/// Opens the store listing. Returns false when it could not be opened.
final storeLauncherProvider = Provider<Future<bool> Function(Uri)>(
  (ref) => (uri) async {
    try {
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      return false;
    }
  },
);

/// Drives the whole update experience: check the backend policy, ask Google
/// Play what it can deliver, and start the Play flow. It never downloads or
/// installs anything itself and never reports an update as done until the
/// installed build number really changed.
class AppUpdateController extends StateNotifier<AppUpdateState> {
  AppUpdateController({
    required AppVersionRepository repository,
    required PlayUpdateClient play,
    required InstalledAppReader installedReader,
    required AppUpdateStore store,
    required DateTime Function() clock,
    required Future<bool> Function(Uri) openUrl,
  })  : _repo = repository,
        _play = play,
        _reader = installedReader,
        _store = store,
        _clock = clock,
        _openUrl = openUrl,
        super(const AppUpdateState()) {
    _installSub = _play.installStatus.listen(_onInstallStatus, onError: (_) {});
  }

  final AppVersionRepository _repo;
  final PlayUpdateClient _play;
  final InstalledAppReader _reader;
  final AppUpdateStore _store;
  final DateTime Function() _clock;
  final Future<bool> Function(Uri) _openUrl;

  StreamSubscription<PlayInstallStatus>? _installSub;
  bool _checking = false;
  DateTime? _lastAttempt;

  /// How often resume / login may hit the backend (startup and manual always may).
  static const Duration resumeThrottle = Duration(minutes: 15);
  static const Duration loginThrottle = Duration(minutes: 1);

  /// "Maybe later" hides the optional prompt for this build this long.
  static const Duration snoozeFor = Duration(hours: 24);

  @override
  void dispose() {
    _installSub?.cancel();
    super.dispose();
  }

  // ── Checking ──────────────────────────────────────────────────────────────
  Future<void> check(CheckReason reason) async {
    if (_checking) return;
    final now = _clock();
    final last = _lastAttempt;
    if (last != null) {
      final gap = now.difference(last);
      if (reason == CheckReason.resume && gap < resumeThrottle && !state.isMandatory) return;
      if (reason == CheckReason.afterLogin && gap < loginThrottle) return;
    }
    _checking = true;
    _lastAttempt = now;
    try {
      final installed = await _reader.read();
      state = state.copyWith(installed: installed);

      // A mandatory requirement remembered from an earlier run holds until a
      // check (or the installed build) says it is met - even if we're offline.
      final remembered = await _store.readRequired();
      if (remembered != null && installed.buildNumber >= remembered.build) {
        await _store.clearRequired();
      } else if (remembered != null && !state.isMandatory) {
        state = state.copyWith(
          phase: UpdatePhase.mandatory,
          policy: VersionPolicy(
            status: VersionStatus.updateRequired,
            mandatory: true,
            updateMode: 'immediate',
            minimumBuild: remembered.build,
            minimumVersionName: remembered.versionName,
          ),
          optionalPromptPending: false,
        );
      }

      final result = await _repo.check(installed);
      switch (result) {
        case Success(:final data):
          await _apply(data, installed, now);
        case Failure(:final error):
          AppLogger.d('[UPDATE]', 'version check failed: ${error.message}');
          // Keep whatever we already knew (a remembered mandatory lock stays).
          if (state.phase == UpdatePhase.unknown) state = state.copyWith(phase: UpdatePhase.upToDate);
          if (state.isMandatory) {
            state = state.copyWith(message: 'Could not reach the update server. Check your internet connection and try again.');
          }
      }
    } catch (e) {
      AppLogger.d('[UPDATE]', 'version check error: $e');
      if (state.phase == UpdatePhase.unknown) state = state.copyWith(phase: UpdatePhase.upToDate);
    } finally {
      _checking = false;
    }
  }

  Future<void> _apply(VersionPolicy policy, InstalledApp installed, DateTime now) async {
    if (policy.mandatory) {
      await _store.writeRequired(policy.minimumBuild, policy.minimumVersionName);
      state = state.copyWith(
        phase: UpdatePhase.mandatory,
        policy: policy,
        lastSuccessfulCheck: now,
        optionalPromptPending: false,
        clearMessage: true,
      );
      return;
    }
    await _store.clearRequired();
    if (policy.isOptionalUpdate) {
      final snoozed = await _store.isSnoozed(policy.latestBuild, now);
      state = state.copyWith(
        phase: UpdatePhase.optionalAvailable,
        policy: policy,
        lastSuccessfulCheck: now,
        playUnavailable: false,
        clearMessage: true,
        optionalPromptPending: !snoozed,
      );
      return;
    }
    state = state.copyWith(
      phase: UpdatePhase.upToDate,
      policy: policy,
      lastSuccessfulCheck: now,
      playUnavailable: false,
      clearMessage: true,
      optionalPromptPending: false,
    );
  }

  // ── Optional update ───────────────────────────────────────────────────────
  /// The UI showed the optional dialog.
  void optionalPromptShown() {
    if (state.optionalPromptPending) state = state.copyWith(optionalPromptPending: false);
  }

  Future<void> maybeLater() async {
    final policy = state.policy;
    state = state.copyWith(optionalPromptPending: false);
    if (policy != null) await _store.snooze(policy.latestBuild, _clock().add(snoozeFor));
  }

  // ── Starting the update ───────────────────────────────────────────────────
  /// "Update Now" on either screen.
  Future<void> updateNow() async {
    final policy = state.policy;
    if (policy == null || state.busy) return;
    state = state.copyWith(busy: true, clearMessage: true, playUnavailable: false, optionalPromptPending: false);
    try {
      if (policy.mandatory) {
        await _runMandatory(policy);
      } else {
        await _runOptional(policy);
      }
    } finally {
      state = state.copyWith(busy: false);
    }
  }

  Future<void> _runMandatory(VersionPolicy policy) async {
    final PlayUpdateInfo info;
    try {
      info = await _play.check();
    } on PlayUnavailableException catch (e) {
      AppLogger.d('[UPDATE]', 'Play unavailable: ${e.reason}');
      state = state.copyWith(
        playUnavailable: true,
        message: StoreInfo.isIos
            ? 'Open the App Store to update SEVO.'
            : 'The Google Play update service is not available on this device. Open the Play Store to update.',
      );
      return;
    }
    final hasRequiredBuild = info.available && (info.availableVersionCode ?? 0) >= policy.minimumBuild;
    if (!hasRequiredBuild) {
      state = state.copyWith(
        playUnavailable: true,
        message: 'The required version is not available for your device on ${StoreInfo.longName} yet. '
            'Please try again later or contact SEVO support.',
      );
      return;
    }
    if (!info.immediateAllowed) {
      state = state.copyWith(
        playUnavailable: true,
        message: '${StoreInfo.longName == 'Google Play' ? 'Google Play' : 'The App Store'} cannot start the update inside the app right now. Open the ${StoreInfo.shortName} to update.',
      );
      return;
    }
    final outcome = await _play.performImmediate();
    switch (outcome) {
      case PlayUpdateOutcome.success:
        // Not "done" yet - confirm against the real installed build.
        await _recheckInstalled();
      case PlayUpdateOutcome.userDenied:
        state = state.copyWith(message: 'This update is required to keep using SEVO. Please tap Update Now to continue.');
      case PlayUpdateOutcome.failed:
        state = state.copyWith(
          playUnavailable: true,
          message: 'The update could not be completed. Try again, or open the ${StoreInfo.shortName} to update.',
        );
    }
  }

  Future<void> _runOptional(VersionPolicy policy) async {
    PlayUpdateInfo? info;
    try {
      info = await _play.check();
    } on PlayUnavailableException {
      info = null;
    }
    if (info == null || !info.available) {
      await openStore();
      return;
    }
    if (policy.updateMode == 'immediate' && info.immediateAllowed) {
      final outcome = await _play.performImmediate();
      if (outcome == PlayUpdateOutcome.success) await _recheckInstalled();
      return;
    }
    if (info.flexibleAllowed) {
      await _play.startFlexible(); // completion arrives on installStatus
      return;
    }
    if (info.immediateAllowed) {
      final outcome = await _play.performImmediate();
      if (outcome == PlayUpdateOutcome.success) await _recheckInstalled();
      return;
    }
    await openStore();
  }

  /// Re-read the installed build and ask the backend again. Called after an
  /// update flow ends and whenever the app resumes while locked.
  Future<void> _recheckInstalled() async {
    _lastAttempt = null;
    _checking = false;
    await check(CheckReason.manual);
  }

  /// Retry button / app resume on the mandatory screen.
  Future<void> recheck() async {
    if (state.busy) return;
    state = state.copyWith(busy: true, clearMessage: true);
    try {
      _lastAttempt = null;
      await check(CheckReason.manual);
    } finally {
      state = state.copyWith(busy: false);
    }
  }

  // ── Flexible update completion ───────────────────────────────────────────
  void _onInstallStatus(PlayInstallStatus status) {
    switch (status) {
      case PlayInstallStatus.downloaded:
        state = state.copyWith(flexibleDownloaded: true);
      case PlayInstallStatus.failed:
      case PlayInstallStatus.canceled:
        state = state.copyWith(flexibleDownloaded: false);
      case PlayInstallStatus.installed:
        unawaited(_recheckInstalled());
      default:
        break;
    }
  }

  Future<void> installDownloadedUpdate() async {
    try {
      await _play.completeFlexible(); // the app restarts into the new version
    } catch (e) {
      AppLogger.d('[UPDATE]', 'completeFlexible failed: $e');
      state = state.copyWith(flexibleDownloaded: false);
    }
  }

  // ── Store fallback ────────────────────────────────────────────────────────
  Future<bool> openStore() async {
    final policy = state.policy;
    final installed = state.installed;
    final configured = policy?.storeUrl.trim() ?? '';
    final Uri? uri = configured.isNotEmpty
        ? Uri.tryParse(configured)
        : (installed != null ? StoreInfo.fallbackUrl(installed.packageName) : null);
    if (uri == null) {
      state = state.copyWith(message: 'The store link is not available. Please contact SEVO support.');
      return false;
    }
    final ok = await _openUrl(uri);
    if (!ok) state = state.copyWith(message: 'Could not open the ${StoreInfo.shortName}. Please open it manually and update SEVO.');
    return ok;
  }
}

final appUpdateControllerProvider = StateNotifierProvider<AppUpdateController, AppUpdateState>((ref) {
  return AppUpdateController(
    repository: ref.watch(appVersionRepositoryProvider),
    play: ref.watch(playUpdateClientProvider),
    installedReader: ref.watch(installedAppReaderProvider),
    store: ref.watch(appUpdateStoreProvider),
    clock: ref.watch(updateClockProvider),
    openUrl: ref.watch(storeLauncherProvider),
  );
});
