import 'dart:convert';

import 'package:calservices_customer/core/errors/api_error.dart';
import 'package:calservices_customer/core/foundation/announcement_host.dart';
import 'package:calservices_customer/core/foundation/error_reporter.dart';
import 'package:calservices_customer/core/foundation/feature_guard.dart';
import 'package:calservices_customer/core/foundation/foundation_controller.dart';
import 'package:calservices_customer/core/foundation/foundation_gate.dart';
import 'package:calservices_customer/core/foundation/foundation_models.dart';
import 'package:calservices_customer/core/foundation/foundation_repository.dart';
import 'package:calservices_customer/core/network/api_client.dart';
import 'package:calservices_customer/features/app_update/domain/app_update_controller.dart' show installedAppReaderProvider;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../features/app_update/fakes.dart' show FakeInstalledReader, installedApp;

Map<String, dynamic> payload({bool maintenance = false, List<String> modules = const [], Map<String, dynamic>? flags, Map<String, dynamic>? settings}) => {
      'config_version': 'abc123',
      'maintenance': {'enabled': maintenance, 'title': 'Upgrading', 'message': 'Back soon', 'eta': null, 'blocked_modules': modules},
      'flags': flags ?? {'goods_transport': false, 'wallet': true},
      'settings': settings ?? {'max_upload_mb': 25},
      'announcements': [
        {'id': 1, 'kind': 'banner', 'title': 'Diwali hours', 'body': 'x', 'severity': 'info', 'dismissible': true},
        {'id': 'bad'},
      ],
    };

class FakeRepo implements FoundationRepository {
  Result<FoundationFetch> Function() handler = () => const Failure(NetworkError());
  int calls = 0;
  String? lastEtag;
  @override
  ApiClient get api => throw UnimplementedError();
  @override
  String get appKey => 'customer';
  @override
  Future<String?> Function()? get installId => null;
  List<List<Map<String, String>>> reported = [];
  bool reportOk = true;
  @override
  Future<bool> reportErrors(List<Map<String, String>> errors, {required String version}) async {
    reported.add(errors);
    return reportOk;
  }

  @override
  Future<Result<FoundationFetch>> fetch({required String version, required int build, String? etag}) async {
    calls++;
    lastEtag = etag;
    return handler();
  }
}

class FakeCache extends FoundationCache {
  FoundationConfig? stored;
  Map<String, dynamic>? written;
  @override
  Future<FoundationConfig?> read() async => stored;
  @override
  Future<void> write(Map<String, dynamic> raw) async => written = raw;
}

Result<FoundationFetch> ok(Map<String, dynamic> p) {
  final c = FoundationConfig.tryParse(p)!;
  return Success(FoundationFetch(config: c, etag: c.version, raw: p));
}

