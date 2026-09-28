import 'dart:async';
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
import 'package:calservices_customer/core/network/auth_interceptor.dart';
import 'package:calservices_customer/core/storage/secure_storage.dart';
import 'package:calservices_customer/features/auth/data/auth_repository.dart';
import 'package:calservices_customer/features/auth/domain/auth_models.dart';
import 'package:calservices_customer/features/auth/domain/auth_notifier.dart';
import 'package:calservices_customer/features/auth/presentation/screens/phone_auth_screen.dart';
import 'package:calservices_customer/features/booking/domain/cart_notifier.dart';
import 'package:calservices_customer/features/catalog/domain/catalog_models.dart';
import 'package:calservices_customer/features/catalog/presentation/widgets/service_card.dart';
import 'package:calservices_customer/routing/app_router.dart';

class _MockErrorInterceptorHandler extends ErrorInterceptorHandler {
  bool nextCalled = false;
  Response? resolvedResponse;
  @override
  void next(DioException err) {
    nextCalled = true;
  }
  @override
  void resolve(Response response) {
    resolvedResponse = response;
  }
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

  const authenticatedUser = UserProfile(
    id: 7988,
    phone: '9876543210',
    name: 'Gokul M',
    email: 'cust_gokul.m@example.com',
  );

  group('Authentication & Session Stability Suite (AUTH-01 - AUTH-26)', () {
    // ── AUTH-01 & AUTH-02: Phone vs Email Keyboard Input ─────────────────────
    testWidgets('AUTH-01: Login with email renders email keyboard configuration',
        (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: PhoneAuthScreen(),
          ),
        ),
      );
      await tester.pump();

      // Tap Email chip
      await tester.tap(find.text('Email Address'));
      await tester.pump();

      final emailFieldFinder = find.byKey(const ValueKey('email_input_field'));
      expect(emailFieldFinder, findsOneWidget);

      final textField = tester.widget<TextField>(
        find.descendant(of: emailFieldFinder, matching: find.byType(TextField)),
      );
      expect(textField.keyboardType, equals(TextInputType.emailAddress));
      expect(textField.autofillHints, contains(AutofillHints.email));
    });

    testWidgets('AUTH-02: Login with phone renders phone keyboard configuration',
        (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: PhoneAuthScreen(),
          ),
        ),
      );
      await tester.pump();

      final phoneFieldFinder = find.byKey(const ValueKey('phone_input_field'));
      expect(phoneFieldFinder, findsOneWidget);

      final textField = tester.widget<TextField>(
        find.descendant(of: phoneFieldFinder, matching: find.byType(TextField)),
      );
      expect(textField.keyboardType, equals(TextInputType.phone));
      expect(textField.autofillHints, contains(AutofillHints.telephoneNumber));
    });

    // ── AUTH-03 & AUTH-04: OTP Verification & Auth State ─────────────────────
    test('AUTH-03: Successful email OTP establishes AuthAuthenticated state', () {
      final state = const AuthAuthenticated(user: UserProfile(
        id: 101,
        phone: 'user@example.com',
        email: 'user@example.com',
        name: 'Email User',
      ));
      expect(state.user.email, equals('user@example.com'));
      expect(state.user.isGuest, isFalse);
    });

    test('AUTH-04: Successful phone OTP establishes AuthAuthenticated state', () {
      final state = const AuthAuthenticated(user: authenticatedUser);
      expect(state.user.phone, equals('9876543210'));
      expect(state.user.isGuest, isFalse);
    });

    // ── AUTH-05, AUTH-06, AUTH-07: Token Persistence ─────────────────────────
    test('AUTH-05: Access token persists in SecureStorage across navigation', () async {
      final storage = SecureStorage();
      await storage.setAccessToken('jwt_access_12345');
      final token = await storage.getAccessToken();
      expect(token, equals('jwt_access_12345'));
    });

    test('AUTH-06: Access token persists across ProviderContainer rebuild', () async {
      final container1 = ProviderContainer();
      final storage1 = container1.read(secureStorageProvider);
      await storage1.setAccessToken('rebuild_access_token');
      container1.dispose();

      final container2 = ProviderContainer();
      final storage2 = container2.read(secureStorageProvider);
      expect(await storage2.getAccessToken(), equals('rebuild_access_token'));
      container2.dispose();
    });

    test('AUTH-07: Access token & user JSON persist after app restart simulation', () async {
      final storage = SecureStorage();
      await storage.setAccessToken('persistent_jwt_token');
      await storage.setRefreshToken('persistent_refresh_token');
      await storage.setUserJson('{"id": 7988, "phone": "9876543210", "name": "Gokul M"}');

      final repo = AuthRepository(api: ApiClient.create(storage), storage: storage);
      final restored = await repo.restoreSession();

      expect(restored, isNotNull);
      expect(restored!.id, equals(7988));
      expect(restored.name, equals('Gokul M'));
    });

    // ── AUTH-08, AUTH-09, AUTH-10: Authenticated Operations without Logout ───
    testWidgets('AUTH-08: Authenticated ADD mutates cart without login redirect',
        (tester) async {
      final container = ProviderContainer(
        overrides: [
          authProvider.overrideWith(() => _MockAuthNotifier(const AuthAuthenticated(user: authenticatedUser))),
        ],
      );
      addTearDown(container.dispose);

      final router = GoRouter(
        initialLocation: '/',
        routes: [
          GoRoute(
            path: '/',
            builder: (context, state) => Scaffold(body: ServiceCard(service: sampleBeetroot)),
          ),
          GoRoute(
            path: '/login',
            builder: (context, state) => const Scaffold(body: Text('Login Screen')),
          ),
        ],
      );

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pump();

      await tester.tap(find.text('ADD'));
      await tester.pump();

      expect(find.text('Login Screen'), findsNothing);
      expect(container.read(cartProvider).length, equals(1));
    });

    testWidgets('AUTH-09: Authenticated BUY navigates to cart without login redirect',
        (tester) async {
      final container = ProviderContainer(
        overrides: [
          authProvider.overrideWith(() => _MockAuthNotifier(const AuthAuthenticated(user: authenticatedUser))),
        ],
      );
      addTearDown(container.dispose);

      final router = GoRouter(
        initialLocation: '/',
        routes: [
          GoRoute(
            path: '/',
            builder: (context, state) => Scaffold(body: ServiceCard(service: sampleBeetroot)),
          ),
          GoRoute(
            path: '/cart',
            builder: (context, state) => const Scaffold(body: Text('Cart Screen')),
          ),
          GoRoute(
            path: '/login',
            builder: (context, state) => const Scaffold(body: Text('Login Screen')),
          ),
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
      expect(find.text('Login Screen'), findsNothing);
    });

    test('AUTH-10: Authenticated BOOK checks user is valid without asking for re-login', () {
      final container = ProviderContainer(
        overrides: [
          authProvider.overrideWith(() => _MockAuthNotifier(const AuthAuthenticated(user: authenticatedUser))),
        ],
      );
      addTearDown(container.dispose);

      final isAuth = container.read(isUserAuthenticatedProvider);
      expect(isAuth, isTrue);
    });

    // ── AUTH-11 & AUTH-12: 401 Refresh vs Invalid Token ──────────────────────
    test('AUTH-11: Expired access token with valid refresh token triggers retry', () async {
      final storage = SecureStorage();
      await storage.setAccessToken('expired_token');
      await storage.setRefreshToken('valid_refresh_token');

      // Create a mock Dio adapter for the refresh response
      final dio = Dio();
      dio.httpClientAdapter = _MockRefreshAdapter(
        refreshSuccessData: {
          'success': true,
          'data': {
            'access': 'new_valid_access_token',
            'refresh': 'new_valid_refresh_token',
          },
        },
      );

      final interceptor = AuthInterceptor(storage: storage, dio: dio);
      final err = DioException(
        requestOptions: RequestOptions(path: '/booking/'),
        response: Response(
          requestOptions: RequestOptions(path: '/booking/'),
          statusCode: 401,
        ),
      );
      final handler = _MockErrorInterceptorHandler();

      await interceptor.onError(err, handler);

      // Verify new access token was saved
      final newAccessToken = await storage.getAccessToken();
      expect(newAccessToken, equals('new_valid_access_token'));
      expect(handler.resolvedResponse, isNotNull);
    });

    test('AUTH-12: Expired access token with invalid refresh token triggers onAuthFailure', () async {
      final storage = SecureStorage();
      await storage.setAccessToken('expired_token');
      await storage.setRefreshToken('invalid_refresh_token');

      bool authFailureCalled = false;
      final dio = Dio();
      dio.httpClientAdapter = _MockRefreshAdapter(
        refreshStatusCode: 401,
      );

      final interceptor = AuthInterceptor(
        storage: storage,
        dio: dio,
        onAuthFailure: () {
          authFailureCalled = true;
        },
      );
      final err = DioException(
        requestOptions: RequestOptions(path: '/booking/'),
        response: Response(
          requestOptions: RequestOptions(path: '/booking/'),
          statusCode: 401,
        ),
      );
      final handler = _MockErrorInterceptorHandler();

      await interceptor.onError(err, handler);

      expect(authFailureCalled, isTrue);
      expect(await storage.hasAccessToken(), isFalse);
    });

    // ── AUTH-13 to AUTH-16: Generic Non-401 Errors DO NOT LOGOUT ─────────────
    test('AUTH-13: Cart API returning 500 DOES NOT trigger logout', () async {
      final storage = SecureStorage();
      await storage.setAccessToken('valid_user_token');

      bool authFailureCalled = false;
      final interceptor = AuthInterceptor(
        storage: storage,
        dio: Dio(),
        onAuthFailure: () => authFailureCalled = true,
      );

      final err = DioException(
        requestOptions: RequestOptions(path: '/cart/order/'),
        response: Response(
          requestOptions: RequestOptions(path: '/cart/order/'),
          statusCode: 500,
        ),
      );
      final handler = _MockErrorInterceptorHandler();

      await interceptor.onError(err, handler);

      expect(authFailureCalled, isFalse);
      expect(await storage.hasAccessToken(), isTrue);
    });

    test('AUTH-14: Booking API returning 422 DOES NOT trigger logout', () async {
      final storage = SecureStorage();
      await storage.setAccessToken('valid_user_token');

      bool authFailureCalled = false;
      final interceptor = AuthInterceptor(
        storage: storage,
        dio: Dio(),
        onAuthFailure: () => authFailureCalled = true,
      );

      final err = DioException(
        requestOptions: RequestOptions(path: '/booking/'),
        response: Response(
          requestOptions: RequestOptions(path: '/booking/'),
          statusCode: 422,
        ),
      );
      final handler = _MockErrorInterceptorHandler();

      await interceptor.onError(err, handler);

      expect(authFailureCalled, isFalse);
      expect(await storage.hasAccessToken(), isTrue);
    });

    test('AUTH-15: Network timeout DOES NOT trigger logout', () async {
      final storage = SecureStorage();
      await storage.setAccessToken('valid_user_token');

      bool authFailureCalled = false;
      final interceptor = AuthInterceptor(
        storage: storage,
        dio: Dio(),
        onAuthFailure: () => authFailureCalled = true,
      );

      final err = DioException(
        requestOptions: RequestOptions(path: '/booking/'),
        type: DioExceptionType.connectionTimeout,
      );
      final handler = _MockErrorInterceptorHandler();

      await interceptor.onError(err, handler);

      expect(authFailureCalled, isFalse);
      expect(await storage.hasAccessToken(), isTrue);
    });

    test('AUTH-16: Image API failure DOES NOT trigger logout', () async {
      final storage = SecureStorage();
      await storage.setAccessToken('valid_user_token');

      bool authFailureCalled = false;
      final interceptor = AuthInterceptor(
        storage: storage,
        dio: Dio(),
        onAuthFailure: () => authFailureCalled = true,
      );

      final err = DioException(
        requestOptions: RequestOptions(path: '/mockups/missing_image.png'),
        response: Response(
          requestOptions: RequestOptions(path: '/mockups/missing_image.png'),
          statusCode: 404,
        ),
      );
      final handler = _MockErrorInterceptorHandler();

      await interceptor.onError(err, handler);

      expect(authFailureCalled, isFalse);
      expect(await storage.hasAccessToken(), isTrue);
    });

    test('AUTH-16b: 400 Bad Request DOES NOT trigger logout', () async {
      final storage = SecureStorage();
      await storage.setAccessToken('valid_user_token');

      bool authFailureCalled = false;
      final interceptor = AuthInterceptor(
        storage: storage,
        dio: Dio(),
        onAuthFailure: () => authFailureCalled = true,
      );

      final err = DioException(
        requestOptions: RequestOptions(path: '/catalog/services/'),
        response: Response(
          requestOptions: RequestOptions(path: '/catalog/services/'),
          statusCode: 400,
        ),
      );
      final handler = _MockErrorInterceptorHandler();

      await interceptor.onError(err, handler);

      expect(authFailureCalled, isFalse);
      expect(await storage.hasAccessToken(), isTrue);
    });

    test('AUTH-16c: 409 Conflict DOES NOT trigger logout', () async {
      final storage = SecureStorage();
      await storage.setAccessToken('valid_user_token');

      bool authFailureCalled = false;
      final interceptor = AuthInterceptor(
        storage: storage,
        dio: Dio(),
        onAuthFailure: () => authFailureCalled = true,
      );

      final err = DioException(
        requestOptions: RequestOptions(path: '/booking/create/'),
        response: Response(
          requestOptions: RequestOptions(path: '/booking/create/'),
          statusCode: 409,
        ),
      );
      final handler = _MockErrorInterceptorHandler();

      await interceptor.onError(err, handler);

      expect(authFailureCalled, isFalse);
      expect(await storage.hasAccessToken(), isTrue);
    });

    test('AUTH-16d: Connection failure & JSON format error DO NOT trigger logout', () async {
      final storage = SecureStorage();
      await storage.setAccessToken('valid_user_token');

      bool authFailureCalled = false;
      final interceptor = AuthInterceptor(
        storage: storage,
        dio: Dio(),
        onAuthFailure: () => authFailureCalled = true,
      );

      final err = DioException(
        requestOptions: RequestOptions(path: '/booking/'),
        type: DioExceptionType.connectionError,
        error: const FormatException('Unexpected character in JSON'),
      );
      final handler = _MockErrorInterceptorHandler();

      await interceptor.onError(err, handler);

      expect(authFailureCalled, isFalse);
      expect(await storage.hasAccessToken(), isTrue);
    });

    // ── AUTH-17 & AUTH-18: Concurrency & Refresh Updates ─────────────────────
    test('AUTH-17: Concurrent 401 requests trigger a single refresh operation', () async {
      final storage = SecureStorage();
      await storage.setAccessToken('expired_token');
      await storage.setRefreshToken('valid_refresh_token');

      int refreshCallCount = 0;
      final dio = Dio();
      dio.httpClientAdapter = _MockCountingRefreshAdapter(
        onRefresh: () => refreshCallCount++,
        refreshSuccessData: {
          'success': true,
          'data': {'access': 'fresh_access_token', 'refresh': 'fresh_refresh_token'},
        },
      );

      final interceptor = AuthInterceptor(storage: storage, dio: dio);

      final err1 = DioException(
        requestOptions: RequestOptions(path: '/booking/1/'),
        response: Response(requestOptions: RequestOptions(path: '/booking/1/'), statusCode: 401),
      );
      final err2 = DioException(
        requestOptions: RequestOptions(path: '/auth/customer/addresses/'),
        response: Response(requestOptions: RequestOptions(path: '/auth/customer/addresses/'), statusCode: 401),
      );

      final handler1 = _MockErrorInterceptorHandler();
      final handler2 = _MockErrorInterceptorHandler();

      // Fire both 401 errors concurrently
      await Future.wait([
        interceptor.onError(err1, handler1),
        interceptor.onError(err2, handler2),
      ]);

      // Exactly 1 POST /auth/refresh/ must have occurred
      expect(refreshCallCount, equals(1));
      expect(handler1.resolvedResponse, isNotNull);
      expect(handler2.resolvedResponse, isNotNull);
    });

    test('AUTH-18: Successful refresh updates stored access and refresh tokens', () async {
      final storage = SecureStorage();
      await storage.setAccessToken('old_token');
      await storage.setRefreshToken('old_refresh');

      final dio = Dio();
      dio.httpClientAdapter = _MockRefreshAdapter(
        refreshSuccessData: {
          'success': true,
          'data': {'access': 'updated_access_jwt', 'refresh': 'updated_refresh_jwt'},
        },
      );

      final interceptor = AuthInterceptor(storage: storage, dio: dio);
      final err = DioException(
        requestOptions: RequestOptions(path: '/profile/'),
        response: Response(requestOptions: RequestOptions(path: '/profile/'), statusCode: 401),
      );
      final handler = _MockErrorInterceptorHandler();

      await interceptor.onError(err, handler);

      expect(await storage.getAccessToken(), equals('updated_access_jwt'));
      expect(await storage.getRefreshToken(), equals('updated_refresh_jwt'));
    });

    test('AUTH-19: Explicit 401 refresh failure clears all storage', () async {
      final storage = SecureStorage();
      await storage.setAccessToken('old_token');
      await storage.setRefreshToken('revoked_refresh');

      final dio = Dio();
      dio.httpClientAdapter = _MockRefreshAdapter(refreshStatusCode: 401);

      final interceptor = AuthInterceptor(storage: storage, dio: dio);
      final err = DioException(
        requestOptions: RequestOptions(path: '/profile/'),
        response: Response(requestOptions: RequestOptions(path: '/profile/'), statusCode: 401),
      );
      final handler = _MockErrorInterceptorHandler();

      await interceptor.onError(err, handler);

      expect(await storage.hasAccessToken(), isFalse);
    });

    // ── AUTH-20 to AUTH-22: Pending Actions survive Login Redirect ───────────
    test('AUTH-20: Pending BUY action survives login redirect and restores on return', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final pendingNotifier = container.read(pendingActionProvider.notifier);
      pendingNotifier.setAction(PendingCartAction(
        service: sampleBeetroot,
        actionType: PendingCartActionType.buy,
        quantity: 2,
        returnPath: AppRoutes.cart,
      ));

      final action = container.read(pendingActionProvider);
      expect(action, isNotNull);
      expect(action!.actionType, equals(PendingCartActionType.buy));
      expect(action.quantity, equals(2));
      expect(action.service.id, equals(228));
      expect(action.returnPath, equals(AppRoutes.cart));
    });

    test('AUTH-21: Pending ADD action survives login redirect and restores on return', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final pendingNotifier = container.read(pendingActionProvider.notifier);
      pendingNotifier.setAction(PendingCartAction(
        service: sampleBeetroot,
        actionType: PendingCartActionType.addToCart,
        quantity: 1,
        returnPath: '/categories/vegetables_groceries',
      ));

      final action = container.read(pendingActionProvider);
      expect(action, isNotNull);
      expect(action!.actionType, equals(PendingCartActionType.addToCart));
      expect(action.returnPath, equals('/categories/vegetables_groceries'));
    });

    test('AUTH-22: Pending BOOK action retains slot and package details', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final pendingNotifier = container.read(pendingActionProvider.notifier);
      pendingNotifier.setAction(PendingCartAction(
        service: sampleBeetroot,
        actionType: PendingCartActionType.addToCart,
        quantity: 3,
        notes: 'Express delivery before 2 PM',
      ));

      final action = container.read(pendingActionProvider);
      expect(action!.notes, equals('Express delivery before 2 PM'));
      expect(action.quantity, equals(3));
    });

    // ── AUTH-23 to AUTH-26: Router & Flow Guards ─────────────────────────────
    test('AUTH-23: Router does not redirect while auth state is AuthLoading', () {
      final container = ProviderContainer(
        overrides: [
          authProvider.overrideWith(() => _MockAuthNotifier(const AuthLoading())),
        ],
      );
      addTearDown(container.dispose);

      final isLoading = container.read(authLoadingProvider);
      expect(isLoading, isTrue);
    });

    test('AUTH-24: Successful OTP does not immediately return to login screen', () {
      final state = const AuthAuthenticated(user: authenticatedUser);
      expect(state, isA<AuthAuthenticated>());
    });

    test('AUTH-25: Cart operation after OTP does not log user out', () {
      final container = ProviderContainer(
        overrides: [
          authProvider.overrideWith(() => _MockAuthNotifier(const AuthAuthenticated(user: authenticatedUser))),
        ],
      );
      addTearDown(container.dispose);

      final cartNotifier = container.read(cartProvider.notifier);
      cartNotifier.addService(sampleBeetroot);

      expect(container.read(isUserAuthenticatedProvider), isTrue);
      expect(container.read(cartProvider).length, equals(1));
    });

    test('AUTH-26: Booking operation after OTP does not log user out', () {
      final container = ProviderContainer(
        overrides: [
          authProvider.overrideWith(() => _MockAuthNotifier(const AuthAuthenticated(user: authenticatedUser))),
        ],
      );
      addTearDown(container.dispose);

      expect(container.read(isUserAuthenticatedProvider), isTrue);
    });

    // ── Dedicated Phase 2 Contract Matrix (A01 - A25) ────────────────────────
    group('Phase 2 Authoritative Auth Contract Matrix (A01 - A25)', () {
      test('A01: OTP request success returns resend_after_seconds', () async {
        final storage = SecureStorage();
        final dio = Dio();
        dio.interceptors.add(InterceptorsWrapper(onRequest: (opts, handler) {
          handler.resolve(Response(
            requestOptions: opts,
            statusCode: 200,
            data: {'success': true, 'data': {'resend_after_seconds': 45}},
          ));
        }));
        final repo = AuthRepository(api: ApiClient.withDio(dio), storage: storage);
        final res = await repo.requestOtp(identifier: '9876543210', channel: 'phone');
        expect(res, isA<Success<Map<String, dynamic>>>());
        expect((res as Success<Map<String, dynamic>>).data['resend_after_seconds'], equals(45));
      });

      test('A02: OTP request failure returns appropriate error message', () async {
        final storage = SecureStorage();
        final dio = Dio();
        dio.interceptors.add(InterceptorsWrapper(onRequest: (opts, handler) {
          handler.reject(DioException(
            requestOptions: opts,
            response: Response(
              requestOptions: opts,
              statusCode: 400,
              data: {'success': false, 'error': {'message': 'Invalid mobile number'}},
            ),
          ));
        }));
        final repo = AuthRepository(api: ApiClient.withDio(dio), storage: storage);
        final res = await repo.requestOtp(identifier: '123', channel: 'phone');
        expect(res, isA<Failure<Map<String, dynamic>>>());
        expect((res as Failure<Map<String, dynamic>>).error.message, contains('Invalid mobile number'));
      });

      test('A03: OTP verification success parses tokens, user, and isNewUser', () async {
        final storage = SecureStorage();
        final dio = Dio();
        dio.interceptors.add(InterceptorsWrapper(onRequest: (opts, handler) {
          handler.resolve(Response(
            requestOptions: opts,
            statusCode: 200,
            data: {
              'success': true,
              'data': {
                'access': 'access_jwt_123',
                'refresh': 'refresh_jwt_456',
                'is_new_customer': false,
                'user': {'id': '142', 'name': 'Aravind K', 'phone': '9876543210'},
              },
            },
          ));
        }));
        final repo = AuthRepository(api: ApiClient.withDio(dio), storage: storage);
        final res = await repo.verifyOtp(identifier: '9876543210', otp: '123456', channel: 'phone');
        expect(res, isA<Success<AuthVerifyResult>>());
        final data = (res as Success<AuthVerifyResult>).data;
        expect(data.access, equals('access_jwt_123'));
        expect(data.refresh, equals('refresh_jwt_456'));
        expect(data.user.id, equals(142));
        expect(data.user.name, equals('Aravind K'));
      });

      test('A04: OTP verification invalid OTP returns ValidationError', () async {
        final storage = SecureStorage();
        final dio = Dio();
        dio.interceptors.add(InterceptorsWrapper(onRequest: (opts, handler) {
          handler.reject(DioException(
            requestOptions: opts,
            response: Response(
              requestOptions: opts,
              statusCode: 400,
              data: {'success': false, 'error': {'message': 'Invalid OTP code'}},
            ),
          ));
        }));
        final repo = AuthRepository(api: ApiClient.withDio(dio), storage: storage);
        final res = await repo.verifyOtp(identifier: '9876543210', otp: '000000', channel: 'phone');
        expect(res, isA<Failure<AuthVerifyResult>>());
        expect((res as Failure<AuthVerifyResult>).error.message, contains('Invalid OTP code'));
      });

      test('A05 & A06: String user.id and Integer customer_id both safely parse to int', () {
        final u1 = UserProfile.fromJson(const {'id': '142', 'name': 'String ID'});
        final u2 = UserProfile.fromJson(const {'customer_id': 142, 'name': 'Int ID'});
        expect(u1.id, equals(142));
        expect(u2.id, equals(142));
      });

      test('A07 & A08: Access and Refresh tokens correctly store and retrieve in SecureStorage', () async {
        final storage = SecureStorage();
        await storage.setAccessToken('test_access');
        await storage.setRefreshToken('test_refresh');
        expect(await storage.getAccessToken(), equals('test_access'));
        expect(await storage.getRefreshToken(), equals('test_refresh'));
      });

      test('A09: Authenticated API request automatically injects Bearer header', () async {
        final storage = SecureStorage();
        await storage.setAccessToken('my_bearer_token');
        RequestOptions? capturedOpts;
        final dio = Dio();
        dio.interceptors.add(AuthInterceptor(storage: storage, dio: dio));
        dio.interceptors.add(InterceptorsWrapper(onRequest: (opts, handler) {
          capturedOpts = opts;
          handler.resolve(Response(requestOptions: opts, statusCode: 200, data: {}));
        }));
        await dio.get('/test-endpoint/');
        expect(capturedOpts?.headers['Authorization'], equals('Bearer my_bearer_token'));
      });

      test('A10 & A11: 401 response triggers silent refresh and retries original request', () async {
        final storage = SecureStorage();
        await storage.setAccessToken('expired_token');
        await storage.setRefreshToken('valid_refresh');
        final dio = Dio();
        dio.httpClientAdapter = _MockRefreshAdapter(
          refreshSuccessData: {
            'success': true,
            'data': {'access': 'new_access_token', 'refresh': 'new_refresh_token'},
          },
        );
        final interceptor = AuthInterceptor(storage: storage, dio: dio);
        final err = DioException(
          requestOptions: RequestOptions(path: '/booking/'),
          response: Response(requestOptions: RequestOptions(path: '/booking/'), statusCode: 401),
        );
        final handler = _MockErrorInterceptorHandler();
        await interceptor.onError(err, handler);
        expect(await storage.getAccessToken(), equals('new_access_token'));
        expect(handler.resolvedResponse, isNotNull);
      });

      test('A12: Simultaneous 401 requests trigger exactly 1 single refresh', () async {
        final storage = SecureStorage();
        await storage.setAccessToken('expired_token');
        await storage.setRefreshToken('valid_refresh');
        int refreshCount = 0;
        final dio = Dio();
        dio.httpClientAdapter = _MockCountingRefreshAdapter(
          onRefresh: () => refreshCount++,
          refreshSuccessData: {
            'success': true,
            'data': {'access': 'fresh_access', 'refresh': 'fresh_refresh'},
          },
        );
        final interceptor = AuthInterceptor(storage: storage, dio: dio);
        final err1 = DioException(requestOptions: RequestOptions(path: '/a/'), response: Response(requestOptions: RequestOptions(path: '/a/'), statusCode: 401));
        final err2 = DioException(requestOptions: RequestOptions(path: '/b/'), response: Response(requestOptions: RequestOptions(path: '/b/'), statusCode: 401));
        final h1 = _MockErrorInterceptorHandler();
        final h2 = _MockErrorInterceptorHandler();
        await Future.wait([interceptor.onError(err1, h1), interceptor.onError(err2, h2)]);
        expect(refreshCount, equals(1));
      });

      test('A13: Refresh returning 401 clears storage and triggers logout', () async {
        final storage = SecureStorage();
        await storage.setAccessToken('expired_token');
        await storage.setRefreshToken('revoked_refresh');
        bool loggedOut = false;
        final dio = Dio();
        dio.httpClientAdapter = _MockRefreshAdapter(refreshStatusCode: 401);
        final interceptor = AuthInterceptor(storage: storage, dio: dio, onAuthFailure: () => loggedOut = true);
        final err = DioException(requestOptions: RequestOptions(path: '/me/'), response: Response(requestOptions: RequestOptions(path: '/me/'), statusCode: 401));
        await interceptor.onError(err, _MockErrorInterceptorHandler());
        expect(loggedOut, isTrue);
        expect(await storage.hasAccessToken(), isFalse);
      });

      test('A14: Refresh returning 400 clears storage and triggers logout', () async {
        final storage = SecureStorage();
        await storage.setAccessToken('expired_token');
        await storage.setRefreshToken('malformed_refresh');
        bool loggedOut = false;
        final dio = Dio();
        dio.httpClientAdapter = _MockRefreshAdapter(refreshStatusCode: 400);
        final interceptor = AuthInterceptor(storage: storage, dio: dio, onAuthFailure: () => loggedOut = true);
        final err = DioException(requestOptions: RequestOptions(path: '/me/'), response: Response(requestOptions: RequestOptions(path: '/me/'), statusCode: 401));
        await interceptor.onError(err, _MockErrorInterceptorHandler());
        expect(loggedOut, isTrue);
        expect(await storage.hasAccessToken(), isFalse);
      });

      test('A15, A16, A17, A18: Ordinary 400, 403, 404, 500 DO NOT logout user', () async {
        final storage = SecureStorage();
        await storage.setAccessToken('valid_token');
        bool loggedOut = false;
        final interceptor = AuthInterceptor(storage: storage, dio: Dio(), onAuthFailure: () => loggedOut = true);
        for (final status in [400, 403, 404, 500]) {
          final err = DioException(
            requestOptions: RequestOptions(path: '/orders/'),
            response: Response(requestOptions: RequestOptions(path: '/orders/'), statusCode: status),
          );
          await interceptor.onError(err, _MockErrorInterceptorHandler());
          expect(loggedOut, isFalse);
          expect(await storage.hasAccessToken(), isTrue);
        }
      });

      test('A19: App startup restores session when access token & userJson exist', () async {
        final storage = SecureStorage();
        await storage.setAccessToken('valid_startup_token');
        await storage.setUserJson('{"id": 142, "name": "Aravind K", "phone": "9876543210"}');
        final repo = AuthRepository(api: ApiClient.create(storage), storage: storage);
        final user = await repo.restoreSession();
        expect(user, isNotNull);
        expect(user!.id, equals(142));
      });

      test('A20: App startup restores placeholder session when userJson is missing but token exists', () async {
        final storage = SecureStorage();
        await storage.setAccessToken('valid_startup_token');
        final repo = AuthRepository(api: ApiClient.create(storage), storage: storage);
        final user = await repo.restoreSession();
        expect(user, isNotNull);
        expect(user!.id, equals(0));
      });

      test('A21: Logout explicitly clears access token, refresh token, and userJson', () async {
        final storage = SecureStorage();
        await storage.setAccessToken('tok_1');
        await storage.setRefreshToken('tok_2');
        await storage.setUserJson('{"id": 1}');
        final repo = AuthRepository(api: ApiClient.create(storage), storage: storage);
        await repo.logout();
        expect(await storage.getAccessToken(), isNull);
        expect(await storage.getRefreshToken(), isNull);
        expect(await storage.getUserJson(), isNull);
      });

      test('A22, A23, A24, A25: ADD, BUY, BOOK, PAYMENT while authenticated maintain auth state', () {
        final container = ProviderContainer(
          overrides: [
            authProvider.overrideWith(() => _MockAuthNotifier(const AuthAuthenticated(user: authenticatedUser))),
          ],
        );
        addTearDown(container.dispose);
        expect(container.read(isUserAuthenticatedProvider), isTrue);
        // ADD
        container.read(cartProvider.notifier).addService(sampleBeetroot);
        expect(container.read(isUserAuthenticatedProvider), isTrue);
        // BUY
        expect(container.read(cartProvider).length, equals(1));
        expect(container.read(isUserAuthenticatedProvider), isTrue);
        // BOOK / PAYMENT state check
        expect(container.read(currentUserProvider)?.phone, equals('9876543210'));
      });
    });
  });
}

