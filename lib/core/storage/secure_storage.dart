import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../config/env.dart';
import '../utils/app_logger.dart';

/// Secure token storage backed by Android Keystore.
///
/// SECURITY RULE: This is the ONLY place tokens may be stored.
/// Never use SharedPreferences, Hive (unencrypted), or plain files for tokens.
class SecureStorage {
  SecureStorage() : _storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(
      encryptedSharedPreferences: true,
    ),
  );

  final FlutterSecureStorage _storage;

  // Fixed 2026-09-16 — root cause of "logged out every time the app is
  // closed and reopened": `FlutterSecureStorage.read()` on Android's
  // `encryptedSharedPreferences` backend can throw (a wrapped
  // `PlatformException`/`GeneralSecurityException`) instead of returning
  // null on a transient keystore hiccup — a documented failure mode of
  // that plugin, not something this app's code causes. Before this fix,
  // that exception propagated straight out of getAccessToken() into
  // AuthRepository.restoreSession(), which then unconditionally called
  // storage.clearAll() the instant hasAccessToken() came back false/threw
  // — permanently destroying the still-good refresh token and cached user
  // on what may have been a one-off read glitch, guaranteeing every next
  // app open needed a fresh OTP login. Every read below now fails soft
  // (returns null, logs it) instead of throwing, so a single bad read is
  // never treated as "this device was logged out."
  Future<String?> _readSafe(String key) async {
    try {
      return await _storage.read(key: key);
    } catch (e) {
      AppLogger.d('[P0-AUTH]', 'SECURE_STORAGE: read($key) failed transiently: $e');
      return null;
    }
  }

  // ── Access token ──────────────────────────────────────────────────────────
  Future<String?> getAccessToken() => _readSafe(Env.keyAccessToken);

  Future<void> setAccessToken(String token) =>
      _storage.write(key: Env.keyAccessToken, value: token);

  // ── Refresh token ─────────────────────────────────────────────────────────
  Future<String?> getRefreshToken() => _readSafe(Env.keyRefreshToken);

  Future<void> setRefreshToken(String token) =>
      _storage.write(key: Env.keyRefreshToken, value: token);

  // ── User JSON ─────────────────────────────────────────────────────────────
  Future<String?> getUserJson() => _readSafe(Env.keyUserJson);

  Future<void> setUserJson(String json) =>
      _storage.write(key: Env.keyUserJson, value: json);

  // ── Cart Storage (Persistent Offline Basket) ──────────────────────────────
  Future<String?> getCartJson() =>
      _storage.read(key: 'calservices_persistent_cart');

  Future<void> setCartJson(String json) =>
      _storage.write(key: 'calservices_persistent_cart', value: json);

  Future<void> clearCartStorage() =>
      _storage.delete(key: 'calservices_persistent_cart');

  // ── Selected Address Storage ──────────────────────────────────────────────
  Future<String?> getSelectedAddressJson() =>
      _storage.read(key: 'calservices_selected_address');

  Future<void> setSelectedAddressJson(String json) =>
      _storage.write(key: 'calservices_selected_address', value: json);

  Future<void> clearSelectedAddress() =>
      _storage.delete(key: 'calservices_selected_address');

  // ── Onboarding seen flag ───────────────────────────────────────────────────
  // Added 2026-09-19 — root cause of "onboarding pages don't do anything":
  // SplashScreen unconditionally routed straight to Home on every cold
  // start regardless of first-launch state, so OnboardingScreen and
  // LocationAccessScreen (both fully built, both registered routes) were
  // never once reachable in the app's real user journey. Not sensitive
  // data — stored here anyway rather than adding a whole new
  // (shared_preferences) dependency for one boolean, matching how
  // cart/selected-address already share this same storage for
  // non-secret state.
  Future<bool> hasSeenOnboarding() async {
    final value = await _readSafe('calservices_onboarding_seen');
    return value == 'true';
  }

  Future<void> setOnboardingSeen() =>
      _storage.write(key: 'calservices_onboarding_seen', value: 'true');

  // ── Grocery Hub guest cart id ──────────────────────────────────────────────
  // Added 2026-09-19: the separate Vendor Grocery Hub backend's public cart
  // API (`/api/workforce/public/cart/`) is keyed by an opaque `customer_id`
  // string, not a real account — a guest browsing this new section still
  // needs a stable id so their cart survives navigating between screens
  // (and app restarts) even before signing in. Not sensitive, same
  // reasoning as the onboarding-seen flag above: reusing this existing
  // storage for one small string beats adding a whole new dependency.
  Future<String> getOrCreateGroceryHubGuestId() async {
    final existing = await _readSafe('grocery_hub_guest_id');
    if (existing != null && existing.isNotEmpty) return existing;
    final generated =
        'guest_${DateTime.now().microsecondsSinceEpoch}_${(1000 + (DateTime.now().microsecond % 9000))}';
    await _storage.write(key: 'grocery_hub_guest_id', value: generated);
    return generated;
  }

  // ── Clear all (logout) ────────────────────────────────────────────────────
  Future<void> clearAll() async {
    await _storage.delete(key: Env.keyAccessToken);
    await _storage.delete(key: Env.keyRefreshToken);
    await _storage.delete(key: Env.keyUserJson);
  }

  // ── Has active session ────────────────────────────────────────────────────
  Future<bool> hasAccessToken() async {
    final token = await getAccessToken();
    return token != null && token.isNotEmpty;
  }
}

// ── Provider ─────────────────────────────────────────────────────────────────
final secureStorageProvider = Provider<SecureStorage>((_) => SecureStorage());
