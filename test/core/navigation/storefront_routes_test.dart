import 'dart:io';

import 'package:calservices_customer/core/navigation/storefront_routes.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('StorefrontRoutes', () {
    test('a category destination always opens the category page, never a product', () {
      final r = StorefrontRoutes.forDestination(type: 'category', value: 'laundry-additive', grocery: true);
      expect(r, '/groceries/seller-hub?category=laundry-additive');
      expect(r, isNot(contains('/products/')));
    });

    test('category uses the slug when present, else the value', () {
      expect(StorefrontRoutes.forDestination(type: 'category', slug: 'oil', value: 'x', grocery: true), contains('category=oil'));
      expect(StorefrontRoutes.forDestination(type: 'category', value: 'flour', grocery: true), contains('category=flour'));
    });

    test('empty category does nothing', () {
      expect(StorefrontRoutes.forDestination(type: 'category', grocery: true), isNull);
    });

    test('services categories use /categories/<slug>', () {
      expect(StorefrontRoutes.forDestination(type: 'category', value: 'ac-repair', grocery: false), '/categories/ac-repair');
    });

    test('vegetable root uses the vegetables page', () {
      expect(StorefrontRoutes.groceryCategory('tomato', vegetable: true), '/vegetables/seller-hub?category=tomato');
    });

    test('a product destination opens the product page directly', () {
      expect(StorefrontRoutes.forDestination(type: 'product', value: 'seller-hub-42', grocery: true), '/products/seller-hub-42');
      expect(StorefrontRoutes.forDestination(type: 'product', grocery: true), isNull);
    });

    test('other destinations', () {
      expect(StorefrontRoutes.forDestination(type: 'service', value: 's1', grocery: false), '/services/s1');
      expect(StorefrontRoutes.forDestination(type: 'package', value: 'p1', grocery: false), '/services/p1');
      expect(StorefrontRoutes.forDestination(type: 'collection', value: '7', grocery: true), '/baskets/7');
      expect(StorefrontRoutes.forDestination(type: 'search', value: 'rice dal', grocery: true), '/search?mode=groceries&q=rice+dal');
      expect(StorefrontRoutes.forDestination(type: 'none', grocery: true), isNull);
      expect(StorefrontRoutes.forDestination(type: 'unknown', value: 'x', grocery: true), isNull);
    });
  });

  // Source guards: the home category taps must never be able to open a product page again.
  group('home category taps stay on the category page', () {
    String functionBody(String source, String signature) {
      final start = source.indexOf(signature);
      expect(start, greaterThanOrEqualTo(0), reason: '$signature not found');
      final open = source.indexOf('{', source.indexOf(')', start));
      var depth = 0;
      for (var i = open; i < source.length; i++) {
        if (source[i] == '{') depth++;
        if (source[i] == '}') {
          depth--;
          if (depth == 0) return source.substring(open, i + 1);
        }
      }
      fail('unbalanced braces after $signature');
    }

    test('_openCategory in grocery_section_layouts.dart never pushes a product page', () {
      final src = File('lib/features/home/presentation/widgets/grocery_section_layouts.dart').readAsStringSync();
      final body = functionBody(src, 'Future<void> _openCategory(');
      expect(body, isNot(contains('/products/')));
      expect(body, isNot(contains('toServiceItem')));
      expect(body, isNot(contains('totalProductCount')));
    });

    test('_openCategoryListing never pushes a product page', () {
      final src = File('lib/features/home/presentation/widgets/grocery_section_layouts.dart').readAsStringSync();
      final body = functionBody(src, 'void _openCategoryListing(');
      expect(body, isNot(contains('/products/')));
    });
  });
}
