import 'package:dio/dio.dart';
import 'package:firebase_performance/firebase_performance.dart';
import 'package:flutter/foundation.dart';

import '../foundation/firebase_bootstrap.dart';

/// One in-flight HTTP measurement.
abstract class HttpTrace {
  Future<void> stop({int? statusCode});
}

abstract class PerformanceSink {
  Future<void> setEnabled(bool enabled);
  Future<HttpTrace?> startHttp(String method, String urlTemplate);
}

class FirebasePerformanceSink implements PerformanceSink {
  const FirebasePerformanceSink();

  @override
  Future<void> setEnabled(bool enabled) => FirebasePerformance.instance.setPerformanceCollectionEnabled(enabled);

  @override
  Future<HttpTrace?> startHttp(String method, String urlTemplate) async {
    final m = switch (method.toUpperCase()) {
      'POST' => HttpMethod.Post,
      'PUT' => HttpMethod.Put,
      'PATCH' => HttpMethod.Patch,
      'DELETE' => HttpMethod.Delete,
      'HEAD' => HttpMethod.Head,
      _ => HttpMethod.Get,
    };
    final metric = FirebasePerformance.instance.newHttpMetric(urlTemplate, m);
    await metric.start();
    return _FirebaseHttpTrace(metric);
  }
}

class _FirebaseHttpTrace implements HttpTrace {
  _FirebaseHttpTrace(this._metric);
  final HttpMetric _metric;
  @override
  Future<void> stop({int? statusCode}) async {
    if (statusCode != null) _metric.httpResponseCode = statusCode;
    await _metric.stop();
  }
}

/// API latency in Firebase Performance. URLs are reported as templates (`/api/bookings/:id/`), never
/// with ids or query strings. Off in debug, and never able to break a request.
class PerformanceMonitor {
  PerformanceMonitor({PerformanceSink? sink, Future<bool> Function()? ensureFirebase, bool? collectInThisBuild})
      : _sink = sink ?? const FirebasePerformanceSink(),
        _ensureFirebase = ensureFirebase ?? FirebaseBootstrap.ensure,
        _collect = collectInThisBuild ?? !kDebugMode;

  static final PerformanceMonitor instance = PerformanceMonitor();

  final PerformanceSink _sink;
  final Future<bool> Function() _ensureFirebase;
  final bool _collect;
  bool _ready = false;

  bool get active => _ready && _collect;

  Future<void> init() async {
    if (_ready || !_collect) return;
    try {
      if (!await _ensureFirebase()) return;
      _ready = true;
      await _sink.setEnabled(true);
    } catch (_) {}
  }

  static String template(String path) {
    final clean = path.split('?').first;
    return clean
        .split('/')
        .map((s) => RegExp(r'^\d+$').hasMatch(s) || RegExp(r'^[0-9a-fA-F-]{16,}$').hasMatch(s) ? ':id' : s)
        .join('/');
  }

  Future<HttpTrace?> startHttp(String method, String path) async {
    if (!active) return null;
    try {
      return await _sink.startHttp(method, 'https://sevo.co.in${template(path)}');
    } catch (_) {
      return null;
    }
  }
}

class PerformanceInterceptor extends Interceptor {
  PerformanceInterceptor({PerformanceMonitor? monitor}) : _monitor = monitor;
  final PerformanceMonitor? _monitor;
  static const _key = 'perfTrace';

  PerformanceMonitor get _m => _monitor ?? PerformanceMonitor.instance;

  @override
  Future<void> onRequest(RequestOptions options, RequestInterceptorHandler handler) async {
    final trace = await _m.startHttp(options.method, options.path);
    if (trace != null) options.extra[_key] = trace;
    handler.next(options);
  }

  Future<void> _finish(RequestOptions o, int? status) async {
    final trace = o.extra.remove(_key);
    if (trace is HttpTrace) {
      try {
        await trace.stop(statusCode: status);
      } catch (_) {}
    }
  }

  @override
  Future<void> onResponse(Response response, ResponseInterceptorHandler handler) async {
    await _finish(response.requestOptions, response.statusCode);
    handler.next(response);
  }

  @override
  Future<void> onError(DioException err, ErrorInterceptorHandler handler) async {
    await _finish(err.requestOptions, err.response?.statusCode);
    handler.next(err);
  }
}
