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
        // Fixed 2026-10-01: this used to discard the response body entirely
        // and return a generic "Too many requests" NetworkError — on the
        // OTP-request rate limit specifically (accounts/services.py's
        // RateLimitError, HTTP 429), that body carries the real wait time
        // (`resend_after_seconds`) and a specific message ("Please wait 42
        // seconds..."), both silently thrown away. Routing through the same
        // parser as 400/422 preserves them (see _parseValidationError's
        // `extra` map) instead of always showing a fixed 60s countdown with
        // a generic message regardless of what the server actually said.
        return _parseValidationError(data);
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
        final errMap = Map<String, dynamic>.from(map['error'] as Map);
        final msg = errMap['message']?.toString();
        if (msg != null && msg.isNotEmpty && msg != 'false' && msg != 'true') {
          // Everything besides code/message is caller-specific extra data —
          // e.g. resend_after_seconds (RateLimitError) or
          // attempts_remaining (InvalidOTPError). Carried through as-is so
          // the OTP screens can use the real values instead of a hardcoded
          // guess.
          final extra = Map<String, dynamic>.from(errMap)
            ..remove('code')
            ..remove('message');
          return ValidationError(
            msg,
            code: errMap['code']?.toString(),
            extra: extra,
          );
        }
      }
      if (map['error'] is String && (map['error'] as String).isNotEmpty && map['error'] != 'false') {
        return ValidationError(map['error'] as String);
      }

      // Fixed 2026-10-01: BookingCreateView (service_requests/views.py) and
      // other DRF-serializer-backed endpoints respond to a serializer
      // validation failure with a FIXED, generic envelope —
      //   {"success": false, "message": "Validation error.", "errors": {<field>: [<real reason>, ...]}}
      // — where `message` is always the literal placeholder string
      // "Validation error." and the actually useful per-field reason (e.g.
      // "Please provide your real name to complete the booking.", "Enter a
      // valid 10-digit phone number.", "Preferred date cannot be in the
      // past.") sits unread in `errors`. The `message` check just below
      // used to match that placeholder first and return it immediately, so
      // every distinct validation failure rendered as the exact same
      // opaque "Validation error." SnackBar no matter what was actually
      // wrong — this is why the booking-placement error looked identical
      // across separate, unrelated incidents ("we fixed this yesterday,
      // same problem today"): the generic text never changed even when the
      // real cause did. The Shape D-b loop further down never helped
      // either — it explicitly skips the literal key "error" but was never
      // told about the different key "errors" this envelope actually uses.
      // Checking this plural `errors` map first and preferring its first
      // real field message (when there is one) surfaces the true reason
      // instead.
      if (map['errors'] is Map) {
        final errorsMap = Map<String, dynamic>.from(map['errors'] as Map);
        final fieldErrors = <String, List<String>>{};
        String? firstFieldMessage;
        for (final entry in errorsMap.entries) {
          final errors = <String>[];
          final value = entry.value;
          if (value is List) {
            for (final e in value) {
              errors.add(e.toString());
            }
          } else if (value != null) {
            errors.add(value.toString());
          }
          if (errors.isNotEmpty) {
            fieldErrors[entry.key] = errors;
            firstFieldMessage ??= errors.first;
          }
        }
        if (firstFieldMessage != null && firstFieldMessage.isNotEmpty) {
          return ValidationError(
            firstFieldMessage,
            code: map['code']?.toString(),
            fieldErrors: fieldErrors,
          );
        }
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
