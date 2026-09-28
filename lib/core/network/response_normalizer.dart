import 'package:decimal/decimal.dart';
import 'package:dio/dio.dart';

import '../errors/api_error.dart';

/// Response normaliser for all four CalServices API envelope shapes.
///
/// The backend returns four different shapes (per Handover Bible §14):
///   Shape A: {success, data, error, meta}     — auth/OTP
///   Shape B: {success, data, message}          — service_requests, settings
///   Shape C: bare object/array                 — catalog categories
///   Shape D: {detail} or {field: [errors]}    — DRF exceptions
///
/// NEVER put shape-detection logic in repositories or screens.
/// ALWAYS go through this normaliser.
abstract final class ResponseNormalizer {
  ResponseNormalizer._();

  /// Extracts the payload from any of the four envelope shapes.
  /// Returns [Success] with the extracted data, or [Failure] with [ParseError].
  static Result<dynamic> extractPayload(Response response) {
    final body = response.data;

    // Shape C — bare array (e.g. catalog categories)
    if (body is List) return Success(body);

    // Non-map responses that aren't lists
    if (body is! Map) {
      return const Failure(ParseError('Unexpected response body type.'));
    }

    final map = body is Map<String, dynamic> ? body : Map<String, dynamic>.from(body);

    // Shape A / B — {success: true/false, data: ...}
    if (map.containsKey('success')) {
      final isSuccess = map['success'] == true;
      if (!isSuccess) {
        final msg = _extractMessage(map);
        return Failure(ValidationError(msg));
      }
      final data = map['data'] ?? map;
      return Success(data);
    }

    // Shape D — {detail: "..."} error
    if (map.containsKey('detail')) {
      return Failure(ValidationError(map['detail']?.toString() ?? 'Error.'));
    }

    // Shape C — bare object (no success/detail key)
    return Success(map);
  }

  static String _extractMessage(Map<String, dynamic> map) {
    if (map['error'] is Map) {
      final err = map['error'] as Map;
      final msg = err['message']?.toString();
      if (msg != null &&
          msg.isNotEmpty &&
          msg != 'false' &&
          msg != 'true' &&
          msg.toLowerCase() != 'validation_error' &&
          msg.toLowerCase() != 'validation error.') {
        return msg;
      }
      if (err['details'] is Map) {
        final details = err['details'] as Map;
        final lines = <String>[];
        details.forEach((key, value) {
          if (value is List) {
            lines.add('$key: ${value.join(', ')}');
          } else {
            lines.add('$key: $value');
          }
        });
        if (lines.isNotEmpty) return lines.join('\n');
      }
    }
    if (map['error'] is String &&
        (map['error'] as String).isNotEmpty &&
        map['error'] != 'false') {
      return map['error'] as String;
    }
    if (map['message'] is String &&
        (map['message'] as String).isNotEmpty &&
        map['message'] != 'false') {
      return map['message'] as String;
    }
    if (map['detail'] is String && (map['detail'] as String).isNotEmpty) {
      return map['detail'] as String;
    }
    final fieldErrors = <String>[];
    map.forEach((key, value) {
      if (key != 'success' && key != 'status_code' && key != 'data') {
        if (value is List) {
          fieldErrors.add('$key: ${value.join(', ')}');
        } else if (value is String && value.isNotEmpty) {
          fieldErrors.add('$key: $value');
        }
      }
    });
    if (fieldErrors.isNotEmpty) {
      return fieldErrors.join('\n');
    }
    return 'Request failed.';
  }

  /// Convenience: extract and deserialize in one step.
  static Result<T> extract<T>(
    Response response,
    T Function(dynamic json) fromJson,
  ) {
    final payloadResult = extractPayload(response);
    return switch (payloadResult) {
      Failure<dynamic> f => Failure<T>(f.error),
      Success<dynamic> s => _tryParse<T>(s.data, fromJson),
    };
  }

  static Result<T> _tryParse<T>(dynamic data, T Function(dynamic) fromJson) {
    try {
      return Success(fromJson(data));
    } catch (e) {
      return Failure(ParseError('Failed to parse response: $e'));
    }
  }
}

// ── Money parser ──────────────────────────────────────────────────────────────

/// Per-field money parser per Handover Bible §14 and api-integration skill.
///
/// Different serializers return money as different types:
///   - float/int (from SerializerMethodField via float())
///   - String "499.00" (from DecimalField)
///
/// This handles ALL cases without precision loss.
///
/// NEVER use [double.parse] directly on money fields.
/// NEVER multiply by 100 for Razorpay — use the integer from the order API.
Decimal parseMoney(dynamic raw) {
  if (raw == null) {
    throw const ParseError('Money field was null.');
  }
  if (raw is int) return Decimal.fromInt(raw);
  if (raw is double) return Decimal.parse(raw.toStringAsFixed(10));
  if (raw is String) {
    if (raw.isEmpty) throw const ParseError('Money field was empty string.');
    return Decimal.parse(raw);
  }
  throw ParseError('Unexpected money type: ${raw.runtimeType}');
}

/// Returns null instead of throwing — for optional money fields.
Decimal? parseMoneyOrNull(dynamic raw) {
  if (raw == null) return null;
  try {
    return parseMoney(raw);
  } catch (_) {
    return null;
  }
}

/// Detects the ₹599.0 booking-total fallback signal.
/// See Handover Bible §8 and booking skill.
bool isBookingTotalFallback(Decimal? amount, List<dynamic>? cartData) {
  if (amount == null) return false;
  final is599 = amount == Decimal.parse('599');
  final emptyCart = cartData == null || cartData.isEmpty;
  return is599 && emptyCart;
}

// ── Integer ID & Count parser ────────────────────────────────────────────────

/// Safely parses an integer identifier or numeric count from dynamic values (int, num, or String).
int? parseIntOrNull(dynamic raw) {
  if (raw == null) return null;
  if (raw is int) return raw;
  if (raw is num) return raw.toInt();
  if (raw is String) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;
    return int.tryParse(trimmed);
  }
  return null;
}

/// Safely parses an integer, falling back to [fallback] (default 0) if null or unparseable.
int parseInt(dynamic raw, {int fallback = 0}) {
  return parseIntOrNull(raw) ?? fallback;
}

// ── Double parser ────────────────────────────────────────────────────────────

/// Safely parses a double from dynamic values (double, int, num, or String).
double? parseDoubleOrNull(dynamic raw) {
  if (raw == null) return null;
  if (raw is double) return raw;
  if (raw is num) return raw.toDouble();
  if (raw is String) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;
    return double.tryParse(trimmed);
  }
  return null;
}

/// Safely parses a double with fallback.
double parseDouble(dynamic raw, {double fallback = 0.0}) {
  return parseDoubleOrNull(raw) ?? fallback;
}

// ── Boolean parser ───────────────────────────────────────────────────────────

/// Safely parses a boolean from dynamic values (bool, num 1/0, or String "true"/"false"/"1"/"0").
bool? parseBoolOrNull(dynamic raw) {
  if (raw == null) return null;
  if (raw is bool) return raw;
  if (raw is num) return raw != 0;
  if (raw is String) {
    final lower = raw.trim().toLowerCase();
    if (lower == 'true' || lower == '1' || lower == 'yes') return true;
    if (lower == 'false' || lower == '0' || lower == 'no') return false;
  }
  return null;
}

/// Safely parses a boolean with default fallback.
bool parseBoolOrDefault(dynamic raw, [bool fallback = false]) {
  return parseBoolOrNull(raw) ?? fallback;
}

