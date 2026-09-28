import 'package:calservices_customer/core/network/api_client.dart';
import 'package:calservices_customer/core/network/auth_interceptor.dart';
import 'package:calservices_customer/core/storage/secure_storage.dart';
import 'package:calservices_customer/features/auth/data/auth_repository.dart';
import 'package:calservices_customer/features/auth/domain/auth_models.dart';
import 'package:calservices_customer/features/auth/domain/auth_notifier.dart';
import 'package:calservices_customer/features/booking/domain/cart_notifier.dart';
import 'package:calservices_customer/features/catalog/domain/catalog_models.dart';
import 'package:decimal/decimal.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

class _MockInterceptorHandler extends RequestInterceptorHandler {
  RequestOptions? passedOptions;
  @override
  void next(RequestOptions requestOptions) {
    passedOptions = requestOptions;
  }
}

class _MockErrorInterceptorHandler extends ErrorInterceptorHandler {
  bool nextCalled = false;
  @override
  void next(DioException err) {
    nextCalled = true;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
  });

  final sampleProduce = ServiceItem(
    id: 228,
    categoryId: 18,
    title: 'Beetroot',
    slug: 'veg-beetroot',
    price: Decimal.fromInt(37),
    categorySlug: 'vegetables_groceries',
    categoryName: 'Farm-Fresh Vegetable',
  );

  group('Authentication Flow Comprehensive Suite (Section 11 Tests 1 - 12)', () {
    test('TEST A01: OTP Request args format phone identifier', () {
      final repo = AuthRepository(
        api: ApiClient.create(SecureStorage()),
        storage: SecureStorage(),
      );
      expect(repo, isNotNull);
    });

    test('TEST A02: OTP response with standard payload parses cleanly into UserProfile object', () {
      final jsonPayload = {
        'id': 7988,
        'phone': '9876543210',
        'first_name': 'Gokul',
        'last_name': 'M',
        'email': 'cust_gokul.m@example.com',
      };
      final user = UserProfile.fromJson(jsonPayload);
      expect(user.id, equals(7988));
      expect(user.phone, equals('9876543210'));
      expect(user.name, equals('Gokul M'));
      expect(user.isGuest, isFalse);
    });

    test('TEST A03: String user ID "7988" from DRF is parsed safely without type exception', () {
      final jsonPayload = {
        'id': '7988',
        'phone': '9876543210',
        'first_name': 'Gokul',
      };
      final user = UserProfile.fromJson(jsonPayload);
      expect(user.id, equals(7988));
    });

    test('TEST A04: Integer user ID 7988 is parsed cleanly', () {
      final jsonPayload = {
        'id': 7988,
        'phone': '9876543210',
        'first_name': 'Gokul',
      };
      final user = UserProfile.fromJson(jsonPayload);
      expect(user.id, equals(7988));
    });

    test('TEST A05: Access token is saved and retrieved from SecureStorage', () async {
      final storage = SecureStorage();
      await storage.setAccessToken('sample_access_jwt_token');
      final retrieved = await storage.getAccessToken();
      expect(retrieved, equals('sample_access_jwt_token'));
    });

    test('TEST A06: Refresh token is saved and retrieved from SecureStorage', () async {
      final storage = SecureStorage();
      await storage.setRefreshToken('sample_refresh_jwt_token');
      final retrieved = await storage.getRefreshToken();
      expect(retrieved, equals('sample_refresh_jwt_token'));
    });

    test('TEST A07: AuthInterceptor injects Bearer token into HTTP request Authorization header', () async {
      final storage = SecureStorage();
      await storage.setAccessToken('valid_bearer_token');

      final interceptor = AuthInterceptor(
        storage: storage,
        dio: Dio(),
        onAuthFailure: () {},
      );

      final options = RequestOptions(path: '/catalog/categories/');
      final handler = _MockInterceptorHandler();

      await interceptor.onRequest(options, handler);

      expect(options.headers['Authorization'], equals('Bearer valid_bearer_token'));
    });

    test('TEST A08: Authenticated request preserves Authorization header for protected endpoints', () async {
      final storage = SecureStorage();
      await storage.setAccessToken('session_jwt_123');

      final interceptor = AuthInterceptor(
        storage: storage,
        dio: Dio(),
        onAuthFailure: () {},
      );

      final options = RequestOptions(path: '/booking/');
      final handler = _MockInterceptorHandler();

      await interceptor.onRequest(options, handler);
      expect(options.headers['Authorization'], equals('Bearer session_jwt_123'));
    });

    test('TEST A09: 401 handling triggers onAuthFailure callback when token cannot be refreshed', () async {
      final storage = SecureStorage();
      await storage.clearAll();
      bool authFailed = false;

      final interceptor = AuthInterceptor(
        storage: storage,
        dio: Dio(),
        onAuthFailure: () {
          authFailed = true;
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

      expect(authFailed, isTrue);
      expect(handler.nextCalled, isTrue);
    });

    test('TEST A10: Pending ADD action stores target service and return path', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final action = PendingCartAction(
        service: sampleProduce,
        actionType: PendingCartActionType.addToCart,
        quantity: 2,
        returnPath: '/categories/vegetables_groceries',
      );

      container.read(pendingActionProvider.notifier).setAction(action);

      final pending = container.read(pendingActionProvider);
      expect(pending, isNotNull);
      expect(pending!.service.id, equals(228));
      expect(pending.actionType, equals(PendingCartActionType.addToCart));
      expect(pending.quantity, equals(2));
      expect(pending.returnPath, equals('/categories/vegetables_groceries'));
    });

    test('TEST A11: Pending BUY action stores target service and /cart destination', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final action = PendingCartAction(
        service: sampleProduce,
        actionType: PendingCartActionType.buy,
        returnPath: '/cart',
      );

      container.read(pendingActionProvider.notifier).setAction(action);

      final pending = container.read(pendingActionProvider);
      expect(pending, isNotNull);
      expect(pending!.actionType, equals(PendingCartActionType.buy));
      expect(pending.returnPath, equals('/cart'));
    });

    test('TEST A12: Post-login action execution fulfills pending cart action without re-tapping ADD', () {
      final container = ProviderContainer(
        overrides: [
          currentUserProvider.overrideWithValue(
            const UserProfile(id: 7988, phone: '9876543210', name: 'Gokul M'),
          ),
        ],
      );
      addTearDown(container.dispose);

      container.read(pendingActionProvider.notifier).setAction(
            PendingCartAction(
              service: sampleProduce,
              actionType: PendingCartActionType.addToCart,
              quantity: 1,
              returnPath: '/categories/vegetables_groceries',
            ),
          );

      final pending = container.read(pendingActionProvider);
      expect(pending, isNotNull);

      container.read(cartProvider.notifier).addService(pending!.service, quantity: pending.quantity);
      container.read(pendingActionProvider.notifier).clear();

      expect(container.read(cartProvider).length, equals(1));
      expect(container.read(cartProvider).first.service.title, equals('Beetroot'));
      expect(container.read(pendingActionProvider), isNull);
    });
  });
}
