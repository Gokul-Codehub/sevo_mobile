import 'dart:async';
import 'dart:math';

import 'package:dio/dio.dart';

/// Retries safe requests that failed because of the network or a gateway hiccup.
///
/// * Retried: GET / HEAD, and any write that carries an `Idempotency-Key` header (the server
///   then guarantees a repeat has no extra effect).
/// * Never retried: other writes, anything under a payment path, cancelled requests, requests marked
///   `extra: {'skipRetry': true}`, 4xx answers, and a 503 that says `MAINTENANCE`.
/// * Back-off 0.5 s, 1.5 s, 4.5 s (+ up to 20 % jitter), at most three retries.
class RetryInterceptor extends Interceptor {
  RetryInterceptor({
    required this.dio,
    this.delays = defaultDelays,
    Random? random,
  }) : _random = random ?? Random();

  static const List<Duration> defaultDelays = [
    Duration(milliseconds: 500),
    Duration(milliseconds: 1500),
    Duration(milliseconds: 4500),
  ];

  final Dio dio;
  final List<Duration> delays;
  final Random _random;

  static const _attemptKey = 'retryAttempt';

  @override
  Future<void> onError(DioException err, ErrorInterceptorHandler handler) async {
    final options = err.requestOptions;
    final attempt = (options.extra[_attemptKey] as int?) ?? 0;
    if (attempt >= delays.length || !shouldRetry(err)) {
      handler.next(err);
      return;
    }
    final base = delays[attempt];
    final jitter = Duration(milliseconds: (base.inMilliseconds * 0.2 * _random.nextDouble()).round());
    await Future<void>.delayed(base + jitter);
    try {
      final response = await dio.fetch<dynamic>(options.copyWith(extra: {...options.extra, _attemptKey: attempt + 1}));
      handler.resolve(response);
    } on DioException catch (e) {
      // The nested call already ran the full interceptor chain (including further retries).
      handler.reject(e);
    }
  }

  static bool shouldRetry(DioException err) {
    final o = err.requestOptions;
    if (o.extra['skipRetry'] == true) return false;
    if (o.path.toLowerCase().contains('payment')) return false;

    final method = o.method.toUpperCase();
    final idempotent = method == 'GET' || method == 'HEAD' || _hasIdempotencyKey(o);
    if (!idempotent) return false;

    switch (err.type) {
      case DioExceptionType.connectionError:
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.sendTimeout:
        return true;
      case DioExceptionType.badResponse:
        final status = err.response?.statusCode;
        if (status == 502 || status == 504) return true;
        if (status == 503) return !_isMaintenance(err.response?.data);
        return false;
      default:
        return false;
    }
  }

  static bool _hasIdempotencyKey(RequestOptions o) =>
      o.headers.keys.any((k) => k.toString().toLowerCase() == 'idempotency-key');

  static bool _isMaintenance(Object? body) => body is Map && body['code'] == 'MAINTENANCE';
}
