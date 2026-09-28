import 'package:calservices_customer/core/errors/api_error.dart';
import 'package:calservices_customer/core/network/api_client.dart';
import 'package:calservices_customer/features/booking/data/booking_repository.dart';
import 'package:calservices_customer/features/booking/domain/booking_models.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

class MockApiClient extends ApiClient {
  MockApiClient({required this.handler}) : super.withDio(Dio());

  final Future<Response<dynamic>> Function(String path, {Map<String, dynamic>? queryParameters, dynamic data}) handler;

  @override
  Future<Response<T>> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
  }) async {
    final res = await handler(path, queryParameters: queryParameters);
    return Response<T>(
      data: res.data as T,
      requestOptions: res.requestOptions,
      statusCode: res.statusCode,
      statusMessage: res.statusMessage,
      headers: res.headers,
    );
  }

  @override
  Future<Response<T>> post<T>(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
  }) async {
    final res = await handler(path, data: data, queryParameters: queryParameters);
    return Response<T>(
      data: res.data as T,
      requestOptions: res.requestOptions,
      statusCode: res.statusCode,
      statusMessage: res.statusMessage,
      headers: res.headers,
    );
  }
}

void main() {
  group('My Bookings Production Contract Matrix (BOOK-01 - BOOK-13)', () {
    test('BOOK-01: Authenticated user with zero bookings returns empty list', () async {
      final mock = MockApiClient(
        handler: (path, {data, queryParameters}) async {
          return Response(
            requestOptions: RequestOptions(path: path),
            statusCode: 200,
            data: {
              'success': true,
              'data': [],
              'message': '',
            },
          );
        },
      );

      final repo = BookingRepository(api: mock);
      final res = await repo.getMyBookings();

      expect(res, isA<Success<List<Booking>>>());
      expect((res as Success<List<Booking>>).data, isEmpty);
    });

    test('BOOK-02: Authenticated user with one booking parses fields accurately', () async {
      final mock = MockApiClient(
        handler: (path, {data, queryParameters}) async {
          return Response(
            requestOptions: RequestOptions(path: path),
            statusCode: 200,
            data: {
              'success': true,
              'data': [
                {
                  'id': 104,
                  'request_id': 'CAL-20260822-104',
                  'status': 'confirmed',
                  'total_amount': '499.00',
                  'advance_amount': '99.80',
                  'balance_amount': '399.20',
                  'payment_status': 'paid',
                  'available_actions': {'can_cancel': true, 'can_reschedule': true, 'can_track': false},
                  'items': [
                    {
                      'id': 228,
                      'service': {'id': 228, 'title': 'AC General Service', 'slug': 'ac-service', 'price': '499.00'},
                      'quantity': 1
                    }
                  ],
                  'scheduled_date': '2026-08-26',
                  'scheduled_time_slot': '10:00 AM - 12:00 PM',
                }
              ],
              'message': '',
            },
          );
        },
      );

      final repo = BookingRepository(api: mock);
      final res = await repo.getMyBookings();

      expect(res, isA<Success<List<Booking>>>());
      final list = (res as Success<List<Booking>>).data;
      expect(list.length, equals(1));
      expect(list.first.id, equals(104));
      expect(list.first.requestId, equals('CAL-20260822-104'));
      expect(list.first.canCancel, isTrue);
      expect(list.first.canReschedule, isTrue);
      expect(list.first.canTrack, isFalse);
    });

    test('BOOK-03: Authenticated user with multiple bookings parses all items', () async {
      final mock = MockApiClient(
        handler: (path, {data, queryParameters}) async {
          return Response(
            requestOptions: RequestOptions(path: path),
            statusCode: 200,
            data: {
              'success': true,
              'data': [
                {'id': 101, 'status': 'completed', 'total_amount': '350.00'},
                {'id': 102, 'status': 'confirmed', 'total_amount': '499.00'},
                {'id': 103, 'status': 'in_progress', 'total_amount': '120.00'},
              ],
            },
          );
        },
      );

      final repo = BookingRepository(api: mock);
      final res = await repo.getMyBookings();

      expect(res, isA<Success<List<Booking>>>());
      expect((res as Success<List<Booking>>).data.length, equals(3));
    });

    test('BOOK-04: Upcoming booking state evaluation', () async {
      final json = {'id': 1, 'status': 'confirmed', 'total_amount': '499.00'};
      final booking = Booking.fromJson(json);
      expect(booking.isUpcoming, isTrue);
      expect(booking.isCompleted, isFalse);
    });

    test('BOOK-05: Active in-progress booking with track action enabled', () async {
      final json = {
        'id': 2,
        'status': 'in_progress',
        'total_amount': '499.00',
        'available_actions': ['track', 'give_feedback'],
        'tracking_identifier': 'TRK-987654',
      };
      final booking = Booking.fromJson(json);
      expect(booking.canTrack, isTrue);
      expect(booking.trackingIdentifier, equals('TRK-987654'));
    });

    test('BOOK-06: Completed booking evaluation and canRate capability', () async {
      final json = {
        'id': 3,
        'status': 'completed',
        'total_amount': '499.00',
        'available_actions': ['rate'],
      };
      final booking = Booking.fromJson(json);
      expect(booking.isCompleted, isTrue);
      expect(booking.canRate, isTrue);
      expect(booking.canCancel, isFalse);
    });

    test('BOOK-07: Cancelled booking with reason', () async {
      final json = {
        'id': 4,
        'status': 'cancelled',
        'total_amount': '499.00',
        'cancellation_reason': 'Customer requested change of plan.',
      };
      final booking = Booking.fromJson(json);
      expect(booking.status, equals('cancelled'));
      expect(booking.isUpcoming, isFalse);
      expect(booking.cancellationReason, equals('Customer requested change of plan.'));
    });

    test('BOOK-08: Booking containing multiple items with quantity and notes', () async {
      final json = {
        'id': 5,
        'status': 'confirmed',
        'total_amount': '119.00',
        'items': [
          {
            'service': {'id': 228, 'title': 'Beetroot', 'price': '37.00'},
            'quantity': 2,
            'notes': 'Fresh batch only'
          },
          {
            'service': {'id': 229, 'title': 'Carrots', 'price': '45.00'},
            'quantity': 1,
          }
        ]
      };
      final booking = Booking.fromJson(json);
      expect(booking.items.length, equals(2));
      expect(booking.items[0].service.title, equals('Beetroot'));
      expect(booking.items[0].quantity, equals(2));
      expect(booking.items[0].customNotes, equals('Fresh batch only'));
      expect(booking.items[1].service.title, equals('Carrots'));
    });

    test('BOOK-09: Booking containing service object (DRF nested foreign-key structure)', () async {
      final json = {
        'id': 6,
        'status': 'assigned',
        'service_id': 101,
        'issue_title': 'AC General Service',
        'service_category': 15,
        'total_amount': '499.00',
        'technician': {
          'id': 501,
          'name': 'Ramesh Kumar',
          'phone': '9876543210',
          'rating': 4.95,
        }
      };
      final booking = Booking.fromJson(json);
      expect(booking.items.length, equals(1));
      expect(booking.items.first.service.title, equals('AC General Service'));
      expect(booking.technician?.name, equals('Ramesh Kumar'));
    });

    test('BOOK-10: Invalid response shape (e.g. data = string) throws ApiContractError and does NOT look successful', () async {
      final mock = MockApiClient(
        handler: (path, {data, queryParameters}) async {
          return Response(
            requestOptions: RequestOptions(path: path),
            statusCode: 200,
            data: {
              'success': true,
              'data': 'invalid_string_instead_of_list',
              'message': '',
            },
          );
        },
      );

      final repo = BookingRepository(api: mock);
      final res = await repo.getMyBookings();

      expect(res, isA<Failure<List<Booking>>>());
      final err = (res as Failure<List<Booking>>).error;
      expect(err, isA<ApiContractError>());
      expect(err.message, contains('API Contract Violation'));
      expect(err.message, contains('GET /api/booking/my-bookings/'));
    });

    test('BOOK-11: 401 response propagates UnauthorizedError', () async {
      final mock = MockApiClient(
        handler: (path, {data, queryParameters}) async {
          throw DioException(
            requestOptions: RequestOptions(path: path),
            error: const UnauthorizedError(),
            type: DioExceptionType.badResponse,
          );
        },
      );

      final repo = BookingRepository(api: mock);
      final res = await repo.getMyBookings();

      expect(res, isA<Failure<List<Booking>>>());
      expect((res as Failure<List<Booking>>).error, isA<UnauthorizedError>());
    });

    test('BOOK-12: 500 response propagates ServerError', () async {
      final mock = MockApiClient(
        handler: (path, {data, queryParameters}) async {
          throw DioException(
            requestOptions: RequestOptions(path: path),
            error: const ServerError('Internal Server Error'),
            type: DioExceptionType.badResponse,
          );
        },
      );

      final repo = BookingRepository(api: mock);
      final res = await repo.getMyBookings();

      expect(res, isA<Failure<List<Booking>>>());
      expect((res as Failure<List<Booking>>).error, isA<ServerError>());
    });

    test('BOOK-13: Network timeout propagates NetworkError', () async {
      final mock = MockApiClient(
        handler: (path, {data, queryParameters}) async {
          throw DioException(
            requestOptions: RequestOptions(path: path),
            error: const NetworkError('Connection timed out'),
            type: DioExceptionType.connectionTimeout,
          );
        },
      );

      final repo = BookingRepository(api: mock);
      final res = await repo.getMyBookings();

      expect(res, isA<Failure<List<Booking>>>());
      expect((res as Failure<List<Booking>>).error, isA<NetworkError>());
    });
  });
}
