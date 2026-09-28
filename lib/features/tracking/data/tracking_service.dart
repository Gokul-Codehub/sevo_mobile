import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../../../config/env.dart';
import '../../../core/network/api_client.dart';
import '../domain/tracking_models.dart';

/// Service managing WebSocket connection with heartbeat, backoff, and an
/// always-on REST polling safety net.
///
/// Rewritten 2026-09-16 — three verified bugs fixed against the real
/// backend (service_requests/consumers.py `TrackingConsumer` +
/// service_requests/views.py `_build_tracking_payload`):
///
/// 1. The WS connect URL never appended `?token=`. Flutter's
///    `WebSocketChannel` cannot set an `Authorization` header (calservices-
///    mobile skill guardrail #8), and `TrackingConsumer._is_authorized`
///    only accepts an anonymous/guest connection when the tracking token is
///    supplied as a query parameter — otherwise the socket is closed
///    (code 4003) immediately after connecting. Every booking reached
///    without a logged-in session (guest booking is a supported feature —
///    guardrail #5) silently never received a single WS message.
/// 2. `_handleWsMessage` checked `map['type']`, but this consumer always
///    sends `{"event": ..., "data": ...}` — never a `type` key at the top
///    level. The heartbeat pong check and the actual payload parsing both
///    silently no-op'd on every message; worse, the WHOLE wrapper object
///    (not `data`) was being parsed as a tracking snapshot.
/// 3. REST polling only ever started after 3 consecutive WS failures. A WS
///    connection that opens at the transport level but is then closed by
///    the server for auth reasons, or one that connects fine but the
///    consumer never pushes an update, left the screen with no data
///    indefinitely. REST polling now always runs as a safety net, exactly
///    like the reference web app's `useCustomerTracking` hook (WS is an
///    enhancement for low-latency pushes, REST is the source of truth).
class TrackingNotifier extends FamilyNotifier<TrackingUpdate, TrackingArgs> {
  WebSocketChannel? _channel;
  StreamSubscription? _channelSub;
  Timer? _heartbeatTimer;
  Timer? _pollingTimer;
  Timer? _reconnectTimer;

  int _reconnectAttempts = 0;
  bool _isDisposed = false;

  @override
  TrackingUpdate build(TrackingArgs arg) {
    _isDisposed = false;
    _reconnectAttempts = 0;

    ref.onDispose(() {
      _isDisposed = true;
      _cleanupAll();
    });

    // REST is the authoritative source of truth and always runs; WS is a
    // best-effort low-latency enhancement layered on top of it.
    _pollOnce(arg);
    _startRestPolling(arg);
    _connectWebSocket(arg);

    return TrackingUpdate.initial();
  }

  ApiClient get _api => ref.read(apiClientProvider);

  // ── 1. WebSocket Connection ───────────────────────────────────────────────
  void _connectWebSocket(TrackingArgs arg) {
    if (_isDisposed) return;

    final token = (arg.trackingToken ?? '').trim();
    final query = token.isNotEmpty ? '?token=${Uri.encodeQueryComponent(token)}' : '';
    final baseWs = '${Env.wsBaseUrl}/tracking/${arg.identifier}/$query';
    final wsUri = Uri.parse(baseWs);

    try {
      debugPrint('[Tracking WS] Connecting to $wsUri...');
      _channel = WebSocketChannel.connect(wsUri);

      _channelSub = _channel!.stream.listen(
        (message) {
          _reconnectAttempts = 0; // Reset on successful message
          _handleWsMessage(message);
        },
        onError: (error) {
          debugPrint('[Tracking WS] Error: $error');
          _scheduleReconnect(arg);
        },
        onDone: () {
          debugPrint('[Tracking WS] Connection closed');
          _scheduleReconnect(arg);
        },
      );

      _startHeartbeat();
    } catch (e) {
      debugPrint('[Tracking WS] Connect failed: $e');
      _scheduleReconnect(arg);
    }
  }

  void _handleWsMessage(dynamic raw) {
    try {
      final decoded = jsonDecode(raw.toString());
      if (decoded is! Map) return;
      final map = Map<String, dynamic>.from(decoded);
      // TrackingConsumer always keys the message type as "event", not
      // "type" (see consumers.py — every send_json call uses {"event": ...}).
      final event = map['event']?.toString();

      if (event == 'pong') {
        return; // Heartbeat response
      }

      // Every event this consumer emits nests the actual tracking snapshot
      // under "data" (initial_state, job_updated, technician_location_updated,
      // technician_assigned, technician_status_updated,
      // otp_verification_success all follow this same {event, data} shape).
      final data = map['data'];
      if (data is Map) {
        state = TrackingUpdate.fromJson(Map<String, dynamic>.from(data), isWs: true);
      }
    } catch (e) {
      debugPrint('[Tracking WS] Failed to parse message: $e');
    }
  }

  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 25), (_) {
      if (_channel != null && !_isDisposed) {
        try {
          _channel!.sink.add(jsonEncode({'action': 'ping'}));
        } catch (_) {}
      }
    });
  }

  // ── 2. Exponential Reconnect ───────────────────────────────────────────────
  void _scheduleReconnect(TrackingArgs arg) {
    if (_isDisposed) return;
    if (state.isTerminal) return; // booking is finished — nothing left to track
    _cleanupWs();

    _reconnectAttempts++;
    if (_reconnectAttempts > 3) {
      // REST polling is already running unconditionally (see build()) — WS
      // just goes quiet rather than being retried forever.
      debugPrint('[Tracking WS] Giving up on WS after 3 failures — REST polling continues.');
      return;
    }

    final delaySeconds = (1 << (_reconnectAttempts - 1)).clamp(1, 8);
    debugPrint('[Tracking WS] Reconnecting in ${delaySeconds}s (attempt $_reconnectAttempts)...');

    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(Duration(seconds: delaySeconds), () {
      _connectWebSocket(arg);
    });
  }

  // ── 3. REST Polling Safety Net ─────────────────────────────────────────────
  void _startRestPolling(TrackingArgs arg) {
    _pollingTimer?.cancel();
    // Every 5s, matching the reference web app's fallback cadence
    // (useCustomerTracking.js polls every 5s while not WS-connected).
    _pollingTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (state.isTerminal) {
        _pollingTimer?.cancel();
        return;
      }
      _pollOnce(arg);
    });
  }

  Future<void> _pollOnce(TrackingArgs arg) async {
    if (_isDisposed) return;
    try {
      final token = (arg.trackingToken ?? '').trim();
      final response = await _api.get(
        '/booking/${arg.identifier}/live-location/',
        queryParameters: token.isNotEmpty ? {'token': token} : null,
      );
      final data = response.data;
      if (data is Map) {
        final map = Map<String, dynamic>.from(data);
        final inner = map['data'] is Map ? Map<String, dynamic>.from(map['data'] as Map) : map;
        state = TrackingUpdate.fromJson(inner, isWs: false);
      }
    } catch (e) {
      debugPrint('[Tracking REST] Polling error: $e');
    }
  }

  void _cleanupWs() {
    _heartbeatTimer?.cancel();
    _channelSub?.cancel();
    _channel?.sink.close();
    _channel = null;
    _channelSub = null;
  }

  void _cleanupAll() {
    _cleanupWs();
    _pollingTimer?.cancel();
    _reconnectTimer?.cancel();
  }
}

// ── Provider ─────────────────────────────────────────────────────────────────
final trackingProvider =
    NotifierProvider.family<TrackingNotifier, TrackingUpdate, TrackingArgs>(
  TrackingNotifier.new,
);
