import 'package:equatable/equatable.dart';

import 'friendly_message.dart';

/// Typed API error hierarchy for CalServices.
///
/// Every network failure is converted to one of these subtypes
/// by the ResponseNormalizer — screens never see raw DioExceptions.
sealed class ApiError extends Equatable implements Exception {
  const ApiError(String message) : _message = message;

  final String _message;

  /// Customer-safe text: server-written sentences pass through, technical text is replaced
  /// (see [FriendlyMessage.polish]). The untouched original stays in [toString] for logs.
  String get message => FriendlyMessage.polish(_message);

  @override
  List<Object?> get props => [message];

  @override
  String toString() => '$runtimeType: $_message';
}

/// HTTP 401 — access token expired or missing.
final class UnauthorizedError extends ApiError {
  const UnauthorizedError([super.message = 'Your session has ended. Please sign in again.']);
}

/// HTTP 403 — authenticated but not permitted.
final class ForbiddenError extends ApiError {
  const ForbiddenError([super.message = "This account can't do that. Please contact support if you think this is a mistake."]);
}

/// HTTP 404 — resource not found.
final class NotFoundError extends ApiError {
  const NotFoundError([super.message = "We couldn't find that. It may have been removed or is no longer available."]);
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
  const ServerError([super.message = 'Something went wrong on our side. Please try again in a moment.']);
}

/// Network timeout or no internet connection.
final class NetworkError extends ApiError {
  const NetworkError([super.message = "We couldn't reach SEVO. Please check your internet connection and try again."]);
}

/// Response was received but could not be parsed.
final class ParseError extends ApiError {
  const ParseError([super.message = "We couldn't read the response. Please try again."]);
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
  const UnknownError([super.message = "We couldn't complete that. Please try again."]);
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
