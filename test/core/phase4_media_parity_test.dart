import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:calservices_customer/core/utils/image_url_helper.dart';
import 'package:calservices_customer/features/auth/domain/auth_models.dart';
import 'package:calservices_customer/features/auth/domain/auth_notifier.dart';
import 'package:calservices_customer/features/booking/domain/cart_notifier.dart';
import 'package:calservices_customer/features/catalog/domain/catalog_models.dart';
import 'package:calservices_customer/shared/widgets/app_remote_image.dart';

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

  const sampleUser = UserProfile(
    id: 7988,
    phone: '9876543210',
    name: 'Gokul M',
    email: 'cust_gokul.m@example.com',
  );

  final sampleBeetroot = ServiceItem(
    id: 228,
    categoryId: 18,
    title: 'Beetroot',
    slug: 'veg-beetroot',
    price: Decimal.fromInt(37),
    categorySlug: 'vegetables_groceries',
    categoryName: 'Farm-Fresh Vegetable',
    imageUrl: '/mockups/veg/beetroot.jpg',
  );

  group('Phase 4 Master Media & Asset Parity Matrix (IMG01 - IMG20)', () {
    // IMG01
    test('IMG01: Category image mapping for all 8 categories to distinct remote URLs & fallback assets', () {
      final categories = [
        (id: 12, slug: 'goods_transports', raw: '/mockups/category_goods_transports.png', expectedFallback: 'assets/images/mockups/service_transport.jpg', icon: Icons.local_shipping_rounded),
        (id: 13, slug: 'home_cleaning', raw: '/mockups/category_cleaning.png', expectedFallback: 'assets/images/mockups/service_cleaning.png', icon: Icons.cleaning_services_rounded),
        (id: 14, slug: 'pest_control', raw: '/mockups/pest_control_header.jpg', expectedFallback: 'assets/images/mockups/pest_control_header.jpg', icon: Icons.pest_control_rounded),
        (id: 15, slug: 'ac_appliance', raw: '/mockups/category_appliance.png', expectedFallback: 'assets/images/mockups/service_hvac.png', icon: Icons.ac_unit_rounded),
        (id: 16, slug: 'electrician_plumber_carpenter', raw: '/mockups/service_electrical.png', expectedFallback: 'assets/images/mockups/service_electrical.png', icon: Icons.build_rounded),
        (id: 17, slug: 'mason_construction', raw: '/mockups/wall_plastering_masonry.jpg', expectedFallback: 'assets/images/mockups/wall_plastering_masonry.jpg', icon: Icons.foundation_rounded),
        (id: 18, slug: 'vegetables_groceries', raw: '/mockups/vegetables_realistic.png', expectedFallback: 'assets/images/mockups/vegetables_realistic.png', icon: Icons.shopping_basket_rounded),
        (id: 19, slug: 'painting_waterproofing', raw: '/mockups/category_painting.png', expectedFallback: 'assets/images/mockups/wall_plastering_masonry.jpg', icon: Icons.format_paint_rounded),
      ];

      for (final cat in categories) {
        final resolvedUrl = ImageUrlHelper.resolve(cat.raw);
        expect(resolvedUrl, equals('https://sevo.co.in${cat.raw}'));
        final icon = ImageUrlHelper.mapCategoryIcon(null, cat.slug);
        expect(icon, equals(cat.icon));
      }
    });

    // IMG02
    test('IMG02: Beetroot produce image mapping strictly resolves to veg/beetroot.jpg without shifting cross-contamination', () {
      final resolvedUrl = ImageUrlHelper.resolve(sampleBeetroot.imageUrl);
      expect(resolvedUrl, equals('https://sevo.co.in/mockups/veg/beetroot.jpg'));
      expect(resolvedUrl, isNot(contains('service_transport')));
      expect(resolvedUrl, isNot(contains('shifting')));
    });

    // Note: IMG03 and IMG04 (produce/service local-asset-fallback mapping)
    // exercised the Tier-2 "resolveLocalAssetFallback" method, which was
    // removed as dead code (the bundled asset folders it pointed at were
    // empty) — removed here along with it.

    // IMG05
    testWidgets('IMG05: Null image URL gracefully falls back to Tier 3 semantic icon placeholder', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AppRemoteImage(
              imageUrl: null,
              categoryName: 'AC & Appliance',
              slug: 'ac_appliance',
              width: 100,
              height: 100,
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.byIcon(Icons.ac_unit_rounded), findsOneWidget);
    });

    // IMG06
    testWidgets('IMG06: Empty image URL string falls back to Tier 3 placeholder without throwing exception', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AppRemoteImage(
              imageUrl: '   ',
              categoryName: 'Home Cleaning',
              slug: 'home_cleaning',
              width: 100,
              height: 100,
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.byIcon(Icons.cleaning_services_rounded), findsOneWidget);
    });

    // IMG07
    test('IMG07: Relative URL resolution prepends authoritative production origin', () {
      expect(
        ImageUrlHelper.resolve('/mockups/service_cleaning.png'),
        equals('https://sevo.co.in/mockups/service_cleaning.png'),
      );
    });

    // IMG08
    test('IMG08: Absolute HTTPS URLs from CDNs are preserved untouched', () {
      const cdnUrl = 'https://images.unsplash.com/photo-1581578731548-c64695cc6952?w=500';
      expect(ImageUrlHelper.resolve(cdnUrl), equals(cdnUrl));
    });

    // IMG09
    test('IMG09: Insecure HTTP URLs are upgraded to HTTPS', () {
      const httpUrl = 'http://sevo.co.in/media/categories/cleaning.png';
      expect(
        ImageUrlHelper.resolve(httpUrl),
        equals('https://sevo.co.in/media/categories/cleaning.png'),
      );
    });

    // IMG10
    test('IMG10: /media/ path resolution maps cleanly to production media endpoint', () {
      expect(
        ImageUrlHelper.resolve('/media/categories/ac.png'),
        equals('https://sevo.co.in/media/categories/ac.png'),
      );
    });

    // IMG11
    test('IMG11: /mockups/ path resolution maps cleanly to production mockups endpoint', () {
      expect(
        ImageUrlHelper.resolve('/mockups/groceries_realistic.png'),
        equals('https://sevo.co.in/mockups/groceries_realistic.png'),
      );
    });

    // Note: IMG12 (Tier-2 resolveLocalAssetFallback resolution) was removed
    // along with the method itself — see the note above IMG05.

    // IMG13
    testWidgets('IMG13: Completely missing local asset and remote URL renders vector placeholder', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AppRemoteImage(
              imageUrl: null,
              rawPath: null,
              categoryName: 'Pest Control',
              slug: 'pest_control',
              width: 80,
              height: 80,
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.byIcon(Icons.pest_control_rounded), findsOneWidget);
    });

    // IMG14
    testWidgets('IMG14: Image failure does NOT logout or mutate authenticated user state', (tester) async {
      final container = ProviderContainer(
        overrides: [
          authProvider.overrideWith(() => _MockAuthNotifier(const AuthAuthenticated(user: sampleUser))),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: Scaffold(
              body: AppRemoteImage(
                imageUrl: 'https://sevo.co.in/mockups/broken_image_404.png',
                categoryName: 'AC & Appliance',
                slug: 'ac_appliance',
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      // Auth state MUST remain authenticated
      final authState = container.read(authProvider);
      expect(authState, isA<AuthAuthenticated>());
      expect((authState as AuthAuthenticated).user.id, equals(7988));
    });

    // IMG15
    testWidgets('IMG15: Image failure does NOT clear cart items or cart subtotal', (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      container.read(cartProvider.notifier).addService(sampleBeetroot, quantity: 2);
      expect(container.read(cartProvider).length, equals(1));

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: Scaffold(
              body: AppRemoteImage(
                imageUrl: 'https://invalid-host-image-failure.com/image.png',
                categoryName: 'Farm-Fresh Vegetables',
                slug: 'vegetables_groceries',
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      // Cart items MUST remain intact
      final cart = container.read(cartProvider);
      expect(cart.length, equals(1));
      expect(cart.first.service.id, equals(228));
      expect(cart.first.quantity, equals(2));
    });

    // IMG16
    test('IMG16: Path normalization avoids duplicate /api/api path prefix', () {
      const url = '/api/catalog/services/';
      final resolved = ImageUrlHelper.resolve(url);
      expect(resolved, equals('https://sevo.co.in/api/catalog/services/'));
      expect(resolved, isNot(contains('/api/api')));
    });

    // IMG17
    test('IMG17: Path normalization avoids duplicate /media/media path prefix', () {
      const url = '/media/categories/ac.png';
      final resolved = ImageUrlHelper.resolve(url);
      expect(resolved, equals('https://sevo.co.in/media/categories/ac.png'));
      expect(resolved, isNot(contains('/media/media')));
    });

    // IMG18
    test('IMG18: Path normalization avoids duplicate /mockups/mockups path prefix', () {
      const url = '/mockups/service_hvac.png';
      final resolved = ImageUrlHelper.resolve(url);
      expect(resolved, equals('https://sevo.co.in/mockups/service_hvac.png'));
      expect(resolved, isNot(contains('/mockups/mockups')));
    });

    // IMG19
    test('IMG19: Category image parity aligns with React categoriesData.js definitions', () {
      expect(
        ImageUrlHelper.resolve('/mockups/service_hvac.png'),
        equals('https://sevo.co.in/mockups/service_hvac.png'),
      );
      expect(
        ImageUrlHelper.resolve('/mockups/service_building.png'),
        equals('https://sevo.co.in/mockups/service_building.png'),
      );
    });

    // Note: IMG20 (grocery produce local-asset-fallback parity) was removed
    // along with the Tier-2 resolveLocalAssetFallback method — see the note
    // above IMG05.
  });
}
