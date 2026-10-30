import 'dart:convert';

import 'package:calservices_customer/core/network/auth_interceptor.dart';
import 'package:calservices_customer/core/network/retry_interceptor.dart';
import 'package:calservices_customer/core/network/session_interceptors.dart';
import 'package:calservices_customer/core/storage/secure_storage.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

class _Adapter implements HttpClientAdapter {
  _Adapter(this.respond);
  final Future<ResponseBody> Function(RequestOptions, int call) respond;
  final List<RequestOptions> calls = [];

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<List<int>>? requestStream, Future<void>? cancelFuture) {
    calls.add(options);
    return respond(options, calls.length);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody _json(Object body, int status) => ResponseBody.fromString(jsonEncode(body), status, headers: {
      Headers.contentTypeHeader: ['application/json'],
    });

class _Storage extends SecureStorage {
  bool cleared = false;
  @override
  Future<void> clearAll() async => cleared = true;
  @override
  Future<String?> getAccessToken() async => 'access';
  @override
  Future<String?> getRefreshToken() async => 'refresh';
}

DioException _net(RequestOptions o) => DioException(requestOptions: o, type: DioExceptionType.connectionError);

Dio _dio(_Adapter a, {List<Duration> delays = const [Duration.zero, Duration.zero, Duration.zero]}) {
  final dio = Dio(BaseOptions(baseUrl: 'https://example.test'))..httpClientAdapter = a;
  dio.interceptors.add(RetryInterceptor(dio: dio, delays: delays));
  return dio;
}

void main() {
  group('RetryInterceptor', () {
    test('a flaky GET succeeds on retry', () async {
      final a = _Adapter((o, n) async => n < 3 ? throw _net(o) : _json({'ok': true}, 200));
      final r = await _dio(a).get('/api/x/');
      expect(r.statusCode, 200);
      expect(a.calls, hasLength(3));
    });

    test('gives up after three retries', () async {
      final a = _Adapter((o, n) async => throw _net(o));
      await expectLater(_dio(a).get('/api/x/'), throwsA(isA<DioException>()));
      expect(a.calls, hasLength(4)); // first try + 3 retries
    });

    test('a plain POST is never retried', () async {
      final a = _Adapter((o, n) async => throw _net(o));
      await expectLater(_dio(a).post('/api/booking/', data: {}), throwsA(isA<DioException>()));
      expect(a.calls, hasLength(1));
    });

    test('a POST with an Idempotency-Key is retried', () async {
      final a = _Adapter((o, n) async => n < 2 ? throw _net(o) : _json({'ok': true}, 200));
      final r = await _dio(a).post('/api/booking/', data: {}, options: Options(headers: {'Idempotency-Key': 'k1'}));
      expect(r.statusCode, 200);
      expect(a.calls, hasLength(2));
    });

    test('payment requests are never retried, even with a key', () async {
      final a = _Adapter((o, n) async => throw _net(o));
      await expectLater(
        _dio(a).post('/api/payments/intent/', data: {}, options: Options(headers: {'Idempotency-Key': 'k'})),
        throwsA(isA<DioException>()),
      );
      expect(a.calls, hasLength(1));
    });

    test('4xx is not retried; 502 is', () async {
      final a400 = _Adapter((o, n) async => _json({'detail': 'no'}, 400));
      await expectLater(_dio(a400).get('/api/x/'), throwsA(isA<DioException>()));
      expect(a400.calls, hasLength(1));

      final a502 = _Adapter((o, n) async => n == 1 ? _json({}, 502) : _json({'ok': 1}, 200));
      expect((await _dio(a502).get('/api/x/')).statusCode, 200);
      expect(a502.calls, hasLength(2));
    });

    test('503 MAINTENANCE is not retried but a plain 503 is', () async {
      final m = _Adapter((o, n) async => _json({'code': 'MAINTENANCE'}, 503));
      await expectLater(_dio(m).get('/api/x/'), throwsA(isA<DioException>()));
      expect(m.calls, hasLength(1));

      final p = _Adapter((o, n) async => n == 1 ? _json({}, 503) : _json({'ok': 1}, 200));
      expect((await _dio(p).get('/api/x/')).statusCode, 200);
    });

    test('skipRetry is honoured', () async {
      final a = _Adapter((o, n) async => throw _net(o));
      await expectLater(_dio(a).get('/api/x/', options: Options(extra: {'skipRetry': true})), throwsA(isA<DioException>()));
      expect(a.calls, hasLength(1));
    });

    test('waits between attempts (back-off)', () async {
      final a = _Adapter((o, n) async => n < 3 ? throw _net(o) : _json({'ok': 1}, 200));
      final sw = Stopwatch()..start();
      await _dio(a, delays: const [Duration(milliseconds: 60), Duration(milliseconds: 60), Duration(milliseconds: 60)]).get('/api/x/');
      expect(sw.elapsedMilliseconds, greaterThanOrEqualTo(110));
    });
  });

  group('DeviceIdInterceptor', () {
    test('adds X-Device-Id and tolerates a failing store', () async {
      final a = _Adapter((o, n) async => _json({'ok': 1}, 200));
      final dio = Dio(BaseOptions(baseUrl: 'https://example.test'))
        ..httpClientAdapter = a
        ..interceptors.add(DeviceIdInterceptor(() async => 'abcdef1234567890'));
      await dio.get('/api/x/');
      expect(a.calls.single.headers['X-Device-Id'], 'abcdef1234567890');

      final b = _Adapter((o, n) async => _json({'ok': 1}, 200));
      final dio2 = Dio(BaseOptions(baseUrl: 'https://example.test'))
        ..httpClientAdapter = b
        ..interceptors.add(DeviceIdInterceptor(() async => throw StateError('no storage')));
      expect((await dio2.get('/api/x/')).statusCode, 200);
      expect(b.calls.single.headers.containsKey('X-Device-Id'), isFalse);
    });
  });

  group('SessionRevokedInterceptor', () {
    test('401 SESSION_REVOKED signs out without trying a token refresh', () async {
      final storage = _Storage();
      var revokedCalls = 0;
      final a = _Adapter((o, n) async => _json({'code': 'SESSION_REVOKED', 'message': 'x'}, 401));
      final dio = Dio(BaseOptions(baseUrl: 'https://example.test'))..httpClientAdapter = a;
      dio.interceptors.addAll([
        SessionRevokedInterceptor(storage: storage, onRevoked: () => revokedCalls++),
        AuthInterceptor(storage: storage, dio: dio),
      ]);
      SessionNotice.message.value = null;
      await expectLater(dio.get('/api/bookings/'), throwsA(isA<DioException>()));
      expect(storage.cleared, isTrue);
      expect(revokedCalls, 1);
      expect(SessionNotice.message.value, SessionNotice.revoked);
      expect(a.calls.where((c) => c.path.contains('/auth/refresh/')), isEmpty);
      expect(a.calls, hasLength(1));
    });

    test('an ordinary 401 is left to the normal refresh path (no revoke)', () async {
      final storage = _Storage();
      var revoked = 0;
      final a = _Adapter((o, n) async => _json({'detail': 'expired'}, 401));
      final dio = Dio(BaseOptions(baseUrl: 'https://example.test'))..httpClientAdapter = a;
      dio.interceptors.add(SessionRevokedInterceptor(storage: storage, onRevoked: () => revoked++));
      await expectLater(dio.get('/api/bookings/'), throwsA(isA<DioException>()));
      expect(revoked, 0);
      expect(storage.cleared, isFalse);
    });
  });
}
