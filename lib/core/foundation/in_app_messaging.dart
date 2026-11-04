import 'dart:async';

// import 'package:firebase_in_app_messaging/firebase_in_app_messaging.dart'; // disabled, see pubspec.yaml

import 'firebase_bootstrap.dart';

/// Seam over Firebase In-App Messaging (the pop-ups, banners and cards created in
/// Firebase Console > Engage > In-App Messaging), so tests need no Firebase.
abstract class InAppMessagingSink {
  Future<void> setSuppressed(bool suppressed);
}

class FirebaseInAppMessagingSink implements InAppMessagingSink {
  const FirebaseInAppMessagingSink();
  @override
  Future<void> setSuppressed(bool suppressed) async {} // no-op while plugin is disabled
}

/// Screens where a marketing pop-up must never appear: payment, checkout, sign-in, live tracking
/// and the booking flows. (The SEVO announcements from the admin panel follow the same idea.)
abstract final class InAppMessagingRules {
  static const sensitivePrefixes = [
    '/checkout',
    '/login',
    '/goods-transport',
    '/ac-inspection',
    '/track',
    '/work-extension',
    '/feedback',
    '/splash',
    '/onboarding',
    '/location-access',
  ];

  static bool isSensitive(String? location) {
    if (location == null || location.isEmpty) return false;
    final path = location.split('?').first;
    return sensitivePrefixes.any((p) => path == p || path.startsWith('$p/'));
  }
}

/// Firebase In-App Messaging, kept safe: switchable from the admin panel (`in_app_messaging_enabled`),
/// held back on payment / sign-in / tracking screens, and never able to break the app.
class InAppMessagingManager {
  InAppMessagingManager({InAppMessagingSink? sink, Future<bool> Function()? ensureFirebase})
      : _sink = sink ?? const FirebaseInAppMessagingSink(),
        _ensure = ensureFirebase ?? FirebaseBootstrap.ensure;

  static final InAppMessagingManager instance = InAppMessagingManager();

  final InAppMessagingSink _sink;
  final Future<bool> Function() _ensure;
  bool _ready = false;
  bool _remoteEnabled = true;
  bool _sensitive = false;

  bool get suppressed => !_remoteEnabled || _sensitive;

  /// Starts Firebase (shared with push / crash reporting) and applies the current state.
  Future<void> init() async {
    try {
      if (!await _ensure()) return;
      _ready = true;
      await _apply();
    } catch (_) {}
  }

  void setRemoteEnabled(bool enabled) {
    if (enabled == _remoteEnabled) return;
    _remoteEnabled = enabled;
    unawaited(_apply());
  }

  /// Called with the screen the customer is on, e.g. `/checkout/payment`.
  void setLocation(String? location) {
    final sensitive = InAppMessagingRules.isSensitive(location);
    if (sensitive == _sensitive) return;
    _sensitive = sensitive;
    unawaited(_apply());
  }

  Future<void> _apply() async {
    if (!_ready) return;
    try {
      await _sink.setSuppressed(suppressed);
    } catch (_) {}
  }
}
