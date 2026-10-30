import 'package:calservices_customer/core/network/api_client.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('server timeouts are applied, and out-of-range values are ignored', () {
    final dio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(seconds: 30),
      sendTimeout: const Duration(seconds: 30),
    ));
    final api = ApiClient.withDio(dio);

    api.applyTimeouts(connectSeconds: 10, receiveSeconds: 20, uploadSeconds: 45);
    expect(dio.options.connectTimeout, const Duration(seconds: 10));
    expect(dio.options.receiveTimeout, const Duration(seconds: 20));
    expect(dio.options.sendTimeout, const Duration(seconds: 45));

    api.applyTimeouts(connectSeconds: 0, receiveSeconds: 9999, uploadSeconds: null);
    expect(dio.options.connectTimeout, const Duration(seconds: 10));
    expect(dio.options.receiveTimeout, const Duration(seconds: 20));
    expect(dio.options.sendTimeout, const Duration(seconds: 45));
  });
}
