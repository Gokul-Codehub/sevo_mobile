import 'package:flutter/foundation.dart' show TargetPlatform, defaultTargetPlatform, kIsWeb;

/// Which app store this install updates from. Android: Google Play. iOS: the App Store (no in-app update
/// API there, so the update screens send the customer to the store page).
abstract final class StoreInfo {
  StoreInfo._();

  static bool get isIos => !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  /// "Play Store" / "App Store" - for button labels and sentences.
  static String get shortName => isIos ? 'App Store' : 'Play Store';

  /// "Google Play" / "the App Store".
  static String get longName => isIos ? 'the App Store' : 'Google Play';

  /// Store page to open when the admin configured none. Only Android can derive it from the package id;
  /// on iOS the configured `store_url` (https://apps.apple.com/...) is required.
  static Uri? fallbackUrl(String packageName) =>
      isIos ? null : Uri.parse('https://play.google.com/store/apps/details?id=$packageName');
}
