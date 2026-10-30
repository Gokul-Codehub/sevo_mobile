import 'package:calservices_customer/core/errors/api_error.dart';
import 'package:calservices_customer/core/network/api_client.dart';
import 'package:calservices_customer/features/account_settings/data/account_settings_repository.dart';
import 'package:calservices_customer/features/account_settings/presentation/account_settings_screens.dart';
import 'package:calservices_customer/features/account_settings/presentation/feedback_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

class FakeRepo implements AccountSettingsRepository {
  List<DeviceSession> devs = [
    DeviceSession(deviceId: 'a', model: 'Samsung SM-A546E', osVersion: 'Android 14', lastSeen: DateTime.now(), current: true),
    DeviceSession(deviceId: 'b', model: 'Google Pixel 7', osVersion: 'Android 15', lastSeen: DateTime.now().subtract(const Duration(days: 3)), current: false),
  ];
  Map<String, bool> prefs = {for (final k in kNotificationToggles.keys) k: true}..['promotional_offers'] = false;
  bool fail = false;
  final List<String> signedOut = [];
  int signedOutOthers = 0;
  final Map<String, bool> saved = {};

  @override
  ApiClient get api => throw UnimplementedError();
  @override
  Future<String?> Function()? get installId => null;
  final List<Map<String, String?>> feedback = [];
  bool feedbackOk = true;
  @override
  Future<bool> sendFeedback({required String category, required String message, String? bookingRef}) async {
    feedback.add({'category': category, 'message': message, 'booking': bookingRef});
    return feedbackOk;
  }
  @override
  Future<Result<List<DeviceSession>>> devices() async => fail ? const Failure(NetworkError()) : Success(devs);
  @override
  Future<bool> signOutDevice(String id) async {
    signedOut.add(id);
    return true;
  }

  @override
  Future<bool> signOutOthers() async {
    signedOutOthers++;
    return true;
  }

  @override
  Future<Result<Map<String, bool>>> preferences() async => fail ? const Failure(NetworkError()) : Success(prefs);
  @override
  Future<bool> setPreference(String field, bool value) async {
    saved[field] = value;
    prefs = {...prefs, field: value};
    return true;
  }
}

Widget app(FakeRepo repo, Widget screen) => ProviderScope(
      overrides: [accountSettingsRepositoryProvider.overrideWithValue(repo)],
      child: MaterialApp.router(
        routerConfig: GoRouter(routes: [GoRoute(path: '/', builder: (_, __) => screen)]),
      ),
    );

void main() {
  group('DeviceSession.tryParse', () {
    test('parses and rejects junk', () {
      expect(DeviceSession.tryParse({'device_id': 'x', 'model': 'Moto', 'current': true})!.current, isTrue);
      expect(DeviceSession.tryParse({'model': 'no id'}), isNull);
      expect(DeviceSession.tryParse('x'), isNull);
      expect(DeviceSession.tryParse({'device_id': 'x', 'model': ''})!.model, 'Unknown device');
    });
  });

  group('DevicesScreen', () {
    testWidgets('lists devices, marks this one, no sign-out on the current device', (tester) async {
      await tester.pumpWidget(app(FakeRepo(), const DevicesScreen()));
      await tester.pumpAndSettle();
      expect(find.text('Samsung SM-A546E'), findsOneWidget);
      expect(find.textContaining('This device'), findsOneWidget);
      expect(find.text('Sign out'), findsOneWidget); // only the other phone
    });

    testWidgets('signing out another device asks first, then calls the server', (tester) async {
      final repo = FakeRepo();
      await tester.pumpWidget(app(repo, const DevicesScreen()));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sign out').first);
      await tester.pumpAndSettle();
      expect(find.textContaining('Sign out Google Pixel 7?'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Sign out'));
      await tester.pumpAndSettle();
      expect(repo.signedOut, ['b']);
    });

    testWidgets('cancel does nothing', (tester) async {
      final repo = FakeRepo();
      await tester.pumpWidget(app(repo, const DevicesScreen()));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sign out').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(repo.signedOut, isEmpty);
    });

    testWidgets('sign out all others', (tester) async {
      final repo = FakeRepo();
      await tester.pumpWidget(app(repo, const DevicesScreen()));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sign out all other devices'));
      await tester.pumpAndSettle();
      expect(repo.signedOutOthers, 1);
    });

    testWidgets('load failure shows a retry, not a blank page', (tester) async {
      await tester.pumpWidget(app(FakeRepo()..fail = true, const DevicesScreen()));
      await tester.pumpAndSettle();
      expect(find.text('Try again'), findsOneWidget);
    });
  });

  group('NotificationSettingsScreen', () {
    testWidgets('shows every category with the saved state', (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(app(FakeRepo(), const NotificationSettingsScreen()));
      await tester.pumpAndSettle();
      expect(find.byType(SwitchListTile), findsNWidgets(kNotificationToggles.length));
      final promo = tester.widget<SwitchListTile>(find.widgetWithText(SwitchListTile, 'Offers & promotions'));
      expect(promo.value, isFalse);
    });

    testWidgets('turning a switch saves it to the server', (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final repo = FakeRepo();
      await tester.pumpWidget(app(repo, const NotificationSettingsScreen()));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(SwitchListTile, 'Offers & promotions'));
      await tester.pumpAndSettle();
      expect(repo.saved, {'promotional_offers': true});
    });

    testWidgets('load failure shows a retry', (tester) async {
      await tester.pumpWidget(app(FakeRepo()..fail = true, const NotificationSettingsScreen()));
      await tester.pumpAndSettle();
      expect(find.text('Try again'), findsOneWidget);
    });
  });

  group('AppFeedbackScreen', () {
    testWidgets('Send is disabled until the message has some text', (tester) async {
      await tester.pumpWidget(app(FakeRepo(), const AppFeedbackScreen()));
      await tester.pump();
      expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed, isNull);
      await tester.enterText(find.byType(TextField), 'The map does not load');
      await tester.pump();
      expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed, isNotNull);
    });

    testWidgets('sends the category and message to the server', (tester) async {
      final repo = FakeRepo();
      await tester.pumpWidget(app(repo, const AppFeedbackScreen()));
      await tester.tap(find.text('Suggestion'));
      await tester.pump();
      await tester.enterText(find.byType(TextField), 'Please add dark mode');
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Send'));
      await tester.pump();
      expect(repo.feedback.single, {'category': 'suggestion', 'message': 'Please add dark mode', 'booking': null});
    });

    testWidgets('the booking shortcut pre-selects the booking category and attaches the reference', (tester) async {
      final repo = FakeRepo();
      await tester.pumpWidget(app(repo, const AppFeedbackScreen(bookingRef: 'SEVO-42')));
      expect(find.text('About booking SEVO-42'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'Technician did not arrive');
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Send'));
      await tester.pump();
      expect(repo.feedback.single['category'], 'booking');
      expect(repo.feedback.single['booking'], 'SEVO-42');
    });
  });
}
