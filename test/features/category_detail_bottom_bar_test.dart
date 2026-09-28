import 'package:calservices_customer/features/booking/domain/cart_notifier.dart';
import 'package:calservices_customer/features/catalog/domain/catalog_models.dart';
import 'package:calservices_customer/features/catalog/presentation/screens/category_detail_screen.dart';
import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
  });

  final beetroot = ServiceItem(
    id: 228,
    categoryId: 18,
    title: 'Beetroot',
    slug: 'veg-beetroot',
    price: Decimal.fromInt(37),
    categorySlug: 'vegetables_groceries',
    categoryName: 'Farm-Fresh Vegetable',
  );

  for (final width in [320.0, 360.0, 390.0, 393.0, 412.0]) {
    testWidgets('CategoryDetailScreen bottom bar renders horizontally without vertical wrapping at width ${width}dp', (tester) async {
      tester.view.physicalSize = Size(width * 2.75, 2400);
      tester.view.devicePixelRatio = 2.75;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final container = ProviderContainer();
      container.read(cartProvider.notifier).addService(beetroot, quantity: 8);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: CategoryDetailScreen(
              categorySlug: 'vegetables_groceries',
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      final textFinder = find.text('Continue adding or go to cart');
      expect(textFinder, findsOneWidget);

      final textRect = tester.getRect(textFinder);
      // The text must be rendered horizontally on 1 line (height <= 24dp, not 500dp+)
      expect(textRect.height, lessThanOrEqualTo(24.0),
          reason: 'Text must NOT wrap vertically character by character; height should be single-line.');
      expect(textRect.width, greaterThan(80.0),
          reason: 'Text must have sufficient horizontal width to render normally.');

      final buttonFinder = find.text('Go to Cart');
      expect(buttonFinder, findsOneWidget);
      final buttonRect = tester.getRect(buttonFinder);
      expect(buttonRect.width, greaterThan(50.0));

      // The button must be on the right side of the text (horizontal row layout)
      expect(buttonRect.left, greaterThanOrEqualTo(textRect.left),
          reason: 'Button must be positioned horizontally adjacent to the text column.');

      // The bottom bar height should be compact (< 100dp, not 500dp+)
      final bottomBarFinder = find.byType(Container).last;
      final bottomBarRect = tester.getRect(bottomBarFinder);
      expect(bottomBarRect.height, lessThan(100.0),
          reason: 'Bottom navigation bar must remain compact, not taking over the screen.');
    });
  }
}
