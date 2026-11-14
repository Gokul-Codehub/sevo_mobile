import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../../config/env.dart';
import '../../features/auth/domain/auth_notifier.dart';
import '../../features/booking/domain/booking_providers.dart';
import '../../features/orders/data/grocery_orders_repository.dart';
import '../storage/secure_storage.dart';

/// Live push for the signed-in customer's orders and bookings.
///
/// Connects to the backend's `/ws/orders/?token=<access token>` channel. When an order (status, payment or
/// refund status) or a booking changes, the server sends `order_updated` / `booking_updated` and this
/// refreshes the matching lists and detail screens at once. The previous data stays on screen while the
/// refresh runs (no flicker), and the screens' own polling stays as the fallback, so a dead socket never
/// leaves anything stale for long. Reconnects with back-off, reconnects when the app returns to the
/// foreground, and refreshes everything after a reconnect to catch anything missed while offline.
class CustomerLiveUpdates with WidgetsBindingObserver {
  CustomerLiveUpdates(this._ref);

  final Ref _ref;

  WebSocketChannel? _channel;
  StreamSubscription? _sub;
  Timer? _heartbeat;
  Timer? _reconnect;
  Timer? _debounce;
  int _attempts = 0;
  bool _disposed = false;
  bool _everConnected = false;

  void start() {
    if (_disposed) return;
    WidgetsBinding.instance.addObserver(this);
    _connect();
  }

  Future<void> _connect() async {
    if (_disposed) return;
    _close();
    try {
      final token = await _ref.read(secureStorageProvider).getAccessToken();
      if (_disposed) return;
      if (token == null || token.isEmpty) {
        _scheduleReconnect();
        return;
      }
      final uri = Uri.parse('${Env.wsBaseUrl}/orders/').replace(queryParameters: {'token': token});
      final channel = WebSocketChannel.connect(uri);
      _channel = channel;
      _sub = channel.stream.listen(
        _onMessage,
        onError: (_) => _scheduleReconnect(),
        onDone: _scheduleReconnect,
        cancelOnError: true,
      );
      _heartbeat = Timer.periodic(const Duration(seconds: 25), (_) {
        try {
          _channel?.sink.add(jsonEncode({'type': 'ping'}));
        } catch (_) {}
      });
    } catch (e) {
      debugPrint('[CustomerLive] connect failed: $e');
      _scheduleReconnect();
    }
  }

  void _onMessage(dynamic raw) {
    try {
      final decoded = jsonDecode(raw.toString());
      if (decoded is! Map) return;
      switch (decoded['event']) {
        case 'hello':
          // Connected: after a RE-connect, catch up on anything that changed while we were away.
          _attempts = 0;
          if (_everConnected) _refreshAll();
          _everConnected = true;
        case 'order_updated':
        case 'booking_updated':
          _refreshSoon();
      }
    } catch (e) {
      debugPrint('[CustomerLive] bad message: $e');
    }
  }

  /// A burst of changes (several saves for one action) becomes one refresh.
  void _refreshSoon() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), _refreshAll);
  }

  void _refreshAll() {
    if (_disposed) return;
    _ref.invalidate(groceryOrdersProvider);
    _ref.invalidate(groceryOrderProvider);
    _ref.invalidate(myBookingsProvider);
    _ref.invalidate(bookingDetailProvider);
  }

  void _scheduleReconnect() {
    if (_disposed) return;
    _close();
    _reconnect?.cancel();
    // 2s, 4s, 8s ... capped at 60s. A fresh access token is read on every attempt.
    final secs = (2 << (_attempts.clamp(0, 5))).clamp(2, 60);
    _attempts++;
    _reconnect = Timer(Duration(seconds: secs), _connect);
  }

  void _close() {
    _heartbeat?.cancel();
    _heartbeat = null;
    _sub?.cancel();
    _sub = null;
    try {
      _channel?.sink.close();
    } catch (_) {}
    _channel = null;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !_disposed) {
      _attempts = 0;
      _reconnect?.cancel();
      _connect();
    }
  }

  void dispose() {
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    _reconnect?.cancel();
    _debounce?.cancel();
    _close();
  }
}

/// Watch once (from the app shell) to keep the live connection open while a customer is signed in.
/// Signing out (or a guest) closes it; signing in opens it.
final customerLiveUpdatesProvider = Provider<CustomerLiveUpdates?>((ref) {
  final signedIn = ref.watch(currentUserProvider.select((u) => u != null && !u.isGuest && u.id != 0));
  if (!signedIn) return null;
  final live = CustomerLiveUpdates(ref)..start();
  ref.onDispose(live.dispose);
  return live;
});
