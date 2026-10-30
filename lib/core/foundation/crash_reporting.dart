import 'dart:ui' show PlatformDispatcher;

import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'firebase_bootstrap.dart';

/// Seam over Firebase Crashlytics (so the logic is testable).
abstract class CrashBackend {
  Future<void> setEnabled(bool enabled);
  Future<void> recordFlutterFatal(FlutterErrorDetails details);
  Future<void> recordError(Object error, StackTrace? stack, {required bool fatal});
  Future<void> setKey(String key, String value);
}

class FirebaseCrashBackend implements CrashBackend {
  const FirebaseCrashBackend();
  FirebaseCrashlytics get _c => FirebaseCrashlytics.instance;

  @override
  Future<void> setEnabled(bool enabled) => _c.setCrashlyticsCollectionEnabled(enabled);
  @override
  Future<void> recordFlutterFatal(FlutterErrorDetails details) => _c.recordFlutterFatalError(details);
  @override
  Future<void> recordError(Object error, StackTrace? stack, {required bool fatal}) => _c.recordError(error, stack, fatal: fatal);
  @override
  Future<void> setKey(String key, String value) => _c.setCustomKey(key, value);
}

/// Sends fatal Flutter / async errors to Crashlytics so crashes are known before customers complain.
///
///  * Off in debug builds, and switchable at runtime with the `crash_reporting_enabled` remote setting.
///  * Keys carry only app facts (app, version, build). No phone number, address, token or other personal data.
///  * Wraps (never replaces) the handlers installed in main.dart, so on-device logging behaves as before.
///  * If Firebase cannot start, nothing happens and the app is unaffected.
class CrashReporting {
  CrashReporting({CrashBackend? backend, Future<bool> Function()? ensureFirebase, bool? collectInThisBuild})
      : _backend = backend ?? const FirebaseCrashBackend(),
        _ensureFirebase = ensureFirebase ?? FirebaseBootstrap.ensure,
        _collect = collectInThisBuild ?? !kDebugMode;

  static final CrashReporting instance = CrashReporting();

  final CrashBackend _backend;
  final Future<bool> Function() _ensureFirebase;
  final bool _collect;

  bool _active = false; // Firebase up and collection allowed
  bool _remoteEnabled = true;
  bool installed = false;

  bool get active => _active && _remoteEnabled;

  /// Safe to call once at start-up; never throws.
  Future<void> init({String appKey = 'customer', String? version, int? build}) async {
    if (installed) return;
    try {
      if (!await _ensureFirebase()) return;
      installed = true;
      _active = _collect;
      await _backend.setEnabled(_active && _remoteEnabled);
      _hookHandlers();
      await _backend.setKey('app_key', appKey);
      if (version != null) await _backend.setKey('app_version', version);
      if (build != null) await _backend.setKey('build', '$build');
    } catch (_) {}
  }

  /// Convenience for main(): reads the installed version itself.
  Future<void> initFromPlatform() async {
    String? version;
    int? build;
    try {
      final info = await PackageInfo.fromPlatform();
      version = info.version;
      build = int.tryParse(info.buildNumber);
    } catch (_) {}
    await init(version: version, build: build);
  }

  /// The `crash_reporting_enabled` remote setting.
  Future<void> setRemoteEnabled(bool enabled) async {
    _remoteEnabled = enabled;
    if (!installed) return;
    try {
      await _backend.setEnabled(_active && enabled);
    } catch (_) {}
  }

  void _hookHandlers() {
    final previousFlutter = FlutterError.onError;
    FlutterError.onError = (details) {
      previousFlutter?.call(details);
      if (active) _backend.recordFlutterFatal(details).catchError((_) {});
    };
    final previousPlatform = PlatformDispatcher.instance.onError;
    PlatformDispatcher.instance.onError = (error, stack) {
      final handled = previousPlatform?.call(error, stack) ?? false;
      if (active) _backend.recordError(error, stack, fatal: true).catchError((_) {});
      return handled;
    };
  }

  /// A handled error worth knowing about (does not crash the app).
  void recordNonFatal(Object error, [StackTrace? stack]) {
    if (active) _backend.recordError(error, stack, fatal: false).catchError((_) {});
  }
}
