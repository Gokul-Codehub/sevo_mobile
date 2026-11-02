import 'package:calservices_customer/core/errors/api_error.dart';
import 'package:calservices_customer/core/network/api_client.dart';
import 'package:calservices_customer/features/tracking/data/call_service.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _Repo extends CallRepository {
  _Repo(this.result) : super(api: ApiClient.withDio(Dio()));
  Result<CallOutcome> result;
  final List<int> asked = [];
  @override
  Future<Result<CallOutcome>> start(int bookingId) async {
    asked.add(bookingId);
    return result;
  }
}

Future<void> tapCall(WidgetTester tester, _Repo repo, List<Uri> dialed, {int? bookingId = 12, String? number = '9123456789'}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [callRepositoryProvider.overrideWithValue(repo)],
      child: MaterialApp(
        home: Scaffold(
          body: Consumer(
            builder: (context, ref, _) => ElevatedButton(
              onPressed: () => callProfessional(
                context,
                ref,
                bookingId: bookingId,
                directNumber: number,
                launcher: (u) async {
                  dialed.add(u);
                  return true;
                },
              ),
              child: const Text('Call'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Call'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

void main() {
  testWidgets('masked bridge: no number is dialled, the customer is told the call is coming', (tester) async {
    final dialed = <Uri>[];
    final repo = _Repo(const Success(CallOutcome(CallMode.bridge, 'We are calling you now. Pick up to be connected.')));
    await tapCall(tester, repo, dialed);
    expect(repo.asked, [12]);
    expect(dialed, isEmpty);
    expect(find.textContaining('calling you now'), findsOneWidget);
    await tester.pump(const Duration(seconds: 6));
  });

  testWidgets('direct mode (masking not set up): the number is dialled like before', (tester) async {
    final dialed = <Uri>[];
    await tapCall(tester, _Repo(const Success(CallOutcome(CallMode.direct))), dialed);
    expect(dialed.single.toString(), 'tel:9123456789');
  });

  testWidgets('unavailable: nothing is dialled and the reason is shown', (tester) async {
    final dialed = <Uri>[];
    await tapCall(tester, _Repo(const Success(CallOutcome(CallMode.unavailable, 'A professional has not been assigned yet.'))), dialed);
    expect(dialed, isEmpty);
    expect(find.text('A professional has not been assigned yet.'), findsOneWidget);
    await tester.pump(const Duration(seconds: 6));
  });

  testWidgets('a network failure never dials directly (it would bypass masking) and says what happened', (tester) async {
    final dialed = <Uri>[];
    await tapCall(tester, _Repo(const Failure(NetworkError())), dialed);
    expect(dialed, isEmpty);
    expect(find.textContaining('internet connection'), findsOneWidget);
    await tester.pump(const Duration(seconds: 6));
  });

  testWidgets('no booking id: falls back to the old direct dial; no number: nothing happens', (tester) async {
    final dialed = <Uri>[];
    final repo = _Repo(const Success(CallOutcome(CallMode.bridge)));
    await tapCall(tester, repo, dialed, bookingId: null);
    expect(repo.asked, isEmpty);
    expect(dialed.single.toString(), 'tel:9123456789');

    final none = <Uri>[];
    await tapCall(tester, _Repo(const Success(CallOutcome(CallMode.direct))), none, number: '  ');
    expect(none, isEmpty);
  });
}