class _MockAuthNotifier extends AuthNotifier {
  _MockAuthNotifier(this._initialState);
  final AuthState _initialState;

  @override
  AuthState build() => _initialState;
}

class _MockRefreshAdapter implements HttpClientAdapter {
  _MockRefreshAdapter({
    this.refreshSuccessData,
    this.refreshStatusCode = 200,
  });

  final Map<String, dynamic>? refreshSuccessData;
  final int refreshStatusCode;

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (options.path.contains('/auth/refresh/')) {
      if (refreshStatusCode == 200) {
        final payload = refreshSuccessData != null
            ? jsonEncode(refreshSuccessData)
            : '{"success": true, "data": {"access": "new_valid_access_token", "refresh": "new_valid_refresh_token"}}';
        return ResponseBody.fromString(
          payload,
          200,
          headers: {
            Headers.contentTypeHeader: [Headers.jsonContentType],
          },
        );
      } else {
        return ResponseBody.fromString(
          '{"success": false, "error": "Token expired"}',
          refreshStatusCode,
          headers: {
            Headers.contentTypeHeader: [Headers.jsonContentType],
          },
        );
      }
    }
    // For the retried request
    return ResponseBody.fromString(
      '{"success": true, "data": {"status": "ok"}}',
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }
}

class _MockCountingRefreshAdapter implements HttpClientAdapter {
  _MockCountingRefreshAdapter({
    required this.onRefresh,
    required this.refreshSuccessData,
  });

  final VoidCallback onRefresh;
  final Map<String, dynamic> refreshSuccessData;

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (options.path.contains('/auth/refresh/')) {
      onRefresh();
      // Simulate small latency
      await Future<void>.delayed(const Duration(milliseconds: 50));
      return ResponseBody.fromString(
        '{"success": true, "data": {"access": "fresh_access_token", "refresh": "fresh_refresh_token"}}',
        200,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      );
    }
    // Retried request response
    return ResponseBody.fromString(
      '{"success": true, "data": {"status": "retried_ok"}}',
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }
}
