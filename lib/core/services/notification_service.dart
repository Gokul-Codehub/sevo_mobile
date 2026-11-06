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

  /// Event keys already shown on this device, so the same event (a push AND the 45-second inbox poll) never alerts twice.
  final List<String> _recentKeys = [];

  /// True the first time [key] is seen; remembers the last 100.
  bool claim(String? key) {
    if (key == null || key.isEmpty) return true;
    if (_recentKeys.contains(key)) return false;
    _recentKeys.add(key);
    if (_recentKeys.length > 100) _recentKeys.removeAt(0);
    return true;
  }

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
        AndroidInitializationSettings('ic_stat_sevo');
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
      // Default channel for pushes that name no channel (e.g. Firebase Console campaigns). Without it Android
      // uses its own low-key fallback channel and the notification never pops up at the top of the screen.
      await androidImpl?.createNotificationChannel(const AndroidNotificationChannel(
        'sevo_default',
        'SEVONIQ notifications',
        description: 'Offers, news and updates from SEVONIQ',
        importance: Importance.high,
      ));
      // Channel named by the server's app-update pushes (FCM falls back to a default channel without it).
      await androidImpl?.createNotificationChannel(const AndroidNotificationChannel(
        'sevo_updates',
        'App updates',
        description: 'Reminders when a new version of SEVONIQ is available',
        importance: Importance.defaultImportance,
      ));
      // One channel per kind of notification (matches the channel ids the server sends), so each can be muted alone.
      for (final c in const [
        ('payments', 'Payments & refunds', 'Payment receipts and refund progress', Importance.high),
        ('support_updates', 'Support', 'Replies to your support requests', Importance.high),
        ('promotions', 'Offers & promotions', 'Coupons and deals (only if you opted in)', Importance.low),
      ]) {
        await androidImpl?.createNotificationChannel(
          AndroidNotificationChannel(c.$1, c.$2, description: c.$3, importance: c.$4),
        );
      }
      // The Android 13+ permission prompt is NOT shown here any more: at launch it stacked on top of the location
      // prompt, and for a guest it asks for something that does nothing yet. See [requestPermission], called once
      // the customer signs in (the way the big delivery apps do it).
    } catch (e) {
      debugPrint('[NotificationService] Failed to initialize notifications plugin: $e');
    }
  }

  /// Asks for the Android 13+ (API 33) notification permission, which is required before any notification can be
  /// shown; a no-op on older Android and when already granted. Call it at a moment the customer can see the point of
  /// it, for example right after signing in. iOS asks through DarwinInitializationSettings.
  Future<void> requestPermission() async {
    try {
      final androidImpl = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      await androidImpl?.requestNotificationsPermission();
    } catch (e) {
      debugPrint('[NotificationService] Notification permission request failed: $e');
    }
  }

  /// Set by CustomerNotificationWatcher: opens a web link carried by an inbox
  /// notification (payload `web:<claimExpiryMillis>|<web path>`).
  void Function(String webPath, DateTime? claimExpiresAt)? webLinkHandler;

  void _onNotificationTapped(NotificationResponse response) {
    final route = response.payload;
    if (route == null || route.isEmpty) return;
    if (route.startsWith('web:')) {
      final rest = route.substring(4);
      final bar = rest.indexOf('|');
      if (bar > 0) {
        final ms = int.tryParse(rest.substring(0, bar)) ?? 0;
        webLinkHandler?.call(
          rest.substring(bar + 1),
          ms > 0 ? DateTime.fromMillisecondsSinceEpoch(ms) : null,
        );
      }
      return;
    }
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
    String? dedupeKey,
  }) async {
    if (!claim(dedupeKey)) return; // already alerted for this event
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
