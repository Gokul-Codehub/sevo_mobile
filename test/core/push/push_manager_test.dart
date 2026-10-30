import 'dart:async';

import 'package:calservices_customer/core/push/push_manager.dart';
import 'package:calservices_customer/core/push/push_messaging.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../features/app_update/fakes.dart' show FakeInstalledReader, installedApp;

class FakeMessaging implements PushMessaging {
  bool ok = true;
  String? token = 'tok-1';
  bool allowed = true;
  PushMessage? initial;
  final refresh = StreamController<String>.broadcast();
  final foreground = StreamController<PushMessage>.broadcast();
  final opened = StreamController<PushMessage>.broadcast();

  @override
  Future<bool> initialize() async => ok;
  @override
  Future<String?> getToken() async => token;
  @override
  Future<bool> notificationsAllowed() async => allowed;
  @override
  Stream<String> get tokenRefresh => refresh.stream;
  @override
  Stream<PushMessage> get onForegroundMessage => foreground.stream;
  @override
  Stream<PushMessage> get onMessageOpenedApp => opened.stream;
  @override
  Future<PushMessage?> initialMessage() async => initial;
}

class FakeRepo extends PushRepository {
  FakeRepo() : super(api: null);
  final List<Map<String, Object?>> registered = [];
  int detached = 0;
  @override
  Future<bool> register({required String? token, required bool notificationsEnabled, required String version, required int build}) async {
    registered.add({'token': token, 'enabled': notificationsEnabled, 'version': version, 'build': build});
    return true;
  }

  @override
  Future<bool> detachUser() async {
    detached++;
    return true;
  }
}

void main() {
  late FakeMessaging messaging;
  late FakeRepo repo;
  late int updateChecks;
  late List<String> navigated;
  late List<List<String?>> shown;
  late PushManager manager;

  PushManager make() => PushManager(
        messaging: messaging,
        repository: repo,
        installedReader: FakeInstalledReader(installedApp(10)),
        onAppUpdate: () => updateChecks++,
        onNavigate: navigated.add,
        showLocal: (t, b, r) async => shown.add([t, b, r]),
      );

  setUp(() {
    messaging = FakeMessaging();
    repo = FakeRepo();
    updateChecks = 0;
    navigated = [];
    shown = [];
    manager = make();
  });

  tearDown(() => manager.dispose());

  Future<void> pump() => Future<void>.delayed(const Duration(milliseconds: 10));

  test('Firebase unavailable: push is off, nothing is registered, nothing throws', () async {
    messaging.ok = false;
    await manager.start();
    expect(manager.available, isFalse);
    expect(repo.registered, isEmpty);
    await manager.onSignedIn();
    await manager.onSignedOut();
    expect(repo.detached, 0);
  });

  test('registers the token with version, build and permission state', () async {
    await manager.start();
    expect(repo.registered.single, {'token': 'tok-1', 'enabled': true, 'version': '1.0.9', 'build': 10});
  });

  test('permission denied is reported, not hidden', () async {
    messaging.allowed = false;
    await manager.start();
    expect(repo.registered.single['enabled'], isFalse);
  });

  test('a refreshed token is registered again', () async {
    await manager.start();
    messaging.token = 'tok-2';
    messaging.refresh.add('tok-2');
    await pump();
    expect(repo.registered.last['token'], 'tok-2');
    expect(repo.registered, hasLength(2));
  });

  test('sign-in re-registers; sign-out detaches the user', () async {
    await manager.start();
    await manager.onSignedIn();
    expect(repo.registered, hasLength(2));
    await manager.onSignedOut();
    expect(repo.detached, 1);
  });

  test('foreground APP_UPDATE triggers an update check and no duplicate notification', () async {
    await manager.start();
    messaging.foreground.add(const PushMessage(title: 'New version', body: 'x', data: {'type': 'APP_UPDATE'}));
    await pump();
    expect(updateChecks, 1);
    expect(shown, isEmpty);
  });

  test('foreground booking push is shown locally with its route', () async {
    await manager.start();
    messaging.foreground.add(const PushMessage(title: 'Technician assigned', body: 'Ravi', data: {'route': '/bookings/42'}));
    await pump();
    expect(shown.single, ['Technician assigned', 'Ravi', '/bookings/42']);
  });

  test('tapping a push opens its route; tapping an update push checks for the update', () async {
    await manager.start();
    messaging.opened.add(const PushMessage(data: {'route': '/bookings/42'}));
    messaging.opened.add(const PushMessage(data: {'type': 'APP_UPDATE'}));
    await pump();
    expect(navigated, ['/bookings/42']);
    expect(updateChecks, 1);
  });

  test('a push that launched the app from a closed state is handled at start', () async {
    messaging.initial = const PushMessage(data: {'route': '/tracking/7'});
    await manager.start();
    expect(navigated, ['/tracking/7']);
  });

  test('routes must be in-app paths (no URLs, no protocol-relative links)', () {
    expect(PushManager.safeRoute('/bookings/1'), '/bookings/1');
    for (final bad in ['https://evil.com', '//evil.com', 'bookings/1', r'/a\b', 'javascript:alert(1)', '/x://y', null, '']) {
      expect(PushManager.safeRoute(bad), isNull, reason: '$bad');
    }
  });

  test('a malicious route in a tap is ignored', () async {
    await manager.start();
    messaging.opened.add(const PushMessage(data: {'route': 'https://evil.com'}));
    await pump();
    expect(navigated, isEmpty);
  });

  test('start is idempotent', () async {
    await manager.start();
    await manager.start();
    expect(repo.registered, hasLength(1));
  });
}
