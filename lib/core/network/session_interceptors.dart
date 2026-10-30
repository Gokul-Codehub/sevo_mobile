import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../storage/secure_storage.dart';

/// Adds the anonymous per-install id to every request (`X-Device-Id`) so the server can tell
/// devices apart and revoke one. Skipped on web; never blocks a request if the id is unavailable.
class DeviceIdInterceptor extends Interceptor {
  DeviceIdInterceptor(this._read);
  final Future<String?> Function() _read;
  String? _cached;

  @override
  Future<void> onRequest(RequestOptions options, RequestInterceptorHandler handler) async {
    if (!kIsWeb) {
      try {
        _cached ??= await _read();
        final id = _cached;
        if (id != null && id.isNotEmpty) options.headers['X-Device-Id'] = id;
      } catch (_) {}
    }
    handler.next(options);
  }
}

/// A one-shot message for the UI after the server ends this device's session.
abstract final class SessionNotice {
  SessionNotice._();
  static final ValueNotifier<String?> message = ValueNotifier<String?>(null);
  static const String revoked = 'You were signed out. Please sign in again.';
}

/// Handles `401 {"code": "SESSION_REVOKED"}`: the server has ended this session (signed out from
/// another device or by an admin), so refreshing the token is pointless. Clears the local tokens,
/// sends the user to login and shows a notice. Must sit BEFORE the auth interceptor so no refresh is tried.
class SessionRevokedInterceptor extends Interceptor {
  SessionRevokedInterceptor({required this.storage, this.onRevoked});

  final SecureStorage storage;
  final VoidCallback? onRevoked;

  static bool isRevoked(DioException err) {
    if (err.response?.statusCode != 401) return false;
    final data = err.response?.data;
    return data is Map && data['code'] == 'SESSION_REVOKED';
  }

  @override
  Future<void> onError(DioException err, ErrorInterceptorHandler handler) async {
    if (!isRevoked(err)) {
      handler.next(err);
      return;
    }
    // Tell the auth interceptor not to try a token refresh for this request.
    err.requestOptions.extra['skipAuth'] = true;
    try {
      await storage.clearAll();
    } catch (_) {}
    SessionNotice.message.value = SessionNotice.revoked;
    onRevoked?.call();
    handler.next(err);
  }
}
