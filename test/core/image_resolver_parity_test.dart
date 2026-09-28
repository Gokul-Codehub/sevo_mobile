import 'package:calservices_customer/core/utils/image_url_helper.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';


void main() {
  group('ImageUrlHelper Parity & Fallback Comprehensive Suite', () {
    test('Resolves relative /mockups/ path to production domain', () {
      const input = '/mockups/vegetables_realistic.png';
      final resolved = ImageUrlHelper.resolve(input);
      expect(resolved, equals('https://sevo.co.in/mockups/vegetables_realistic.png'));
    });

    test('Preserves absolute HTTPS URLs untouched', () {
      const input = 'https://images.unsplash.com/photo-1621905252507-b35492d04029';
      final resolved = ImageUrlHelper.resolve(input);
      expect(resolved, equals(input));
    });

    test('Upgrades insecure HTTP URLs to HTTPS', () {
      const input = 'http://sevo.co.in/media/catalog/image.png';
      final resolved = ImageUrlHelper.resolve(input);
      expect(resolved, equals('https://sevo.co.in/media/catalog/image.png'));
    });

    test('Rewrites legacy localhost /media/ URL to production domain', () {
      const input = 'http://localhost:8000/media/catalog/test.jpg';
      final resolved = ImageUrlHelper.resolve(input);
      expect(resolved, equals('https://sevo.co.in/media/catalog/test.jpg'));
    });

    test('Returns null for null, empty, or whitespace string', () {
      expect(ImageUrlHelper.resolve(null), isNull);
      expect(ImageUrlHelper.resolve(''), isNull);
      expect(ImageUrlHelper.resolve('   '), isNull);
    });

    // Note: the Tier-2 "resolveLocalAssetFallback" local-asset fallback was
    // removed as dead code (the bundled asset folders it pointed at were
    // empty, so the method could never actually resolve anything real) —
    // the tests that exercised it were removed here for the same reason.

    test('Category icon mapping provides Lucide parity Material icons', () {
      expect(
        ImageUrlHelper.mapCategoryIcon('carrot', 'vegetables_groceries'),
        equals(Icons.shopping_basket_rounded),
      );
      expect(
        ImageUrlHelper.mapCategoryIcon('truck', 'goods_transports'),
        equals(Icons.local_shipping_rounded),
      );
      expect(
        ImageUrlHelper.mapCategoryIcon('wind', 'ac_appliance'),
        equals(Icons.ac_unit_rounded),
      );
      expect(
        ImageUrlHelper.mapCategoryIcon('sparkles', 'deep-cleaning'),
        equals(Icons.cleaning_services_rounded),
      );
      expect(
        ImageUrlHelper.mapCategoryIcon('palette', 'paintings'),
        equals(Icons.format_paint_rounded),
      );



    });
  });
}
