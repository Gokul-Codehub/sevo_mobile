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
      // Fixed 2026-10-01 (production resolution — Authentication scope,
      // resolves B01): the backend's /auth/refresh/ now accepts the
      // refresh token from the request body as well as the cookie, and
      // returns the new access token in the JSON response body (see
      // RefreshView in accounts/views.py) — so a genuine HTTP response
      // from this endpoint now actually reflects whether the stored
      // refresh token is valid, which it structurally could not before
      // (every refresh used to fail regardless of session validity — see
      // the 2026-08-27 comment this replaces).
      //
      // A real response from the server (dioErr.response != null) — the
      // request reached /auth/refresh/ and it explicitly rejected the
      // token — is now trustworthy and means the session really is over,
      // so it's treated as one: tokens are cleared and the app is routed
      // back to login via onAuthFailure. A DioException with NO response
      // at all (connectionError/timeout — the request never reached the
      // server) is a connectivity problem, not a session problem, and must
      // not log the user out just because they were briefly offline.
      if (dioErr.response != null) {
        debugPrint('[AUTH] Refresh explicitly rejected by server ($refreshStatus) — session is genuinely over.');
        await storage.clearAll();
        onAuthFailure?.call();
      } else {
        debugPrint('[AUTH] Refresh request could not reach the server (network error) — session preserved.');
      }
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
