import 'dart:ui' show PlatformDispatcher;

import 'package:calservices_customer/core/foundation/crash_reporting.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeBackend implements CrashBackend {
  final List<bool> enabledCalls = [];
  final List<FlutterErrorDetails> flutterFatals = [];
  final List<(Object, bool)> errors = [];
  final Map<String, String> keys = {};

  @override
  Future<void> setEnabled(bool enabled) async => enabledCalls.add(enabled);
  @override
  Future<void> recordFlutterFatal(FlutterErrorDetails details) async => flutterFatals.add(details);
  @override
  Future<void> recordError(Object error, StackTrace? stack, {required bool fatal}) async => errors.add((error, fatal));
  @override
  Future<void> setKey(String key, String value) async => keys[key] = value;
}

void main() {
  late FakeBackend backend;
  late FlutterExceptionHandler? savedFlutter;
  late bool Function(Object, StackTrace)? savedPlatform;

  setUp(() {
    backend = FakeBackend();
    savedFlutter = FlutterError.onError;
    savedPlatform = PlatformDispatcher.instance.onError;
  });

  tearDown(() {
    FlutterError.onError = savedFlutter;
    PlatformDispatcher.instance.onError = savedPlatform;
  });

  CrashReporting make({bool firebaseOk = true, bool collect = true}) =>
      CrashReporting(backend: backend, ensureFirebase: () async => firebaseOk, collectInThisBuild: collect);

  test('Firebase unavailable: nothing is installed and nothing throws', () async {
    final before = FlutterError.onError;
    final c = make(firebaseOk: false);
    await c.init(version: '1.0.9', build: 10);
    expect(c.installed, isFalse);
    expect(FlutterError.onError, same(before));
    expect(backend.enabledCalls, isEmpty);
  });

  test('release: collection on, app keys set, no personal data keys', () async {
    final c = make();
    await c.init(version: '1.0.9', build: 10);
    expect(backend.enabledCalls, [true]);
    expect(backend.keys, {'app_key': 'customer', 'app_version': '1.0.9', 'build': '10'});
  });

  test('debug builds never collect', () async {
    final c = make(collect: false);
    await c.init();
    expect(backend.enabledCalls, [false]);
    FlutterError.onError!(FlutterErrorDetails(exception: StateError('x')));
    expect(backend.flutterFatals, isEmpty);
  });

  test('a Flutter error is reported and the previous handler still runs', () async {
    var previousCalled = 0;
    FlutterError.onError = (d) => previousCalled++;
    final c = make();
    await c.init();
    FlutterError.onError!(FlutterErrorDetails(exception: StateError('boom')));
    expect(previousCalled, 1);
    expect(backend.flutterFatals, hasLength(1));
  });

  test('an uncaught async error is reported as fatal and the previous verdict is kept', () async {
    PlatformDispatcher.instance.onError = (e, s) => true;
    final c = make();
    await c.init();
    final handled = PlatformDispatcher.instance.onError!(StateError('async boom'), StackTrace.current);
    expect(handled, isTrue);
    expect(backend.errors.single.$2, isTrue);
  });

  test('the remote switch turns reporting off and on', () async {
    final c = make();
    await c.init();
    await c.setRemoteEnabled(false);
    FlutterError.onError!(FlutterErrorDetails(exception: StateError('ignored')));
    expect(backend.flutterFatals, isEmpty);
    expect(backend.enabledCalls.last, isFalse);
    await c.setRemoteEnabled(true);
    FlutterError.onError!(FlutterErrorDetails(exception: StateError('counted')));
    expect(backend.flutterFatals, hasLength(1));
    expect(backend.enabledCalls.last, isTrue);
  });

  test('a remote switch received before init is honoured at init', () async {
    final c = make();
    await c.setRemoteEnabled(false);
    await c.init();
    expect(backend.enabledCalls, [false]);
  });

  test('init is idempotent (handlers are not wrapped twice)', () async {
    final c = make();
    await c.init();
    await c.init();
    FlutterError.onError!(FlutterErrorDetails(exception: StateError('once')));
    expect(backend.flutterFatals, hasLength(1));
  });

  test('non-fatal errors are recorded only when active', () async {
    final c = make();
    await c.init();
    c.recordNonFatal(StateError('handled'));
    expect(backend.errors.single.$2, isFalse);
  });
}
