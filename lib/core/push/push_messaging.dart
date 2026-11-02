import '../../features/app_update/domain/store_info.dart';
import 'dart:async';

import 'package:firebase_core/firebase_core.dart' show Firebase;
import 'package:firebase_messaging/firebase_messaging.dart';

import '../foundation/firebase_bootstrap.dart';

/// A push message reduced to plain Dart (the manager never sees Firebase types, so it is testable
/// and the rest of the app does not depend on the Firebase SDK).
class PushMessage {
  const PushMessage({this.title, this.body, this.data = const {}});
  final String? title;
  final String? body;
  final Map<String, String> data;

  String get type => data['type'] ?? '';
  String? get route => data['route'];
}

/// Seam over Firebase Cloud Messaging.
abstract class PushMessaging {
  /// Starts Firebase. False when Firebase is unavailable (no config, no Play services...): push is then off.
  Future<bool> initialize();
  Future<String?> getToken();
  Future<bool> notificationsAllowed();
  Stream<String> get tokenRefresh;
  Stream<PushMessage> get onForegroundMessage;
  Stream<PushMessage> get onMessageOpenedApp;
  Future<PushMessage?> initialMessage();
}

/// Runs in a background isolate when a message arrives while the app is closed. The system already
/// shows the notification (the server sends a notification block), so there is nothing to do here.
@pragma('vm:entry-point')
Future<void> sevoFirebaseBackgroundHandler(RemoteMessage message) async {}

PushMessage _convert(RemoteMessage m) => PushMessage(
      title: m.notification?.title,
      body: m.notification?.body,
      data: {for (final e in m.data.entries) e.key: e.value?.toString() ?? ''},
    );

class FirebasePushMessaging implements PushMessaging {
  const FirebasePushMessaging();

  @override
  Future<bool> initialize() async {
    try {
      if (!await FirebaseBootstrap.ensure() || Firebase.apps.isEmpty) return false;
      FirebaseMessaging.onBackgroundMessage(sevoFirebaseBackgroundHandler);
      if (StoreInfo.isIos) {
        // iOS: let the system banner show while the app is open (Android shows a local notification instead).
        await FirebaseMessaging.instance.setForegroundNotificationPresentationOptions(alert: true, badge: true, sound: true);
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<String?> getToken() async {
    try {
      return await FirebaseMessaging.instance.getToken();
    } catch (_) {
      return null;
    }
  }

  @override
  Future<bool> notificationsAllowed() async {
    try {
      final s = await FirebaseMessaging.instance.getNotificationSettings();
      return s.authorizationStatus == AuthorizationStatus.authorized || s.authorizationStatus == AuthorizationStatus.provisional;
    } catch (_) {
      return false;
    }
  }

  @override
  Stream<String> get tokenRefresh => FirebaseMessaging.instance.onTokenRefresh;

  @override
  Stream<PushMessage> get onForegroundMessage => FirebaseMessaging.onMessage.map(_convert);

  @override
  Stream<PushMessage> get onMessageOpenedApp => FirebaseMessaging.onMessageOpenedApp.map(_convert);

  @override
  Future<PushMessage?> initialMessage() async {
    try {
      final m = await FirebaseMessaging.instance.getInitialMessage();
      return m == null ? null : _convert(m);
    } catch (_) {
      return null;
    }
  }
}
