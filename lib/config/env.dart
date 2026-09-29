/// Environment configuration for CalServices Customer app.
///
/// IMPORTANT: These are the authoritative production URLs.
/// Never use localhost, 127.0.0.1, or the legacy /Caltrack configuration.
library;

class Env {
  Env._();

  // ── Production Media / Assets base origin ──
  // NOTE: ApiClient builds every API request from [mediaBaseUrl] + '/api/<path>'
  // (see ApiClient._normalizePath). This is the ONLY base URL actually used
  // for network calls. A previous `apiBaseUrl` constant duplicating this
  // value was removed (2026-08-26) because it was never referenced by
  // ApiClient and only invited the two to drift out of sync.
  // Updated 2026-09-23 per explicit request ("the base URL for customer
  // has been updated into 'sevo.co.in'") — this app's own custom domain,
  // replacing the earlier customer.caldimservices.online. Every API call
  // (ApiClient._normalizePath) and every image/media URL this app resolves
  // relatively (ImageUrlHelper) picks this up automatically since both
  // read only this constant — nothing else needed to change to move the
  // whole app's traffic to the new domain.
  // Switched 2026-09-25 to the CalServices backend running LOCALLY on the
  // same LAN as the vendor backend (see [groceryHubBaseUrl]'s doc comment)
  // -- the live sevo.co.in server can't reach a private LAN address, so
  // testing the Seller Hub Marketplace proxy (marketplace_catalog_repository
  // .dart) end-to-end requires BOTH backends running locally together.
  // This affects EVERY API call the app makes (auth, booking, addresses,
  // everything) -- revert to the commented production line below once the
  // real vendor.sevo.co.in deploy is current.
  static const String mediaBaseUrl =
      'https://sevo.co.in';
    //   'http://192.168.102.116:8000';
      // 'https://127.0.0.1:8000';


  // ── Vendor Grocery Hub base origin ──
  // Added 2026-09-19, confirmed directly by the user ("i actually working
  // in the following url 'vendor.caldimservices.online'") after the
  // Grocery Hub integration guide's own doc left production as an
  // unspecified "<API_DOMAIN>" placeholder. This is a DIFFERENT host from
  // [mediaBaseUrl] above — the vendor/seller backend, not the customer
  // backend — so grocery_hub_repository.dart builds full absolute URLs
  // against this instead of going through [ApiClient]'s normal
  // mediaBaseUrl-relative path helper. Any relative `/media/...` image
  // path this backend returns must also be resolved against THIS host,
  // never [mediaBaseUrl] — see GroceryHubProduct.fromJson.
  // Updated 2026-09-23 per explicit request ("a vendor base url has been
  // changed too... 'https://vendor.sevo.co.in/api'") — same domain move as
  // [mediaBaseUrl], applied to the vendor host. Kept as a bare origin (no
  // trailing /api) since every call site here already appends '/api/...'
  // itself — see grocery_hub_repository.dart lines using
  // '${Env.groceryHubBaseUrl}/api/...' — so the shape is unchanged, only
  // the host moved.
  // Updated 2026-09-25: pointed at the vendor backend running LOCALLY on
  // the developer's own LAN (192.168.102.116:8001) instead of
  // vendor.sevo.co.in, because the updated vendor code wasn't deployed to
  // that production host yet. Reverted 2026-09-25 (same day) once the real
  // deploy went live — back to the production host, trailing slash still
  // intentionally omitted since every call site appends its own leading
  // '/api/...' (see the doc comment above).
  static const String groceryHubBaseUrl =
      'https://vendor.sevo.co.in';
      // 'http://192.168.102.116:8001';

  // ── Production WebSocket base (authoritative per Handover Bible §3) ──
  // Updated 2026-09-23 alongside [mediaBaseUrl] — same domain move.
  // Switched 2026-09-25 alongside [mediaBaseUrl] to match the local
  // CalServices instance -- revert together with it.
  static const String wsBaseUrl =
      'wss://sevo.co.in/ws';
    //   'ws://192.168.102.116:8000/ws';

  // ── WebSocket channel paths ──
  /// Tracking channel: append `/{identifier}/?token=<tracking_token>`
  static const String wsTrackingPath = '/ws/tracking';

  /// OTP fast-lane channel
  static const String wsOtpPath = '/ws/auth/otp/';

  // ── App metadata ──
  static const String appName = 'SEVO';
  static const String appVersion = '1.0.0';

  // ── Payment Gateway ──
  static const String defaultRazorpayKeyId = 'rzp_live_caldimservices';

  // ── Official Legal & Policy URLs ──
  static const String privacyPolicyUrl = 'https://sevo.co.in/privacy/sevo/';
  static const String accountDeletionUrl = 'https://sevo.co.in/account-deletion/';

  // ── Token storage keys ──
  static const String keyAccessToken = 'cal_access_token';
  static const String keyRefreshToken = 'cal_refresh_token';
  static const String keyUserJson = 'cal_user_json';
}
