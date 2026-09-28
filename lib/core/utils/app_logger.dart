import 'package:flutter/foundation.dart';

/// Centralized debug-only logger.
///
/// Replaces bare `print()` calls that previously ran unconditionally in
/// release builds (including phone numbers, cart contents, and other
/// internal state). `AppLogger.d` is a no-op outside debug builds, so
/// nothing it logs ever reaches a release-mode device log.
///
/// Usage: `AppLogger.d('[P0-CART]', 'CART_ADD: serviceId=$id');`
abstract final class AppLogger {
  AppLogger._();

  static void d(String tag, String message) {
    if (kDebugMode) {
      debugPrint('$tag $message');
    }
  }
}
