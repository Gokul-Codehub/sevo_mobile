import 'package:calservices_customer/core/network/auth_interceptor.dart';
import 'package:calservices_customer/core/storage/secure_storage.dart';
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AuthInterceptor Token Refresh Tests', () {
    late SecureStorage storage;
    late Dio dio;
    late AuthInterceptor interceptor;
    bool onAuthFailureCalled = false;

    setUp(() {
      FlutterSecureStorage.setMockInitialValues({});
      storage = SecureStorage();
      dio = Dio(BaseOptions(baseUrl: 'https://customer.caldimservices.online/api'));
      onAuthFailureCalled = false;
      interceptor = AuthInterceptor(
        storage: storage,
        dio: dio,
        onAuthFailure: () {
          onAuthFailureCalled = true;
        },
      );
    });

    test('onRequest injects Bearer token if present', () async {
      await storage.setAccessToken('test_access_token');
      final options = RequestOptions(path: '/catalog/categories/');
      final handler = _TestRequestInterceptorHandler();

      await interceptor.onRequest(options, handler);

      expect(options.headers['Authorization'], equals('Bearer test_access_token'));
    });

    test('onRequest skips auth header if skipAuth is true', () async {
      await storage.setAccessToken('test_access_token');
      final options = RequestOptions(
        path: '/auth/refresh/',
        extra: {'skipAuth': true},
      );
      final handler = _TestRequestInterceptorHandler();

      await interceptor.onRequest(options, handler);

      expect(options.headers.containsKey('Authorization'), isFalse);
    });

    test('onError calls onAuthFailure when no refresh token exists', () async {
      await storage.clearAll();
      final err = DioException(
        requestOptions: RequestOptions(path: '/auth/customer/addresses/'),
        response: Response(
          requestOptions: RequestOptions(path: '/auth/customer/addresses/'),
          statusCode: 401,
        ),
      );
      final handler = _TestErrorInterceptorHandler();

      await interceptor.onError(err, handler);

      expect(onAuthFailureCalled, isTrue);
      expect(handler.nextCalled, isTrue);
    });
  });
}

class _TestRequestInterceptorHandler extends RequestInterceptorHandler {
  bool nextCalled = false;

  @override
  void next(RequestOptions requestOptions) {
    nextCalled = true;
  }
}

class _TestErrorInterceptorHandler extends ErrorInterceptorHandler {
  bool nextCalled = false;
  Response? resolvedResponse;

  @override
  void next(DioException err) {
    nextCalled = true;
  }

  @override
  void resolve(Response response) {
    resolvedResponse = response;
  }
}
