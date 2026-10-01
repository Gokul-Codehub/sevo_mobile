import 'package:equatable/equatable.dart';

/// Typed API error hierarchy for CalServices.
///
/// Every network failure is converted to one of these subtypes
/// by the ResponseNormalizer — screens never see raw DioExceptions.
sealed class ApiError extends Equatable implements Exception {
  const ApiError(this.message);

  final String message;

  @override
  List<Object?> get props => [message];

  @override
  String toString() => '$runtimeType: $message';
}

/// HTTP 401 — access token expired or missing.
final class UnauthorizedError extends ApiError {
  const UnauthorizedError([super.message = 'Session expired. Please log in again.']);
}

/// HTTP 403 — authenticated but not permitted.
final class ForbiddenError extends ApiError {
  const ForbiddenError([super.message = 'You do not have permission to do this.']);
}

/// HTTP 404 — resource not found.
final class NotFoundError extends ApiError {
  const NotFoundError([super.message = 'The requested resource was not found.']);
}

/// HTTP 422 / 400 / 429 — validation and rate-limit errors from DRF.
/// [fieldErrors] maps field names to their error messages.
/// [extra] carries any additional top-level fields the backend's error
/// envelope included alongside `code`/`message` — e.g. `resend_after_seconds`
/// on an OTP rate-limit response or `attempts_remaining` on an invalid-OTP
/// response (see accounts/services.py's RateLimitError/InvalidOTPError
/// `extra={...}`). Previously this data was silently discarded by
/// [ErrorInterceptor], which only ever read `message`.
final class ValidationError extends ApiError {
  const ValidationError(
    super.message, {
    this.fieldErrors = const {},
    this.code,
    this.extra = const {},
  });

  final Map<String, List<String>> fieldErrors;
  final String? code;
  final Map<String, dynamic> extra;

  @override
  List<Object?> get props => [message, fieldErrors, code, extra];
}

/// HTTP 5xx — server-side error.
final class ServerError extends ApiError {
  const ServerError([super.message = 'Something went wrong. Please try again.']);
}

/// Network timeout or no internet connection.
final class NetworkError extends ApiError {
  const NetworkError([super.message = 'No internet connection. Please check your network.']);
}

/// Response was received but could not be parsed.
final class ParseError extends ApiError {
  const ParseError([super.message = 'Unexpected response from server.']);
}

/// Specific contract violation error when response structure violates expected endpoint schema.
final class ApiContractError extends ApiError {
  const ApiContractError({
    required this.endpoint,
    required this.expected,
    required this.actual,
  }) : super('API Contract Violation on $endpoint: expected $expected, but received $actual');

  final String endpoint;
  final String expected;
  final String actual;

  @override
  List<Object?> get props => [message, endpoint, expected, actual];
}

/// Unknown / catch-all error.
final class UnknownError extends ApiError {
  const UnknownError([super.message = 'An unexpected error occurred.']);
}

/// Result type — either a success value or an [ApiError].
sealed class Result<T> {
  const Result();
}

final class Success<T> extends Result<T> {
  const Success(this.data);
  final T data;
}

final class Failure<T> extends Result<T> {
  const Failure(this.error);
  final ApiError error;
}

extension ResultX<T> on Result<T> {
  bool get isSuccess => this is Success<T>;
  bool get isFailure => this is Failure<T>;

  T get data => (this as Success<T>).data;
  ApiError get error => (this as Failure<T>).error;

  R when<R>({
    required R Function(T data) success,
    required R Function(ApiError error) failure,
  }) =>
      switch (this) {
        Success<T> s => success(s.data),
        Failure<T> f => failure(f.error),
      };
}
