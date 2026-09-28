import 'package:calservices_customer/core/network/api_client.dart';
import 'package:calservices_customer/core/storage/secure_storage.dart';
import 'package:calservices_customer/features/catalog/data/catalog_repository.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

class _RecordingInterceptor extends Interceptor {
  RequestOptions? lastRequest;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    lastRequest = options;
    handler.resolve(Response(
      requestOptions: options,
      statusCode: 200,
      data: {'success': true, 'data': []},
    ));
  }
}

void main() {
  group('CatalogRepository Category ID Query Tests', () {
    late ApiClient apiClient;
    late _RecordingInterceptor interceptor;
    late CatalogRepository repository;

    setUp(() {
      apiClient = ApiClient.create(SecureStorage());
      interceptor = _RecordingInterceptor();
      // Inject recording interceptor at index 0 to capture requests
      apiClient.dio.interceptors.insert(0, interceptor);
      repository = CatalogRepository(api: apiClient);
    });

    test('getServicesByCategory sends category_id as numeric string query param', () async {
      await repository.getServicesByCategory(
        categoryId: 15,
        categorySlug: 'ac_appliance',
        subcategorySlug: 'refrigerator',
      );

      expect(interceptor.lastRequest, isNotNull);
      expect(interceptor.lastRequest!.path, anyOf(equals('/api/catalog/services/'), equals('/catalog/services/')));
      expect(interceptor.lastRequest!.queryParameters['category_id'], equals('15'));
      expect(interceptor.lastRequest!.queryParameters['service_slug'], equals('refrigerator'));
      expect(interceptor.lastRequest!.queryParameters.containsKey('category'), isFalse);
    });

    test('getSubServicesByCategory sends category_slug query param to /catalog/sub-services/', () async {
      await repository.getSubServicesByCategory(
        categorySlug: 'ac_appliance',
      );

      expect(interceptor.lastRequest, isNotNull);
      expect(interceptor.lastRequest!.path, anyOf(equals('/api/catalog/sub-services/'), equals('/catalog/sub-services/')));
      expect(interceptor.lastRequest!.queryParameters['category_slug'], equals('ac_appliance'));
    });

    test('getServicesByCategory accurately resolves all 8 production category IDs from slug alone', () async {
      final expectations = <String, String>{
        'ac_appliance': '15',
        'electrician_plumber_carpenter': '16',
        'vegetables_groceries': '18',
        'goods_transports': '12',
        'home_cleaning': '13',
        'mason_construction': '17',
        'painting_waterproofing': '19',
        'pest_control': '14',
      };

      for (final entry in expectations.entries) {
        await repository.getServicesByCategory(categorySlug: entry.key);
        expect(interceptor.lastRequest, isNotNull);
        expect(
          interceptor.lastRequest!.queryParameters['category_id'],
          equals(entry.value),
          reason: 'Failed for category slug ${entry.key}',
        );
      }
    });
  });
}
