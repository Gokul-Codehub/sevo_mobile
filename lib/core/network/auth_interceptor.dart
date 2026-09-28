import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../storage/secure_storage.dart';

/// Injects the Authorization header and handles 401 token refresh with request retry.
///
/// Refresh & Retry Lifecycle:
/// 1. Injects `Authorization: Bearer <access_token>` on outgoing authenticated requests.
/// 2. Intercepts 401 responses on authenticated requests.
/// 3. Queues concurrent 401s using a [Completer] to avoid refresh storms.
/// 4. On successful refresh: persists new access & refresh tokens to [SecureStorage],
///    re-issues the original failed request with the new token, and resolves the handler.
/// 5. On refresh failure (or missing token): clears tokens, notifies [onAuthFailure],
///    and rejects the handler with the original error.
class AuthInterceptor extends Interceptor {
  AuthInterceptor({
    required this.storage,
    required this.dio,
    this.onAuthFailure,
  });

  final SecureStorage storage;
  final Dio dio;

  /// Called when refresh fails and the user must re-authenticate.
  /// Wired to AuthNotifier.forceUnauthenticated() by ApiClient.
  final VoidCallback? onAuthFailure;

  Completer<String?>? _refreshCompleter;

  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    // Skip auth header injection for requests explicitly marked to skip auth
    if (options.extra['skipAuth'] == true) {
      handler.next(options);
      return;
    }
    // Inject Bearer token if available
    final token = await storage.getAccessToken();
    if (token != null && token.isNotEmpty) {
      options.headers['Authorization'] = 'Bearer $token';
    }
    handler.next(options);
  }

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    final statusCode = err.response?.statusCode;
    final isSkipAuth = err.requestOptions.extra['skipAuth'] == true;
    final isAuthEndpoint = err.requestOptions.path.contains('/auth/refresh/') ||
        err.requestOptions.path.contains('/auth/customer/otp/') ||
        err.requestOptions.path.contains('/auth/logout/');

    // Only attempt refresh for 401 on non-auth endpoints
    if (statusCode != 401 || isSkipAuth || isAuthEndpoint) {
      handler.next(err);
      return;
    }

    debugPrint('[AUTH] ${err.requestOptions.method} ${err.requestOptions.path} returned 401 Unauthorized');

    // If another refresh is already in flight, await its result and retry
    if (_refreshCompleter != null) {
      debugPrint('[AUTH] Awaiting existing in-flight token refresh...');
      try {
        final newToken = await _refreshCompleter!.future;
        if (newToken != null && newToken.isNotEmpty) {
          debugPrint('[AUTH] In-flight refresh completed. Retrying request: ${err.requestOptions.path}');
          final retried = await _retryRequest(err.requestOptions, newToken);
          handler.resolve(retried);
          return;
        }
      } catch (_) {
        // Fall through to reject
      }
      handler.next(err);
      return;
    }

    // Start a new single-flight refresh sequence
    _refreshCompleter = Completer<String?>();

    try {
      final refreshToken = await storage.getRefreshToken();
      if (refreshToken == null || refreshToken.isEmpty) {
        debugPrint('[AUTH] No refresh token available in secure storage. Session expired.');
        await storage.clearAll();
        onAuthFailure?.call();
        _refreshCompleter?.complete(null);
        _refreshCompleter = null;
        handler.next(err);
        return;
      }

      debugPrint('[AUTH] Attempting silent token refresh via POST /api/auth/refresh/');
      final refreshResponse = await dio.post(
        '/api/auth/refresh/',
        data: {'refresh': refreshToken},
        options: Options(
          extra: {'skipAuth': true},
        ),
      );

      final newTokens = _extractTokens(refreshResponse.data);
      final newAccessToken = newTokens.access;
      final newRefreshToken = newTokens.refresh;

      if (newAccessToken != null && newAccessToken.isNotEmpty) {
        debugPrint('[AUTH] Token refresh successful. Storing new tokens.');
        await storage.setAccessToken(newAccessToken);
        if (newRefreshToken != null && newRefreshToken.isNotEmpty) {
          await storage.setRefreshToken(newRefreshToken);
        }

        _refreshCompleter?.complete(newAccessToken);
        _refreshCompleter = null;

        // Retry original failed request with the newly issued access token
        debugPrint('[AUTH] Retrying original request: ${err.requestOptions.path}');
        final retriedResponse = await _retryRequest(err.requestOptions, newAccessToken);
        handler.resolve(retriedResponse);
        return;
      } else {
        throw const FormatException('Refresh response did not contain a valid access token');
      }
    } on DioException catch (dioErr) {
      final refreshStatus = dioErr.response?.statusCode;
      debugPrint('[AUTH] Token refresh request failed with status: $refreshStatus, type: ${dioErr.type}');
      // Fixed 2026-08-27: this used to wipe stored tokens and force the user
      // back to the login screen on ANY explicit 401/403/400 from
      // /auth/refresh/ — which sounds correct in isolation ("the refresh
      // token was genuinely rejected"), but this backend's refresh endpoint
      // currently reads the refresh token ONLY from a cookie, not the
      // request body (confirmed backend limitation — the body-accepting
      // variant hasn't shipped yet). This client sends the refresh token in
      // the body (see the POST call above), so the backend has structurally
      // no way to read it and will reject essentially every refresh attempt
      // with a 401/400 regardless of whether the user's actual session is
      // still perfectly valid. Treating that as "log the user out" is what
      // was making every access-token expiry — including simply reopening
      // the app after it sat idle — force a fresh OTP login. Until the
      // cookie-only limitation is lifted server-side, a failed refresh here
      // can't be trusted to mean "session invalid", so it no longer clears
      // storage or force-logs-out — the one failed request just fails, and
      // the user's stored session is left alone exactly like a network
      // error already was.
      debugPrint('[AUTH] Refresh failed ($refreshStatus) — session preserved (see B01 in calservices-mobile skill: cookie-only refresh).');
      _refreshCompleter?.complete(null);
      _refreshCompleter = null;
      handler.next(err);
    } catch (e) {
      debugPrint('[AUTH] Non-Dio exception during token refresh: $e. Session preserved.');
      _refreshCompleter?.complete(null);
      _refreshCompleter = null;
      handler.next(err);
    }
  }

  /// Re-issues a failed request with the updated Bearer token.
  Future<Response<dynamic>> _retryRequest(
    RequestOptions requestOptions,
    String newAccessToken,
  ) {
    final headers = Map<String, dynamic>.from(requestOptions.headers)
      ..['Authorization'] = 'Bearer $newAccessToken';

    final options = Options(
      method: requestOptions.method,
      headers: headers,
      responseType: requestOptions.responseType,
      contentType: requestOptions.contentType,
      validateStatus: requestOptions.validateStatus,
      receiveTimeout: requestOptions.receiveTimeout,
      sendTimeout: requestOptions.sendTimeout,
      extra: requestOptions.extra,
    );

    return dio.request<dynamic>(
      requestOptions.path,
      data: requestOptions.data,
      queryParameters: requestOptions.queryParameters,
      options: options,
    );
  }

  /// Extracts access and refresh tokens from various API response shapes.
  ({String? access, String? refresh}) _extractTokens(dynamic data) {
    if (data is Map) {
      final map = Map<String, dynamic>.from(data);
      // Shape A / B: {success: true, data: {access: ..., refresh: ...}}
      if (map['data'] is Map) {
        final inner = Map<String, dynamic>.from(map['data'] as Map);
        return (
          access: inner['access']?.toString() ?? inner['auth_token']?.toString(),
          refresh: inner['refresh']?.toString() ?? inner['refresh_token']?.toString(),
        );
      }
      // Bare map: {access: ..., refresh: ...}
      return (
        access: map['access']?.toString() ?? map['auth_token']?.toString(),
        refresh: map['refresh']?.toString() ?? map['refresh_token']?.toString(),
      );
    }
    return (access: null, refresh: null);
  }
}
