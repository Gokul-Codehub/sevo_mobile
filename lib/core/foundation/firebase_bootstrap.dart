import 'dart:async';

import 'package:firebase_core/firebase_core.dart';

/// Starts Firebase exactly once, shared by crash reporting and push. Never throws and never blocks
/// the app: a failure (no config file, no Play services, no network on first start) just means the
/// Firebase features stay off.
abstract final class FirebaseBootstrap {
  FirebaseBootstrap._();

  static Future<bool>? _ready;

  static Future<bool> ensure() => _ready ??= _start();

  static Future<bool> _start() async {
    try {
      if (Firebase.apps.isEmpty) {
        // Android reads google-services.json through the Gradle plugin, so no options are needed.
        await Firebase.initializeApp().timeout(const Duration(seconds: 6));
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Tests: forget the memoised result.
  static void resetForTest() => _ready = null;
}