void main() {
  group('FoundationConfig parsing and defaults', () {
    test('parses flags, settings, maintenance and announcements, skipping malformed ones', () {
      final c = FoundationConfig.tryParse(payload(maintenance: true, modules: ['goods_transport']))!;
      expect(c.flag('goods_transport'), isFalse);
      expect(c.flag('wallet'), isTrue);
      expect(c.intSetting('max_upload_mb'), 25);
      expect(c.maintenance.enabled, isTrue);
      expect(c.maintenance.blocksApp, isFalse); // module-level only
      expect(c.maintenance.blocksModule('goods_transport'), isTrue);
      expect(c.maintenance.blocksModule('grocery'), isFalse);
      expect(c.announcements.map((a) => a.title), ['Diwali hours']);
    });

    test('missing flag resolves to the caller default; missing/wrong-typed setting to the compiled default', () {
      final c = FoundationConfig.tryParse(payload(settings: {'max_upload_mb': 'huge', 'support_phone': 5}))!;
      expect(c.flag('never_sent'), isTrue);
      expect(c.flag('never_sent', orElse: false), isFalse);
      expect(c.intSetting('max_upload_mb'), 10);
      expect(c.stringSetting('support_phone'), '');
      expect(c.intSetting('api_receive_timeout_s'), 20);
      expect(c.boolSetting('crash_reporting_enabled'), isTrue);
    });

    test('garbage is rejected without throwing', () {
      expect(FoundationConfig.tryParse(null), isNull);
      expect(FoundationConfig.tryParse('x'), isNull);
      final c = FoundationConfig.tryParse({'flags': 'nope', 'maintenance': 5, 'settings': []})!;
      expect(c.maintenance.enabled, isFalse);
      expect(c.flags, isEmpty);
    });

    test('only explicit enabled=true blocks', () {
      expect(MaintenanceInfo.parse({'enabled': 'true'}).blocksApp, isFalse);
      expect(MaintenanceInfo.parse({'enabled': true}).blocksApp, isTrue);
      expect(MaintenanceInfo.parse(null).blocksApp, isFalse);
    });
  });

  group('FoundationController', () {
    late FakeRepo repo;
    late FakeCache cache;
    late DateTime now;
    late FoundationController controller;

    FoundationController make({Duration poll = const Duration(seconds: 30)}) => FoundationController(
          repository: repo,
          cache: cache,
          installedReader: FakeInstalledReader(installedApp(10)),
          clock: () => now,
          maintenancePollInterval: poll,
        );

    setUp(() {
      repo = FakeRepo();
      cache = FakeCache();
      now = DateTime(2026, 11, 1, 9);
      controller = make();
    });

    tearDown(() => controller.dispose());

    test('no server and no cache: runs on defaults and never blocks', () async {
      await controller.start();
      expect(controller.state.maintenanceBlocksApp, isFalse);
      expect(controller.state.lastFetchOk, isFalse);
      expect(controller.state.config.flag('goods_transport'), isTrue);
    });

    test('cache is applied before the network answers, and survives an outage', () async {
      cache.stored = FoundationConfig.tryParse(payload(flags: {'wallet': false}));
      await controller.start();
      expect(controller.state.config.flag('wallet'), isFalse);
      expect(controller.state.fromServer, isFalse);
    });

    test('a cached maintenance=true still blocks while offline, but an outage alone never does', () async {
      cache.stored = FoundationConfig.tryParse(payload(maintenance: true));
      await controller.start();
      expect(controller.state.maintenanceBlocksApp, isTrue);
      controller.dispose();
      controller = make();
      cache.stored = null;
      await controller.start();
      expect(controller.state.maintenanceBlocksApp, isFalse);
    });

    test('server config replaces cache and is written back', () async {
      repo.handler = () => ok(payload());
      await controller.start();
      expect(controller.state.fromServer, isTrue);
      expect(controller.state.config.intSetting('max_upload_mb'), 25);
      expect(cache.written, isNotNull);
      expect(jsonEncode(cache.written), contains('abc123'));
    });

    test('304 keeps the current config and sends the etag next time', () async {
      repo.handler = () => ok(payload());
      await controller.start();
      repo.handler = () => const Success(FoundationFetch(notModified: true));
      now = now.add(const Duration(minutes: 20));
      await controller.refresh(FoundationRefresh.resume);
      expect(repo.lastEtag, 'abc123');
      expect(controller.state.config.intSetting('max_upload_mb'), 25);
    });

    test('resume refresh is throttled to the configured interval', () async {
      repo.handler = () => ok(payload());
      await controller.start();
      expect(repo.calls, 1);
      now = now.add(const Duration(minutes: 5));
      await controller.refresh(FoundationRefresh.resume);
      expect(repo.calls, 1);
      now = now.add(const Duration(minutes: 11));
      await controller.refresh(FoundationRefresh.resume);
      expect(repo.calls, 2);
    });

    test('maintenance is polled while on and reopens by itself when it ends', () async {
      repo.handler = () => ok(payload(maintenance: true));
      controller.dispose();
      controller = make(poll: const Duration(milliseconds: 20));
      await controller.start();
      expect(controller.state.maintenanceBlocksApp, isTrue);
      repo.handler = () => ok({...payload(), 'config_version': 'def456'});
      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(controller.state.maintenanceBlocksApp, isFalse);
    });

    test('a failed refresh keeps the previous config (fail open)', () async {
      repo.handler = () => ok(payload());
      await controller.start();
      repo.handler = () => const Failure(NetworkError());
      await controller.refresh(FoundationRefresh.manual);
      expect(controller.state.config.intSetting('max_upload_mb'), 25);
      expect(controller.state.lastFetchOk, isFalse);
    });
  });

  group('FoundationGate / MaintenanceScreen', () {
    late FakeRepo repo;
    late FakeCache cache;

    Future<void> pump(WidgetTester tester) async {
      await tester.pumpWidget(ProviderScope(
        overrides: [
          foundationRepositoryProvider.overrideWithValue(repo),
          foundationCacheProvider.overrideWithValue(cache),
          installedAppReaderProvider.overrideWithValue(FakeInstalledReader(installedApp(10))),
        ],
        child: const MaterialApp(
          home: FoundationGate(child: Scaffold(body: Center(child: Text('App content')))),
        ),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
    }

    setUp(() {
      repo = FakeRepo();
      cache = FakeCache();
    });

    testWidgets('no maintenance: app is visible', (tester) async {
      repo.handler = () => ok(payload());
      await pump(tester);
      expect(find.text('App content'), findsOneWidget);
      expect(find.text('Upgrading'), findsNothing);
    });

    testWidgets('maintenance on: branded screen with the message covers the app', (tester) async {
      repo.handler = () => ok(payload(maintenance: true));
      await pump(tester);
      expect(find.text('Upgrading'), findsOneWidget);
      expect(find.text('Back soon'), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
      final pop = tester.widget<PopScope>(find.byType(PopScope).first);
      expect(pop.canPop, isFalse);
    });

    testWidgets('module-only maintenance does not cover the app', (tester) async {
      repo.handler = () => ok(payload(maintenance: true, modules: ['goods_transport']));
      await pump(tester);
      expect(find.text('Upgrading'), findsNothing);
    });

    testWidgets('server unreachable: app opens normally', (tester) async {
      await pump(tester);
      expect(find.text('App content'), findsOneWidget);
    });

    testWidgets('Try again reopens the app once maintenance is over', (tester) async {
      repo.handler = () => ok(payload(maintenance: true));
      await pump(tester);
      repo.handler = () => ok({...payload(), 'config_version': 'next'});
      await tester.tap(find.text('Try again'));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.text('Upgrading'), findsNothing);
    });

    testWidgets('renders on a small phone without overflow', (tester) async {
      tester.view.physicalSize = const Size(320, 480);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      repo.handler = () => ok(payload(maintenance: true));
      await pump(tester);
      expect(tester.takeException(), isNull);
    });
  });

  group('FeatureGuard', () {
    late FakeRepo repo;
    Future<void> pump(WidgetTester tester) async {
      await tester.pumpWidget(ProviderScope(
        overrides: [
          foundationRepositoryProvider.overrideWithValue(repo),
          foundationCacheProvider.overrideWithValue(FakeCache()),
          installedAppReaderProvider.overrideWithValue(FakeInstalledReader(installedApp(10))),
        ],
        child: MaterialApp(
          home: Consumer(builder: (context, ref, _) {
            ref.read(foundationControllerProvider.notifier).start();
            return const FeatureGuard(flag: 'goods_transport', label: 'Goods & Transport', child: Scaffold(body: Text('GT screen')));
          }),
        ),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
    }

    setUp(() => repo = FakeRepo());

    testWidgets('flag on or unknown: module is shown', (tester) async {
      repo.handler = () => ok(payload(flags: {'goods_transport': true}));
      await pump(tester);
      expect(find.text('GT screen'), findsOneWidget);
    });

    testWidgets('server unreachable: module stays available', (tester) async {
      await pump(tester);
      expect(find.text('GT screen'), findsOneWidget);
    });

    testWidgets('flag off: friendly unavailable page replaces the module', (tester) async {
      repo.handler = () => ok(payload(flags: {'goods_transport': false}));
      await pump(tester);
      expect(find.text('GT screen'), findsNothing);
      expect(find.text('Goods & Transport is temporarily unavailable'), findsOneWidget);
    });

    testWidgets('module-only maintenance also blocks it', (tester) async {
      repo.handler = () => ok(payload(maintenance: true, modules: ['goods_transport'], flags: {'goods_transport': true}));
      await pump(tester);
      expect(find.text('GT screen'), findsNothing);
    });
  });

  group('Announcements', () {
    late FakeRepo repo;
    Future<void> pump(WidgetTester tester) async {
      await tester.pumpWidget(ProviderScope(
        overrides: [
          foundationRepositoryProvider.overrideWithValue(repo),
          foundationCacheProvider.overrideWithValue(FakeCache()),
          installedAppReaderProvider.overrideWithValue(FakeInstalledReader(installedApp(10))),
          announcementStoreProvider.overrideWithValue(_MemoryAnnouncements()),
        ],
        child: const MaterialApp(home: FoundationGate(child: Scaffold(body: Text('App content')))),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
    }

    setUp(() => repo = FakeRepo());

    testWidgets('shows the banner and the app; dismiss hides it', (tester) async {
      repo.handler = () => ok(payload());
      await pump(tester);
      expect(find.text('Diwali hours'), findsOneWidget);
      expect(find.text('App content'), findsOneWidget);
      await tester.tap(find.byTooltip('Dismiss'));
      await tester.pump();
      expect(find.text('Diwali hours'), findsNothing);
    });
  });

  group('ErrorReporter', () {
    setUp(ErrorReporter.clearForTest);

    test('keeps type + short message, collapses repeats, is bounded', () {
      ErrorReporter.record(StateError('x' * 500), screen: 'home');
      ErrorReporter.record(StateError('x' * 500), screen: 'home');
      expect(ErrorReporter.pending, 1);
      for (var i = 0; i < 40; i++) {
        ErrorReporter.record('error $i');
      }
      expect(ErrorReporter.pending, ErrorReporter.maxQueued);
      final batch = ErrorReporter.drain();
      expect(batch.last['message'], contains('error 39'));
      expect(ErrorReporter.pending, 0);
    });

    test('long messages are trimmed', () {
      ErrorReporter.record('y' * 1000);
      expect(ErrorReporter.drain().single['message']!.length, lessThan(230));
    });

    test('a successful config fetch uploads queued errors; a failed upload keeps them', () async {
      final repo = FakeRepo()..handler = () => ok(payload());
      final controller = FoundationController(
        repository: repo,
        cache: FakeCache(),
        installedReader: FakeInstalledReader(installedApp(10)),
        clock: DateTime.now,
      );
      addTearDown(controller.dispose);
      ErrorReporter.record('boom');
      repo.reportOk = false;
      await controller.start();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(repo.reported, hasLength(1));
      expect(ErrorReporter.pending, 1); // restored, will retry next time
    });
  });
}

class _MemoryAnnouncements extends AnnouncementStore {
  Set<int> ids = {};
  @override
  Future<Set<int>> read() async => ids;
  @override
  Future<void> write(Set<int> v) async => ids = v;
}
