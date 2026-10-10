import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:go_router/go_router.dart';

import '../../routing/app_router.dart' show rootNavigatorKey;

/// Posts real notifications to the device's system notification center
/// (Android status bar / notification shade, iOS Notification Center) for
/// booking lifecycle events — "Booking Placed", "Booking Confirmed",
/// "Technician Assigned", "Service Completed", etc.
///
/// ── What this is ────────────────────────────────────────────────────────
/// These are LOCAL notifications: triggered entirely from code already
/// running inside this app (immediately on a successful booking-create —
/// see BookingActionController.createBooking — and by periodically
/// re-checking booking statuses while the app is open — see
/// BookingNotificationWatcher). They use the real OS notification API
/// (`flutter_local_notifications`), so they look, sound, and behave
/// exactly like a push notification and appear in the same notification
/// center/tray. They work while the app is in the foreground or
/// backgrounded (but not force-killed).
///
/// ── What this is NOT ────────────────────────────────────────────────────
/// This is not server-sent push (FCM/APNs). It cannot wake the app up or
/// deliver anything once the app process has been fully killed or the
/// device rebooted — there is nothing listening on the device at that
/// point. True always-on push (the "Swiggy/Zomato" experience) needs:
///   1. A device-token registry on the backend (register/unregister an
///      FCM/APNs token per signed-in customer).
///   2. A dispatch hook wired into the booking state machine
///      (backend/service_requests/state_machine.py's apply_transition)
///      that sends a push on every real status change.
///   3. A Firebase project (google-services.json) and, for iOS, an APNs
///      key — both of which only the project owner can create.
/// None of that exists in this backend yet (confirmed: no device-token
/// model, no FCM/APNs integration anywhere in accounts/service_requests).
/// See docs/PUSH_NOTIFICATIONS_BACKEND_SPEC.md for the exact spec to hand
/// to backend engineering when that work is picked up — this local
/// implementation would keep working unchanged alongside it.
class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  bool _initialized = false;
  int _nextId = 0;

  static const _channelId = 'booking_updates';
  static const _channelName = 'Booking Updates';
  static const _channelDescription =
      'Booking confirmations, technician assignment, and service status updates';

  Future<void> initialize() async {
    if (_initialized) return;
    // Guard against re-entrant initialize() calls firing concurrently
    // (e.g. the app-root watcher and an early notification both calling
    // it before the first one finishes).
    _initialized = true;

    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const darwinSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: darwinSettings,
    );

    try {
      await _plugin.initialize(
        initSettings,
        onDidReceiveNotificationResponse: _onNotificationTapped,
      );

      const androidChannel = AndroidNotificationChannel(
        _channelId,
        _channelName,
        description: _channelDescription,
        importance: Importance.high,
      );
      final androidImpl = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      await androidImpl?.createNotificationChannel(androidChannel);
      // Android 13+ (API 33) requires this explicit runtime request before
      // any notification can be shown; a no-op on older Android. iOS
      // permission is requested via DarwinInitializationSettings above.
      await androidImpl?.requestNotificationsPermission();
    } catch (e) {
      debugPrint('[NotificationService] Failed to initialize notifications plugin: $e');
    }
  }

  void _onNotificationTapped(NotificationResponse response) {
    final route = response.payload;
    if (route == null || route.isEmpty) return;
    final context = rootNavigatorKey.currentContext;
    if (context == null) return;
    GoRouter.of(context).push(route);
  }

  /// Shows one notification. [routePayload], if given, is the in-app route
  /// (e.g. `/bookings/123`) pushed when the customer taps the
  /// notification.
  Future<void> show({
    required String title,
    required String body,
    String? routePayload,
  }) async {
    if (!_initialized) await initialize();
    try {
      await _plugin.show(
        _nextId++,
        title,
        body,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            _channelId,
            _channelName,
            channelDescription: _channelDescription,
            importance: Importance.high,
            priority: Priority.high,
          ),
          iOS: DarwinNotificationDetails(),
        ),
        payload: routePayload,
      );
    } catch (e) {
      debugPrint('[NotificationService] Failed to show notification: $e');
    }
  }
}
