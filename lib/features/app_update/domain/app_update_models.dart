import 'package:equatable/equatable.dart';

/// What the app is running right now (from `PackageInfo.fromPlatform()`).
/// Never hard-coded: the build number is the Android `versionCode`.
class InstalledApp extends Equatable {
  const InstalledApp({required this.versionName, required this.buildNumber, required this.packageName});

  final String versionName;
  final int buildNumber;
  final String packageName;

  @override
  List<Object?> get props => [versionName, buildNumber, packageName];
}

enum VersionStatus { upToDate, updateAvailable, updateRequired, notConfigured, invalidConfiguration }

/// The backend's answer to `GET /api/mobile/version-check/`
/// (settings_hub/views_mobile_version.py). The server decides which screen the
/// app shows; the installed build it was given is advisory only.
class VersionPolicy extends Equatable {
  const VersionPolicy({
    required this.status,
    required this.mandatory,
    required this.updateMode,
    this.latestVersionName = '',
    this.latestBuild = 0,
    this.minimumVersionName = '',
    this.minimumBuild = 0,
    this.releaseTitle = '',
    this.releaseNotes = const [],
    this.storeUrl = '',
  });

  final VersionStatus status;
  final bool mandatory;

  /// 'none' | 'flexible' | 'immediate'
  final String updateMode;
  final String latestVersionName;
  final int latestBuild;
  final String minimumVersionName;
  final int minimumBuild;
  final String releaseTitle;
  final List<String> releaseNotes;
  final String storeUrl;

  bool get isOptionalUpdate => status == VersionStatus.updateAvailable && !mandatory;

  /// Parses the `data` object. Returns null for anything malformed so a bad
  /// response is treated as "no usable answer" rather than crashing startup.
  static VersionPolicy? tryParse(dynamic raw) {
    if (raw is! Map) return null;
    final map = Map<String, dynamic>.from(raw);
    final status = _status(map['status']);
    if (status == null) return null;

    final latest = _map(map['latest']);
    final minimum = _map(map['minimum_supported']);
    final release = _map(map['release']);
    final mandatory = map['mandatory'] == true;
    if (status == VersionStatus.updateRequired && !mandatory) return null; // contradictory

    final notes = release['notes'];
    return VersionPolicy(
      status: status,
      mandatory: mandatory,
      updateMode: (map['update_mode'] ?? 'none').toString(),
      latestVersionName: (latest['version_name'] ?? '').toString(),
      latestBuild: _int(latest['build']),
      minimumVersionName: (minimum['version_name'] ?? '').toString(),
      minimumBuild: _int(minimum['build']),
      releaseTitle: (release['title'] ?? '').toString(),
      releaseNotes: notes is List ? [for (final n in notes) n.toString()].where((n) => n.trim().isNotEmpty).toList() : const [],
      storeUrl: (map['store_url'] ?? '').toString(),
    );
  }

  static VersionStatus? _status(dynamic v) {
    switch (v?.toString().toUpperCase()) {
      case 'UP_TO_DATE':
        return VersionStatus.upToDate;
      case 'UPDATE_AVAILABLE':
        return VersionStatus.updateAvailable;
      case 'UPDATE_REQUIRED':
        return VersionStatus.updateRequired;
      case 'NOT_CONFIGURED':
        return VersionStatus.notConfigured;
      case 'INVALID_CONFIGURATION':
        return VersionStatus.invalidConfiguration;
    }
    return null;
  }

  static Map<String, dynamic> _map(dynamic v) => v is Map ? Map<String, dynamic>.from(v) : const {};
  static int _int(dynamic v) => v is int ? v : int.tryParse('$v') ?? 0;

  @override
  List<Object?> get props =>
      [status, mandatory, updateMode, latestVersionName, latestBuild, minimumVersionName, minimumBuild, releaseTitle, releaseNotes, storeUrl];
}

/// What the Google Play Core in-app update API says about this install.
class PlayUpdateInfo extends Equatable {
  const PlayUpdateInfo({
    required this.available,
    this.immediateAllowed = false,
    this.flexibleAllowed = false,
    this.availableVersionCode,
    this.inProgress = false,
  });

  /// An update for this app is available on Google Play.
  final bool available;
  final bool immediateAllowed;
  final bool flexibleAllowed;
  final int? availableVersionCode;

  /// An update (started earlier) is already downloading / installing.
  final bool inProgress;

  @override
  List<Object?> get props => [available, immediateAllowed, flexibleAllowed, availableVersionCode, inProgress];
}

enum PlayUpdateOutcome { success, userDenied, failed }

enum PlayInstallStatus { downloading, downloaded, installing, installed, failed, canceled, other }

/// The Play API could not be used at all (not installed from Play, no Play
/// Services, sideloaded build...). Callers fall back to the store link.
class PlayUnavailableException implements Exception {
  const PlayUnavailableException([this.reason = '']);
  final String reason;
  @override
  String toString() => 'PlayUnavailableException($reason)';
}

enum UpdatePhase {
  /// Nothing known yet / first check running.
  unknown,
  upToDate,
  optionalAvailable,
  mandatory,
}

enum CheckReason { startup, resume, afterLogin, manual }

class AppUpdateState extends Equatable {
  const AppUpdateState({
    this.phase = UpdatePhase.unknown,
    this.installed,
    this.policy,
    this.busy = false,
    this.message,
    this.playUnavailable = false,
    this.flexibleDownloaded = false,
    this.optionalPromptPending = false,
    this.lastSuccessfulCheck,
  });

  final UpdatePhase phase;
  final InstalledApp? installed;
  final VersionPolicy? policy;

  /// An update action (Play flow / re-check) is running.
  final bool busy;

  /// Plain-language status or error for the mandatory screen / dialog.
  final String? message;

  /// Play could not provide the required update (not published to this device yet, no Play, error).
  final bool playUnavailable;

  /// A flexible update finished downloading and only needs a restart.
  final bool flexibleDownloaded;

  /// The optional-update dialog should be shown (once) by the UI.
  final bool optionalPromptPending;

  final DateTime? lastSuccessfulCheck;

  bool get isMandatory => phase == UpdatePhase.mandatory;

  AppUpdateState copyWith({
    UpdatePhase? phase,
    InstalledApp? installed,
    VersionPolicy? policy,
    bool clearPolicy = false,
    bool? busy,
    String? message,
    bool clearMessage = false,
    bool? playUnavailable,
    bool? flexibleDownloaded,
    bool? optionalPromptPending,
    DateTime? lastSuccessfulCheck,
  }) =>
      AppUpdateState(
        phase: phase ?? this.phase,
        installed: installed ?? this.installed,
        policy: clearPolicy ? null : (policy ?? this.policy),
        busy: busy ?? this.busy,
        message: clearMessage ? null : (message ?? this.message),
        playUnavailable: playUnavailable ?? this.playUnavailable,
        flexibleDownloaded: flexibleDownloaded ?? this.flexibleDownloaded,
        optionalPromptPending: optionalPromptPending ?? this.optionalPromptPending,
        lastSuccessfulCheck: lastSuccessfulCheck ?? this.lastSuccessfulCheck,
      );

  @override
  List<Object?> get props =>
      [phase, installed, policy, busy, message, playUnavailable, flexibleDownloaded, optionalPromptPending, lastSuccessfulCheck];
}
