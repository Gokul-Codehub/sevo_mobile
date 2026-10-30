import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../foundation/firebase_bootstrap.dart';

/// The single catalogue of events. No screen calls Firebase directly; new events are added here.
abstract final class AnalyticsEvents {
  static const appOpen = 'app_open';
  static const screenView = 'screen_view';
  static const serviceViewed = 'service_viewed';
  static const cartStarted = 'cart_started';
  static const bookingStepViewed = 'booking_step_viewed';
  static const bookingSubmitted = 'booking_submitted';
  static const bookingConfirmed = 'booking_confirmed';
  static const paymentStarted = 'payment_started';
  static const paymentFailed = 'payment_failed';
  static const paymentSucceeded = 'payment_succeeded';
  static const trackingOpened = 'tracking_opened';
  static const cancelTapped = 'cancel_tapped';
  static const ratingSubmitted = 'rating_submitted';
  static const searchPerformed = 'search_performed';
}

/// Keeps personal data out of analytics: parameters named like contact/identity data are dropped,
/// and values that look like an email or phone number never leave the device.
abstract final class AnalyticsSanitizer {
  static final _badKey = RegExp(r'(phone|mobile|email|mail|name|address|otp|token|password|pass|lat|lng|lon|location|text|query)', caseSensitive: false);
  /// Standard Firebase keys that look personal by name but only ever carry a templated screen path.
  static const _allowedKeys = {'screen_name'};
  static final _email = RegExp(r'\S+@\S+\.\S+');
  static final _longDigits = RegExp(r'\d{8,}');

  static Map<String, Object> clean(Map<String, Object?>? params) {
    final out = <String, Object>{};
    params?.forEach((key, value) {
      if (value == null || (!_allowedKeys.contains(key) && _badKey.hasMatch(key))) return;
      if (value is String) {
        if (value.length > 100 || _email.hasMatch(value) || _longDigits.hasMatch(value)) return;
        out[key] = value;
      } else if (value is num || value is bool) {
        out[key] = value is bool ? (value ? 1 : 0) : value;
      }
    });
    return out;
  }

  /// '/bookings/123/receipt' -> '/bookings/:id/receipt' so ids never become part of an analytics name.
  static String screenName(String? raw) {
    if (raw == null || raw.isEmpty) return 'unknown';
    var path = raw.split('?').first;
    path = path
        .split('/')
        .map((s) => RegExp(r'^\d+$').hasMatch(s) || RegExp(r'^[0-9a-fA-F-]{16,}$').hasMatch(s) ? ':id' : s)
        .join('/');
    return path.isEmpty ? '/' : path;
  }
}

abstract class AnalyticsSink {
  Future<void> setEnabled(bool enabled);
  Future<void> log(String event, Map<String, Object> params);
  Future<void> setUserProperty(String name, String value);
}

class FirebaseAnalyticsSink implements AnalyticsSink {
  const FirebaseAnalyticsSink();
  FirebaseAnalytics get _a => FirebaseAnalytics.instance;
  @override
  Future<void> setEnabled(bool enabled) => _a.setAnalyticsCollectionEnabled(enabled);
  @override
  Future<void> log(String event, Map<String, Object> params) => _a.logEvent(name: event, parameters: params.isEmpty ? null : params);
  @override
  Future<void> setUserProperty(String name, String value) => _a.setUserProperty(name: name, value: value);
}

/// Product analytics behind one interface. Off in debug builds, switchable at runtime
/// (`analytics_enabled` remote setting), and never able to break the app.
class AnalyticsManager {
  AnalyticsManager({AnalyticsSink? sink, Future<bool> Function()? ensureFirebase, bool? collectInThisBuild})
      : _sink = sink ?? const FirebaseAnalyticsSink(),
        _ensureFirebase = ensureFirebase ?? FirebaseBootstrap.ensure,
        _collect = collectInThisBuild ?? !kDebugMode;

  static final AnalyticsManager instance = AnalyticsManager();

  final AnalyticsSink _sink;
  final Future<bool> Function() _ensureFirebase;
  final bool _collect;

  bool _ready = false;
  bool _remoteEnabled = true;

  bool get active => _ready && _collect && _remoteEnabled;

  Future<void> init() async {
    if (_ready) return;
    try {
      if (!await _ensureFirebase()) return;
      _ready = true;
      await _sink.setEnabled(_collect && _remoteEnabled);
    } catch (_) {}
  }

  /// The `analytics_enabled` remote setting.
  Future<void> setRemoteEnabled(bool enabled) async {
    _remoteEnabled = enabled;
    if (!_ready) return;
    try {
      await _sink.setEnabled(_collect && enabled);
    } catch (_) {}
  }

  void track(String event, [Map<String, Object?>? params]) {
    if (!active) return;
    _sink.log(event, AnalyticsSanitizer.clean(params)).catchError((_) {});
  }

  void screen(String? route) => track(AnalyticsEvents.screenView, {'screen_name': AnalyticsSanitizer.screenName(route)});

  void setUserProperty(String name, String value) {
    if (!active) return;
    _sink.setUserProperty(name, value).catchError((_) {});
  }
}

/// Reports a `screen_view` for every page the router shows (automatic - screens add nothing).
class AnalyticsRouteObserver extends NavigatorObserver {
  AnalyticsRouteObserver({AnalyticsManager? manager}) : _manager = manager;
  final AnalyticsManager? _manager;
  String? _last;

  AnalyticsManager get _m => _manager ?? AnalyticsManager.instance;

  void _report(Route<dynamic>? route) {
    final name = route?.settings.name;
    if (route is! PageRoute || name == null || name == _last) return;
    _last = name;
    _m.screen(name);
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) => _report(route);
  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) => _report(newRoute);
  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) => _report(previousRoute);
}
