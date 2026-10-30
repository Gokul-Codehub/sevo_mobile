import 'dart:io' show Platform;
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../../core/errors/api_error.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/response_normalizer.dart';
import '../domain/app_update_controller.dart' show appUpdateStoreProvider;
import '../domain/app_update_models.dart';

/// Reads the installed app info. Wrapped so tests can supply any build.
abstract class InstalledAppReader {
  Future<InstalledApp> read();
}

class PackageInfoReader implements InstalledAppReader {
  const PackageInfoReader();

  @override
  Future<InstalledApp> read() async {
    final info = await PackageInfo.fromPlatform();
    return InstalledApp(
      versionName: info.version,
      buildNumber: int.tryParse(info.buildNumber) ?? 0,
      packageName: info.packageName,
    );
  }
}

/// `GET /api/mobile/version-check/` - public, works before login.
class AppVersionRepository {
  AppVersionRepository({required this.api, this.installId});

  final ApiClient api;

  /// Anonymous per-install id (adoption analytics). Null/empty/failing => the check simply omits it.
  final Future<String?> Function()? installId;

  /// A version check must never hold the app up: a short timeout, and any
  /// failure is a [Failure] the caller handles (it never throws).
  static const Duration timeout = Duration(seconds: 8);

  static String get platformName => !kIsWeb && Platform.isIOS ? 'ios' : 'android';

  Future<Result<VersionPolicy>> check(InstalledApp installed) async {
    try {
      String? deviceId;
      try {
        deviceId = await installId?.call();
      } catch (_) {}
      final response = await api.get(
        '/mobile/version-check/',
        queryParameters: {
          if (deviceId != null && deviceId.isNotEmpty) 'device_id': deviceId,
          'platform': platformName,
          'application_id': installed.packageName,
          'build': installed.buildNumber,
          'version': installed.versionName,
        },
        options: Options(sendTimeout: timeout, receiveTimeout: timeout, extra: {'skipRetry': true}),
      );
      final payload = ResponseNormalizer.extractPayload(response);
      switch (payload) {
        case Success(:final data):
          final policy = VersionPolicy.tryParse(data);
          return policy == null
              ? const Failure(ParseError('The update server sent an unexpected answer.'))
              : Success(policy);
        case Failure(:final error):
          return Failure(error);
      }
    } on DioException catch (e) {
      if (e.error is ApiError) return Failure(e.error! as ApiError);
      return const Failure(NetworkError());
    } catch (e) {
      return Failure(UnknownError(e.toString()));
    }
  }
}

/// Survives restarts so a device that was told an update is MANDATORY stays
/// locked while the check cannot reach the server (otherwise going offline and
/// relaunching would silently unlock an unsupported build). Cleared as soon as
/// a successful check - or the installed build - says the requirement is met.
class AppUpdateStore {
  AppUpdateStore([FlutterSecureStorage? storage])
      : _storage = storage ?? const FlutterSecureStorage(aOptions: AndroidOptions(encryptedSharedPreferences: true));

  final FlutterSecureStorage _storage;

  static const _kRequiredBuild = 'sevo_update_required_build';
  static const _kRequiredName = 'sevo_update_required_name';
  static const _kSnoozeBuild = 'sevo_update_snooze_build';
  static const _kSnoozeUntil = 'sevo_update_snooze_until';
  static const _kInstallId = 'sevo_install_id';

  /// Random id created on first use; not derived from any hardware or account data.
  Future<String?> installId() async {
    try {
      final existing = await _storage.read(key: _kInstallId);
      if (existing != null && existing.length >= 16) return existing;
      final rnd = Random.secure();
      final id = List.generate(32, (_) => rnd.nextInt(16).toRadixString(16)).join();
      await _storage.write(key: _kInstallId, value: id);
      return id;
    } catch (_) {
      return null;
    }
  }

  Future<({int build, String versionName})?> readRequired() async {
    try {
      final build = int.tryParse(await _storage.read(key: _kRequiredBuild) ?? '');
      if (build == null || build <= 0) return null;
      return (build: build, versionName: await _storage.read(key: _kRequiredName) ?? '');
    } catch (_) {
      return null;
    }
  }

  Future<void> writeRequired(int build, String versionName) async {
    try {
      await _storage.write(key: _kRequiredBuild, value: '$build');
      await _storage.write(key: _kRequiredName, value: versionName);
    } catch (_) {}
  }

  Future<void> clearRequired() async {
    try {
      await _storage.delete(key: _kRequiredBuild);
      await _storage.delete(key: _kRequiredName);
    } catch (_) {}
  }

  /// "Maybe later" on an optional update: not shown again for this build until [until].
  Future<void> snooze(int latestBuild, DateTime until) async {
    try {
      await _storage.write(key: _kSnoozeBuild, value: '$latestBuild');
      await _storage.write(key: _kSnoozeUntil, value: until.toIso8601String());
    } catch (_) {}
  }

  Future<bool> isSnoozed(int latestBuild, DateTime now) async {
    try {
      final build = int.tryParse(await _storage.read(key: _kSnoozeBuild) ?? '');
      final until = DateTime.tryParse(await _storage.read(key: _kSnoozeUntil) ?? '');
      return build == latestBuild && until != null && now.isBefore(until);
    } catch (_) {
      return false;
    }
  }
}

final appVersionRepositoryProvider = Provider<AppVersionRepository>(
  (ref) => AppVersionRepository(api: ref.watch(apiClientProvider), installId: ref.watch(appUpdateStoreProvider).installId),
);
