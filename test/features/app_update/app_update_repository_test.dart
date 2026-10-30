import 'dart:convert';

import 'package:calservices_customer/core/errors/api_error.dart';
import 'package:calservices_customer/core/network/api_client.dart';
import 'package:calservices_customer/features/app_update/data/app_version_repository.dart';
import 'package:calservices_customer/features/app_update/domain/app_update_models.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'fakes.dart';

class _Adapter implements HttpClientAdapter {
  _Adapter(this.respond);
  final Future<ResponseBody> Function(RequestOptions) respond;
  RequestOptions? last;

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<List<int>>? requestStream, Future<void>? cancelFuture) {
    last = options;
    return respond(options);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody _json(Map<String, dynamic> body, [int status = 200]) =>
    ResponseBody.fromString(jsonEncode(body), status, headers: {
      Headers.contentTypeHeader: ['application/json'],
    });

Map<String, dynamic> _payload({String status = 'UPDATE_AVAILABLE', bool mandatory = false, String mode = 'flexible'}) => {
      'success': true,
      'data': {
        'status': status,
        'update_available': status != 'UP_TO_DATE',
        'mandatory': mandatory,
        'update_mode': mode,
        'latest': {'version_name': '1.2.0', 'build': 20},
        'minimum_supported': {'version_name': '1.0.0', 'build': 10},
        'release': {'title': 'Faster bookings', 'notes': ['Faster checkout', 'Bug fixes'], 'notes_text': 'x'},
        'store_url': 'https://play.google.com/store/apps/details?id=com.caldim.sevo_customer',
      },
      'message': 'Success.',
    };

AppVersionRepository _repo(_Adapter adapter) {
  final dio = Dio(BaseOptions(baseUrl: 'https://example.test/api/'))..httpClientAdapter = adapter;
  return AppVersionRepository(api: ApiClient.withDio(dio));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PackageInfoReader (installed version / build detection)', () {
    test('reads version, build number and package id from the platform', () async {
      PackageInfo.setMockInitialValues(
        appName: 'SEVO', packageName: 'com.caldim.sevo_customer', version: '1.0.9', buildNumber: '10', buildSignature: '',
      );
      final app = await const PackageInfoReader().read();
      expect(app.versionName, '1.0.9');
      expect(app.buildNumber, 10);
      expect(app.packageName, 'com.caldim.sevo_customer');
    });

    test('a non-numeric build number reads as 0 (never a hard-coded value)', () async {
      PackageInfo.setMockInitialValues(
        appName: 'SEVO', packageName: 'a.b', version: '1.0.0', buildNumber: 'abc', buildSignature: '',
      );
      expect((await const PackageInfoReader().read()).buildNumber, 0);
    });
  });

  group('VersionPolicy.tryParse', () {
    test('parses a complete answer', () {
      final p = VersionPolicy.tryParse(_payload(status: 'UPDATE_REQUIRED', mandatory: true, mode: 'immediate')['data'])!;
      expect(p.status, VersionStatus.updateRequired);
      expect(p.mandatory, isTrue);
      expect(p.updateMode, 'immediate');
      expect(p.latestBuild, 20);
      expect(p.minimumBuild, 10);
      expect(p.releaseNotes, ['Faster checkout', 'Bug fixes']);
      expect(p.storeUrl, contains('play.google.com'));
    });

    test('rejects malformed or contradictory data', () {
      expect(VersionPolicy.tryParse(null), isNull);
      expect(VersionPolicy.tryParse('nope'), isNull);
      expect(VersionPolicy.tryParse({'status': 'WHATEVER'}), isNull);
      expect(VersionPolicy.tryParse({'status': 'UPDATE_REQUIRED', 'mandatory': false}), isNull);
    });

    test('tolerates missing optional parts', () {
      final p = VersionPolicy.tryParse({'status': 'NOT_CONFIGURED'})!;
      expect(p.status, VersionStatus.notConfigured);
      expect(p.mandatory, isFalse);
      expect(p.releaseNotes, isEmpty);
    });
  });

  group('AppVersionRepository', () {
    test('sends platform, application id, build and version, and parses the answer', () async {
      final adapter = _Adapter((_) async => _json(_payload()));
      final result = await _repo(adapter).check(installedApp(10));
      expect(result, isA<Success<VersionPolicy>>());
      final q = adapter.last!.queryParameters;
      expect(q['platform'], 'android');
      expect(q['application_id'], 'com.caldim.sevo_customer');
      expect(q['build'], 10);
      expect(q['version'], '1.0.9');
      expect(adapter.last!.path, contains('mobile/version-check'));
    });

    test('sends the anonymous install id when available, omits it when not', () async {
      final adapter = _Adapter((_) async => _json(_payload()));
      final dio = Dio(BaseOptions(baseUrl: 'https://example.test/api/'))..httpClientAdapter = adapter;
      await AppVersionRepository(api: ApiClient.withDio(dio), installId: () async => 'abcdef1234567890').check(installedApp(10));
      expect(adapter.last!.queryParameters['device_id'], 'abcdef1234567890');
      await AppVersionRepository(api: ApiClient.withDio(dio), installId: () async => throw StateError('x')).check(installedApp(10));
      expect(adapter.last!.queryParameters.containsKey('device_id'), isFalse);
    });

    test('backend error answer becomes a Failure', () async {
      final adapter = _Adapter((_) async => _json({'success': false, 'message': 'bad'}, 400));
      expect(await _repo(adapter).check(installedApp(10)), isA<Failure<VersionPolicy>>());
    });

    test('invalid response body becomes a ParseError Failure', () async {
      final adapter = _Adapter((_) async => _json({'success': true, 'data': {'status': 'GARBAGE'}}));
      final result = await _repo(adapter).check(installedApp(10));
      expect(result, isA<Failure<VersionPolicy>>());
      expect((result as Failure<VersionPolicy>).error, isA<ParseError>());
    });

    test('internet unavailable becomes a Failure (never throws)', () async {
      final adapter = _Adapter((o) async => throw DioException(requestOptions: o, type: DioExceptionType.connectionError));
      expect(await _repo(adapter).check(installedApp(10)), isA<Failure<VersionPolicy>>());
    });

    test('a timeout becomes a Failure (startup is never held up)', () async {
      final adapter = _Adapter((o) async => throw DioException(requestOptions: o, type: DioExceptionType.receiveTimeout));
      expect(await _repo(adapter).check(installedApp(10)), isA<Failure<VersionPolicy>>());
    });
  });
}
