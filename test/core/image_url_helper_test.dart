import 'package:calservices_customer/core/utils/image_url_helper.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ImageUrlHelper.resolve() Regression Tests', () {
    test('resolves absolute HTTPS URL unchanged', () {
      const url = 'https://sevo.co.in/media/categories/ac.png';
      expect(ImageUrlHelper.resolve(url), equals(url));
    });

    test('upgrades insecure HTTP URL to HTTPS', () {
      const url = 'http://sevo.co.in/media/services/pipe.png';
      expect(
        ImageUrlHelper.resolve(url),
        equals('https://sevo.co.in/media/services/pipe.png'),
      );
    });

    test('resolves relative path starting with slash', () {
      const path = '/mockups/category_appliance.png';
      expect(
        ImageUrlHelper.resolve(path),
        equals('https://sevo.co.in/mockups/category_appliance.png'),
      );
    });

    test('resolves relative path without leading slash', () {
      const path = 'media/services/sample.png';
      expect(
        ImageUrlHelper.resolve(path),
        equals('https://sevo.co.in/media/services/sample.png'),
      );
    });

    test('rewrites legacy localhost /media/ path to production domain', () {
      const legacy = 'http://localhost:8000/media/categories/electrician.png';
      expect(
        ImageUrlHelper.resolve(legacy),
        equals('https://sevo.co.in/media/categories/electrician.png'),
      );
    });

    test('rewrites legacy 127.0.0.1 /mockups/ path to production domain', () {
      const legacy = 'http://127.0.0.1:8000/mockups/service_truck.png';
      expect(
        ImageUrlHelper.resolve(legacy),
        equals('https://sevo.co.in/mockups/service_truck.png'),
      );
    });

    test('returns null for null, empty, or whitespace-only inputs', () {
      expect(ImageUrlHelper.resolve(null), isNull);
      expect(ImageUrlHelper.resolve(''), isNull);
      expect(ImageUrlHelper.resolve('   '), isNull);
    });
  });

  // Note: the "ImageUrlHelper.resolveLocalAssetFallback() Tests" group was
  // removed along with the Tier-2 local-asset-fallback method itself — the
  // bundled asset folders it pointed at were empty so it could never
  // actually resolve anything real, and it was deleted as dead code.
}
