import 'package:calservices_customer/core/errors/api_error.dart';
import 'package:calservices_customer/core/network/api_client.dart';
import 'package:calservices_customer/core/storage/secure_storage.dart';
import 'package:calservices_customer/features/account_settings/presentation/delete_account_screen.dart';
import 'package:calservices_customer/features/auth/data/auth_repository.dart';
import 'package:calservices_customer/features/auth/domain/auth_notifier.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

class _Storage extends SecureStorage {
  bool cleared = false;
  @override
  Future<void> clearAll() async => cleared = true;
  @override
  Future<void> clearCartStorage() async {}
  @override
  Future<void> clearSelectedAddress() async {}
}

class _Repo extends AuthRepository {
  _Repo() : super(api: ApiClient.withDio(Dio()), storage: _Storage());
  Result<DeletionCodeInfo> requestResult = const Success(DeletionCodeInfo(sentTo: '******3210', resendAfterSeconds: 60));
  Result<bool> confirmResult = const Success(true);
  int requests = 0;
  final List<String> confirmed = [];

  @override
  Future<Result<DeletionCodeInfo>> requestAccountDeletion() async {
    requests++;
    return requestResult;
  }

  @override
  Future<Result<bool>> confirmAccountDeletion(String otp) async {
    confirmed.add(otp);
    return confirmResult;
  }
}

Widget app(_Repo repo, {List<String>? visited}) => ProviderScope(
      overrides: [authRepositoryProvider.overrideWithValue(repo)],
      child: MaterialApp.router(
        routerConfig: GoRouter(routes: [
          GoRoute(path: '/', builder: (_, __) => const Scaffold(body: Text('HOME'))),
          GoRoute(path: '/delete', builder: (_, __) => const DeleteAccountScreen()),
          GoRoute(path: '/bookings', builder: (_, __) => const Scaffold(body: Text('MY BOOKINGS'))),
        ], initialLocation: '/delete'),
      ),
    );

void main() {
  testWidgets('step 1 explains honestly what is deleted and what is kept', (tester) async {
    await tester.pumpWidget(app(_Repo()));
    await tester.pumpAndSettle();
    expect(find.textContaining('permanently removed'), findsOneWidget);
    expect(find.textContaining('kept without your personal details'), findsOneWidget);
    expect(find.text('Send confirmation code'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('sending the code moves to step 2 and shows where it went', (tester) async {
    final repo = _Repo();
    await tester.pumpWidget(app(repo));
    await tester.tap(find.text('Send confirmation code'));
    await tester.pumpAndSettle();
    expect(repo.requests, 1);
    expect(find.textContaining('******3210'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
    // Delete button stays disabled until the 6 digits are entered
    expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Delete my account permanently')).onPressed, isNull);
    await tester.pumpWidget(const SizedBox()); // stop the resend timer
  });

  testWidgets('confirming with the code deletes and returns to Home', (tester) async {
    final repo = _Repo();
    await tester.pumpWidget(app(repo));
    await tester.tap(find.text('Send confirmation code'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '123456');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Delete my account permanently'));
    await tester.pumpAndSettle();
    expect(repo.confirmed, ['123456']);
    expect(find.text('HOME'), findsOneWidget);
  });

  testWidgets('a wrong code shows the server message and stays on the screen', (tester) async {
    final repo = _Repo()..confirmResult = const Failure(ValidationError('Wrong code. 2 attempt(s) left.', code: 'INVALID_OTP'));
    await tester.pumpWidget(app(repo));
    await tester.tap(find.text('Send confirmation code'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '000000');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Delete my account permanently'));
    await tester.pumpAndSettle();
    expect(find.text('Wrong code. 2 attempt(s) left.'), findsOneWidget);
    expect(find.text('HOME'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('an active booking blocks it, explains why, and offers My Bookings', (tester) async {
    final repo = _Repo()
      ..requestResult = const Failure(ValidationError('active', code: 'ACTIVE_ACTIVITY', extra: {'details': {'bookings': 2, 'orders': 0}}));
    await tester.pumpWidget(app(repo));
    await tester.tap(find.text('Send confirmation code'));
    await tester.pumpAndSettle();
    expect(find.text('You still have something in progress'), findsOneWidget);
    expect(find.textContaining('2 booking(s)'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    await tester.tap(find.text('View my bookings'));
    await tester.pumpAndSettle();
    expect(find.text('MY BOOKINGS'), findsOneWidget);
  });

  testWidgets('a network failure while sending the code shows a plain message, never signs out', (tester) async {
    final repo = _Repo()..requestResult = const Failure(NetworkError());
    await tester.pumpWidget(app(repo));
    await tester.tap(find.text('Send confirmation code'));
    await tester.pumpAndSettle();
    expect(find.textContaining('internet connection'), findsOneWidget);
    expect(find.text('Send confirmation code'), findsOneWidget);
  });
}
