import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

/// Debug-only request/response logger.
/// NEVER logs Authorization header values or token contents.
/// Only added to Dio when [kDebugMode] is true (see api_client.dart).
class LoggingInterceptor extends Interceptor {
  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    assert(kDebugMode, 'LoggingInterceptor must only run in debug mode');
    // Log path + method only — NOT headers (would expose token)
    debugPrint('[API →] ${options.method} ${options.path}');
    handler.next(options);
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    debugPrint(
      '[API ←] ${response.statusCode} ${response.requestOptions.path}',
    );
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    debugPrint(
      '[API ✗] ${err.response?.statusCode ?? err.type} '
      '${err.requestOptions.path}: ${err.message}',
    );
    handler.next(err);
  }
}
