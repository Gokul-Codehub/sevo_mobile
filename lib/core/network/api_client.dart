import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config/env.dart';
import '../../core/storage/secure_storage.dart';
import '../../features/auth/domain/auth_notifier.dart';
import 'auth_interceptor.dart';
import 'error_interceptor.dart';
import 'logging_interceptor.dart';

/// Singleton Dio client for CalServices API.
/// All HTTP requests go through this client — never instantiate Dio elsewhere.
class ApiClient {
  ApiClient._build({
    required SecureStorage storage,
    VoidCallback? onAuthFailure,
  }) {
    _dio = Dio(
      BaseOptions(
        baseUrl: Env.mediaBaseUrl,
        connectTimeout: const Duration(seconds: 30),
        receiveTimeout: const Duration(seconds: 30),
        sendTimeout: const Duration(seconds: 30),
        headers: const {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
      ),
    );

    _dio.interceptors.addAll([
      AuthInterceptor(
        storage: storage,
        dio: _dio,
        onAuthFailure: onAuthFailure,
      ),
      ErrorInterceptor(),
      if (kDebugMode) LoggingInterceptor(),
    ]);
  }

  factory ApiClient.create(SecureStorage storage, {VoidCallback? onAuthFailure}) =>
      ApiClient._build(storage: storage, onAuthFailure: onAuthFailure);

  /// Testing constructor allowing mock/recording Dio instance injection.
  ApiClient.withDio(Dio dio) : _dio = dio;

  late final Dio _dio;

  Dio get dio => _dio;

  static String _normalizePath(String path) {
    if (path.startsWith('http://') || path.startsWith('https://')) return path;
    var p = path.trim();
    while (p.startsWith('/')) {
      p = p.substring(1);
    }
    if (p.startsWith('api/')) {
      p = p.substring(4);
    }
    return '/api/$p';
  }

  // ── GET ──────────────────────────────────────────────────────────────────
  Future<Response<T>> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) =>
      _dio.get<T>(
        _normalizePath(path),
        queryParameters: queryParameters,
        options: options,
      );

  // ── POST ─────────────────────────────────────────────────────────────────
  Future<Response<T>> post<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) =>
      _dio.post<T>(
        _normalizePath(path),
        data: data,
        queryParameters: queryParameters,
        options: options,
      );

  // ── PATCH ────────────────────────────────────────────────────────────────
  Future<Response<T>> patch<T>(
    String path, {
    Object? data,
    Options? options,
  }) =>
      _dio.patch<T>(_normalizePath(path), data: data, options: options);

  // ── DELETE ───────────────────────────────────────────────────────────────
  Future<Response<T>> delete<T>(
    String path, {
    Object? data,
    Options? options,
  }) =>
      _dio.delete<T>(_normalizePath(path), data: data, options: options);
}

// ── Provider ────────────────────────────────────────────────────────────────
final apiClientProvider = Provider<ApiClient>((ref) {
  final storage = ref.watch(secureStorageProvider);
  return ApiClient._build(
    storage: storage,
    // On refresh failure: immediately emit AuthUnauthenticated so the router
    // guard redirects to login instead of silently showing "Session expired".
    onAuthFailure: () {
      try {
        ref.read(authProvider.notifier).forceUnauthenticated();
      } catch (_) {
        // Provider may be disposed during teardown — safe to ignore
      }
    },
  );
});
