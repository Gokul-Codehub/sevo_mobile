import 'dart:convert';
import 'dart:typed_data';

import 'package:calservices_customer/core/errors/api_error.dart';
import 'package:calservices_customer/core/network/api_client.dart';
import 'package:calservices_customer/features/feedback/data/feedback_repository.dart';
import 'package:calservices_customer/features/feedback/presentation/widgets/review_photo_picker.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';

class _Adapter implements HttpClientAdapter {
  _Adapter(this.status);
  final int status;
  RequestOptions? last;
  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<List<int>>? requestStream, Future<void>? cancelFuture) async {
    last = options;
    return ResponseBody.fromString(jsonEncode({'success': true, 'data': {'id': 1}}), status, headers: {
      Headers.contentTypeHeader: ['application/json'],
    });
  }

  @override
  void close({bool force = false}) {}
}

XFile photo(String name) => XFile.fromData(Uint8List.fromList(List.filled(64, 7)), name: name, length: 64);

void main() {
  group('FeedbackRepository.uploadPhoto', () {
    test('posts multipart to the token photos endpoint', () async {
      final adapter = _Adapter(200);
      final dio = Dio(BaseOptions(baseUrl: 'https://example.test/api/', headers: {'Content-Type': 'application/json'}))..httpClientAdapter = adapter;
      final result = await FeedbackRepository(api: ApiClient.withDio(dio)).uploadPhoto('tok-1', [1, 2, 3], 'work.jpg');
      expect(result, isA<Success<bool>>());
      expect(adapter.last!.path, contains('/feedback/tok-1/photos/'));
      expect(adapter.last!.contentType, contains('multipart/form-data'));
      expect(adapter.last!.data, isA<FormData>());
    });

    test('a server refusal is a Failure, never a throw', () async {
      final dio = Dio(BaseOptions(baseUrl: 'https://example.test/api/'))..httpClientAdapter = _Adapter(400);
      final result = await FeedbackRepository(api: ApiClient.withDio(dio)).uploadPhoto('tok-1', [1], 'a.jpg');
      expect(result, isA<Failure<bool>>());
    });
  });

  group('ReviewPhotoPicker', () {
    Widget host(List<XFile> photos, ValueChanged<List<XFile>> onChanged, {Future<XFile?> Function(ImageSource)? pick}) => MaterialApp(
          home: Scaffold(body: ReviewPhotoPicker(photos: photos, onChanged: onChanged, pick: pick)),
        );

    testWidgets('empty: shows the add tile and the 3-photo hint', (tester) async {
      await tester.pumpWidget(host(const [], (_) {}));
      expect(find.text('Add photos (optional)'), findsOneWidget);
      expect(find.textContaining('Up to 3 photos'), findsOneWidget);
      expect(find.byKey(const Key('add_photo')), findsOneWidget);
    });

    testWidgets('tapping add asks camera or gallery, then adds the chosen photo', (tester) async {
      List<XFile> result = const [];
      final a = photo('a.jpg');
      await tester.pumpWidget(host(const [], (p) => result = p, pick: (_) async => a));
      await tester.tap(find.byKey(const Key('add_photo')));
      await tester.pumpAndSettle();
      expect(find.text('Take a photo'), findsOneWidget);
      await tester.tap(find.text('Choose from gallery'));
      await tester.pumpAndSettle();
      expect(result, [a]);
    });

    testWidgets('cancelling the picker adds nothing', (tester) async {
      var changed = 0;
      await tester.pumpWidget(host(const [], (_) => changed++, pick: (_) async => null));
      await tester.tap(find.byKey(const Key('add_photo')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Take a photo'));
      await tester.pumpAndSettle();
      expect(changed, 0);
    });

    testWidgets('three photos hide the add tile; a photo can be removed', (tester) async {
      final one = photo('1.jpg'), two = photo('2.jpg'), three = photo('3.jpg');
      List<XFile> current = [one, two, three];
      await tester.pumpWidget(host(current, (p) => current = p));
      expect(find.byKey(const Key('add_photo')), findsNothing);
      await tester.tap(find.byKey(const Key('remove_photo_1')));
      expect(current, [one, three]);
    });
  });
}
