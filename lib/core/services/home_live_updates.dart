import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../../config/env.dart';
import '../../features/home/data/home_studio_repository.dart';
import '../../features/home/data/homepage_repository.dart';

/// Live push for the Home page.
///
/// Connects to the backend's public `/ws/home/` channel. When an admin
/// publishes (or rolls back) a Home Studio page the server sends
/// `{"event": "home_updated", "data": {"page": "services_home"}}` and this
/// re-fetches that page immediately — no waiting for the 90 s poll. The poll
/// in [homeStudioPageProvider] stays as the fallback, so a dead socket never
/// leaves the page stale for long. The previous page stays on screen while
/// the new one loads (no flicker).
class HomeLiveUpdates {
  HomeLiveUpdates(this._ref);

  final Ref _ref;

  WebSocketChannel? _channel;
  StreamSubscription? _sub;
  Timer? _heartbeat;
  Timer? _reconnect;
  int _attempts = 0;
  bool _disposed = false;

  void start() {
    if (_disposed || _channel != null) return;
    _connect();
  }

  void _connect() {
    if (_disposed) return;
    _close();
    try {
      final uri = Uri.parse('${Env.wsBaseUrl}/home/');
      _channel = WebSocketChannel.connect(uri);
      _sub = _channel!.stream.listen(
        (raw) {
          _attempts = 0;
          _onMessage(raw);
        },
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
      debugPrint('[HomeLive] connect failed: $e');
      _scheduleReconnect();
    }
  }

  void _onMessage(dynamic raw) {
    try {
      final decoded = jsonDecode(raw.toString());
      if (decoded is! Map || decoded['event'] != 'home_updated') return;
      final data = decoded['data'];
      final page = data is Map ? (data['page'] ?? '').toString() : '';
      if (page.isEmpty) {
        _ref.invalidate(homeStudioPageProvider);
      } else {
        _ref.invalidate(homeStudioPageProvider(page));
      }
      // Legacy (non-Studio) home content shares the same refresh.
      _ref.invalidate(homepageConfigProvider);
    } catch (e) {
      debugPrint('[HomeLive] bad message: $e');
    }
  }

  void _scheduleReconnect() {
    if (_disposed) return;
    _close();
    _reconnect?.cancel();
    // 2s, 4s, 8s ... capped at 60s.
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

  void dispose() {
    _disposed = true;
    _reconnect?.cancel();
    _close();
  }
}

/// Read once (e.g. from Home) to start listening; lives for the app session.
final homeLiveUpdatesProvider = Provider<HomeLiveUpdates>((ref) {
  final live = HomeLiveUpdates(ref)..start();
  ref.onDispose(live.dispose);
  return live;
});
