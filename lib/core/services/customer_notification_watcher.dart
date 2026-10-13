import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../features/booking/domain/cart_notifier.dart';
import '../../features/notifications/domain/notification_providers.dart';
import '../../routing/app_router.dart' show rootNavigatorKey;
import 'notification_service.dart';

/// Keeps the in-app inbox fresh while the app is open and turns each NEW
/// notification into a real Android notification (status bar / notification
/// shade), the same way [BookingNotificationWatcher] does for booking status
/// changes. Mounted once above every screen (see main.dart).
///
/// This is polling plus local notifications: it works while the app is open
/// or in the background, but not once the app is fully closed — that needs
/// server push (FCM), which the backend does not have yet (no device-token
/// registry).
class CustomerNotificationWatcher extends ConsumerStatefulWidget {
  const CustomerNotificationWatcher({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<CustomerNotificationWatcher> createState() => _CustomerNotificationWatcherState();
}

class _CustomerNotificationWatcherState extends ConsumerState<CustomerNotificationWatcher>
    with WidgetsBindingObserver {
  static const _pollInterval = Duration(seconds: 45);
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );
  static const _baselineKey = 'sevo_last_notified_inbox_id';

  Timer? _timer;

  /// Highest inbox id already shown as a device notification; null = not read yet.
  int? _lastNotifiedId;
  bool _baselineLoaded = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    NotificationService.instance.initialize();
    // A tap on a device notification carrying a web link opens that page.
    NotificationService.instance.webLinkHandler = (raw, expiresAt) {
      final context = rootNavigatorKey.currentContext;
      if (context != null && mounted) {
        openNotificationLink(ref, context, raw, claimExpiresAt: expiresAt);
      }
    };
    _timer = Timer.periodic(_pollInterval, (_) => _poll());
    _loadBaseline();
  }

  Future<void> _loadBaseline() async {
    try {
      final raw = await _storage.read(key: _baselineKey);
      _lastNotifiedId = int.tryParse(raw ?? '');
    } catch (_) {}
    _baselineLoaded = true;
  }

  void _poll() {
    if (!ref.read(isUserAuthenticatedProvider)) return;
    ref.read(notificationsControllerProvider.notifier).refresh(silent: true);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _poll();
  }

  @override
  void dispose() {
    _timer?.cancel();
    NotificationService.instance.webLinkHandler = null;
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _onInbox(NotificationsState? previous, NotificationsState next) {
    if (!_baselineLoaded || !next.loadedOnce || next.items.isEmpty) return;
    final maxId = next.items.map((n) => n.id).reduce((a, b) => a > b ? a : b);

    // First run on this device: don't replay the whole backlog as alerts.
    final baseline = _lastNotifiedId;
    if (baseline == null) {
      _remember(maxId);
      return;
    }

    final fresh = next.items
        .where((n) => n.id > baseline && !n.isRead && !n.isExpired)
        .toList()
      ..sort((a, b) => a.id.compareTo(b.id));
    if (fresh.isEmpty) {
      if (maxId > baseline) _remember(maxId);
      return;
    }
    for (final n in fresh.take(3)) {
      NotificationService.instance.show(
        title: n.title,
        body: n.body.isEmpty ? 'Tap to open' : n.body,
        routePayload: n.target == null
            ? '/notifications'
            : 'web:${n.expiresAt?.millisecondsSinceEpoch ?? 0}|${n.target}',
      );
    }
    _remember(maxId);
  }

  void _remember(int id) {
    _lastNotifiedId = id;
    _storage.write(key: _baselineKey, value: '$id').catchError((_) {});
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<NotificationsState>(notificationsControllerProvider, _onInbox);
    return widget.child;
  }
}
