import 'dart:convert';
import 'package:decimal/decimal.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:calservices_customer/core/errors/api_error.dart';
import 'package:calservices_customer/core/network/api_client.dart';
import 'package:calservices_customer/core/storage/secure_storage.dart';
import 'package:calservices_customer/features/auth/domain/auth_models.dart';
import 'package:calservices_customer/features/auth/domain/auth_notifier.dart';
import 'package:calservices_customer/features/booking/data/booking_repository.dart';
import 'package:calservices_customer/features/booking/domain/booking_models.dart';
import 'package:calservices_customer/features/booking/domain/cart_notifier.dart';
import 'package:calservices_customer/features/catalog/data/catalog_repository.dart';
import 'package:calservices_customer/features/catalog/domain/catalog_models.dart';
import 'package:calservices_customer/features/catalog/domain/catalog_providers.dart';
import 'package:calservices_customer/features/catalog/presentation/screens/category_detail_screen.dart';
import 'package:calservices_customer/features/catalog/presentation/widgets/service_card.dart';
import 'package:calservices_customer/routing/app_router.dart';

class _MockContractApiClient extends ApiClient {
  _MockContractApiClient({required this.handler}) : super.withDio(Dio());

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

class _MockAuthNotifier extends AuthNotifier {
  _MockAuthNotifier(this._initialState);
  final AuthState _initialState;

