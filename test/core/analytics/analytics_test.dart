import 'package:calservices_customer/core/analytics/analytics_manager.dart';
import 'package:calservices_customer/core/analytics/performance_monitor.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeSink implements AnalyticsSink {
  final List<bool> enabled = [];
  final List<(String, Map<String, Object>)> events = [];
  final Map<String, String> props = {};
  @override
  Future<void> setEnabled(bool e) async => enabled.add(e);
  @override
  Future<void> log(String event, Map<String, Object> params) async => events.add((event, params));
  @override
  Future<void> setUserProperty(String n, String v) async => props[n] = v;
}

class FakePerfSink implements PerformanceSink {
  final List<String> started = [];
  final List<int?> stopped = [];
  @override
  Future<void> setEnabled(bool e) async {}
  @override
  Future<HttpTrace?> startHttp(String method, String url) async {
    started.add('$method $url');
    return _T(stopped);
  }
}

class _T implements HttpTrace {
  _T(this.out);
  final List<int?> out;
  @override
  Future<void> stop({int? statusCode}) async => out.add(statusCode);
}

void main() {
  group('AnalyticsSanitizer', () {
    test('drops personal-data-shaped parameters and values', () {
      final out = AnalyticsSanitizer.clean({
        'service_id': 12,
        'step': 'address',
        'phone': '9876543210',
        'customer_name': 'Ravi',
        'email_used': true,
        'note': 'call me on 9876543210',
        'contact': 'a@b.com',
        'lat': 12.5,
        'ok': true,
        'empty': null,
        'long': 'x' * 200,
        'search_text': 'ac repair',
      });
      expect(out, {'service_id': 12, 'step': 'address', 'ok': 1});
    });

    test('screen names never contain ids', () {
      expect(AnalyticsSanitizer.screenName('/bookings/123/receipt?x=1'), '/bookings/:id/receipt');
      expect(AnalyticsSanitizer.screenName('/tracking/3f2b9c1e-1111-2222-3333-444455556666'), '/tracking/:id');
      expect(AnalyticsSanitizer.screenName(null), 'unknown');
    });

    test('the event catalogue has no PII-shaped names', () {
      final names = [
        AnalyticsEvents.appOpen, AnalyticsEvents.screenView, AnalyticsEvents.serviceViewed, AnalyticsEvents.cartStarted,
        AnalyticsEvents.bookingStepViewed, AnalyticsEvents.bookingSubmitted, AnalyticsEvents.bookingConfirmed,
        AnalyticsEvents.paymentStarted, AnalyticsEvents.paymentFailed, AnalyticsEvents.paymentSucceeded,
        AnalyticsEvents.trackingOpened, AnalyticsEvents.cancelTapped, AnalyticsEvents.ratingSubmitted, AnalyticsEvents.searchPerformed,
      ];
      for (final n in names) {
        expect(RegExp(r'(phone|email|name|address|otp|token)').hasMatch(n), isFalse, reason: n);
      }
    });
  });

  group('AnalyticsManager', () {
    late FakeSink sink;
    AnalyticsManager make({bool ok = true, bool collect = true}) =>
        AnalyticsManager(sink: sink, ensureFirebase: () async => ok, collectInThisBuild: collect);

    setUp(() => sink = FakeSink());

    test('Firebase unavailable: silent no-op', () async {
      final m = make(ok: false);
      await m.init();
      m.track('x');
      expect(sink.events, isEmpty);
      expect(m.active, isFalse);
    });

    test('release: events are sent with cleaned params', () async {
      final m = make();
      await m.init();
      m.track(AnalyticsEvents.bookingStepViewed, {'step': 'slot', 'phone': '123'});
      expect(sink.events.single.$1, AnalyticsEvents.bookingStepViewed);
      expect(sink.events.single.$2, {'step': 'slot'});
    });

    test('debug builds send nothing', () async {
      final m = make(collect: false);
      await m.init();
      m.track('x');
      expect(sink.events, isEmpty);
      expect(sink.enabled, [false]);
    });

    test('the remote switch turns it off and on', () async {
      final m = make();
      await m.init();
      await m.setRemoteEnabled(false);
      m.track('hidden');
      expect(sink.events, isEmpty);
      await m.setRemoteEnabled(true);
      m.track('shown');
      expect(sink.events, hasLength(1));
    });

    test('a switch received before init is honoured', () async {
      final m = make();
      await m.setRemoteEnabled(false);
      await m.init();
      expect(sink.enabled, [false]);
    });

    test('screen() reports the templated name', () async {
      final m = make();
      await m.init();
      m.screen('/bookings/55');
      expect(sink.events.single.$2, {'screen_name': '/bookings/:id'});
    });
  });

  testWidgets('route observer reports each page once, with its name', (tester) async {
    final sink = FakeSink();
    final m = AnalyticsManager(sink: sink, ensureFirebase: () async => true, collectInThisBuild: true);
    await m.init();
    final observer = AnalyticsRouteObserver(manager: m);
    await tester.pumpWidget(MaterialApp(
      navigatorObservers: [observer],
      onGenerateRoute: (s) => MaterialPageRoute(settings: s, builder: (_) => const Scaffold(body: Text('page'))),
      initialRoute: '/home',
    ));
    final nav = tester.state<NavigatorState>(find.byType(Navigator));
    nav.pushNamed('/bookings/7');
    await tester.pumpAndSettle();
    nav.pushNamed('/bookings/7');
    await tester.pumpAndSettle();
    final names = sink.events.map((e) => e.$2['screen_name']).toList();
    expect(names, ['/', '/home', '/bookings/:id']); // Flutter pushes '/' first; the repeated page is reported once
  });

  group('PerformanceMonitor / interceptor', () {
    test('templates strip ids and queries', () {
      expect(PerformanceMonitor.template('/api/bookings/42/?x=1'), '/api/bookings/:id/');
    });

    test('measures a request and records the status code', () async {
      final sink = FakePerfSink();
      final monitor = PerformanceMonitor(sink: sink, ensureFirebase: () async => true, collectInThisBuild: true);
      await monitor.init();
      final i = PerformanceInterceptor(monitor: monitor);
      final o = RequestOptions(path: '/api/bookings/9/', method: 'GET');
      final handler = _ReqHandler();
      await i.onRequest(o, handler);
      expect(sink.started.single, 'GET https://sevo.co.in/api/bookings/:id/');
      await i.onResponse(Response(requestOptions: o, statusCode: 200), _ResHandler());
      expect(sink.stopped, [200]);
    });

    test('inactive monitor adds no overhead', () async {
      final sink = FakePerfSink();
      final monitor = PerformanceMonitor(sink: sink, ensureFirebase: () async => true, collectInThisBuild: false);
      await monitor.init();
      expect(await monitor.startHttp('GET', '/x'), isNull);
      expect(sink.started, isEmpty);
    });
  });
}

class _ReqHandler extends RequestInterceptorHandler {}

class _ResHandler extends ResponseInterceptorHandler {}
