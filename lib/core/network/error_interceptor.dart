import 'package:dio/dio.dart';

import '../errors/api_error.dart';

/// Converts DioExceptions into typed [ApiError] subtypes.
/// Every network failure goes through this — screens never see raw exceptions.
class ErrorInterceptor extends Interceptor {
  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    final apiError = _toApiError(err);
    // Attach the typed error to the exception for repositories to unwrap
    handler.next(
      DioException(
        requestOptions: err.requestOptions,
        response: err.response,
        type: err.type,
        error: apiError,
        message: apiError.message,
      ),
    );
  }

  ApiError _toApiError(DioException err) {
    final statusCode = err.response?.statusCode;

    switch (err.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.sendTimeout:
        return const NetworkError('Request timed out. Please try again.');

      case DioExceptionType.connectionError:
        return const NetworkError();

      case DioExceptionType.badResponse:
        return _fromStatusCode(statusCode, err.response?.data);

      case DioExceptionType.cancel:
        return const UnknownError('Request was cancelled.');

      default:
        return const UnknownError();
    }
  }

  ApiError _fromStatusCode(int? code, dynamic data) {
    if (code == null) return const UnknownError();
    switch (code) {
      case 400:
      case 422:
        return _parseValidationError(data);
      case 401:
        return const UnauthorizedError();
      case 403:
        return const ForbiddenError();
      case 404:
        return const NotFoundError();
      case 429:
        return const NetworkError('Too many requests. Please wait a moment.');
      case >= 500:
        return const ServerError();
      default:
        return const UnknownError();
    }
  }

  /// Parses DRF validation error shapes:
  ///   Shape A/B: {"success": false, "error": {"code": "...", "message": "..."}}
  ///   Shape D-a: {"detail": "..."}
  ///   Shape D-b: {"field_name": ["error message", ...], ...}
  ValidationError _parseValidationError(dynamic data) {
    if (data == null) return const ValidationError('Bad request.');

    if (data is Map) {
      final map = Map<String, dynamic>.from(data);
      // Shape A / B: {error: {message: "..."}} or {error: "..."}
      if (map['error'] is Map) {
        final errMap = map['error'] as Map;
        final msg = errMap['message']?.toString();
        if (msg != null && msg.isNotEmpty && msg != 'false' && msg != 'true') {
          return ValidationError(msg);
        }
      }
      if (map['error'] is String && (map['error'] as String).isNotEmpty && map['error'] != 'false') {
        return ValidationError(map['error'] as String);
      }
      if (map['message'] is String && (map['message'] as String).isNotEmpty && map['message'] != 'false') {
        return ValidationError(map['message'] as String);
      }

      // Shape D-a
      if (map.containsKey('detail')) {
        return ValidationError(map['detail']?.toString() ?? 'Bad request.');
      }

      // Shape D-b — field errors
      final fieldErrors = <String, List<String>>{};
      String firstMessage = 'Validation error.';
      bool isFirst = true;
      for (final entry in map.entries) {
        // Skip envelope metadata keys
        if (entry.key == 'success' || entry.key == 'meta' || entry.key == 'data' || entry.key == 'error') {
          continue;
        }
        final errors = <String>[];
        final value = entry.value;
        if (value is List) {
          for (final e in value) {
            errors.add(e.toString());
          }
        } else if (value != null) {
          errors.add(value.toString());
        }
        if (isFirst && errors.isNotEmpty) {
          firstMessage = errors.first;
          isFirst = false;
        }
        fieldErrors[entry.key] = errors;
      }
      return ValidationError(firstMessage, fieldErrors: fieldErrors);
    }

    return const ValidationError('Bad request.');
  }
}