  @override
  AuthState build() => _initialState;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
  });

  final sampleBeetroot = ServiceItem(
    id: 228,
    categoryId: 18,
    title: 'Beetroot',
    slug: 'veg-beetroot',
    price: Decimal.fromInt(37),
    categorySlug: 'vegetables_groceries',
    categoryName: 'Farm-Fresh Vegetable',
  );

  final sampleAcService = ServiceItem(
    id: 101,
    categoryId: 15,
    title: 'AC Deep Clean Service',
    slug: 'ac-deep-clean',
    price: Decimal.fromInt(499),
    categorySlug: 'ac_appliance',
    categoryName: 'AC & Appliance',
    durationMinutes: 60,
    rating: 4.8,
  );

  const sampleUser = UserProfile(
    id: 7988,
    phone: '9876543210',
    name: 'Gokul M',
    email: 'cust_gokul.m@example.com',
  );

  // ===========================================================================
  // GROUP 1: BOOKINGS (B01 - B12)
  // ===========================================================================
  group('Phase 3 Bookings Contract Suite (B01 - B12)', () {
    test('B01: Upcoming bookings parsed with confirmed/pending status', () async {
      final mock = _MockContractApiClient(handler: (path, {data, queryParameters}) async {
        return Response(
          requestOptions: RequestOptions(path: path),
          statusCode: 200,
          data: {
            'success': true,
            'data': [
              {
                'id': 501,
                'request_id': 'SR-501',
                'status': 'confirmed',
                'total_amount': '499.00',
                'service_category': 15,
                'scheduled_date': '2026-08-30',
                'scheduled_time_slot': '10:00 AM - 12:00 PM',
              }
            ],
          },
        );
      });
      final repo = BookingRepository(api: mock);
      final res = await repo.getMyBookings(statusFilter: 'upcoming');
      expect(res, isA<Success<List<Booking>>>());
      final list = (res as Success<List<Booking>>).data;
      expect(list.length, equals(1));
      expect(list.first.status, equals('confirmed'));
    });

    test('B02: Active bookings parsed with on_the_way / in_progress status', () async {
      final mock = _MockContractApiClient(handler: (path, {data, queryParameters}) async {
        return Response(
          requestOptions: RequestOptions(path: path),
          statusCode: 200,
          data: {
            'success': true,
            'data': [
              {
                'id': 502,
                'request_id': 'SR-502',
                'status': 'on_the_way',
                'total_amount': '150.00',
                'service_category': 18,
              }
            ],
          },
        );
      });
      final repo = BookingRepository(api: mock);
      final res = await repo.getMyBookings(statusFilter: 'active');
      expect(res, isA<Success<List<Booking>>>());
      final list = (res as Success<List<Booking>>).data;
      expect(list.first.status, equals('on_the_way'));
    });

    test('B03: Completed & history bookings parsed accurately', () async {
      final mock = _MockContractApiClient(handler: (path, {data, queryParameters}) async {
        return Response(
          requestOptions: RequestOptions(path: path),
          statusCode: 200,
          data: {
            'success': true,
            'data': [
              {
                'id': 503,
                'request_id': 'SR-503',
                'status': 'completed',
                'total_amount': '799.00',
                'service_category': 13,
              }
            ],
          },
        );
      });
      final repo = BookingRepository(api: mock);
      final res = await repo.getMyBookings(statusFilter: 'completed');
      expect(res, isA<Success<List<Booking>>>());
      final list = (res as Success<List<Booking>>).data;
      expect(list.first.status, equals('completed'));
    });

    test('B04: Empty bookings array returns Success with empty list', () async {
      final mock = _MockContractApiClient(handler: (path, {data, queryParameters}) async {
        return Response(
          requestOptions: RequestOptions(path: path),
          statusCode: 200,
          data: {'success': true, 'data': [], 'message': ''},
        );
      });
      final repo = BookingRepository(api: mock);
      final res = await repo.getMyBookings();
      expect(res, isA<Success<List<Booking>>>());
      expect((res as Success<List<Booking>>).data, isEmpty);
    });

    test('B05: Multiple bookings array parses all elements without data loss', () async {
      final mock = _MockContractApiClient(handler: (path, {data, queryParameters}) async {
        return Response(
          requestOptions: RequestOptions(path: path),
          statusCode: 200,
          data: {
            'success': true,
            'data': [
              {'id': 1, 'request_id': 'SR-1', 'total_amount': 100},
              {'id': 2, 'request_id': 'SR-2', 'total_amount': 200},
              {'id': 3, 'request_id': 'SR-3', 'total_amount': 300},
            ],
          },
        );
      });
      final repo = BookingRepository(api: mock);
      final res = await repo.getMyBookings();
      expect(res, isA<Success<List<Booking>>>());
      expect((res as Success<List<Booking>>).data.length, equals(3));
    });

    test('B06: Wrapped list in data.items or data.results parses cleanly', () async {
      final mock = _MockContractApiClient(handler: (path, {data, queryParameters}) async {
        return Response(
          requestOptions: RequestOptions(path: path),
          statusCode: 200,
          data: {
            'success': true,
            'data': {
              'items': [
                {'id': 504, 'request_id': 'SR-504', 'total_amount': '550.00'}
              ]
            },
          },
        );
      });
      final repo = BookingRepository(api: mock);
      final res = await repo.getMyBookings();
      expect(res, isA<Success<List<Booking>>>());
      expect((res as Success<List<Booking>>).data.first.id, equals(504));
    });

    test('B07: Direct JSON array response parsed without error', () async {
      final mock = _MockContractApiClient(handler: (path, {data, queryParameters}) async {
        return Response(
          requestOptions: RequestOptions(path: path),
          statusCode: 200,
          data: [
            {'id': 505, 'request_id': 'SR-505', 'total_amount': '45.00'}
          ],
        );
      });
      final repo = BookingRepository(api: mock);
      final res = await repo.getMyBookings();
      expect(res, isA<Success<List<Booking>>>());
      expect((res as Success<List<Booking>>).data.first.id, equals(505));
    });

    test('B08: Malformed error response is caught as Failure', () async {
      final mock = _MockContractApiClient(handler: (path, {data, queryParameters}) async {
        return Response(
          requestOptions: RequestOptions(path: path),
          statusCode: 200,
          data: {'success': false, 'message': 'Internal database query failed'},
        );
      });
      final repo = BookingRepository(api: mock);
      final res = await repo.getMyBookings();
      expect(res, isA<Failure<List<Booking>>>());
      expect((res as Failure<List<Booking>>).error.message, contains('Internal database query failed'));
    });

    test('B09: HTTP 500 server error returns typed Failure', () async {
      final mock = _MockContractApiClient(handler: (path, {data, queryParameters}) async {
        throw DioException(
          requestOptions: RequestOptions(path: path),
          response: Response(requestOptions: RequestOptions(path: path), statusCode: 500),
        );
      });
      final repo = BookingRepository(api: mock);
      final res = await repo.getMyBookings();
      expect(res, isA<Failure<List<Booking>>>());
    });

    test('B10: HTTP 401 authentication error returns typed Failure', () async {
      final mock = _MockContractApiClient(handler: (path, {data, queryParameters}) async {
        throw DioException(
          requestOptions: RequestOptions(path: path),
          response: Response(requestOptions: RequestOptions(path: path), statusCode: 401),
        );
      });
      final repo = BookingRepository(api: mock);
      final res = await repo.getMyBookings();
      expect(res, isA<Failure<List<Booking>>>());
    });

    test('B11: Retry after failure successfully queries repository again', () async {
      int attempts = 0;
      final mock = _MockContractApiClient(handler: (path, {data, queryParameters}) async {
        attempts++;
        if (attempts == 1) {
          throw DioException(
            requestOptions: RequestOptions(path: path),
            response: Response(requestOptions: RequestOptions(path: path), statusCode: 503),
          );
        }
        return Response(
          requestOptions: RequestOptions(path: path),
          statusCode: 200,
          data: {'success': true, 'data': []},
        );
      });
      final repo = BookingRepository(api: mock);
      final firstRes = await repo.getMyBookings();
      expect(firstRes, isA<Failure<List<Booking>>>());
      final retryRes = await repo.getMyBookings();
      expect(retryRes, isA<Success<List<Booking>>>());
      expect(attempts, equals(2));
    });

    test('B12: Tab switching attaches appropriate status query parameters', () async {
      String? lastStatus;
      final mock = _MockContractApiClient(handler: (path, {data, queryParameters}) async {
        lastStatus = queryParameters?['status']?.toString();
        return Response(
          requestOptions: RequestOptions(path: path),
          statusCode: 200,
          data: {'success': true, 'data': []},
        );
      });
      final repo = BookingRepository(api: mock);
      await repo.getMyBookings(statusFilter: 'active');
      expect(lastStatus, equals('active'));
      await repo.getMyBookings(statusFilter: 'completed');
      expect(lastStatus, equals('completed'));
    });
  });

  // ===========================================================================
  // GROUP 2: CATALOG & HIERARCHY (C01 - C10)
  // ===========================================================================
  group('Phase 3 Catalog & Hierarchy Suite (C01 - C10)', () {
    test('C01: Category list queries /catalog/categories/ and parses accurately', () async {
      final mock = _MockContractApiClient(handler: (path, {data, queryParameters}) async {
        return Response(
          requestOptions: RequestOptions(path: path),
          statusCode: 200,
          data: [
            {'id': 18, 'name': 'Farm-Fresh Vegetables & Groceries', 'slug': 'vegetables_groceries'},
            {'id': 15, 'name': 'AC & Appliance', 'slug': 'ac_appliance'},
          ],
        );
      });
      final repo = CatalogRepository(api: mock);
      final res = await repo.getCategories();
      expect(res, isA<Success<List<Category>>>());
      expect((res as Success<List<Category>>).data.length, equals(2));
    });

    test('C02: Category ID resolution maps 8 canonical slugs to production IDs', () {
      expect(CatalogRepository.getCanonicalCategoryId('ac_appliance'), equals(15));
      expect(CatalogRepository.getCanonicalCategoryId('electrician_plumber_carpenter'), equals(16));
      expect(CatalogRepository.getCanonicalCategoryId('vegetables_groceries'), equals(18));
      expect(CatalogRepository.getCanonicalCategoryId('goods_transports'), equals(12));
      expect(CatalogRepository.getCanonicalCategoryId('home_cleaning'), equals(13));
      expect(CatalogRepository.getCanonicalCategoryId('mason_construction'), equals(17));
      expect(CatalogRepository.getCanonicalCategoryId('painting_waterproofing'), equals(19));
      expect(CatalogRepository.getCanonicalCategoryId('pest_control'), equals(14));
    });

    test('C03: Category services query passes category_id=18 for grocery produce', () async {
      String? capturedCatId;
      final mock = _MockContractApiClient(handler: (path, {data, queryParameters}) async {
        capturedCatId = queryParameters?['category_id']?.toString();
        return Response(
          requestOptions: RequestOptions(path: path),
          statusCode: 200,
          data: {'success': true, 'data': [sampleBeetroot.toJson()]},
        );
      });
      final repo = CatalogRepository(api: mock);
      final res = await repo.getServicesByCategory(categoryId: 18);
      expect(res, isA<Success<List<ServiceItem>>>());
      expect(capturedCatId, equals('18'));
    });

    test('C04: Beetroot lookup retrieves matching grocery item by slug', () async {
      final mock = _MockContractApiClient(handler: (path, {data, queryParameters}) async {
        return Response(
          requestOptions: RequestOptions(path: path),
          statusCode: 200,
          data: {'success': true, 'data': [sampleBeetroot.toJson()]},
        );
      });
      final repo = CatalogRepository(api: mock);
      final res = await repo.getServiceDetail('veg-beetroot');
      expect(res, isA<Success<ServiceItem>>());
      final data = (res as Success<ServiceItem>).data;
      expect(data.title, equals('Beetroot'));
      expect(data.slug, equals('veg-beetroot'));
    });

    test('C05: Unrelated service exclusion — Beetroot query does NOT return shifting service', () async {
      final mock = _MockContractApiClient(handler: (path, {data, queryParameters}) async {
        return Response(
          requestOptions: RequestOptions(path: path),
          statusCode: 200,
          data: {
            'success': true,
            'data': [
              {'id': 99, 'title': '1 RK / 1 BHK Shifting', 'slug': '1-rk-shifting', 'price': '1200.00'},
              sampleBeetroot.toJson(),
            ],
          },
        );
      });
      final repo = CatalogRepository(api: mock);
      final res = await repo.getServiceDetail('veg-beetroot');
      expect(res, isA<Success<ServiceItem>>());
      final data = (res as Success<ServiceItem>).data;
      expect(data.title, equals('Beetroot'));
      expect(data.title, isNot(equals('1 RK / 1 BHK Shifting')));
    });

    test('C06: Service detail parses duration, rating, and price accurately', () async {
      final mock = _MockContractApiClient(handler: (path, {data, queryParameters}) async {
        return Response(
          requestOptions: RequestOptions(path: path),
          statusCode: 200,
          data: {'success': true, 'data': [sampleAcService.toJson()]},
        );
      });
      final repo = CatalogRepository(api: mock);
      final res = await repo.getServiceDetail('ac-deep-clean');
      expect(res, isA<Success<ServiceItem>>());
      final svc = (res as Success<ServiceItem>).data;
      expect(svc.durationMinutes, equals(60));
      expect(svc.rating, equals(4.8));
      expect(svc.price, equals(Decimal.fromInt(499)));
    });

    test('C07: Grocery produce item correctly identified with CatalogFlowType.grocery', () {
      expect(sampleBeetroot.flowType, equals(CatalogFlowType.grocery));
    });

    test('C08: Scheduled service item correctly identified with CatalogFlowType.serviceBooking', () {
      expect(sampleAcService.flowType, equals(CatalogFlowType.serviceBooking));
    });

    test('C09: Non-existent service slug synthesizes clean service item instead of crashing or returning wrong item', () async {
      final mock = _MockContractApiClient(handler: (path, {data, queryParameters}) async {
        return Response(
          requestOptions: RequestOptions(path: path),
          statusCode: 200,
          data: {'success': true, 'data': []},
        );
      });
      final repo = CatalogRepository(api: mock);
      final res = await repo.getServiceDetail('custom-unknown-service');
      expect(res, isA<Success<ServiceItem>>());
      final data = (res as Success<ServiceItem>).data;
      expect(data.slug, equals('custom-unknown-service'));
      expect(data.title, isNot(equals('1 RK / 1 BHK Shifting')));
    });

    testWidgets('C10: CategoryDetailScreen eager ID resolution prevents blank screen on mount', (tester) async {
      final container = ProviderContainer(
        overrides: [
          categoriesProvider.overrideWith((ref) => Future.value(const [])),
          categoryServicesProvider(const CategoryServicesParam(
            categoryId: 18,
            categorySlug: 'vegetables_groceries',
          )).overrideWith((ref) => Future.value([sampleBeetroot])),
          subServicesProvider('vegetables_groceries')
              .overrideWith((ref) => Future.value(const [])),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: CategoryDetailScreen(categorySlug: 'vegetables_groceries'),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Farm-Fresh Vegetables & Groceries'), findsOneWidget);
      expect(find.text('Beetroot'), findsOneWidget);
    });
  });

  // ===========================================================================
  // GROUP 3: CART & QUICK COMMERCE FLOW (CR01 - CR08)
  // ===========================================================================
  group('Phase 3 Cart & Quick Commerce Flow Suite (CR01 - CR08)', () {
    test('CR01: ADD mutates cart and increments item count', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier = container.read(cartProvider.notifier);
      notifier.addService(sampleBeetroot);

      final items = container.read(cartProvider);
      expect(items.length, equals(1));
      expect(items.first.service.id, equals(228));
      expect(items.first.quantity, equals(1));
    });

    test('CR02: Quantity increment updates total calculation accurately', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier = container.read(cartProvider.notifier);
      notifier.addService(sampleBeetroot, quantity: 1);
      notifier.updateQuantity(sampleBeetroot.id, 2);

      final summary = container.read(cartSummaryProvider);
      expect(summary.itemCount, equals(2));
      expect(summary.subtotal, equals(Decimal.fromInt(74))); // 37 * 2
    });

    test('CR03: Quantity decrement reduces count and removes item at zero', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier = container.read(cartProvider.notifier);
      notifier.addService(sampleBeetroot, quantity: 2);
      notifier.updateQuantity(sampleBeetroot.id, 1);
      expect(container.read(cartProvider).first.quantity, equals(1));

      notifier.removeService(sampleBeetroot.id);
      expect(container.read(cartProvider), isEmpty);
    });

    testWidgets('CR04: Continue shopping remains on catalog screen without navigating away', (tester) async {
      final container = ProviderContainer(
        overrides: [
          authProvider.overrideWith(() => _MockAuthNotifier(const AuthAuthenticated(user: sampleUser))),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Scaffold(body: ServiceCard(service: sampleBeetroot)),
          ),
        ),
      );
      await tester.pump();

      await tester.tap(find.text('ADD'));
      await tester.pump();

      expect(container.read(cartProvider).length, equals(1));
      expect(find.byType(ServiceCard), findsOneWidget);
    });

    testWidgets('CR05: BUY button navigates to /cart and adds item if not in cart', (tester) async {
      final container = ProviderContainer(
        overrides: [
          authProvider.overrideWith(() => _MockAuthNotifier(const AuthAuthenticated(user: sampleUser))),
        ],
      );
      addTearDown(container.dispose);

      final router = GoRouter(
        initialLocation: '/',
        routes: [
          GoRoute(path: '/', builder: (c, s) => Scaffold(body: ServiceCard(service: sampleBeetroot))),
          GoRoute(path: '/cart', builder: (c, s) => const Scaffold(body: Text('Cart Screen'))),
        ],
      );

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pump();

      await tester.tap(find.text('BUY'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Cart Screen'), findsOneWidget);
      expect(container.read(cartProvider).length, equals(1));
    });

    test('CR06: Cart persistence serializes and restores from storage JSON', () async {
      final storage = SecureStorage();
      final item = CartItem(service: sampleBeetroot, quantity: 3);
      final jsonStr = jsonEncode([item.toStorageJson()]);
      await storage.setCartJson(jsonStr);

      final restoredJson = await storage.getCartJson();
      expect(restoredJson, isNotNull);
      final list = jsonDecode(restoredJson!) as List;
      final restoredItem = CartItem.fromStorageJson(Map<String, dynamic>.from(list.first as Map));
      expect(restoredItem.service.id, equals(228));
      expect(restoredItem.quantity, equals(3));
    });

    test('CR07: Guest ADD sets pending action with returnPath to catalog', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier = container.read(pendingActionProvider.notifier);
      notifier.setAction(
        PendingCartAction(
          service: sampleBeetroot,
          actionType: PendingCartActionType.addToCart,
          quantity: 1,
          returnPath: '/categories/vegetables_groceries',
        ),
      );

      final action = container.read(pendingActionProvider);
      expect(action, isNotNull);
      expect(action!.actionType, equals(PendingCartActionType.addToCart));
      expect(action.returnPath, equals('/categories/vegetables_groceries'));
    });

    test('CR08: Guest BUY sets pending action with returnPath to cart', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier = container.read(pendingActionProvider.notifier);
      notifier.setAction(
        PendingCartAction(
          service: sampleBeetroot,
          actionType: PendingCartActionType.buy,
          quantity: 1,
          returnPath: AppRoutes.cart,
        ),
      );

      final action = container.read(pendingActionProvider);
      expect(action, isNotNull);
      expect(action!.actionType, equals(PendingCartActionType.buy));
      expect(action.returnPath, equals(AppRoutes.cart));
    });
  });
}
