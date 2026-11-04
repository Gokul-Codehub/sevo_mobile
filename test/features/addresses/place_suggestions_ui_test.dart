import 'package:calservices_customer/core/errors/api_error.dart';
import 'package:calservices_customer/core/network/api_client.dart';
import 'package:calservices_customer/features/addresses/domain/place_search.dart';
import 'package:calservices_customer/features/addresses/presentation/screens/guest_location_picker_screen.dart';
import 'package:calservices_customer/features/addresses/presentation/widgets/place_suggestions_panel.dart';
import 'package:calservices_customer/features/coverage/data/coverage_repository.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _busStand = PlaceDetails(
  lat: 12.7350668,
  lng: 77.8274106,
  label: 'Hosur Bus Stand, Dharmapuri-Bengaluru Road',
  pincode: '635109',
  name: 'Hosur Bus Stand',
  address: 'Dharmapuri-Bengaluru Rd, Hamumanthapuram, Anna Nagar, Hosur, Tamil Nadu 635109, India',
  locality: 'Anna Nagar',
  city: 'Anna Nagar',
  state: 'Tamil Nadu',
);

const _suggestion = PlaceSuggestion(placeId: 'ChIJU4JTNM9wrjsR', main: 'Hosur Bus Stand', secondary: 'Dharmapuri-Bengaluru Road, Tamil Nadu, India');

class _FakeRepo extends CoverageRepository {
  _FakeRepo({this.fail = false, this.empty = false}) : super(api: ApiClient.withDio(Dio()));
  final bool fail;
  final bool empty;
  final List<String> sessions = [];

  @override
  Future<Result<List<PlaceSuggestion>>> autocomplete(String text, {required String session, double? lat, double? lng}) async {
    sessions.add(session);
    if (fail) return Failure(UnknownError('503'));
    return Success(empty ? const <PlaceSuggestion>[] : const [_suggestion]);
  }

  @override
  Future<Result<PlaceDetails>> details(PlaceSuggestion s, {required String session}) async {
    sessions.add(session);
    return fail ? Failure(UnknownError('503')) : const Success(_busStand);
  }
}

Future<_FakeRepo> _openGuestPicker(WidgetTester tester, {bool fail = false, bool empty = false}) async {
  final repo = _FakeRepo(fail: fail, empty: empty);
  await tester.pumpWidget(ProviderScope(
    overrides: [coverageRepositoryProvider.overrideWithValue(repo)],
    child: const MaterialApp(home: GuestLocationPickerScreen()),
  ));
  await tester.pump();
  return repo;
}

Finder get _searchBox => find.widgetWithText(TextField, 'Search your area, street or pincode');

String _text(WidgetTester tester, String label) =>
    tester.widget<TextFormField>(find.widgetWithText(TextFormField, label)).controller!.text;

void main() {
  test('the country is dropped from an Indian address', () {
    expect(withoutCountry('Hosur, Tamil Nadu 635109, India'), 'Hosur, Tamil Nadu 635109');
    expect(withoutCountry('Hosur, Tamil Nadu'), 'Hosur, Tamil Nadu');
  });

  group('location typed on the onboarding / guest screen', () {
    testWidgets('suggestions appear in the field as you type, and picking one fills the whole form', (tester) async {
      final repo = await _openGuestPicker(tester);
      await tester.enterText(_searchBox, 'hosur bus');
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pump();
      expect(find.text('Hosur Bus Stand'), findsOneWidget);

      await tester.tap(find.text('Hosur Bus Stand'));
      await tester.pump();
      await tester.pump();

      expect(_text(tester, 'Address line (house / flat / building)'), 'Hosur Bus Stand');
      expect(_text(tester, 'Area, street or landmark'), 'Hosur Bus Stand, Dharmapuri-Bengaluru Rd, Hamumanthapuram, Anna Nagar');
      expect(_text(tester, 'City'), 'Hosur'); // the proxy said "Anna Nagar"; the address text says Hosur
      expect(_text(tester, 'Pincode'), '635109');
      expect(find.text('Tamil Nadu'), findsWidgets);
      expect(repo.sessions.toSet().length, 1); // one session token: typing and the details call

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('typing fewer than 3 characters asks nothing', (tester) async {
      final repo = await _openGuestPicker(tester);
      await tester.enterText(_searchBox, 'ho');
      await tester.pump(const Duration(seconds: 1));
      expect(repo.sessions, isEmpty);
      expect(find.text('Hosur Bus Stand'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('proxy unavailable: the customer is told, and the form is still there to fill by hand', (tester) async {
      await _openGuestPicker(tester, fail: true);
      await tester.enterText(_searchBox, 'hosur bus');
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pump();
      expect(find.textContaining("Place search isn't available right now"), findsOneWidget);

      await tester.enterText(find.widgetWithText(TextFormField, 'City'), 'Hosur');
      expect(_text(tester, 'City'), 'Hosur');
      expect(find.widgetWithText(TextFormField, 'Pincode'), findsOneWidget);
      await tester.dragUntilVisible(find.text('Confirm location'), find.byType(ListView), const Offset(0, -300));
      expect(find.text('Confirm location'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('no matches: says so and points to the form', (tester) async {
      await _openGuestPicker(tester, empty: true);
      await tester.enterText(_searchBox, 'zzqxjkvv qqq');
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pump();
      expect(find.textContaining('No matching places'), findsOneWidget);
      expect(find.textContaining('Fill in the address below instead'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });
  });
}
