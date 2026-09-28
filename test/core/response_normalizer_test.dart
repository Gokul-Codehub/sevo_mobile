import 'package:calservices_customer/core/errors/api_error.dart';
import 'package:calservices_customer/core/network/response_normalizer.dart';
import 'package:decimal/decimal.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ResponseNormalizer Money Parsing', () {
    test('parses integer rupee amount to Decimal', () {
      final result = parseMoney(599);
      expect(result, Decimal.parse('599'));
    });

    test('parses string rupee amount to Decimal cleanly', () {
      final result = parseMoney('499.50');
      expect(result, Decimal.parse('499.50'));
    });

    test('parses string with exact value', () {
      final result = parseMoney('1250.00');
      expect(result, Decimal.parse('1250.00'));
    });

    test('parseMoneyOrNull returns null on null input without throwing', () {
      final result = parseMoneyOrNull(null);
      expect(result, isNull);
    });
  });

  group('ResponseNormalizer DRF Shapes', () {
    test('extracts direct map data (Shape C)', () {
      final response = Response(
        requestOptions: RequestOptions(path: '/test'),
        statusCode: 200,
        data: {'id': 1, 'name': 'Plumbing'},
      );

      final result = ResponseNormalizer.extract(
        response,
        (json) => (json as Map<String, dynamic>)['name'] as String,
      );

      expect(result, isA<Success<String>>());
      expect((result as Success<String>).data, 'Plumbing');
    });

    test('extracts data envelope (Shape A/B)', () {
      final response = Response(
        requestOptions: RequestOptions(path: '/test'),
        statusCode: 200,
        data: {
          'success': true,
          'data': {'id': 2, 'title': 'AC Repair'},
        },
      );

      final result = ResponseNormalizer.extract(
        response,
        (json) => (json as Map<String, dynamic>)['title'] as String,
      );

      expect(result, isA<Success<String>>());
      expect((result as Success<String>).data, 'AC Repair');
    });

    test('extracts list results (Shape C list)', () {
      final response = Response(
        requestOptions: RequestOptions(path: '/test'),
        statusCode: 200,
        data: [
          {'id': 1, 'name': 'Electrical'},
          {'id': 2, 'name': 'Cleaning'},
        ],
      );

      final result = ResponseNormalizer.extract(
        response,
        (json) => (json as List<dynamic>)
            .map((e) => (e as Map<String, dynamic>)['name'] as String)
            .toList(),
      );

      expect(result, isA<Success<List<String>>>());
      expect((result as Success<List<String>>).data, ['Electrical', 'Cleaning']);
    });
  });
}
