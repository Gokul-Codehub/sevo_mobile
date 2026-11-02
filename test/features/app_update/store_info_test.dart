import 'package:calservices_customer/features/app_update/domain/store_info.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  test('Android: Google Play wording, and a Play URL can be derived from the package id', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    expect(StoreInfo.isIos, isFalse);
    expect(StoreInfo.shortName, 'Play Store');
    expect(StoreInfo.longName, 'Google Play');
    expect(StoreInfo.fallbackUrl('com.caldim.sevo_customer').toString(), 'https://play.google.com/store/apps/details?id=com.caldim.sevo_customer');
  });

  test('iOS: App Store wording, and no Play URL is ever invented (the configured store link is required)', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    expect(StoreInfo.isIos, isTrue);
    expect(StoreInfo.shortName, 'App Store');
    expect(StoreInfo.longName, 'the App Store');
    expect(StoreInfo.fallbackUrl('com.caldim.sevo_customer'), isNull);
  });
}
