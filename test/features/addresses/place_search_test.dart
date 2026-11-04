import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:calservices_customer/core/errors/api_error.dart';
import 'package:calservices_customer/core/network/api_client.dart';
import 'package:calservices_customer/features/addresses/domain/place_search.dart';
import 'package:calservices_customer/features/coverage/data/coverage_repository.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

// ── What the live proxy actually answered (captured 2026-11-04) ──────────────────────────────────────────────
const _liveSuggestions = {
  'success': true,
  'data': [
    {'place_id': 'ChIJU4JTNM9wrjsR', 'main': 'Hosur Bus Stand', 'secondary': 'Dharmapuri-Bengaluru Road, Hamumanthapuram, Anna Nagar, Tamil Nadu, India'},
    {'place_id': 'ChIJVVVVVcVwrjsR', 'main': 'Hosur busstand', 'secondary': 'Hamumanthapuram, Avalapalli Hudco, Tamil Nadu, India'},
  ],
};
const _liveDetails = {
  'success': true,
  'data': {
    'lat': 12.7350668,
    'lng': 77.8274106,
    'name': 'Hosur Bus Stand',
    'address': 'Dharmapuri-Bengaluru Rd, Hamumanthapuram, Anna Nagar, Hosur, Tamil Nadu 635109, India',
    'pincode': '635109',
    'locality': 'Anna Nagar',
    'city': 'Anna Nagar',
    'state': 'Tamil Nadu',
  },
};

const hosurBusStand = PlaceDetails(
  lat: 12.7350668,
  lng: 77.8274106,
  label: 'Hosur Bus Stand',
  pincode: '635109',
  name: 'Hosur Bus Stand',
  address: 'Dharmapuri-Bengaluru Rd, Hamumanthapuram, Anna Nagar, Hosur, Tamil Nadu 635109, India',
  locality: 'Anna Nagar',
  city: 'Anna Nagar',
  state: 'Tamil Nadu',
);

class _Adapter implements HttpClientAdapter {
  _Adapter(this.handler);
  final ({int status, Object body}) Function(RequestOptions) handler;
  final List<RequestOptions> seen = [];

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    seen.add(options);
    final r = handler(options);
    return ResponseBody.fromString(jsonEncode(r.body), r.status, headers: {
      Headers.contentTypeHeader: ['application/json'],
    });
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  const s1 = PlaceSuggestion(placeId: 'p1', main: 'Hosur Bus Stand', secondary: 'Hosur');

  group('PlaceDetails turns a place into address fields', () {
    test('the town comes from the address text, not from a neighbourhood the proxy called "city"', () {
      expect(hosurBusStand.cityName, 'Hosur');
    });

    test('the street line is the name and the area, without town, state, pincode or country', () {
      expect(hosurBusStand.street, 'Hosur Bus Stand, Dharmapuri-Bengaluru Rd, Hamumanthapuram, Anna Nagar');
    });

    test('a place with no real name just gets the area', () {
      const d = PlaceDetails(
        lat: 1, lng: 1, label: 'x', pincode: '560001', name: 'Bengaluru', locality: 'Bengaluru', city: 'Bengaluru', state: 'Karnataka',
        address: 'Bengaluru, Karnataka 560001, India',
      );
      expect(d.cityName, 'Bengaluru');
      expect(d.street, '');
    });

    test('falls back to the proxy\'s own fields when the address text is unusable', () {
      const d = PlaceDetails(lat: 1, lng: 1, label: 'x', pincode: '', city: 'Hosur', locality: 'Anna Nagar', state: '', address: '');
      expect(d.cityName, 'Hosur');
      expect(d.street, '');
    });
  });

