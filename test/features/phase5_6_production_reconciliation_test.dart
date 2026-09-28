import 'package:decimal/decimal.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:calservices_customer/core/errors/api_error.dart';
import 'package:calservices_customer/core/network/api_client.dart';
import 'package:calservices_customer/core/utils/image_url_helper.dart';
import 'package:calservices_customer/features/booking/data/booking_repository.dart';
import 'package:calservices_customer/features/booking/domain/booking_models.dart';
import 'package:calservices_customer/features/catalog/domain/catalog_models.dart';
import 'package:calservices_customer/shared/widgets/app_remote_image.dart';

class _FakeApiClient extends ApiClient {
  _FakeApiClient({required this.handler}) : super.withDio(Dio());
  final Future<Response<dynamic>> Function(String path, {dynamic data, Map<String, dynamic>? queryParameters}) handler;

  @override
  Future<Response<T>> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
    ProgressCallback? onReceiveProgress,
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
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
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
  TestWidgetsFlutterBinding.ensureInitialized();

  // ──────────────────────────────────────────────────────────────────────────
  // 1. MY BOOKINGS COMPLETE CONTRACT CHAIN & EDGE CASES
  // ──────────────────────────────────────────────────────────────────────────
  group('Part 2 — My Bookings Production Contract & Resilience', () {
    test('Zero bookings: {success: true, data: []} returns Success with empty list', () async {
      final fakeApi = _FakeApiClient(
        handler: (path, {data, queryParameters}) async => Response(
          requestOptions: RequestOptions(path: path),
          statusCode: 200,
          data: {'success': true, 'data': [], 'message': ''},
        ),
      );
      final repo = BookingRepository(api: fakeApi);
      final result = await repo.getMyBookings();

      expect(result, isA<Success<List<Booking>>>());
      expect((result as Success<List<Booking>>).data, isEmpty);
    });

    test('One booking: {success: true, data: [{...}]} parses correctly', () async {
      final fakeApi = _FakeApiClient(
        handler: (path, {data, queryParameters}) async => Response(
          requestOptions: RequestOptions(path: path),
          statusCode: 200,
          data: {
            'success': true,
            'data': [
              {
                'id': 8841,
                'request_id': 'CAL-8841',
                'status': 'confirmed',
                'total_amount': '499.00',
                'scheduled_date': '2026-08-25',
                'scheduled_time_slot': '10:00 AM - 12:00 PM',
                'items': [
                  {
                    'service_id': 101,
                    'service_title': 'AC Jet Pump Service',
                    'service_slug': 'ac-jet-pump-service',
                    'quantity': 1,
                    'unit_price': '499.00',
                    'total_price': '499.00',
                  }
                ],
              }
            ],
            'message': '',
          },
        ),
      );
      final repo = BookingRepository(api: fakeApi);
      final result = await repo.getMyBookings();

      expect(result, isA<Success<List<Booking>>>());
      final bookings = (result as Success<List<Booking>>).data;
      expect(bookings.length, equals(1));
      expect(bookings.first.id, equals(8841));
      expect(bookings.first.status, equals('confirmed'));
      expect(bookings.first.isUpcoming, isTrue);
    });

    test('Multiple bookings: {success: true, data: [{...}, {...}]} parses list', () async {
      final fakeApi = _FakeApiClient(
        handler: (path, {data, queryParameters}) async => Response(
          requestOptions: RequestOptions(path: path),
          statusCode: 200,
          data: {
            'success': true,
            'data': [
              {
                'id': 8841,
                'status': 'confirmed',
                'total_amount': '499.00',
                'scheduled_date': '2026-08-25',
                'scheduled_time_slot': '10:00 AM - 12:00 PM',
              },
              {
                'id': 8842,
                'status': 'completed',
                'total_amount': '120.00',
                'scheduled_date': '2026-08-20',
                'scheduled_time_slot': '02:00 PM - 04:00 PM',
              },
            ],
          },
        ),
      );
      final repo = BookingRepository(api: fakeApi);
      final result = await repo.getMyBookings();

      expect(result, isA<Success<List<Booking>>>());
      final bookings = (result as Success<List<Booking>>).data;
      expect(bookings.length, equals(2));
      expect(bookings[0].id, equals(8841));
      expect(bookings[1].id, equals(8842));
      expect(bookings[1].isCompleted, isTrue);
    });

    test('HTTP 401 unauthenticated: returns Failure with UnauthorizedError', () async {
      final fakeApi = _FakeApiClient(
        handler: (path, {data, queryParameters}) async => throw DioException(
          requestOptions: RequestOptions(path: path),
          response: Response(
            requestOptions: RequestOptions(path: path),
            statusCode: 401,
            data: {'detail': 'Authentication credentials were not provided.'},
          ),
          error: const UnauthorizedError(),
        ),
      );
      final repo = BookingRepository(api: fakeApi);
      final result = await repo.getMyBookings();

      expect(result, isA<Failure<List<Booking>>>());
      expect((result as Failure<List<Booking>>).error, isA<UnauthorizedError>());
    });

    test('Malformed response: {random_key: 123} does NOT hide as empty list, returns Failure(ApiContractError)', () async {
      final fakeApi = _FakeApiClient(
        handler: (path, {data, queryParameters}) async => Response(
          requestOptions: RequestOptions(path: path),
          statusCode: 200,
          data: {'unexpected_structure': 999},
        ),
      );
      final repo = BookingRepository(api: fakeApi);
      final result = await repo.getMyBookings();

      expect(result, isA<Failure<List<Booking>>>());
      expect((result as Failure<List<Booking>>).error, isA<ApiContractError>());
    });

    test('Booking status tab filtering categories properly', () {
      final bUpcoming = Booking(
        id: 1,
        requestId: 'CAL-1',
        status: 'confirmed',
        scheduledDate: '2026-08-26',
        scheduledTimeSlot: '10:00 AM - 12:00 PM',
        totalAmount: Decimal.zero,
        advanceAmount: Decimal.zero,
        balanceAmount: Decimal.zero,
      );
      final bActive = Booking(
        id: 2,
        requestId: 'CAL-2',
        status: 'in_progress',
        scheduledDate: '2026-08-24',
        scheduledTimeSlot: '10:00 AM - 12:00 PM',
        totalAmount: Decimal.zero,
        advanceAmount: Decimal.zero,
        balanceAmount: Decimal.zero,
      );
      final bCompleted = Booking(
        id: 3,
        requestId: 'CAL-3',
        status: 'completed',
        scheduledDate: '2026-08-20',
        scheduledTimeSlot: '10:00 AM - 12:00 PM',
        totalAmount: Decimal.zero,
        advanceAmount: Decimal.zero,
        balanceAmount: Decimal.zero,
      );
      final bCancelled = Booking(
        id: 4,
        requestId: 'CAL-4',
        status: 'cancelled',
        scheduledDate: '2026-08-19',
        scheduledTimeSlot: '10:00 AM - 12:00 PM',
        totalAmount: Decimal.zero,
        advanceAmount: Decimal.zero,
        balanceAmount: Decimal.zero,
      );

      final list = [bUpcoming, bActive, bCompleted, bCancelled];

      // Tab 0: Upcoming
      final upcoming = list.where((b) => b.isUpcoming).toList();
      expect(upcoming.length, equals(2)); // confirmed + in_progress
      expect(upcoming.map((b) => b.id), containsAll([1, 2]));

      // Tab 1: Completed
      final completed = list.where((b) => b.isCompleted).toList();
      expect(completed.length, equals(1));
      expect(completed.first.id, equals(3));

      // Tab 2: Cancelled
      final cancelled = list.where((b) => b.isCancelled).toList();
      expect(cancelled.length, equals(1));
      expect(cancelled.first.id, equals(4));
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  // 2. CATALOG & GROCERY IMAGE-FIELD PRIORITY CONTRACT
  // ──────────────────────────────────────────────────────────────────────────
  group('Part 3 — Catalog & Grocery Image-Field Priority', () {
    test('Live Beetroot contract: image is empty, service_image is present -> resolves service_image', () {
      final beetrootJson = {
        'id': 228,
        'category': 18,
        'category_slug': 'vegetables_groceries',
        'name': 'Beetroot',
        'slug': 'veg-beetroot',
        'price': '37.00',
        'duration': '8 MINS',
        'image': '', // Empty on live backend
        'service_id': 50,
        'service_name': 'Farm-Fresh Vegetable',
        'service_slug': 'vegetables',
        'service_image': '/mockups/vegetables_realistic.png', // Present on live backend
      };

      final item = ServiceItem.fromJson(beetrootJson);
      expect(item.id, equals(228));
      expect(item.title, equals('Beetroot'));
      expect(item.price, equals(Decimal.fromInt(37)));
      expect(item.flowType, equals(CatalogFlowType.grocery));

      // Image priority correctly selected service_image over empty image string!
      expect(item.imageUrl, equals('https://customer.caldimservices.online/mockups/vegetables_realistic.png'));
    });

    test('Image field priority: item.image > item.service_image > fallback', () {
      final customItemJson = {
        'id': 244,
        'name': 'Amla',
        'slug': 'veg-amla',
        'price': '64.00',
        'image': 'https://images.unsplash.com/photo-custom-amla.jpg',
        'service_image': '/mockups/vegetables_realistic.png',
      };

      final item = ServiceItem.fromJson(customItemJson);
      // Non-empty valid item.image takes priority
      expect(item.imageUrl, equals('https://images.unsplash.com/photo-custom-amla.jpg'));
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  // 3. IMAGE PIPELINE RESOLUTION & HTML FALLBACK REJECTION
  // ──────────────────────────────────────────────────────────────────────────
  group('Part 4 — Image Pipeline & Fallback Hierarchy', () {
    test('ImageUrlHelper generates HTTPS production URLs for relative mockups', () {
      expect(
        ImageUrlHelper.resolve('/mockups/veg/beetroot.jpg'),
        equals('https://customer.caldimservices.online/mockups/veg/beetroot.jpg'),
      );
      expect(
        ImageUrlHelper.resolve('/mockups/vegetables_realistic.png'),
        equals('https://customer.caldimservices.online/mockups/vegetables_realistic.png'),
      );
      expect(
        ImageUrlHelper.resolve('/mockups/category_appliance.png'),
        equals('https://customer.caldimservices.online/mockups/category_appliance.png'),
      );
      expect(
        ImageUrlHelper.resolve('/mockups/service_hvac.png'),
        equals('https://customer.caldimservices.online/mockups/service_hvac.png'),
      );
      expect(
        ImageUrlHelper.resolve('/mockups/category_repair.png'),
        equals('https://customer.caldimservices.online/mockups/category_repair.png'),
      );
    });

    testWidgets('AppRemoteImage with null/empty image renders Tier 3 Lucide vector icon without crash', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AppRemoteImage(
              imageUrl: null,
              rawPath: '',
              categoryName: 'Farm-Fresh Vegetables',
              slug: 'vegetables_groceries',
              width: 64,
              height: 64,
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(AppRemoteImage), findsOneWidget);
      expect(find.byIcon(Icons.shopping_basket_rounded), findsOneWidget);
    });
  });
}