  group('PlaceSearch', () {
    late List<({String q, String session, double? lat, double? lng})> acCalls;
    late List<String> detailSessions;
    Result<List<PlaceSuggestion>> Function() acAnswer = () => const Success([s1]);
    Result<PlaceDetails> Function() detailAnswer = () => const Success(hosurBusStand);
    var n = 0;

    PlaceSearch make() {
      acCalls = [];
      detailSessions = [];
      n = 0;
      acAnswer = () => const Success([s1]);
      detailAnswer = () => const Success(hosurBusStand);
      return PlaceSearch(
        autocomplete: (q, session, lat, lng) async {
          acCalls.add((q: q, session: session, lat: lat, lng: lng));
          return acAnswer();
        },
        details: (s, session) async {
          detailSessions.add(session);
          return detailAnswer();
        },
        newToken: () => 'token-${++n}',
      );
    }

    testWidgets('waits for 3 characters, then for a 300 ms pause', (tester) async {
      final ps = make();
      ps.onChanged('ho');
      await tester.pump(const Duration(seconds: 1));
      expect(acCalls, isEmpty);
      expect(ps.status, PlaceSearchStatus.idle);

      ps.onChanged('hos');
      await tester.pump(const Duration(milliseconds: 299));
      expect(acCalls, isEmpty);
      await tester.pump(const Duration(milliseconds: 2));
      expect(acCalls.length, 1);
      expect(ps.status, PlaceSearchStatus.results);
      ps.dispose();
    });

    testWidgets('typing quickly asks once, for the final text, with the location bias', (tester) async {
      final ps = make();
      for (final t in ['hos', 'hosu', 'hosur', 'hosur b']) {
        ps.onChanged(t, lat: 12.74, lng: 77.82);
        await tester.pump(const Duration(milliseconds: 100));
      }
      await tester.pump(const Duration(milliseconds: 400));
      expect(acCalls.map((c) => c.q).toList(), ['hosur b']);
      expect((acCalls.single.lat, acCalls.single.lng), (12.74, 77.82));
      ps.dispose();
    });

    testWidgets('one session token for the whole search AND the details call, a fresh one for the next search', (tester) async {
      final ps = make();
      ps.onChanged('hos');
      await tester.pump(const Duration(milliseconds: 350));
      ps.onChanged('hosur');
      await tester.pump(const Duration(milliseconds: 350));
      expect(acCalls.map((c) => c.session).toSet(), {'token-1'});

      final d = await ps.select(s1);
      expect(d?.pincode, '635109');
      expect(detailSessions, ['token-1']); // same token as the typing that found it

      ps.onChanged('another place');
      await tester.pump(const Duration(milliseconds: 350));
      expect(acCalls.last.session, 'token-2'); // new search, new session
      ps.dispose();
    });

    testWidgets('clearing the box ends the session; the next search starts a new one', (tester) async {
      final ps = make();
      ps.onChanged('hos');
      await tester.pump(const Duration(milliseconds: 350));
      ps.onChanged('');
      expect(ps.session, isNull);
      expect(ps.status, PlaceSearchStatus.idle);
      ps.onChanged('hos');
      await tester.pump(const Duration(milliseconds: 350));
      expect(acCalls.map((c) => c.session).toList(), ['token-1', 'token-2']);
      ps.dispose();
    });

    testWidgets('no matches and "proxy unavailable" are different states, and neither throws', (tester) async {
      final ps = make();
      acAnswer = () => const Success(<PlaceSuggestion>[]);
      ps.onChanged('zzqxjkvv qqq');
      await tester.pump(const Duration(milliseconds: 350));
      expect(ps.status, PlaceSearchStatus.empty);

      acAnswer = () => Failure(UnknownError('503'));
      ps.onChanged('hosur');
      await tester.pump(const Duration(milliseconds: 350));
      expect(ps.status, PlaceSearchStatus.unavailable);
      expect(ps.suggestions, isEmpty);
      ps.dispose();
    });

    testWidgets('an answer for text the customer has since changed is ignored', (tester) async {
      final gate = Completer<Result<List<PlaceSuggestion>>>();
      var calls = 0;
      final ps = PlaceSearch(
        autocomplete: (q, session, lat, lng) {
          calls++;
          return calls == 1 ? gate.future : Future.value(const Success(<PlaceSuggestion>[PlaceSuggestion(placeId: 'new', main: 'New', secondary: '')]));
        },
        details: (s, session) async => const Success(hosurBusStand),
      );
      ps.onChanged('hos');
      await tester.pump(const Duration(milliseconds: 350)); // first request now in flight
      ps.onChanged('hosur');
      await tester.pump(const Duration(milliseconds: 350)); // second request answers
      gate.complete(const Success([s1])); // the slow first answer arrives last
      await tester.pump();
      expect(ps.suggestions.single.placeId, 'new');
      ps.dispose();
    });

    testWidgets('a failed details call returns null (manual entry carries on) and ends the session', (tester) async {
      final ps = make();
      ps.onChanged('hos');
      await tester.pump(const Duration(milliseconds: 350));
      detailAnswer = () => Failure(UnknownError('boom'));
      expect(await ps.select(s1), isNull);
      expect(ps.status, PlaceSearchStatus.unavailable);
      expect(ps.session, isNull);
      ps.dispose();
    });
  });

  group('the proxy contract (live response shapes)', () {
    CoverageRepository repo(_Adapter a) => CoverageRepository(api: ApiClient.withDio(Dio(BaseOptions(baseUrl: 'https://staging.invalid'))..httpClientAdapter = a));

    test('autocomplete sends q, session and the bias; parses the suggestions; no key anywhere', () async {
      final a = _Adapter((o) => (status: 200, body: _liveSuggestions));
      final r = await repo(a).autocomplete('hosur bus', session: 'tok123456', lat: 12.74, lng: 77.82);
      expect(r, isA<Success<List<PlaceSuggestion>>>());
      final list = (r as Success<List<PlaceSuggestion>>).data;
      expect(list.first.main, 'Hosur Bus Stand');
      expect(list.first.placeId, 'ChIJU4JTNM9wrjsR');
      final sent = a.seen.single;
      expect(sent.path, contains('/settings/places/autocomplete/'));
      expect(sent.queryParameters, {'q': 'hosur bus', 'session': 'tok123456', 'lat': 12.74, 'lng': 77.82});
      expect(sent.uri.toString().toLowerCase(), isNot(contains('key')));
    });

    test('details sends place_id and the SAME session; parses address, pincode and coordinates', () async {
      final a = _Adapter((o) => (status: 200, body: _liveDetails));
      final r = await repo(a).details(s1, session: 'tok123456');
      final d = (r as Success<PlaceDetails>).data;
      expect((d.lat, d.lng), (12.7350668, 77.8274106));
      expect(d.pincode, '635109');
      expect(d.cityName, 'Hosur');
      expect(a.seen.single.queryParameters, {'place_id': 'p1', 'session': 'tok123456'});
    });

    test('a 503 from the proxy is a Failure, not a crash', () async {
      final a = _Adapter((o) => (status: 503, body: {'success': false, 'message': 'Place search is not available right now.'}));
      expect(await repo(a).autocomplete('hosur', session: 'tok123456'), isA<Failure<List<PlaceSuggestion>>>());
      expect(await repo(a).details(s1, session: 'tok123456'), isA<Failure<PlaceDetails>>());
    });
  });
}
